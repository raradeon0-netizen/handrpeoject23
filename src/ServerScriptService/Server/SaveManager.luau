--!strict
-- SaveManager (сервер): облачное сохранение участка в DataStore.
--   * «Сохранить» / «Загрузить» из верхней панели клиента (RemoteEvent BuildConfig.SaveRemoteName);
--   * при получении участка сохранение подгружается само, при выходе игрока — записывается само;
--   * все обращения к DataStore обёрнуты в pcall: если хранилище недоступно (например, в Studio
--     выключен доступ к API), игрок получает понятное сообщение, а игра продолжает работать.
-- Автосохранение при выходе пишет данные, только если в этой сессии сохранение удалось
-- прочитать (или его точно не было): иначе сбой загрузки затёр бы постройки пустым участком.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BuildConfig = require(ReplicatedStorage.Shared.BuildConfig)

local PlotOwnership = require(script.Parent.PlotOwnership)
local PlotResizer = require(script.Parent.PlotResizer)
local PlotSerializer = require(script.Parent.PlotSerializer)

type StatusKind = "ok" | "error" | "info"

local SHUTDOWN_WAIT = 15 -- секунд ждём незавершённые записи при остановке сервера

local SaveManager = {}

local remote: RemoteEvent? = nil
local store: DataStore? = nil

local synced: { [number]: boolean } = {} -- UserId -> сохранение прочитано, автосохранение безопасно
local busy: { [number]: boolean } = {} -- UserId -> идёт сохранение или загрузка
local lastSave: { [number]: number } = {}
local pendingWrites = 0

-- Снимок только что освобождённого участка. При смене фракции новый участок выдаётся сразу,
-- пока запись ещё идёт в хранилище, — постройки берём отсюда, а не читаем устаревшие данные.
local handoff: { [number]: PlotSerializer.SaveData } = {}
local HANDOFF_LIFETIME = 30

local function send(player: Player, kind: StatusKind, text: string)
	if remote and player.Parent then
		remote:FireClient(player, kind, text)
	end
end

local function getStore(): DataStore?
	if store then
		return store
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(BuildConfig.SaveStoreName)
	end)
	if ok then
		store = result
		return result
	end
	warn("[SaveManager] DataStore недоступен:", result)
	return nil
end

local function keyFor(userId: number): string
	return "plot_" .. userId
end

local function unavailable(action: string): string
	if RunService:IsStudio() then
		return action
			.. ": хранилище недоступно. В Studio включите Game Settings → Security → "
			.. "Enable Studio Access to API Services (место должно быть опубликовано)"
	end
	return action .. ": хранилище сейчас недоступно, попробуйте позже"
end

local function read(userId: number): (boolean, any)
	local dataStore = getStore()
	if not dataStore then
		return false, nil
	end
	local ok, result = pcall(function()
		return dataStore:GetAsync(keyFor(userId))
	end)
	if not ok then
		warn("[SaveManager] Чтение не удалось:", result)
		return false, nil
	end
	return true, result
end

local function write(userId: number, data: PlotSerializer.SaveData): boolean
	local dataStore = getStore()
	if not dataStore then
		return false
	end
	pendingWrites += 1
	local ok, result = pcall(function()
		dataStore:SetAsync(keyFor(userId), data)
	end)
	pendingWrites -= 1
	if not ok then
		warn("[SaveManager] Запись не удалась:", result)
	end
	return ok
end

local function blocksFolder(plot: Part): Instance
	local folder = plot:FindFirstChild(BuildConfig.BlocksFolderName)
	if folder then
		return folder
	end
	local created = Instance.new("Folder")
	created.Name = BuildConfig.BlocksFolderName
	created.Parent = plot
	return created
end

local function snapshot(claim: PlotOwnership.Claim): PlotSerializer.SaveData
	return PlotSerializer.serialize(claim.plot, blocksFolder(claim.plot), claim.factionId)
end

-- ===== Действия игрока =====

local function save(player: Player)
	local userId = player.UserId
	local claim = PlotOwnership.getClaim(player)
	if not claim then
		return
	end
	if busy[userId] then
		send(player, "info", "Подождите: идёт сохранение или загрузка")
		return
	end
	local now = os.clock()
	if now - (lastSave[userId] or -math.huge) < BuildConfig.SaveCooldown then
		send(player, "info", "Сохранять можно раз в несколько секунд")
		return
	end
	lastSave[userId] = now

	busy[userId] = true
	local data = snapshot(claim)
	local ok = write(userId, data)
	busy[userId] = nil

	if ok then
		synced[userId] = true -- теперь в хранилище лежит именно этот участок
		send(player, "ok", string.format("Сохранено! Блоков: %d", #data.blocks))
	else
		send(player, "error", unavailable("Не удалось сохранить"))
	end
end

-- replace = true — кнопка «Загрузить»: нынешние постройки заменяются сохранёнными.
local function load(player: Player, claim: PlotOwnership.Claim, replace: boolean)
	local userId = player.UserId
	if busy[userId] then
		send(player, "info", "Подождите: идёт сохранение или загрузка")
		return
	end
	busy[userId] = true

	local function stillValid(): boolean
		return PlotOwnership.getClaim(player) == claim and claim.plot.Parent ~= nil
	end

	local ok: boolean, data: any = true, handoff[userId]
	handoff[userId] = nil
	if data == nil then
		ok, data = read(userId)
	end
	if not stillValid() then
		busy[userId] = nil
		return
	end
	if not ok then
		busy[userId] = nil
		send(player, "error", unavailable("Не удалось загрузить"))
		return
	end
	if data == nil then
		busy[userId] = nil
		synced[userId] = true -- сохранения нет: перезаписывать нечего
		if replace then
			send(player, "info", "Сохранений пока нет")
		end
		return
	end

	local blocks = blocksFolder(claim.plot)
	if replace then
		blocks:ClearAllChildren()
	end
	-- Сначала плита принимает сохранённый размер: иначе постройки могли бы не поместиться.
	local savedSize = if typeof(data) == "table" then data.plotSize else nil
	if typeof(savedSize) == "number" then
		PlotResizer.resize(claim.plot, savedSize, claim.factionId)
	end
	local restored = PlotSerializer.restore(claim.plot, blocks, data, claim.factionId, player, stillValid)
	busy[userId] = nil
	if stillValid() then
		synced[userId] = true
		send(player, "ok", string.format("Загружено! Блоков: %d", restored))
	end
end

-- Автосохранение: снимок делается сразу (участок вот-вот удалят), запись идёт в фоне.
local function autoSave(claim: PlotOwnership.Claim)
	local userId = claim.player.UserId
	local allowed = synced[userId] and not busy[userId]
	synced[userId] = nil
	busy[userId] = nil
	lastSave[userId] = nil
	if allowed then
		local data = snapshot(claim)
		handoff[userId] = data
		task.delay(HANDOFF_LIFETIME, function()
			if handoff[userId] == data then
				handoff[userId] = nil
			end
		end)
		task.spawn(write, userId, data)
	end
end

function SaveManager.start()
	if remote then
		return
	end
	local created = Instance.new("RemoteEvent")
	created.Name = BuildConfig.SaveRemoteName
	created.Parent = ReplicatedStorage.Shared
	remote = created

	created.OnServerEvent:Connect(function(player: Player, action: unknown)
		if action == "Save" then
			save(player)
		elseif action == "Load" then
			local claim = PlotOwnership.getClaim(player)
			if claim then
				load(player, claim, true)
			end
		end
	end)

	-- Новый участок: подгружаем сохранённые постройки.
	PlotOwnership.onClaim(function(claim: PlotOwnership.Claim)
		load(claim.player, claim, false)
	end)
	-- Участок освобождается (игрок выходит): автосохранение.
	PlotOwnership.onRelease(autoSave)

	-- Остановка сервера: сохраняем всех и ждём, пока записи дойдут до хранилища.
	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			local claim = PlotOwnership.getClaim(player)
			if claim then
				autoSave(claim)
			end
		end
		local deadline = os.clock() + SHUTDOWN_WAIT
		while pendingWrites > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return SaveManager
