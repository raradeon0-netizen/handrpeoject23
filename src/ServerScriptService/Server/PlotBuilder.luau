--!strict
-- PlotBuilder: физически создаёт Part участка с нужным материалом и цветом,
-- сеткой для стройки, бордюром и угловыми элементами.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotConfig = require(ReplicatedStorage.Shared.PlotConfig)

local PlotBuilder = {}

-- Создаёт один анкерный Part-деталь декора.
local function addPart(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	material: Enum.Material,
	color: Color3
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.Material = material
	part.Color = color
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Едва заметная строительная сетка поверх участка (Texture на верхней грани).
local function addGrid(plot: Part)
	local grid = Instance.new("Texture")
	grid.Name = "BuildGrid"
	grid.Texture = PlotConfig.GridTexture
	grid.Face = Enum.NormalId.Top
	grid.StudsPerTileU = PlotConfig.GridStudsPerTile
	grid.StudsPerTileV = PlotConfig.GridStudsPerTile
	grid.Transparency = PlotConfig.GridTransparency
	grid.Color3 = PlotConfig.GridColor
	grid.Parent = plot
end

-- Бордюр: четыре планки по краю участка. Длинные (север/юг) идут на всю ширину,
-- короткие (восток/запад) заходят между ними, чтобы планки не пересекались.
local function addBorder(decor: Instance, center: Vector3, style: PlotConfig.PlotStyle)
	local half = PlotConfig.PlotSize / 2
	local width = PlotConfig.BorderWidth
	local height = PlotConfig.BorderHeight
	local surfaceY = center.Y + PlotConfig.PlotThickness / 2
	local y = surfaceY + height / 2
	local offset = half - width / 2

	local function rail(name: string, size: Vector3, dx: number, dz: number)
		addPart(
			decor,
			name,
			size,
			CFrame.new(center.X + dx, y, center.Z + dz),
			style.borderMaterial,
			style.borderColor
		)
	end

	local long = PlotConfig.PlotSize
	local short = PlotConfig.PlotSize - width * 2
	rail("BorderNorth", Vector3.new(long, height, width), 0, -offset)
	rail("BorderSouth", Vector3.new(long, height, width), 0, offset)
	rail("BorderEast", Vector3.new(width, height, short), offset, 0)
	rail("BorderWest", Vector3.new(width, height, short), -offset, 0)
end

-- Колонна: база + цилиндрический ствол + капитель.
local function addColumn(decor: Instance, name: string, base: Vector3, style: PlotConfig.PlotStyle)
	local baseSize = PlotConfig.CornerBaseSize
	local slab = 2 -- толщина базы и капители
	local shaftHeight = PlotConfig.CornerHeight - slab * 2
	local shaftDiameter = baseSize - 3

	addPart(
		decor,
		name .. "Base",
		Vector3.new(baseSize, slab, baseSize),
		CFrame.new(base + Vector3.new(0, slab / 2, 0)),
		style.cornerMaterial,
		style.cornerColor
	)

	-- Цилиндр Roblox вытянут вдоль оси X, поэтому поворачиваем его «стоймя».
	local shaft = addPart(
		decor,
		name .. "Shaft",
		Vector3.new(shaftHeight, shaftDiameter, shaftDiameter),
		CFrame.new(base + Vector3.new(0, slab + shaftHeight / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		style.cornerMaterial,
		style.cornerColor
	)
	shaft.Shape = Enum.PartType.Cylinder

	addPart(
		decor,
		name .. "Capital",
		Vector3.new(baseSize, slab, baseSize),
		CFrame.new(base + Vector3.new(0, slab + shaftHeight + slab / 2, 0)),
		style.cornerMaterial,
		style.cornerColor
	)
end

-- Массивный блок с «шапкой» (для Египта).
local function addBlock(decor: Instance, name: string, base: Vector3, style: PlotConfig.PlotStyle)
	local baseSize = PlotConfig.CornerBaseSize
	local capHeight = 2
	local bodyHeight = PlotConfig.CornerHeight - capHeight

	addPart(
		decor,
		name .. "Body",
		Vector3.new(baseSize, bodyHeight, baseSize),
		CFrame.new(base + Vector3.new(0, bodyHeight / 2, 0)),
		style.cornerMaterial,
		style.cornerColor
	)
	addPart(
		decor,
		name .. "Cap",
		Vector3.new(baseSize - 2, capHeight, baseSize - 2),
		CFrame.new(base + Vector3.new(0, bodyHeight + capHeight / 2, 0)),
		style.borderMaterial,
		style.capColor or style.borderColor
	)
end

-- Угловые элементы: по одному в каждом углу, вплотную к внешнему краю участка.
local function addCorners(decor: Instance, center: Vector3, style: PlotConfig.PlotStyle)
	local surfaceY = center.Y + PlotConfig.PlotThickness / 2
	local inset = PlotConfig.PlotSize / 2 - PlotConfig.CornerBaseSize / 2
	local corners = {
		{ name = "CornerNE", sx = 1, sz = -1 },
		{ name = "CornerSE", sx = 1, sz = 1 },
		{ name = "CornerSW", sx = -1, sz = 1 },
		{ name = "CornerNW", sx = -1, sz = -1 },
	}

	for _, corner in corners do
		local base = Vector3.new(center.X + corner.sx * inset, surfaceY, center.Z + corner.sz * inset)
		if style.cornerKind == "Column" then
			addColumn(decor, corner.name, base, style)
		else
			addBlock(decor, corner.name, base, style)
		end
	end
end

-- Создаёт участок 200x200 с центром в `center` и помещает его в `parent`.
function PlotBuilder.build(parent: Instance, player: Player, factionId: string, slot: number, center: Vector3): Part
	-- Шаг 1. Стиль по фракции (песок для Египта, мрамор для Рима и Греции).
	local style = PlotConfig.Styles[factionId] or PlotConfig.DefaultStyle

	-- Шаг 2. Сам Part: размер, положение, материал, цвет.
	local plot = Instance.new("Part")
	plot.Name = `Plot_{player.UserId}`
	plot.Size = Vector3.new(PlotConfig.PlotSize, PlotConfig.PlotThickness, PlotConfig.PlotSize)
	plot.Position = center
	plot.Anchored = true
	plot.Material = style.material
	plot.Color = style.color
	plot.TopSurface = Enum.SurfaceType.Smooth
	plot.BottomSurface = Enum.SurfaceType.Smooth

	-- Шаг 3. Метки владельца: их удобно читать из любых будущих скриптов.
	plot:SetAttribute(PlotConfig.Attributes.OwnerUserId, player.UserId)
	plot:SetAttribute(PlotConfig.Attributes.FactionId, factionId)
	plot:SetAttribute(PlotConfig.Attributes.SlotIndex, slot)

	-- Шаг 4. Оформление: сетка, бордюр и углы. Декор лежит внутри участка (папка Decor),
	-- поэтому исчезает вместе с ним, когда PlotService удаляет участок.
	addGrid(plot)
	local decor = Instance.new("Folder")
	decor.Name = "Decor"
	addBorder(decor, center, style)
	addCorners(decor, center, style)
	decor.Parent = plot

	-- Папка для построек игрока (заполняет BuildService, имя = BuildConfig.BlocksFolderName).
	-- Лежит внутри участка, поэтому блоки удаляются вместе с ним.
	local blocks = Instance.new("Folder")
	blocks.Name = "Blocks"
	blocks.Parent = plot

	-- Parent задаём последним, когда Part полностью настроен.
	plot.Parent = parent
	return plot
end

return PlotBuilder
