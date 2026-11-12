--!strict
-- BuildCameraController: свободная строительная камера (Free Build Camera).
-- Включается после того, как сервер построил участок игрока (см. MenuController).
--
-- Управление:
--   WASD            движение вперёд/назад/влево/вправо (по горизонтали, по взгляду)
--   E / Пробел      вверх,  Q / LeftShift: вниз,  LeftCtrl: ускорение
--   ПКМ (зажать)    поворот камеры мышью
--   Колесо мыши     приближение / отдаление (вдоль направления взгляда)
--
-- Плавность: клиент хранит «целевое» положение камеры (его двигает ввод) и каждый
-- кадр в RenderStep догоняет его критически демпфированной пружиной (smoothDamp):
-- старт и остановка без рывков, а при резком вводе камера не дёргается.
-- Границы: камера не уходит дальше BoundsMargin за края плиты, не опускается ниже
-- поверхности плиты и не поднимается выше PlotConfig.BuildHeight.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local PlotConfig = require(ReplicatedStorage.Shared.PlotConfig)

-- Все настройки камеры в одном месте.
local CONFIG = {
	MoveSpeed = 70, -- studs/сек
	BoostMultiplier = 2.5, -- множитель скорости при зажатом LeftCtrl
	ZoomStep = 18, -- studs за один «щелчок» колеса
	MouseSensitivity = 0.0045, -- радиан на пиксель

	MinPitch = math.rad(-85), -- нельзя смотреть строго вниз/вверх (нет переворота)
	MaxPitch = math.rad(70),

	BoundsMargin = 30, -- насколько можно вылететь за край плиты
	MinHeight = 4, -- минимальная высота над поверхностью плиты
	MaxHeight = PlotConfig.BuildHeight, -- максимальная высота над поверхностью плиты

	StartOutset = 25, -- стартовая точка: на столько студов за краем плиты
	StartHeightRatio = 0.7, -- стартовая высота как доля размера плиты (200 -> 140)

	IntroSmoothTime = 0.9, -- «длинная» плавность при перелёте на стартовую позицию
	MoveSmoothTime = 0.14, -- обычная плавность движения
	RotateSmoothTime = 0.07, -- обычная плавность поворота
	IntroDuration = 2.5, -- за сколько секунд плавность меняется с длинной на обычную

	PlotWaitTimeout = 5, -- сколько секунд ждать появления участка на клиенте
}

local KEYS = {
	Forward = { Enum.KeyCode.W },
	Back = { Enum.KeyCode.S },
	Left = { Enum.KeyCode.A },
	Right = { Enum.KeyCode.D },
	Up = { Enum.KeyCode.E, Enum.KeyCode.Space },
	Down = { Enum.KeyCode.Q, Enum.KeyCode.LeftShift },
	Boost = { Enum.KeyCode.LeftControl },
}

local BIND_NAME = "BuildCameraController"

type Session = {
	plot: Part,
	camera: Camera,
	minBounds: Vector3,
	maxBounds: Vector3,
	-- Текущее (отображаемое) состояние камеры и скорости пружин.
	pos: Vector3,
	posVelocity: Vector3,
	yaw: number,
	yawVelocity: number,
	pitch: number,
	pitchVelocity: number,
	-- Цель, к которой камера плавно стремится.
	targetPos: Vector3,
	targetYaw: number,
	targetPitch: number,
	elapsed: number,
	rotating: boolean,
	connections: { RBXScriptConnection },
}

local BuildCameraController = {}

local session: Session? = nil

-- Короткая тряска камеры (тяжёлый удар блока): размах в студах и сколько секунд осталось.
local shakeStrength = 0
local shakeLeft = 0
local shakeLength = 0

-- ===== Математика =====

-- Критически демпфированная пружина (как SmoothDamp в Unity): без перелёта и рывков.
local function smoothDamp(current: number, target: number, velocity: number, smoothTime: number, dt: number): (number, number)
	local omega = 2 / math.max(smoothTime, 0.0001)
	local x = omega * dt
	local decay = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
	local change = current - target
	local temp = (velocity + omega * change) * dt
	return target + (change + temp) * decay, (velocity - omega * temp) * decay
end

local function smoothDampVector(
	current: Vector3,
	target: Vector3,
	velocity: Vector3,
	smoothTime: number,
	dt: number
): (Vector3, Vector3)
	local omega = 2 / math.max(smoothTime, 0.0001)
	local x = omega * dt
	local decay = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
	local change = current - target
	local temp = (velocity + omega * change) * dt
	return target + (change + temp) * decay, (velocity - omega * temp) * decay
end

-- Приводит угол к диапазону [-pi, pi], чтобы камера поворачивалась кратчайшим путём.
local function wrapAngle(angle: number): number
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

local function clampToBounds(s: Session, position: Vector3): Vector3
	return Vector3.new(
		math.clamp(position.X, s.minBounds.X, s.maxBounds.X),
		math.clamp(position.Y, s.minBounds.Y, s.maxBounds.Y),
		math.clamp(position.Z, s.minBounds.Z, s.maxBounds.Z)
	)
end

-- ===== Ввод =====

local function isAnyDown(keys: { Enum.KeyCode }): boolean
	for _, key in keys do
		if UserInputService:IsKeyDown(key) then
			return true
		end
	end
	return false
end

local function axis(positive: { Enum.KeyCode }, negative: { Enum.KeyCode }): number
	return (if isAnyDown(positive) then 1 else 0) - (if isAnyDown(negative) then 1 else 0)
end

local function setRotating(s: Session, rotating: boolean)
	s.rotating = rotating
	-- Пока зажата ПКМ, курсор «прибит» к месту, а мы читаем только смещение мыши.
	UserInputService.MouseBehavior = if rotating then Enum.MouseBehavior.LockCurrentPosition else Enum.MouseBehavior.Default
end

-- Отключает/включает стандартное управление персонажем (иначе он бегает по WASD).
local function setCharacterControls(enabled: boolean)
	local ok, err = pcall(function()
		local playerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")
		local playerModule = require(playerScripts:WaitForChild("PlayerModule")) :: any
		local controls = playerModule:GetControls()
		if enabled then
			controls:Enable()
		else
			controls:Disable()
		end
	end)
	if not ok then
		warn(`[BuildCameraController] Не удалось переключить управление персонажем: {err}`)
	end
end

-- ===== Покадровое обновление =====

local function step(dt: number)
	local s = session
	if not s then
		return
	end
	dt = math.min(dt, 0.1) -- защита от больших скачков при лагах

	s.elapsed += dt

	-- Шаг 1. Ввод двигает ЦЕЛЬ (если игрок не печатает в чат).
	if UserInputService:GetFocusedTextBox() == nil then
		local forward = axis(KEYS.Forward, KEYS.Back)
		local strafe = axis(KEYS.Right, KEYS.Left)
		local vertical = axis(KEYS.Up, KEYS.Down)

		-- Горизонтальные оси берём по yaw, вертикаль: мировая «вверх».
		local flat = CFrame.fromOrientation(0, s.targetYaw, 0)
		local direction = flat.LookVector * forward + flat.RightVector * strafe + Vector3.yAxis * vertical

		if direction.Magnitude > 0 then
			local speed = CONFIG.MoveSpeed * (if isAnyDown(KEYS.Boost) then CONFIG.BoostMultiplier else 1)
			s.targetPos = clampToBounds(s, s.targetPos + direction.Unit * speed * dt)
		end
	end

	-- Шаг 2. Плавность: сначала длинная (перелёт на старт), потом обычная.
	local introProgress = math.clamp(s.elapsed / CONFIG.IntroDuration, 0, 1)
	local moveTime = CONFIG.IntroSmoothTime + (CONFIG.MoveSmoothTime - CONFIG.IntroSmoothTime) * introProgress
	local rotateTime = CONFIG.IntroSmoothTime + (CONFIG.RotateSmoothTime - CONFIG.IntroSmoothTime) * introProgress

	s.pos, s.posVelocity = smoothDampVector(s.pos, s.targetPos, s.posVelocity, moveTime, dt)
	s.yaw, s.yawVelocity = smoothDamp(s.yaw, s.targetYaw, s.yawVelocity, rotateTime, dt)
	s.pitch, s.pitchVelocity = smoothDamp(s.pitch, s.targetPitch, s.pitchVelocity, rotateTime, dt)

	-- Шаг 3. Применяем к камере (позиция дополнительно зажата границами).
	s.pos = clampToBounds(s, s.pos)
	local cframe = CFrame.new(s.pos) * CFrame.fromOrientation(s.pitch, s.yaw, 0)

	-- Шаг 4. Тряска: случайный сдвиг в плоскости экрана, быстро затухающий. Само положение
	-- камеры (s.pos) не меняется, поэтому после тряски она стоит ровно там же.
	if shakeLeft > 0 then
		shakeLeft -= dt
		local fade = math.max(shakeLeft, 0) / shakeLength
		local reach = shakeStrength * fade * fade
		cframe *= CFrame.new((math.random() - 0.5) * 2 * reach, (math.random() - 0.5) * 2 * reach, 0)
	end
	s.camera.CFrame = cframe
end

-- ===== Публичный API =====

-- Выключает камеру и возвращает обычное управление.
function BuildCameraController.stop()
	local s = session
	if not s then
		return
	end
	session = nil -- сначала обнуляем, чтобы step() больше ничего не делал

	RunService:UnbindFromRenderStep(BIND_NAME)
	for _, connection in s.connections do
		connection:Disconnect()
	end
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	s.camera.CameraType = Enum.CameraType.Custom
	setCharacterControls(true)
end

-- Встряхивает камеру: strength — размах в студах, duration — длительность в секундах.
-- Более слабый толчок не перебивает ещё не затихший сильный.
function BuildCameraController.shake(strength: number, duration: number)
	local remaining = if shakeLength > 0 then shakeStrength * math.max(shakeLeft, 0) / shakeLength else 0
	if strength >= remaining and duration > 0 then
		shakeStrength = strength
		shakeLeft = duration
		shakeLength = duration
	end
end

function BuildCameraController.isActive(): boolean
	return session ~= nil
end

-- Включает камеру для данного участка.
function BuildCameraController.start(plot: Part)
	BuildCameraController.stop()

	local camera = workspace.CurrentCamera
	if not camera then
		warn("[BuildCameraController] Нет CurrentCamera")
		return
	end

	-- Шаг 1. Границы: края плиты ± BoundsMargin, высота от плиты до MaxHeight.
	local half = plot.Size / 2
	local center = plot.Position
	local surfaceY = center.Y + half.Y
	local minBounds = Vector3.new(
		center.X - half.X - CONFIG.BoundsMargin,
		surfaceY + CONFIG.MinHeight,
		center.Z - half.Z - CONFIG.BoundsMargin
	)
	local maxBounds = Vector3.new(
		center.X + half.X + CONFIG.BoundsMargin,
		surfaceY + CONFIG.MaxHeight,
		center.Z + half.Z + CONFIG.BoundsMargin
	)

	-- Шаг 2. Стартовая точка: над южным краем плиты, взгляд на центр. Так видна вся плита.
	local startHeight = math.min(plot.Size.X * CONFIG.StartHeightRatio, CONFIG.MaxHeight)
	local startPos = Vector3.new(center.X, surfaceY + startHeight, center.Z + half.Z + CONFIG.StartOutset)
	local lookTarget = Vector3.new(center.X, surfaceY, center.Z)
	local startPitch, startYaw = CFrame.lookAt(startPos, lookTarget):ToOrientation()

	-- Шаг 3. Текущее состояние берём у обычной камеры, чтобы перелёт начался без скачка.
	local currentPitch, currentYaw = camera.CFrame:ToOrientation()
	local currentPos = camera.CFrame.Position

	local s: Session = {
		plot = plot,
		camera = camera,
		minBounds = minBounds,
		maxBounds = maxBounds,
		pos = currentPos,
		posVelocity = Vector3.zero,
		yaw = currentYaw,
		yawVelocity = 0,
		pitch = currentPitch,
		pitchVelocity = 0,
		targetPos = startPos,
		targetYaw = currentYaw + wrapAngle(startYaw - currentYaw), -- кратчайший поворот
		targetPitch = startPitch,
		elapsed = 0,
		rotating = false,
		connections = {},
	}
	session = s

	-- Шаг 4. Ввод мышью: ПКМ крутит камеру, колесо двигает вдоль взгляда.
	table.insert(
		s.connections,
		UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			if not processed and input.UserInputType == Enum.UserInputType.MouseButton2 then
				setRotating(s, true)
			end
		end)
	)
	table.insert(
		s.connections,
		UserInputService.InputEnded:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton2 then
				setRotating(s, false)
			end
		end)
	)
	table.insert(
		s.connections,
		UserInputService.InputChanged:Connect(function(input: InputObject, processed: boolean)
			if input.UserInputType == Enum.UserInputType.MouseMovement and s.rotating then
				s.targetYaw -= input.Delta.X * CONFIG.MouseSensitivity
				s.targetPitch =
					math.clamp(s.targetPitch - input.Delta.Y * CONFIG.MouseSensitivity, CONFIG.MinPitch, CONFIG.MaxPitch)
			elseif input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
				local look = CFrame.fromOrientation(s.targetPitch, s.targetYaw, 0).LookVector
				s.targetPos = clampToBounds(s, s.targetPos + look * input.Position.Z * CONFIG.ZoomStep)
			end
		end)
	)
	-- Окно потеряло фокус при зажатой ПКМ: отпускание не придёт, сбрасываем сами.
	table.insert(
		s.connections,
		UserInputService.WindowFocusReleased:Connect(function()
			setRotating(s, false)
		end)
	)
	-- Участок удалён (например, игрок выходит): камеру выключаем.
	table.insert(s.connections, plot.Destroying:Connect(BuildCameraController.stop))

	-- Шаг 5. Берём камеру на себя, отключаем бег персонажа и запускаем покадровый цикл.
	camera.CameraType = Enum.CameraType.Scriptable
	setCharacterControls(false)
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, step)
end

-- Ищет участок локального игрока среди Workspace.Plots по атрибуту владельца.
local function findOwnPlot(): Part?
	local folder = workspace:WaitForChild(PlotConfig.FolderName, CONFIG.PlotWaitTimeout)
	if not folder then
		return nil
	end

	local userId = Players.LocalPlayer.UserId
	local deadline = os.clock() + CONFIG.PlotWaitTimeout
	repeat
		for _, child in folder:GetChildren() do
			if child:IsA("Part") and child:GetAttribute(PlotConfig.Attributes.OwnerUserId) == userId then
				return child
			end
		end
		task.wait(0.1)
	until os.clock() >= deadline

	return nil
end

-- Вызывается после того, как сервер выдал участок: находит его и включает камеру.
function BuildCameraController.enter(): boolean
	local plot = findOwnPlot()
	if not plot then
		warn("[BuildCameraController] Участок игрока не найден, камера не включена")
		return false
	end

	BuildCameraController.start(plot)
	return true
end

-- Участок текущей сессии камеры (нужен BuildController).
function BuildCameraController.getPlot(): Part?
	local s = session
	return if s then s.plot else nil
end

return BuildCameraController
