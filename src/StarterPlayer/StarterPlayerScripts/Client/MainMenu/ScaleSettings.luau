--!strict
-- ScaleSettings: общий размер интерфейса (значение UIScale).
-- Главное меню записывает сюда выбранный в «Настройках» размер, а остальные
-- экраны (например, строительная панель) читают его и подписываются на изменения,
-- поэтому весь интерфейс масштабируется одинаково.

local Theme = require(script.Parent.Theme)

local ScaleSettings = {}

local changed = Instance.new("BindableEvent")
local current = 1

-- Стартовое значение: вариант по умолчанию из Theme.
for _, option in Theme.ScaleOptions do
	if option.id == Theme.DefaultScaleId then
		current = option.scale
	end
end

-- Сигнал: (scale: number, instant: boolean). instant = true: применить без анимации.
ScaleSettings.Changed = changed.Event

function ScaleSettings.get(): number
	return current
end

function ScaleSettings.set(scale: number, instant: boolean?)
	current = scale
	changed:Fire(scale, instant == true)
end

return ScaleSettings
