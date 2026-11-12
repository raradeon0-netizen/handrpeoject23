--!strict
-- PlotTeleporter: ставит персонажа игрока ровно в центр его участка.

local PlotTeleporter = {}

local CHARACTER_WAIT_TIMEOUT = 5 -- сколько секунд ждать появления персонажа
local SAFETY_GAP = 0.5 -- небольшой зазор над поверхностью, чтобы не застрять в Part'е

-- Ждёт персонажа с HumanoidRootPart (игрок мог ещё не заспавниться).
local function waitForCharacter(player: Player): (Model?, BasePart?)
	local deadline = os.clock() + CHARACTER_WAIT_TIMEOUT
	repeat
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if character and root and root:IsA("BasePart") then
			return character, root
		end
		task.wait(0.1)
	until os.clock() >= deadline or player.Parent == nil

	return nil, nil
end

-- Телепортирует на участок. Возвращает false, если персонажа не удалось найти.
function PlotTeleporter.toPlot(player: Player, plot: Part): boolean
	local character, root = waitForCharacter(player)
	if not character or not root then
		warn(`[PlotTeleporter] У {player.Name} нет персонажа, телепорт отменён`)
		return false
	end

	-- Шаг 1. Высота от HumanoidRootPart до ступней: работает и для R15, и для R6.
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hipHeight = if humanoid then humanoid.HipHeight else 0
	local standHeight = math.max(hipHeight + root.Size.Y / 2, character:GetExtentsSize().Y / 2)

	-- Шаг 2. Центр участка по X/Z (ровно), по Y: верхняя грань + рост персонажа.
	local center = plot.Position
	local surfaceY = center.Y + plot.Size.Y / 2
	local target = Vector3.new(center.X, surfaceY + standHeight + SAFETY_GAP, center.Z)

	-- Шаг 3. Переносим и гасим скорость, чтобы персонажа не «унесло» после телепорта.
	character:PivotTo(CFrame.new(target))
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	return true
end

-- ===== Режим прогулки =====

local WALK_INSET = 12 -- отступ точки входа от края плиты
local WALK_STEP = 12 -- шаг перебора точек вдоль края
local WALK_CLEARANCE = Vector3.new(5, 6, 5) -- свободное место, нужное персонажу
local DROP_FROM = 400 -- с какой высоты ищем верх построек, если свободного места нет

-- Точки для выхода на прогулку (в координатах плиты): сначала вдоль «входного» края (+Z, откуда
-- смотрит стартовая камера) от середины к углам, затем остальные края и центр.
local function walkCandidates(half: number): { Vector2 }
	local points: { Vector2 } = { Vector2.new(0, half) }
	for index = 1, math.floor(half / WALK_STEP) do
		table.insert(points, Vector2.new(index * WALK_STEP, half))
		table.insert(points, Vector2.new(-index * WALK_STEP, half))
	end
	table.insert(points, Vector2.new(half, 0))
	table.insert(points, Vector2.new(-half, 0))
	table.insert(points, Vector2.new(0, -half))
	table.insert(points, Vector2.zero)
	return points
end

-- Ставит персонажа на свободное место у края участка лицом к центру. Если всё застроено,
-- персонаж встаёт сверху на постройку у входа — внутри стены он не окажется.
function PlotTeleporter.toWalkSpot(player: Player, plot: Part): boolean
	local character, root = waitForCharacter(player)
	if not character or not root then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hipHeight = if humanoid then humanoid.HipHeight else 0
	local standHeight = math.max(hipHeight + root.Size.Y / 2, character:GetExtentsSize().Y / 2)

	local surface = plot.Size.Y / 2
	local half = math.max(plot.Size.X / 2 - WALK_INSET, 0)
	local candidates = walkCandidates(half)

	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = { plot }

	local ground: Vector3? = nil
	for _, point in candidates do
		-- Бокс висит чуть над плитой: сама плита в него не попадает, только постройки и декор.
		local probe = plot.CFrame:PointToWorldSpace(Vector3.new(point.X, surface + WALK_CLEARANCE.Y / 2 + 0.3, point.Y))
		if #workspace:GetPartBoundsInBox(CFrame.new(probe), WALK_CLEARANCE, overlap) == 0 then
			ground = plot.CFrame:PointToWorldSpace(Vector3.new(point.X, surface, point.Y))
			break
		end
	end

	if not ground then
		local first = candidates[1]
		local top = plot.CFrame:PointToWorldSpace(Vector3.new(first.X, surface + DROP_FROM, first.Y))
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Include
		rayParams.FilterDescendantsInstances = { plot }
		local hit = workspace:Raycast(top, Vector3.yAxis * -(DROP_FROM + 10), rayParams)
		ground = if hit then hit.Position else plot.CFrame:PointToWorldSpace(Vector3.new(first.X, surface, first.Y))
	end

	local target = (ground :: Vector3) + Vector3.yAxis * (standHeight + SAFETY_GAP)
	local lookAt = Vector3.new(plot.Position.X, target.Y, plot.Position.Z)
	local cframe = if (lookAt - target).Magnitude > 1 then CFrame.lookAt(target, lookAt) else CFrame.new(target)
	character:PivotTo(cframe)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	return true
end

return PlotTeleporter
