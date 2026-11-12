--!strict
-- FactionConfig: единый источник данных о фракциях.
-- Используется и клиентом (меню), и в будущем сервером (спавн, бонусы фракций).

export type Faction = {
	id: string, -- внутренний идентификатор
	displayName: string, -- название на кнопке
	description: string, -- подпись под названием
	platformName: string, -- имя Part в Workspace.Platforms
	fallbackPosition: Vector3, -- куда телепортировать, если платформы нет
	buttonColor: Color3, -- основной цвет кнопки
	accentColor: Color3, -- цвет обводки
}

local FactionConfig = {}

-- Порядок в массиве = порядок кнопок в меню.
FactionConfig.List = {
	{
		id = "Rome",
		displayName = "Рим",
		description = "Легионы, акведуки и форумы",
		platformName = "RomePlatform",
		fallbackPosition = Vector3.new(-200, 5, 0),
		buttonColor = Color3.fromRGB(140, 30, 35),
		accentColor = Color3.fromRGB(220, 180, 90),
	},
	{
		id = "Greece",
		displayName = "Греция",
		description = "Полисы, философы и мраморные храмы",
		platformName = "GreecePlatform",
		fallbackPosition = Vector3.new(0, 5, -200),
		buttonColor = Color3.fromRGB(35, 75, 140),
		accentColor = Color3.fromRGB(235, 235, 225),
	},
	{
		id = "Egypt",
		displayName = "Египет",
		description = "Пирамиды, Нил и пески пустыни",
		platformName = "EgyptPlatform",
		fallbackPosition = Vector3.new(200, 5, 0),
		buttonColor = Color3.fromRGB(190, 140, 50),
		accentColor = Color3.fromRGB(40, 110, 120),
	},
} :: { Faction }

-- Быстрый поиск по id: FactionConfig.ById.Rome
FactionConfig.ById = {} :: { [string]: Faction }
for _, faction in FactionConfig.List do
	FactionConfig.ById[faction.id] = faction
end

return FactionConfig
