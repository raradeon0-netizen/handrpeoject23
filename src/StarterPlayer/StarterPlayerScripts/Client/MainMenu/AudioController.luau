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
--
-- Здесь же короткие звуковые эффекты (playSfx): установка, вырез, покраска, снос и щелчки
-- кнопок. Они выключаются в настройках отдельно от музыки.

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local MUSIC_ASSET_ID = "rbxassetid://1840833726"

local DEFAULT_VOLUME = 0.4 -- 0..1, как на шкале в настройках
local VOLUME_STEP = 0.1
local FADE = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE_IN = TweenInfo.new(2.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Особая подача звука: свой диапазон высоты тона и множитель громкости
-- (например, низкий и громкий удар в режиме анимаций «Мощная»).
export type SfxStyle = {
	pitch: NumberRange,
	gain: number,
}

local AudioController = {}

AudioController.VolumeStep = VOLUME_STEP

local changed = Instance.new("BindableEvent")

-- Срабатывает при смене громкости, режима «без звука» или переключателя звуковых эффектов.
AudioController.Changed = changed.Event

local sound: Sound? = nil
local volume = DEFAULT_VOLUME
local muted = false

-- Звуковые эффекты строительства и интерфейса — звуки из официальной библиотеки Roblox
-- (Pro Sound Effects и Roblox). Чтобы заменить звук, вставьте свой "rbxassetid://…" в поле id.
local SFX: { [string]: { id: string, volume: number } } = {
	Place = { id = "rbxassetid://9118608146", volume = 0.6 }, -- камень о камень: блок встал на место
	Carve = { id = "rbxassetid://9119071703", volume = 0.5 }, -- скрежет: резак прошёл по камню
	Paint = { id = "rbxassetid://9116394545", volume = 0.45 }, -- мягкий перезвон: покраска и скрижаль
	Remove = { id = "rbxassetid://9118770616", volume = 0.5 }, -- осыпающийся песок: блок снесён
	Click = { id = "rbxassetid://15675032796", volume = 0.35 }, -- щелчок кнопки интерфейса
	-- Режим прогулки (FootstepController)
	StepStone = { id = "rbxassetid://9118248653", volume = 0.4 }, -- шаг по камню
	StepSand = { id = "rbxassetid://9118768256", volume = 0.35 }, -- шаг по песку
	Land = { id = "rbxassetid://9113474578", volume = 0.3 }, -- приземление после прыжка
}

-- Высота тона каждый раз немного другая: частые действия не звучат монотонно.
local PITCH_MIN, PITCH_MAX = 0.95, 1.05

local sfxEnabled = true
local sfxSounds: { [string]: Sound } = {}

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

-- Проигрывает звуковой эффект по имени из таблицы SFX (если эффекты не выключены в настройках).
function AudioController.playSfx(name: string, style: SfxStyle?)
	local spec = SFX[name]
	if not sfxEnabled or not spec then
		return
	end
	local effect = sfxSounds[name]
	if not effect then
		local created = Instance.new("Sound")
		created.Name = name .. "Sfx"
		created.SoundId = spec.id
		created.Volume = spec.volume
		created.Parent = SoundService
		sfxSounds[name] = created
		effect = created
	end
	local low = if style then style.pitch.Min else PITCH_MIN
	local high = if style then style.pitch.Max else PITCH_MAX
	effect.PlaybackSpeed = low + math.random() * (high - low)
	effect.Volume = spec.volume * (if style then style.gain else 1)
	SoundService:PlayLocalSound(effect) -- играет копию: звуки могут накладываться друг на друга
end

function AudioController.isSfxEnabled(): boolean
	return sfxEnabled
end

-- Звуки стройки и интерфейса выключаются отдельно от музыки.
function AudioController.setSfxEnabled(value: boolean)
	sfxEnabled = value
	changed:Fire()
end

return AudioController
