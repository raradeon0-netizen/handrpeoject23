--!strict
-- PlotOwnership: реестр «чей участок». Закрепляет территорию за игроком и
-- отвечает на вопрос «может ли игрок строить в этой точке?».
-- Будущая система строительства должна вызывать PlotOwnership.canBuildAt
-- перед тем, как поставить блок.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotConfig = require(ReplicatedStorage.Shared.PlotConfig)

export type Claim = {
	player: Player,
	plot: Part,
	factionId: string,
}

local PlotOwnership = {}

local claims: { [number]: Claim } = {} -- UserId -> участок
local claimCallbacks: { (Claim) -> () } = {}
local releaseCallbacks: { (Claim) -> () } = {}

-- Подписка на выдачу участка (например, подгрузить сохранённые постройки).
function PlotOwnership.onClaim(callback: (Claim) -> ())
	table.insert(claimCallbacks, callback)
end

-- Подписка на освобождение участка: вызывается до его удаления (автосохранение).
function PlotOwnership.onRelease(callback: (Claim) -> ())
	table.insert(releaseCallbacks, callback)
end

-- Закрепляет участок за игроком.
function PlotOwnership.claim(player: Player, plot: Part, factionId: string)
	local claim: Claim = { player = player, plot = plot, factionId = factionId }
	claims[player.UserId] = claim
	for _, callback in claimCallbacks do
		task.spawn(callback, claim)
	end
end

-- Участок игрока или nil, если он ещё не выбрал фракцию.
function PlotOwnership.getClaim(player: Player): Claim?
	return claims[player.UserId]
end

-- Снимает закрепление и возвращает снятую запись (nil, если её не было).
function PlotOwnership.release(player: Player): Claim?
	local claim = claims[player.UserId]
	if claim then
		-- Подписчики выполняются до первой паузы сразу: участок ещё цел, его можно прочитать.
		for _, callback in releaseCallbacks do
			task.spawn(callback, claim)
		end
	end
	claims[player.UserId] = nil
	return claim
end

-- Чей участок в этой точке мира? nil, если точка не принадлежит никому.
function PlotOwnership.getOwnerAt(position: Vector3): Player?
	for _, claim in claims do
		-- Переводим точку в локальные координаты участка и сравниваем с границами.
		local local_ = claim.plot.CFrame:PointToObjectSpace(position)
		local halfSize = claim.plot.Size / 2
		local insideX = math.abs(local_.X) <= halfSize.X
		local insideZ = math.abs(local_.Z) <= halfSize.Z
		local insideY = local_.Y >= -halfSize.Y and local_.Y <= halfSize.Y + PlotConfig.BuildHeight

		if insideX and insideZ and insideY then
			return claim.player
		end
	end
	return nil
end

-- Можно ли игроку строить в этой точке: только на собственном участке.
function PlotOwnership.canBuildAt(player: Player, position: Vector3): boolean
	return PlotOwnership.getOwnerAt(position) == player
end

return PlotOwnership
