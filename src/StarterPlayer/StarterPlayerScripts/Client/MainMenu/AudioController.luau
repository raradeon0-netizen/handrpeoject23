--!strict
-- AudioController (клиент): спокойная фоновая музыка в главном меню и во время игры.
--
-- ┌─ СВОЯ МУЗЫКА ───────────────────────────────────────────────────────────────────────┐
-- │ Чтобы заменить трек, вставьте его id в MUSIC_ASSET_ID ниже в виде                    │
-- │ "rbxassetid://123456789". Трек должен быть доступен вашему месту: свой загруженный    │
-- │ звук или звук из библиотеки Roblox (Creator Store → Audio).                           │
-- └───────────────────────────────────────────────────────────────────────────────────────┘
--
-- По умолчанию играет «Ancient Paths» (Matthew Cang, альбом The Ambient Works) из официальной
-- библиотеки Roblox — лицензионная музыка APM Music, бесплатная для всех мест.
-- Громкость и «без звука» меняются в окне «Настройки» (MenuController).

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local MUSIC_ASSET_ID = "rbxassetid://1840833726"

local DEFAULT_VOLUME = 0.4 -- 0..1, как на шкале в настройках
local VOLUME_STEP = 0.1
local FADE = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE_IN = TweenInfo.new(2.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local AudioController = {}

AudioController.VolumeStep = VOLUME_STEP

local changed = Instance.new("BindableEvent")

-- Срабатывает при смене громкости или режима «без звука».
AudioController.Changed = changed.Event

local sound: Sound? = nil
local volume = DEFAULT_VOLUME
local muted = false

local function apply(info: TweenInfo)
	local music = sound
	if music then
		TweenService:Create(music, info, { Volume = if muted then 0 else volume }):Play()
	end
end

-- Создаёт звук и запускает музыку (один раз). Громкость плавно нарастает с нуля.
function AudioController.start()
	if sound then
		return
	end
	local music = Instance.new("Sound")
	music.Name = "BackgroundMusic"
	music.SoundId = MUSIC_ASSET_ID
	music.Looped = true
	music.Volume = 0
	music.Parent = SoundService
	sound = music
	music:Play()
	apply(FADE_IN)
end

function AudioController.getVolume(): number
	return volume
end

function AudioController.isMuted(): boolean
	return muted
end

-- level — 0..1. Любая смена громкости снимает режим «без звука».
function AudioController.setVolume(level: number)
	volume = math.clamp(math.round(level * 100) / 100, 0, 1)
	muted = false
	apply(FADE)
	changed:Fire()
end

function AudioController.setMuted(value: boolean)
	muted = value
	apply(FADE)
	changed:Fire()
end

return AudioController
