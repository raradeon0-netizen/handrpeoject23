--!strict
-- PlotTeleporter: ставит персонажа игрока ровно в центр его участка.

local PlotTeleporter = {}

local CHARACTER_WAIT_TIMEOUT = 5 -- сколько секунд ждать появления персонажа
local SAFETY_GAP = 0.5 -- небольшой зазор над поверхностью, чтобы не застрять в Part'е

-- Ждёт персонажа с HumanoidRootPart (игрок мог ещё не заспавниться).
local function waitForCharacter(player: Player): (Model?, BasePart?)
	local deadline = os.clock() + CHARACTER_WAIT_TIMEOUT
	repeat
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if character and root and root:IsA("BasePart") then
			return character, root
		end
		task.wait(0.1)
	until os.clock() >= deadline or player.Parent == nil

	return nil, nil
end

-- Телепортирует на участок. Возвращает false, если персонажа не удалось найти.
function PlotTeleporter.toPlot(player: Player, plot: Part): boolean
	local character, root = waitForCharacter(player)
	if not character or not root then
		warn(`[PlotTeleporter] У {player.Name} нет персонажа, телепорт отменён`)
		return false
	end

	-- Шаг 1. Высота от HumanoidRootPart до ступней: работает и для R15, и для R6.
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hipHeight = if humanoid then humanoid.HipHeight else 0
	local standHeight = math.max(hipHeight + root.Size.Y / 2, character:GetExtentsSize().Y / 2)

	-- Шаг 2. Центр участка по X/Z (ровно), по Y: верхняя грань + рост персонажа.
	local center = plot.Position
	local surfaceY = center.Y + plot.Size.Y / 2
	local target = Vector3.new(center.X, surfaceY + standHeight + SAFETY_GAP, center.Z)

	-- Шаг 3. Переносим и гасим скорость, чтобы персонажа не «унесло» после телепорта.
	character:PivotTo(CFrame.new(target))
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	return true
end

return PlotTeleporter
