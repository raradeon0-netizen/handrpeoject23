--!strict
-- BlockFactory: создаёт реальный закреплённый (Anchored) блок нужной формы.
--   * Базовые формы (Блок, Стена, Опора, Плита) — один Part с материалом фракции
--     (песчаник для Египта, мрамор для Рима и Греции). Их же умеет резать резак.
--   * Составные формы (колонны, арки, лестницы, пирамиды, алтари...) — Model из
--     нескольких деталей по чертежу BlockLibrary с палитрой фракции (камень, окантовка,
--     золото, цветные вставки). Pivot модели = центр габаритной коробки формы.
-- Метки владельца и формы ставятся на сам блок (Part или Model) — прямого ребёнка папки Blocks.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildConfig = require(ReplicatedStorage.Shared.BuildConfig)
local BlockLibrary = require(ReplicatedStorage.Shared.BlockLibrary)

local BlockFactory = {}

local function createBasic(shapeId: string, size: Vector3, factionId: string, cframe: CFrame): Part
	local look = BuildConfig.FactionMaterials[factionId] or BuildConfig.DefaultMaterial
	local part = Instance.new("Part")
	part.Name = shapeId
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.CanCollide = true
	part.Material = look.material
	part.Color = look.color
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

-- size — свой размер формы (составные блоки растягиваются пропорционально).
function BlockFactory.create(
	shapeId: string,
	factionId: string,
	cframe: CFrame,
	owner: Player,
	size: Vector3?
): Instance?
	local shape = BuildConfig.Shapes[shapeId]
	if not shape then
		return nil
	end

	local block: Instance?
	if shape.prefab then
		block = BlockLibrary.buildModel(shapeId, factionId, cframe, size)
	else
		block = createBasic(shapeId, size or shape.size, factionId, cframe)
	end
	if not block then
		return nil
	end

	-- Метки: чей блок и какой формы (проверяются при удалении).
	block:SetAttribute(BuildConfig.Attributes.OwnerUserId, owner.UserId)
	block:SetAttribute(BuildConfig.Attributes.ShapeId, shapeId)
	return block
end

return BlockFactory
