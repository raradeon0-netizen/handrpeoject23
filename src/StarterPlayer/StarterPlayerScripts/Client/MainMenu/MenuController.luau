--!strict
-- MenuController: логика меню. Переключает экраны и обрабатывает кнопки.
-- Состояния: "Title" -> "FactionSelect" -> закрыто (игрок в мире),
-- плюс "Settings" (открывается с титульного экрана).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local PlotConfig = require(ReplicatedStorage.Shared.PlotConfig)
local MenuView = require(script.Parent.MenuView)
local AudioController = require(script.Parent.AudioController)
local BuildEffects = require(script.Parent.BuildEffects)
local TopHudController = require(script.Parent.TopHudController)
local BuildCameraController = require(script.Parent.BuildCameraController)
local BuildHudController = require(script.Parent.BuildHudController)
local BuildController = require(script.Parent.BuildController)
local Teleporter = require(script.Parent.Teleporter)
local ScaleSettings = require(script.Parent.ScaleSettings)
local Theme = require(script.Parent.Theme)

type State = "Title" | "FactionSelect" | "Settings" | "Pause" | "Closed"

-- Клавиши меню паузы (Escape зарезервирован за меню Roblox).
local PAUSE_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.Tab] = true,
	[Enum.KeyCode.P] = true,
}

local MenuController = {}

function MenuController.start(playerGui: PlayerGui)
	local view = MenuView.build(playerGui)
	local buildHud = BuildHudController.start(playerGui) -- строительная панель (скрыта до выбора фракции)
	local busy = false -- защита от двойного клика во время телепорта
	local inGame = false -- игрок на участке: работает меню паузы
	local currentState: State = "Title"
	local settingsReturn: State = "Title" -- куда вернуться из окна настроек
	local refreshSettings: (() -> ())? = nil -- обновляет подписи настроек при открытии окна

	-- Показывает только нужный экран.
	local function setState(state: State)
		currentState = state
		if state == "Settings" and refreshSettings then
			refreshSettings()
		end
		view.pauseScreen.Visible = state == "Pause"
		-- Пока открыто любое окно меню, редактор не реагирует на клавиши и клики.
		BuildController.setPaused(state ~= "Closed")
		view.titleScreen.Visible = state == "Title"
		view.factionScreen.Visible = state == "FactionSelect"
		view.settingsScreen.Visible = state == "Settings"
		view.gui.Enabled = state ~= "Closed"
	end

	-- Применяет размер интерфейса: плавно меняет UIScale и подсвечивает
	-- выбранную кнопку обводкой (фон кнопок занят hover-эффектом UIFactory).
	local function applyScale(optionId: string, instant: boolean?)
		for _, option in Theme.ScaleOptions do
			local button = view.scaleButtons[option.id]
			local stroke = button:FindFirstChildOfClass("UIStroke")
			local selected = option.id == optionId

			if stroke then
				stroke.Color = if selected then Theme.SelectedStroke else Theme.PanelStroke
				stroke.Thickness = if selected then Theme.StrokeThickness + 2 else Theme.StrokeThickness
			end

			if selected then
				ScaleSettings.set(option.scale, instant) -- общий масштаб для остальных экранов
				if instant then
					view.uiScale.Scale = option.scale
				else
					TweenService:Create(view.uiScale, Theme.TweenInfo, { Scale = option.scale }):Play()
				end
			end
		end
	end

	-- «Настройки» и «Закрыть»: открыть окно и вернуться в главное меню.
	view.settingsButton.Activated:Connect(function()
		settingsReturn = "Title"
		setState("Settings")
	end)
	view.closeSettingsButton.Activated:Connect(function()
		setState(settingsReturn)
	end)

	-- Кнопки размера интерфейса.
	for optionId, button in view.scaleButtons do
		button.Activated:Connect(function()
			applyScale(optionId)
		end)
	end

	-- «Играть»: переходим к выбору фракции.
	view.playButton.Activated:Connect(function()
		setState("FactionSelect")
	end)

	-- «Назад»: возвращаемся на титульный экран.
	view.backButton.Activated:Connect(function()
		setState("Title")
	end)

	-- Выбор фракции: закрываем меню, сервер строит участок и телепортирует персонажа,
	-- затем включается свободная строительная камера.
	for factionId, button in view.factionButtons do
		button.Activated:Connect(function()
			if busy then
				return
			end
			busy = true
			setState("Closed")

			if Teleporter.toFaction(factionId) then
				-- Участок готов: включаем строительную камеру, вместе с ней появляется панель.
				if BuildCameraController.enter() then
					buildHud.show()
					inGame = true
					-- Строительный редактор: призрак, установка, резак и удаление блоков.
					local plot = BuildCameraController.getPlot()
					if plot then
						task.spawn(BuildController.start, plot, buildHud)
					end
				end
			else
				setState("FactionSelect") -- не получилось: вернуть меню
			end
			busy = false
		end)
	end

	-- ===== Громкость музыки (окно «Настройки») =====
	local function refreshVolume()
		local level = AudioController.getVolume()
		local muted = AudioController.isMuted()
		view.volumeLabel.Text = if muted
			then "Громкость музыки: без звука"
			else string.format("Громкость музыки: %d%%", math.round(level * 100))
		view.muteButton.Text = if muted then "Включить" else "Без звука"
		TweenService:Create(view.volumeFill, Theme.TweenInfo, { Size = UDim2.fromScale(if muted then 0 else level, 1) })
			:Play()
	end

	view.volumeMinus.Activated:Connect(function()
		AudioController.setVolume(AudioController.getVolume() - AudioController.VolumeStep)
	end)
	view.volumePlus.Activated:Connect(function()
		AudioController.setVolume(AudioController.getVolume() + AudioController.VolumeStep)
	end)
	view.muteButton.Activated:Connect(function()
		AudioController.setMuted(not AudioController.isMuted())
	end)
	AudioController.Changed:Connect(refreshVolume)
	refreshVolume()

	-- ===== Звуки и анимации стройки (окно «Настройки») =====
	local function refreshToggles()
		local sfxOn = AudioController.isSfxEnabled()
		local animationMode = BuildEffects.getMode()
		local animationsOn = animationMode ~= "Off"
		view.sfxButton.Text = "Звуки стройки (SFX): " .. (if sfxOn then "Вкл" else "Выкл")
		view.animationButton.Text = "Анимации стройки: " .. BuildEffects.modeLabel(animationMode)
		for button, on in { [view.sfxButton] = sfxOn, [view.animationButton] = animationsOn } do
			local stroke = button:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = if on then Theme.SelectedStroke else Theme.PanelStroke
			end
		end
	end

	view.sfxButton.Activated:Connect(function()
		AudioController.setSfxEnabled(not AudioController.isSfxEnabled())
		refreshToggles()
	end)
	view.animationButton.Activated:Connect(function()
		BuildEffects.cycleMode() -- «Выкл» -> «Обычная» -> «Мощная»
		refreshToggles()
	end)
	refreshToggles()

	-- ===== Размер плиты (окно «Настройки») =====
	local knownPlotSize = PlotConfig.PlotSize
	local resizing = false
	local noteToken = 0

	local function refreshPlotSize()
		local plot = BuildCameraController.getPlot()
		if plot then
			knownPlotSize = math.round(plot.Size.X)
		end
		local label = ""
		for _, preset in PlotConfig.SizePresets do
			if preset.size == knownPlotSize then
				label = " (" .. preset.label .. ")"
			end
		end
		view.plotSizeButton.Text = string.format("Размер плиты: %d×%d%s", knownPlotSize, knownPlotSize, label)
	end
	refreshSettings = refreshPlotSize

	local function showPlotNote(text: string)
		noteToken += 1
		local token = noteToken
		view.plotSizeNote.Text = text
		view.plotSizeNote.Visible = true
		task.delay(4, function()
			if noteToken == token then
				view.plotSizeNote.Visible = false
			end
		end)
	end

	-- Клик выбирает следующий пресет по кругу и просит сервер перестроить плиту.
	view.plotSizeButton.Activated:Connect(function()
		if resizing then
			return
		end
		refreshPlotSize()
		local nextSize = PlotConfig.SizePresets[1].size
		for index, preset in PlotConfig.SizePresets do
			if preset.size == knownPlotSize then
				nextSize = PlotConfig.SizePresets[index % #PlotConfig.SizePresets + 1].size
			end
		end

		resizing = true
		task.spawn(function()
			local remote = ReplicatedStorage.Shared:FindFirstChild(PlotConfig.ResizeRemoteName)
			local ok, success, message, current = false, false, nil, nil
			if remote and remote:IsA("RemoteFunction") then
				ok, success, message, current = pcall(function()
					return remote:InvokeServer(nextSize)
				end)
			end
			resizing = false
			if typeof(current) == "number" then
				knownPlotSize = math.round(current)
			end
			if not ok then
				showPlotNote("Сервер не ответил, попробуйте ещё раз")
			elseif typeof(message) == "string" then
				showPlotNote(message)
			elseif success == true then
				showPlotNote("Плита перестроена")
			end
			refreshPlotSize()
		end)
	end)
	refreshPlotSize()

	-- ===== Меню паузы =====
	-- Escape занят меню Roblox, поэтому пауза — кнопка «Меню» в углу и клавиши из PAUSE_KEYS.
	local function togglePause()
		if not inGame or busy then
			return
		end
		if currentState == "Closed" then
			setState("Pause")
		elseif currentState == "Pause" then
			setState("Closed")
		end
	end

	TopHudController.PauseRequested:Connect(togglePause)
	UserInputService.InputBegan:Connect(function(input: InputObject)
		if PAUSE_KEYS[input.KeyCode] and not UserInputService:GetFocusedTextBox() then
			togglePause()
		end
	end)

	view.resumeButton.Activated:Connect(function()
		setState("Closed")
	end)

	view.pauseSettingsButton.Activated:Connect(function()
		settingsReturn = "Pause" -- «Закрыть» в настройках вернёт сюда
		setState("Settings")
	end)

	-- Выход в главное меню: выключаем редактор и камеру, прячем панели. Участок остаётся
	-- за игроком: можно вернуться в ту же фракцию или выбрать другую.
	view.exitButton.Activated:Connect(function()
		inGame = false
		BuildController.stop()
		BuildCameraController.stop()
		buildHud.hide()
		setState("Title")
	end)

	applyScale(Theme.DefaultScaleId, true)
	setState("Title")
end

return MenuController
