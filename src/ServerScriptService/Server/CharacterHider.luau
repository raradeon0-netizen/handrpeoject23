--!strict
-- CharacterHider: полностью прячет персонажа игрока, пока тот строит свободной камерой,
-- и возвращает его в обычный вид для режима прогулки.
-- Делается на сервере, потому что изменения прозрачности на клиенте
-- не реплицируются, и другие игроки продолжали бы видеть персонажа.
--
-- Что именно делаем при hide:
--   1) все части и аксессуары: Transparency = 1, без коллизий, лучи (Raycast) их не задевают;
--   2) лица (Decal), частицы, следы и таблички над головой выключаем;
--   3) HumanoidRootPart якорим: без коллизий персонаж иначе провалился бы сквозь плиту.
-- Прежние значения запоминаются, поэтому show возвращает персонажа точно таким, каким он был.

local CharacterHider = {}

type State = {
	connection: RBXScriptConnection,
	saved: { [Instance]: { [string]: any } }, -- объект -> его свойства до скрытия
}

local states: { [Model]: State } = {}

-- Прячет один объект из персонажа (часть, лицо, эффект или табличку), запомнив прежний вид.
local function hideInstance(instance: Instance, saved: { [Instance]: { [string]: any } })
	if saved[instance] then
		return
	end
	if instance:IsA("BasePart") then
		saved[instance] = {
			Transparency = instance.Transparency,
			CanCollide = instance.CanCollide,
			CanQuery = instance.CanQuery,
			CanTouch = instance.CanTouch,
		}
		instance.Transparency = 1
		instance.CanCollide = false
		instance.CanQuery = false -- луч мыши при стройке пролетает сквозь персонажа
		instance.CanTouch = false
	elseif instance:IsA("Decal") then
		saved[instance] = { Transparency = instance.Transparency }
		instance.Transparency = 1
	elseif instance:IsA("ParticleEmitter") then
		saved[instance] = { Enabled = instance.Enabled }
		instance.Enabled = false
	elseif instance:IsA("Trail") then
		saved[instance] = { Enabled = instance.Enabled }
		instance.Enabled = false
	elseif instance:IsA("Beam") then
		saved[instance] = { Enabled = instance.Enabled }
		instance.Enabled = false
	elseif instance:IsA("BillboardGui") then
		saved[instance] = { Enabled = instance.Enabled }
		instance.Enabled = false
	end
end

local function setAnchored(character: Model, anchored: boolean)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.Anchored = anchored
	end
end

function CharacterHider.isHidden(character: Model): boolean
	return states[character] ~= nil
end

function CharacterHider.hide(character: Model)
	setAnchored(character, true)
	if states[character] then
		return -- уже спрятан: повторно запоминать «прежний вид» нельзя, он уже невидимый
	end

	-- Имя и здоровье над головой.
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end

	local saved: { [Instance]: { [string]: any } } = {}
	for _, descendant in character:GetDescendants() do
		hideInstance(descendant, saved)
	end

	-- Аксессуары и одежда могут догрузиться позже — прячем и их.
	local connection = character.DescendantAdded:Connect(function(descendant: Instance)
		hideInstance(descendant, saved)
	end)
	states[character] = { connection = connection, saved = saved }

	character.Destroying:Once(function()
		states[character] = nil
	end)
end

-- Возвращает персонажу прежний вид, коллизии и подвижность (режим прогулки).
function CharacterHider.show(character: Model)
	local state = states[character]
	if state then
		states[character] = nil
		state.connection:Disconnect()
		for instance, properties in state.saved do
			if instance.Parent then
				for name, value in properties do
					(instance :: any)[name] = value
				end
			end
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
		end
	end
	setAnchored(character, false)
end

return CharacterHider
