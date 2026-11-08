--!strict
-- Brief 8: concurrent runs. Every run slot (Run/ cloned once per map, plus the hub slot = the Run/ template) wires
-- its client -> server handlers through Run/SlotRemotes, which lands here: one real connection per remote, each
-- call routed to the handlers of the slot the player belongs to (Runs installs `slotOf`). So a party's FireShot,
-- votes, pause and debug calls reach only its own run's modules; everyone else's go to the hub slot.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local RemoteRouter = {}

-- Installed by Runs: the slot id a player's calls go to ("hub" when not in a party).
RemoteRouter.slotOf = function(_player: Player): string
	return "hub"
end

type Handler = (Player, ...any) -> ...any

local events: { [string]: { [string]: { Handler } } } = {}
local invokes: { [string]: { [string]: Handler } } = {}

function RemoteRouter.connect(name: string, slotId: string, fn: Handler): { Disconnect: () -> () }
	local bySlot = events[name]
	if not bySlot then
		local fresh: { [string]: { Handler } } = {}
		bySlot = fresh
		events[name] = fresh
		Remotes[name].OnServerEvent:Connect(function(player: Player, ...)
			local list = fresh[RemoteRouter.slotOf(player)]
			if list then
				for _, f in list do
					task.spawn(f, player, ...)
				end
			end
		end)
	end
	local list = bySlot[slotId]
	if not list then
		list = {}
		bySlot[slotId] = list
	end
	table.insert(list, fn)
	local own = list
	return {
		Disconnect = function()
			local i = table.find(own, fn)
			if i then
				table.remove(own, i)
			end
		end,
	}
end

function RemoteRouter.invoke(name: string, slotId: string, fn: Handler)
	local bySlot = invokes[name]
	if not bySlot then
		local fresh: { [string]: Handler } = {}
		bySlot = fresh
		invokes[name] = fresh
		Remotes[name].OnServerInvoke = function(player: Player, ...)
			local f = fresh[RemoteRouter.slotOf(player)]
			if f then
				return f(player, ...)
			end
			return nil
		end
	end
	bySlot[slotId] = fn
end

return RemoteRouter
