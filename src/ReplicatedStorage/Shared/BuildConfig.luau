--!strict
-- BuildConfig: все настройки строительного редактора (Placement System).
-- Лежит в ReplicatedStorage.Shared: клиент (призрак, панель «Точность») и сервер
-- (проверка, спавн, вырезание) берут формы, шаги сетки/поворота и материалы из одного места.

export type Shape = {
	id: string, -- совпадает с id в BlockCatalog
	size: Vector3, -- габарит без поворота (X = длина, Y = высота, Z = толщина)
	prefab: boolean?, -- true = составная модель из BlockLibrary (резаком не используется)
}

export type FactionMaterial = {
	material: Enum.Material,
	color: Color3,
}

-- Палитра составных блоков: материал для каждой роли детали (см. BlockLibrary).
export type Palette = {
	Main: FactionMaterial, -- основной камень
	Trim: FactionMaterial, -- окантовка, базы, карнизы
	Accent: FactionMaterial, -- золото / бронза
	Detail: FactionMaterial, -- цветные вставки
}

export type GridOption = {
	step: number, -- шаг сетки в студах; 0 = свободное перемещение без сетки
	label: string, -- надпись на кнопке панели
	hint: string, -- пояснение в заголовке секции
}

local BuildConfig = {}

-- Имена RemoteEvent'ов (их создаёт сервер в ReplicatedStorage.Shared, см. BuildService).
BuildConfig.PlaceRemoteName = "PlaceBlock"
BuildConfig.RemoveRemoteName = "RemoveBlock"
BuildConfig.CarveRemoteName = "CarveBlock"
BuildConfig.MoveRemoteName = "MoveBlock"
BuildConfig.NoticeRemoteName = "BuildNotice" -- сервер -> клиент: короткие сообщения для панели

-- Папки внутри Part участка. Лежат внутри участка, поэтому удаляются вместе с ним.
BuildConfig.BlocksFolderName = "Blocks" -- постройки игрока
BuildConfig.DecorFolderName = "Decor" -- бордюр и углы участка (см. PlotBuilder)

-- ===== Точность (переключается на панели «Точность» справа) =====

-- Шаг сетки. Сетка начинается от угла плиты, поэтому блоки ложатся ровно по её текстуре.
BuildConfig.GridOptions = {
	{ step = 4, label = "4", hint = "крупный" },
	{ step = 1, label = "1", hint = "средний" },
	{ step = 0.25, label = "0.25", hint = "ювелирный" },
	{ step = 0, label = "0", hint = "без сетки" },
} :: { GridOption }
BuildConfig.DefaultGridIndex = 1

-- Шаг поворота в градусах.
BuildConfig.RotationSteps = { 90, 45, 15, 5 } :: { number }
BuildConfig.DefaultRotationIndex = 1
-- Сервер принимает только углы, кратные этому значению (наименьший шаг из списка выше).
BuildConfig.MinRotationStep = 5

-- Отступ от края плиты 200x200, внутри которого строить нельзя (там бордюр).
-- Поставьте 0, если хотите строить вплотную к краю.
BuildConfig.EdgeInset = 4

-- Id слотов-инструментов на нижней панели (см. BuildSlots).
BuildConfig.CarveSlotId = "Carve"
BuildConfig.DeleteSlotId = "Delete"
BuildConfig.MoveSlotId = "Move" -- перенос блока 3D-стрелками
BuildConfig.CatalogSlotId = "Blocks" -- кнопка «Блоки»: открывает каталог форм

-- Горячие клавиши редактора (ПКМ не используется — она только вращает камеру).
BuildConfig.Keys = {
	RotateY = Enum.KeyCode.R, -- вращение вокруг вертикальной оси Y
	TiltX = Enum.KeyCode.T, -- наклон вперёд/назад (ось X)
	TiltZ = Enum.KeyCode.Y, -- наклон вбок (ось Z)
	QuickDelete = Enum.KeyCode.X, -- удалить свой блок под курсором
	OpenCatalog = Enum.KeyCode.B, -- открыть/закрыть каталог блоков
}

-- Защита сервера от спама и лимиты.
BuildConfig.PlaceCooldown = 0.08 -- секунд между установками
BuildConfig.RemoveCooldown = 0.05 -- секунд между удалениями
BuildConfig.CarveCooldown = 0.35 -- CSG — дорогая операция
BuildConfig.MaxBlocksPerPlayer = 2000
BuildConfig.MaxCarveTargets = 8 -- сколько блоков максимум прорезает один клик
BuildConfig.MoveCooldown = 0.1 -- секунд между переносами

-- Пользовательский размер базовых блоков и резака (панель «Точность»).
BuildConfig.MinBlockSize = 0.25
BuildConfig.MaxBlockSize = 64
BuildConfig.FreeSizeStep = 0.05 -- шаг кнопок −/+ при сетке «0»

-- Формы резака: «куб» — выбранная базовая форма, «полоса» — тонкая пластина.
BuildConfig.BladeThickness = 0.2
BuildConfig.BladeDefaultSize = Vector3.new(8, 8, BuildConfig.BladeThickness)
BuildConfig.CutterCubeId = "Cube"
BuildConfig.CutterBladeId = "Blade"
BuildConfig.CutterShapes = {
	{ id = BuildConfig.CutterCubeId, label = "Куб" },
	{ id = BuildConfig.CutterBladeId, label = "Полоса / Лезвие" },
} :: { { id: string, label: string } }

-- Допуски.
BuildConfig.OverlapTolerance = 0.02 -- касание гранями не считается пересечением
BuildConfig.CutterInflate = 0.02 -- резак чуть больше призрака: без «плёнок» на совпадающих гранях

-- Формы для постройки. Ключи = id из BlockCatalog.
-- Базовые формы — один Part (их же использует резак). Составные (prefab = true) —
-- модели из нескольких деталей, геометрия в BlockLibrary; size = их габаритная коробка,
-- по ней работают сетка, поворот и прилипание к граням.
BuildConfig.Shapes = {
	-- Базовые
	Block = { id = "Block", size = Vector3.new(4, 4, 4) }, -- простой куб
	Wall = { id = "Wall", size = Vector3.new(16, 12, 4) }, -- длинная стена
	Column = { id = "Column", size = Vector3.new(4, 16, 4) }, -- высокая опора
	Slab = { id = "Slab", size = Vector3.new(12, 2, 12) }, -- плита пола/перекрытия

	-- Колонны
	CarvedColumn = { id = "CarvedColumn", size = Vector3.new(4, 16, 4), prefab = true },
	CarvedColumnShort = { id = "CarvedColumnShort", size = Vector3.new(4, 8, 4), prefab = true },
	-- Арки
	Arch = { id = "Arch", size = Vector3.new(12, 12, 4), prefab = true },
	ArchStepped = { id = "ArchStepped", size = Vector3.new(12, 12, 4), prefab = true },
	-- Ступени
	Stairs = { id = "Stairs", size = Vector3.new(8, 4, 8), prefab = true },
	Ramp = { id = "Ramp", size = Vector3.new(8, 4, 8), prefab = true },
	Crepidoma = { id = "Crepidoma", size = Vector3.new(12, 3, 12), prefab = true },
	-- Пирамиды и крыши
	Pyramid = { id = "Pyramid", size = Vector3.new(12, 8, 12), prefab = true },
	StepPyramid = { id = "StepPyramid", size = Vector3.new(12, 8, 12), prefab = true },
	GableRoof = { id = "GableRoof", size = Vector3.new(12, 4, 8), prefab = true },
	RoofSlope = { id = "RoofSlope", size = Vector3.new(8, 4, 4), prefab = true },
	RoofCorner = { id = "RoofCorner", size = Vector3.new(4, 4, 4), prefab = true },
	-- Декор
	Altar = { id = "Altar", size = Vector3.new(8, 4, 4), prefab = true },
	Pedestal = { id = "Pedestal", size = Vector3.new(4, 6, 4), prefab = true },
	Obelisk = { id = "Obelisk", size = Vector3.new(4, 16, 4), prefab = true },
} :: { [string]: Shape }

-- Базовый материал блоков по фракции: песчаник для Египта, мрамор для Рима и Греции.
BuildConfig.FactionMaterials = {
	Egypt = { material = Enum.Material.Sandstone, color = Color3.fromRGB(214, 180, 120) },
	Rome = { material = Enum.Material.Marble, color = Color3.fromRGB(225, 225, 230) },
	Greece = { material = Enum.Material.Marble, color = Color3.fromRGB(242, 234, 214) },
} :: { [string]: FactionMaterial }

BuildConfig.DefaultMaterial = {
	material = Enum.Material.SmoothPlastic,
	color = Color3.fromRGB(200, 200, 200),
} :: FactionMaterial

local GOLD = { material = Enum.Material.Foil, color = Color3.fromRGB(212, 175, 55) } :: FactionMaterial

-- Палитры составных блоков по фракциям (Main = базовый материал фракции).
BuildConfig.FactionPalettes = {
	Egypt = {
		Main = BuildConfig.FactionMaterials.Egypt,
		Trim = { material = Enum.Material.Sandstone, color = Color3.fromRGB(184, 146, 92) }, -- тёмный песчаник
		Accent = GOLD,
		Detail = { material = Enum.Material.Marble, color = Color3.fromRGB(52, 150, 160) }, -- бирюза / фаянс
	},
	Rome = {
		Main = BuildConfig.FactionMaterials.Rome,
		Trim = { material = Enum.Material.Limestone, color = Color3.fromRGB(206, 196, 172) }, -- травертин
		Accent = GOLD,
		Detail = { material = Enum.Material.Marble, color = Color3.fromRGB(122, 40, 52) }, -- порфир
	},
	Greece = {
		Main = BuildConfig.FactionMaterials.Greece,
		Trim = { material = Enum.Material.Marble, color = Color3.fromRGB(250, 248, 240) }, -- белый мрамор
		Accent = GOLD,
		Detail = { material = Enum.Material.Marble, color = Color3.fromRGB(58, 92, 156) }, -- расписная синь
	},
} :: { [string]: Palette }

BuildConfig.DefaultPalette = {
	Main = BuildConfig.DefaultMaterial,
	Trim = { material = Enum.Material.SmoothPlastic, color = Color3.fromRGB(170, 170, 170) },
	Accent = GOLD,
	Detail = { material = Enum.Material.SmoothPlastic, color = Color3.fromRGB(90, 110, 150) },
} :: Palette

-- Цвета призрака.
BuildConfig.GhostValidColor = Color3.fromRGB(90, 230, 120) -- установка: можно ставить
BuildConfig.GhostInvalidColor = Color3.fromRGB(235, 75, 75) -- установка: нельзя
BuildConfig.CarveActiveColor = Color3.fromRGB(170, 90, 255) -- резак задевает блок: ЛКМ вырежет
BuildConfig.CarveIdleColor = Color3.fromRGB(255, 150, 40) -- резак ничего не задевает
BuildConfig.GhostTransparency = 0.55
BuildConfig.GhostFollowSpeed = 22 -- чем больше, тем быстрее призрак догоняет курсор

-- Подсветка блока под курсором в режиме «Снос».
BuildConfig.DeleteHighlightColor = Color3.fromRGB(255, 70, 70)

-- Режим «Двигать»: подсветка блока, цвет стрелок, ожидание ответа сервера.
BuildConfig.MoveHighlightColor = Color3.fromRGB(90, 170, 255)
BuildConfig.MoveHandlesColor = Color3.fromRGB(255, 200, 60)
BuildConfig.MovePendingTimeout = 1

-- Сколько секунд держится сообщение на панели «Точность».
BuildConfig.NoticeDuration = 3

-- Атрибуты на поставленных блоках (переносятся и на вырезанные блоки).
BuildConfig.Attributes = {
	OwnerUserId = "OwnerUserId",
	ShapeId = "ShapeId",
}

return BuildConfig
