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

function BuildSize.clamp(value: number, minSize: number, maxSize: number?): number
	return round3(math.clamp(value, minSize, maxSize or BuildConfig.MaxBlockSize))
end

-- Допустимые размеры формы по осям. Базовые формы: общий минимум (basicMin) и максимум.
-- Составные растягиваются пропорционально, поэтому пределы считаются от их родного размера.
function BuildSize.limits(shape: BuildConfig.Shape, basicMin: number?): (Vector3, Vector3)
	local ceiling = Vector3.one * BuildConfig.MaxBlockSize
	if shape.prefab then
		return shape.size * BuildConfig.PrefabMinScale, (shape.size * BuildConfig.PrefabMaxScale):Min(ceiling)
	end
	return Vector3.one * (basicMin or BuildConfig.MinBlockSize), ceiling
end

-- Сервер: размер от клиента — конечный Vector3 в пределах [minSize, maxSize] по каждой оси.
function BuildSize.isValid(value: unknown, minSize: Vector3, maxSize: Vector3): boolean
	if typeof(value) ~= "Vector3" then
		return false
	end
	local size = value :: Vector3
	if size.X ~= size.X or size.Y ~= size.Y or size.Z ~= size.Z then
		return false -- NaN
	end
	local low, high = minSize - Vector3.one * EPSILON, maxSize + Vector3.one * EPSILON
	return size.X >= low.X
		and size.Y >= low.Y
		and size.Z >= low.Z
		and size.X <= high.X
		and size.Y <= high.Y
		and size.Z <= high.Z
end

-- Кнопки −/+: к ближайшему кратному шага сетки в нужную сторону (при сетке «0» — мелкий шаг).
function BuildSize.nudge(value: number, gridStep: number, direction: number, minSize: number, maxSize: number?): number
	local step = if gridStep > 0 then gridStep else BuildConfig.FreeSizeStep
	local ratio = value / step
	local nextValue = if direction > 0
		then (math.floor(ratio + EPSILON) + 1) * step
		else (math.ceil(ratio - EPSILON) - 1) * step
	return BuildSize.clamp(nextValue, minSize, maxSize)
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
