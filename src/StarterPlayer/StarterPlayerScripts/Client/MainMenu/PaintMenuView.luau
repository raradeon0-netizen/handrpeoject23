--!strict
-- PaintMenuView: окно «Покраска / Скрижали» над строительной панелью.
-- Две вкладки: образцы материалов и карточки скрижалей (плюс «Очистить грань»).
-- Только создаёт GUI; выбор кисти и открытие/закрытие — в PaintMenuController.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PaintCatalog = require(ReplicatedStorage.Shared.PaintCatalog)
local Theme = require(script.Parent.Theme)
local UIFactory = require(script.Parent.UIFactory)

export type TabletTile = {
	button: TextButton,
	star: TextLabel, -- ★ скрижаль фракции игрока
}

export type View = {
	frame: Frame,
	closeButton: TextButton,
	tabButtons: { [string]: TextButton }, -- id вкладки -> кнопка
	pages: { [string]: Frame }, -- id вкладки -> страница
	materialTiles: { [string]: TextButton }, -- id материала -> образец
	tabletTiles: { [string]: TabletTile }, -- id скрижали -> карточка
	eraseButton: TextButton,
	hintLabel: TextLabel,
}

local MENU_SIZE = Vector2.new(680, 330)
local TAB_SIZE = Vector2.new(210, 30)
local SWATCH_TILE = Vector2.new(100, 104)
local TABLET_TILE = Vector2.new(210, 150)
local GAP = 8
local PAGE_TOP = 44 + TAB_SIZE.Y + 10
local HINT_HEIGHT = 22

local PaintMenuView = {}

PaintMenuView.MaterialsTabId = "Materials"
PaintMenuView.TabletsTabId = "Tablets"

PaintMenuView.Tabs = {
	{ id = PaintMenuView.MaterialsTabId, label = "Материалы и Цвета" },
	{ id = PaintMenuView.TabletsTabId, label = "Древние Скрижали" },
}

-- Над нижней панелью, на месте каталога блоков (одновременно они не открываются).
PaintMenuView.ShownPosition = UDim2.new(0.5, 0, 1, -136)
PaintMenuView.HiddenPosition = UDim2.new(0.5, 0, 1, -116)

local function fitText(label: TextLabel, maxTextSize: number)
	label.TextScaled = true
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = maxTextSize
	constraint.Parent = label
end

local function horizontalRow(name: string, parent: Instance): Frame
	local row = Instance.new("Frame")
	row.Name = name
	row.BackgroundTransparency = 1
	row.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, GAP)
	layout.Parent = row
	return row
end

local function buildSwatch(material: PaintCatalog.Material, order: number, parent: Instance): TextButton
	local button = UIFactory.button(material.id .. "Swatch", "", Theme.SecondaryButtonColor, parent)
	button.Size = UDim2.fromOffset(SWATCH_TILE.X, SWATCH_TILE.Y)
	button.LayoutOrder = order

	local sample = Instance.new("Frame")
	sample.Name = "Sample"
	sample.Position = UDim2.fromOffset(10, 10)
	sample.Size = UDim2.new(1, -20, 0, 56)
	sample.BackgroundColor3 = material.color
	sample.BorderSizePixel = 0
	sample.Parent = button

	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.CornerRadius
	corner.Parent = sample

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.PanelStroke
	stroke.Thickness = 1
	stroke.Parent = sample

	local name = UIFactory.label("SwatchName", material.displayName, 18, button)
	name.Position = UDim2.fromOffset(6, 70)
	name.Size = UDim2.new(1, -12, 0, 26)
	fitText(name, 19)
	return button
end

local function buildTabletTile(tablet: PaintCatalog.Tablet, order: number, parent: Instance): TabletTile
	local button = UIFactory.button(tablet.id .. "Tablet", "", Theme.SecondaryButtonColor, parent)
	button.Size = UDim2.fromOffset(TABLET_TILE.X, TABLET_TILE.Y)
	button.LayoutOrder = order

	local title = UIFactory.label("TabletTitle", tablet.title, 18, button)
	title.Position = UDim2.fromOffset(8, 8)
	title.Size = UDim2.new(1, -16, 0, 26)
	fitText(title, 19)

	local faction = UIFactory.label("TabletFaction", tablet.factionName, 14, button)
	faction.Font = Theme.BodyFont
	faction.TextColor3 = Theme.PanelStroke
	faction.Position = UDim2.fromOffset(8, 34)
	faction.Size = UDim2.new(1, -16, 0, 18)

	local excerpt = UIFactory.label("TabletText", "«" .. tablet.text .. "»", 13, button)
	excerpt.Font = Theme.BodyFont
	excerpt.TextColor3 = Theme.SubTextColor
	excerpt.TextYAlignment = Enum.TextYAlignment.Top
	excerpt.Position = UDim2.fromOffset(8, 56)
	excerpt.Size = UDim2.new(1, -16, 1, -64)
	fitText(excerpt, 14)

	local star = UIFactory.label("Featured", "★", 16, button)
	star.AnchorPoint = Vector2.new(1, 0)
	star.Position = UDim2.new(1, -4, 0, 2)
	star.Size = UDim2.fromOffset(18, 18)
	star.TextColor3 = Theme.PanelStroke
	star.Visible = false

	return { button = button, star = star }
end

function PaintMenuView.build(gui: ScreenGui): View
	local frame = UIFactory.panel("PaintMenu", UDim2.fromOffset(MENU_SIZE.X, MENU_SIZE.Y), gui)
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = PaintMenuView.HiddenPosition
	frame.Active = true -- клики по фону меню не уходят в мир
	frame.Visible = false

	local title = UIFactory.label("Title", "Покраска и скрижали", 22, frame)
	title.Position = UDim2.fromOffset(14, 8)
	title.Size = UDim2.new(0.6, 0, 0, 28)
	title.TextXAlignment = Enum.TextXAlignment.Left

	local closeButton = UIFactory.button("Close", "✕", Theme.SecondaryButtonColor, frame)
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -10, 0, 8)
	closeButton.Size = UDim2.fromOffset(32, 30)

	-- Вкладки.
	local tabsRow = horizontalRow("Tabs", frame)
	tabsRow.Position = UDim2.fromOffset(12, 44)
	tabsRow.Size = UDim2.new(1, -24, 0, TAB_SIZE.Y)
	local tabsLayout = tabsRow:FindFirstChildOfClass("UIListLayout")
	if tabsLayout then
		tabsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	end

	local tabButtons: { [string]: TextButton } = {}
	local pages: { [string]: Frame } = {}
	for index, tab in PaintMenuView.Tabs do
		local button = UIFactory.button(tab.id .. "Tab", tab.label, Theme.SecondaryButtonColor, tabsRow)
		button.Size = UDim2.fromOffset(TAB_SIZE.X, TAB_SIZE.Y)
		button.LayoutOrder = index
		button.TextSize = 16
		tabButtons[tab.id] = button

		local page = Instance.new("Frame")
		page.Name = tab.id .. "Page"
		page.BackgroundTransparency = 1
		page.Position = UDim2.fromOffset(12, PAGE_TOP)
		page.Size = UDim2.new(1, -24, 1, -(PAGE_TOP + HINT_HEIGHT + 12))
		page.Visible = false
		page.Parent = frame
		pages[tab.id] = page
	end

	-- Страница материалов: ряд образцов.
	local swatchRow = horizontalRow("Swatches", pages[PaintMenuView.MaterialsTabId])
	swatchRow.Position = UDim2.fromOffset(0, 24)
	swatchRow.Size = UDim2.new(1, 0, 0, SWATCH_TILE.Y)

	local materialTiles: { [string]: TextButton } = {}
	for index, material in PaintCatalog.Materials do
		materialTiles[material.id] = buildSwatch(material, index, swatchRow)
	end

	-- Страница скрижалей: карточки и «Очистить грань» под ними.
	local tabletsPage = pages[PaintMenuView.TabletsTabId]
	local tabletRow = horizontalRow("Tablets", tabletsPage)
	tabletRow.Size = UDim2.new(1, 0, 0, TABLET_TILE.Y)

	local tabletTiles: { [string]: TabletTile } = {}
	for index, tablet in PaintCatalog.Tablets do
		tabletTiles[tablet.id] = buildTabletTile(tablet, index, tabletRow)
	end

	local eraseButton = UIFactory.button("ErasePlaque", "Очистить грань", Theme.PrimaryButtonColor, tabletsPage)
	eraseButton.TextSize = 18
	eraseButton.AnchorPoint = Vector2.new(0.5, 1)
	eraseButton.Position = UDim2.new(0.5, 0, 1, 0)
	eraseButton.Size = UDim2.fromOffset(240, 34)

	local hintLabel = UIFactory.label("Hint", "", 15, frame)
	hintLabel.Font = Theme.BodyFont
	hintLabel.TextColor3 = Theme.SubTextColor
	hintLabel.AnchorPoint = Vector2.new(0.5, 1)
	hintLabel.Position = UDim2.new(0.5, 0, 1, -8)
	hintLabel.Size = UDim2.new(1, -24, 0, HINT_HEIGHT)
	fitText(hintLabel, 15)

	return {
		frame = frame,
		closeButton = closeButton,
		tabButtons = tabButtons,
		pages = pages,
		materialTiles = materialTiles,
		tabletTiles = tabletTiles,
		eraseButton = eraseButton,
		hintLabel = hintLabel,
	}
end

return PaintMenuView
