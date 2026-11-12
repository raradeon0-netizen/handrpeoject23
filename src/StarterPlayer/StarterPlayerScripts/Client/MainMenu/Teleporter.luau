--!strict
-- Teleporter: отправляет выбор фракции на сервер.
-- Сам телепорт и создание участка теперь делает сервер (PlotService):
-- он строит личный Plot 200x200 и ставит персонажа в его центр.
-- Клиент только ждёт ответа: true = готово, false = ошибка (меню вернётся назад).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FactionConfig = require(ReplicatedStorage.Shared.FactionConfig)
local PlotConfig = require(ReplicatedStorage.Shared.PlotConfig)

local REMOTE_TIMEOUT = 10 -- сколько секунд ждать RemoteFunction от сервера

local Teleporter = {}

function Teleporter.toFaction(factionId: string): boolean
	if not FactionConfig.ById[factionId] then
		warn(`[Teleporter] Неизвестная фракция: {factionId}`)
		return false
	end

	local remote = ReplicatedStorage.Shared:WaitForChild(PlotConfig.RemoteName, REMOTE_TIMEOUT)
	if not remote or not remote:IsA("RemoteFunction") then
		warn("[Teleporter] Сервер не ответил: RemoteFunction не найдена")
		return false
	end

	-- InvokeServer ждёт, пока сервер построит участок и телепортирует персонажа.
	local ok, result = pcall(function()
		return remote:InvokeServer(factionId)
	end)
	if not ok then
		warn(`[Teleporter] Ошибка вызова сервера: {result}`)
		return false
	end
	return result == true
end

return Teleporter
