--!strict
-- WalkController (клиент): переключение между стройкой и прогулкой по своему участку.
--   «Прогулка»: сервер показывает персонажа и ставит его на свободное место у края плиты;
--   свободная камера выключается, камера запирается в виде от первого лица (голова и
--   аксессуары персонажа при этом скрыты самим Roblox), нижняя панель и панель
--   «Точность» прячутся; включаются бег, покачивание камеры (WalkMotion) и шаги (FootstepController).
--   «Стройка»: сервер снова прячет персонажа, возвращаются свободная камера и панели.
--   Курсор в виде от первого лица заперт в центре; он освобождается, пока открыто меню
--   паузы или настройки и пока зажат Alt — так можно нажать кнопки верхней панели.
-- Кнопку в верхней панели и клавишу V подключает MenuController.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local PlotConfig = require(ReplicatedStorage.Shared.PlotConfig)
local BuildCameraController = require(script.Parent.BuildCameraController)
local BuildController = require(script.Parent.BuildController)
local BuildSettingsController = require(script.Parent.BuildSettingsController)
local FootstepController = require(script.Parent.FootstepController)
local WalkMotion = require(script.Parent.WalkMotion)

-- Часть BuildHud, нужная прогулке: спрятать и вернуть нижнюю панель инструментов.
export type Toolbar = {
	setToolbarVisible: (visible: boolean) -> (),
}

local CHARACTER_TIMEOUT = 5

local WalkController = {}

local changed = Instance.new("BindableEvent")

-- (walking: boolean) — режим сменился.
WalkController.Changed = changed.Event

local walking = false
local busy = false
local plot: Part? = nil
local respawnConnection: RBXScriptConnection? = nil

-- ===== Вид от первого лица и курсор =====
-- На прогулке камера заперта в виде от первого лица, а курсор — в центре экрана. Чтобы нажать
-- кнопку интерфейса, курсор освобождается: пока открыто меню (причина "menu") или зажат Alt
-- (причина "alt"). Освобождает его видимая кнопка с Modal = true — штатный способ Roblox,
-- который стандартная камера не перебивает; MouseBehavior выставляется вдобавок к ней.

local CURSOR_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.LeftAlt] = true,
	[Enum.KeyCode.RightAlt] = true,
}

local freeReasons: { [string]: boolean? } = {}
local modalButton: TextButton? = nil
local cursorConnections: { RBXScriptConnection } = {}
local savedMaxZoom: number? = nil

local function getModalButton(): TextButton
	local existing = modalButton
	if existing then
		return existing
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "WalkCursor"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 1
	local button = Instance.new("TextButton")
	button.Name = "Modal"
	button.Text = ""
	button.BackgroundTransparency = 1
	button.Size = UDim2.fromOffset(1, 1)
	button.Position = UDim2.fromOffset(-10, -10) -- за краем экрана: ничего не заслоняет и не ловит клики
	button.Modal = true
	button.Visible = false
	button.Parent = gui
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	modalButton = button
	return button
end

local function applyCursor()
	local free = walking and next(freeReasons) ~= nil
	getModalButton().Visible = free
	if walking then
		UserInputService.MouseBehavior = if free then Enum.MouseBehavior.Default else Enum.MouseBehavior.LockCenter
	end
end

-- Освобождает или снова запирает курсор по названной причине. Действует только на прогулке;
-- причина "menu" запоминается и вне её, чтобы прогулка началась с правильным состоянием.
function WalkController.setCursorFree(reason: string, free: boolean)
	freeReasons[reason] = if free then true else nil
	applyCursor()
end

-- Запирает камеру в виде от первого лица или возвращает обычную.
local function setFirstPerson(locked: boolean)
	local player = Players.LocalPlayer
	local ok = pcall(function()
		player.CameraMode = if locked then Enum.CameraMode.LockFirstPerson else Enum.CameraMode.Classic
	end)
	-- Запасной путь, если режим камеры менять нельзя: не даём отдалить камеру от глаз.
	if not ok and locked then
		savedMaxZoom = player.CameraMaxZoomDistance
		player.CameraMaxZoomDistance = player.CameraMinZoomDistance
	elseif not locked and savedMaxZoom then
		player.CameraMaxZoomDistance = savedMaxZoom
		savedMaxZoom = nil
	end
end

local function watchCursorKeys()
	table.insert(
		cursorConnections,
		UserInputService.InputBegan:Connect(function(input: InputObject)
			if CURSOR_KEYS[input.KeyCode] then
				WalkController.setCursorFree("alt", true)
			end
		end)
	)
	table.insert(
		cursorConnections,
		UserInputService.InputEnded:Connect(function(input: InputObject)
			if CURSOR_KEYS[input.KeyCode] then
				WalkController.setCursorFree("alt", false)
			end
		end)
	)
	-- Окно потеряло фокус с зажатым Alt (Alt+Tab): отпускание клавиши до игры не дойдёт.
	table.insert(
		cursorConnections,
		UserInputService.WindowFocusReleased:Connect(function()
			WalkController.setCursorFree("alt", false)
		end)
	)
end

local function unwatchCursorKeys()
	for _, connection in cursorConnections do
		connection:Disconnect()
	end
	table.clear(cursorConnections)
	freeReasons.alt = nil
end

function WalkController.isWalking(): boolean
	return walking
end

-- Просит сервер показать или спрятать персонажа. true — сервер выполнил.
local function request(value: boolean): boolean
	local remote = ReplicatedStorage.Shared:FindFirstChild(PlotConfig.WalkRemoteName)
	if not remote or not remote:IsA("RemoteFunction") then
		return false
	end
	local ok, result = pcall(function()
		return remote:InvokeServer(value)
	end)
	return ok and result == true
end

local function waitHumanoid(character: Model): Humanoid?
	local humanoid = character:WaitForChild("Humanoid", CHARACTER_TIMEOUT)
	return if humanoid and humanoid:IsA("Humanoid") then humanoid else nil
end

-- Камера и эффекты ходьбы для нынешнего персонажа.
local function attach(character: Model)
	local humanoid = waitHumanoid(character)
	if not humanoid or not walking then
		return
	end
	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = humanoid
	end
	WalkMotion.start(humanoid)
	FootstepController.start(humanoid)
end

local function detach()
	WalkMotion.stop()
	FootstepController.stop()
	if respawnConnection then
		respawnConnection:Disconnect()
		respawnConnection = nil
	end
end

-- Стройка -> прогулка. Возвращает false, если сервер не смог выпустить персонажа.
function WalkController.enter(toolbar: Toolbar): boolean
	local currentPlot = BuildCameraController.getPlot()
	if walking or busy or not currentPlot then
		return false
	end
	busy = true
	if not request(true) then
		busy = false
		BuildSettingsController.notify("Не удалось выйти на прогулку: персонаж ещё не готов")
		return false
	end

	walking = true
	plot = currentPlot
	BuildController.setWalking(true)
	BuildSettingsController.hide()
	toolbar.setToolbarVisible(false)
	BuildCameraController.stop() -- возвращает обычную камеру и управление персонажем
	setFirstPerson(true)
	watchCursorKeys()
	applyCursor()

	local player = Players.LocalPlayer
	if player.Character then
		task.spawn(attach, player.Character)
	end
	-- После гибели (например, падения с плиты) сервер снова ставит персонажа у входа.
	respawnConnection = player.CharacterAdded:Connect(attach)

	busy = false
	changed:Fire(true)
	return true
end

-- Прогулка -> стройка. quiet = true — выход в главное меню: редактор и камеру не возвращаем.
function WalkController.leave(toolbar: Toolbar, quiet: boolean?)
	if not walking or busy then
		return
	end
	busy = true
	detach()
	-- Обычный режим камеры возвращаем до свободной камеры стройки; курсор снова свободен.
	setFirstPerson(false)
	unwatchCursorKeys()
	request(false) -- сервер прячет персонажа и ставит его в центр плиты

	walking = false
	applyCursor() -- прячет модальную кнопку
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	toolbar.setToolbarVisible(true)
	BuildController.setWalking(false)
	local currentPlot = plot
	plot = nil
	if not quiet and currentPlot and currentPlot.Parent then
		BuildCameraController.start(currentPlot)
		BuildSettingsController.show()
	end

	busy = false
	changed:Fire(false)
end

function WalkController.toggle(toolbar: Toolbar)
	if walking then
		WalkController.leave(toolbar)
	else
		WalkController.enter(toolbar)
	end
end

return WalkController
