--!strict
-- Server entry point. Builds the room, wires every module, then runs the wave state machine forever:
-- Intro (WAVE 1 banner) -> Wave -> Intermission -> Wave ... No game over.
local Players = game:GetService("Players")
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

PlayerState.init()
SkipVote.init()
Abilities.init()
Enemy.init()
Combat.init()
UpgradeShop.init()
WeaponRoll.init()
BigCrate.init()
CrewCall.init()
Debug.init()

local function setState(state: string)
	World.state = state
	PlayerState.markAllDirty()
end

local function waitIntermission()
	local t0 = os.clock()
	while os.clock() - t0 < Config.IntermissionSec do
		if World.skipRequested or World.pendingWave then
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

-- Hold the intro until the first player is standing in the room, so they see the crate land.
local function waitForFirstPlayer()
	while true do
		for _, player in Players:GetPlayers() do
			local char = player.Character
			if char and char:FindFirstChild("HumanoidRootPart") then
				return
			end
		end
		task.wait(0.25)
	end
end

task.spawn(function()
	World.wave = 1
	setState("Intro")
	waitForFirstPlayer()
	task.wait(1)
	Remotes.Juice:FireAllClients("WaveStart", { wave = 1, intro = true })
	Log.event("Wave", "Intro, first wave in %ds", Config.IntroSec)
	BigCrate.onIntro()
	task.wait(Config.IntroSec)

	while true do
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
end)
