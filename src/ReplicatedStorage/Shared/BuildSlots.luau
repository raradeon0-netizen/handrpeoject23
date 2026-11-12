--!strict
-- BuildSlots: единый источник данных о слотах строительной панели.
-- Как и FactionConfig, лежит в Shared: клиент (BuildController) и сервер ссылаются
-- на одни и те же id слотов. Сами формы теперь выбираются в каталоге «Блоки»
-- (BlockCatalog), а на панели остаются кнопка каталога и инструменты.

export type Slot = {
	id: string, -- внутренний идентификатор
	displayName: string, -- название на кнопке
	description: string, -- подпись под названием
	kind: "Catalog" | "Tool", -- кнопка каталога форм или инструмент (стоит отдельно справа)
	wide: boolean?, -- широкая кнопка (для длинного названия)
}

local BuildSlots = {}

-- Порядок в массиве = порядок кнопок на панели слева направо.
BuildSlots.List = {
	{ id = "Blocks", displayName = "Блоки", description = "Каталог · B", kind = "Catalog", wide = true },
	{ id = "Carve", displayName = "Вырезать", description = "Проёмы и окна", kind = "Tool" },
	{ id = "Move", displayName = "Двигать", description = "Стрелки X / Y / Z", kind = "Tool" },
	{ id = "Delete", displayName = "Снос", description = "ЛКМ или X", kind = "Tool" },
	{ id = "Paint", displayName = "Покраска / Скрижали", description = "Скоро", kind = "Tool", wide = true },
} :: { Slot }

-- Быстрый поиск по id: BuildSlots.ById.Carve
BuildSlots.ById = {} :: { [string]: Slot }
for _, slot in BuildSlots.List do
	BuildSlots.ById[slot.id] = slot
end

return BuildSlots
