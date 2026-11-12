--!strict
-- MenuView: строит иерархию интерфейса (ScreenGui -> Frames -> Buttons).
-- Только разметка, без логики: обработчики навешивает MenuController.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FactionConfig = require(ReplicatedStorage.Shared.FactionConfig)
local Theme = require(script.Parent.Theme)
local UIFactory = require(script.Parent.UIFactory)

export type View = {
	gui: ScreenGui,
	uiScale: UIScale, -- масштаб всего меню
	titleScreen: Frame, -- экран с кнопкой «Играть»
	factionScreen: Frame, -- экран выбора фракции
	settingsScreen: Frame, -- окно настроек
	playButton: TextButton,
	settingsButton: TextButton,
	backButton: TextButton,
	closeSettingsButton: TextButton,
	factionButtons: { [string]: TextButton }, -- id фракции -> кнопка
	scaleButtons: { [string]: TextButton }, -- id варианта размера -> кнопка
	volumeLabel: TextLabel, -- «Громкость музыки: 40%»
	volumeMinus: TextButton,
	volumePlus: TextButton,
	volumeFill: Frame, -- заполнение шкалы громкости
	muteButton: TextButton,
	sfxButton: TextButton, -- «Звуки стройки (SFX): Вкл / Выкл»
	animationButton: TextButton, -- «Анимации стройки: Выкл / Обычная / Мощная»
	plotSizeButton: TextButton, -- «Размер плиты: 200×200 (Стандартная)»
	plotSizeNote: TextLabel, -- ответ сервера на смену размера
	pauseScreen: Frame, -- меню паузы (во время игры)
	resumeButton: TextButton,
	pauseSettingsButton: TextButton,
	exitButton: TextButton,
}

local MenuView = {}

function MenuView.build(playerGui: PlayerGui): View
	-- Шаг 1. Корневой ScreenGui. ResetOnSpawn = false, чтобы меню
	-- не пересоздавалось при респавне персонажа.
	local gui = Instance.new("ScreenGui")
	gui.Name = "MainMenu"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true -- закрывает и верхнюю панель Roblox
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 10

	-- UIScale на ScreenGui масштабирует все вложенные элементы разом.
	local uiScale = Instance.new("UIScale")
	uiScale.Parent = gui

	-- Шаг 2. Титульный экран: название игры, кнопки «Играть» и «Настройки».
	local titleScreen = UIFactory.screen("TitleScreen", gui)
	local titlePanel = UIFactory.panel("Panel", UDim2.fromOffset(460, 370), titleScreen)
	UIFactory.verticalList(titlePanel, 20)

	local title = UIFactory.label("Title", "Древний Мир", 48, titlePanel)
	title.LayoutOrder = 1

	local subtitle = UIFactory.label("Subtitle", "Рим • Греция • Египет", 22, titlePanel)
	subtitle.Font = Theme.BodyFont
	subtitle.TextColor3 = Theme.SubTextColor
	subtitle.LayoutOrder = 2

	local playButton = UIFactory.button("PlayButton", "Играть", Theme.PrimaryButtonColor, titlePanel)
	playButton.Size = UDim2.new(0.7, 0, 0, 60)
	playButton.LayoutOrder = 3

	local settingsButton = UIFactory.button("SettingsButton", "Настройки", Theme.SecondaryButtonColor, titlePanel)
	settingsButton.Size = UDim2.new(0.7, 0, 0, 48)
	settingsButton.TextSize = 24
	settingsButton.LayoutOrder = 4

	-- Шаг 3. Экран выбора фракции: по кнопке на каждую фракцию из конфига.
	local factionScreen = UIFactory.screen("FactionScreen", gui)
	local factionPanel = UIFactory.panel("Panel", UDim2.fromOffset(520, 480), factionScreen)
	UIFactory.verticalList(factionPanel, 16)

	local factionTitle = UIFactory.label("Title", "Выберите цивилизацию", 36, factionPanel)
	factionTitle.LayoutOrder = 0

	local factionButtons: { [string]: TextButton } = {}
	for index, faction in FactionConfig.List do
		local button = UIFactory.button(
			faction.id .. "Button",
			"",
			faction.buttonColor,
			factionPanel,
			faction.accentColor
		)
		button.Size = UDim2.new(1, 0, 0, 80)
		button.LayoutOrder = index

		-- Внутри кнопки: название и описание фракции.
		local name = UIFactory.label("FactionName", faction.displayName, 30, button)
		name.Position = UDim2.fromOffset(0, 8)

		local description = UIFactory.label("Description", faction.description, 18, button)
		description.Font = Theme.BodyFont
		description.TextColor3 = Theme.SubTextColor
		description.Position = UDim2.fromOffset(0, 44)

		factionButtons[faction.id] = button
	end

	local backButton = UIFactory.button("BackButton", "Назад", Theme.SecondaryButtonColor, factionPanel)
	backButton.Size = UDim2.new(0.5, 0, 0, 44)
	backButton.TextSize = 22
	backButton.LayoutOrder = #FactionConfig.List + 1

	-- Шаг 4. Окно настроек: выбор размера интерфейса и кнопка «Закрыть».
	local settingsScreen = UIFactory.screen("SettingsScreen", gui)
	settingsScreen.Active = true -- открытое из паузы окно не пропускает клики в мир
	local settingsPanel = UIFactory.panel("Panel", UDim2.fromOffset(480, 580), settingsScreen)
	UIFactory.verticalList(settingsPanel, 16)

	local settingsTitle = UIFactory.label("Title", "Настройки", 36, settingsPanel)
	settingsTitle.LayoutOrder = 1

	local scaleLabel = UIFactory.label("ScaleLabel", "Размер интерфейса", 22, settingsPanel)
	scaleLabel.Font = Theme.BodyFont
	scaleLabel.TextColor3 = Theme.SubTextColor
	scaleLabel.LayoutOrder = 2

	-- Ряд кнопок-переключателей, по одной на каждый вариант из Theme.ScaleOptions.
	local scaleRow = Instance.new("Frame")
	scaleRow.Name = "ScaleRow"
	scaleRow.BackgroundTransparency = 1
	scaleRow.Size = UDim2.new(1, 0, 0, 48)
	scaleRow.LayoutOrder = 3
	scaleRow.Parent = settingsPanel

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Padding = UDim.new(0, 10)
	rowLayout.Parent = scaleRow

	local scaleButtons: { [string]: TextButton } = {}
	local optionCount = #Theme.ScaleOptions
	for index, option in Theme.ScaleOptions do
		local button = UIFactory.button(option.id .. "ScaleButton", option.label, Theme.SecondaryButtonColor, scaleRow)
		-- Делим ширину ряда поровну с учётом отступов между кнопками.
		button.Size = UDim2.new(1 / optionCount, -10 * (optionCount - 1) / optionCount, 1, 0)
		button.TextSize = 20
		button.LayoutOrder = index
		scaleButtons[option.id] = button
	end

	-- Громкость музыки: «−», шкала, «+» и переключатель «без звука».
	local volumeLabel = UIFactory.label("VolumeLabel", "Громкость музыки", 22, settingsPanel)
	volumeLabel.Font = Theme.BodyFont
	volumeLabel.TextColor3 = Theme.SubTextColor
	volumeLabel.LayoutOrder = 4

	local volumeRow = Instance.new("Frame")
	volumeRow.Name = "VolumeRow"
	volumeRow.BackgroundTransparency = 1
	volumeRow.Size = UDim2.new(1, 0, 0, 40)
	volumeRow.LayoutOrder = 5
	volumeRow.Parent = settingsPanel

	local volumeLayout = Instance.new("UIListLayout")
	volumeLayout.FillDirection = Enum.FillDirection.Horizontal
	volumeLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	volumeLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	volumeLayout.SortOrder = Enum.SortOrder.LayoutOrder
	volumeLayout.Padding = UDim.new(0, 8)
	volumeLayout.Parent = volumeRow

	local volumeMinus = UIFactory.button("VolumeMinus", "−", Theme.SecondaryButtonColor, volumeRow)
	volumeMinus.Size = UDim2.fromOffset(44, 40)
	volumeMinus.TextSize = 26
	volumeMinus.LayoutOrder = 1

	local volumeBar = Instance.new("Frame")
	volumeBar.Name = "VolumeBar"
	volumeBar.Size = UDim2.fromOffset(190, 14)
	volumeBar.BackgroundColor3 = Theme.BackgroundColor
	volumeBar.BorderSizePixel = 0
	volumeBar.LayoutOrder = 2
	volumeBar.Parent = volumeRow

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(1, 0)
	barCorner.Parent = volumeBar

	local barStroke = Instance.new("UIStroke")
	barStroke.Color = Theme.PanelStroke
	barStroke.Thickness = 1
	barStroke.Transparency = Theme.StrokeTransparency
	barStroke.Parent = volumeBar

	local volumeFill = Instance.new("Frame")
	volumeFill.Name = "Fill"
	volumeFill.Size = UDim2.fromScale(0, 1)
	volumeFill.BackgroundColor3 = Theme.PanelStroke
	volumeFill.BorderSizePixel = 0
	volumeFill.Parent = volumeBar

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = volumeFill

	local volumePlus = UIFactory.button("VolumePlus", "+", Theme.SecondaryButtonColor, volumeRow)
	volumePlus.Size = UDim2.fromOffset(44, 40)
	volumePlus.TextSize = 26
	volumePlus.LayoutOrder = 3

	local muteButton = UIFactory.button("MuteButton", "", Theme.SecondaryButtonColor, volumeRow)
	muteButton.Size = UDim2.fromOffset(120, 40)
	muteButton.TextSize = 18
	muteButton.LayoutOrder = 4

	-- Переключатели: звуки стройки (отдельно от музыки) и анимации стройки.
	local sfxButton = UIFactory.button("SfxButton", "", Theme.SecondaryButtonColor, settingsPanel)
	sfxButton.Size = UDim2.new(0.85, 0, 0, 38)
	sfxButton.TextSize = 19
	sfxButton.LayoutOrder = 6

	local animationButton = UIFactory.button("AnimationButton", "", Theme.SecondaryButtonColor, settingsPanel)
	animationButton.Size = UDim2.new(0.85, 0, 0, 38)
	animationButton.TextSize = 19
	animationButton.LayoutOrder = 7

	-- Размер строительной плиты: кнопка перебирает пресеты, под ней — ответ сервера.
	local plotSizeButton = UIFactory.button("PlotSizeButton", "", Theme.SecondaryButtonColor, settingsPanel)
	plotSizeButton.Size = UDim2.new(0.85, 0, 0, 38)
	plotSizeButton.TextSize = 19
	plotSizeButton.LayoutOrder = 8

	local plotSizeNote = UIFactory.label("PlotSizeNote", "", 16, settingsPanel)
	plotSizeNote.Font = Theme.BodyFont
	plotSizeNote.TextColor3 = Theme.SubTextColor
	plotSizeNote.Size = UDim2.new(1, 0, 0, 20)
	plotSizeNote.LayoutOrder = 9
	plotSizeNote.Visible = false -- скрытая строка не занимает места в списке

	local closeSettingsButton = UIFactory.button("CloseButton", "Закрыть", Theme.PrimaryButtonColor, settingsPanel)
	closeSettingsButton.Size = UDim2.new(0.5, 0, 0, 44)
	closeSettingsButton.TextSize = 22
	closeSettingsButton.LayoutOrder = 10

	-- Шаг 5. Добавляем GUI в PlayerGui последним, когда иерархия уже собрана.
	-- Меню паузы (во время игры): продолжить, настройки, выход в главное меню.
	local pauseScreen = UIFactory.screen("PauseScreen", gui)
	pauseScreen.Active = true -- клики по затемнению не уходят в мир (не ставят блоки)
	local pausePanel = UIFactory.panel("Panel", UDim2.fromOffset(400, 300), pauseScreen)
	UIFactory.verticalList(pausePanel, 16)

	local pauseTitle = UIFactory.label("Title", "Меню паузы", 36, pausePanel)
	pauseTitle.LayoutOrder = 1

	local resumeButton = UIFactory.button("ResumeButton", "Продолжить", Theme.PrimaryButtonColor, pausePanel)
	resumeButton.Size = UDim2.new(0.8, 0, 0, 56)
	resumeButton.LayoutOrder = 2

	local pauseSettingsButton = UIFactory.button("SettingsButton", "Настройки", Theme.SecondaryButtonColor, pausePanel)
	pauseSettingsButton.Size = UDim2.new(0.8, 0, 0, 48)
	pauseSettingsButton.TextSize = 24
	pauseSettingsButton.LayoutOrder = 3

	local exitButton = UIFactory.button("ExitButton", "Выйти в главное меню", Theme.SecondaryButtonColor, pausePanel)
	exitButton.Size = UDim2.new(0.8, 0, 0, 48)
	exitButton.TextSize = 22
	exitButton.LayoutOrder = 4

	gui.Parent = playerGui

	return {
		gui = gui,
		uiScale = uiScale,
		titleScreen = titleScreen,
		factionScreen = factionScreen,
		settingsScreen = settingsScreen,
		playButton = playButton,
		settingsButton = settingsButton,
		backButton = backButton,
		closeSettingsButton = closeSettingsButton,
		factionButtons = factionButtons,
		scaleButtons = scaleButtons,
		volumeLabel = volumeLabel,
		volumeMinus = volumeMinus,
		volumePlus = volumePlus,
		volumeFill = volumeFill,
		muteButton = muteButton,
		sfxButton = sfxButton,
		animationButton = animationButton,
		plotSizeButton = plotSizeButton,
		plotSizeNote = plotSizeNote,
		pauseScreen = pauseScreen,
		resumeButton = resumeButton,
		pauseSettingsButton = pauseSettingsButton,
		exitButton = exitButton,
	}
end

return MenuView
