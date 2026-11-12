--!strict
-- MoveGizmo (клиент): 3D-стрелки перемещения (стандартные Roblox Handles) вокруг выбранного блока.
--   * стрелки идут вдоль осей X / Y / Z участка: Handles привязаны к невидимому боксу-габариту,
--     повёрнутому как плита, поэтому направления не зависят от поворота самого блока;
--   * во время перетаскивания двигается полупрозрачная копия блока (зелёная — можно, красная — нельзя),
--     смещение привязывается к текущему шагу сетки панели «Точность»;
--   * когда мышь отпущена, смещение уходит на сервер (commit) — он перепроверяет и двигает блок.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local BuildConfig = require(ReplicatedStorage.Shared.BuildConfig)
local BuildGrid = require(ReplicatedStorage.Shared.BuildGrid)

export type Callbacks = {
	getGridStep: () -> number, -- текущий шаг сетки (0 = свободно)
	commit: (block: Instance, localOffset: Vector3) -> (), -- отправить перенос на сервер
	notify: (text: string) -> (),
}

export type Gizmo = {
	select: (block: Instance?) -> (), -- показать стрелки вокруг блока (nil — убрать)
	getSelected: () -> Instance?,
	isBusy: () -> boolean, -- курсор на стрелке или идёт перетаскивание: клик не должен менять выбор
	update: (dt: number) -> (),
	destroy: () -> (),
}

type Drag = {
	block: PVInstance,
	startPivot: CFrame,
	center: Vector3, -- центр габарита в координатах участка до переноса
	extents: Vector3,
	offset: Vector3, -- целевое смещение (уже привязано к сетке)
	shown: Vector3, -- смещение копии: плавно догоняет offset
	valid: boolean,
	ghost: PVInstance?,
}

local PROXY_MARGIN = 0.1 -- стрелки чуть отступают от граней блока
local DIMMED = 0.8 -- прозрачность исходного блока, пока двигается копия

local MoveGizmo = {}

local function makeGhost(block: PVInstance, parent: Instance): PVInstance?
	local ok, clone = pcall(function()
		return block:Clone()
	end)
	if not ok or not clone then
		return nil
	end
	for _, part in BuildGrid.blockParts(clone) do
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.Transparency = BuildConfig.GhostTransparency
		if part:IsA("PartOperation") then
			part.UsePartColor = true
		end
	end
	clone.Parent = parent
	return clone
end

local function tint(ghost: PVInstance?, color: Color3)
	if ghost then
		for _, part in BuildGrid.blockParts(ghost) do
			part.Color = color
		end
	end
end

local function setDimmed(block: Instance, dimmed: boolean)
	for _, part in BuildGrid.blockParts(block) do
		part.LocalTransparencyModifier = if dimmed then DIMMED else 0
	end
end

function MoveGizmo.new(plot: BasePart, previewFolder: Instance, playerGui: Instance, callbacks: Callbacks): Gizmo
	local proxy = Instance.new("Part")
	proxy.Name = "MoveBounds"
	proxy.Anchored = true
	proxy.CanCollide = false
	proxy.CanQuery = false
	proxy.CanTouch = false
	proxy.CastShadow = false
	proxy.Transparency = 1
	proxy.Parent = previewFolder

	-- Handles получают события мыши, только когда лежат в PlayerGui.
	local handles = Instance.new("Handles")
	handles.Name = "MoveHandles"
	handles.Style = Enum.HandlesStyle.Movement
	handles.Faces = Faces.new(
		Enum.NormalId.Right,
		Enum.NormalId.Left,
		Enum.NormalId.Top,
		Enum.NormalId.Bottom,
		Enum.NormalId.Front,
		Enum.NormalId.Back
	)
	handles.Color3 = BuildConfig.MoveHandlesColor
	handles.Visible = false
	handles.Parent = playerGui

	local selected: PVInstance? = nil
	local drag: Drag? = nil
	local pending: Drag? = nil -- перенос отправлен, ждём, пока сервер сдвинет блок
	local pendingDeadline = 0
	local hovered: { [Enum.NormalId]: boolean } = {}
	local connections: { RBXScriptConnection } = {}

	local function placeProxy(center: Vector3, extents: Vector3)
		proxy.Size = extents + Vector3.one * PROXY_MARGIN
		proxy.CFrame = plot.CFrame * CFrame.new(center)
	end

	local function release(d: Drag)
		local ghost = d.ghost
		if ghost then
			ghost:Destroy()
		end
		setDimmed(d.block, false)
	end

	local function cancelActive()
		if drag then
			release(drag)
			drag = nil
		end
		if pending then
			release(pending)
			pending = nil
		end
	end

	local function select(block: Instance?)
		local target: PVInstance? = if block and block:IsA("PVInstance") then block else nil
		if target == selected then
			return
		end
		cancelActive()
		table.clear(hovered)
		selected = target
		handles.Adornee = if target then proxy else nil
		handles.Visible = target ~= nil
		if target then
			local center, extents = BuildGrid.getBlockBounds(plot, target)
			if center and extents then
				placeProxy(center, extents)
			end
		end
	end

	local function beginDrag()
		local block = selected
		if not block or drag then
			return
		end
		if pending then
			release(pending)
			pending = nil
		end
		local center, extents = BuildGrid.getBlockBounds(plot, block)
		if not center or not extents then
			return
		end
		local ghost = makeGhost(block, previewFolder)
		tint(ghost, BuildConfig.GhostValidColor)
		setDimmed(block, true)
		drag = {
			block = block,
			startPivot = block:GetPivot(),
			center = center,
			extents = extents,
			offset = Vector3.zero,
			shown = Vector3.zero,
			valid = true,
			ghost = ghost,
		}
	end

	-- distance — путь мыши вдоль стрелки от начала перетаскивания (в студах).
	local function onDrag(face: Enum.NormalId, distance: number)
		local d = drag
		if not d then
			return
		end
		local normal = Vector3.FromNormalId(face)
		local axis = if normal.X ~= 0 then 1 elseif normal.Y ~= 0 then 2 else 3
		local sign = normal.X + normal.Y + normal.Z
		local amount = BuildGrid.snapMove(plot, d.center, d.extents, axis, sign * distance, callbacks.getGridStep())
		local offset = normal * (sign * amount)
		if offset == d.offset then
			return
		end
		d.offset = offset
		d.valid = amount == 0
			or (
				BuildGrid.isInsideArea(plot, d.center + offset, d.extents)
				and not BuildGrid.isMoveBlocked(plot, d.block, offset)
			)
		tint(d.ghost, if d.valid then BuildConfig.GhostValidColor else BuildConfig.GhostInvalidColor)
	end

	local function finishDrag()
		local d = drag
		if not d then
			return
		end
		drag = nil
		if d.offset.Magnitude < 1e-3 then
			release(d)
		elseif not d.valid then
			callbacks.notify("Сюда передвинуть нельзя: блок выходит за плиту или задевает другой блок")
			release(d)
		else
			callbacks.commit(d.block, d.offset)
			d.shown = d.offset
			pending = d
			pendingDeadline = os.clock() + BuildConfig.MovePendingTimeout
		end
	end

	local function showAt(d: Drag)
		local ghost = d.ghost
		if ghost then
			ghost:PivotTo(d.startPivot + plot.CFrame:VectorToWorldSpace(d.shown))
		end
		placeProxy(d.center + d.shown, d.extents)
	end

	local function update(dt: number)
		local block = selected
		if not block then
			return
		end
		if not block:IsDescendantOf(plot) then
			select(nil) -- блок снесли или заменили (резак)
			return
		end

		local d, p = drag, pending
		if d then
			local alpha = 1 - math.exp(-BuildConfig.GhostFollowSpeed * dt)
			d.shown = d.shown:Lerp(d.offset, alpha)
			showAt(d)
		elseif p then
			showAt(p)
			local moved = (block:GetPivot().Position - p.startPivot.Position).Magnitude > 1e-3
			if moved or os.clock() > pendingDeadline then
				release(p)
				pending = nil
			end
		else
			local center, extents = BuildGrid.getBlockBounds(plot, block)
			if center and extents then
				placeProxy(center, extents)
			end
		end
	end

	table.insert(
		connections,
		handles.MouseEnter:Connect(function(face: Enum.NormalId)
			hovered[face] = true
		end)
	)
	table.insert(
		connections,
		handles.MouseLeave:Connect(function(face: Enum.NormalId)
			hovered[face] = nil
		end)
	)
	table.insert(connections, handles.MouseButton1Down:Connect(beginDrag))
	table.insert(connections, handles.MouseDrag:Connect(onDrag))
	table.insert(connections, handles.MouseButton1Up:Connect(finishDrag))
	-- MouseButton1Up не приходит, если кнопку отпустили мимо стрелки.
	table.insert(
		connections,
		UserInputService.InputEnded:Connect(function(input: InputObject)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				finishDrag()
			end
		end)
	)

	return {
		select = select,
		getSelected = function(): Instance?
			return selected
		end,
		isBusy = function(): boolean
			return drag ~= nil or next(hovered) ~= nil
		end,
		update = update,
		destroy = function()
			cancelActive()
			for _, connection in connections do
				connection:Disconnect()
			end
			handles:Destroy()
			proxy:Destroy()
		end,
	}
end

return MoveGizmo
