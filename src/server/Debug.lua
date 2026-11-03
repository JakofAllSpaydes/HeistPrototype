--!strict
-- Debug commands, server side. Only honoured in Studio or when Config.DebugEnabled.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Rarity = require(Shared.Rarity)
local PlayerState = require(script.Parent.PlayerState)
local Economy = require(script.Parent.Economy)
local Enemy = require(script.Parent.Enemy)
local WeaponRoll = require(script.Parent.WeaponRoll)
local BigCrate = require(script.Parent.BigCrate)
local CrewCall = require(script.Parent.CrewCall)
local Abilities = require(script.Parent.Abilities)
local World = require(script.Parent.World)
local Log = require(script.Parent.Log)
local Staging = require(script.Parent.Staging)
local Minigames = require(script.Parent.Minigames)

local Debug = {}

local function toast(player: Player, text: string)
	Remotes.Juice:FireClient(player, "Toast", { text = text })
end

local handlers: { [string]: (Player, PlayerState.State, any) -> () } = {
	AddCash = function(_player, state, args)
		Economy.addCash(state, tonumber(args) or 0)
	end,
	SkipWave = function(_player, _state, _args)
		World.skipRequested = true
	end,
	SetWave = function(player, _state, args)
		local n = tonumber(args)
		if n and n >= 1 then
			World.pendingWave = math.floor(n)
			World.skipRequested = true
		else
			toast(player, "SET WAVE: enter a number")
		end
	end,
	PauseSpawns = function(player, _state, _args)
		World.spawnsPaused = not World.spawnsPaused
		PlayerState.markAllDirty()
		toast(player, if World.spawnsPaused then "SPAWNS PAUSED" else "SPAWNS RESUMED")
	end,
	KillAll = function(_player, _state, _args)
		Enemy.killAll()
	end,
	ForceRarity = function(player, state, args)
		local r = if typeof(args) == "number" then args else Rarity.fromLetter(tostring(args))
		if r then
			state.forcedRarity = r
			toast(player, "NEXT ROLL: " .. string.upper(Rarity.name(r)))
		end
	end,
	ForceTradeoff = function(player, state, _args)
		state.forceTradeoff = true
		toast(player, "NEXT PICK-3 HAS A TRADEOFF")
	end,
	DropCrate = function(_player, _state, _args)
		BigCrate.drop()
	end,
	TriggerCall = function(_player, _state, _args)
		CrewCall.trigger()
	end,
	GodMode = function(player, state, _args)
		state.god = not state.god
		toast(player, if state.god then "GOD MODE ON" else "GOD MODE OFF")
	end,
	ResetRun = function(_player, _state, _args)
		for _, s in PlayerState.all() do
			PlayerState.reset(s, if World.inRun() then Config.StartingCash else Config.StagingCash)
		end
		BigCrate.finishAll()
		CrewCall.finish(false, true)
		WeaponRoll.clearAll()
		Abilities.clearAll()
		Enemy.killAll()
		World.spawnsPaused = false
		World.pendingWave = 1
		World.skipRequested = true
	end,
	StartRun = function(player, _state, _args)
		if World.state == "Staging" then
			Staging.requestRun(player)
		else
			toast(player, "ALREADY IN A RUN")
		end
	end,
	EndRun = function(player, _state, _args)
		if World.inRun() then
			World.runOver = true
			World.skipRequested = true
		else
			toast(player, "NO RUN TO END")
		end
	end,
	SetTier = function(player, _state, args)
		Staging.setTier(tonumber(args) or 1, player.Name)
	end,
	OpenMinigame = function(player, _state, args)
		Minigames.open(player, tostring(args))
	end,
	MinigameStats = function(_player, _state, _args)
		Minigames.printStats()
	end,
}

function Debug.init()
	Remotes.Debug.OnServerEvent:Connect(function(player: Player, command: any, args: any)
		if not (Config.DebugEnabled or RunService:IsStudio()) then
			return
		end
		local handler = handlers[tostring(command)]
		if not handler then
			return
		end
		local state = PlayerState.get(player)
		handler(player, state, args)
		state.dirty = true
		Log.event("Debug", "%s ran %s %s", player.Name, tostring(command), if args ~= nil then tostring(args) else "")
	end)
end

return Debug
