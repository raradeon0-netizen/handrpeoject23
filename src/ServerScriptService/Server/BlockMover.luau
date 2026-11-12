--!strict
-- BlockMover (сервер): перенос уже поставленного блока (Part, CSG-результат или составная Model)
-- на смещение, присланное 3D-стрелками клиента. Блок сдвигается целиком, без поворота.
-- Клиенту не доверяем: новое место проверяется по границам участка и по пересечениям.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildGrid = require(ReplicatedStorage.Shared.BuildGrid)

local BlockMover = {}

-- localOffset — смещение в координатах участка. Возвращает false и причину, если двигать нельзя.
function BlockMover.move(plot: BasePart, block: Instance, localOffset: Vector3): (boolean, string?)
	if not block:IsA("PVInstance") then
		return false, nil
	end
	local center, extents = BuildGrid.getBlockBounds(plot, block)
	if not center or not extents then
		return false, nil
	end

	local offset = BuildGrid.roundVector(localOffset)
	if not BuildGrid.isInsideArea(plot, center + offset, extents) then
		return false, "Сюда передвинуть нельзя: блок выходит за плиту"
	end
	if BuildGrid.isMoveBlocked(plot, block, offset) then
		return false, "Сюда передвинуть нельзя: мешает другой блок"
	end

	BuildGrid.shiftBlock(block, plot.CFrame:VectorToWorldSpace(offset))
	return true, nil
end

return BlockMover
