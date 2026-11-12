--!strict
-- MenuController: логика меню. Переключает экраны и обрабатывает кнопки.
-- Состояния: "Title" -> "FactionSelect" -> закрыто (игрок в мире),
-- плюс "Settings" (открывается с титульного экрана).

local TweenService = game:GetService("TweenService")

local MenuView = require(script.Parent.MenuView)
local BuildCameraController = require(script.Parent.BuildCameraController)
local BuildHudController = require(script.Parent.BuildHudController)
local BuildController = require(script.Parent.BuildController)
local Teleporter = require(script.Parent.Teleporter)
local ScaleSettings = require(script.Parent.ScaleSettings)
local Theme = require(script.Parent.Theme)

type State = "Title" | "FactionSelect" | "Settings" | "Closed"

local MenuController = {}

function MenuController.start(playerGui: PlayerGui)
	local view = MenuView.build(playerGui)
	local buildHud = BuildHudController.start(playerGui) -- строительная панель (скрыта до выбора фракции)
	local busy = false -- защита от двойного клика во время телепорта

	-- Показывает только нужный экран.
	local function setState(state: State)
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
		setState("Settings")
	end)
	view.closeSettingsButton.Activated:Connect(function()
		setState("Title")
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

	applyScale(Theme.DefaultScaleId, true)
	setState("Title")
end

return MenuController
