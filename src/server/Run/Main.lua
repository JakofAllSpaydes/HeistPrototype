--!strict
-- One run slot's entry point (brief 8; was the body of GameLoop.server.lua). Builds this slot's map pieces, wires
-- every run module, then (map slots only) runs the run state machine forever:
-- Hub (idle) -> Queue start -> Intro -> Wave -> Intermission -> Wave ... -> RunOver -> RunEnd -> Summary -> Hub.
-- The party (World.party, set by Queue on this slot) is the run's player set; everyone else stays in the hub.
-- The hub slot (the Run/ template) wires the same modules for the players in the hub and never starts a run.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(script.Parent.SlotRemotes)
local Maps = require(Shared.Maps)

local Slot = require(script.Parent.Slot)
local Room = require(script.Parent.Room)
local MapLoader = require(script.Parent.MapLoader)
local EnemyPath = require(script.Parent.EnemyPath)
local Doors = require(script.Parent.Doors)
local Windows = require(script.Parent.Windows)
local Alarms = require(script.Parent.Alarms) -- Round 19c
local ZoneGas = require(script.Parent.ZoneGas) -- Round 19c
local Offices = require(script.Parent.Offices) -- Round 19f

local World = require(script.Parent.World)
local Log = require(script.Parent.Parent.Log)
local Profiles = require(script.Parent.Parent.Profiles)
local PlayerState = require(script.Parent.Parent.PlayerState)
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
local Hub = require(script.Parent.Parent.Hub)
local Queue = require(script.Parent.Parent.Queue)
local Minigames = require(script.Parent.Minigames)
local Downed = require(script.Parent.Downed)
local RunStart = require(script.Parent.RunStart)
local RunEnd = require(script.Parent.RunEnd)
local Heat = require(script.Parent.Heat)
local Bags = require(script.Parent.Bags)
local VaultJob = require(script.Parent.VaultJob)
local Boss = require(script.Parent.Boss)
local Roster = require(script.Parent.Roster)
local Economy = require(script.Parent.Parent.Economy)
local AllyCallout = require(script.Parent.AllyCallout)
local Elements = require(script.Parent.Elements)
local Mastery = require(script.Parent.Mastery)
local Pause = require(script.Parent.Pause)
local Dealer = require(script.Parent.Dealer)
local RunEvents = require(script.Parent.Parent.RunEvents)
local Jobs = require(script.Parent.Parent.Jobs)
local Squad = require(script.Parent.Squad)
local Range = require(script.Parent.Range)

local Main = {}

local function setState(state: string)
	World.state = state
	for _, p in World.partyPlayers() do
		PlayerState.markDirty(p)
	end
end

-- Everything hostile or left over from this slot's last run goes away (was Hub.clearArena).
local function clearArena()
	Enemy.killAll()
	BigCrate.finishAll()
	CrewCall.clearAll()
	WeaponRoll.clearAll()
	Abilities.clearAll()
	Squad.clear()
	Bags.clearAll()
	VaultJob.resetRun()
	Boss.clear()
	Enemy.paused = false
	World.spawnsPaused = false
	World.enemiesLeft = 0
end
Main.clearArena = clearArena
RunEnd.clearArena = clearArena

-- Paused time does not count (Pause pushes intermissionEndsAt forward every frame of a pause).
local function waitIntermission()
	local minAt = World.intermissionEndsAt - Config.IntermissionSec + Config.SkipMinIntermissionSec
	while Workspace:GetServerTimeNow() < World.intermissionEndsAt do
		if World.skipRequested or World.pendingWave or World.runOver or Dealer.requested then
			break
		end
		if Pause.active() then
			minAt += Pause.hold()
		end
		if Workspace:GetServerTimeNow() >= minAt and World.skipVotePassed() then
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
		-- Boss wave: the cutscene plays first (the game pauses; the boss steps in during it; the run clock waits).
		if World.isBossWave(wave) and not Boss.isActive() then
			local t0 = Workspace:GetServerTimeNow()
			Boss.cutscene(wave)
			if World.runClockStart > 0 then
				World.runClockPaused += Workspace:GetServerTimeNow() - t0
			end
			if World.runOver then
				return
			end
		end
		World.waveStartedAt = Workspace:GetServerTimeNow()
		if World.runClockStart <= 0 then
			World.runClockStart = World.waveStartedAt -- TIME SURVIVED runs from the WAVE 1 banner
		end
		SkipVote.reset()
		setState("Wave")
		World.fireRun("WaveStart", { wave = wave, boss = World.isBossWave(wave) })
		Heat.waveStarted(wave, Spawner.regularBudget(wave))
		Log.event(
			"Wave",
			"%s wave %d start, budget %d, par %.1fs, server time %.1f%s",
			Maps.get(World.map).short,
			wave,
			Spawner.budgetFor(wave),
			Heat.parFor(wave, Spawner.regularBudget(wave)),
			Workspace:GetServerTimeNow(),
			if World.isBossWave(wave) then " (boss wave)" else ""
		)
		BigCrate.onWaveStart(wave)
		Doors.onWaveStart(wave) -- brief 7: a door due by this wave takes the slot before the side-job draw
		CrewCall.onWaveStart(wave)
		Bags.onWaveStart(wave)
		ZoneGas.onWaveStart(wave) -- Round 19c: every few waves the crew's zone is gassed

		local advanced = Spawner.runWave(wave)
		if World.runOver then
			return
		end

		BigCrate.onWaveEnd()
		for _, p in World.partyPlayers() do
			RunEvents.emit(p, "wave", wave) -- brief 6 Jobs: the best wave reached
		end
		Economy.logWave(wave, World.partyPlayers())
		EnemyPath.logWave(wave)
		Mastery.onWaveEnd(wave, World.partyPlayers())
		if advanced then
			Log.event("Wave", "Wave %d rolled into the next by AUTO SKIP, %d still alive", wave, Enemy.count())
		else
			Log.event("Wave", "%s wave %d clear", Maps.get(World.map).short, wave)
		end
		if not World.skipRequested then
			World.addWaveGold(wave)
		end
		-- The dealer break: after a boss wave is cleared (or on debug request), before the intermission.
		if
			not World.runOver
			and not World.pendingWave
			and not advanced
			and (World.isBossWave(wave) or Dealer.requested)
		then
			World.skipRequested = false
			Dealer.run(wave)
			if World.runOver then
				return
			end
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
		Doors.onIntermission(wave + 1) -- brief 7: doors due next wave are called now
		waitIntermission()
		-- Debug "Open dealer now" during the intermission: the break runs, then the next wave.
		if Dealer.requested and not World.runOver and not World.pendingWave then
			Dealer.run(wave)
			if World.runOver then
				return
			end
		end
		if not World.pendingWave then
			World.wave = wave + 1
		end
	end
end

-- One run from the queue start to the summary.
local function playRun()
	World.runId += 1
	RunEvents.setMap(World.partyPlayers(), World.map)
	World.runGold = 0
	World.objectivesDone = 0
	World.banked = 0
	World.wavesCleared = 0
	World.bossKills = 0
	World.runClockStart = 0
	World.runClockPaused = 0
	World.runClockEnd = 0

	-- Run start: fresh run state for the party, then the drive-in sequence (IntroSec); WAVE 1 follows.
	World.wave = 1
	Heat.reset()
	EnemyPath.resetRun()
	Spawner.resetRun()
	MapLoader.resetRun()
	Doors.resetRun()
	Windows.resetRun()
	Alarms.resetRun()
	ZoneGas.resetRun()
	Offices.resetRun()
	Hub.beginRun(World.partyPlayers())
	Economy.resetRun(World.partyPlayers())
	Mastery.beginRun(World.partyPlayers())
	Jobs.beginRun(World.partyPlayers())
	setState("Intro")
	Doors.sendState() -- brief 7: the door beacons for the party
	Log.event(
		"Run",
		"Run %d start on %s for a party of %d (%s), first wave in %.1fs",
		World.runId,
		World.map,
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
		Heat.cancelAll() -- the wave in progress is not scored
		World.runClockEnd = Workspace:GetServerTimeNow() -- the clock freezes under the stamp
		Enemy.freezeAll(Config.RunOverSlowSec)
		Log.event("Run", "Run %d over at wave %d (%.1fs to revive everybody)", World.runId, World.wave, window)
		-- Brief 6 upsell: all down and nobody can pay for REVIVE EVERYBODY: the token sheet opens for the first
		-- bled-out member (the window holds while it is up).
		do
			local cost = Downed.reviveAllCost()
			local anyone = false
			local first: Player? = nil
			for _, p in World.partyPlayers() do
				local prof = Profiles.get(p)
				if prof and prof.reviveTokens >= cost then
					anyone = true
				end
				if not first and PlayerState.get(p).bledOut then
					first = p
				end
			end
			if not anyone and first then
				Remotes.Juice:FireClient(first, "OfferTokens", { cost = cost })
				Log.event("Tokens", "run over with no tokens in the crew: token sheet offered to %s", first.Name)
			end
		end
		-- Brief 6: while a member has the purchase sheet up (GET TOKENS), the window stands still.
		local t0 = os.clock()
		local holding = false
		while World.runOver and os.clock() - t0 < window do
			local dt = task.wait(0.1)
			local held = false
			for _, p in World.partyPlayers() do
				if World.sheetOpen[p.UserId] then
					held = true
					break
				end
			end
			if held then
				t0 += dt
			end
			if held ~= holding then
				holding = held
				World.fireRun("RunOverHold", { on = held, left = math.max(0, window - (os.clock() - t0)) })
			end
		end
		if World.runOver then
			break
		end
		-- Second chance: the clock resumes, the window taken out.
		World.runClockPaused += Workspace:GetServerTimeNow() - World.runClockEnd
		World.runClockEnd = 0
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
	Log.event("Run", "%s summary closed (%s), back to the hub", World.map, result)
end

-- Back to idle: the party comes home, this slot's map is cleared, its pad reopens (or re-forms on PLAY AGAIN).
local function backToHub(first: boolean)
	local lastParty = World.partyPlayers()
	local choice = World.lastChoice
	World.lastChoice = nil
	World.wave = 1
	World.runOver = false
	World.runRequested = false
	World.pendingWave = nil
	World.skipRequested = false
	World.summaryChoice = nil
	World.roster = nil
	setState("Hub")
	Pause.reset()
	clearArena()
	Doors.resetRun()
	Alarms.resetRun()
	ZoneGas.resetRun()
	Offices.resetRun()
	if first then
		return
	end
	World.fireRun("HubEnter", {})
	-- The party is let go before the characters reload so they spawn as hub players (the hub slot).
	World.party = {}
	RunEvents.setMap(lastParty, nil)
	Queue.onRunEnded(Slot.id, choice, lastParty)
	Hub.enter(lastParty)
	-- Brief 6: back in the hub after a reset, MARLOW announces the new Jobs.
	for _, p in lastParty do
		task.delay(2.5, Jobs.announce, p)
	end
	for _, p in lastParty do
		PlayerState.markDirty(p)
	end
	Log.event("Run", "%s: idle, waiting for a party", World.map)
end

function Main.start()
	Room.build()
	-- Brief 7: THE BANK's nodes (Workspace.Bank.Nodes) become Room.forMap("TheBank"); only the bank's slot builds
	-- its props (MapLoader gates on Slot.mapId).
	MapLoader.init()

	Downed.init()
	SkipVote.init()
	Abilities.init()
	Enemy.init()
	-- The run's hooks (heat, mastery, Jobs, wildfire); the hub slot's enemies (the range) score nothing.
	if not Slot.isHub then
		Enemy.onSpawn = function(d)
			Heat.onSpawn(d.wave)
		end
	end
	Enemy.onDeath = if Slot.isHub
		then nil
		else function(d, attacker)
			Heat.onEnemyDead(d.wave)
			Mastery.onKill(d.model, attacker)
			Elements.onKill(d.model, d.root.Position) -- WILDFIRE (synergy): a Fire Ammo burn jumps to the enemies around
			-- Brief 6 Jobs: kills by archetype and elites for the killer, boss kills for the whole party.
			if attacker then
				RunEvents.emit(attacker, "kill", 1, d.row.id)
				if d.elite then
					RunEvents.emit(attacker, "elite", 1)
				end
			end
			if d.row.boss then
				for _, p in World.partyPlayers() do
					RunEvents.emit(p, "boss", 1)
				end
			end
			-- The boss's last hit: the crew hears who landed it.
			if d.row.boss and attacker then
				AllyCallout.send(attacker, "bossKill", d.row.name)
			end
		end
	Mastery.init()
	Pause.init()
	-- The pause: every party member's character is held where it stands, then let go.
	Pause.setFreezeHook(function(on: boolean)
		for _, p in World.partyPlayers() do
			local char = p.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				root.Anchored = on
			end
			local s = PlayerState.get(p)
			if not on then
				PlayerState.applyCharacterStats(s)
			end
			s.dirty = true
		end
	end)
	Dealer.init()
	Elements.init()
	Combat.init()
	UpgradeShop.init()
	WeaponRoll.init()
	BigCrate.init()
	CrewCall.init()
	Minigames.init()
	VaultJob.init()
	RunEnd.init()
	Roster.init()
	Debug.init()
	Doors.init()
	Windows.init()
	Alarms.init()
	ZoneGas.init()
	Offices.init()
	Range.init() -- brief 8: the hub slot only

	if Slot.isHub then
		return
	end
	World.map = Slot.mapId
	task.spawn(function()
		backToHub(true)
		while true do
			while not World.runRequested do
				task.wait(0.1)
			end
			World.runRequested = false
			playRun()
			backToHub(false)
		end
	end)
end

return Main
