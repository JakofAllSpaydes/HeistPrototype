--!strict
-- Run and wave state shared by every server module. GameLoop writes, everyone else reads.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local World = {
	heat = Config.HeatStart, -- stars, 0..5
	wave = 1,
	-- Staging (yard, nothing hostile) | Intro | Wave | Intermission | RunOver | RunEnd | Summary
	state = "Staging",
	runId = 0, -- counts runs since the server started
	runRequested = false, -- START RUN pressed (or debug): leave Staging
	runOver = false, -- game over (or debug): the wave loop winds down and the run end plays
	summaryChoice = nil :: string?, -- "again" | "lobby": a summary button was pressed
	intermissionEndsAt = 0, -- server time (workspace:GetServerTimeNow())
	pendingWave = nil :: number?, -- set by debug: next loop iteration jumps here
	skipRequested = false, -- set by debug: end the current wave / intermission now
	spawnsPaused = false,
	enemiesLeft = 0, -- unspawned budget + alive, kept current by Spawner during a wave
	waveStartedAt = 0, -- server time the current wave started
	skipVotes = {} :: { [number]: boolean }, -- userId -> voted to skip this intermission
	autoSkip = {} :: { [number]: boolean }, -- userId -> votes automatically every intermission
	minigameTier = Config.MinigameTier, -- 1..3, set by the tier pad in the yard or the debug panel
}

-- True while a run is on: waves can spawn, downs count, cash is Match Cash.
function World.inRun(): boolean
	return World.state == "Intro" or World.state == "Wave" or World.state == "Intermission"
end

function World.skipNeeded(): number
	return math.max(1, math.ceil(#Players:GetPlayers() * Config.SkipVoteFraction))
end

function World.skipVoteCount(): number
	local n = 0
	for _, p in Players:GetPlayers() do
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
	for _, p in Players:GetPlayers() do
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
	Remotes.Juice:FireAllClients("HeatChanged", { delta = World.heat - before, value = World.heat, reason = reason })
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

return World
