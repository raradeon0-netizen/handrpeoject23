--!strict
-- TimeOfDayController (клиент): время суток — день, закат, ночь.
-- Освещение меняется только у этого игрока (свойства Lighting на клиенте локальны),
-- поэтому каждый смотрит на свой храм в удобное ему время. Переход плавный.

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

export type Preset = {
	id: string,
	label: string,
	clockTime: number,
	brightness: number,
	ambient: Color3,
	outdoorAmbient: Color3,
	colorShiftTop: Color3,
	exposure: number,
	-- Атмосфера: дымка и оттенок неба у горизонта
	density: number,
	haze: number,
	glare: number,
	atmosphereColor: Color3,
	atmosphereDecay: Color3,
}

local TRANSITION = TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

local TimeOfDayController = {}

TimeOfDayController.Presets = {
	{
		id = "Day",
		label = "День",
		clockTime = 14,
		brightness = 3,
		ambient = Color3.fromRGB(70, 70, 70),
		outdoorAmbient = Color3.fromRGB(128, 128, 128),
		colorShiftTop = Color3.fromRGB(0, 0, 0),
		exposure = 0,
		density = 0.3,
		haze = 0,
		glare = 0,
		atmosphereColor = Color3.fromRGB(199, 199, 199),
		atmosphereDecay = Color3.fromRGB(106, 112, 125),
	},
	{
		id = "Sunset",
		label = "Закат",
		clockTime = 18.2,
		brightness = 2,
		ambient = Color3.fromRGB(92, 66, 54),
		outdoorAmbient = Color3.fromRGB(150, 104, 78),
		colorShiftTop = Color3.fromRGB(255, 150, 70),
		exposure = 0.1,
		density = 0.36,
		haze = 1.8,
		glare = 0.4,
		atmosphereColor = Color3.fromRGB(255, 172, 110),
		atmosphereDecay = Color3.fromRGB(255, 112, 60),
	},
	{
		id = "Night",
		label = "Ночь",
		clockTime = 0,
		brightness = 1.2,
		-- Тёмное окружение: факелы, жаровни и обелиски становятся главным светом.
		ambient = Color3.fromRGB(14, 16, 24),
		outdoorAmbient = Color3.fromRGB(28, 32, 48),
		colorShiftTop = Color3.fromRGB(0, 0, 0),
		exposure = 0,
		density = 0.25,
		haze = 0,
		glare = 0,
		atmosphereColor = Color3.fromRGB(30, 36, 60),
		atmosphereDecay = Color3.fromRGB(10, 12, 24),
	},
} :: { Preset }

TimeOfDayController.DefaultId = "Day"

local currentId: string? = nil

local function getAtmosphere(): Atmosphere
	local existing = Lighting:FindFirstChildOfClass("Atmosphere")
	if existing then
		return existing
	end
	local created = Instance.new("Atmosphere")
	created.Parent = Lighting
	return created
end

function TimeOfDayController.getCurrent(): string?
	return currentId
end

function TimeOfDayController.set(id: string, instant: boolean?)
	local preset: Preset? = nil
	for _, candidate in TimeOfDayController.Presets do
		if candidate.id == id then
			preset = candidate
		end
	end
	if not preset then
		return
	end
	currentId = id

	-- Часы идут кратчайшим путём: к полуночи из вечера — вперёд через 24, а не назад через день.
	local clock = preset.clockTime
	if clock - Lighting.ClockTime < -12 then
		clock += 24
	elseif clock - Lighting.ClockTime > 12 then
		clock -= 24
	end

	local lightingGoal = {
		Brightness = preset.brightness,
		Ambient = preset.ambient,
		OutdoorAmbient = preset.outdoorAmbient,
		ColorShift_Top = preset.colorShiftTop,
		ExposureCompensation = preset.exposure,
	}
	local atmosphereGoal = {
		Density = preset.density,
		Haze = preset.haze,
		Glare = preset.glare,
		Color = preset.atmosphereColor,
		Decay = preset.atmosphereDecay,
	}

	local atmosphere = getAtmosphere()
	local info = if instant then TweenInfo.new(0) else TRANSITION
	TweenService:Create(Lighting, info, lightingGoal):Play()
	TweenService:Create(atmosphere, info, atmosphereGoal):Play()

	-- ClockTime за пределами 0..24 двигаем вручную через промежуточное значение.
	local start = Lighting.ClockTime
	local value = Instance.new("NumberValue")
	value.Value = start
	value.Changed:Connect(function(v: number)
		if currentId == id then
			Lighting.ClockTime = v % 24
		end
	end)
	local clockTween = TweenService:Create(value, info, { Value = clock })
	clockTween.Completed:Once(function()
		if currentId == id then
			Lighting.ClockTime = preset.clockTime
		end
		value:Destroy()
	end)
	clockTween:Play()
end

return TimeOfDayController
