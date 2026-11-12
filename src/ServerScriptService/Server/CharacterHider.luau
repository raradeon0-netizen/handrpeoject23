--!strict
-- CharacterHider: полностью прячет персонажа игрока, пока тот строит свободной камерой.
-- Делается на сервере, потому что изменения прозрачности на клиенте
-- не реплицируются, и другие игроки продолжали бы видеть персонажа.
--
-- Что именно делаем:
--   1) все части и аксессуары: Transparency = 1, без коллизий, лучи (Raycast) их не задевают;
--   2) лица (Decal), частицы, следы и таблички над головой выключаем;
--   3) HumanoidRootPart якорим: без коллизий персонаж иначе провалился бы сквозь плиту.

local CharacterHider = {}

-- Прячет один объект из персонажа (часть, лицо, эффект или табличку).
local function hideInstance(instance: Instance)
	if instance:IsA("BasePart") then
		instance.Transparency = 1
		instance.CanCollide = false
		instance.CanQuery = false -- луч мыши при будущей стройке пролетает сквозь персонажа
		instance.CanTouch = false
	elseif instance:IsA("Decal") then
		instance.Transparency = 1
	elseif instance:IsA("ParticleEmitter") or instance:IsA("Trail") or instance:IsA("Beam") then
		instance.Enabled = false
	elseif instance:IsA("BillboardGui") then
		instance.Enabled = false
	end
end

-- Прячет персонажа. Вызывать после телепорта на участок.
function CharacterHider.hide(character: Model)
	-- Шаг 1. Убираем ник и полоску здоровья над головой.
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end

	-- Шаг 2. Прячем всё, что уже есть в персонаже.
	for _, descendant in character:GetDescendants() do
		hideInstance(descendant)
	end

	-- Шаг 3. Аксессуары и инструменты могут догрузиться позже: прячем и их.
	character.DescendantAdded:Connect(hideInstance)

	-- Шаг 4. Якорим корень, чтобы персонаж остался на месте, а не упал в пустоту.
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.Anchored = true
	end
end

return CharacterHider
