--!strict
-- Run and wave state shared by every server module. GameLoop writes, everyone else reads. The party
-- (the player set of the current or forming run) lives here too: run-scoped events go to its members.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

export type PartySettings = { partySize: number, mapId: string, difficultyId: string }

local World = {
	heat = Config.HeatStart, -- stars, 0..5
	wave = 1,
	-- Hub (the yard, nothing hostile) | Intro | Wave | Intermission | RunOver | RunEnd | Summary
	state = "Hub",
	runId = 0, -- counts runs since the server started
	runRequested = false, -- the queue started a run (or debug): leave the hub
	runOver = false, -- game over (or debug): the wave loop winds down and the run end plays
	summaryChoice = nil :: string?, -- "again" | "lobby": a summary button was pressed
	lastChoice = nil :: string?, -- how the last summary closed; "again" re-forms the party in the queue zone
	intermissionEndsAt = 0, -- server time (workspace:GetServerTimeNow())
	pendingWave = nil :: number?, -- set by debug: next loop iteration jumps here
	skipRequested = false, -- set by debug: end the current wave / intermission now
	spawnsPaused = false,
	enemiesLeft = 0, -- unspawned budget + alive, kept current by Spawner during a wave
	waveStartedAt = 0, -- server time the current wave started
	skipVotes = {} :: { [number]: boolean }, -- userId -> voted to skip this intermission
	autoSkip = {} :: { [number]: boolean }, -- userId -> votes automatically every intermission
	minigameTier = Config.MinigameTier, -- 1..3, set by the tier pad in the yard or the debug panel
	-- The party: userIds in join order. Set by Queue when a run starts (or re-forms), cleared back in the hub.
	party = {} :: { number },
	partySettings = { partySize = 1, mapId = "TheBank", difficultyId = "Normal" } :: PartySettings,
	-- Payout accumulators for the run (GDD_7 payout). Survive REVIVE EVERYBODY saves; paid once at the summary.
	runGold = 0, -- sum over cleared waves of GoldPerWaveBase + GoldPerWaveAdd x (wave - 1)
	objectivesDone = 0, -- side jobs completed this run
	banked = 0, -- the team's Banked total from gold bags (TOTAL BANKED, paid in full to every member at the summary)
	-- The live boss for the HUD bar (Boss.lua writes it, StateSync carries it): { id, name, hp, maxHP, phase } or nil.
	bossView = nil :: { id: string, name: string, hp: number, maxHP: number, phase: number }?,
	-- The run clock: from the WAVE 1 banner, paused during the boss cutscene and the run-over window, frozen
	-- once the run ends (TIME SURVIVED on the scoreboard and the summary, XpSurvivedPerMin).
	runClockStart = 0, -- server time, 0 = not started
	runClockPaused = 0, -- seconds taken out (cutscenes, the run-over window)
	runClockEnd = 0, -- server time the clock froze, 0 = running
	wavesCleared = 0, -- waves cleared this run (XP)
	bossKills = 0, -- bosses killed this run (XP, credited to every member)
}

function World.survivedSec(): number
	if World.runClockStart <= 0 then
		return 0
	end
	local now = if World.runClockEnd > 0 then World.runClockEnd else Workspace:GetServerTimeNow()
	return math.max(0, now - World.runClockStart - World.runClockPaused)
end

-- True while a run is on: waves can spawn, downs count, cash is Match Cash.
function World.inRun(): boolean
	return World.state == "Intro" or World.state == "Wave" or World.state == "Intermission"
end

-- Anything but the hub: a party is in the arena (run, run over, run end or summary).
function World.inRunCycle(): boolean
	return World.state ~= "Hub"
end

function World.isInParty(player: Player): boolean
	return table.find(World.party, player.UserId) ~= nil
end

-- Party members still on the server, in party order.
function World.partyPlayers(): { Player }
	local out = {}
	for _, userId in World.party do
		local p = Players:GetPlayerByUserId(userId)
		if p then
			table.insert(out, p)
		end
	end
	return out
end

-- Players who should receive run-scoped events: the party during a run cycle, everyone otherwise.
function World.runAudience(): { Player }
	if World.inRunCycle() and #World.party > 0 then
		return World.partyPlayers()
	end
	return Players:GetPlayers()
end

-- Juice for the run's players only; the hub never sees wave banners, crates or crew calls.
function World.fireRun(name: string, data: any)
	for _, p in World.runAudience() do
		Remotes.Juice:FireClient(p, name, data)
	end
end

function World.partyKey(): string
	return World.partySettings.mapId .. ":" .. World.partySettings.difficultyId
end

function World.skipNeeded(): number
	return math.max(1, math.ceil(#World.runAudience() * Config.SkipVoteFraction))
end

function World.skipVoteCount(): number
	local n = 0
	for _, p in World.runAudience() do
		if World.skipVotes[p.UserId] or World.autoSkip[p.UserId] then
			n += 1
		end
	end
	return n
end

function World.skipVotePassed(): boolean
	return World.state == "Intermission" and World.skipVoteCount() >= World.skipNeeded()
end

-- Enough players have AUTO SKIP on for waves to roll into each other.
function World.autoSkipActive(): boolean
	local n = 0
	for _, p in World.runAudience() do
		if World.autoSkip[p.UserId] then
			n += 1
		end
	end
	return n > 0 and n >= World.skipNeeded()
end

-- Heat moves in half-star steps. Everyone sees the change; PlayerState resends on the next flush.
World.heatDirty = false
function World.addHeat(delta: number, reason: string)
	if delta == 0 then
		return
	end
	local before = World.heat
	World.heat = math.clamp(math.round((before + delta) * 2) / 2, 0, 5)
	if World.heat == before then
		return
	end
	World.heatDirty = true
	World.fireRun("HeatChanged", { delta = World.heat - before, value = World.heat, reason = reason })
	print(
		string.format(
			"[GHS Heat] %s: %.1f -> %.1f (%s)",
			reason,
			before,
			World.heat,
			if delta > 0 then "up" else "down"
		)
	)
end

-- Heat effects at S stars (GDD_7 pace meter): cash, elite chance, spawn pace and the composition shift.
function World.cashMult(): number
	return 1 + Config.HeatCashPerStar * World.heat
end

function World.eliteChance(): number
	return Config.HeatElitePerStar * math.max(0, World.heat - 1)
end

function World.spawnIntervalMult(): number
	return math.max(0.2, 1 - Config.HeatSpawnPerStar * World.heat)
end

function World.bracketShift(): number
	return if World.heat >= Config.HeatShiftStars then Config.HeatBracketShift else 0
end

-- Boss waves: the first at BossWaveInterval and every multiple after.
function World.isBossWave(wave: number): boolean
	return Config.BossWaveInterval > 0 and wave > 0 and wave % Config.BossWaveInterval == 0
end

-- Payout accumulators.
function World.addWaveGold(wave: number)
	World.runGold += Config.GoldPerWaveBase + Config.GoldPerWaveAdd * math.max(0, wave - 1)
	World.wavesCleared += 1
end

function World.addObjective()
	World.objectivesDone += 1
end

-- GoldEarned for the run (before per-player side job Gold): the GDD_7 formula.
function World.payoutBase(): number
	return math.floor((World.runGold + Config.GoldPerObjective * World.objectivesDone) * Config.DiffGoldMult)
end

return World
