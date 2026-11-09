--!strict
-- Brief 13: the debug commands of the heist systems (the debug panel's HEIST group, client/HeistDebug.lua),
-- registered into Debug's table so Debug.lua stays as it was. Only honoured where Debug honours commands.
local Debug = require(script.Parent.Debug)
local World = require(script.Parent.World)
local Breach = require(script.Parent.Breach)

local HeistDebug = {}

function HeistDebug.init()
	-- The pre-heist ends now (as if someone walked in): the alarm, the doors, HEIST ON, wave 1.
	Debug.add("BreachNow", function(player, _state, _args)
		if not Breach.active then
			Debug.toast(player, if World.inRun() then "ALREADY BREACHED" else "NO PRE-HEIST RUNNING")
			return
		end
		Breach.requested = true
	end)
end

return HeistDebug
