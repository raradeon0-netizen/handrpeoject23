--!strict
-- PlotSerializer (сервер): превращает постройки участка в таблицу для DataStore и обратно.
-- Сохраняется не геометрия, а «рецепт»: тип блока, положение относительно плиты, размер,
-- покраска, история вырезов и скрижали. При загрузке блок строится заново тем же кодом,
-- что и при обычной установке, а затем на него накладываются изменения.
--
-- Формат (короткие ключи — сохранение компактнее):
--   { v = 1, plotSize = сторона плиты, blocks = { Entry } }
--   Entry: s — id формы, c — CFrame относительно плиты, z — свой размер, o — светильник погашен,
--          для одиночного блока поля детали лежат прямо в Entry,
--          для составного: q — { [номер детали] = поля детали }, x — номера удалённых деталей.
--   Поля детали: p — id материала покраски, k — вырезы (BlockCarver.Cut), t — скрижали
--          { i — id, c — CFrame относительно исходной рамки детали, w / h — ширина и высота }.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BlockLibrary = require(ReplicatedStorage.Shared.BlockLibrary)
local BuildConfig = require(ReplicatedStorage.Shared.BuildConfig)
local BuildSize = require(ReplicatedStorage.Shared.BuildSize)
local LightEffects = require(ReplicatedStorage.Shared.LightEffects)
local PaintCatalog = require(ReplicatedStorage.Shared.PaintCatalog)

local BlockCarver = require(script.Parent.BlockCarver)
local BlockFactory = require(script.Parent.BlockFactory)
local BlockPainter = require(script.Parent.BlockPainter)
local SaveCodec = require(script.Parent.SaveCodec)
local TabletFactory = require(script.Parent.TabletFactory)

export type SaveData = {
	v: number,
	plotSize: number?, -- сторона плиты (нет в старых сохранениях)
	blocks: { { [string]: any } },
}

type Fields = { [string]: any }

local VERSION = 1
local YIELD_EVERY = 40 -- блоков между паузами при загрузке, чтобы сервер не замирал

local Attributes = BuildConfig.Attributes

local PlotSerializer = {}

-- ===== Сохранение =====

-- Покраска, вырезы и скрижали одной детали. Возвращает true, если что-то записано.
local function writePart(part: BasePart, fields: Fields): boolean
	local changed = false

	local paintId = part:GetAttribute(Attributes.PaintId)
	if typeof(paintId) == "string" then
		fields.p = paintId
		changed = true
	end

	local cuts = BlockCarver.getCuts(part)
	if #cuts > 0 then
		fields.k = cuts
		changed = true
	end

	local baseCFrame = BlockCarver.getBase(part)
	local tablets = {}
	for _, child in part:GetChildren() do
		local tabletId = child:GetAttribute(Attributes.TabletId)
		if child:IsA("BasePart") and typeof(tabletId) == "string" then
			table.insert(tablets, {
				i = tabletId,
				c = SaveCodec.encodeCFrame(baseCFrame:ToObjectSpace(child.CFrame)),
				w = math.round(child.Size.X * 1000) / 1000,
				h = math.round(child.Size.Y * 1000) / 1000,
			})
		end
	end
	if #tablets > 0 then
		fields.t = tablets
		changed = true
	end
	return changed
end

local function isCustom(size: Vector3, shape: BuildConfig.Shape): boolean
	return (size - shape.size).Magnitude > 1e-3
end

function PlotSerializer.serialize(plot: BasePart, blocks: Instance, factionId: string): SaveData
	local entries = {}
	for _, block in blocks:GetChildren() do
		local shapeId = block:GetAttribute(Attributes.ShapeId)
		local shape = if typeof(shapeId) == "string" then BuildConfig.Shapes[shapeId] else nil
		if not shape then
			continue
		end

		local entry: Fields = { s = shape.id }
		if block:IsA("BasePart") and not shape.prefab then
			local baseCFrame, baseSize = BlockCarver.getBase(block)
			entry.c = SaveCodec.encodeCFrame(plot.CFrame:ToObjectSpace(baseCFrame))
			if isCustom(baseSize, shape) then
				entry.z = SaveCodec.encodeVector(baseSize)
			end
			writePart(block, entry)
		elseif block:IsA("Model") and shape.prefab then
			entry.c = SaveCodec.encodeCFrame(plot.CFrame:ToObjectSpace(block:GetPivot()))
			local size = block:GetAttribute(Attributes.Size)
			if typeof(size) == "Vector3" and isCustom(size, shape) then
				entry.z = SaveCodec.encodeVector(size)
			end
			if LightEffects.isOff(block) then
				entry.o = true
			end

			local parts: Fields = {}
			local present: { [number]: boolean } = {}
			for _, child in block:GetChildren() do
				local index = child:GetAttribute(Attributes.PieceIndex)
				if child:IsA("BasePart") and typeof(index) == "number" then
					present[index] = true
					local fields: Fields = {}
					if writePart(child, fields) then
						parts[tostring(index)] = fields
					end
				end
			end
			if next(parts) then
				entry.q = parts
			end

			local removed = {}
			for index = 1, #BlockLibrary.getPieces(shape.id, factionId) do
				if not present[index] then
					table.insert(removed, index)
				end
			end
			if #removed > 0 then
				entry.x = removed
			end
		else
			continue
		end
		table.insert(entries, entry)
	end
	return { v = VERSION, plotSize = math.round(plot.Size.X), blocks = entries }
end

-- ===== Загрузка =====

-- Накладывает на свежую деталь сохранённые покраску, скрижали и вырезы.
local function readPart(part: BasePart, fields: unknown)
	if typeof(fields) ~= "table" then
		return
	end
	local data = fields :: Fields

	local material = if typeof(data.p) == "string" then PaintCatalog.MaterialById[data.p] else nil
	if material then
		BlockPainter.paint(part, material)
	end

	-- Скрижали вешаем до вырезов: при CSG они переедут на результат вместе с деталью.
	if typeof(data.t) == "table" then
		local full = BuildConfig.TabletSize
		for _, raw in data.t :: { unknown } do
			if typeof(raw) ~= "table" then
				continue
			end
			local record = raw :: Fields
			local tablet = if typeof(record.i) == "string" then PaintCatalog.TabletById[record.i] else nil
			local relative = SaveCodec.decodeCFrame(record.c)
			local width, height = SaveCodec.number(record.w), SaveCodec.number(record.h)
			if tablet and relative and width and height then
				TabletFactory.spawn(
					part,
					tablet,
					part.CFrame * relative,
					math.clamp(width, 0.1, full.X),
					math.clamp(height, 0.1, full.Y)
				)
			end
		end
	end

	if data.k ~= nil then
		BlockCarver.replay(part, data.k)
	end
end

-- Строит один блок из записи. Возвращает false, если запись испорчена.
local function restoreEntry(plot: BasePart, blocks: Instance, raw: unknown, factionId: string, owner: Player): boolean
	if typeof(raw) ~= "table" then
		return false
	end
	local entry = raw :: Fields
	local shape = if typeof(entry.s) == "string" then BuildConfig.Shapes[entry.s] else nil
	local relative = SaveCodec.decodeCFrame(entry.c)
	if not shape or not relative then
		return false
	end

	local size: Vector3? = nil
	if entry.z ~= nil then
		local low, high = BuildSize.limits(shape)
		if not BuildSize.isValid(SaveCodec.decodeVector(entry.z), low, high) then
			return false
		end
		size = SaveCodec.decodeVector(entry.z)
	end

	local block = BlockFactory.create(shape.id, factionId, plot.CFrame * relative, owner, size)
	if not block then
		return false
	end
	block.Parent = blocks -- CSG работает только с деталями в мире

	if block:IsA("BasePart") then
		readPart(block, entry)
	else
		local removed: { [number]: boolean } = {}
		if typeof(entry.x) == "table" then
			for _, index in entry.x :: { unknown } do
				if typeof(index) == "number" then
					removed[index] = true
				end
			end
		end
		local parts: Fields = if typeof(entry.q) == "table" then entry.q else {}
		for _, child in block:GetChildren() do
			local index = child:GetAttribute(Attributes.PieceIndex)
			if child:IsA("BasePart") and typeof(index) == "number" then
				if removed[index] then
					child:Destroy()
				else
					readPart(child, parts[tostring(index)])
				end
			end
		end
		if entry.o == true and block.Parent then
			LightEffects.setEnabled(block, false)
		end
	end
	return true
end

-- Восстанавливает постройки из сохранения. Вызывается из корутины: CSG и паузы уступают управление.
-- stillValid — проверка, что участок всё ещё принадлежит игроку (он мог выйти посреди загрузки).
-- Возвращает число восстановленных блоков.
function PlotSerializer.restore(
	plot: BasePart,
	blocks: Instance,
	data: unknown,
	factionId: string,
	owner: Player,
	stillValid: () -> boolean
): number
	if typeof(data) ~= "table" then
		return 0
	end
	local entries = (data :: Fields).blocks
	if typeof(entries) ~= "table" then
		return 0
	end

	local restored = 0
	for index, raw in entries :: { unknown } do
		if index > BuildConfig.MaxBlocksPerPlayer or not stillValid() then
			break
		end
		local ok, built = pcall(restoreEntry, plot, blocks, raw, factionId, owner)
		if ok and built then
			restored += 1
		elseif not ok then
			warn("[PlotSerializer] Блок из сохранения не восстановлен:", built)
		end
		if index % YIELD_EVERY == 0 then
			task.wait()
		end
	end
	return restored
end

return PlotSerializer
