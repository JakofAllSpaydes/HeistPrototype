--!strict
-- Brief 6: the run event bus. Gameplay modules emit what happened (kills by archetype, headshots, bags, waves,
-- side jobs, the vault, minigames, boss kills, revives, the class a run was finished as, kills by weapon
-- archetype); Jobs.lua listens. No requires, so anything can emit without a cycle.
local RunEvents = {}

export type Handler = (player: Player, kind: string, amount: number, arg: string?, map: string?) -> ()

local handlers: { Handler } = {}

-- Brief 7: the map every event happened on. Brief 8: per player, since two runs can be on at once (Run/Main sets
-- it for its party at run start and clears it back in the hub).
local mapOf: { [Player]: string } = {}

function RunEvents.setMap(players: { Player }, map: string?)
	for _, p in players do
		mapOf[p] = map
	end
end

function RunEvents.listen(fn: Handler)
	table.insert(handlers, fn)
end

function RunEvents.emit(player: Player?, kind: string, amount: number?, arg: string?)
	if not player or not player.Parent then
		return
	end
	for _, fn in handlers do
		local ok, err = pcall(fn, player, kind, amount or 1, arg, mapOf[player])
		if not ok then
			warn("[GHS RunEvents] " .. kind .. ": " .. tostring(err))
		end
	end
end

return RunEvents
