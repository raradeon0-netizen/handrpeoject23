--!strict
-- PlotResizer (сервер): смена размера строительной плиты между пресетами PlotConfig.SizePresets.
-- Центр плиты остаётся на месте, поэтому постройки не сдвигаются; бордюр, угловые элементы
-- и сетка перестраиваются под новые края (PlotBuilder.decorate).
-- Проверки стройки (BuildGrid.isInsideArea, PlotOwnership.getOwnerAt) читают plot.Size
-- напрямую, поэтому новые границы начинают действовать сразу.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildConfig = require(ReplicatedStorage.Shared.BuildConfig)
local BuildGrid = require(ReplicatedStorage.Shared.BuildGrid)
local PlotConfig = require(ReplicatedStorage.Shared.PlotConfig)

local PlotBuilder = require(script.Parent.PlotBuilder)

local EPSILON = 0.01

local PlotResizer = {}

function PlotResizer.isPreset(size: unknown): boolean
	for _, preset in PlotConfig.SizePresets do
		if preset.size == size then
			return true
		end
	end
	return false
end

-- Помещаются ли все постройки в зону стройки плиты размера size.
local function blocksFit(plot: Part, size: number): boolean
	local blocks = plot:FindFirstChild(BuildConfig.BlocksFolderName)
	if not blocks then
		return true
	end
	local limit = size / 2 - BuildConfig.EdgeInset + EPSILON
	for _, block in blocks:GetChildren() do
		local center, extents = BuildGrid.getBlockBounds(plot, block)
		if center and extents then
			if math.abs(center.X) + extents.X / 2 > limit or math.abs(center.Z) + extents.Z / 2 > limit then
				return false
			end
		end
	end
	return true
end

-- Меняет размер плиты. Возвращает false и причину, если размер недопустим или при уменьшении
-- какие-то постройки оказались бы за краем.
function PlotResizer.resize(plot: Part, size: number, factionId: string): (boolean, string?)
	if not PlotResizer.isPreset(size) then
		return false, "Такого размера плиты нет"
	end
	if math.abs(plot.Size.X - size) < EPSILON then
		return true, nil
	end
	if size < plot.Size.X and not blocksFit(plot, size) then
		return false, "Плиту не уменьшить: сначала уберите постройки у её краёв"
	end

	plot.Size = Vector3.new(size, PlotConfig.PlotThickness, size)
	PlotBuilder.decorate(plot, factionId)
	return true, nil
end

return PlotResizer
