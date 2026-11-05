--!strict
-- Debug commands, server side. Only honoured in Studio or when Config.DebugEnabled.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Rarity = require(Shared.Rarity)
local Enemies = require(Shared.Enemies)
local Room = require(script.Parent.Room)
local PlayerState = require(script.Parent.PlayerState)
local Economy = require(script.Parent.Economy)
local Enemy = require(script.Parent.Enemy)
local WeaponRoll = require(script.Parent.WeaponRoll)
local BigCrate = require(script.Parent.BigCrate)
local CrewCall = require(script.Parent.CrewCall)
local Abilities = require(script.Parent.Abilities)
local World = require(script.Parent.World)
local Log = require(script.Parent.Log)
local Hub = require(script.Parent.Hub)
local Minigames = require(script.Parent.Minigames)
local Downed = require(script.Parent.Downed)
local Profiles = require(script.Parent.Profiles)
local Queue = require(script.Parent.Queue)
local Heat = require(script.Parent.Heat)
local Bags = require(script.Parent.Bags)
local VaultJob = require(script.Parent.VaultJob)
local Boss = require(script.Parent.Boss)
local Progression = require(script.Parent.Progression)

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
	-- Spawn one archetype (args = id, "elite:<id>" for an elite) at the marker nearest the player.
	SpawnEnemy = function(player, _state, args)
		local id = tostring(args)
		local elite = false
		if string.sub(id, 1, 6) == "elite:" then
			elite = true
			id = string.sub(id, 7)
		end
		if not Enemies.ById[id] then
			toast(player, "NO SUCH ENEMY: " .. id)
			return
		end
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local best = Room.randomSpawnPoint()
		if root then
			local bestDist = math.huge
			for _, p in Room.spawnPoints do
				local d = (p - root.Position).Magnitude
				if d < bestDist then
					bestDist = d
					best = p
				end
			end
		end
		Enemy.spawn(id, World.wave, best, { elite = elite })
		World.enemiesLeft = math.max(World.enemiesLeft, Enemy.count())
		PlayerState.markAllDirty()
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
	ForceElement = function(player, state, _args)
		state.forceElement = true
		toast(player, "NEXT PICK-3 HAS AN ELEMENT")
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
			PlayerState.reset(s, if World.inRun() then Config.StartingCash else Config.HubCash)
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
	-- Force a run: the player's party (or a party of just them) starts now, whatever the countdown says.
	StartRun = function(player, _state, _args)
		if World.state == "Hub" then
			Queue.forceStart(player)
		else
			toast(player, "ALREADY IN A RUN")
		end
	end,
	AddGold = function(player, _state, args)
		Profiles.addGold(player, tonumber(args) or 1000, "debug")
	end,
	ResetProfile = function(player, state, _args)
		Profiles.reset(player)
		PlayerState.applyProfile(state)
		toast(player, "PROFILE RESET")
	end,
	UnlockAll = function(player, state, _args)
		Profiles.unlockAll(player)
		PlayerState.applyProfile(state)
		toast(player, "EVERYTHING UNLOCKED")
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
		Hub.setTier(tonumber(args) or 1, player.Name)
	end,
	OpenMinigame = function(player, _state, args)
		Minigames.open(player, tostring(args))
	end,
	MinigameStats = function(_player, _state, _args)
		Minigames.printStats()
		Heat.printStats()
		Economy.printStats()
	end,
	-- The boss without the cutscene, at the marker nearest the player.
	SpawnBoss = function(player, _state, _args)
		if not World.inRun() then
			toast(player, "NO RUN")
			return
		end
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local best = Room.randomSpawnPoint()
		if root then
			local bestDist = math.huge
			for _, p in Room.spawnPoints do
				local d = (p - root.Position).Magnitude
				if d < bestDist then
					bestDist = d
					best = p
				end
			end
		end
		Boss.spawn(Config.BossId, World.wave, best)
		World.enemiesLeft = math.max(World.enemiesLeft, Enemy.count())
		PlayerState.markAllDirty()
	end,
	SpawnBag = function(player, _state, args)
		Bags.debugSpawn(player, tostring(args))
	end,
	-- Loot Rush: a bag burst round the player (bypasses the cap), to test a pile of pickups at once.
	LootRush = function(player, _state, _args)
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or not World.inRun() then
			toast(player, "NO RUN")
			return
		end
		Bags.burstAround(root.Position, Config.LootRushCash, Config.LootRushGold, Config.LootRushRadius)
		toast(player, "LOOT RUSH")
	end,
	OpenVault = function(player, _state, _args)
		if VaultJob.phase == "closed" or VaultJob.phase == "job" then
			if VaultJob.phase == "job" then
				CrewCall.finish(true)
			else
				VaultJob.open()
			end
		else
			toast(player, "VAULT IS " .. string.upper(VaultJob.phase))
		end
	end,
	GasVault = function(player, _state, _args)
		if VaultJob.phase == "open" or VaultJob.phase == "warn" then
			VaultJob.debugGas()
		else
			toast(player, "VAULT IS " .. string.upper(VaultJob.phase))
		end
	end,
	AddXp = function(player, state, args)
		Progression.addXp(player, tonumber(args) or 500)
		Hub.refreshTag(player)
		state.dirty = true
	end,
	SetLevel = function(player, state, args)
		local n = tonumber(args)
		if n then
			Progression.setLevel(player, n)
			Hub.refreshTag(player)
			state.dirty = true
		else
			toast(player, "SET LEVEL: enter a number")
		end
	end,
	ResetDaily = function(player, _state, _args)
		Progression.resetDaily(player)
		toast(player, "DAILY FLAG RESET")
	end,
	SetHeat = function(player, _state, args)
		local n = tonumber(args)
		if n then
			Heat.set(n)
			toast(player, string.format("HEAT %.1f", World.heat))
		else
			toast(player, "SET HEAT: enter a number")
		end
	end,
	DownMe = function(player, _state, _args)
		Downed.down(player)
	end,
	DownAll = function(_player, _state, _args)
		for p, s in PlayerState.all() do
			if PlayerState.isStanding(s) then
				Downed.down(p)
			end
		end
	end,
	ReviveAll = function(_player, _state, _args)
		Downed.reviveEverybody(nil)
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
