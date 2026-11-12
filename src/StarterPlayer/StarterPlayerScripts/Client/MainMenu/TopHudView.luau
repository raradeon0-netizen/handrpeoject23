--!strict
-- TopHudView: компактная верхняя панель строительства.
-- Слева — переключатель «Время суток», справа — «Сохранить» / «Загрузить»; под панелью
-- всплывает строка статуса. Только создаёт GUI; логика — в TopHudController.

local Theme = require(script.Parent.Theme)
local TimeOfDayController = require(script.Parent.TimeOfDayController)
local UIFactory = require(script.Parent.UIFactory)

export type View = {
	gui: ScreenGui,
	uiScale: UIScale,
	panel: Frame,
	timeButtons: { [string]: TextButton }, -- id времени суток -> кнопка
	saveButton: TextButton,
	loadButton: TextButton,
	statusLabel: TextLabel,
	pauseButton: TextButton, -- «Меню» в левом верхнем углу
	walkButton: TextButton, -- «Режим: Стройка / Прогулка»
}

local BUTTON_HEIGHT = 28
local TIME_BUTTON_WIDTH = 62
local ACTION_BUTTON_WIDTH = 96
local PANEL_PADDING = 6
local TOP_MARGIN = 8

local TopHudView = {}

TopHudView.PanelShownPosition = UDim2.new(0.5, 0, 0, TOP_MARGIN)
TopHudView.PanelHiddenPosition = UDim2.new(0.5, 0, 0, -80)

local function compactButton(name: string, text: string, color: Color3, width: number, order: number, parent: Instance): TextButton
	local button = UIFactory.button(name, text, color, parent)
	button.TextSize = 16
	button.Size = UDim2.fromOffset(width, BUTTON_HEIGHT)
	button.LayoutOrder = order
	return button
end

function TopHudView.build(playerGui: PlayerGui): View
	local gui = Instance.new("ScreenGui")
	gui.Name = "TopHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 5
	gui.Enabled = false

	local uiScale = Instance.new("UIScale")
	uiScale.Parent = gui

	local panel = UIFactory.panel("Panel", UDim2.fromOffset(0, 0), gui)
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = TopHudView.PanelHiddenPosition
	panel.AutomaticSize = Enum.AutomaticSize.XY
	panel.Active = true -- клики по фону панели не уходят в мир
	UIFactory.horizontalList(panel, PANEL_PADDING)

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	local caption = UIFactory.label("TimeCaption", "Время суток", 15, panel)
	caption.Font = Theme.BodyFont
	caption.TextColor3 = Theme.SubTextColor
	caption.Size = UDim2.fromOffset(86, BUTTON_HEIGHT)
	caption.LayoutOrder = nextOrder()

	local timeButtons: { [string]: TextButton } = {}
	for _, preset in TimeOfDayController.Presets do
		timeButtons[preset.id] = compactButton(
			preset.id .. "Time",
			preset.label,
			Theme.SecondaryButtonColor,
			TIME_BUTTON_WIDTH,
			nextOrder(),
			panel
		)
	end

	local separator = Instance.new("Frame")
	separator.Name = "Separator"
	separator.Size = UDim2.fromOffset(1, BUTTON_HEIGHT - 8)
	separator.BackgroundColor3 = Theme.PanelStroke
	separator.BackgroundTransparency = 0.5
	separator.BorderSizePixel = 0
	separator.LayoutOrder = nextOrder()
	separator.Parent = panel

	local saveButton =
		compactButton("Save", "Сохранить", Theme.PrimaryButtonColor, ACTION_BUTTON_WIDTH, nextOrder(), panel)
	local loadButton =
		compactButton("Load", "Загрузить", Theme.SecondaryButtonColor, ACTION_BUTTON_WIDTH, nextOrder(), panel)

	local walkSeparator = separator:Clone()
	walkSeparator.LayoutOrder = nextOrder()
	walkSeparator.Parent = panel

	-- Переключатель стройка / прогулка (клавиша V).
	local walkButton = compactButton("Walk", "", Theme.SecondaryButtonColor, 156, nextOrder(), panel)

	-- Статус под панелью: «Сохранено!», «Загружено!» или причина ошибки.
	local statusLabel = UIFactory.label("Status", "", 16, gui)
	statusLabel.Font = Theme.BodyFont
	statusLabel.AnchorPoint = Vector2.new(0.5, 0)
	statusLabel.Position = UDim2.new(0.5, 0, 0, TOP_MARGIN + BUTTON_HEIGHT + PANEL_PADDING * 2 + 6)
	statusLabel.Size = UDim2.fromOffset(520, 0)
	statusLabel.AutomaticSize = Enum.AutomaticSize.Y
	statusLabel.BackgroundColor3 = Theme.PanelColor
	statusLabel.BackgroundTransparency = 0.15
	statusLabel.Visible = false

	local statusCorner = Instance.new("UICorner")
	statusCorner.CornerRadius = Theme.CornerRadius
	statusCorner.Parent = statusLabel

	local statusPadding = Instance.new("UIPadding")
	statusPadding.PaddingTop = UDim.new(0, 4)
	statusPadding.PaddingBottom = UDim.new(0, 4)
	statusPadding.PaddingLeft = UDim.new(0, 10)
	statusPadding.PaddingRight = UDim.new(0, 10)
	statusPadding.Parent = statusLabel

	-- Кнопка меню паузы: левый верхний угол, под значками верхней панели Roblox.
	local pauseButton = UIFactory.button("Pause", "Меню", Theme.SecondaryButtonColor, gui)
	pauseButton.TextSize = 17
	pauseButton.Position = UDim2.fromOffset(12, 62)
	pauseButton.Size = UDim2.fromOffset(84, 30)

	gui.Parent = playerGui

	return {
		gui = gui,
		uiScale = uiScale,
		panel = panel,
		timeButtons = timeButtons,
		saveButton = saveButton,
		loadButton = loadButton,
		statusLabel = statusLabel,
		pauseButton = pauseButton,
		walkButton = walkButton,
	}
end

return TopHudView
