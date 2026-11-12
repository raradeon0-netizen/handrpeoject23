--!strict
-- BlockPickerView: разметка компактного каталога блоков (кнопка «Блоки» / клавиша B).
-- Заголовок, вкладки категорий и прокручиваемая сетка плиток (ScrollingFrame + UIGridLayout).
-- Только разметка, без логики: фильтры, выбор и звёздочки — в BlockPickerController.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BlockCatalog = require(ReplicatedStorage.Shared.BlockCatalog)
local Theme = require(script.Parent.Theme)
local UIFactory = require(script.Parent.UIFactory)

export type Tile = {
	button: TextButton,
	star: TextLabel, -- ★ «родной» блок фракции
	lock: TextLabel, -- «только стройка»: составной блок нельзя взять формой резака
	order: number,
}

export type View = {
	frame: Frame,
	scroll: ScrollingFrame,
	closeButton: TextButton,
	factionLabel: TextLabel,
	tabButtons: { [string]: TextButton },
	tiles: { [string]: Tile },
}

local PICKER_SIZE = Vector2.new(680, 330)
local TILE_SIZE = Vector2.new(120, 76)
local TAB_HEIGHT = 30
local TAB_GAP = 6
local GAP = 8

local BlockPickerView = {}

-- Над нижней панелью: её высота (84 + отступы) + нижний отступ + зазор.
BlockPickerView.ShownPosition = UDim2.new(0.5, 0, 1, -136)
BlockPickerView.HiddenPosition = UDim2.new(0.5, 0, 1, -116)

local function fitText(label: TextLabel, maxTextSize: number)
	label.TextScaled = true
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = maxTextSize
	constraint.Parent = label
end

local function buildTile(entry: BlockCatalog.Entry, order: number, parent: Instance): Tile
	local button = UIFactory.button(entry.id .. "Tile", "", Theme.SecondaryButtonColor, parent)
	button.LayoutOrder = order

	local name = UIFactory.label("TileName", entry.displayName, 18, button)
	name.Position = UDim2.fromOffset(6, 8)
	name.Size = UDim2.new(1, -12, 0, 26)
	fitText(name, 19)

	local description = UIFactory.label("TileDescription", entry.description, 13, button)
	description.Font = Theme.BodyFont
	description.TextColor3 = Theme.SubTextColor
	description.TextWrapped = true
	description.Position = UDim2.fromOffset(6, 36)
	description.Size = UDim2.new(1, -12, 0, 32)
	fitText(description, 14)

	local star = UIFactory.label("Featured", "★", 16, button)
	star.AnchorPoint = Vector2.new(1, 0)
	star.Position = UDim2.new(1, -4, 0, 2)
	star.Size = UDim2.fromOffset(18, 18)
	star.TextColor3 = Theme.PanelStroke
	star.Visible = false

	local lock = UIFactory.label("BuildOnly", "только стройка", 11, button)
	lock.Font = Theme.BodyFont
	lock.TextColor3 = Theme.SubTextColor
	lock.AnchorPoint = Vector2.new(0.5, 1)
	lock.Position = UDim2.new(0.5, 0, 1, -2)
	lock.Size = UDim2.new(1, -8, 0, 12)
	fitText(lock, 11)
	lock.Visible = false

	return { button = button, star = star, lock = lock, order = order }
end

function BlockPickerView.build(gui: ScreenGui): View
	-- Шаг 1. Рамка каталога (в том же ScreenGui, что и нижняя панель — общий UIScale).
	local frame = UIFactory.panel("BlockPicker", UDim2.fromOffset(PICKER_SIZE.X, PICKER_SIZE.Y), gui)
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = BlockPickerView.HiddenPosition
	frame.Active = true -- клики по фону каталога не уходят в мир
	frame.Visible = false

	-- Шаг 2. Заголовок и крестик.
	local title = UIFactory.label("Title", "Каталог блоков", 22, frame)
	title.Position = UDim2.fromOffset(14, 8)
	title.Size = UDim2.new(0.5, 0, 0, 28)
	title.TextXAlignment = Enum.TextXAlignment.Left

	local factionLabel = UIFactory.label("FactionHint", "", 14, frame)
	factionLabel.Font = Theme.BodyFont
	factionLabel.TextColor3 = Theme.SubTextColor
	factionLabel.AnchorPoint = Vector2.new(1, 0)
	factionLabel.Position = UDim2.new(1, -52, 0, 12)
	factionLabel.Size = UDim2.new(0.45, 0, 0, 22)
	factionLabel.TextXAlignment = Enum.TextXAlignment.Right

	local closeButton = UIFactory.button("Close", "✕", Theme.SecondaryButtonColor, frame)
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -10, 0, 8)
	closeButton.Size = UDim2.fromOffset(32, 30)

	-- Шаг 3. Вкладки категорий.
	local tabsRow = Instance.new("Frame")
	tabsRow.Name = "Tabs"
	tabsRow.BackgroundTransparency = 1
	tabsRow.Position = UDim2.fromOffset(12, 44)
	tabsRow.Size = UDim2.new(1, -24, 0, TAB_HEIGHT)
	tabsRow.Parent = frame

	local tabsLayout = Instance.new("UIListLayout")
	tabsLayout.FillDirection = Enum.FillDirection.Horizontal
	tabsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabsLayout.Padding = UDim.new(0, TAB_GAP)
	tabsLayout.Parent = tabsRow

	-- Вкладки делят ширину окна поровну: новая категория не уезжает за край.
	local tabCount = #BlockCatalog.Categories
	local tabWidth = math.floor((PICKER_SIZE.X - 24 - TAB_GAP * (tabCount - 1)) / tabCount)
	local tabButtons: { [string]: TextButton } = {}
	for index, category in BlockCatalog.Categories do
		local tab = UIFactory.button(category.id .. "Tab", category.label, Theme.SecondaryButtonColor, tabsRow)
		tab.Size = UDim2.fromOffset(tabWidth, TAB_HEIGHT)
		tab.LayoutOrder = index
		tab.TextScaled = true
		local tabTextLimit = Instance.new("UITextSizeConstraint")
		tabTextLimit.MaxTextSize = 16
		tabTextLimit.Parent = tab
		tabButtons[category.id] = tab
	end

	-- Шаг 4. Прокручиваемая сетка плиток.
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Blocks"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(12, 44 + TAB_HEIGHT + 10)
	scroll.Size = UDim2.new(1, -24, 1, -(44 + TAB_HEIGHT + 10 + 12))
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = Theme.PanelStroke
	scroll.Parent = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingLeft = UDim.new(0, 4)
	padding.PaddingRight = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 4)
	padding.Parent = scroll

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(TILE_SIZE.X, TILE_SIZE.Y)
	grid.CellPadding = UDim2.fromOffset(GAP, GAP)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroll

	-- Подстраховка к AutomaticCanvasSize: высота прокрутки всегда равна высоте сетки плиток,
	-- поэтому новые блоки не остаются за нижним краем списка.
	local function fitCanvas()
		scroll.CanvasSize = UDim2.fromOffset(0, grid.AbsoluteContentSize.Y + 8)
	end
	grid:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fitCanvas)
	fitCanvas()

	local tiles: { [string]: Tile } = {}
	for index, entry in BlockCatalog.List do
		tiles[entry.id] = buildTile(entry, index, scroll)
	end

	return {
		frame = frame,
		scroll = scroll,
		closeButton = closeButton,
		factionLabel = factionLabel,
		tabButtons = tabButtons,
		tiles = tiles,
	}
end

return BlockPickerView
