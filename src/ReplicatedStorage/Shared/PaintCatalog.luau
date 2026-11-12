--!strict
-- PaintCatalog: единый источник данных меню «Покраска / Скрижали».
-- Клиент рисует по нему образцы и карточки, сервер по id находит материал или текст скрижали.

export type Material = {
	id: string,
	displayName: string,
	material: Enum.Material,
	color: Color3,
	reflectance: number,
}

export type TabletStyle = "Stone" | "DarkStone"

export type Tablet = {
	id: string,
	title: string,
	factionId: string, -- «родная» фракция (скрижали доступны всем, своя отмечается ★)
	factionName: string,
	style: TabletStyle,
	text: string,
}

local PaintCatalog = {}

PaintCatalog.Materials = {
	{
		id = "Gold",
		displayName = "Золото",
		material = Enum.Material.Foil,
		color = Color3.fromRGB(212, 175, 55),
		reflectance = 0.2,
	},
	{
		id = "Lapis",
		displayName = "Лазурит",
		material = Enum.Material.Marble,
		color = Color3.fromRGB(34, 76, 164),
		reflectance = 0.05,
	},
	{
		id = "Marble",
		displayName = "Мрамор",
		material = Enum.Material.Marble,
		color = Color3.fromRGB(240, 238, 232),
		reflectance = 0,
	},
	{
		id = "Sandstone",
		displayName = "Песчаник",
		material = Enum.Material.Sandstone,
		color = Color3.fromRGB(214, 180, 120),
		reflectance = 0,
	},
	{
		id = "Obsidian",
		displayName = "Обсидиан",
		material = Enum.Material.Slate,
		color = Color3.fromRGB(24, 22, 30),
		reflectance = 0.18,
	},
	{
		id = "Bronze",
		displayName = "Бронза",
		material = Enum.Material.Metal,
		color = Color3.fromRGB(176, 114, 54),
		reflectance = 0.1,
	},
} :: { Material }

PaintCatalog.Tablets = {
	{
		id = "Tutankhamun",
		title = "Захоронение Тутанхамона",
		factionId = "Egypt",
		factionName = "Египет",
		style = "DarkStone",
		text = "Тутанхамон был славным правителем, считался одним из лучших богов. "
			.. "Жаль, он нас покинул и не освятил нашу пирамиду, вот и захоронился в ней...",
	},
	{
		id = "Caesar",
		title = "Дух Цезаря",
		factionId = "Rome",
		factionName = "Рим",
		style = "Stone",
		text = "Был один бог Цезарь, прославил и отдал половину духа в Колизей. "
			.. "Вот Цезарь любил народ, восхищался Колизеем, и проживет тот 1000 лет. "
			.. "Но к сожалению, бог не вечный — предал нашу душу брат его честной...",
	},
	{
		id = "Olympus",
		title = "Пророчество Олимпа",
		factionId = "Greece",
		factionName = "Греция",
		style = "Stone",
		text = "Боги спустились с Олимпа и велели воздвигнуть этот храм. "
			.. "Коли колонны коснутся облаков, Зевс благословит народ, "
			.. "а коли дрогнут — пошлет грозу на земли наши...",
	},
} :: { Tablet }

PaintCatalog.MaterialById = {} :: { [string]: Material }
for _, material in PaintCatalog.Materials do
	PaintCatalog.MaterialById[material.id] = material
end

PaintCatalog.TabletById = {} :: { [string]: Tablet }
for _, tablet in PaintCatalog.Tablets do
	PaintCatalog.TabletById[tablet.id] = tablet
end

return PaintCatalog
