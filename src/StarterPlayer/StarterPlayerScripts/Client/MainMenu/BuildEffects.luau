--!strict
-- BuildEffects (клиент): «сочные» эффекты строительства — анимации, частицы и звуки.
-- Сервер после каждого действия шлёт всем событие BuildConfig.EffectRemoteName, а оформляет
-- его каждый клиент сам, поэтому эффекты можно выключить в настройках только у себя:
--   Place  — блок падает сверху с упругим отскоком, у основания — облачко пыли;
--   Carve  — каменная крошка и искры в объёме выреза;
--   Paint / Tablet — золотое мерцание детали (Highlight, плавно гаснет);
--   Remove — блок быстро сжимается и тает (сервер удаляет его через RemoveEffectTime).
-- Звук действия слышит только тот, кто его совершил (AudioController.playSfx).

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local BuildConfig = require(ReplicatedStorage.Shared.BuildConfig)
local BuildGrid = require(ReplicatedStorage.Shared.BuildGrid)
local AudioController = require(script.Parent.AudioController)

local DROP_HEIGHT = 1.5
local DROP_INFO = TweenInfo.new(0.38, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SHIMMER_INFO = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SHIMMER_COLOR = Color3.fromRGB(255, 215, 120)
local DUST_COLOR = Color3.fromRGB(226, 198, 140)
local SPARK_COLOR = Color3.fromRGB(255, 224, 160)
local STONE_COLOR = Color3.fromRGB(170, 162, 150)
local MAX_EMITTER_SIDE = 24

-- Какой звук сопровождает действие.
local SOUNDS: { [string]: string } = {
	Place = "Place",
	Carve = "Carve",
	Paint = "Paint",
	Tablet = "Paint",
	Remove = "Remove",
}

local BuildEffects = {}

local started = false
local enabled = true
local folder: Folder? = nil

function BuildEffects.isEnabled(): boolean
	return enabled
end

-- Выключенные эффекты: блоки ставятся и исчезают мгновенно, без частиц и мерцания.
function BuildEffects.setEnabled(value: boolean)
	enabled = value
end

local function getFolder(): Folder
	local existing = folder
	if existing and existing.Parent then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = "BuildEffects"
	created.Parent = workspace
	folder = created
	return created
end

-- Плавно ведёт число от 0 до 1 и на каждом шаге зовёт onStep.
local function animate(info: TweenInfo, onStep: (number) -> (), onDone: (() -> ())?)
	local value = Instance.new("NumberValue")
	value.Changed:Connect(onStep)
	local tween = TweenService:Create(value, info, { Value = 1 })
	tween.Completed:Once(function()
		value:Destroy()
		if onDone then
			onDone()
		end
	end)
	tween:Play()
end

-- Невидимый бокс, из объёма которого вылетают частицы; сам исчезает через пару секунд.
local function emitterPart(cframe: CFrame, size: Vector3): Part
	local part = Instance.new("Part")
	part.Name = "Emitter"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(
		math.clamp(size.X, 0.2, MAX_EMITTER_SIDE),
		math.clamp(size.Y, 0.2, MAX_EMITTER_SIDE),
		math.clamp(size.Z, 0.2, MAX_EMITTER_SIDE)
	)
	part.CFrame = cframe
	part.Parent = getFolder()
	Debris:AddItem(part, 2)
	return part
end

local function burst(
	parent: Part,
	count: number,
	color: Color3,
	size: number,
	speed: NumberRange,
	lifetime: NumberRange,
	gravity: number,
	glow: number
)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Speed = speed
	emitter.Lifetime = lifetime
	emitter.Drag = 3
	emitter.Acceleration = Vector3.new(0, -gravity, 0)
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = glow
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size),
		NumberSequenceKeypoint.new(1, size * 0.3),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Parent = parent
	emitter:Emit(count)
end

-- Блок падает с DROP_HEIGHT; Back-сглаживание чуть «проседает» ниже места и возвращается.
local function dropIn(block: Instance)
	if not block:IsA("PVInstance") then
		return
	end
	local applied = Vector3.yAxis * DROP_HEIGHT
	BuildGrid.shiftBlock(block, applied)
	animate(DROP_INFO, function(alpha: number)
		if block.Parent then
			local wanted = Vector3.yAxis * (DROP_HEIGHT * (1 - alpha))
			BuildGrid.shiftBlock(block, wanted - applied)
			applied = wanted
		end
	end, function()
		if block.Parent then
			BuildGrid.shiftBlock(block, -applied) -- точно на место, без накопленной погрешности
		end
	end)
end

local function dust(cframe: CFrame, size: Vector3)
	local base = emitterPart(cframe * CFrame.new(0, -size.Y / 2, 0), Vector3.new(size.X, 0.2, size.Z))
	local count = math.clamp(math.round(size.X * size.Z * 0.6), 8, 28)
	burst(base, count, DUST_COLOR, 0.9, NumberRange.new(2, 5), NumberRange.new(0.5, 0.9), 3, 0.1)
end

local function sparks(cframe: CFrame, size: Vector3)
	local volume = emitterPart(cframe, size)
	local count = math.clamp(math.round((size.X + size.Y + size.Z) * 2.5), 12, 40)
	burst(volume, count, STONE_COLOR, 0.5, NumberRange.new(3, 8), NumberRange.new(0.4, 0.8), 18, 0)
	burst(volume, count, SPARK_COLOR, 0.14, NumberRange.new(7, 14), NumberRange.new(0.2, 0.45), 30, 0.9)
end

local function shimmer(part: Instance)
	local highlight = Instance.new("Highlight")
	highlight.Name = "Shimmer"
	highlight.FillColor = SHIMMER_COLOR
	highlight.OutlineColor = SHIMMER_COLOR
	highlight.FillTransparency = 0.35
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = part
	highlight.Parent = getFolder()
	TweenService:Create(highlight, SHIMMER_INFO, { FillTransparency = 1, OutlineTransparency = 1 }):Play()
	Debris:AddItem(highlight, SHIMMER_INFO.Time + 0.1)
end

-- Сервер уже сделал блок «призрачным» и вскоре удалит; здесь он сжимается и тает.
-- Без анимаций блок просто сразу пропадает из вида.
local function vanish(block: Instance)
	local parts: { BasePart } = {}
	if block:IsA("BasePart") then
		table.insert(parts, block)
	end
	for _, descendant in block:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		elseif descendant:IsA("SurfaceGui") then
			descendant.Enabled = false
		elseif descendant:IsA("PointLight") then
			descendant.Enabled = false
		elseif descendant:IsA("Fire") then
			descendant.Enabled = false
		elseif descendant:IsA("ParticleEmitter") then
			descendant.Enabled = false
		end
	end

	if not enabled then
		for _, part in parts do
			part.LocalTransparencyModifier = 1
		end
		return
	end

	local startSize = if block:IsA("BasePart") then block.Size else Vector3.zero
	local info = TweenInfo.new(BuildConfig.RemoveEffectTime * 0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	animate(info, function(alpha: number)
		if not block.Parent then
			return
		end
		local scale = math.max(1 - 0.9 * alpha, 0.05)
		if block:IsA("Model") then
			block:ScaleTo(scale)
		elseif block:IsA("BasePart") then
			block.Size = startSize * scale
		end
		for _, part in parts do
			part.LocalTransparencyModifier = alpha
		end
	end)
end

local function onEffect(kind: unknown, userId: unknown, instance: unknown, cframe: unknown, size: unknown)
	if typeof(kind) ~= "string" then
		return
	end
	local soundName = SOUNDS[kind]
	if soundName and userId == Players.LocalPlayer.UserId then
		AudioController.playSfx(soundName)
	end

	-- Экземпляр может ещё не доехать до клиента — тогда эффект просто пропускается.
	local target = if typeof(instance) == "Instance" then instance else nil
	if kind == "Remove" then
		if target then
			vanish(target)
		end
		return
	end
	if not enabled then
		return
	end

	local hasBox = typeof(cframe) == "CFrame" and typeof(size) == "Vector3"
	if kind == "Place" then
		if target then
			dropIn(target)
		end
		if hasBox then
			dust(cframe :: CFrame, size :: Vector3)
		end
	elseif kind == "Carve" then
		if hasBox then
			sparks(cframe :: CFrame, size :: Vector3)
		end
	elseif kind == "Paint" or kind == "Tablet" then
		if target then
			shimmer(target)
		end
	end
end

function BuildEffects.start()
	if started then
		return
	end
	started = true
	-- RemoteEvent создаёт сервер; ждём его в фоне, чтобы не задерживать меню.
	task.spawn(function()
		local remote = ReplicatedStorage:WaitForChild("Shared"):WaitForChild(BuildConfig.EffectRemoteName, 30)
		if remote and remote:IsA("RemoteEvent") then
			remote.OnClientEvent:Connect(onEffect)
		end
	end)
end

return BuildEffects
