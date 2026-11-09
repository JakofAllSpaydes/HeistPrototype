--!strict
-- Brief 13: the debug commands of the heist systems (the debug panel's HEIST group, client/HeistDebug.lua),
-- registered into Debug's table so Debug.lua stays as it was. Only honoured where Debug honours commands.
local Debug = require(script.Parent.Debug)
local World = require(script.Parent.World)
local Breach = require(script.Parent.Breach)
local Dressing = require(script.Parent.Dressing)
local RelicService = require(script.Parent.RelicService)
local Profiles = require(script.Parent.Parent.Profiles)
local Relics = require(game:GetService("ReplicatedStorage").Shared.Relics)
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

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
	-- Step 4: the street at a stage now (0..3; 4 = stage 3 and the boss pieces), and the helicopter on / off.
	Debug.add("DressingStage", function(player, _state, args)
		local n = tonumber(args) or 0
		Dressing.debugStage(n)
		Debug.toast(
			player,
			if n >= 4 then "DRESSING STAGE 3 + BOSS" else "DRESSING STAGE " .. math.clamp(math.floor(n), 0, 3)
		)
	end)
	-- Step 5: relics. The next gun crate's roll hits; grant one to yourself; clear yours; the first-crate flag off.
	Debug.add("ForceRelic", function(player, _state, _args)
		RelicService.forceNext = true
		Debug.toast(player, "NEXT GUN CRATE DROPS A RELIC")
	end)
	Debug.add("GrantRelic", function(player, _state, args)
		local id = tostring(args)
		if not Relics.ById[id] then
			Debug.toast(player, "NO RELIC " .. string.upper(id))
			return
		end
		local r = RelicService.grant(player, id)
		Debug.toast(player, string.format("%s · %s", Relics.title(id), string.upper(r)))
	end)
	Debug.add("ResetRelics", function(player, _state, _args)
		RelicService.reset(player)
		Debug.toast(player, "RELICS RESET · FIRST CRATE ARMED")
	end)
	Debug.add("ForceFirstCrate", function(player, _state, _args)
		local p = Profiles.get(player)
		if p then
			p.relics.firstCrateOpened = false
			Profiles.markDirty(player)
		end
		Debug.toast(player, "FIRST CRATE ARMED")
	end)
	Debug.add("HeliToggle", function(player, _state, _args)
		local on = not (if Dressing.heliOverride ~= nil then Dressing.heliOverride else Config.HeliEnabled)
		Dressing.debugHeli(on)
		Debug.toast(player, if on then "HELICOPTER ON (STAGE 3)" else "HELICOPTER OFF")
	end)
end

return HeistDebug
