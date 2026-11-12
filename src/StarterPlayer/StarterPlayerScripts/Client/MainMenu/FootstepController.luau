--!strict
-- FootstepController (клиент): звук шагов в режиме прогулки — по материалу под ногами.
--   * камень (мрамор, сланец, булыжник, кирпич, бетон и всё прочее твёрдое) — чёткий шаг;
--   * песок и песчаник — мягкий хрустящий шаг;
--   * приземление после прыжка — глухой удар.
-- Каждый шаг немного отличается высотой тона и громкостью, а частота шагов растёт со скоростью.
-- Звуки идут через AudioController.playSfx, поэтому выключаются переключателем
-- «Звуки стройки (SFX)» в настройках. Стандартный звук бега Roblox на это время глушится.

local RunService = game:GetService("RunService")

local AudioController = require(script.Parent.AudioController)

local STRIDE = 5.4 -- студов между шагами: при скорости 16 — шаг каждые ~0.34 с
local MIN_SPEED = 0.5 -- медленнее персонаж считается стоящим
local VARIATION = NumberRange.new(0.9, 1.1) -- разброс высоты тона и громкости

-- Материалы, по которым шаг звучит как по песку; всё остальное — как по камню.
local SAND_MATERIALS: { [Enum.Material]: boolean } = {
	[Enum.Material.Sand] = true,
	[Enum.Material.Sandstone] = true,
	[Enum.Material.Ground] = true,
	[Enum.Material.Mud] = true,
	[Enum.Material.Snow] = true,
}

-- Стандартные звуки персонажа, которые заменяются нашими.
local DEFAULT_SOUNDS = { "Running", "Landing" }

local FootstepController = {}

local connections: { RBXScriptConnection } = {}
local muted: { [Sound]: number } = {} -- стандартный звук -> его прежняя громкость
local travelled = 0

local function varied(gain: number): AudioController.SfxStyle
	local spread = VARIATION.Max - VARIATION.Min
	return { pitch = VARIATION, gain = gain * (VARIATION.Min + math.random() * spread) }
end

local function muteDefaults(character: Model)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	for _, name in DEFAULT_SOUNDS do
		local sound = root:FindFirstChild(name)
		if sound and sound:IsA("Sound") then
			muted[sound] = sound.Volume
			sound.Volume = 0
		end
	end
end

function FootstepController.stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for sound, volume in muted do
		if sound.Parent then
			sound.Volume = volume
		end
	end
	table.clear(muted)
end

-- Включает шаги для персонажа (вызывается при входе в режим прогулки и после респавна).
function FootstepController.start(humanoid: Humanoid)
	FootstepController.stop()
	travelled = 0

	local character = humanoid.Parent
	if character and character:IsA("Model") then
		muteDefaults(character)
	end

	table.insert(
		connections,
		RunService.Heartbeat:Connect(function(dt: number)
			local speed = humanoid.MoveDirection.Magnitude * humanoid.WalkSpeed
			local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
			local state = humanoid:GetState()
			local walking = state == Enum.HumanoidStateType.Running or state == Enum.HumanoidStateType.RunningNoPhysics
			if speed < MIN_SPEED or not grounded or not walking then
				travelled = STRIDE * 0.6 -- первый шаг после остановки звучит почти сразу
				return
			end
			travelled += speed * dt
			if travelled >= STRIDE then
				travelled -= STRIDE
				local sand = SAND_MATERIALS[humanoid.FloorMaterial] == true
				AudioController.playSfx(if sand then "StepSand" else "StepStone", varied(1))
			end
		end)
	)

	table.insert(
		connections,
		humanoid.StateChanged:Connect(function(_old: Enum.HumanoidStateType, new: Enum.HumanoidStateType)
			if new == Enum.HumanoidStateType.Landed then
				AudioController.playSfx("Land", varied(1))
			end
		end)
	)
end

return FootstepController
