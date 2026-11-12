--!strict
-- PlotService (Script): точка входа серверной части.
-- Слушает выбор фракции в Главном Меню и выдаёт игроку личный участок:
--   1) проверяет запрос от клиента,
--   2) занимает слот в сетке и строит участок (PlotBuilder),
--   3) закрепляет участок за игроком (PlotOwnership),
--   4) телепортирует персонажа в центр участка (PlotTeleporter).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FactionConfig = require(ReplicatedStorage.Shared.FactionConfig)
local PlotConfig = require(ReplicatedStorage.Shared.PlotConfig)

local PlotAllocator = require(script.Parent.PlotAllocator)
local PlotBuilder = require(script.Parent.PlotBuilder)
local PlotResizer = require(script.Parent.PlotResizer)
local PlotOwnership = require(script.Parent.PlotOwnership)
local CharacterHider = require(script.Parent.CharacterHider)
local PlotTeleporter = require(script.Parent.PlotTeleporter)

-- Шаг 1. Подготовка: папка для участков и RemoteFunction для меню.
local plotsFolder = workspace:FindFirstChild(PlotConfig.FolderName)
if not plotsFolder then
	plotsFolder = Instance.new("Folder")
	plotsFolder.Name = PlotConfig.FolderName
	plotsFolder.Parent = workspace
end

local selectFaction = Instance.new("RemoteFunction")
selectFaction.Name = PlotConfig.RemoteName
selectFaction.Parent = ReplicatedStorage.Shared

local resizePlot = Instance.new("RemoteFunction")
resizePlot.Name = PlotConfig.ResizeRemoteName
resizePlot.Parent = ReplicatedStorage.Shared

local setWalkMode = Instance.new("RemoteFunction")
setWalkMode.Name = PlotConfig.WalkRemoteName
setWalkMode.Parent = ReplicatedStorage.Shared

local busyPlayers: { [Player]: boolean } = {} -- защита от повторных запросов
local walking: { [Player]: boolean } = {} -- игрок гуляет по участку (персонаж виден)

-- Полная очистка игрока: участок, закрепление и слот. Безопасно вызывать повторно.
local function releasePlayer(player: Player)
	local claim = PlotOwnership.release(player)
	if claim then
		claim.plot:Destroy()
	end
	PlotAllocator.release(player.UserId)
end

-- Шаг 2a. Телепортирует игрока в центр участка и прячет его персонажа:
-- дальше игрок смотрит на участок свободной камерой, персонаж ему не нужен.
local function placeOnPlot(player: Player, plot: Part): boolean
	if not PlotTeleporter.toPlot(player, plot) then
		return false
	end

	local character = player.Character
	if character then
		CharacterHider.hide(character)
	end
	return true
end

-- Шаг 2. Создаёт участок и переносит на него игрока.
local function assignPlot(player: Player, faction: FactionConfig.Faction): boolean
	-- Участок уже есть (повторный запрос): новый не строим, просто возвращаем на него.
	local existing = PlotOwnership.getClaim(player)
	if existing and existing.factionId == faction.id then
		return placeOnPlot(player, existing.plot)
	end
	if existing then
		-- Игрок вернулся в главное меню и выбрал другую фракцию: прежний участок
		-- освобождается (с автосохранением), постройки подгрузятся на новый.
		releasePlayer(player)
	end

	-- Слот в сетке -> центр участка -> Part нужного стиля.
	local slot = PlotAllocator.acquire(player.UserId)
	local center = PlotAllocator.slotCenter(slot)
	local plot = PlotBuilder.build(plotsFolder, player, faction.id, slot, center)

	-- Закрепляем территорию ДО телепорта: она принадлежит игроку с первой секунды.
	PlotOwnership.claim(player, plot, faction.id)

	-- Телепорт. Если персонажа нет, откатываем всё, чтобы не осталось «мёртвых» участков.
	if not placeOnPlot(player, plot) then
		releasePlayer(player)
		return false
	end
	return true
end

-- Шаг 3. Обработчик сигнала из меню. Возвращаемое значение получает клиент:
-- true = всё готово, false = меню нужно вернуть на экран выбора.
selectFaction.OnServerInvoke = function(player: Player, factionId: unknown): boolean
	walking[player] = nil -- вход на участок всегда начинается в режиме стройки
	-- Данным от клиента верить нельзя: проверяем тип и существование фракции.
	if typeof(factionId) ~= "string" then
		return false
	end
	local faction = FactionConfig.ById[factionId]
	if not faction then
		warn(`[PlotService] {player.Name} прислал неизвестную фракцию: {factionId}`)
		return false
	end

	if busyPlayers[player] then
		return false
	end
	busyPlayers[player] = true

	local success, result = pcall(assignPlot, player, faction)
	busyPlayers[player] = nil

	if not success then
		warn(`[PlotService] Ошибка выдачи участка для {player.Name}: {result}`)
		releasePlayer(player)
		return false
	end
	return result
end

-- Шаг 4. Игрок вышел: удаляем участок и освобождаем слот для следующих.
-- Режим прогулки: true — показать персонажа и поставить у входа на участок,
-- false — снова спрятать и вернуть в центр (режим стройки).
setWalkMode.OnServerInvoke = function(player: Player, value: unknown): boolean
	local claim = PlotOwnership.getClaim(player)
	local character = player.Character
	if not claim or not character or typeof(value) ~= "boolean" then
		return false
	end
	if value then
		if not PlotTeleporter.toWalkSpot(player, claim.plot) then
			return false
		end
		CharacterHider.show(character)
		walking[player] = true
	else
		walking[player] = nil
		placeOnPlot(player, claim.plot)
	end
	return true
end

-- Смена размера плиты из настроек клиента. Возвращает (успех, сообщение, нынешний размер).
local lastResize: { [Player]: number } = {}

resizePlot.OnServerInvoke = function(player: Player, size: unknown): (boolean, string?, number?)
	local claim = PlotOwnership.getClaim(player)
	if not claim then
		return false, "Сначала выберите цивилизацию и получите участок", nil
	end
	local current = claim.plot.Size.X
	if typeof(size) ~= "number" then
		return false, nil, current
	end
	local now = os.clock()
	if now - (lastResize[player] or -math.huge) < PlotConfig.ResizeCooldown then
		return false, "Не так быстро", current
	end
	lastResize[player] = now

	local ok, message = PlotResizer.resize(claim.plot, size, claim.factionId)
	return ok, message, claim.plot.Size.X
end

Players.PlayerRemoving:Connect(function(player: Player)
	busyPlayers[player] = nil
	lastResize[player] = nil
	walking[player] = nil
	releasePlayer(player)
end)

-- Шаг 5. Респавн: возвращаем игрока на его участок и снова прячем персонажа.
local function trackRespawns(player: Player)
	player.CharacterAdded:Connect(function()
		local claim = PlotOwnership.getClaim(player)
		if claim and walking[player] then
			-- Гулявший игрок возвращается видимым ко входу на участок.
			PlotTeleporter.toWalkSpot(player, claim.plot)
		elseif claim then
			placeOnPlot(player, claim.plot)
		end
	end)
end

Players.PlayerAdded:Connect(trackRespawns)
for _, player in Players:GetPlayers() do
	trackRespawns(player)
end
