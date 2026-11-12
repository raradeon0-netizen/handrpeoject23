--!strict
-- LightEffects: «живые» эффекты светильников — тёплый PointLight, пламя и искры.
-- BlockLibrary вешает эффект на светящуюся деталь префаба (Piece.effect), сервер включает
-- и выключает светильник целиком (setEnabled). Мерцание света считает клиент (LightFlicker):
-- свет помечается тегом, а сервер не шлёт по сети изменение яркости каждый кадр.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildConfig = require(ReplicatedStorage.Shared.BuildConfig)

export type Effect = {
	range: number, -- радиус света в студах
	brightness: number,
	color: Color3,
	flicker: number, -- размах мерцания (доля яркости)
	fire: { size: number, heat: number }?, -- пламя (Fire)
	sparks: number, -- искр в секунду (ParticleEmitter)
}

local LightEffects = {}

LightEffects.BaseBrightnessAttribute = "BaseBrightness"
LightEffects.FlickerAttribute = "Flicker"

local EFFECT_ATTRIBUTE = "LightEffect" -- стоит на созданных здесь PointLight / Fire / ParticleEmitter
local OFF_ATTRIBUTE = "LightsOff" -- стоит на блоке, пока светильник погашен

local EFFECTS: { [string]: Effect } = {
	-- Настенный факел
	Torch = {
		range = 24,
		brightness = 1.6,
		color = Color3.fromRGB(255, 160, 70),
		flicker = 0.22,
		fire = { size = 3, heat = 7 },
		sparks = 3,
	},
	-- Храмовая жаровня
	Brazier = {
		range = 36,
		brightness = 2,
		color = Color3.fromRGB(255, 150, 60),
		flicker = 0.18,
		fire = { size = 6, heat = 10 },
		sparks = 6,
	},
	-- Кристалл обелиска: ровное золотое сияние без пламени
	Crystal = {
		range = 50,
		brightness = 1.8,
		color = Color3.fromRGB(255, 205, 110),
		flicker = 0.06,
		fire = nil,
		sparks = 2,
	},
}

local function mark(instance: Instance)
	instance:SetAttribute(EFFECT_ATTRIBUTE, true)
end

-- Вешает эффект на светящуюся деталь. Неизвестный id молча пропускается.
function LightEffects.apply(part: BasePart, effectId: string)
	local effect = EFFECTS[effectId]
	if not effect then
		return
	end

	local light = Instance.new("PointLight")
	light.Name = "Glow"
	light.Range = effect.range
	light.Brightness = effect.brightness
	light.Color = effect.color
	light.Shadows = false
	light:SetAttribute(LightEffects.BaseBrightnessAttribute, effect.brightness)
	light:SetAttribute(LightEffects.FlickerAttribute, effect.flicker)
	mark(light)
	CollectionService:AddTag(light, BuildConfig.FlickerTag)
	light.Parent = part

	local fire = effect.fire
	if fire then
		local flames = Instance.new("Fire")
		flames.Name = "Flames"
		flames.Size = fire.size
		flames.Heat = fire.heat
		flames.Color = effect.color
		flames.SecondaryColor = Color3.fromRGB(150, 40, 10)
		mark(flames)
		flames.Parent = part
	end

	if effect.sparks > 0 then
		local sparks = Instance.new("ParticleEmitter")
		sparks.Name = "Sparks"
		sparks.Rate = effect.sparks
		sparks.Lifetime = NumberRange.new(1, 2.2)
		sparks.Speed = NumberRange.new(1.5, 3.5)
		sparks.SpreadAngle = Vector2.new(25, 25)
		sparks.Acceleration = Vector3.new(0, 2, 0)
		sparks.EmissionDirection = Enum.NormalId.Top
		sparks.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.18),
			NumberSequenceKeypoint.new(1, 0),
		})
		sparks.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		sparks.Color = ColorSequence.new(effect.color)
		sparks.LightEmission = 1
		mark(sparks)
		sparks.Parent = part
	end
end

-- Зажигает или гасит все эффекты блока. Возвращает false, если это не светильник.
function LightEffects.setEnabled(block: Instance, enabled: boolean): boolean
	local found = false
	for _, descendant in block:GetDescendants() do
		if descendant:GetAttribute(EFFECT_ATTRIBUTE) then
			if descendant:IsA("PointLight") then
				descendant.Enabled = enabled
				found = true
			elseif descendant:IsA("Fire") then
				descendant.Enabled = enabled
				found = true
			elseif descendant:IsA("ParticleEmitter") then
				descendant.Enabled = enabled
				found = true
			end
		end
	end
	if found then
		block:SetAttribute(OFF_ATTRIBUTE, if enabled then nil else true)
	end
	return found
end

function LightEffects.isOff(block: Instance): boolean
	return block:GetAttribute(OFF_ATTRIBUTE) == true
end

return LightEffects
