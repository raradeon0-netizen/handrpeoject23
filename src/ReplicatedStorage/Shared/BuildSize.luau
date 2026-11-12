--!strict
-- BuildSize: пользовательские размеры блока и резака (X, Y, Z).
-- Общий модуль: панель «Точность» считает шаг кнопок −/+, сервер проверяет присланный размер.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildConfig = require(ReplicatedStorage.Shared.BuildConfig)

local BuildSize = {}

local EPSILON = 1e-4

local function round3(x: number): number
	return math.round(x * 1000) / 1000
end

function BuildSize.round(size: Vector3): Vector3
	return Vector3.new(round3(size.X), round3(size.Y), round3(size.Z))
end

function BuildSize.clamp(value: number, minSize: number): number
	return round3(math.clamp(value, minSize, BuildConfig.MaxBlockSize))
end

-- Сервер: размер от клиента — конечный Vector3 в пределах [minSize, MaxBlockSize].
function BuildSize.isValid(value: unknown, minSize: number): boolean
	if typeof(value) ~= "Vector3" then
		return false
	end
	local size = value :: Vector3
	for _, c in { size.X, size.Y, size.Z } do
		if c ~= c or c < minSize - EPSILON or c > BuildConfig.MaxBlockSize + EPSILON then
			return false
		end
	end
	return true
end

-- Кнопки −/+: к ближайшему кратному шага сетки в нужную сторону (при сетке «0» — мелкий шаг).
function BuildSize.nudge(value: number, gridStep: number, direction: number, minSize: number): number
	local step = if gridStep > 0 then gridStep else BuildConfig.FreeSizeStep
	local ratio = value / step
	local nextValue = if direction > 0
		then (math.floor(ratio + EPSILON) + 1) * step
		else (math.ceil(ratio - EPSILON) - 1) * step
	return BuildSize.clamp(nextValue, minSize)
end

-- Текст из поля ввода; запятая допускается как десятичный разделитель.
function BuildSize.parse(text: string): number?
	local n = tonumber((string.gsub(text, ",", ".")))
	if not n or n ~= n or math.abs(n) == math.huge then
		return nil
	end
	return n
end

function BuildSize.format(value: number): string
	return (string.gsub(string.format("%.3f", value), "%.?0+$", ""))
end

-- Полоса резака: ширина и высота от игрока, толщина фиксирована.
function BuildSize.blade(size: Vector3): Vector3
	return Vector3.new(size.X, size.Y, BuildConfig.BladeThickness)
end

return BuildSize
