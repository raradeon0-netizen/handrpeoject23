--!strict
-- BlockCarver (сервер): вырезание формы из блоков с помощью Roblox CSG
-- (Solid Modeling, BasePart:SubtractAsync). Так прорезаются дверные проёмы, окна и ниши.
--
-- Каждый вызов SubtractAsync обёрнут в pcall: на сложных пересечениях
-- (слишком много треугольников, вырожденная геометрия, пустой результат)
-- движок бросает ошибку — тогда блок просто остаётся как был.
--
-- Результат CSG нельзя сохранить «как есть», поэтому каждая деталь помнит свою историю:
-- исходную рамку (где и какого размера она была до первого выреза) и список резаков
-- относительно этой рамки. По ним PlotSerializer воссоздаёт вырезы при загрузке (replay).

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildConfig = require(ReplicatedStorage.Shared.BuildConfig)
local BuildGrid = require(ReplicatedStorage.Shared.BuildGrid)
local SaveCodec = require(script.Parent.SaveCodec)

export type CarveResult = {
	carved: number, -- сколько блоков прорезано
	removed: number, -- сколько блоков резак накрыл целиком (они удалены)
	failed: number, -- на скольких CSG не справился (блок не изменился)
}

-- Один вырез: резак относительно исходной рамки детали.
export type Cut = {
	c: { number }, -- CFrame резака (SaveCodec.encodeCFrame)
	z: { number }, -- размер резака
}

type Outcome = "carved" | "removed" | "failed" | "gone"

local BASE_OFFSET = "BaseOffset" -- CFrame: исходная рамка относительно нынешнего CFrame детали
local BASE_SIZE = "BaseSize" -- Vector3: размер детали до вырезов
local CUTS = "Cuts" -- JSON-список Cut

local MAX_REPLAYED_CUTS = 64

local BlockCarver = {}

-- Исходная рамка детали: её CFrame и размер до вырезов. Перенос блока рамку не ломает —
-- она хранится относительно самой детали.
function BlockCarver.getBase(part: BasePart): (CFrame, Vector3)
	local offset = part:GetAttribute(BASE_OFFSET)
	local size = part:GetAttribute(BASE_SIZE)
	return part.CFrame * (if typeof(offset) == "CFrame" then offset else CFrame.identity),
		if typeof(size) == "Vector3" then size else part.Size
end

-- Вырезы, уже сделанные в детали (в порядке применения).
function BlockCarver.getCuts(part: BasePart): { Cut }
	local raw = part:GetAttribute(CUTS)
	if typeof(raw) ~= "string" then
		return {}
	end
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(raw)
	end)
	return if ok and typeof(decoded) == "table" then decoded else {}
end

local function makeCutter(cframe: CFrame, size: Vector3): Part
	local cutter = Instance.new("Part")
	cutter.Name = "BuildCutter"
	cutter.Size = size
	cutter.CFrame = cframe
	cutter.Anchored = true
	cutter.CanCollide = false
	cutter.CanTouch = false
	cutter.CanQuery = false
	cutter.CastShadow = false
	cutter.Transparency = 1
	return cutter
end

-- Резак чуть больше призрака: без «плёнок» на совпадающих гранях.
-- Тонкую сторону полосы не раздуваем: пропил остаётся ровно в её толщину.
local function inflated(size: Vector3): Vector3
	local function inflate(side: number): number
		return if side > BuildConfig.BladeThickness + 1e-3 then side + BuildConfig.CutterInflate * 2 else side
	end
	return Vector3.new(inflate(size.X), inflate(size.Y), inflate(size.Z))
end

-- Переносит на результат CSG всё, что важно для игры: метки владельца, физику и вид.
local function adopt(union: BasePart, original: BasePart)
	for name, value in original:GetAttributes() do
		union:SetAttribute(name, value)
	end
	union.Name = original.Name
	union.Anchored = true
	union.CanCollide = true
	union.CanQuery = true
	union.CanTouch = true
	union.Material = original.Material
	union.Color = original.Color
	union.Reflectance = original.Reflectance
	if union:IsA("UnionOperation") then
		-- Стенки среза красим цветом блока, а не цветом резака.
		union.UsePartColor = true
	end
	-- Всё, что висело на исходной детали (скрижали, свет и пламя светильника), переезжает на результат.
	for _, child in original:GetChildren() do
		child.Parent = union
	end
end

-- Вычитает резак из одной детали. Результат встаёт на место исходной детали в том же
-- родителе (папка Blocks или Model), поэтому составная модель остаётся цельной.
local function subtract(target: BasePart, cutter: Part): (Outcome, BasePart?)
	local parent = target.Parent
	if not parent then
		return "gone", nil -- деталь уже удалили
	end

	-- Резак накрыл деталь целиком: вычитать нечего (SubtractAsync вернул бы пустоту
	-- и бросил ошибку), просто удаляем её.
	if BuildGrid.isBoxInside(target.CFrame, target.Size, cutter.CFrame, cutter.Size) then
		target:Destroy()
		-- От составной модели ничего не осталось — убираем и пустую оболочку.
		if parent:IsA("Model") and #BuildGrid.blockParts(parent) == 0 then
			parent:Destroy()
		end
		return "removed", nil
	end

	local baseCFrame, baseSize = BlockCarver.getBase(target)
	local cuts = BlockCarver.getCuts(target)

	-- Цвет и материал резака задают вид стенок выреза — делаем их как у детали.
	cutter.Material = target.Material
	cutter.Color = target.Color

	local ok, union = pcall(function()
		return target:SubtractAsync(
			{ cutter },
			Enum.CollisionFidelity.PreciseConvexDecomposition, -- точная коллизия: в проём можно пройти
			Enum.RenderFidelity.Automatic
		)
	end)

	if not ok then
		warn("[BlockCarver] SubtractAsync не справился:", union)
		return "failed", nil
	end
	if typeof(union) ~= "Instance" or not union:IsA("BasePart") then
		return "failed", nil
	end
	-- Пока шёл CSG, деталь могли снести или перенести в другое место иерархии.
	if target.Parent ~= parent then
		union:Destroy()
		return "gone", nil
	end

	-- Рамку пересчитываем от текущего положения: за время CSG блок могли передвинуть.
	baseCFrame = BlockCarver.getBase(target)
	table.insert(cuts, {
		c = SaveCodec.encodeCFrame(baseCFrame:ToObjectSpace(cutter.CFrame)),
		z = SaveCodec.encodeVector(cutter.Size),
	})

	adopt(union, target)
	union:SetAttribute(BASE_OFFSET, union.CFrame:ToObjectSpace(baseCFrame))
	union:SetAttribute(BASE_SIZE, baseSize)
	union:SetAttribute(CUTS, HttpService:JSONEncode(cuts))
	union.Parent = parent
	target:Destroy()
	return "carved", union
end

-- Вырезает коробку (cutterCFrame, cutterSize) из каждой детали targets.
-- Цель — одиночный блок или деталь составной модели.
function BlockCarver.carve(targets: { BasePart }, cutterCFrame: CFrame, cutterSize: Vector3): CarveResult
	local result: CarveResult = { carved = 0, removed = 0, failed = 0 }
	local cutter = makeCutter(cutterCFrame, inflated(cutterSize))
	cutter.Parent = workspace

	for _, target in targets do
		local outcome = subtract(target, cutter)
		if outcome == "carved" then
			result.carved += 1
		elseif outcome == "removed" then
			result.removed += 1
		elseif outcome == "failed" then
			result.failed += 1
		end
	end

	cutter:Destroy()
	return result
end

-- Загрузка сохранения: заново делает в свежей детали вырезы из её истории.
-- Возвращает итоговую деталь (nil, если её не стало).
function BlockCarver.replay(part: BasePart, cuts: unknown): BasePart?
	if typeof(cuts) ~= "table" then
		return part
	end
	local current: BasePart = part
	for index, cut in cuts :: { unknown } do
		if index > MAX_REPLAYED_CUTS or typeof(cut) ~= "table" then
			break
		end
		local record = cut :: { [string]: unknown }
		local relative = SaveCodec.decodeCFrame(record.c)
		local size = SaveCodec.decodeVector(record.z)
		if not relative or not size or math.min(size.X, size.Y, size.Z) <= 0 then
			continue
		end
		local baseCFrame = BlockCarver.getBase(current)
		local cutter = makeCutter(baseCFrame * relative, size)
		cutter.Parent = workspace
		local outcome, union = subtract(current, cutter)
		cutter:Destroy()
		if outcome == "carved" and union then
			current = union
		elseif outcome == "removed" or outcome == "gone" then
			return nil
		end
	end
	return current
end

return BlockCarver
