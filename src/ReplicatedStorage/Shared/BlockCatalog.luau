--!strict
-- BlockCatalog: список форм для панели «Блоки» (названия, подписи, категории).
-- Размеры — в BuildConfig.Shapes, геометрия составных блоков — в BlockLibrary.
-- Чтобы добавить новый блок: размер в BuildConfig.Shapes, строитель в BlockLibrary, строка здесь.

export type Category = {
	id: string,
	label: string,
}

export type Entry = {
	id: string, -- ключ BuildConfig.Shapes
	displayName: string,
	description: string,
	category: string,
	featured: { string }?, -- фракции, для которых блок «родной» (звёздочка в каталоге)
}

local BlockCatalog = {}

BlockCatalog.AllCategoryId = "All"

-- Вкладки каталога (в порядке показа). Первая — «Все».
BlockCatalog.Categories = {
	{ id = "All", label = "Все" },
	{ id = "Basic", label = "Базовые" },
	{ id = "Ornate", label = "Резные" },
	{ id = "Columns", label = "Колонны" },
	{ id = "Arches", label = "Арки" },
	{ id = "Stairs", label = "Ступени" },
	{ id = "Roofs", label = "Крыши" },
	{ id = "Decor", label = "Декор" },
} :: { Category }

BlockCatalog.List = {
	-- Базовые (один Part, работают и как форма резака)
	{ id = "Block", displayName = "Блок", description = "Куб 4×4×4", category = "Basic" },
	{ id = "Wall", displayName = "Стена", description = "16×12×4", category = "Basic" },
	{ id = "Column", displayName = "Опора", description = "Простая колонна", category = "Basic" },
	{ id = "Slab", displayName = "Плита", description = "Полы и перекрытия", category = "Basic" },

	-- Резные: составные варианты базовых блоков с отделкой
	{
		id = "OrnateRoad",
		displayName = "Дорога (Брусчатка)",
		description = "Камни и бордюры 8×1×8",
		category = "Ornate",
	},
	{
		id = "OrnateWall",
		displayName = "Резная стена",
		description = "Панели и пояса 12×8×4",
		category = "Ornate",
	},
	{
		id = "OrnateCube",
		displayName = "Орнаментный блок",
		description = "Столбики и вставки 4×4×4",
		category = "Ornate",
	},

	-- Колонны
	{
		id = "CarvedColumn",
		displayName = "Резная колонна",
		description = "База, рифлёный ствол, капитель",
		category = "Columns",
		featured = { "Rome", "Greece", "Egypt" },
	},
	{
		id = "CarvedColumnShort",
		displayName = "Малая колонна",
		description = "Портики и галереи",
		category = "Columns",
	},

	-- Арки
	{
		id = "Arch",
		displayName = "Античная арка",
		description = "Полукруглый свод, замковый камень",
		category = "Arches",
		featured = { "Rome" },
	},
	{
		id = "ArchStepped",
		displayName = "Ступенчатая арка",
		description = "Ложный свод из рядов камня",
		category = "Arches",
		featured = { "Egypt", "Greece" },
	},

	-- Ступени
	{ id = "Stairs", displayName = "Лестница", description = "4 ступени с кантом", category = "Stairs" },
	{ id = "Ramp", displayName = "Пандус", description = "Плавный подъём", category = "Stairs" },
	{
		id = "Crepidoma",
		displayName = "Подиум храма",
		description = "Трёхступенчатое основание",
		category = "Stairs",
		featured = { "Greece", "Rome" },
	},

	-- Пирамиды и крыши
	{
		id = "Pyramid",
		displayName = "Пирамида",
		description = "Золотое навершие",
		category = "Roofs",
		featured = { "Egypt" },
	},
	{
		id = "StepPyramid",
		displayName = "Ступенчатая пирамида",
		description = "Четыре яруса",
		category = "Roofs",
		featured = { "Egypt" },
	},
	{
		id = "GableRoof",
		displayName = "Фронтон",
		description = "Двускатная крыша храма",
		category = "Roofs",
		featured = { "Greece", "Rome" },
	},
	{ id = "RoofSlope", displayName = "Скат", description = "Клин 8×4×4", category = "Roofs" },
	{ id = "RoofCorner", displayName = "Угол ската", description = "Угловой клин 4×4×4", category = "Roofs" },

	-- Декор
	{
		id = "Altar",
		displayName = "Алтарь",
		description = "Золотая окантовка",
		category = "Decor",
		featured = { "Greece" },
	},
	{
		id = "Pedestal",
		displayName = "Пьедестал",
		description = "Для статуй и чаш",
		category = "Decor",
		featured = { "Rome" },
	},
	{
		id = "Obelisk",
		displayName = "Обелиск",
		description = "Золотой пирамидион",
		category = "Decor",
		featured = { "Egypt" },
	},
} :: { Entry }

BlockCatalog.ById = {} :: { [string]: Entry }
for _, entry in BlockCatalog.List do
	BlockCatalog.ById[entry.id] = entry
end

function BlockCatalog.displayName(shapeId: string?): string
	local entry = if shapeId then BlockCatalog.ById[shapeId] else nil
	return if entry then entry.displayName else (shapeId or "")
end

function BlockCatalog.isFeatured(entry: Entry, factionId: string?): boolean
	if not factionId or not entry.featured then
		return false
	end
	return table.find(entry.featured, factionId) ~= nil
end

return BlockCatalog
