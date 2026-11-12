--!strict
-- PlotAllocator: раздаёт игрокам слоты сетки и считает центр участка по слоту.
-- Ничего не знает ни о Part'ах, ни о фракциях: только номера и координаты.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotConfig = require(ReplicatedStorage.Shared.PlotConfig)

local PlotAllocator = {}

local slotOwner: { [number]: number } = {} -- слот -> UserId
local slotOfUser: { [number]: number } = {} -- UserId -> слот

-- Центр участка для слота: слоты идут рядами по GridColumns штук.
function PlotAllocator.slotCenter(slot: number): Vector3
	local column = slot % PlotConfig.GridColumns
	local row = slot // PlotConfig.GridColumns
	local offset = Vector3.new(column * PlotConfig.GridSpacing, 0, row * PlotConfig.GridSpacing)
	return PlotConfig.GridOrigin + offset
end

-- Выдаёт игроку наименьший свободный слот (освободившиеся слоты переиспользуются).
-- Если слот у игрока уже есть, возвращает его же.
function PlotAllocator.acquire(userId: number): number
	local existing = slotOfUser[userId]
	if existing then
		return existing
	end

	local slot = 0
	while slotOwner[slot] do
		slot += 1
	end

	slotOwner[slot] = userId
	slotOfUser[userId] = slot
	return slot
end

-- Освобождает слот игрока (безопасно вызывать повторно).
function PlotAllocator.release(userId: number)
	local slot = slotOfUser[userId]
	if slot then
		slotOwner[slot] = nil
		slotOfUser[userId] = nil
	end
end

return PlotAllocator
