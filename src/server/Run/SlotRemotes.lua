--!strict
-- Brief 8: the remotes as the modules of one run slot see them. Same names and calls as Shared.Remotes:
-- FireClient / FireAllClients pass straight through; OnServerEvent:Connect and OnServerInvoke = register with
-- RemoteRouter under this slot, so a handler only ever hears from players of its own run (or the hub).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Real = require(ReplicatedStorage.Shared.Remotes)
local RemoteRouter = require(script.Parent.Parent.RemoteRouter)
local Slot = require(script.Parent.Slot)

local SlotRemotes = {} :: { [string]: any }

for name, real in Real do
	local proxy = {}
	proxy.OnServerEvent = {
		Connect = function(_self: any, fn: (Player, ...any) -> ())
			return RemoteRouter.connect(name, Slot.id, fn)
		end,
	}
	function proxy.FireClient(_self: any, player: Player, ...: any)
		real:FireClient(player, ...)
	end
	function proxy.FireAllClients(_self: any, ...: any)
		real:FireAllClients(...)
	end
	setmetatable(proxy, {
		__newindex = function(t: any, key: any, value: any)
			if key == "OnServerInvoke" then
				RemoteRouter.invoke(name, Slot.id, value)
			else
				rawset(t, key, value)
			end
		end,
		__index = function(_t: any, key: any)
			return (real :: any)[key]
		end,
	})
	SlotRemotes[name] = proxy
end

return SlotRemotes
