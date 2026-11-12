--!strict
-- BlockCarver (сервер): вырезание формы из блоков с помощью Roblox CSG
-- (Solid Modeling, BasePart:SubtractAsync). Так прорезаются дверные проёмы, окна и ниши.
--
-- Каждый вызов SubtractAsync обёрнут в pcall: на сложных пересечениях
-- (слишком много треугольников, вырожденная геометрия, пустой результат)
-- движок бросает ошибку — тогда блок просто остаётся как был.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildConfig = require(ReplicatedStorage.Shared.BuildConfig)
local BuildGrid = require(ReplicatedStorage.Shared.BuildGrid)

export type CarveResult = {
	carved: number, -- сколько блоков прорезано
	removed: number, -- сколько блоков резак накрыл целиком (они удалены)
	failed: number, -- на скольких CSG не справился (блок не изменился)
}

local BlockCarver = {}

-- Невидимая деталь-резак той же формы, что и призрак (чуть больше, см. CutterInflate).
local function makeCutter(cframe: CFrame, size: Vector3): Part
	local cutter = Instance.new("Part")
	cutter.Name = "BuildCutter"
	-- Тонкую сторону полосы не раздуваем: пропил остаётся ровно в её толщину.
	local function inflate(side: number): number
		return if side > BuildConfig.BladeThickness + 1e-3 then side + BuildConfig.CutterInflate * 2 else side
	end
	cutter.Size = Vector3.new(inflate(size.X), inflate(size.Y), inflate(size.Z))
	cutter.CFrame = cframe
	cutter.Anchored = true
	cutter.CanCollide = false
	cutter.CanTouch = false
	cutter.CanQuery = false
	cutter.CastShadow = false
	cutter.Transparency = 1
	return cutter
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
	if union:IsA("UnionOperation") then
		-- Стенки среза красим цветом блока, а не цветом резака.
		union.UsePartColor = true
	end
end

-- Вырезает коробку (cutterCFrame, cutterSize) из каждого блока targets.
-- folder — папка Blocks участка: результат кладётся туда же, исходный блок удаляется.
function BlockCarver.carve(targets: { BasePart }, cutterCFrame: CFrame, cutterSize: Vector3, folder: Instance): CarveResult
	local result: CarveResult = { carved = 0, removed = 0, failed = 0 }
	local cutter = makeCutter(cutterCFrame, cutterSize)
	cutter.Parent = workspace

	for _, target in targets do
		if target.Parent ~= folder then
			continue -- блок уже удалили
		end

		-- Резак накрывает блок целиком: от блока ничего не останется — просто удаляем его
		-- (SubtractAsync с пустым результатом всё равно вернул бы ошибку).
		if BuildGrid.isBoxInside(target.CFrame, target.Size, cutter.CFrame, cutter.Size) then
			target:Destroy()
			result.removed += 1
			continue
		end

		-- Срез в материале и цвете самого блока.
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
			result.failed += 1
		elseif typeof(union) == "Instance" and union:IsA("BasePart") then
			-- SubtractAsync уступает выполнение: за это время блок могли удалить.
			if target.Parent == folder then
				adopt(union, target)
				union.Parent = folder
				target:Destroy()
				result.carved += 1
			else
				union:Destroy()
			end
		else
			result.failed += 1
		end
	end

	cutter:Destroy()
	return result
end

return BlockCarver
