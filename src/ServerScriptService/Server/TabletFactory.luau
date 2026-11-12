--!strict
-- TabletFactory (сервер): декоративные скрижали с надписью на гранях блоков.
--   * скрижаль — тонкая плита, прижатая к грани по нормали попадания луча, с SurfaceGui на лицевой стороне;
--   * она становится потомком детали, на которую повешена: сносится и переезжает вместе с блоком;
--   * плита не участвует в коллизиях и запросах (CanQuery = false), поэтому не мешает стройке,
--     а клики «проходят» сквозь неё в блок — так работает «Очистить грань».

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildConfig = require(ReplicatedStorage.Shared.BuildConfig)
local BuildGrid = require(ReplicatedStorage.Shared.BuildGrid)
local PaintCatalog = require(ReplicatedStorage.Shared.PaintCatalog)

type Look = {
	material: Enum.Material,
	color: Color3,
	ink: Color3,
	border: Color3,
	borderTransparency: number,
	textStroke: number?, -- прозрачность тёмной обводки букв (nil = без обводки)
}

local LOOKS: { [PaintCatalog.TabletStyle]: Look } = {
	Stone = {
		material = Enum.Material.Limestone,
		color = Color3.fromRGB(196, 186, 165),
		ink = Color3.fromRGB(46, 38, 30),
		border = Color3.fromRGB(46, 38, 30),
		borderTransparency = 0.35,
	},
	-- Тёмный камень с золотом: светлые буквы с обводкой читаются при любом освещении.
	DarkStone = {
		material = Enum.Material.Slate,
		color = Color3.fromRGB(45, 35, 25),
		ink = Color3.fromRGB(255, 235, 180),
		border = Color3.fromRGB(255, 200, 60),
		borderTransparency = 0,
		textStroke = 0.15,
	},
}

local PIXELS_PER_STUD = 60
local TABLET_FONT = Enum.Font.Garamond -- античная антиква с кириллицей
local SAME_FACE_DOT = 0.9 -- скрижаль считается висящей на грани, если смотрит почти туда же

local TabletFactory = {}

local function isTablet(instance: Instance): boolean
	return instance:GetAttribute(BuildConfig.Attributes.TabletId) ~= nil
end

local function isBox(part: BasePart): boolean
	return part:IsA("Part") and part.Shape == Enum.PartType.Block
end

-- Протяжённость детали вдоль направления (для грани бокса — её ширина или высота).
local function span(part: BasePart, direction: Vector3): number
	local cframe, size = part.CFrame, part.Size
	return math.abs(direction:Dot(cframe.RightVector)) * size.X
		+ math.abs(direction:Dot(cframe.UpVector)) * size.Y
		+ math.abs(direction:Dot(cframe.LookVector)) * size.Z
end

local function makeLabel(name: string, text: string, look: Look, parent: Instance): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Text = text
	label.Font = TABLET_FONT
	label.TextColor3 = look.ink
	if look.textStroke then
		label.TextStrokeColor3 = Color3.new(0, 0, 0)
		label.TextStrokeTransparency = look.textStroke
	end
	label.TextScaled = true
	label.TextWrapped = true
	label.BackgroundTransparency = 1
	label.Parent = parent
	return label
end

local function buildInscription(tablet: PaintCatalog.Tablet, look: Look, parent: BasePart)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Inscription"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PIXELS_PER_STUD
	gui.LightInfluence = 0.4
	gui.Parent = parent

	-- Рамка с отступом от края плиты.
	local border = Instance.new("Frame")
	border.Name = "Border"
	border.AnchorPoint = Vector2.new(0.5, 0.5)
	border.Position = UDim2.fromScale(0.5, 0.5)
	border.Size = UDim2.fromScale(0.94, 0.9)
	border.BackgroundTransparency = 1
	border.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Color = look.border
	stroke.Thickness = 4
	stroke.Transparency = look.borderTransparency
	stroke.Parent = border

	local title = makeLabel("Title", tablet.title, look, border)
	title.Position = UDim2.fromScale(0.05, 0.05)
	title.Size = UDim2.fromScale(0.9, 0.2)

	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.AnchorPoint = Vector2.new(0.5, 0)
	divider.Position = UDim2.fromScale(0.5, 0.27)
	divider.Size = UDim2.new(0.6, 0, 0, 2)
	divider.BackgroundColor3 = look.border
	divider.BackgroundTransparency = look.borderTransparency
	divider.BorderSizePixel = 0
	divider.Parent = border

	local body = makeLabel("Body", tablet.text, look, border)
	body.Position = UDim2.fromScale(0.05, 0.31)
	body.Size = UDim2.fromScale(0.9, 0.63)
end

-- Вешает скрижаль на грань детали part в точке попадания луча (hitPos, hitNormal — мировые).
function TabletFactory.place(
	plot: BasePart,
	part: BasePart,
	hitPos: Vector3,
	hitNormal: Vector3,
	tablet: PaintCatalog.Tablet
): BasePart
	local full = BuildConfig.TabletSize
	local aspect = full.X / full.Y
	local point, normal = hitPos, hitNormal.Unit

	-- У бокса берём точную грань: скрижаль ложится вплотную, без наклона от погрешности нормали.
	local faceCenter: Vector3? = nil
	if isBox(part) then
		local center, faceNormal = BuildGrid.getFace(part, normal)
		faceCenter, normal = center, faceNormal
		point -= normal * (point - center):Dot(normal)
	end

	-- Верх надписи — вверх участка; на горизонтальной грани — «вперёд» участка.
	local plotCFrame = plot.CFrame
	local up = if math.abs(normal:Dot(plotCFrame.UpVector)) > 0.99 then plotCFrame.LookVector else plotCFrame.UpVector
	local facing = CFrame.lookAt(point, point + normal, up)
	local right, top = facing.RightVector, facing.UpVector

	-- Не шире и не выше грани (но и не мельче читаемого минимума).
	local spanRight, spanTop = span(part, right), span(part, top)
	local width = math.clamp(spanRight, BuildConfig.TabletMinWidth, full.X)
	local height = math.min(width / aspect, math.max(spanTop, BuildConfig.TabletMinWidth / aspect))
	width = height * aspect

	if faceCenter then
		-- Сдвигаем к центру грани ровно настолько, чтобы плита не свисала с края.
		local offset = point - faceCenter
		local limitRight = math.max((spanRight - width) / 2, 0)
		local limitTop = math.max((spanTop - height) / 2, 0)
		point = faceCenter
			+ right * math.clamp(offset:Dot(right), -limitRight, limitRight)
			+ top * math.clamp(offset:Dot(top), -limitTop, limitTop)
	end

	local position = point + normal * (full.Z / 2)

	-- Новая скрижаль заменяет те, что она перекрыла бы на этой же грани.
	for _, child in part:GetChildren() do
		if
			child:IsA("BasePart")
			and isTablet(child)
			and child.CFrame.LookVector:Dot(normal) > SAME_FACE_DOT
			and (child.Position - position).Magnitude < math.max(height, child.Size.Y)
		then
			child:Destroy()
		end
	end

	local look = LOOKS[tablet.style]
	local plaque = Instance.new("Part")
	plaque.Name = "Tablet"
	plaque.Size = Vector3.new(width, height, full.Z)
	plaque.CFrame = CFrame.lookAt(position, position + normal, up) -- лицевая грань (Front) смотрит наружу
	plaque.Anchored = true
	plaque.CanCollide = false
	plaque.CanQuery = false
	plaque.CanTouch = false
	plaque.CastShadow = false
	plaque.Material = look.material
	plaque.Color = look.color
	plaque.TopSurface = Enum.SurfaceType.Smooth
	plaque.BottomSurface = Enum.SurfaceType.Smooth
	plaque:SetAttribute(BuildConfig.Attributes.TabletId, tablet.id)
	buildInscription(tablet, look, plaque)
	plaque.Parent = part
	return plaque
end

-- Снимает все скрижали с грани детали, на которую указывает нормаль. Возвращает их число.
function TabletFactory.erase(part: BasePart, hitNormal: Vector3): number
	local normal = hitNormal.Unit
	if isBox(part) then
		local _, faceNormal = BuildGrid.getFace(part, normal)
		normal = faceNormal
	end
	local removed = 0
	for _, child in part:GetChildren() do
		if child:IsA("BasePart") and isTablet(child) and child.CFrame.LookVector:Dot(normal) > SAME_FACE_DOT then
			child:Destroy()
			removed += 1
		end
	end
	return removed
end

-- Сколько скрижалей уже висит на постройках участка.
function TabletFactory.count(blocks: Instance): number
	local total = 0
	for _, descendant in blocks:GetDescendants() do
		if isTablet(descendant) then
			total += 1
		end
	end
	return total
end

return TabletFactory
