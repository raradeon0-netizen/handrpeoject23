--!strict
-- BuildController: клиентский контроллер строительного редактора (Placement System).
--   * нижняя панель: каталог «Блоки» (базовые и составные формы) + инструменты «Вырезать» и «Снос»;
--   * составные блоки (Model) ведут себя как одиночные: призрак из тех же деталей,
--     сетка и поворот по габариту, «Снос» по любой детали удаляет всю модель;
--   * панель «Точность» справа: шаг сетки 4 / 1 / 0.25 / 0 (свободно), шаг поворота
--     90° / 45° / 15° / 5°, «Магнит к центру», сброс поворота (BuildSettingsController);
--   * призрак плавно следует за курсором по плите и блокам:
--       установка — зелёный (можно) / красный (нельзя),
--       резак — фиолетовый (задевает ваш блок, ЛКМ вырежет) / оранжевый (ничего не задевает);
--   * «Двигать»: ЛКМ по своему блоку показывает 3D-стрелки X / Y / Z (MoveGizmo), перенос идёт по шагу сетки;
--   * размер базовых блоков и резака (X, Y, Z) задаётся на панели «Точность»; резак бывает «кубом»
--     или тонкой «полосой» (BuildConfig.BladeThickness);
--   * «Покраска / Скрижали»: ЛКМ красит деталь выбранным материалом, вешает скрижаль на грань
--     или очищает грань — смотря какая кисть выбрана в меню (PaintMenuController);
--   * R — вращение вокруг вертикальной оси Y, T — наклон вперёд/назад (X), Y — наклон вбок (Z);
--   * ЛКМ — поставить / вырезать / снести (в режиме «Снос»);
--   * X — быстро удалить свой блок под курсором в любом режиме;
--   * ПКМ строительство НЕ использует: она только вращает камеру (BuildCameraController).
-- Сервер всё перепроверяет сам (BuildService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local BuildConfig = require(ReplicatedStorage.Shared.BuildConfig)
local BuildGrid = require(ReplicatedStorage.Shared.BuildGrid)
local BuildSize = require(ReplicatedStorage.Shared.BuildSize)
local PlotConfig = require(ReplicatedStorage.Shared.PlotConfig)
local BlockCatalog = require(ReplicatedStorage.Shared.BlockCatalog)
local PaintCatalog = require(ReplicatedStorage.Shared.PaintCatalog)
local BuildSettingsController = require(script.Parent.BuildSettingsController)
local GhostPreview = require(script.Parent.GhostPreview)
local MoveGizmo = require(script.Parent.MoveGizmo)
local PaintMenuController = require(script.Parent.PaintMenuController)

type BuildHud = {
	getSelection: () -> (string?, string?),
	SelectionChanged: RBXScriptSignal,
	setFaction: ((factionId: string?) -> ())?,
}

type Mode = "None" | "Place" | "Carve" | "Delete" | "Move" | "Paint"

type Remotes = {
	place: RemoteEvent,
	remove: RemoteEvent,
	carve: RemoteEvent,
	move: RemoteEvent,
	paint: RemoteEvent,
	tablet: RemoteEvent,
	erase: RemoteEvent,
	light: RemoteEvent,
	notice: RemoteEvent,
}

type Session = {
	plot: Part,
	blocks: Instance,
	remotes: Remotes,
	previewFolder: Folder,
	ghost: GhostPreview.Ghost,
	gizmo: MoveGizmo.Gizmo, -- 3D-стрелки режима «Двигать»
	highlight: Highlight,
	rayParams: RaycastParams,
	mode: Mode,
	shapeId: string?,
	placement: BuildGrid.Placement?,
	canAct: boolean, -- можно ли сделать ЛКМ в текущей точке (поставить / вырезать)
	hovered: Instance?, -- корень блока под курсором (Part или Model)
	factionId: string?, -- фракция участка: палитра и стиль колонн в призраке
	lastActionTime: number,
	connections: { RBXScriptConnection },
}

local BIND_NAME = "BuildController"
local RAY_LENGTH = 2000
local CLIENT_PLACE_COOLDOWN = 0.1

local localPlayer = Players.LocalPlayer

local BuildController = {}

local session: Session? = nil
-- Поворот призрака в градусах; запоминается между сессиями строительства.
local angles: BuildGrid.Angles = { yaw = 0, pitch = 0, roll = 0 }

-- Открыто меню (пауза, настройки): редактор не строит и не реагирует на клавиши.
local paused = false

-- ===== Луч из курсора =====

-- Куда смотрит курсор: только своя плита или блоки на ней (декор и призрак исключены).
local function raycastMouse(s: Session): RaycastResult?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end

	local exclude: { Instance } = { s.previewFolder }
	local decor = s.plot:FindFirstChild(BuildConfig.DecorFolderName)
	if decor then
		table.insert(exclude, decor)
	end
	if localPlayer.Character then
		table.insert(exclude, localPlayer.Character)
	end
	s.rayParams.FilterDescendantsInstances = exclude

	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local result = workspace:Raycast(ray.Origin, ray.Direction * RAY_LENGTH, s.rayParams)
	if not result then
		return nil
	end
	if result.Instance == s.plot or result.Instance:IsDescendantOf(s.blocks) then
		return result
	end
	return nil
end

-- Свой поставленный (в том числе уже вырезанный) блок под курсором или nil.
-- Для составного блока луч попадает в одну деталь — возвращаем всю модель
-- (прямого ребёнка папки Blocks), чтобы подсветка и «Снос» работали с блоком целиком.
local function ownBlockFrom(s: Session, result: RaycastResult?): Instance?
	if not result then
		return nil
	end
	local node: Instance? = result.Instance
	while node and node.Parent ~= s.blocks do
		node = node.Parent
	end
	if node and node:GetAttribute(BuildConfig.Attributes.OwnerUserId) == localPlayer.UserId then
		return node
	end
	return nil
end

local function setHovered(s: Session, part: Instance?)
	if part ~= s.hovered then
		s.hovered = part
		s.highlight.Adornee = part
		s.highlight.Enabled = part ~= nil
	end
end

-- ===== Режимы =====

local function shapeName(shapeId: string): string
	return BlockCatalog.displayName(shapeId)
end

-- Свой размер из панели «Точность»: базовая форма и резак меняются по осям свободно,
-- составной блок растягивается пропорционально (nil = сейчас размер не нужен).
local function activeSize(s: Session): Vector3?
	local shapeId = s.shapeId
	local shape = if shapeId then BuildConfig.Shapes[shapeId] else nil
	if not shape or (s.mode ~= "Place" and s.mode ~= "Carve") then
		return nil
	end
	return BuildSettingsController.get().size or shape.size
end

local function isBlade(s: Session): boolean
	return s.mode == "Carve" and BuildSettingsController.get().cutterShape == BuildConfig.CutterBladeId
end

-- Сообщает панели, чей размер редактируется, и перестраивает призрак под этот размер.
local function syncSize(s: Session)
	local shapeId = s.shapeId
	local shape = if shapeId then BuildConfig.Shapes[shapeId] else nil
	BuildSettingsController.setCarveMode(s.mode == "Carve")
	if isBlade(s) then
		BuildSettingsController.setSizeTarget(BuildConfig.CutterBladeId, BuildConfig.BladeDefaultSize, true)
	elseif shapeId and shape and (s.mode == "Place" or s.mode == "Carve") then
		local minSize, maxSize = BuildSize.limits(shape)
		BuildSettingsController.setSizeTarget(shapeId, shape.size, false, minSize, maxSize)
	else
		BuildSettingsController.setSizeTarget(nil)
	end
	if shapeId then
		s.ghost.setShape(shapeId, s.factionId, activeSize(s))
	end
end

local describeBrush: () -> string

local function describeMode(s: Session): string
	local shapeId = s.shapeId
	if isBlade(s) then
		return "Резак-полоса: ЛКМ — разрезать, R — повернуть лезвие"
	elseif s.mode == "Move" then
		return "Перенос: ЛКМ по своему блоку, затем тяните стрелки"
	elseif s.mode == "Paint" then
		return describeBrush()
	end
	if s.mode == "Place" and shapeId then
		return "Установка: " .. shapeName(shapeId) .. ". ЛКМ — поставить"
	elseif s.mode == "Carve" and shapeId then
		return "Резак, форма: " .. shapeName(shapeId) .. ". ЛКМ — вырезать"
	elseif s.mode == "Delete" then
		return "Снос: ЛКМ по своему блоку"
	end
	return "Откройте «Блоки» (B) и выберите форму"
end

-- Переключение режима по выбору на нижней панели (форма + инструмент).
local function applySelection(s: Session, shapeId: string?, toolId: string?)
	s.placement = nil
	s.canAct = false
	setHovered(s, nil)

	local shape = if shapeId then BuildConfig.Shapes[shapeId] else nil
	local hasShape = shape ~= nil
	if toolId == BuildConfig.CarveSlotId and shape and shape.prefab then
		-- Резак работает только базовыми формами (CSG по одному Part).
		shapeId = "Block"
	end
	if toolId == BuildConfig.CarveSlotId and hasShape then
		s.mode = "Carve"
	elseif toolId == BuildConfig.DeleteSlotId then
		s.mode = "Delete"
	elseif toolId == BuildConfig.MoveSlotId then
		s.mode = "Move"
	elseif toolId == BuildConfig.PaintSlotId then
		s.mode = "Paint"
	elseif toolId == nil and hasShape then
		s.mode = "Place"
	else
		-- Ничего не выбрано или инструмент без призрака («Покраска»).
		s.mode = "None"
	end

	if (s.mode == "Place" or s.mode == "Carve") and shapeId then
		s.shapeId = shapeId
	else
		s.shapeId = nil
	end
	if s.mode ~= "Move" then
		s.gizmo.select(nil)
	end
	local highlightColor = if s.mode == "Move"
		then BuildConfig.MoveHighlightColor
		elseif s.mode == "Paint" then BuildConfig.PaintHighlightColor
		else BuildConfig.DeleteHighlightColor
	s.highlight.FillColor = highlightColor
	s.highlight.OutlineColor = highlightColor
	syncSize(s)
	s.ghost.hide()
	BuildSettingsController.setMode(describeMode(s))
end

-- ===== Действия =====

local function cooldownPassed(s: Session, cooldown: number): boolean
	local now = os.clock()
	if now - s.lastActionTime < cooldown then
		return false
	end
	s.lastActionTime = now
	return true
end

-- ЛКМ в режиме установки: отправляем «намерение» — форму, центр (в координатах
-- участка) и три угла. Сервер сам проверит границы и пересечения.
local function tryPlace(s: Session)
	local shapeId = s.shapeId
	local placement = s.placement
	if not shapeId or not placement then
		return
	end
	if not s.canAct then
		BuildSettingsController.notify("Здесь строить нельзя: фигура выходит за плиту или задевает блок")
		return
	end
	if not cooldownPassed(s, CLIENT_PLACE_COOLDOWN) then
		return
	end
	-- Настенная форма могла развернуться к стене сама: тогда шлём её углы, а не углы игрока.
	local used = placement.angles or angles
	s.remotes.place:FireServer(shapeId, placement.localCenter, used.yaw, used.pitch, used.roll, activeSize(s))
end

-- ЛКМ в режиме резака: сервер вычтет форму призрака из задетых блоков (SubtractAsync).
local function tryCarve(s: Session)
	local shapeId = s.shapeId
	local placement = s.placement
	if not shapeId or not placement then
		return
	end
	if not s.canAct then
		BuildSettingsController.notify("Резак ничего не задевает: наведите его на свой блок")
		return
	end
	if not cooldownPassed(s, BuildConfig.CarveCooldown) then
		return
	end
	s.remotes.carve:FireServer(shapeId, placement.localCenter, angles.yaw, angles.pitch, angles.roll, activeSize(s))
end

local function tryRemove(s: Session, part: Instance?)
	if part then
		s.remotes.remove:FireServer(part)
	end
end

-- Деталь своего блока под курсором: цель покраски и скрижалей (у модели — отдельная часть).
local function paintTarget(s: Session, result: RaycastResult?): BasePart?
	if result and ownBlockFrom(s, result) then
		return result.Instance
	end
	return nil
end

function describeBrush(): string
	local brush = PaintMenuController.getBrush()
	local id = if brush then brush.id else nil
	if brush and brush.kind == "Erase" then
		return "Очистить грань: ЛКМ по грани со скрижалью"
	elseif brush and brush.kind == "Material" and id then
		local material = PaintCatalog.MaterialById[id]
		return "Покраска: " .. (if material then material.displayName else id) .. ". ЛКМ по блоку или детали"
	elseif brush and brush.kind == "Tablet" and id then
		local tablet = PaintCatalog.TabletById[id]
		return "Скрижаль «" .. (if tablet then tablet.title else id) .. "». ЛКМ по грани блока"
	end
	return "Покраска / Скрижали: выберите материал или скрижаль в меню"
end

-- ЛКМ в режиме «Покраска / Скрижали»: действие зависит от выбранной в меню кисти.
local function tryPaint(s: Session)
	local brush = PaintMenuController.getBrush()
	if not brush then
		BuildSettingsController.notify("Сначала выберите материал или скрижаль в меню")
		return
	end
	local result = raycastMouse(s)
	local part = paintTarget(s, result)
	if not result or not part then
		BuildSettingsController.notify("Наведите курсор на свой блок")
		return
	end
	if brush.kind == "Material" then
		s.remotes.paint:FireServer(part, brush.id)
	elseif brush.kind == "Tablet" then
		s.remotes.tablet:FireServer(part, result.Position, result.Normal, brush.id)
	else
		s.remotes.erase:FireServer(part, result.Normal)
	end
end

-- R / T / Y: поворот на текущий шаг панели «Точность» (призрак довернётся плавно).
local function rotate(axis: "yaw" | "pitch" | "roll")
	local stepDegrees = BuildSettingsController.get().rotationStep
	if axis == "yaw" then
		angles.yaw = BuildGrid.addAngle(angles.yaw, stepDegrees)
	elseif axis == "pitch" then
		angles.pitch = BuildGrid.addAngle(angles.pitch, stepDegrees)
	else
		angles.roll = BuildGrid.addAngle(angles.roll, stepDegrees)
	end
	BuildSettingsController.setAngles(angles)
end

-- ===== Кадр =====

local function step(dt: number)
	local s = session
	if not s or paused then
		return
	end

	local result = raycastMouse(s)
	local shapeId = s.shapeId
	local shape: BuildConfig.Shape? = nil
	if shapeId then
		shape = BuildConfig.Shapes[shapeId]
	end

	if (s.mode == "Place" or s.mode == "Carve") and shapeId and shape then
		local size = activeSize(s)
		local placement: BuildGrid.Placement? = nil
		if result then
			local hit = result.Instance
			if hit:IsA("BasePart") then
				local settings = BuildSettingsController.get()
				placement = BuildGrid.computePlacement({
					plot = s.plot,
					shapeId = shapeId,
					size = size,
					angles = angles,
					gridStep = settings.gridStep,
					snapToCenter = settings.snapToCenter,
					inward = s.mode == "Carve",
					hitPart = hit,
					hitPos = result.Position,
					hitNormal = result.Normal,
				})
			end
		end
		s.placement = placement

		if placement then
			local color: Color3
			if s.mode == "Place" then
				-- Установка: целиком на плите 200x200 и ни с чем не пересекается.
				s.canAct = BuildGrid.isInsideArea(s.plot, placement.localCenter, placement.extents)
					and not (
						if shape.prefab
							then BuildGrid.isShapeBlocked(s.plot, placement.cframe, shapeId, size)
							else BuildGrid.isBlocked(s.plot, placement.cframe, size or shape.size)
					)
				color = if s.canAct then BuildConfig.GhostValidColor else BuildConfig.GhostInvalidColor
			else
				-- Резак: фиолетовый, если задевает хотя бы один свой блок, иначе оранжевый.
				local targets = BuildGrid.findCarveTargets(s.plot, placement.cframe, size or shape.size, localPlayer.UserId)
				s.canAct = #targets > 0
				color = if s.canAct then BuildConfig.CarveActiveColor else BuildConfig.CarveIdleColor
			end
			s.ghost.update(placement.cframe, color, dt)
		else
			s.canAct = false
			s.ghost.hide()
		end
	elseif s.mode == "Delete" then
		setHovered(s, ownBlockFrom(s, result))
	elseif s.mode == "Paint" then
		setHovered(s, paintTarget(s, result))
	elseif s.mode == "Move" then
		-- Подсвечиваем блок, который выберет клик (кроме уже выбранного и пока тянут стрелку).
		local target = if s.gizmo.isBusy() then nil else ownBlockFrom(s, result)
		setHovered(s, if target ~= s.gizmo.getSelected() then target else nil)
	end
	s.gizmo.update(dt)
end

-- ===== Публичный API =====

function BuildController.setPaused(value: boolean)
	paused = value
	local s = session
	if value and s then
		s.ghost.hide()
		s.highlight.Adornee = nil
		s.highlight.Enabled = false
		s.hovered = nil
	end
end

function BuildController.isActive(): boolean
	return session ~= nil
end

function BuildController.stop()
	local s = session
	if not s then
		return
	end
	session = nil
	RunService:UnbindFromRenderStep(BIND_NAME)
	for _, connection in s.connections do
		connection:Disconnect()
	end
	s.ghost.destroy()
	s.gizmo.destroy()
	s.previewFolder:Destroy()
	BuildSettingsController.hide()
end

local function waitRemote(name: string): RemoteEvent?
	local remote = ReplicatedStorage.Shared:WaitForChild(name, 10)
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end
	return nil
end

-- Включает строительный редактор на участке игрока. Вызывается из MenuController
-- после того, как включилась строительная камера и показалась нижняя панель.
function BuildController.start(plot: Part, buildHud: BuildHud): boolean
	BuildController.stop()

	-- Шаг 1. Ждём папку блоков и RemoteEvent'ы от сервера.
	local blocks = plot:WaitForChild(BuildConfig.BlocksFolderName, 10)
	local place = waitRemote(BuildConfig.PlaceRemoteName)
	local remove = waitRemote(BuildConfig.RemoveRemoteName)
	local carve = waitRemote(BuildConfig.CarveRemoteName)
	local move = waitRemote(BuildConfig.MoveRemoteName)
	local paint = waitRemote(BuildConfig.PaintRemoteName)
	local tablet = waitRemote(BuildConfig.TabletRemoteName)
	local erase = waitRemote(BuildConfig.EraseTabletRemoteName)
	local light = waitRemote(BuildConfig.ToggleLightRemoteName)
	local notice = waitRemote(BuildConfig.NoticeRemoteName)
	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	if not blocks or not place or not remove or not carve or not move then
		warn("[BuildController] Не найдены Blocks или RemoteEvent'ы, строительство не включено")
		return false
	end
	if not paint or not tablet or not erase or not light or not notice or not playerGui then
		warn("[BuildController] Не найдены Blocks или RemoteEvent'ы, строительство не включено")
		return false
	end

	-- Шаг 2. Локальные объекты предпросмотра (созданы на клиенте — сервер их не видит).
	local previewFolder = Instance.new("Folder")
	previewFolder.Name = "BuildPreview"
	previewFolder.Parent = workspace

	local highlight = Instance.new("Highlight")
	highlight.Name = "DeleteHighlight"
	highlight.FillColor = BuildConfig.DeleteHighlightColor
	highlight.OutlineColor = BuildConfig.DeleteHighlightColor
	highlight.FillTransparency = 0.55
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Enabled = false
	highlight.Parent = previewFolder

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	local s: Session = {
		plot = plot,
		blocks = blocks,
		remotes = {
			place = place,
			remove = remove,
			carve = carve,
			move = move,
			paint = paint,
			tablet = tablet,
			erase = erase,
			light = light,
			notice = notice,
		},
		previewFolder = previewFolder,
		ghost = GhostPreview.new(previewFolder),
		gizmo = MoveGizmo.new(plot, previewFolder, playerGui, {
			getGridStep = function(): number
				return BuildSettingsController.get().gridStep
			end,
			commit = function(block: Instance, localOffset: Vector3)
				move:FireServer(block, localOffset)
			end,
			notify = BuildSettingsController.notify,
		}),
		highlight = highlight,
		rayParams = rayParams,
		mode = "None",
		shapeId = nil,
		placement = nil,
		canAct = false,
		hovered = nil,
		factionId = nil,
		lastActionTime = 0,
		connections = {},
	}
	session = s

	-- Фракция участка (ставит сервер): палитра призрака и «родные» блоки в каталоге.
	local faction = plot:GetAttribute(PlotConfig.Attributes.FactionId)
	s.factionId = if typeof(faction) == "string" then faction else nil
	local setFaction = buildHud.setFaction
	if setFaction then
		setFaction(s.factionId)
	end

	-- Шаг 3. Панель «Точность» справа (шаг сетки, шаг поворота, магнит).
	BuildSettingsController.show()
	BuildSettingsController.setAngles(angles)

	-- Шаг 4. Выбор на нижней панели (форма + инструмент).
	applySelection(s, buildHud.getSelection())
	table.insert(
		s.connections,
		buildHud.SelectionChanged:Connect(function(shapeId: string?, toolId: string?)
			applySelection(s, shapeId, toolId)
		end)
	)

	-- Кнопка «Сброс» на панели «Точность»: все углы в 0.
	-- Смена кисти в меню «Покраска / Скрижали»: обновляем подпись режима.
	table.insert(
		s.connections,
		PaintMenuController.Changed:Connect(function()
			BuildSettingsController.setMode(describeMode(s))
		end)
	)

	-- Смена формы резака или размера на панели: обновляем призрак и подпись режима.
	table.insert(
		s.connections,
		BuildSettingsController.Changed:Connect(function()
			syncSize(s)
			BuildSettingsController.setMode(describeMode(s))
		end)
	)

	table.insert(
		s.connections,
		BuildSettingsController.ResetRotationRequested:Connect(function()
			angles.yaw = 0
			angles.pitch = 0
			angles.roll = 0
			BuildSettingsController.setAngles(angles)
		end)
	)

	-- Сообщения сервера (лимит блоков, неудачный разрез и т.п.).
	table.insert(
		s.connections,
		notice.OnClientEvent:Connect(function(text: unknown)
			if typeof(text) == "string" then
				BuildSettingsController.notify(text)
			end
		end)
	)

	-- Шаг 5. Клавиатура и мышь. ПКМ здесь не обрабатывается — она целиком у камеры.
	table.insert(
		s.connections,
		UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			if processed or paused or UserInputService:GetFocusedTextBox() then
				return
			end

			local key = input.KeyCode
			local shaping = s.mode == "Place" or s.mode == "Carve"
			if key == BuildConfig.Keys.RotateY then
				if shaping then
					rotate("yaw")
				end
			elseif key == BuildConfig.Keys.TiltX then
				if shaping then
					rotate("pitch")
				end
			elseif key == BuildConfig.Keys.TiltZ then
				if shaping then
					rotate("roll")
				end
			elseif key == BuildConfig.Keys.QuickDelete then
				-- X: быстрое удаление своего блока под курсором в любом режиме.
				tryRemove(s, ownBlockFrom(s, raycastMouse(s)))
			elseif key == BuildConfig.Keys.ToggleLight then
				-- L: зажечь или погасить свой светильник под курсором в любом режиме.
				local block = ownBlockFrom(s, raycastMouse(s))
				if block then
					s.remotes.light:FireServer(block)
				end
			elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
				if s.mode == "Place" then
					tryPlace(s)
				elseif s.mode == "Carve" then
					tryCarve(s)
				elseif s.mode == "Delete" then
					tryRemove(s, ownBlockFrom(s, raycastMouse(s)))
				elseif s.mode == "Paint" then
					tryPaint(s)
				elseif s.mode == "Move" then
					-- Откладываем на такт: клик по стрелке — это перетаскивание, а не смена выбора.
					task.defer(function()
						if session == s and s.mode == "Move" and not s.gizmo.isBusy() then
							s.gizmo.select(ownBlockFrom(s, raycastMouse(s)))
						end
					end)
				end
			end
		end)
	)

	-- Шаг 6. Обновление призрака каждый кадр — после того, как сдвинулась камера.
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 2, step)

	-- Участок удалён (игрок вышел/перезашёл) — выключаемся.
	table.insert(s.connections, plot.Destroying:Connect(BuildController.stop))
	return true
end

return BuildController
