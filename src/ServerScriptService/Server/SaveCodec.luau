--!strict
-- SaveCodec (сервер): компактная запись CFrame и Vector3 в сохранение и строгий разбор обратно.
-- Всё, что читается из сохранения, проверяется: не число, NaN или бесконечность — значит nil.

local SaveCodec = {}

local LIMIT = 1e6

local function round(value: number, digits: number): number
	local scale = 10 ^ digits
	return math.round(value * scale) / scale
end

function SaveCodec.number(value: unknown): number?
	if typeof(value) ~= "number" then
		return nil
	end
	local n = value :: number
	if n ~= n or math.abs(n) > LIMIT then
		return nil
	end
	return n
end

local function numbers(value: unknown, count: number): { number }?
	if typeof(value) ~= "table" then
		return nil
	end
	local list = value :: { unknown }
	local result: { number } = table.create(count)
	for index = 1, count do
		local n = SaveCodec.number(list[index])
		if not n then
			return nil
		end
		result[index] = n
	end
	return result
end

function SaveCodec.encodeVector(v: Vector3): { number }
	return { round(v.X, 3), round(v.Y, 3), round(v.Z, 3) }
end

function SaveCodec.decodeVector(value: unknown): Vector3?
	local n = numbers(value, 3)
	return if n then Vector3.new(n[1], n[2], n[3]) else nil
end

-- Положение и три угла Эйлера (XYZ, радианы).
function SaveCodec.encodeCFrame(cframe: CFrame): { number }
	local rx, ry, rz = cframe:ToEulerAnglesXYZ()
	return { round(cframe.X, 3), round(cframe.Y, 3), round(cframe.Z, 3), round(rx, 5), round(ry, 5), round(rz, 5) }
end

function SaveCodec.decodeCFrame(value: unknown): CFrame?
	local n = numbers(value, 6)
	return if n then CFrame.new(n[1], n[2], n[3]) * CFrame.fromEulerAnglesXYZ(n[4], n[5], n[6]) else nil
end

return SaveCodec
