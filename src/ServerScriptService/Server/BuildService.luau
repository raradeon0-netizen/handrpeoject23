--!strict
-- BuildService (Script): серверный обработчик строительного редактора.
-- Принимает запросы клиента «поставить» / «удалить» / «вырезать» и НИЧЕМУ не верит:
--   1) проверяет типы данных, форму и углы (кратны BuildConfig.MinRotationStep),
--   2) проверяет, что фигура на СВОЁМ участке (и для установки — ни с чем не пересекается),
--   3) спавнит блок (BlockFactory) или вырезает форму (BlockCarver -> SubtractAsync в pcall).
-- Шаг сетки (4 / 1 / 0.25 / свободно) — удобство клиента, сервер его не навязывает:
-- сервер отвечает за то, ГДЕ можно строить.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildConfig = require(ReplicatedStorage.Shared.BuildConfig)
local BuildGrid = require(ReplicatedStorage.Shared.BuildGrid)
local BuildSize = require(ReplicatedStorage.Shared.BuildSize)
local PaintCatalog = require(ReplicatedStorage.Shared.PaintCatalog)

local PlotOwnership = require(script.Parent.PlotOwnership)
local BlockFactory = require(script.Parent.BlockFactory)
local BlockCarver = require(script.Parent.BlockCarver)
local BlockMover = require(script.Parent.BlockMover)
local BlockPainter = require(script.Parent.BlockPainter)
local TabletFactory = require(script.Parent.TabletFactory)

-- Шаг 1. RemoteEvent'ы для клиента.
local function makeRemote(name: string): RemoteEvent
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = ReplicatedStorage.Shared
	return remote
end

local placeRemote = makeRemote(BuildConfig.PlaceRemoteName)
local removeRemote = makeRemote(BuildConfig.RemoveRemoteName)
local carveRemote = makeRemote(BuildConfig.CarveRemoteName)
local moveRemote = makeRemote(BuildConfig.MoveRemoteName)
local paintRemote = makeRemote(BuildConfig.PaintRemoteName)
local tabletRemote = makeRemote(BuildConfig.TabletRemoteName)
local eraseRemote = makeRemote(BuildConfig.EraseTabletRemoteName)
local noticeRemote = makeRemote(BuildConfig.NoticeRemoteName)

type ShapeRequest = {
	claim: PlotOwnership.Claim,
	blocks: Folder,
	shapeId: string,
	size: Vector3,
	placement: BuildGrid.Placement,
}

local lastAction: { [Player]: { [string]: number } } = {}
local carving: { [Player]: boolean } = {} -- идёт CSG-операция этого игрока

-- Антиспам: true, если с прошлого такого действия прошло не меньше cooldown секунд.
local function cooldownPassed(player: Player, action: string, cooldown: number): boolean
	local timers = lastAction[player]
	if not timers then
		timers = {}
		lastAction[player] = timers
	end
	local now = os.clock()
	if now - (timers[action] or 0) < cooldown then
		return false
	end
	timers[action] = now
	return true
end

local function notify(player: Player, text: string)
	noticeRemote:FireClient(player, text)
end

local function isFiniteVector(v: Vector3): boolean
	for _, c in { v.X, v.Y, v.Z } do
		if c ~= c or math.abs(c) > 1e5 then -- NaN или бесконечность
			return false
		end
	end
	return true
end

-- Папка Blocks внутри участка (создаётся PlotBuilder; на всякий случай создаём и здесь).
-- Корень своего блока (прямой потомок Blocks на участке игрока) по любой его детали.
local function findOwnBlock(player: Player, clicked: Instance): (Instance?, PlotOwnership.Claim?)
	local claim = PlotOwnership.getClaim(player)
	if not claim then
		return nil, nil
	end
	local blocks = claim.plot:FindFirstChild(BuildConfig.BlocksFolderName)
	if not blocks or not clicked:IsDescendantOf(blocks) then
		return nil, nil
	end
	local target: Instance = clicked
	while target.Parent ~= blocks do
		local parent = target.Parent
		if not parent then
			return nil, nil
		end
		target = parent
	end
	if target:GetAttribute(BuildConfig.Attributes.OwnerUserId) ~= player.UserId then
		return nil, nil
	end
	return target, claim
end

local function getBlocksFolder(plot: Part): Folder
	local folder = plot:FindFirstChild(BuildConfig.BlocksFolderName)
	if folder and folder:IsA("Folder") then
		return folder
	end
	local created = Instance.new("Folder")
	created.Name = BuildConfig.BlocksFolderName
	created.Parent = plot
	return created
end

-- Общий разбор запроса с фигурой: (shapeId, локальный центр, yaw, pitch, roll).
local function parseShapeRequest(
	player: Player,
	shapeId: unknown,
	localCenter: unknown,
	yaw: unknown,
	pitch: unknown,
	roll: unknown,
	size: unknown, -- свой размер (nil = стандартный размер формы)
	minSize: number
): ShapeRequest?
	if typeof(shapeId) ~= "string" or typeof(localCenter) ~= "Vector3" then
		return nil
	end
	local shape = BuildConfig.Shapes[shapeId]
	if not shape or not isFiniteVector(localCenter) then
		return nil
	end
	if not (BuildGrid.isValidAngle(yaw) and BuildGrid.isValidAngle(pitch) and BuildGrid.isValidAngle(roll)) then
		return nil
	end

	-- У игрока должен быть участок.
	local claim = PlotOwnership.getClaim(player)
	if not claim or not claim.plot.Parent then
		return nil
	end

	local angles: BuildGrid.Angles = { yaw = yaw :: number, pitch = pitch :: number, roll = roll :: number }
	-- Свой размер разрешён только базовым формам и только в допустимых пределах.
	local actualSize = shape.size
	if size ~= nil then
		if shape.prefab or not BuildSize.isValid(size, minSize) then
			return nil
		end
		actualSize = BuildSize.round(size :: Vector3)
	end

	local placement = BuildGrid.fromLocal(claim.plot, shapeId, localCenter, angles, actualSize)
	if not placement then
		return nil
	end
	-- Центр фигуры принадлежит участку именно этого игрока (реестр участков).
	if not PlotOwnership.canBuildAt(player, placement.cframe.Position) then
		return nil
	end

	return {
		claim = claim,
		blocks = getBlocksFolder(claim.plot),
		shapeId = shapeId,
		size = actualSize,
		placement = placement,
	}
end

-- Шаг 2. Установка блока.
placeRemote.OnServerEvent:Connect(
	function(
		player: Player,
		shapeId: unknown,
		localCenter: unknown,
		yaw: unknown,
		pitch: unknown,
		roll: unknown,
		size: unknown
	)
		if not cooldownPassed(player, "place", BuildConfig.PlaceCooldown) then
			return
		end
		local request =
			parseShapeRequest(player, shapeId, localCenter, yaw, pitch, roll, size, BuildConfig.MinBlockSize)
		if not request then
			return
		end
		if #request.blocks:GetChildren() >= BuildConfig.MaxBlocksPerPlayer then
			notify(player, string.format("Достигнут лимит: %d блоков", BuildConfig.MaxBlocksPerPlayer))
			return
		end

		local plot = request.claim.plot
		local placement = request.placement
		-- Фигура целиком внутри плиты 200x200 (с учётом поворота) и ни с чем не пересекается.
		if not BuildGrid.isInsideArea(plot, placement.localCenter, placement.extents) then
			return
		end
		-- Для составных блоков проверяются коробки деталей (см. BlockLibrary.getCollisionBoxes).
		-- Базовая форма — один бокс своего размера; составная — боксы из библиотеки.
		local shape = BuildConfig.Shapes[request.shapeId]
		local blocked = if shape.prefab
			then BuildGrid.isShapeBlocked(plot, placement.cframe, request.shapeId)
			else BuildGrid.isBlocked(plot, placement.cframe, request.size)
		if blocked then
			return
		end

		local block =
			BlockFactory.create(request.shapeId, request.claim.factionId, placement.cframe, player, request.size)
		if block then
			block.Parent = request.blocks
		end
	end
)

-- Шаг 3. Вырезание (Резак): форма призрака вычитается из своих блоков через CSG.
carveRemote.OnServerEvent:Connect(
	function(
		player: Player,
		shapeId: unknown,
		localCenter: unknown,
		yaw: unknown,
		pitch: unknown,
		roll: unknown,
		size: unknown
	)
		if carving[player] then
			return -- прошлый разрез ещё считается
		end
		if not cooldownPassed(player, "carve", BuildConfig.CarveCooldown) then
			return
		end
		-- Резаку разрешена толщина полосы: она тоньше минимального блока.
		local request =
			parseShapeRequest(player, shapeId, localCenter, yaw, pitch, roll, size, BuildConfig.BladeThickness)
		if not request then
			return
		end
		local shape = BuildConfig.Shapes[request.shapeId]
		if shape and shape.prefab then
			notify(player, "Резак работает только с базовыми формами")
			return
		end

		local placement = request.placement
		local targets = BuildGrid.findCarveTargets(request.claim.plot, placement.cframe, request.size, player.UserId)
		if #targets == 0 then
			notify(player, "Резак не задевает ни одного вашего блока")
			return
		end
		if #targets > BuildConfig.MaxCarveTargets then
			notify(player, string.format("Слишком много блоков под резаком (максимум %d)", BuildConfig.MaxCarveTargets))
			return
		end

		carving[player] = true
		local ok, result = pcall(BlockCarver.carve, targets, placement.cframe, request.size, request.blocks)
		carving[player] = nil

		if not ok then
			warn("[BuildService] Ошибка вырезания:", result)
			notify(player, "Не удалось вырезать форму")
		elseif result.failed > 0 then
			notify(
				player,
				string.format("Не удалось вырезать %d из %d: слишком сложное пересечение", result.failed, #targets)
			)
		end
	end
)

-- Шаг 4. Удаление (ЛКМ в режиме «Снос» или клавиша X): только свой блок своего участка.
-- Клиент может прислать любую деталь составной модели — поднимаемся до корня
-- (прямого ребёнка папки Blocks) и сносим блок целиком.
removeRemote.OnServerEvent:Connect(function(player: Player, clicked: unknown)
	if typeof(clicked) ~= "Instance" then
		return
	end
	if not cooldownPassed(player, "remove", BuildConfig.RemoveCooldown) then
		return
	end

	local target = findOwnBlock(player, clicked)
	if not target then
		return
	end

	target:Destroy()
end)

-- Шаг 5. Чистим таймеры вышедших игроков (сами блоки удаляются вместе с участком).
-- Перенос: клиент присылает блок и смещение в координатах участка (после отпускания стрелки).
moveRemote.OnServerEvent:Connect(function(player: Player, clicked: unknown, localOffset: unknown)
	if typeof(clicked) ~= "Instance" or typeof(localOffset) ~= "Vector3" then
		return
	end
	if not isFiniteVector(localOffset) or localOffset.Magnitude < 1e-3 then
		return
	end
	if carving[player] then
		return -- CSG может заменить блок прямо сейчас
	end
	if not cooldownPassed(player, "move", BuildConfig.MoveCooldown) then
		return
	end

	local target, claim = findOwnBlock(player, clicked)
	if not target or not claim or not target:IsA("PVInstance") then
		return
	end
	local destination = target:GetPivot().Position + claim.plot.CFrame:VectorToWorldSpace(localOffset)
	if not PlotOwnership.canBuildAt(player, destination) then
		return
	end

	local moved, reason = BlockMover.move(claim.plot, target, localOffset)
	if not moved and reason then
		notify(player, reason)
	end
end)

-- Полезная цель покраски / скрижали: деталь своего блока (сама скрижаль целью не считается).
local function findOwnPart(player: Player, clicked: unknown): (BasePart?, PlotOwnership.Claim?)
	if typeof(clicked) ~= "Instance" or not clicked:IsA("BasePart") then
		return nil, nil
	end
	if clicked:GetAttribute(BuildConfig.Attributes.TabletId) ~= nil then
		return nil, nil
	end
	local block, claim = findOwnBlock(player, clicked)
	if not block or not claim then
		return nil, nil
	end
	return clicked, claim
end

-- Покраска: клиент присылает деталь, по которой кликнул, и id материала из PaintCatalog.
paintRemote.OnServerEvent:Connect(function(player: Player, clicked: unknown, materialId: unknown)
	if typeof(materialId) ~= "string" then
		return
	end
	local material = PaintCatalog.MaterialById[materialId]
	if not material or not cooldownPassed(player, "paint", BuildConfig.PaintCooldown) then
		return
	end
	local part = findOwnPart(player, clicked)
	if part then
		BlockPainter.paint(part, material)
	end
end)

-- Скрижаль: деталь, точка и нормаль попадания луча, id скрижали.
tabletRemote.OnServerEvent:Connect(
	function(player: Player, clicked: unknown, hitPos: unknown, hitNormal: unknown, tabletId: unknown)
		if typeof(hitPos) ~= "Vector3" or typeof(hitNormal) ~= "Vector3" or typeof(tabletId) ~= "string" then
			return
		end
		local tablet = PaintCatalog.TabletById[tabletId]
		if not tablet or not isFiniteVector(hitPos) or not isFiniteVector(hitNormal) then
			return
		end
		if math.abs(hitNormal.Magnitude - 1) > 0.01 then
			return
		end
		if not cooldownPassed(player, "tablet", BuildConfig.TabletCooldown) then
			return
		end
		local part, claim = findOwnPart(player, clicked)
		if not part or not claim or not PlotOwnership.canBuildAt(player, hitPos) then
			return
		end
		-- Точка должна лежать на самой детали, а не где-то в стороне от неё.
		local offset = part.CFrame:PointToObjectSpace(hitPos)
		local reach = part.Size / 2 + Vector3.one * 0.5
		if math.abs(offset.X) > reach.X or math.abs(offset.Y) > reach.Y or math.abs(offset.Z) > reach.Z then
			return
		end
		if TabletFactory.count(getBlocksFolder(claim.plot)) >= BuildConfig.MaxTabletsPerPlayer then
			notify(player, string.format("Достигнут лимит: %d скрижалей", BuildConfig.MaxTabletsPerPlayer))
			return
		end
		TabletFactory.place(claim.plot, part, hitPos, hitNormal, tablet)
	end
)

-- «Очистить грань»: снять скрижали с грани, по которой кликнули.
eraseRemote.OnServerEvent:Connect(function(player: Player, clicked: unknown, hitNormal: unknown)
	if typeof(hitNormal) ~= "Vector3" or not isFiniteVector(hitNormal) then
		return
	end
	if math.abs(hitNormal.Magnitude - 1) > 0.01 then
		return
	end
	if not cooldownPassed(player, "erase", BuildConfig.PaintCooldown) then
		return
	end
	local part = findOwnPart(player, clicked)
	if part and TabletFactory.erase(part, hitNormal) == 0 then
		notify(player, "На этой грани нет скрижалей")
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	lastAction[player] = nil
	carving[player] = nil
end)
