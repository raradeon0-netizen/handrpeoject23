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
local LightEffects = require(script.Parent.LightEffects)

export type Role = "Main" | "Trim" | "Accent" | "Detail"
export type PieceKind = "Block" | "Wedge" | "CornerWedge" | "Cylinder"

export type Piece = {
	kind: PieceKind,
	role: Role,
	size: Vector3, -- размер самой детали (для цилиндра ось — X)
	cframe: CFrame, -- положение относительно центра формы
	shade: number?, -- множитель яркости цвета роли (оттенки отдельных камней)
	material: Enum.Material?, -- свой материал вместо материала роли
	color: Color3?, -- свой цвет вместо цвета роли
	effect: string?, -- id эффекта светильника из LightEffects (свет, пламя, искры)
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

-- Камень кладки: бокс со своим оттенком и, при необходимости, своим материалом и цветом.
local function stone(
	list: { Piece },
	role: Role,
	size: Vector3,
	cframe: CFrame,
	shade: number?,
	material: Enum.Material?,
	color: Color3?
)
	table.insert(list, { kind = "Block", role = role, size = size, cframe = cframe, shade = shade, material = material, color = color })
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

-- ===== Резные (богато украшенные) варианты базовых блоков =====

-- Дорога 8x1x8 (вдоль Z): основание, брусчатка «вперевязку» и приподнятые резные бордюры по бокам.
-- Четыре ряда камней повторяют рисунок, поэтому плитки стыкуются друг с другом без шва.
local function ornateRoad(_factionId: string?): { Piece }
	local list: { Piece } = {}
	block(list, "Trim", 6.4, 0.5, 8, 0, -0.25, 0) -- основание под камнями

	local laneWidth, rows, perRow = 6.4, 4, 3
	local depth = 8 / rows
	local width = laneWidth / perRow
	local gap = 0.1
	for row = 0, rows - 1 do
		local z = -4 + depth * (row + 0.5)
		local shifted = row % 2 == 1
		-- Сдвинутый ряд: половинки по краям и целые камни между ними.
		local edges: { number } = {}
		if shifted then
			edges = { -laneWidth / 2, -laneWidth / 2 + width / 2 }
			for i = 1, perRow - 1 do
				table.insert(edges, -laneWidth / 2 + width / 2 + width * i)
			end
			table.insert(edges, laneWidth / 2)
		else
			for i = 0, perRow do
				table.insert(edges, -laneWidth / 2 + width * i)
			end
		end
		for i = 1, #edges - 1 do
			local left, right = edges[i], edges[i + 1]
			-- Камни чуть разной высоты и двух оттенков: живая, неровная кладка.
			local tall = (row + i) % 2 == 0
			local height = if tall then 0.3 else 0.24
			block(
				list,
				if tall then "Main" else "Trim",
				right - left - gap,
				height,
				depth - gap,
				(left + right) / 2,
				height / 2,
				z
			)
		end
	end

	for _, sx in { -1, 1 } do
		block(list, "Main", 0.8, 0.8, 8, sx * 3.6, -0.1, 0) -- бордюр
		for _, sz in { -1, 1 } do
			block(list, "Trim", 0.8, 0.2, 3.8, sx * 3.6, 0.4, sz * 2) -- резной верх бордюра
		end
		block(list, "Accent", 0.12, 0.12, 8, sx * 3.14, 0.36, 0) -- металлическая кромка у камней
	end
	return list
end

-- Резная стена 12x8x4: цоколь с профилем, рельефные пояса, утопленные панели между пилястрами
-- и золотая отделка. Обе стороны одинаковые.
local function ornateWall(_factionId: string?): { Piece }
	local list: { Piece } = {}
	block(list, "Trim", 12, 1, 4, 0, -3.5, 0) -- цоколь
	block(list, "Trim", 11.6, 0.4, 3.8, 0, -2.8, 0) -- профиль цоколя
	block(list, "Main", 11.2, 5.6, 3.2, 0, 0.2, 0) -- тело стены
	block(list, "Accent", 11.4, 0.25, 3.4, 0, 3.125, 0) -- золотой пояс под карнизом
	block(list, "Trim", 12, 0.75, 4, 0, 3.625, 0) -- карниз

	local pilasters = { -5.2, -1.7333, 1.7333, 5.2 }
	local panels = { -3.4667, 0, 3.4667 }
	for _, sz in { -1, 1 } do
		block(list, "Trim", 11.4, 0.3, 0.2, 0, -2.2, sz * 1.7) -- нижний рельефный пояс
		block(list, "Trim", 11.4, 0.3, 0.2, 0, 2.5, sz * 1.7) -- верхний рельефный пояс
		for _, x in pilasters do
			block(list, "Main", 0.8, 4.4, 0.4, x, 0.15, sz * 1.8)
		end
		-- Панели лежат глубже пилястр: получается ниша с цветной вставкой в золотой раме.
		for _, x in panels do
			block(list, "Detail", 2.3, 3.4, 0.1, x, 0.15, sz * 1.65)
			block(list, "Accent", 2.5, 0.12, 0.12, x, 1.97, sz * 1.72)
			block(list, "Accent", 2.5, 0.12, 0.12, x, -1.67, sz * 1.72)
		end
	end
	return list
end

-- Орнаментный блок 4x4x4: плинт и карниз, угловые столбики и трёхслойный рельеф
-- на каждой боковой грани (каменная плита, металлическая рамка, цветная вставка).
local function ornateCube(_factionId: string?): { Piece }
	local list: { Piece } = {}
	block(list, "Main", 3.4, 3.4, 3.4, 0, 0, 0)
	block(list, "Trim", 4, 0.4, 4, 0, -1.8, 0)
	block(list, "Trim", 4, 0.4, 4, 0, 1.8, 0)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			block(list, "Trim", 0.6, 3.2, 0.6, sx * 1.7, 0, sz * 1.7)
		end
	end
	for _, side in { -1, 1 } do
		block(list, "Main", 2.4, 2.4, 0.15, 0, 0, side * 1.775)
		block(list, "Accent", 2, 2, 0.08, 0, 0, side * 1.89)
		block(list, "Detail", 1.6, 1.6, 0.07, 0, 0, side * 1.965)
		block(list, "Main", 0.15, 2.4, 2.4, side * 1.775, 0, 0)
		block(list, "Accent", 0.08, 2, 2, side * 1.89, 0, 0)
		block(list, "Detail", 0.07, 1.6, 1.6, side * 1.965, 0, 0)
	end
	return list
end

-- ===== Каменная кладка: стены и дороги =====
-- Геометрию этих префабов проверяет tools/prefabs.py check (границы формы и совпадающие грани).

local BRICK_SHADES = { 1, 0.93, 1.05, 0.97 }

-- Кирпичная кладка 12x8x4: ряды кирпичей «вперевязку», утопленный раствор между ними
-- и резной каменный карниз. Кирпичи проходят стену насквозь, поэтому обе стороны одинаковые.
local function brickWall(_factionId: string?): { Piece }
	local list: { Piece } = {}
	stone(list, "Trim", Vector3.new(11.8, 7.2, 3.8), CFrame.new(0, -0.4, 0), 0.8) -- раствор

	local courses, courseHeight, gap = 8, 0.9, 0.1
	for course = 0, courses - 1 do
		local y = -4 + courseHeight * (course + 0.5)
		local edges = if course % 2 == 0 then { -6, -3, 0, 3, 6 } else { -6, -4.5, -1.5, 1.5, 4.5, 6 }
		for i = 1, #edges - 1 do
			local left, right = edges[i], edges[i + 1]
			-- Соседние кирпичи всегда чуть разного оттенка.
			local shade = BRICK_SHADES[(course * 3 + i * 5) % #BRICK_SHADES + 1]
			stone(
				list,
				"Main",
				Vector3.new(right - left - gap, courseHeight - gap, 4),
				CFrame.new((left + right) / 2, y, 0),
				shade
			)
		end
	end

	block(list, "Main", 11.6, 0.3, 3.6, 0, 3.35, 0) -- выкружка под карнизом
	block(list, "Trim", 12, 0.5, 4, 0, 3.75, 0) -- карниз
	return list
end

-- x, y, z, длина, высота, ширина, поворот°, наклон X°, наклон Z°, порода (1 / 2), оттенок
local COBBLES: { { number } } = {
	{ -3.1, 0.08, -3.07, 1.28, 0.42, 1.22, -34.7, 4.9, -3.2, 2, 0.99 },
	{ -3.03, 0, -0.99, 1.35, 0.47, 1.48, -19.9, 4.6, -3.2, 1, 0.96 },
	{ -3.08, 0.01, 0.99, 1.35, 0.47, 1.53, 12.7, 3.3, 3.9, 2, 0.91 },
	{ -3.08, -0.01, 2.88, 1.2, 0.54, 1.27, 19.5, 4.2, 1.7, 2, 1.07 },
	{ -1.06, 0.02, -2.95, 1.34, 0.47, 1.28, -22.3, 4.4, -2.4, 2, 1.02 },
	{ -1.11, 0.12, -1.07, 1.2, 0.54, 1.35, 29.8, -2.6, 2.6, 2, 0.88 },
	{ -0.87, -0.02, 1.12, 1.4, 0.59, 1.5, 0.2, -3.9, 2.6, 2, 0.98 },
	{ -0.78, 0.06, 2.99, 1.22, 0.52, 1.59, 9.9, 1.6, -2, 2, 1.05 },
	{ 0.99, 0.09, -3.03, 1.41, 0.53, 1.57, 13.7, -4.6, -1.8, 1, 0.87 },
	{ 1.05, 0.03, -1.02, 1.65, 0.54, 1.46, -3.5, -4.5, 2.9, 1, 1.02 },
	{ 0.75, 0.11, 0.88, 1.25, 0.5, 1.28, 6.7, 2.5, -4.7, 1, 1.04 },
	{ 1.12, -0.01, 2.86, 1.51, 0.56, 1.4, 0, -4.9, 3.8, 2, 0.92 },
	{ 3.04, 0.08, -3, 1.25, 0.58, 1.22, -28.7, 4.3, -2.4, 1, 1.04 },
	{ 2.98, 0.08, -0.92, 1.31, 0.47, 1.2, -18.2, 3, -1.8, 1, 1.04 },
	{ 3.02, 0.08, 0.83, 1.6, 0.45, 1.29, 7.9, -4.8, 2.5, 1, 1.01 },
	{ 3.01, 0.03, 3.08, 1.38, 0.5, 1.21, 32, 2.5, -4.2, 1, 1.02 },
	{ -2.01, 0, -2.01, 0.66, 0.39, 0.49, -28.4, -6.1, -3.5, 2, 0.97 },
	{ -2.02, -0.01, 0.06, 0.64, 0.44, 0.45, 22.7, -3.7, -2.5, 1, 1.02 },
	{ -1.94, 0.04, 2.05, 0.55, 0.39, 0.7, -7.2, 4.9, -6.2, 1, 1 },
	{ 0.04, 0.01, -2.03, 0.62, 0.35, 0.69, 20, 4.1, 2.9, 2, 0.94 },
	{ -0.03, 0.03, -0.01, 0.58, 0.37, 0.62, 11.1, 3.7, -6.3, 1, 0.99 },
	{ -0.02, -0.01, 1.99, 0.64, 0.43, 0.62, -24.2, -2.8, 2.8, 1, 1 },
	{ 2.03, -0.01, -1.9, 0.61, 0.45, 0.55, -2.1, -2.6, -6.9, 1, 0.88 },
	{ 2.05, 0, -0.04, 0.67, 0.36, 0.56, 13, 4.3, 2.1, 2, 0.99 },
	{ 2.06, -0.02, 1.98, 0.52, 0.45, 0.5, 17.2, -6.9, 2.6, 2, 1.05 },
}

local EARTH_COLOR = Color3.fromRGB(150, 122, 88)

-- Дикий булыжник 8x1x8: неровные, слегка наклонённые камни разной высоты в земляном основании.
-- Бордюров нет: плитки стыкуются с любой стороны.
local function cobbleRoad(_factionId: string?): { Piece }
	local list: { Piece } = {}
	stone(list, "Trim", Vector3.new(8, 0.6, 8), CFrame.new(0, -0.2, 0), nil, Enum.Material.Sand, EARTH_COLOR)
	for _, s in COBBLES do
		local slate = s[10] == 1
		stone(
			list,
			if slate then "Main" else "Trim",
			Vector3.new(s[4], s[5], s[6]),
			CFrame.new(s[1], s[2], s[3])
				* CFrame.Angles(0, math.rad(s[7]), 0)
				* CFrame.Angles(math.rad(s[8]), 0, math.rad(s[9])),
			s[11],
			if slate then Enum.Material.Slate else Enum.Material.Cobblestone
		)
	end
	return list
end

-- Римская мозаика 8x1x8 (вдоль Z): крупные гладкие плиты, по бокам — кайма из цветной полосы
-- с золотыми ромбами и золотой нитью, ступенчатый бордюр и медальон в центре.
local function mosaicRoad(_factionId: string?): { Piece }
	local list: { Piece } = {}
	local diamond = CFrame.Angles(0, math.rad(45), 0)
	block(list, "Trim", 8, 0.5, 8, 0, -0.25, 0)
	for _, sx in { -1, 1 } do
		block(list, "Trim", 0.4, 0.2, 8, sx * 3.8, 0.1, 0) -- нижняя ступень бордюра
		block(list, "Main", 0.4, 0.5, 8, sx * 3.4, 0.25, 0) -- верхняя ступень бордюра
		block(list, "Accent", 0.3, 0.3, 8, sx * 3.05, 0.15, 0) -- золотая нить
		block(list, "Detail", 0.4, 0.26, 8, sx * 2.7, 0.13, 0) -- цветная полоса каймы
		for k = 0, 3 do
			add(list, "Block", "Accent", Vector3.new(0.26, 0.27, 0.26), CFrame.new(sx * 2.7, 0.185, -3 + 2 * k) * diamond)
		end
		for _, sz in { -1, 1 } do
			-- Плиты в шахматном порядке чуть отличаются тоном.
			stone(
				list,
				"Main",
				Vector3.new(2.44, 0.3, 3.94),
				CFrame.new(sx * 1.25, 0.15, sz * 2),
				if sx * sz > 0 then 1 else 0.94
			)
		end
	end
	add(list, "Block", "Accent", Vector3.new(1.7, 0.28, 1.7), CFrame.new(0, 0.19, 0) * diamond)
	add(list, "Block", "Detail", Vector3.new(1.3, 0.26, 1.3), CFrame.new(0, 0.23, 0) * diamond)
	return list
end

-- x, y, длина, высота, глубина, оттенок
local RUIN_STONES: { { number } } = {
	{ -3.795, -2.88, 4.41, 2.24, 3.7, 0.84 },
	{ 0, -2.88, 2.82, 2.24, 4, 0.83 },
	{ 3.795, -2.88, 4.41, 2.24, 4, 0.92 },
	{ -4.795, -0.78, 2.41, 1.64, 4, 0.84 },
	{ -2, -0.78, 2.82, 1.64, 4, 0.96 },
	{ 1.25, -0.78, 3.32, 1.64, 3.7, 0.89 },
	{ 4.545, -0.78, 2.91, 1.64, 4, 1 },
	{ -3.795, 1.22, 4.41, 2.04, 4, 0.91 },
	{ 0.5, 1.22, 3.82, 2.04, 3.85, 0.99 },
	{ 4.295, 1.22, 3.41, 2.04, 4, 0.99 },
	{ -4.045, 3, 3.91, 1.2, 3.85, 1.03 },
	{ -0.25, 3.2, 3.32, 1.6, 3.85, 0.87 },
	{ 3.795, 3.2, 4.41, 1.6, 3.7, 0.99 },
}

-- Древняя кладка 12x8x4: крупные грубо отёсанные блоки разного размера и глубины
-- (циклопическая кладка) с глубокими швами; один камень верхнего ряда выщерблен.
local function ruinWall(_factionId: string?): { Piece }
	local list: { Piece } = {}
	stone(list, "Trim", Vector3.new(11.6, 7.4, 3), CFrame.new(0, -0.2, 0), 0.55) -- тёмная глубина швов
	for _, s in RUIN_STONES do
		stone(list, "Main", Vector3.new(s[3], s[4], s[5]), CFrame.new(s[1], s[2], 0), s[6], Enum.Material.Slate)
	end
	return list
end

-- ===== Освещение =====
-- Светящаяся деталь несёт effect — по нему LightEffects вешает свет, пламя и искры.
-- Геометрию проверяет tools/prefabs.py check.

local IRON = Color3.fromRGB(58, 54, 52)
local BRONZE = Color3.fromRGB(140, 98, 52)
local WOOD = Color3.fromRGB(96, 62, 36)
local CHARRED = Color3.fromRGB(44, 32, 28)
local EMBER = Color3.fromRGB(255, 140, 50)
local CRYSTAL = Color3.fromRGB(255, 205, 90)

-- Меняет вид последней добавленной детали: свой материал, цвет и эффект светильника.
local function restyle(list: { Piece }, material: Enum.Material?, color: Color3?, effect: string?)
	local piece = list[#list]
	piece.material = material
	piece.color = color
	piece.effect = effect
end

-- Настенный факел 1x4x2: бронзовая пластина прижата к стене (сторона -Z), от неё идёт
-- железный кронштейн с чашей, в котором стоит наклонённая от стены деревянная рукоять с углями.
local function wallTorch(_factionId: string?): { Piece }
	local list: { Piece } = {}
	stone(list, "Trim", Vector3.new(1, 2, 0.2), CFrame.new(0, -1, -0.9), nil, Enum.Material.Metal, BRONZE)
	block(list, "Accent", 0.3, 0.12, 0.08, 0, -0.3, -0.77) -- заклёпки пластины
	block(list, "Accent", 0.3, 0.12, 0.08, 0, -1.7, -0.77)
	stone(list, "Trim", Vector3.new(0.2, 0.2, 0.7), CFrame.new(0, -0.9, -0.45), nil, Enum.Material.Metal, IRON)

	local handle = CFrame.new(0, 0, 0.1) * CFrame.Angles(math.rad(20), 0, 0)
	stone(list, "Main", Vector3.new(0.3, 2.4, 0.3), handle, nil, Enum.Material.Wood, WOOD)
	stone(list, "Trim", Vector3.new(0.45, 0.2, 0.45), handle * CFrame.new(0, -0.958, 0), nil, Enum.Material.Metal, IRON)
	stone(list, "Trim", Vector3.new(0.9, 0.12, 0.9), CFrame.new(0, 1.05, 0.55), nil, Enum.Material.Metal, IRON) -- чаша
	stone(list, "Main", Vector3.new(0.5, 0.6, 0.5), handle * CFrame.new(0, 1.4, 0), nil, Enum.Material.Fabric, CHARRED)
	stone(list, "Accent", Vector3.new(0.36, 0.25, 0.36), handle * CFrame.new(0, 1.8, 0), nil, Enum.Material.Neon, EMBER)
	restyle(list, Enum.Material.Neon, EMBER, "Torch")
	return list
end

-- Храмовая жаровня 4x4x4: каменное основание, золотой треножник и чаша с тлеющими углями.
local function brazier(_factionId: string?): { Piece }
	local list: { Piece } = {}
	block(list, "Trim", 4, 0.5, 4, 0, -1.75, 0)
	block(list, "Main", 2.4, 0.4, 2.4, 0, -1.3, 0)

	for k = 0, 2 do
		local angle = math.rad(90 + 120 * k)
		local x, z = 0.75 * math.cos(angle), 0.75 * math.sin(angle)
		-- Ножка наклонена верхом к центру чаши.
		add(
			list,
			"Block",
			"Accent",
			Vector3.new(0.22, 2.3, 0.22),
			CFrame.new(x, -0.05, z) * CFrame.Angles(0, math.atan2(-x, -z), 0) * CFrame.Angles(math.rad(10), 0, 0)
		)
		-- Куски угля поверх тлеющего слоя.
		stone(
			list,
			"Main",
			Vector3.new(0.45, 0.26, 0.45),
			CFrame.new(-0.8 * x, 1.76, -0.8 * z)
				* CFrame.Angles(0, math.rad(40 * k), 0)
				* CFrame.Angles(math.rad(12), 0, math.rad(-9)),
			nil,
			Enum.Material.Slate,
			CHARRED
		)
	end

	cylinder(list, "Accent", 1.5, 0.12, 0, -0.4, 0) -- обруч между ножками
	cylinder(list, "Trim", 2.2, 0.4, 0, 0.9, 0) -- дно чаши
	cylinder(list, "Accent", 3, 0.5, 0, 1.35, 0) -- золотой борт
	cylinder(list, "Accent", 2.5, 0.2, 0, 1.62, 0) -- тлеющие угли
	restyle(list, Enum.Material.Neon, EMBER, "Brazier")
	return list
end

-- Обелиск-светильник 4x12x4: ступенчатый резной столб с золотыми поясами и цветными
-- панелями, наверху — золотая чаша с сияющим кристаллом.
local function obeliskLamp(_factionId: string?): { Piece }
	local list: { Piece } = {}
	block(list, "Trim", 4, 1, 4, 0, -5.5, 0)
	block(list, "Main", 3.2, 0.6, 3.2, 0, -4.7, 0)
	block(list, "Main", 2.4, 3, 2.4, 0, -2.9, 0)
	block(list, "Main", 2.1, 3, 2.1, 0, 0.1, 0)
	block(list, "Main", 1.8, 2.4, 1.8, 0, 2.8, 0)
	block(list, "Accent", 2.6, 0.2, 2.6, 0, -1.4, 0)
	block(list, "Accent", 2.3, 0.2, 2.3, 0, 1.6, 0)
	for _, side in { -1, 1 } do
		block(list, "Detail", 1.2, 1.8, 0.06, 0, -2.9, side * 1.21)
		block(list, "Detail", 0.06, 1.8, 1.2, side * 1.21, -2.9, 0)
	end
	block(list, "Trim", 2.6, 0.4, 2.6, 0, 4.2, 0)
	cylinder(list, "Accent", 3, 0.5, 0, 4.65, 0)
	stone(
		list,
		"Accent",
		Vector3.new(0.8, 0.8, 0.8),
		CFrame.new(0, 5.3, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)),
		nil,
		Enum.Material.Neon,
		CRYSTAL
	)
	restyle(list, Enum.Material.Neon, CRYSTAL, "Crystal")
	return list
end

local PREFABS: { [string]: Prefab } = {
	WallTorch = { build = wallTorch, collision = "bounds" },
	Brazier = { build = brazier, collision = "bounds" },
	ObeliskLamp = { build = obeliskLamp, collision = "bounds" },
	BrickWall = { build = brickWall, collision = "bounds" },
	CobbleRoad = { build = cobbleRoad, collision = "bounds" },
	MosaicRoad = { build = mosaicRoad, collision = "bounds" },
	RuinWall = { build = ruinWall, collision = "bounds" },
	OrnateRoad = { build = ornateRoad, collision = "bounds" },
	OrnateWall = { build = ornateWall, collision = "bounds" },
	OrnateCube = { build = ornateCube, collision = "bounds" },
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
local function basePieces(shapeId: string, factionId: string?): { Piece }
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
local function baseBoxes(shapeId: string): { Box }
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
		for _, piece in basePieces(shapeId, nil) do
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

-- Растягивает детали префаба по осям формы. Деталь, повёрнутая на прямой угол, растягивается
-- точно; у наклонной каждая сторона получает растяжение вдоль своего направления.
local function scalePieces(pieces: { Piece }, scale: Vector3): { Piece }
	local result: { Piece } = table.create(#pieces)
	for index, piece in pieces do
		local rotation = piece.cframe.Rotation
		local copy = table.clone(piece)
		copy.size = Vector3.new(
			piece.size.X * (rotation.XVector * scale).Magnitude,
			piece.size.Y * (rotation.YVector * scale).Magnitude,
			piece.size.Z * (rotation.ZVector * scale).Magnitude
		)
		copy.cframe = CFrame.new(piece.cframe.Position * scale) * rotation
		result[index] = copy
	end
	return result
end

local function isCustomSize(shape: BuildConfig.Shape?, size: Vector3?): boolean
	return shape ~= nil and size ~= nil and (size - shape.size).Magnitude > 1e-3
end

-- Детали формы. size — свой размер: базовая форма становится одним боксом этого размера,
-- составная растягивается пропорционально от родного размера.
function BlockLibrary.getPieces(shapeId: string, factionId: string?, size: Vector3?): { Piece }
	local shape = BuildConfig.Shapes[shapeId]
	if not shape or not size or not isCustomSize(shape, size) then
		return basePieces(shapeId, factionId)
	end
	if not PREFABS[shapeId] then
		local box: Piece = { kind = "Block", role = "Main", size = size, cframe = CFrame.identity }
		return { box }
	end
	return scalePieces(basePieces(shapeId, factionId), size / shape.size)
end

-- Коробки для проверки пересечений при установке (с учётом своего размера формы).
function BlockLibrary.getCollisionBoxes(shapeId: string, size: Vector3?): { Box }
	local shape = BuildConfig.Shapes[shapeId]
	if not shape or not size or not isCustomSize(shape, size) then
		return baseBoxes(shapeId)
	end
	local prefab = PREFABS[shapeId]
	if prefab and prefab.collision == "pieces" then
		local boxes: { Box } = {}
		for _, piece in BlockLibrary.getPieces(shapeId, nil, size) do
			table.insert(boxes, { cframe = piece.cframe, size = piece.size })
		end
		return boxes
	end
	return { { cframe = CFrame.identity, size = size } }
end

-- Собирает закреплённую модель префаба в мире: центр формы = cframe.
function BlockLibrary.buildModel(shapeId: string, factionId: string?, cframe: CFrame, size: Vector3?): Model?
	local pieces = BlockLibrary.getPieces(shapeId, factionId, size)
	if #pieces == 0 then
		return nil
	end
	local palette = BlockLibrary.getPalette(factionId)

	local model = Instance.new("Model")
	model.Name = shapeId
	for _, piece in pieces do
		local part = BlockLibrary.makePart(piece)
		local look = palette[piece.role]
		local color = piece.color or look.color
		local shade = piece.shade
		if shade then
			color = Color3.new(
				math.clamp(color.R * shade, 0, 1),
				math.clamp(color.G * shade, 0, 1),
				math.clamp(color.B * shade, 0, 1)
			)
		end
		part.Material = piece.material or look.material
		part.Color = color
		local effect = piece.effect
		if effect then
			LightEffects.apply(part, effect)
		end
		part.Anchored = true
		part.CanCollide = true
		part.CFrame = cframe * piece.cframe
		part.Parent = model
	end
	model.WorldPivot = cframe -- PivotTo/GetPivot работают от центра формы
	return model
end

return BlockLibrary
