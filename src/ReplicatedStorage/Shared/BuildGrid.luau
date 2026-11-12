--!strict
-- BuildGrid: общая математика строительного редактора для клиента и сервера.
-- Клиент считает здесь положение призрака, сервер теми же функциями
-- перепроверяет запрос, поэтому результат у обоих совпадает.
--
-- Все расчёты идут в локальных координатах участка (центр плиты = 0,0,0).
-- Сетка начинается от угла плиты, поэтому блоки ложатся ровно по текстуре сетки.
-- Поворот — три угла в градусах:
--   yaw   (клавиша R) — вокруг вертикальной оси Y участка;
--   pitch (клавиша T) — наклон вперёд/назад (ось X фигуры);
--   roll  (клавиша Y) — наклон вбок (ось Z фигуры).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildConfig = require(ReplicatedStorage.Shared.BuildConfig)
local BlockLibrary = require(ReplicatedStorage.Shared.BlockLibrary)
local PlotConfig = require(ReplicatedStorage.Shared.PlotConfig)

export type Angles = {
	yaw: number,
	pitch: number,
	roll: number,
}

export type PlacementRequest = {
	plot: BasePart,
	shapeId: string,
	angles: Angles,
	size: Vector3?, -- свой размер базовой формы или резака (nil = размер из BuildConfig.Shapes)
	gridStep: number, -- 0 = без сетки
	snapToCenter: boolean, -- «Магнит к центру»
	inward: boolean, -- true = резак: фигура утапливается в грань, а не ставится на неё
	hitPart: BasePart, -- плита участка или блок под курсором
	hitPos: Vector3, -- точка попадания луча (мир)
	hitNormal: Vector3, -- нормаль грани (мир)
}

export type Placement = {
	cframe: CFrame, -- мировой CFrame фигуры
	angles: Angles?, -- углы, если фигура развернулась сама (настенный светильник); иначе углы игрока
	localCenter: Vector3, -- центр в координатах участка (его клиент отправляет серверу)
	extents: Vector3, -- габариты с учётом поворота (AABB в координатах участка)
}

local EPSILON = 0.01
local AXES = { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis }
local CORNER_SIGNS = { -1, 1 }

local BuildGrid = {}

-- ===== Вспомогательное =====

local function component(v: Vector3, axis: number): number
	if axis == 1 then
		return v.X
	elseif axis == 2 then
		return v.Y
	end
	return v.Z
end

local function withComponent(v: Vector3, axis: number, value: number): Vector3
	if axis == 1 then
		return Vector3.new(value, v.Y, v.Z)
	elseif axis == 2 then
		return Vector3.new(v.X, value, v.Z)
	end
	return Vector3.new(v.X, v.Y, value)
end

-- Номер оси (1 = X, 2 = Y, 3 = Z), вдоль которой вектор направлен сильнее всего.
local function dominantAxis(v: Vector3): number
	local ax, ay, az = math.abs(v.X), math.abs(v.Y), math.abs(v.Z)
	if ay >= ax and ay >= az then
		return 2
	end
	return if ax >= az then 1 else 3
end

-- Почти целые значения делаем целыми: повороты на 90° получаются идеально ровными.
local function clean(x: number): number
	local r = math.round(x)
	return if math.abs(x - r) < 1e-6 then r else x
end

local function round3(x: number): number
	return math.round(x * 1000) / 1000
end

-- Центр округляем до 1/1000 студа: клиент и сервер видят одно и то же число.
local function roundVector(v: Vector3): Vector3
	return Vector3.new(round3(v.X), round3(v.Y), round3(v.Z))
end

-- Высота верхней грани плиты в локальных координатах участка.
local function surfaceY(plot: BasePart): number
	return plot.Size.Y / 2
end

-- Привязывает центр к сетке по одной оси: округляем НИЖНИЙ/ЛЕВЫЙ край до шага,
-- так формы любой кратной шагу длины встают ровно по линиям сетки.
local function snapAxis(center: number, extent: number, origin: number, step: number): number
	local minEdge = center - extent / 2
	local snappedMin = origin + math.floor((minEdge - origin) / step + 0.5) * step
	return snappedMin + extent / 2
end

-- Половина «толщины» повёрнутой коробки вдоль направления n (единичный вектор):
-- на столько центр должен отстоять от грани, чтобы фигура касалась её вплотную.
local function supportHalf(rotation: CFrame, size: Vector3, n: Vector3): number
	return 0.5
		* (
			math.abs(n:Dot(rotation.RightVector)) * size.X
			+ math.abs(n:Dot(rotation.UpVector)) * size.Y
			+ math.abs(n:Dot(rotation.LookVector)) * size.Z
		)
end

-- ===== Поворот =====

-- Угол из сети: число, кратное MinRotationStep, в диапазоне [0, 360).
function BuildGrid.isValidAngle(value: unknown): boolean
	if typeof(value) ~= "number" then
		return false
	end
	local v = value :: number
	return v == v and v >= 0 and v < 360 and v % BuildConfig.MinRotationStep == 0
end

-- Добавляет шаг к углу и возвращает его в диапазон [0, 360).
function BuildGrid.addAngle(current: number, step: number): number
	return (current + step) % 360
end

-- Поворот фигуры в координатах участка: yaw (Y) * pitch (X) * roll (Z).
-- Yaw внешний, поэтому R всегда крутит вокруг вертикали, а T/Y наклоняют фигуру
-- относительно её собственного «перёда».
function BuildGrid.makeRotation(angles: Angles): CFrame
	local raw = CFrame.Angles(0, math.rad(angles.yaw), 0)
		* CFrame.Angles(math.rad(angles.pitch), 0, 0)
		* CFrame.Angles(0, 0, math.rad(angles.roll))
	local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = raw:GetComponents()
	return CFrame.new(
		0,
		0,
		0,
		clean(r00),
		clean(r01),
		clean(r02),
		clean(r10),
		clean(r11),
		clean(r12),
		clean(r20),
		clean(r21),
		clean(r22)
	)
end

-- Габариты повёрнутой коробки в осях участка (AABB).
function BuildGrid.getExtents(rotation: CFrame, size: Vector3): Vector3
	local r, u, l = rotation.RightVector, rotation.UpVector, rotation.LookVector
	return Vector3.new(
		math.abs(r.X) * size.X + math.abs(u.X) * size.Y + math.abs(l.X) * size.Z,
		math.abs(r.Y) * size.X + math.abs(u.Y) * size.Y + math.abs(l.Y) * size.Z,
		math.abs(r.Z) * size.X + math.abs(u.Z) * size.Y + math.abs(l.Z) * size.Z
	)
end

-- ===== Геометрия граней =====

-- Грань детали-коробки, в которую попал луч: центр грани и её нормаль (мир).
-- Для вырезанных блоков (UnionOperation) берётся грань их габаритной коробки.
function BuildGrid.getFace(part: BasePart, worldNormal: Vector3): (Vector3, Vector3)
	local localNormal = part.CFrame:VectorToObjectSpace(worldNormal)
	local axis = dominantAxis(localNormal)
	local sign = if component(localNormal, axis) >= 0 then 1 else -1
	local axisVector = AXES[axis] * sign
	local half = component(part.Size, axis) / 2
	return part.CFrame:PointToWorldSpace(axisVector * half), part.CFrame:VectorToWorldSpace(axisVector)
end

-- Коробка inner целиком внутри коробки outer (все 8 углов)?
function BuildGrid.isBoxInside(innerCFrame: CFrame, innerSize: Vector3, outerCFrame: CFrame, outerSize: Vector3): boolean
	local half = innerSize / 2
	local limit = outerSize / 2 + Vector3.one * EPSILON
	for _, sx in CORNER_SIGNS do
		for _, sy in CORNER_SIGNS do
			for _, sz in CORNER_SIGNS do
				local corner = innerCFrame:PointToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz))
				local p = outerCFrame:PointToObjectSpace(corner)
				if math.abs(p.X) > limit.X or math.abs(p.Y) > limit.Y or math.abs(p.Z) > limit.Z then
					return false
				end
			end
		end
	end
	return true
end

-- ===== Расчёт позиции призрака (клиент) =====

function BuildGrid.computePlacement(req: PlacementRequest): Placement?
	local shape = BuildConfig.Shapes[req.shapeId]
	if not shape then
		return nil
	end

	local plot = req.plot
	local plotCFrame = plot.CFrame
	local size = req.size or shape.size

	-- Настенная форма на вертикальной грани сама встаёт тыльной стороной (-Z) к стене.
	local mounted: Angles? = nil
	if shape.wallMount and not req.inward then
		local wallNormal = plotCFrame:VectorToObjectSpace(req.hitNormal)
		if math.abs(wallNormal.Y) < 0.5 then
			local step = BuildConfig.MinRotationStep
			local yaw = math.deg(math.atan2(wallNormal.X, wallNormal.Z))
			mounted = { yaw = (math.round(yaw / step) * step) % 360, pitch = 0, roll = 0 }
		end
	end
	local rotation = BuildGrid.makeRotation(mounted or req.angles)
	local extents = BuildGrid.getExtents(rotation, size)
	-- Установка — фигура снаружи грани; резак — утоплен в грань (прорезает внутрь блока).
	local direction = if req.inward then -1 else 1
	local center: Vector3

	if req.snapToCenter and req.hitPart ~= plot then
		-- «Магнит к центру»: ровно по центру грани блока под курсором, сетка не нужна.
		local faceCenter, faceNormal = BuildGrid.getFace(req.hitPart, req.hitNormal)
		local p = plotCFrame:PointToObjectSpace(faceCenter)
		local n = plotCFrame:VectorToObjectSpace(faceNormal)
		center = p + n * (supportHalf(rotation, size, n) * direction)
	else
		-- Шаг 1. Точка касания и нормаль в координатах участка.
		local p = plotCFrame:PointToObjectSpace(req.hitPos)
		local n = plotCFrame:VectorToObjectSpace(req.hitNormal).Unit
		if req.hitPart:IsA("Part") then
			-- Обычный блок или плита: берём точную плоскость грани, чтобы не было
			-- микрозазоров из-за погрешности луча.
			local faceCenter, faceNormal = BuildGrid.getFace(req.hitPart, req.hitNormal)
			local f = plotCFrame:PointToObjectSpace(faceCenter)
			n = plotCFrame:VectorToObjectSpace(faceNormal)
			p -= n * (p - f):Dot(n)
		end

		-- Шаг 2. Фигура касается грани вплотную (с учётом поворота и наклона).
		local half = supportHalf(rotation, size, n) * direction
		center = p + n * half

		-- Шаг 3. Сетка: привязываем две оси вдоль грани, по оси нормали фигура
		-- остаётся вплотную к грани. При шаге 0 — свободное перемещение.
		local step = req.gridStep
		if step > 0 then
			local normalAxis = dominantAxis(n)
			-- Сетка отсчитывается от центра плиты: при смене её размера линии не сдвигаются.
			local origins = Vector3.new(0, surfaceY(plot), 0)
			for axis = 1, 3 do
				if axis ~= normalAxis then
					-- Тонкая полоса резака встаёт на линию сетки серединой, а не краем.
					local extent = component(extents, axis)
					if extent <= BuildConfig.BladeThickness + EPSILON then
						extent = 0
					end
					local snapped = snapAxis(component(center, axis), extent, component(origins, axis), step)
					center = withComponent(center, axis, snapped)
				end
			end
			-- Наклонная грань (повёрнутый блок): после привязки возвращаем фигуру в контакт.
			local drift = (center - p):Dot(n) - half
			if math.abs(drift) > 1e-4 then
				center -= n * drift
			end
		end
	end

	center = roundVector(center)
	return {
		cframe = plotCFrame * CFrame.new(center) * rotation,
		angles = mounted,
		localCenter = center,
		extents = extents,
	}
end

-- ===== Проверки (клиент и сервер) =====

-- Сервер: собирает Placement из присланных клиентом центра и углов (углы уже проверены).
function BuildGrid.fromLocal(
	plot: BasePart,
	shapeId: string,
	localCenter: Vector3,
	angles: Angles,
	size: Vector3?
): Placement?
	local shape = BuildConfig.Shapes[shapeId]
	if not shape then
		return nil
	end
	local rotation = BuildGrid.makeRotation(angles)
	local center = roundVector(localCenter)
	return {
		cframe = plot.CFrame * CFrame.new(center) * rotation,
		localCenter = center,
		extents = BuildGrid.getExtents(rotation, size or shape.size),
	}
end

-- Фигура целиком внутри строительной зоны: внутри плиты 200x200 (минус отступ
-- под бордюр), не ниже поверхности и не выше BuildHeight.
function BuildGrid.isInsideArea(plot: BasePart, localCenter: Vector3, extents: Vector3): boolean
	local halfX = plot.Size.X / 2 - BuildConfig.EdgeInset
	local halfZ = plot.Size.Z / 2 - BuildConfig.EdgeInset
	local bottom = localCenter.Y - extents.Y / 2
	local top = localCenter.Y + extents.Y / 2
	local surface = surfaceY(plot)

	return math.abs(localCenter.X) + extents.X / 2 <= halfX + EPSILON
		and math.abs(localCenter.Z) + extents.Z / 2 <= halfZ + EPSILON
		and bottom >= surface - EPSILON
		and top <= surface + PlotConfig.BuildHeight + EPSILON
end

-- Невидимая деталь-«щуп» для точной проверки пересечений (GetPartsInPart).
-- В мире она находится только на время одного запроса.
local probe: Part? = nil

local function getProbe(): Part
	local existing = probe
	if existing then
		return existing
	end
	local created = Instance.new("Part")
	created.Name = "BuildProbe"
	created.Anchored = true
	created.CanCollide = false
	created.CanTouch = false
	created.CastShadow = false
	created.Transparency = 1
	probe = created
	return created
end

-- Детали из папок folders, которые реально пересекают коробку (cframe, size).
-- Проверка идёт по настоящей геометрии, поэтому проёмы, вырезанные резаком,
-- считаются пустым местом (туда можно поставить блок).
function BuildGrid.queryBox(cframe: CFrame, size: Vector3, folders: { Instance }): { BasePart }
	if #folders == 0 then
		return {}
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = folders

	local p = getProbe()
	p.Size = Vector3.new(math.max(size.X, 0.05), math.max(size.Y, 0.05), math.max(size.Z, 0.05))
	p.CFrame = cframe
	p.Parent = workspace
	local parts = workspace:GetPartsInPart(p, params)
	p.Parent = nil
	return parts
end

local function plotFolders(plot: BasePart, withDecor: boolean): { Instance }
	local folders: { Instance } = {}
	local blocks = plot:FindFirstChild(BuildConfig.BlocksFolderName)
	if blocks then
		table.insert(folders, blocks)
	end
	local decor = if withDecor then plot:FindFirstChild(BuildConfig.DecorFolderName) else nil
	if decor then
		table.insert(folders, decor)
	end
	return folders
end

-- Пересекается ли фигура с поставленными блоками или декором участка.
-- Коробку чуть уменьшаем, чтобы соседи, касающиеся гранями, не мешали.
function BuildGrid.isBlocked(plot: BasePart, cframe: CFrame, size: Vector3): boolean
	local shrunk = size - Vector3.one * (BuildConfig.OverlapTolerance * 2)
	return #BuildGrid.queryBox(cframe, shrunk, plotFolders(plot, true)) > 0
end

-- То же для любой формы, включая составные: проверяются коробки из BlockLibrary
-- (у арки — опоры и свод, у лестницы — ступени), поэтому под аркой и над ступенями
-- можно строить. Каждая коробка уменьшается на тот же допуск касания.
function BuildGrid.isShapeBlocked(plot: BasePart, cframe: CFrame, shapeId: string, size: Vector3?): boolean
	local boxes = BlockLibrary.getCollisionBoxes(shapeId, size)
	if #boxes == 0 then
		return true
	end
	local folders = plotFolders(plot, true)
	local inset = Vector3.one * (BuildConfig.OverlapTolerance * 2)
	for _, box in boxes do
		local shrunk = (box.size - inset):Max(Vector3.one * 0.01)
		if #BuildGrid.queryBox(cframe * box.cframe, shrunk, folders) > 0 then
			return true
		end
	end
	return false
end

-- Свои блоки, которые задевает резак (их и будет резать сервер).
-- Составные модели не режутся: берём только Part'ы, лежащие прямо в папке Blocks.
function BuildGrid.findCarveTargets(plot: BasePart, cframe: CFrame, size: Vector3, ownerUserId: number): { BasePart }
	local blocks = plot:FindFirstChild(BuildConfig.BlocksFolderName)
	if not blocks then
		return {}
	end
	local shrunk = size - Vector3.one * (BuildConfig.OverlapTolerance * 2)
	local targets: { BasePart } = {}
	for _, part in BuildGrid.queryBox(cframe, shrunk, { blocks }) do
		-- Цель — сам блок или деталь составной модели: владельца смотрим у корня в папке Blocks.
		local root: Instance = part
		while root.Parent and root.Parent ~= blocks do
			root = root.Parent
		end
		if root.Parent == blocks and root:GetAttribute(BuildConfig.Attributes.OwnerUserId) == ownerUserId then
			table.insert(targets, part)
		end
	end
	return targets
end

-- ---------------------------------------------------------------------------
-- Перенос уже поставленного блока (режим «Двигать»).
-- ---------------------------------------------------------------------------

BuildGrid.roundVector = roundVector

-- Все детали блока: сам Part / CSG-результат или детали составной модели.
-- Скрижали (декор на гранях) в габарит и пересечения не входят.
function BuildGrid.blockParts(block: Instance): { BasePart }
	local parts: { BasePart } = {}
	if block:IsA("BasePart") then
		table.insert(parts, block)
	end
	for _, descendant in block:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:GetAttribute(BuildConfig.Attributes.TabletId) == nil then
			table.insert(parts, descendant)
		end
	end
	return parts
end

-- Сдвигает блок целиком. У одиночной детали PivotTo не двигает потомков,
-- поэтому висящие на ней скрижали переносим вручную.
function BuildGrid.shiftBlock(block: PVInstance, worldOffset: Vector3)
	block:PivotTo(block:GetPivot() + worldOffset)
	if block:IsA("BasePart") then
		for _, descendant in block:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.CFrame += worldOffset
			end
		end
	end
end

-- Габарит блока по осям участка: центр и размеры в координатах участка.
function BuildGrid.getBlockBounds(plot: BasePart, block: Instance): (Vector3?, Vector3?)
	local minCorner: Vector3? = nil
	local maxCorner: Vector3? = nil
	for _, part in BuildGrid.blockParts(block) do
		local relative = plot.CFrame:ToObjectSpace(part.CFrame)
		local half = BuildGrid.getExtents(relative.Rotation, part.Size) / 2
		local low, high = relative.Position - half, relative.Position + half
		minCorner = if minCorner then minCorner:Min(low) else low
		maxCorner = if maxCorner then maxCorner:Max(high) else high
	end
	if not minCorner or not maxCorner then
		return nil, nil
	end
	return (minCorner + maxCorner) / 2, maxCorner - minCorner
end

-- Смещение вдоль одной оси участка (1 = X, 2 = Y, 3 = Z) с привязкой края блока к сетке.
function BuildGrid.snapMove(
	plot: BasePart,
	localCenter: Vector3,
	extents: Vector3,
	axis: number,
	distance: number,
	gridStep: number
): number
	local start = component(localCenter, axis)
	if gridStep <= 0 then
		return round3(distance)
	end
	local origins = Vector3.new(0, surfaceY(plot), 0)
	local snapped = snapAxis(start + distance, component(extents, axis), component(origins, axis), gridStep)
	return round3(snapped - start)
end

-- Задевает ли блок после сдвига чужую геометрию (собственные детали не в счёт).
function BuildGrid.isMoveBlocked(plot: BasePart, block: Instance, localOffset: Vector3): boolean
	local worldOffset = plot.CFrame:VectorToWorldSpace(localOffset)
	local folders = plotFolders(plot, true)
	local inset = Vector3.one * (BuildConfig.OverlapTolerance * 2)
	for _, part in BuildGrid.blockParts(block) do
		local shrunk = (part.Size - inset):Max(Vector3.one * 0.01)
		for _, hit in BuildGrid.queryBox(part.CFrame + worldOffset, shrunk, folders) do
			if hit ~= block and not hit:IsDescendantOf(block) then
				return true
			end
		end
	end
	return false
end

return BuildGrid
