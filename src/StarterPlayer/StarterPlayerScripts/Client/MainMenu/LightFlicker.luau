--!strict
-- LightFlicker (клиент): живое мерцание огня светильников.
-- Сервер помечает PointLight тегом BuildConfig.FlickerTag и кладёт в атрибуты базовую яркость
-- и размах мерцания (LightEffects). Яркость меняется только локально, по сети ничего не идёт.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BuildConfig = require(ReplicatedStorage.Shared.BuildConfig)
local LightEffects = require(ReplicatedStorage.Shared.LightEffects)

local FLICKER_SPEED = 7

local LightFlicker = {}

local started = false
local lights: { [PointLight]: number } = {} -- свет -> собственная фаза шума

local function track(instance: Instance)
	if instance:IsA("PointLight") then
		lights[instance] = math.random() * 1000
	end
end

local function untrack(instance: Instance)
	if instance:IsA("PointLight") then
		lights[instance] = nil
	end
end

function LightFlicker.start()
	if started then
		return
	end
	started = true

	CollectionService:GetInstanceAddedSignal(BuildConfig.FlickerTag):Connect(track)
	CollectionService:GetInstanceRemovedSignal(BuildConfig.FlickerTag):Connect(untrack)
	for _, instance in CollectionService:GetTagged(BuildConfig.FlickerTag) do
		track(instance)
	end

	RunService.Heartbeat:Connect(function()
		local now = os.clock() * FLICKER_SPEED
		for light, phase in lights do
			if light.Enabled then
				local base = light:GetAttribute(LightEffects.BaseBrightnessAttribute)
				local amount = light:GetAttribute(LightEffects.FlickerAttribute)
				if typeof(base) == "number" and typeof(amount) == "number" then
					-- Два наложенных шума: медленное «дыхание» пламени и быстрая дрожь.
					local wave = math.noise(now, phase) + 0.5 * math.noise(now * 2.7, phase + 31)
					light.Brightness = base * (1 + amount * wave)
				end
			end
		end
	end)
end

return LightFlicker
