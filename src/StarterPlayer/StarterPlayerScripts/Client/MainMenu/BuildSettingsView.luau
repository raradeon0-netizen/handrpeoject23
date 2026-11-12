--!strict
-- BuildSettingsView: разметка мини-панели «Точность» (справа сверху).
-- Только разметка, без логики: состояние и клики обрабатывает BuildSettingsController.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildConfig = require(ReplicatedStorage.Shared.BuildConfig)
local Theme = require(script.Parent.Theme)
local UIFactory = require(script.Parent.UIFactory)

export type SizeRow = {
	frame: Frame,
	label: TextLabel,
	minus: TextButton,
	box: TextBox,
	plus: TextButton,
}

export type View = {
	gui: ScreenGui,
	uiScale: UIScale, -- масштаб панели (синхронизируется с настройками меню)
	panel: Frame,
	modeLabel: TextLabel, -- текущий режим: установка / резак / снос
	gridLabel: TextLabel,
	gridButtons: { TextButton }, -- по индексам BuildConfig.GridOptions
	rotationLabel: TextLabel,
	rotationButtons: { TextButton }, -- по индексам BuildConfig.RotationSteps
	anglesLabel: TextLabel,
	resetButton: TextButton,
	snapButton: TextButton,
	cutterRow: Frame, -- переключатель формы резака (виден только в режиме «Вырезать»)
	cutterButtons: { TextButton }, -- по индексам BuildConfig.CutterShapes
	sizeLabel: TextLabel,
	sizeResetButton: TextButton,
	sizeRows: { SizeRow }, -- оси X, Y, Z
	noticeLabel: TextLabel,
}

local PANEL_WIDTH = 300
local PANEL_PADDING = 6
local RIGHT_MARGIN = 16
local TOP_OFFSET = 64 -- ниже верхней панели Roblox (ScreenGui с IgnoreGuiInset)
local ROW_HEIGHT = 34
local SIZE_ROW_HEIGHT = 28
local SIZE_BUTTON_WIDTH = 32

local HINTS = {
	"R — вращать (Y) · T / Y — наклон (X / Z)",
	"X — удалить блок под курсором",
	"ЛКМ — поставить / вырезать / выбрать",
	"«Двигать»: тяните стрелки у блока",
	"ПКМ — вращение камеры",
}

local BuildSettingsView = {}

-- Положения панели для анимации: у правого края и за экраном.
BuildSettingsView.PanelShownPosition = UDim2.new(1, -RIGHT_MARGIN, 0, TOP_OFFSET)
BuildSettingsView.PanelHiddenPosition = UDim2.new(1, PANEL_WIDTH + 60, 0, TOP_OFFSET)

-- Ограничивает максимальный размер текста при TextScaled.
local function scaleToFit(label: TextLabel, maxTextSize: number)
	label.TextScaled = true
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = maxTextSize
	constraint.Parent = label
end

-- Подпись секции (мелкий шрифт, по левому краю).
local function sectionLabel(name: string, parent: Instance, layoutOrder: number): TextLabel
	local label = UIFactory.label(name, "", 18, parent)
	label.Font = Theme.BodyFont
	label.TextColor3 = Theme.SubTextColor
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Size = UDim2.new(1, 0, 0, 20)
	label.LayoutOrder = layoutOrder
	return label
end

-- Ряд одинаковых кнопок-вариантов (переключатель).
local function optionRow(name: string, texts: { string }, parent: Instance, layoutOrder: number): { TextButton }
	local row = Instance.new("Frame")
	row.Name = name
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.LayoutOrder = layoutOrder
	row.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = row

	local buttons: { TextButton } = {}
	for index, text in texts do
		local button = UIFactory.button(name .. index, text, Theme.SecondaryButtonColor, row)
		button.TextSize = 20
		button.Size = UDim2.new(1 / #texts, -5, 1, 0)
		button.LayoutOrder = index
		table.insert(buttons, button)
	end
	return buttons
end

-- Строка одной оси размера: подпись, «−», поле ввода, «+».
local function sizeRow(axis: number, parent: Instance): SizeRow
	local frame = Instance.new("Frame")
	frame.Name = "SizeAxis" .. axis
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, 0, 0, SIZE_ROW_HEIGHT)
	frame.LayoutOrder = axis
	frame.Parent = parent

	local label = UIFactory.label("Axis", "", 17, frame)
	label.Font = Theme.BodyFont
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Size = UDim2.new(0, 94, 1, 0)
	scaleToFit(label, 17)

	local minus = UIFactory.button("Minus", "−", Theme.SecondaryButtonColor, frame)
	minus.TextSize = 22
	minus.Position = UDim2.fromOffset(98, 0)
	minus.Size = UDim2.new(0, SIZE_BUTTON_WIDTH, 1, 0)

	local box = Instance.new("TextBox")
	box.Name = "Value"
	box.Text = ""
	box.ClearTextOnFocus = false
	box.Font = Theme.BodyFont
	box.TextSize = 18
	box.TextColor3 = Theme.TextColor
	box.BackgroundColor3 = Theme.BackgroundColor
	box.BorderSizePixel = 0
	box.Position = UDim2.fromOffset(98 + SIZE_BUTTON_WIDTH + 4, 0)
	box.Size = UDim2.new(1, -(98 + SIZE_BUTTON_WIDTH * 2 + 8), 1, 0)
	box.Parent = frame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.CornerRadius
	corner.Parent = box

	local plus = UIFactory.button("Plus", "+", Theme.SecondaryButtonColor, frame)
	plus.TextSize = 22
	plus.AnchorPoint = Vector2.new(1, 0)
	plus.Position = UDim2.new(1, 0, 0, 0)
	plus.Size = UDim2.new(0, SIZE_BUTTON_WIDTH, 1, 0)

	return { frame = frame, label = label, minus = minus, box = box, plus = plus }
end

function BuildSettingsView.build(playerGui: PlayerGui): View
	-- Шаг 1. Корневой ScreenGui (как у нижней панели: DisplayOrder ниже меню).
	local gui = Instance.new("ScreenGui")
	gui.Name = "BuildSettings"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 5
	gui.Enabled = false

	local uiScale = Instance.new("UIScale")
	uiScale.Parent = gui

	-- Шаг 2. Панель справа сверху; высота подстраивается под содержимое.
	local panel = UIFactory.panel("Panel", UDim2.fromOffset(PANEL_WIDTH, 0), gui)
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = BuildSettingsView.PanelHiddenPosition
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.Active = true -- клики по фону панели не уходят в мир (не ставят блок)
	UIFactory.verticalList(panel, PANEL_PADDING)

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	-- Шаг 3. Заголовок и текущий режим.
	local title = UIFactory.label("Title", "Точность", 26, panel)
	title.Size = UDim2.new(1, 0, 0, 30)
	title.LayoutOrder = nextOrder()

	local modeLabel = UIFactory.label("Mode", "", 18, panel)
	modeLabel.Font = Theme.BodyFont
	modeLabel.Size = UDim2.new(1, 0, 0, 0)
	modeLabel.AutomaticSize = Enum.AutomaticSize.Y
	modeLabel.LayoutOrder = nextOrder()

	-- Шаг 4. Шаг сетки: 4 / 1 / 0.25 / 0.
	local gridLabel = sectionLabel("GridLabel", panel, nextOrder())
	local gridTexts: { string } = {}
	for _, option in BuildConfig.GridOptions do
		table.insert(gridTexts, option.label)
	end
	local gridButtons = optionRow("GridOption", gridTexts, panel, nextOrder())

	-- Шаг 5. Шаг поворота: 90° / 45° / 15° / 5°.
	local rotationLabel = sectionLabel("RotationLabel", panel, nextOrder())
	local rotationTexts: { string } = {}
	for _, stepDegrees in BuildConfig.RotationSteps do
		table.insert(rotationTexts, tostring(stepDegrees) .. "°")
	end
	local rotationButtons = optionRow("RotationOption", rotationTexts, panel, nextOrder())

	-- Шаг 6. Текущие углы + кнопка сброса поворота.
	local anglesRow = Instance.new("Frame")
	anglesRow.Name = "AnglesRow"
	anglesRow.BackgroundTransparency = 1
	anglesRow.Size = UDim2.new(1, 0, 0, 34)
	anglesRow.LayoutOrder = nextOrder()
	anglesRow.Parent = panel

	local anglesLabel = UIFactory.label("Angles", "", 18, anglesRow)
	anglesLabel.Font = Theme.BodyFont
	anglesLabel.TextXAlignment = Enum.TextXAlignment.Left
	anglesLabel.Size = UDim2.new(1, -104, 1, 0)
	scaleToFit(anglesLabel, 18)

	local resetButton = UIFactory.button("ResetRotation", "Сброс", Theme.SecondaryButtonColor, anglesRow)
	resetButton.TextSize = 18
	resetButton.AnchorPoint = Vector2.new(1, 0.5)
	resetButton.Position = UDim2.new(1, 0, 0.5, 0)
	resetButton.Size = UDim2.fromOffset(96, 32)

	-- Шаг 7. «Магнит к центру» (переключатель).
	local snapButton = UIFactory.button("SnapToCenter", "", Theme.SecondaryButtonColor, panel)
	snapButton.TextSize = 20
	snapButton.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	snapButton.LayoutOrder = nextOrder()

	-- Форма резака («Куб» / «Полоса»): строка видна только в режиме «Вырезать».
	local cutterTexts: { string } = {}
	for _, option in BuildConfig.CutterShapes do
		table.insert(cutterTexts, option.label)
	end
	local cutterButtons = optionRow("CutterShape", cutterTexts, panel, nextOrder())
	local cutterRow = cutterButtons[1].Parent :: Frame
	cutterRow.Visible = false
	for _, button in cutterButtons do
		button.TextSize = 17
	end

	-- Размер блока / резака: заголовок со сбросом и по строке «− [поле] +» на каждую ось.
	local sizeSection = Instance.new("Frame")
	sizeSection.Name = "SizeSection"
	sizeSection.BackgroundTransparency = 1
	sizeSection.Size = UDim2.new(1, 0, 0, 0)
	sizeSection.AutomaticSize = Enum.AutomaticSize.Y
	sizeSection.LayoutOrder = nextOrder()
	sizeSection.Parent = panel

	local sizeLayout = Instance.new("UIListLayout")
	sizeLayout.FillDirection = Enum.FillDirection.Vertical
	sizeLayout.SortOrder = Enum.SortOrder.LayoutOrder
	sizeLayout.Padding = UDim.new(0, 4)
	sizeLayout.Parent = sizeSection

	local sizeHeader = Instance.new("Frame")
	sizeHeader.Name = "Header"
	sizeHeader.BackgroundTransparency = 1
	sizeHeader.Size = UDim2.new(1, 0, 0, 24)
	sizeHeader.LayoutOrder = 0
	sizeHeader.Parent = sizeSection

	local sizeLabel = UIFactory.label("SizeLabel", "", 18, sizeHeader)
	sizeLabel.Font = Theme.BodyFont
	sizeLabel.TextColor3 = Theme.SubTextColor
	sizeLabel.TextXAlignment = Enum.TextXAlignment.Left
	sizeLabel.Size = UDim2.new(1, -84, 1, 0)
	scaleToFit(sizeLabel, 18)

	local sizeResetButton = UIFactory.button("ResetSize", "Сброс", Theme.SecondaryButtonColor, sizeHeader)
	sizeResetButton.TextSize = 16
	sizeResetButton.AnchorPoint = Vector2.new(1, 0.5)
	sizeResetButton.Position = UDim2.new(1, 0, 0.5, 0)
	sizeResetButton.Size = UDim2.fromOffset(78, 24)

	local sizeRows: { SizeRow } = {}
	for axis = 1, 3 do
		table.insert(sizeRows, sizeRow(axis, sizeSection))
	end

	-- Шаг 8. Подсказка по клавишам.
	local hints = UIFactory.label("Hints", table.concat(HINTS, "\n"), 16, panel)
	hints.Font = Theme.BodyFont
	hints.TextColor3 = Theme.SubTextColor
	hints.TextXAlignment = Enum.TextXAlignment.Left
	hints.TextYAlignment = Enum.TextYAlignment.Top
	hints.Size = UDim2.new(1, 0, 0, 0)
	hints.AutomaticSize = Enum.AutomaticSize.Y
	hints.LayoutOrder = nextOrder()

	-- Шаг 9. Короткие сообщения (скрыты, пока нечего сказать).
	local noticeLabel = UIFactory.label("Notice", "", 16, panel)
	noticeLabel.Font = Theme.BodyFont
	noticeLabel.TextColor3 = Color3.fromRGB(255, 205, 130)
	noticeLabel.TextXAlignment = Enum.TextXAlignment.Left
	noticeLabel.Size = UDim2.new(1, 0, 0, 0)
	noticeLabel.AutomaticSize = Enum.AutomaticSize.Y
	noticeLabel.Visible = false
	noticeLabel.LayoutOrder = nextOrder()

	-- Шаг 10. Добавляем GUI в PlayerGui последним, когда иерархия уже собрана.
	gui.Parent = playerGui

	return {
		gui = gui,
		uiScale = uiScale,
		panel = panel,
		modeLabel = modeLabel,
		gridLabel = gridLabel,
		gridButtons = gridButtons,
		rotationLabel = rotationLabel,
		rotationButtons = rotationButtons,
		anglesLabel = anglesLabel,
		resetButton = resetButton,
		snapButton = snapButton,
		cutterRow = cutterRow,
		cutterButtons = cutterButtons,
		sizeLabel = sizeLabel,
		sizeResetButton = sizeResetButton,
		sizeRows = sizeRows,
		noticeLabel = noticeLabel,
	}
end

return BuildSettingsView
