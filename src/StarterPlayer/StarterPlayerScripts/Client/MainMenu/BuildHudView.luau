--!strict
-- BuildHudView: строит иерархию нижней строительной панели (ScreenGui -> Panel -> Slots).
-- Только разметка, без логики: выбор слотов обрабатывает BuildHudController.
-- Слева — кнопка каталога «Блоки» (открывает BlockPicker), справа — инструменты.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildSlots = require(ReplicatedStorage.Shared.BuildSlots)
local Theme = require(script.Parent.Theme)
local UIFactory = require(script.Parent.UIFactory)

export type View = {
	gui: ScreenGui,
	uiScale: UIScale, -- масштаб всей панели (синхронизируется с настройками меню)
	panel: Frame,
	slotButtons: { [string]: TextButton }, -- id слота -> кнопка
	selectionBars: { [string]: Frame }, -- id слота -> полоска «выбрано» внизу кнопки
	descriptionLabels: { [string]: TextLabel }, -- id слота -> подпись (у «Блоков» — текущая форма)
}

local SLOT_SIZE = Vector2.new(92, 60)
local TOOL_SLOT_WIDTH = 160
local PANEL_PADDING = 8
local BOTTOM_MARGIN = 10

local BuildHudView = {}

-- Положения панели для анимации появления: у нижнего края и за экраном.
BuildHudView.PanelShownPosition = UDim2.new(0.5, 0, 1, -BOTTOM_MARGIN)
BuildHudView.PanelHiddenPosition = UDim2.new(0.5, 0, 1, 220)

-- Ограничивает максимальный размер текста при TextScaled (длинные названия сжимаются).
local function scaleToFit(label: TextLabel, maxTextSize: number)
	label.TextScaled = true
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = maxTextSize
	constraint.Parent = label
end

function BuildHudView.build(playerGui: PlayerGui): View
	-- Шаг 1. Корневой ScreenGui. Скрыт до выбора фракции; DisplayOrder ниже меню (10).
	local gui = Instance.new("ScreenGui")
	gui.Name = "BuildHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 5
	gui.Enabled = false

	local uiScale = Instance.new("UIScale")
	uiScale.Parent = gui

	-- Шаг 2. Панель внизу по центру: ширина подстраивается под количество слотов.
	local panel = UIFactory.panel("Panel", UDim2.fromOffset(0, 0), gui)
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = BuildHudView.PanelHiddenPosition
	panel.AutomaticSize = Enum.AutomaticSize.XY
	panel.Active = true -- клики по фону панели не уходят в мир (не ставят блок)
	UIFactory.horizontalList(panel, PANEL_PADDING)

	-- Шаг 3. По кнопке на каждый слот из BuildSlots.
	local slotButtons: { [string]: TextButton } = {}
	local selectionBars: { [string]: Frame } = {}
	local descriptionLabels: { [string]: TextLabel } = {}

	local separatorAdded = false
	for index, slot in BuildSlots.List do
		local isTool = slot.kind == "Tool"

		-- Инструменты (резак, снос, покраска) отделяем от каталога одной тонкой вертикальной чертой.
		if isTool and not separatorAdded then
			separatorAdded = true
			local separator = Instance.new("Frame")
			separator.Name = "Separator"
			separator.Size = UDim2.fromOffset(2, SLOT_SIZE.Y - 24)
			separator.BackgroundColor3 = Theme.PanelStroke
			separator.BackgroundTransparency = 0.4
			separator.BorderSizePixel = 0
			separator.LayoutOrder = index * 2 - 1
			separator.Parent = panel
		end

		local button = UIFactory.button(
			slot.id .. "Slot",
			"",
			if isTool then Theme.PrimaryButtonColor else Theme.SecondaryButtonColor,
			panel
		)
		button.Size = UDim2.fromOffset(if slot.wide then TOOL_SLOT_WIDTH else SLOT_SIZE.X, SLOT_SIZE.Y)
		button.LayoutOrder = index * 2

		-- Внутри кнопки: название и подпись.
		local name = UIFactory.label("SlotName", slot.displayName, 19, button)
		name.Position = UDim2.fromOffset(6, 6)
		name.Size = UDim2.new(1, -12, 0, 24)
		scaleToFit(name, 20)

		local description = UIFactory.label("SlotDescription", slot.description, 16, button)
		description.Font = Theme.BodyFont
		description.TextColor3 = Theme.SubTextColor
		description.Position = UDim2.fromOffset(6, 31)
		description.Size = UDim2.new(1, -12, 0, 18)
		scaleToFit(description, 14)

		-- Полоска «выбрано» внизу кнопки (видна только у выбранного слота).
		local bar = Instance.new("Frame")
		bar.Name = "SelectionBar"
		bar.AnchorPoint = Vector2.new(0.5, 1)
		bar.Position = UDim2.new(0.5, 0, 1, -4)
		bar.Size = UDim2.new(0.5, 0, 0, 3)
		bar.BackgroundColor3 = Theme.SelectedStroke
		bar.BorderSizePixel = 0
		bar.Visible = false
		bar.Parent = button

		local barCorner = Instance.new("UICorner")
		barCorner.CornerRadius = UDim.new(1, 0)
		barCorner.Parent = bar

		slotButtons[slot.id] = button
		selectionBars[slot.id] = bar
		descriptionLabels[slot.id] = description
	end

	-- Шаг 4. Добавляем GUI в PlayerGui последним, когда иерархия уже собрана.
	gui.Parent = playerGui

	return {
		gui = gui,
		uiScale = uiScale,
		panel = panel,
		slotButtons = slotButtons,
		selectionBars = selectionBars,
		descriptionLabels = descriptionLabels,
	}
end

return BuildHudView
