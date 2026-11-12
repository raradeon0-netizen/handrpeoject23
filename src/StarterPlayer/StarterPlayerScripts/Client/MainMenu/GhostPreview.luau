--!strict
-- GhostPreview: полупрозрачный «призрак» фигуры для предпросмотра.
-- Живёт только на клиенте (другие игроки его не видят), не участвует в физике
-- и не ловит лучи мыши (CanQuery = false). Плавно догоняет целевую позицию
-- и поворот. Цвет задаёт BuildController: зелёный/красный — установка,
-- фиолетовый/оранжевый — резак.
--
-- Призрак — Model из тех же деталей, что и настоящий блок (BlockLibrary), поэтому
-- составные формы (арки, колонны, пирамиды...) видны в предпросмотре целиком.
-- Невидимая деталь Bounds повторяет габаритную коробку формы: по ней рисуется контур.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildConfig = require(ReplicatedStorage.Shared.BuildConfig)
local BlockLibrary = require(ReplicatedStorage.Shared.BlockLibrary)

export type Ghost = {
	setShape: (shapeId: string, factionId: string?, size: Vector3?) -> (), -- size — свой размер базовой формы
	update: (target: CFrame, color: Color3, dt: number) -> (),
	hide: () -> (),
	destroy: () -> (),
}

local GhostPreview = {}

local function makeGhostPart(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon -- лёгкое свечение
	part.Transparency = 1 -- скрыт до первого update
end

function GhostPreview.new(parent: Instance): Ghost
	local model = Instance.new("Model")
	model.Name = "BuildGhost"
	model.Parent = parent

	-- Габаритная коробка формы (всегда прозрачная) — опора для контура и pivot.
	local bounds = Instance.new("Part")
	bounds.Name = "Bounds"
	makeGhostPart(bounds)
	bounds.Parent = model
	model.PrimaryPart = bounds

	-- Контур, чтобы границы призрака были чётко видны на фоне плиты и блоков.
	local outline = Instance.new("SelectionBox")
	outline.Name = "Outline"
	outline.Adornee = bounds
	outline.LineThickness = 0.06
	outline.SurfaceTransparency = 1
	outline.Visible = false
	outline.Parent = model

	local pieces: { BasePart } = {}
	local visible = false
	local current: CFrame? = nil
	local shownKey: string? = nil

	local function setShape(shapeId: string, factionId: string?, size: Vector3?)
		local key = shapeId .. "|" .. (factionId or "") .. "|" .. (if size then tostring(size) else "")
		if key == shownKey then
			return
		end
		shownKey = key

		for _, piece in pieces do
			piece:Destroy()
		end
		table.clear(pieces)

		local shape = BuildConfig.Shapes[shapeId]
		local specs = BlockLibrary.getPieces(shapeId, factionId)
		if shape and size and not shape.prefab then
			-- Базовая форма своего размера (в том числе тонкая полоса резака): один бокс.
			bounds.Size = size
			specs = { { kind = "Block", role = "Main", size = size, cframe = CFrame.identity } }
		elseif shape then
			bounds.Size = shape.size
		end
		local base = bounds.CFrame
		for _, spec in specs do
			local part = BlockLibrary.makePart(spec)
			makeGhostPart(part)
			part.CFrame = base * spec.cframe
			part.Parent = model
			table.insert(pieces, part)
		end
		current = nil -- новая форма: сразу встаём на место, без полёта
		visible = false
	end

	local function update(target: CFrame, color: Color3, dt: number)
		-- Плавность: экспоненциальное сглаживание позиции и поворота, не зависит от FPS.
		local previous = current
		if previous == nil or not visible then
			current = target
		else
			local alpha = 1 - math.exp(-BuildConfig.GhostFollowSpeed * dt)
			current = previous:Lerp(target, alpha)
		end
		model:PivotTo(current :: CFrame) -- двигает все детали разом

		for _, piece in pieces do
			piece.Color = color
			piece.Transparency = BuildConfig.GhostTransparency
		end
		outline.Color3 = color
		outline.Visible = true
		visible = true
	end

	local function hide()
		if not visible then
			return
		end
		for _, piece in pieces do
			piece.Transparency = 1
		end
		outline.Visible = false
		visible = false
	end

	local function destroy()
		model:Destroy()
	end

	return {
		setShape = setShape,
		update = update,
		hide = hide,
		destroy = destroy,
	}
end

return GhostPreview
