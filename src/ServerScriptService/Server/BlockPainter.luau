--!strict
-- BlockPainter (сервер): перекраска одной детали блока материалом из PaintCatalog.
-- Красится именно та деталь, по которой кликнули: у составной модели — отдельная часть.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PaintCatalog = require(ReplicatedStorage.Shared.PaintCatalog)

local BlockPainter = {}

function BlockPainter.paint(part: BasePart, material: PaintCatalog.Material)
	part.Material = material.material
	part.Color = material.color
	part.Reflectance = material.reflectance
	if part:IsA("PartOperation") then
		part.UsePartColor = true -- иначе CSG-результат сохранит цвета исходных деталей
	end
end

return BlockPainter
