--!strict
-- BlockLibrary: геометрия составных античных блоков (Prefabs).
-- Каждый префаб описан как список деталей (Part / WedgePart / CornerWedgePart / цилиндр)
-- со смещениями ОТНОСИТЕЛЬНО ЦЕНТРА габаритной коробки формы (BuildConfig.Shapes[id].size).
-- Модуль общий: сервер (BlockFactory) строит из него настоящие модели,
-- клиент (GhostPreview) — призрак той же формы, BuildGrid — коробки для проверки пересечений.
--
-- Роли деталей задают материал из палитры фракции (BuildConfig.FactionPalettes):
--   Main — основной камень, Trim — окантовка/второй камень,
--   Accent — золото (бронза), Detail — цветная вставка (бирюза Египта, порфир Рима, синь Греции).

local BuildConfig = require(script.Parent.BuildConfig)

export type Role = "Main" | "Trim" | "Accent" | "Detail"
export type PieceKind = "Block" | "Wedge" | "CornerWedge" | "Cylinder"

export type Piece = {
	kind: PieceKind,
	role: Role,
	size: Vector3, -- размер самой детали (для цилиндра ось — X)
	cframe: CFrame, -- положение относительно центра формы
}

export type Box = {
	cframe: CFrame, -- относительно центра формы
	size: Vector3,
}

type Builder = (factionId: string?) -> { Piece }
type Collision = "bounds" | "pieces"

type Prefab = {
	build: Builder,
	-- Чем проверять пересечения при установке: целой габаритной коробкой или
	-- коробками деталей (тогда под аркой/рядом со ступенями остаётся свободное место).
	collision: Collision,
}

local BlockLibrary = {}

-- ===== Калибровка клиньев =====
-- Чтобы пирамиды и скаты собирались правильно независимо от того, как движок
-- ориентирует WedgePart и CornerWedgePart, один раз «прощупываем» их лучами
-- и узнаём, где у клина высокая сторона, а у углового клина — вершина.

type Calibration = { wedgeHighZ: number, cornerX: number, cornerZ: number }

local PROBE_HEIGHT = 5000
local calibration: Calibration? = nil

local function probeHeights(className: string, points: { Vector2 }): { number }
	local probe = Instance.new(className :: any) :: BasePart
	probe.Anchored = true
	probe.CanCollide = false
	probe.CanTouch = false
	probe.CastShadow = false
	probe.Transparency = 1
	probe.Size = Vector3.new(4, 4, 4)
	probe.CFrame = CFrame.new(0, PROBE_HEIGHT, 0)
	probe.Parent = workspace

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { probe }

	local heights: { number } = {}
	for index, point in points do
		local origin = Vector3.new(point.X, PROBE_HEIGHT + 10, point.Y)
		local hit = workspace:Raycast(origin, Vector3.new(0, -20, 0), params)
		heights[index] = if hit then hit.Position.Y else -math.huge
	end
	probe:Destroy()
	return heights
end

local function calibrate(): Calibration
	local existing = calibration
	if existing then
		return existing
	end

	-- Клин: какая сторона по Z выше.
	local wedgeHighZ = 1
	local w = probeHeights("WedgePart", { Vector2.new(0, -1.6), Vector2.new(0, 1.6) })
	if w[1] > w[2] then
		wedgeHighZ = -1
	end

	-- Угловой клин: над каким углом основания вершина.
	local corners = { Vector2.new(-1, -1), Vector2.new(-1, 1), Vector2.new(1, -1), Vector2.new(1, 1) }
	local points: { Vector2 } = {}
	for index, c in corners do
		points[index] = c * 1.6
	end
	local heights = probeHeights("CornerWedgePart", points)
	local best, bestHeight = corners[3], -math.huge
	for index, h in heights do
		if h > bestHeight then
			best, bestHeight = corners[index], h
		end
	end

	local result: Calibration = { wedgeHighZ = wedgeHighZ, cornerX = best.X, cornerZ = best.Y }
	calibration = result
	return result
end

-- ===== Помощники построения =====

local VERTICAL = CFrame.Angles(0, 0, math.rad(90)) -- ось цилиндра X -> вертикаль

local function add(list: { Piece }, kind: PieceKind, role: Role, size: Vector3, cframe: CFrame)
	table.insert(list, { kind = kind, role = role, size = size, cframe = cframe })
end

local function block(list: { Piece }, role: Role, sx: number, sy: number, sz: number, x: number, y: number, z: number)
	add(list, "Block", role, Vector3.new(sx, sy, sz), CFrame.new(x, y, z))
end

-- Вертикальный цилиндр (диаметр, высота) с центром в (x, y, z).
local function cylinder(list: { Piece }, role: Role, diameter: number, height: number, x: number, y: number, z: number)
	add(list, "Cylinder", role, Vector3.new(height, diameter, diameter), CFrame.new(x, y, z) * VERTICAL)
end

-- Клин, высокая сторона которого смотрит в highToward (+1 = +Z, -1 = -Z) в осях cframe.
local function wedge(list: { Piece }, role: Role, size: Vector3, cframe: CFrame, highToward: number)
	local cal = calibrate()
	local flip = if cal.wedgeHighZ == highToward then CFrame.identity else CFrame.Angles(0, math.pi, 0)
	add(list, "Wedge", role, size, cframe * flip)
end

-- Угловой клин с основанием footprint (X, высота, Z) и вершиной над углом (apexX, apexZ).
local function cornerWedge(list: { Piece }, role: Role, footprint: Vector3, position: Vector3, apexX: number, apexZ: number)
	local cal = calibrate()
	for k = 0, 3 do
		local rotation = CFrame.Angles(0, k * math.pi / 2, 0)
		local v = rotation:VectorToWorldSpace(Vector3.new(cal.cornerX, 0, cal.cornerZ))
		if math.round(v.X) == apexX and math.round(v.Z) == apexZ then
			local size = if k % 2 == 1 then Vector3.new(footprint.Z, footprint.Y, footprint.X) else footprint
			add(list, "CornerWedge", role, size, CFrame.new(position) * rotation)
			return
		end
	end
end

-- Четырёхгранная пирамида из 4 угловых клиньев (вершины клиньев сходятся в центре).
-- inflate чуть расширяет основание — для «облицовки» поверх другой пирамиды без мерцания.
local function pyramid(list: { Piece }, role: Role, halfX: number, halfZ: number, height: number, baseY: number, inflate: number)
	local hx, hz = halfX + inflate, halfZ + inflate
	local cy = baseY + height / 2
	for _, qx in { -1, 1 } do
		for _, qz in { -1, 1 } do
			cornerWedge(list, role, Vector3.new(hx, height, hz), Vector3.new(qx * hx / 2, cy, qz * hz / 2), -qx, -qz)
		end
	end
end

-- ===== Префабы =====

-- Резная колонна: квадратная база, рифлёный (или составной) ствол и капитель.
-- Капитель зависит от фракции: Египет — лотос и пучок папируса, Греция — дорическая,
-- Рим — коринфская с золотыми листьями аканта.
local function column(height: number): Builder
	return function(factionId: string?): { Piece }
		local list: { Piece } = {}
		local y0 = -height / 2
		local top = height / 2

		-- База: квадратный плинт + торус + тонкое кольцо.
		block(list, "Trim", 4, 1, 4, 0, y0 + 0.5, 0)
		cylinder(list, "Main", 3.6, 0.5, 0, y0 + 1.25, 0)
		cylinder(list, "Trim", 3.1, 0.3, 0, y0 + 1.65, 0)

		local shaftBottom = y0 + 1.8
		local shaftTop = top - 2.2
		local shaftH = shaftTop - shaftBottom
		local shaftY = (shaftTop + shaftBottom) / 2

		if factionId == "Egypt" then
			-- Ствол — пучок стеблей папируса, перехваченный бирюзовыми лентами.
			cylinder(list, "Main", 2.0, shaftH, 0, shaftY, 0)
			for i = 0, 7 do
				local a = i * math.pi / 4
				cylinder(list, "Main", 0.9, shaftH, math.cos(a) * 0.95, shaftY, math.sin(a) * 0.95)
			end
			cylinder(list, "Detail", 2.95, 0.22, 0, shaftBottom + 0.3, 0)
			for k = 0, 2 do
				cylinder(list, "Detail", 2.95, 0.22, 0, shaftTop - 0.25 - k * 0.45, 0)
			end
			-- Капитель — раскрытый лотос с золотым поясом.
			cylinder(list, "Main", 2.8, 0.5, 0, shaftTop + 0.25, 0)
			cylinder(list, "Accent", 3.3, 0.6, 0, shaftTop + 0.8, 0)
			cylinder(list, "Main", 3.8, 0.6, 0, shaftTop + 1.4, 0)
			block(list, "Trim", 3, 0.5, 3, 0, top - 0.25, 0)
		elseif factionId == "Greece" then
			-- Дорический ордер: 12 каннелюр, эхин и квадратная абака.
			cylinder(list, "Main", 2.6, shaftH, 0, shaftY, 0)
			for i = 0, 11 do
				local cf = CFrame.new(0, shaftY, 0) * CFrame.Angles(0, i * math.pi / 6, 0) * CFrame.new(0, 0, 1.3)
				add(list, "Block", "Main", Vector3.new(0.34, shaftH, 0.34), cf)
			end
			cylinder(list, "Accent", 2.85, 0.3, 0, shaftTop + 0.15, 0)
			cylinder(list, "Main", 3.0, 0.3, 0, shaftTop + 0.45, 0)
			cylinder(list, "Main", 3.6, 0.6, 0, shaftTop + 0.9, 0)
			block(list, "Trim", 4, 1.0, 4, 0, top - 0.5, 0)
		else
			-- Рим (и по умолчанию): коринфский ордер — 16 каннелюр, колокол капители
			-- в два яруса золотых листьев аканта.
			cylinder(list, "Main", 2.6, shaftH, 0, shaftY, 0)
			for i = 0, 15 do
				local cf = CFrame.new(0, shaftY, 0) * CFrame.Angles(0, i * math.pi / 8, 0) * CFrame.new(0, 0, 1.3)
				add(list, "Block", "Trim", Vector3.new(0.26, shaftH, 0.26), cf)
			end
			cylinder(list, "Accent", 2.85, 0.2, 0, shaftTop + 0.1, 0)
			cylinder(list, "Main", 2.9, 1.2, 0, shaftTop + 0.8, 0)
			for tier = 0, 1 do
				for i = 0, 7 do
					local a = (i + tier * 0.5) * math.pi / 4
					local cf = CFrame.new(0, shaftTop + 0.55 + tier * 0.55, 0)
						* CFrame.Angles(0, a, 0)
						* CFrame.new(0, 0, 1.45)
						* CFrame.Angles(math.rad(15), 0, 0)
					add(list, "Block", "Accent", Vector3.new(0.6, 0.7, 0.25), cf)
				end
			end
			block(list, "Trim", 4, 0.8, 4, 0, top - 0.4, 0)
		end
		return list
	end
end

-- Обелиск 4x16x4: сужающийся ствол и золотой пирамидион из угловых клиньев.
local function obelisk(_factionId: string?): { Piece }
	local list: { Piece } = {}
	block(list, "Trim", 4, 1, 4, 0, -7.5, 0)
	block(list, "Detail", 3.4, 0.6, 3.4, 0, -6.7, 0)
	local segments = 6
	local bottom, topY = -6.4, 6
	local h = (topY - bottom) / segments
	for i = 0, segments - 1 do
		local width = 3.0 - (i + 0.5) / segments
		block(list, "Main", width, h, width, 0, bottom + h * (i + 0.5), 0)
	end
	pyramid(list, "Accent", 1.05, 1.05, 2, topY, 0)
	return list
end

-- Опоры арок (общие для круглой и ступенчатой).
local function archPiers(list: { Piece }, impostRole: Role)
	for _, sx in { -1, 1 } do
		block(list, "Trim", 3, 0.8, 4, sx * 4.5, -5.6, 0) -- база опоры
		block(list, "Main", 3, 5.8, 4, sx * 4.5, -2.3, 0) -- опора
		block(list, impostRole, 3, 0.4, 4, sx * 4.5, 0.8, 0) -- импост (пята свода)
	end
end

-- Античная арка 12x12x4: полукруглый свод из 9 клинчатых камней с золотым замковым камнем.
local function archRound(_factionId: string?): { Piece }
	local list: { Piece } = {}
	archPiers(list, "Accent")

	local cy, r, outer = 1.0, 3.0, 4.4 -- центр свода, внутренний и внешний радиусы
	local count = 9
	local mid = (r + outer) / 2
	local length = 2 * outer * math.sin(math.pi / (2 * count)) + 0.05
	for i = 0, count - 1 do
		local t = math.pi * (i + 0.5) / count
		local isKey = i == (count - 1) / 2
		local cf = CFrame.new(mid * math.cos(t), cy + mid * math.sin(t), 0) * CFrame.Angles(0, 0, t - math.pi / 2)
		add(list, "Block", if isKey then "Accent" else "Trim", Vector3.new(length, outer - r, 4), cf)
	end

	-- Пазухи свода: ступенчатое заполнение до карниза (утоплено на 0.1 за кольцо свода).
	local cornice = 5.4
	local band = 0.55
	for _, sx in { -1, 1 } do
		local x1 = 0
		while x1 < outer - 1e-6 do
			local x2 = math.min(x1 + band, outer)
			local bottomY = cy + math.sqrt(math.max(outer * outer - x2 * x2, 0))
			local h = cornice - bottomY
			if h > 0.01 then
				block(list, "Main", x2 - x1, h, 3.8, sx * (x1 + x2) / 2, bottomY + h / 2, 0)
			end
			x1 = x2
		end
		block(list, "Main", 6 - outer, cornice - cy, 3.8, sx * (outer + 6) / 2, (cy + cornice) / 2, 0)
	end
	block(list, "Trim", 12, 0.6, 4, 0, 5.7, 0) -- карниз
	return list
end

-- Ступенчатая (ложная) арка 12x12x4: свод из нависающих рядов камня, как в Египте.
local function archStepped(_factionId: string?): { Piece }
	local list: { Piece } = {}
	archPiers(list, "Detail")
	local rows = { { inner = 2.2, y = 1.0 }, { inner = 1.4, y = 2.2 }, { inner = 0.6, y = 3.4 } }
	for _, row in rows do
		for _, sx in { -1, 1 } do
			block(list, "Main", 6 - row.inner, 1.2, 4, sx * (row.inner + 6) / 2, row.y + 0.6, 0)
		end
	end
	block(list, "Trim", 12, 0.8, 4, 0, 5.0, 0) -- перемычка
	block(list, "Accent", 12, 0.6, 4, 0, 5.7, 0) -- золотой карниз
	return list
end

-- Лестница 8x4x8: 4 ступени, подъём к +Z (вращайте R), с кантом на каждой ступени.
local function stairs(_factionId: string?): { Piece }
	local list: { Piece } = {}
	for i = 1, 4 do
		local zFront = -4 + 2 * (i - 1)
		block(list, "Main", 8, i, 2, 0, -2 + i / 2, zFront + 1)
		block(list, "Trim", 7.9, 0.16, 0.32, 0, -2 + i - 0.07, zFront + 0.15)
	end
	return list
end

-- Пандус 8x4x8: плавный подъём (WedgePart) с бортиками.
local function ramp(_factionId: string?): { Piece }
	local list: { Piece } = {}
	wedge(list, "Main", Vector3.new(7, 4, 8), CFrame.identity, 1)
	wedge(list, "Trim", Vector3.new(0.5, 4, 8), CFrame.new(-3.75, 0, 0), 1)
	wedge(list, "Trim", Vector3.new(0.5, 4, 8), CFrame.new(3.75, 0, 0), 1)
	return list
end

-- Подиум храма (крепидома) 12x3x12: три ступени-основания.
local function crepidoma(_factionId: string?): { Piece }
	local list: { Piece } = {}
	block(list, "Trim", 12, 1, 12, 0, -1, 0)
	block(list, "Trim", 10, 1, 10, 0, 0, 0)
	block(list, "Main", 8, 1, 8, 0, 1, 0)
	return list
end

-- Пирамида 12x8x12: плинт, 4 угловых клина и золотое навершие.
local function pyramidPrefab(_factionId: string?): { Piece }
	local list: { Piece } = {}
	block(list, "Trim", 12, 0.5, 12, 0, -3.75, 0)
	pyramid(list, "Main", 6, 6, 7.5, -3.5, 0)
	-- Навершие — верхние 1.5 студа той же пирамиды, чуть шире, чтобы лечь поверх.
	pyramid(list, "Accent", 1.2, 1.2, 1.5, 2.5, 0.06)
	return list
end

-- Ступенчатая пирамида 12x8x12 (как пирамида Джосера) с золотой вершиной.
local function stepPyramid(_factionId: string?): { Piece }
	local list: { Piece } = {}
	block(list, "Main", 12, 2, 12, 0, -3, 0)
	block(list, "Trim", 9, 2, 9, 0, -1, 0)
	block(list, "Main", 6, 2, 6, 0, 1, 0)
	block(list, "Accent", 3, 2, 3, 0, 3, 0)
	return list
end

-- Фронтон / двускатная крыша 12x4x8: два клина, карниз, конёк и акротерии.
local function gableRoof(_factionId: string?): { Piece }
	local list: { Piece } = {}
	block(list, "Trim", 12, 0.6, 8, 0, -1.7, 0) -- карниз
	wedge(list, "Main", Vector3.new(12, 3.4, 4), CFrame.new(0, 0.3, -2), 1)
	wedge(list, "Main", Vector3.new(12, 3.4, 4), CFrame.new(0, 0.3, 2), -1)
	block(list, "Accent", 12, 0.3, 0.5, 0, 1.85, 0) -- конёк
	for _, sx in { -1, 1 } do
		block(list, "Accent", 0.5, 0.5, 0.5, sx * 5.75, 1.75, 0) -- акротерий на вершине
		for _, sz in { -1, 1 } do
			block(list, "Accent", 0.5, 0.4, 0.5, sx * 5.75, -1.2, sz * 3.75) -- угловые акротерии
		end
	end
	return list
end

-- Скат крыши 8x4x4: один клин (собирайте из них крыши и грани пирамид).
local function roofSlope(_factionId: string?): { Piece }
	local list: { Piece } = {}
	wedge(list, "Main", Vector3.new(8, 4, 4), CFrame.identity, 1)
	return list
end

-- Угол ската 4x4x4: угловой клин для углов пирамид и вальмовых крыш.
local function roofCorner(_factionId: string?): { Piece }
	local list: { Piece } = {}
	cornerWedge(list, "Main", Vector3.new(4, 4, 4), Vector3.zero, -1, 1)
	return list
end

-- Алтарь 8x4x4: пилястры по углам, цветные панели в золотой раме и золотой пояс.
local function altar(_factionId: string?): { Piece }
	local list: { Piece } = {}
	block(list, "Trim", 8, 0.6, 4, 0, -1.7, 0)
	block(list, "Main", 7, 2.6, 3, 0, -0.1, 0)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			block(list, "Trim", 0.6, 2.6, 0.6, sx * 3.45, -0.1, sz * 1.45)
		end
	end
	for _, sz in { -1, 1 } do
		block(list, "Detail", 4.4, 1.4, 0.1, 0, -0.1, sz * 1.53)
		block(list, "Accent", 4.8, 0.15, 0.14, 0, 0.675, sz * 1.55)
		block(list, "Accent", 4.8, 0.15, 0.14, 0, -0.875, sz * 1.55)
		block(list, "Accent", 0.15, 1.7, 0.14, -2.35, -0.1, sz * 1.55)
		block(list, "Accent", 0.15, 1.7, 0.14, 2.35, -0.1, sz * 1.55)
	end
	block(list, "Accent", 7.4, 0.3, 3.4, 0, 1.35, 0) -- золотой пояс
	block(list, "Main", 8, 0.5, 4, 0, 1.75, 0) -- столешница
	return list
end

-- Пьедестал 4x6x4: золотые рёбра, цветные панели и профилированный карниз.
local function pedestal(_factionId: string?): { Piece }
	local list: { Piece } = {}
	block(list, "Trim", 4, 0.8, 4, 0, -2.6, 0)
	block(list, "Main", 3.6, 0.4, 3.6, 0, -2.0, 0)
	block(list, "Main", 3, 3.6, 3, 0, 0, 0)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			block(list, "Accent", 0.25, 3.6, 0.25, sx * 1.45, 0, sz * 1.45)
		end
		block(list, "Detail", 1.8, 2.4, 0.08, 0, 0, sx * 1.52)
		block(list, "Detail", 0.08, 2.4, 1.8, sx * 1.52, 0, 0)
	end
	block(list, "Accent", 3.4, 0.3, 3.4, 0, 1.95, 0)
	block(list, "Main", 3.8, 0.5, 3.8, 0, 2.35, 0)
	block(list, "Trim", 4, 0.4, 4, 0, 2.8, 0)
	return list
end

local PREFABS: { [string]: Prefab } = {
	CarvedColumn = { build = column(16), collision = "bounds" },
	CarvedColumnShort = { build = column(8), collision = "bounds" },
	Arch = { build = archRound, collision = "pieces" },
	ArchStepped = { build = archStepped, collision = "pieces" },
	Stairs = { build = stairs, collision = "pieces" },
	Ramp = { build = ramp, collision = "bounds" },
	Crepidoma = { build = crepidoma, collision = "pieces" },
	Pyramid = { build = pyramidPrefab, collision = "bounds" },
	StepPyramid = { build = stepPyramid, collision = "pieces" },
	Obelisk = { build = obelisk, collision = "bounds" },
	GableRoof = { build = gableRoof, collision = "bounds" },
	RoofSlope = { build = roofSlope, collision = "bounds" },
	RoofCorner = { build = roofCorner, collision = "bounds" },
	Altar = { build = altar, collision = "bounds" },
	Pedestal = { build = pedestal, collision = "bounds" },
}

-- ===== Публичный API =====

function BlockLibrary.isPrefab(shapeId: string): boolean
	return PREFABS[shapeId] ~= nil
end

local pieceCache: { [string]: { Piece } } = {}

-- Детали формы. Для простых форм (Блок, Стена, ...) — одна коробка размера формы.
function BlockLibrary.getPieces(shapeId: string, factionId: string?): { Piece }
	local key = shapeId .. "|" .. (factionId or "")
	local cached = pieceCache[key]
	if cached then
		return cached
	end

	local pieces: { Piece }
	local prefab = PREFABS[shapeId]
	local shape = BuildConfig.Shapes[shapeId]
	if prefab then
		pieces = prefab.build(factionId)
	elseif shape then
		pieces = { { kind = "Block", role = "Main", size = shape.size, cframe = CFrame.identity } }
	else
		pieces = {}
	end
	pieceCache[key] = pieces
	return pieces
end

local collisionCache: { [string]: { Box } } = {}

-- Коробки для проверки пересечений при установке (относительно центра формы).
function BlockLibrary.getCollisionBoxes(shapeId: string): { Box }
	local cached = collisionCache[shapeId]
	if cached then
		return cached
	end
	local shape = BuildConfig.Shapes[shapeId]
	if not shape then
		return {}
	end

	local boxes: { Box } = {}
	local prefab = PREFABS[shapeId]
	if prefab and prefab.collision == "pieces" then
		for _, piece in BlockLibrary.getPieces(shapeId, nil) do
			table.insert(boxes, { cframe = piece.cframe, size = piece.size })
		end
	else
		boxes = { { cframe = CFrame.identity, size = shape.size } }
	end
	collisionCache[shapeId] = boxes
	return boxes
end

-- Создаёт деталь нужного класса (без материала и положения).
function BlockLibrary.makePart(piece: Piece): BasePart
	local part: BasePart
	if piece.kind == "Wedge" then
		part = Instance.new("WedgePart")
	elseif piece.kind == "CornerWedge" then
		part = Instance.new("CornerWedgePart")
	else
		local p = Instance.new("Part")
		if piece.kind == "Cylinder" then
			p.Shape = Enum.PartType.Cylinder
		end
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		part = p
	end
	part.Name = piece.role
	part.Size = piece.size
	return part
end

-- Палитра фракции (материал и цвет для каждой роли).
function BlockLibrary.getPalette(factionId: string?): BuildConfig.Palette
	return (if factionId then BuildConfig.FactionPalettes[factionId] else nil) or BuildConfig.DefaultPalette
end

-- Собирает закреплённую модель префаба в мире: центр формы = cframe.
function BlockLibrary.buildModel(shapeId: string, factionId: string?, cframe: CFrame): Model?
	local pieces = BlockLibrary.getPieces(shapeId, factionId)
	if #pieces == 0 then
		return nil
	end
	local palette = BlockLibrary.getPalette(factionId)

	local model = Instance.new("Model")
	model.Name = shapeId
	for _, piece in pieces do
		local part = BlockLibrary.makePart(piece)
		local look = palette[piece.role]
		part.Material = look.material
		part.Color = look.color
		part.Anchored = true
		part.CanCollide = true
		part.CFrame = cframe * piece.cframe
		part.Parent = model
	end
	model.WorldPivot = cframe -- PivotTo/GetPivot работают от центра формы
	return model
end

return BlockLibrary
