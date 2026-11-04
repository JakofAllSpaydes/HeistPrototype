--!strict
-- Server entry point. Builds the map, wires every module, then runs the run state machine forever:
-- Hub (yard, nothing hostile) -> Queue start -> Intro -> Wave -> Intermission -> Wave ... -> RunOver ->
-- RunEnd -> Summary -> Hub. The party (World.party, set by Queue) is the run's player set; everyone else
-- stays in the hub.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)

local Room = require(script.Parent.Room)
Room.build()

local World = require(script.Parent.World)
local Log = require(script.Parent.Log)
local Profiles = require(script.Parent.Profiles)
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
local Hub = require(script.Parent.Hub)
local Queue = require(script.Parent.Queue)
local Meta = require(script.Parent.Meta)
local Minigames = require(script.Parent.Minigames)
local Downed = require(script.Parent.Downed)
local RunStart = require(script.Parent.RunStart)
local RunEnd = require(script.Parent.RunEnd)

Profiles.init()
PlayerState.init()
Downed.init()
SkipVote.init()
Abilities.init()
Enemy.init()
Combat.init()
UpgradeShop.init()
WeaponRoll.init()
BigCrate.init()
CrewCall.init()
Hub.init()
Queue.init()
Meta.init()
Minigames.init()
RunEnd.init()
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
			World.fireRun("SkipPassed", { votes = World.skipVoteCount(), needed = World.skipNeeded() })
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
		World.fireRun("WaveStart", { wave = wave })
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
			World.addWaveGold(wave)
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
		World.fireRun("Intermission", { wave = wave, endsAt = World.intermissionEndsAt })
		waitIntermission()
		if not World.pendingWave then
			World.wave = wave + 1
		end
	end
end

task.spawn(function()
	while true do
		-- Hub: the last run's party comes back to the yard; the arena is cleared; the zone reopens.
		local lastParty = World.partyPlayers()
		local choice = World.lastChoice
		World.lastChoice = nil
		World.wave = 1
		World.runOver = false
		World.runRequested = false
		World.pendingWave = nil
		World.skipRequested = false
		World.summaryChoice = nil
		setState("Hub")
		Queue.onRunEnded(choice)
		Hub.enter(lastParty)
		World.fireRun("HubEnter", {})
		World.party = {}
		PlayerState.markAllDirty()
		Log.event(
			"Run",
			"Hub: waiting for a party (%d queue zone%s)",
			Queue.zoneCount(),
			if Queue.zoneCount() == 1 then "" else "s"
		)
		while not World.runRequested do
			task.wait(0.1)
		end
		World.runRequested = false
		World.runId += 1
		World.runGold = 0
		World.objectivesDone = 0

		-- Run start: fresh run state for the party, then the drive-in sequence (IntroSec); WAVE 1 follows.
		World.wave = 1
		World.heat = Config.HeatStart
		World.heatDirty = true
		Hub.beginRun()
		setState("Intro")
		Log.event(
			"Run",
			"Run %d start for a party of %d (%s), first wave in %.1fs",
			World.runId,
			#World.party,
			World.partyKey(),
			Config.IntroSec
		)
		RunStart.play()
		BigCrate.onIntro()

		runWaves()

		-- Run over: enemies freeze and fade under the RUN OVER stamp. While the stamp holds, REVIVE EVERYBODY
		-- still saves the run: the crew stands up and the same wave restarts.
		local window = Config.RunOverSlowSec + Config.RunOverHoldSec
		while true do
			setState("RunOver")
			World.fireRun("RunOver", {
				wave = World.wave,
				slowSec = Config.RunOverSlowSec,
				holdSec = Config.RunOverHoldSec,
				timeScale = Config.RunOverTimeScale,
				reviveWindowSec = window,
			})
			Enemy.freezeAll(Config.RunOverSlowSec)
			Log.event("Run", "Run %d over at wave %d (%.1fs to revive everybody)", World.runId, World.wave, window)
			local t0 = os.clock()
			while World.runOver and os.clock() - t0 < window do
				task.wait(0.1)
			end
			if World.runOver then
				break
			end
			Enemy.killAll()
			World.fireRun("RunResumed", { wave = World.wave })
			Log.event("Run", "second chance: wave %d restarts", World.wave)
			task.wait(1.5)
			runWaves()
		end
		Enemy.killAll()

		-- Run end sequence, MVP, payout, summary (PLAY AGAIN re-forms the party, TO LOBBY returns to the hub).
		setState("RunEnd")
		local result = RunEnd.play()
		World.lastChoice = result
		Log.event("Run", "summary closed (%s), back to the hub", result)
	end
end)
