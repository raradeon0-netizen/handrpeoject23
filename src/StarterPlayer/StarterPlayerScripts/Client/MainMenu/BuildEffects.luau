--!strict
-- BuildEffects (клиент): «сочные» эффекты строительства — анимации, частицы и звуки.
-- Сервер после каждого действия шлёт всем событие BuildConfig.EffectRemoteName, а оформляет
-- его каждый клиент сам, поэтому режим эффектов каждый выбирает в настройках только для себя:
--   «Выкл»    — блоки появляются и исчезают мгновенно, без анимаций и частиц;
--   «Обычная» — лёгкое падение с отскоком и пыль, искры выреза, золотое мерцание, плавный снос;
--   «Мощная»  — блок с размаху падает с высоты и сплющивается при ударе, камера вздрагивает,
--               от основания расходятся кольцо пыли, каменная крошка и тёплая ударная волна,
--               а удар звучит ниже и громче.
-- Звук действия слышит только тот, кто его совершил (AudioController.playSfx).

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local BuildConfig = require(ReplicatedStorage.Shared.BuildConfig)
local BuildGrid = require(ReplicatedStorage.Shared.BuildGrid)
local AudioController = require(script.Parent.AudioController)
local BuildCameraController = require(script.Parent.BuildCameraController)

export type Mode = "Off" | "Normal" | "Heavy"

type Original = { cframe: CFrame, size: Vector3 }

local DROP_HEIGHT = 1.5
local DROP_INFO = TweenInfo.new(0.38, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SHIMMER_INFO = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SHIMMER_COLOR = Color3.fromRGB(255, 215, 120)
local DUST_COLOR = Color3.fromRGB(226, 198, 140)
local SPARK_COLOR = Color3.fromRGB(255, 224, 160)
local STONE_COLOR = Color3.fromRGB(170, 162, 150)
local MAX_EMITTER_SIDE = 24

-- ===== Режим «Мощная» =====
local HEAVY_DROP_HEIGHT = 4
local HEAVY_DROP_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In) -- разгон до удара
local SQUASH_INFO = TweenInfo.new(0.24, Enum.EasingStyle.Linear)
local SQUASH_WIDEN = 0.07 -- на сколько основание раздаётся вширь в момент удара
local SQUASH_FLATTEN = 0.09 -- и на сколько блок проседает по высоте
local SHOCKWAVE_INFO = TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SHOCKWAVE_COLOR = Color3.fromRGB(255, 214, 150)
local SHOCKWAVE_GROWTH = 10 -- на сколько студов волна расходится от основания
local CHIP_COLOR = Color3.fromRGB(255, 205, 110)
local RING_EMITTERS = 10
local SHAKE_TIME = 0.28
-- Тяжёлый звук: ниже тоном и громче обычного.
local HEAVY_IMPACT_SOUND: AudioController.SfxStyle = { pitch = NumberRange.new(0.78, 0.85), gain = 1.4 }
local HEAVY_SOUND: AudioController.SfxStyle = { pitch = NumberRange.new(0.84, 0.92), gain = 1.2 }

-- Какой звук сопровождает действие.
local SOUNDS: { [string]: string } = {
	Place = "Place",
	Carve = "Carve",
	Paint = "Paint",
	Tablet = "Paint",
	Remove = "Remove",
}

local BuildEffects = {}

-- Режимы в порядке переключения кнопкой в настройках.
BuildEffects.Modes = {
	{ id = "Off", label = "Выкл" },
	{ id = "Normal", label = "Обычная" },
	{ id = "Heavy", label = "Мощная" },
} :: { { id: Mode, label: string } }

local started = false
local mode: Mode = "Normal"
local folder: Folder? = nil

function BuildEffects.getMode(): Mode
	return mode
end

function BuildEffects.setMode(value: Mode)
	mode = value
end

function BuildEffects.modeLabel(value: string): string
	for _, option in BuildEffects.Modes do
		if option.id == value then
			return option.label
		end
	end
	return value
end

-- Следующий режим по кругу: «Выкл» -> «Обычная» -> «Мощная» -> «Выкл».
function BuildEffects.cycleMode(): Mode
	for index, option in BuildEffects.Modes do
		if option.id == mode then
			mode = BuildEffects.Modes[index % #BuildEffects.Modes + 1].id
			break
		end
	end
	return mode
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

-- direction / spread — куда и каким конусом летят частицы (по умолчанию — во все стороны).
local function burst(
	parent: Part,
	count: number,
	color: Color3,
	size: number,
	speed: NumberRange,
	lifetime: NumberRange,
	gravity: number,
	glow: number,
	direction: Enum.NormalId?,
	spread: number?
)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	emitter.EmissionDirection = direction or Enum.NormalId.Top
	emitter.SpreadAngle = Vector2.new(spread or 180, spread or 180)
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

-- ===== Режим «Обычная» =====

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

	if mode == "Off" then
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

-- ===== Режим «Мощная» =====

-- «Вес» блока от 0 до 1 по его объёму: куб 4×4×4 — около трети, большая стена — больше половины.
local function weightOf(size: Vector3): number
	return math.clamp((size.X * size.Y * size.Z) ^ (1 / 3) / 12, 0.05, 1)
end

-- Камера вздрагивает только у того, кто совершил действие.
local function shake(own: boolean, strength: number)
	if own then
		BuildCameraController.shake(strength, SHAKE_TIME)
	end
end

-- Точное положение и размер каждой детали блока: к ним блок вернётся после сплющивания.
local function capture(block: Instance): { [BasePart]: Original }
	local originals: { [BasePart]: Original } = {}
	if block:IsA("BasePart") then
		originals[block] = { cframe = block.CFrame, size = block.Size }
	end
	for _, descendant in block:GetDescendants() do
		if descendant:IsA("BasePart") then
			originals[descendant] = { cframe = descendant.CFrame, size = descendant.Size }
		end
	end
	return originals
end

-- Нижняя точка блока под его центром: отсюда расходятся пыль и ударная волна.
local function groundPoint(cframe: CFrame, size: Vector3, originals: { [BasePart]: Original }?): Vector3
	local lowest = cframe.Y - BuildGrid.getExtents(cframe.Rotation, size).Y / 2
	if originals then
		for _, original in originals do
			local bottom = original.cframe.Y - BuildGrid.getExtents(original.cframe.Rotation, original.size).Y / 2
			lowest = math.min(lowest, bottom)
		end
	end
	return Vector3.new(cframe.X, lowest, cframe.Z)
end

-- Удар: основание на миг раздаётся вширь, блок проседает, затем всё возвращается к точным размерам.
local function squash(block: Instance, originals: { [BasePart]: Original }, base: Vector3)
	local function apply(widen: number, flatten: number)
		local stretch = Vector3.new(1 + widen, 1 - flatten, 1 + widen)
		for part, original in originals do
			if part.Parent then
				local rotation = original.cframe.Rotation
				local offset = (original.cframe.Position - base) * stretch
				part.Size = Vector3.new(
					original.size.X * (rotation.XVector * stretch).Magnitude,
					original.size.Y * (rotation.YVector * stretch).Magnitude,
					original.size.Z * (rotation.ZVector * stretch).Magnitude
				)
				part.CFrame = rotation + (base + offset)
			end
		end
	end
	animate(SQUASH_INFO, function(alpha: number)
		if block.Parent then
			local pulse = math.sin(math.pi * alpha)
			apply(SQUASH_WIDEN * pulse, SQUASH_FLATTEN * pulse)
		end
	end, function()
		for part, original in originals do
			if part.Parent then
				part.Size = original.size
				part.CFrame = original.cframe
			end
		end
	end)
end

-- Кольцо из RING_EMITTERS источников вокруг основания: клубы пыли стелются наружу,
-- мелкая золотистая крошка разлетается выше и дальше.
local function impactRing(cframe: CFrame, size: Vector3, base: Vector3, weight: number)
	local _, yaw = cframe:ToOrientation()
	local flat = CFrame.new(base) * CFrame.Angles(0, yaw, 0)
	local radiusX, radiusZ = size.X / 2 + 0.4, size.Z / 2 + 0.4
	local dustCount = 2 + math.round(weight * 3)
	for index = 1, RING_EMITTERS do
		local angle = (index / RING_EMITTERS) * math.pi * 2
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local position = flat:PointToWorldSpace(Vector3.new(radiusX * direction.X, 0.2, radiusZ * direction.Z))
		local outward = flat:VectorToWorldSpace(direction)
		local source = emitterPart(CFrame.lookAt(position, position + outward + Vector3.yAxis * 0.5), Vector3.one * 0.4)
		burst(
			source,
			dustCount,
			DUST_COLOR,
			1.8,
			NumberRange.new(6, 11),
			NumberRange.new(0.6, 1.1),
			1,
			0.1,
			Enum.NormalId.Front,
			30
		)
		burst(
			source,
			2,
			CHIP_COLOR,
			0.16,
			NumberRange.new(9, 16),
			NumberRange.new(0.35, 0.6),
			28,
			0.5,
			Enum.NormalId.Front,
			45
		)
	end
end

-- Тёплая ударная волна: плоский светящийся диск расходится по земле и гаснет.
local function shockwave(base: Vector3, size: Vector3)
	local diameter = math.max(size.X, size.Z) + 1
	local wave = Instance.new("Part")
	wave.Name = "Shockwave"
	wave.Anchored = true
	wave.CanCollide = false
	wave.CanQuery = false
	wave.CanTouch = false
	wave.CastShadow = false
	wave.Material = Enum.Material.Neon
	wave.Color = SHOCKWAVE_COLOR
	wave.Transparency = 0.45
	wave.Size = Vector3.new(0.15, diameter, diameter)
	-- Ось цилиндра — X детали: ставим её вертикально.
	wave.CFrame = CFrame.new(base + Vector3.yAxis * 0.1) * CFrame.Angles(0, 0, math.rad(90))

	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Cylinder
	mesh.Parent = wave
	wave.Parent = getFolder()

	local growth = (diameter + SHOCKWAVE_GROWTH) / diameter
	TweenService:Create(mesh, SHOCKWAVE_INFO, { Scale = Vector3.new(1, growth, growth) }):Play()
	TweenService:Create(wave, SHOCKWAVE_INFO, { Transparency = 1 }):Play()
	Debris:AddItem(wave, SHOCKWAVE_INFO.Time + 0.1)
end

-- Установка: разгон с высоты, удар (звук, тряска, кольцо пыли, волна) и сплющивание.
local function heavyPlace(block: Instance?, cframe: CFrame, size: Vector3, own: boolean)
	local weight = weightOf(size)
	local target = if block and block:IsA("PVInstance") then block else nil
	local originals = if target then capture(target) else nil
	local base = groundPoint(cframe, size, originals)

	local function impact()
		if own then
			AudioController.playSfx(SOUNDS.Place, HEAVY_IMPACT_SOUND)
		end
		shake(own, 0.06 + 0.28 * weight)
		impactRing(cframe, size, base, weight)
		shockwave(base, size)
		if target and originals and target.Parent then
			squash(target, originals, base)
		end
	end

	if not target then
		impact()
		return
	end
	local applied = Vector3.yAxis * HEAVY_DROP_HEIGHT
	BuildGrid.shiftBlock(target, applied)
	animate(HEAVY_DROP_INFO, function(alpha: number)
		if target.Parent then
			local wanted = Vector3.yAxis * (HEAVY_DROP_HEIGHT * (1 - alpha))
			BuildGrid.shiftBlock(target, wanted - applied)
			applied = wanted
		end
	end, function()
		if target.Parent then
			BuildGrid.shiftBlock(target, -applied)
		end
		impact()
	end)
end

-- Вырез: больше крошки и искр, плюс золотистые осколки и лёгкая тряска.
local function heavyCarve(cframe: CFrame, size: Vector3, own: boolean)
	local volume = emitterPart(cframe, size)
	local count = math.clamp(math.round((size.X + size.Y + size.Z) * 4.5), 20, 70)
	burst(volume, count, STONE_COLOR, 0.8, NumberRange.new(4, 11), NumberRange.new(0.5, 1), 16, 0)
	burst(volume, count, SPARK_COLOR, 0.16, NumberRange.new(9, 18), NumberRange.new(0.25, 0.5), 30, 0.9)
	burst(volume, math.round(count / 2), CHIP_COLOR, 0.2, NumberRange.new(8, 15), NumberRange.new(0.4, 0.7), 34, 0.5)
	shake(own, 0.04 + 0.14 * weightOf(size))
end

-- Снос: блок рассыпается в облако пыли и обломков.
local function heavyRemove(block: Instance, own: boolean)
	local cframe: CFrame, size: Vector3
	if block:IsA("Model") then
		cframe, size = block:GetBoundingBox()
	elseif block:IsA("BasePart") then
		cframe, size = block.CFrame, block.Size
	else
		return
	end
	local volume = emitterPart(cframe, size)
	local count = math.clamp(math.round((size.X + size.Y + size.Z) * 3), 16, 60)
	burst(volume, count, DUST_COLOR, 1.6, NumberRange.new(3, 8), NumberRange.new(0.6, 1.1), 2, 0.1)
	burst(volume, count, STONE_COLOR, 0.35, NumberRange.new(5, 12), NumberRange.new(0.5, 0.9), 34, 0)
	shake(own, 0.04 + 0.16 * weightOf(size))
end

-- ===== Обработка события сервера =====

local function onEffect(kind: unknown, userId: unknown, instance: unknown, cframe: unknown, size: unknown)
	if typeof(kind) ~= "string" then
		return
	end
	local own = userId == Players.LocalPlayer.UserId
	local heavy = mode == "Heavy"
	-- Экземпляр может ещё не доехать до клиента — тогда анимация блока просто пропускается.
	local target = if typeof(instance) == "Instance" then instance else nil
	local box: CFrame? = if typeof(cframe) == "CFrame" then cframe else nil
	local boxSize: Vector3? = if typeof(size) == "Vector3" then size else nil

	-- Тяжёлая установка сама сыграет звук в момент удара о землю.
	local heavyDrop = heavy and kind == "Place" and box ~= nil and boxSize ~= nil
	local soundName = SOUNDS[kind]
	if soundName and own and not heavyDrop then
		local weighty = heavy and (kind == "Carve" or kind == "Remove")
		AudioController.playSfx(soundName, if weighty then HEAVY_SOUND else nil)
	end

	if kind == "Remove" then
		if target then
			if heavy then
				heavyRemove(target, own)
			end
			vanish(target)
		end
		return
	end
	if mode == "Off" then
		return
	end

	if kind == "Place" then
		if heavy and box and boxSize then
			heavyPlace(target, box, boxSize, own)
		else
			if target then
				dropIn(target)
			end
			if box and boxSize then
				dust(box, boxSize)
			end
		end
	elseif kind == "Carve" then
		if box and boxSize then
			if heavy then
				heavyCarve(box, boxSize, own)
			else
				sparks(box, boxSize)
			end
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
