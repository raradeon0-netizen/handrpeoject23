--!strict
-- WalkMotion (клиент): ощущение движения пешком в режиме прогулки.
--   * бег при зажатом LeftShift: скорость 16 -> 24 и плавное расширение поля зрения;
--   * лёгкое покачивание камеры в такт шагам (Humanoid.CameraOffset — работает и от третьего,
--     и от первого лица, не мешая стандартной камере).

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local BIND_NAME = "WalkMotion"
local WALK_SPEED = 16
local SPRINT_SPEED = 24
local SPRINT_KEY = Enum.KeyCode.LeftShift
local WALK_FOV = 70
local SPRINT_FOV = 78
local FOV_RESPONSE = 7 -- чем больше, тем быстрее меняется поле зрения
local BOB_HEIGHT = 0.09 -- студов вверх-вниз
local BOB_SWAY = 0.045 -- студов из стороны в сторону
local BOB_RATE = 0.75 -- радиан фазы на студ пути: два шага — один полный цикл покачивания
local BOB_RESPONSE = 12

local WalkMotion = {}

local humanoid: Humanoid? = nil
local phase = 0

local function step(dt: number)
	local h = humanoid
	local camera = workspace.CurrentCamera
	if not h or not h.Parent or not camera then
		return
	end

	local moving = h.MoveDirection.Magnitude > 0.1
	local grounded = h.FloorMaterial ~= Enum.Material.Air
	local typing = UserInputService:GetFocusedTextBox() ~= nil
	local sprinting = moving and not typing and UserInputService:IsKeyDown(SPRINT_KEY)

	local speed = if sprinting then SPRINT_SPEED else WALK_SPEED
	if h.WalkSpeed ~= speed then
		h.WalkSpeed = speed
	end

	local fov = if sprinting then SPRINT_FOV else WALK_FOV
	camera.FieldOfView += (fov - camera.FieldOfView) * (1 - math.exp(-FOV_RESPONSE * dt))

	local target = Vector3.zero
	if moving and grounded then
		phase += dt * h.WalkSpeed * BOB_RATE
		target = Vector3.new(math.cos(phase / 2) * BOB_SWAY, math.sin(phase) * BOB_HEIGHT, 0)
	end
	h.CameraOffset = h.CameraOffset:Lerp(target, 1 - math.exp(-BOB_RESPONSE * dt))
end

function WalkMotion.stop()
	RunService:UnbindFromRenderStep(BIND_NAME)
	local h = humanoid
	humanoid = nil
	if h and h.Parent then
		h.CameraOffset = Vector3.zero
		h.WalkSpeed = WALK_SPEED
	end
	local camera = workspace.CurrentCamera
	if camera then
		camera.FieldOfView = WALK_FOV
	end
end

-- Включает бег и покачивание для персонажа (вход в режим прогулки и респавн).
function WalkMotion.start(target: Humanoid)
	WalkMotion.stop()
	humanoid = target
	phase = 0
	-- До стандартной камеры: она учитывает CameraOffset в этом же кадре.
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value - 1, step)
end

return WalkMotion
