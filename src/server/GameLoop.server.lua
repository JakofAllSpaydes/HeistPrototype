--!strict
-- Server entry point. Builds the map, wires every module, then runs the run state machine forever:
-- Staging (yard, nothing hostile) -> START RUN -> Intro -> Wave -> Intermission -> Wave ... -> RunOver -> Staging.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local Room = require(script.Parent.Room)
Room.build()

local World = require(script.Parent.World)
local Log = require(script.Parent.Log)
local PlayerState = require(script.Parent.PlayerState)
local Enemy = require(script.Parent.Enemy)
local Spawner = require(script.Parent.Spawner)
local Combat = require(script.Parent.Combat)
local UpgradeShop = require(script.Parent.UpgradeShop)
local WeaponRoll = require(script.Parent.WeaponRoll)
local BigCrate = require(script.Parent.BigCrate)
local CrewCall = require(script.Parent.CrewCall)
local Debug = require(script.Parent.Debug)
local Abilities = require(script.Parent.Abilities)
local SkipVote = require(script.Parent.SkipVote)
local Staging = require(script.Parent.Staging)
local Minigames = require(script.Parent.Minigames)

PlayerState.init()
SkipVote.init()
Abilities.init()
Enemy.init()
Combat.init()
UpgradeShop.init()
WeaponRoll.init()
BigCrate.init()
CrewCall.init()
Staging.init()
Minigames.init()
Debug.init()

local function setState(state: string)
	World.state = state
	PlayerState.markAllDirty()
end

local function waitIntermission()
	local t0 = os.clock()
	while os.clock() - t0 < Config.IntermissionSec do
		if World.skipRequested or World.pendingWave or World.runOver then
			break
		end
		if os.clock() - t0 >= Config.SkipMinIntermissionSec and World.skipVotePassed() then
			Log.event("Wave", "Intermission skipped by vote (%d/%d)", World.skipVoteCount(), World.skipNeeded())
			Remotes.Juice:FireAllClients("SkipPassed", { votes = World.skipVoteCount(), needed = World.skipNeeded() })
			break
		end
		task.wait(0.1)
	end
end

-- Wave -> intermission -> wave until the run is over (game over or debug). World.wave stays on the last wave.
local function runWaves()
	while not World.runOver do
		if World.pendingWave then
			World.wave = World.pendingWave
			World.pendingWave = nil
		end
		local wave = World.wave
		World.skipRequested = false
		World.waveStartedAt = Workspace:GetServerTimeNow()
		SkipVote.reset()
		setState("Wave")
		Remotes.Juice:FireAllClients("WaveStart", { wave = wave })
		Log.event(
			"Wave",
			"Wave %d start, budget %d, server time %.1f",
			wave,
			Spawner.budgetFor(wave),
			Workspace:GetServerTimeNow()
		)
		BigCrate.onWaveStart(wave)
		CrewCall.onWaveStart(wave)

		local advanced = Spawner.runWave(wave)
		if World.runOver then
			return
		end

		BigCrate.onWaveEnd()
		if advanced then
			Log.event("Wave", "Wave %d rolled into the next by AUTO SKIP, %d still alive", wave, Enemy.count())
		else
			Log.event("Wave", "Wave %d clear", wave)
		end
		if not World.skipRequested then
			World.addHeat(Config.HeatWaveClear, "wave " .. wave .. " clear")
		end
		if World.pendingWave then
			continue
		end
		if advanced then
			-- No intermission: the next wave starts on top of what is left.
			World.wave = wave + 1
			continue
		end

		World.skipRequested = false
		World.intermissionEndsAt = Workspace:GetServerTimeNow() + Config.IntermissionSec
		SkipVote.reset()
		setState("Intermission")
		Remotes.Juice:FireAllClients("Intermission", { wave = wave, endsAt = World.intermissionEndsAt })
		waitIntermission()
		if not World.pendingWave then
			World.wave = wave + 1
		end
	end
end

task.spawn(function()
	while true do
		-- Staging: everyone in the yard, nothing hostile, until someone presses START RUN.
		World.wave = 1
		World.runOver = false
		World.runRequested = false
		World.pendingWave = nil
		World.skipRequested = false
		World.summaryChoice = nil
		setState("Staging")
		Staging.enter()
		Remotes.Juice:FireAllClients("StagingEnter", {})
		Log.event("Run", "Staging: waiting for START RUN")
		while not World.runRequested do
			task.wait(0.1)
		end
		World.runRequested = false
		World.runId += 1

		-- Run start. Bare teleport-in for now; the drive-in sequence takes this slot.
		World.wave = 1
		World.heat = Config.HeatStart
		World.heatDirty = true
		Staging.beginRun()
		setState("Intro")
		Remotes.Juice:FireAllClients("WaveStart", { wave = 1, intro = true })
		Log.event("Run", "Run %d start, first wave in %.1fs", World.runId, Config.IntroSec)
		BigCrate.onIntro()
		task.wait(Config.IntroSec)

		runWaves()

		-- Run over: hold on the arena for a beat, then everyone goes back to the yard.
		setState("RunOver")
		Remotes.Juice:FireAllClients("RunOver", { wave = World.wave })
		Log.event("Run", "Run %d over at wave %d", World.runId, World.wave)
		task.wait(Config.RunOverSlowSec)
	end
end)
