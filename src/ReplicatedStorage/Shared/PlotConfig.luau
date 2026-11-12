--!strict
-- PlotConfig: все настройки персональных строительных участков (Plot).
-- Лежит в ReplicatedStorage.Shared, чтобы и сервер, и клиент (меню, будущая
-- система строительства, подсказки) брали числа из одного места.

export type PlotStyle = {
	material: Enum.Material, -- материал поверхности участка
	color: Color3, -- цвет поверхности участка
	borderMaterial: Enum.Material, -- материал бордюра по краю
	borderColor: Color3, -- цвет бордюра
	cornerKind: "Column" | "Block", -- что стоит по углам: колонна или массивный блок
	cornerMaterial: Enum.Material, -- материал угловых элементов
	cornerColor: Color3, -- цвет угловых элементов
	capColor: Color3?, -- цвет «шапки» углового блока (только для Block)
}

local PlotConfig = {}

-- Имя RemoteFunction, через которую меню сообщает серверу о выбранной фракции.
-- Сервер создаёт её сам при старте (см. PlotService).
PlotConfig.RemoteName = "SelectFaction"

-- Размер участка: 200x200 studs, толщина 2 (как у платформ в Workspace.Platforms).
PlotConfig.PlotSize = 200
PlotConfig.PlotThickness = 2

-- Сетка участков. Начало сетки далеко от лобби (0,0,0) и от стартовых платформ
-- (±200). Шаг 400 при размере 200 даёт 200 studs пустоты между соседями.
PlotConfig.GridOrigin = Vector3.new(1000, 1, 1000) -- центр участка №0 (верх участка на Y = 2)
PlotConfig.GridSpacing = 400
PlotConfig.GridColumns = 10 -- сколько участков в ряду

-- Максимальная высота постройки над поверхностью участка (для проверки прав).
PlotConfig.BuildHeight = 300

-- Имя папки в Workspace, где живут все участки.
PlotConfig.FolderName = "Plots"

-- Бордюр по краям: ширина (внутрь участка) и высота над поверхностью.
PlotConfig.BorderWidth = 4
PlotConfig.BorderHeight = 3

-- Угловые элементы (колонны/блоки): сторона основания и общая высота.
PlotConfig.CornerBaseSize = 8
PlotConfig.CornerHeight = 20

-- Строительная сетка: стандартная текстура сетки из шаблона Baseplate.
-- Хотите другой шаг сетки: меняйте StudsPerTile (или Texture на свой ассет).
PlotConfig.GridTexture = "rbxassetid://6372755229"
PlotConfig.GridStudsPerTile = 4
PlotConfig.GridTransparency = 0.85 -- чем ближе к 1, тем незаметнее сетка
PlotConfig.GridColor = Color3.fromRGB(0, 0, 0)

-- Имена атрибутов, которыми помечается Part участка.
PlotConfig.Attributes = {
	OwnerUserId = "OwnerUserId",
	FactionId = "FactionId",
	SlotIndex = "SlotIndex",
}

-- Внешний вид участка по id фракции из FactionConfig.
PlotConfig.Styles = {
	-- Египет: песок, золотой бордюр и массивные песчаные блоки с золотыми шапками по углам.
	Egypt = {
		material = Enum.Material.Sand,
		color = Color3.fromRGB(226, 189, 121),
		borderMaterial = Enum.Material.Metal,
		borderColor = Color3.fromRGB(212, 175, 55),
		cornerKind = "Block",
		cornerMaterial = Enum.Material.Sand,
		cornerColor = Color3.fromRGB(205, 165, 100),
		capColor = Color3.fromRGB(212, 175, 55),
	},
	-- Рим: белый/серый мрамор, серый бордюр форума, белые колонны по углам.
	Rome = {
		material = Enum.Material.Marble,
		color = Color3.fromRGB(196, 198, 204),
		borderMaterial = Enum.Material.Marble,
		borderColor = Color3.fromRGB(150, 152, 160),
		cornerKind = "Column",
		cornerMaterial = Enum.Material.Marble,
		cornerColor = Color3.fromRGB(232, 232, 236),
	},
	-- Греция: светло-бежевый мрамор, тёплые колонны по углам.
	Greece = {
		material = Enum.Material.Marble,
		color = Color3.fromRGB(238, 226, 198),
		borderMaterial = Enum.Material.Marble,
		borderColor = Color3.fromRGB(214, 198, 164),
		cornerKind = "Column",
		cornerMaterial = Enum.Material.Marble,
		cornerColor = Color3.fromRGB(248, 240, 222),
	},
} :: { [string]: PlotStyle }

-- Запасной стиль на случай новой фракции, для которой стиль ещё не описан.
PlotConfig.DefaultStyle = {
	material = Enum.Material.SmoothPlastic,
	color = Color3.fromRGB(180, 180, 180),
	borderMaterial = Enum.Material.SmoothPlastic,
	borderColor = Color3.fromRGB(120, 120, 120),
	cornerKind = "Block",
	cornerMaterial = Enum.Material.SmoothPlastic,
	cornerColor = Color3.fromRGB(150, 150, 150),
} :: PlotStyle

return PlotConfig
