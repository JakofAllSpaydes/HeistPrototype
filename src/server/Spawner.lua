--!strict
-- Wave budget -> enemy drip. Each spawn rolls its archetype from the wave's composition bracket (shifted by
-- heat) and its marker by proximity to the crew (NearRange x NearWeightMult, FarRange x1, beyond x
-- FarWeightMult), with the opening surge, the MaxActiveEnemies cap (the rest queues and backfills at once)
-- and the elite roll. Keeps World.enemiesLeft (unspawned + alive) current so the HUD can show "N LEFT".
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Enemies = require(Shared.Enemies)
local Enemy = require(script.Parent.Enemy)
local Room = require(script.Parent.Room)
local World = require(script.Parent.World)
local PlayerState = require(script.Parent.PlayerState)
local Log = require(script.Parent.Log)

local Spawner = {}

function Spawner.budgetFor(wave: number): number
	local budget = Config.WaveBudgetBase + Config.WaveBudgetPerWave * (wave - 1)
	if World.isBossWave(wave) then
		budget = math.max(1, math.floor(budget * Config.BossWaveBudgetPct))
	end
	return budget
end

local function publishLeft(n: number)
	if World.enemiesLeft ~= n then
		World.enemiesLeft = n
		PlayerState.markAllDirty()
	end
end

-- Distance from a marker to the nearest standing player (huge when nobody stands).
local function nearestPlayerDistance(point: Vector3): number
	local best = math.huge
	for _, player in World.runAudience() do
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local state = PlayerState.get(player)
		if root and PlayerState.isStanding(state) then
			best = math.min(best, (root.Position - point).Magnitude)
		end
	end
	return best
end

-- A marker weighted by how close the crew is: enemies mostly arrive from where the action is.
function Spawner.pickMarker(): Vector3
	local points = Room.spawnPoints
	if #points == 0 then
		return Room.randomSpawnPoint()
	end
	local weights = {}
	local total = 0
	for i, p in points do
		local d = nearestPlayerDistance(p)
		local w = if d <= Config.NearRange
			then Config.NearWeightMult
			elseif d <= Config.FarRange then 1
			else Config.FarWeightMult
		weights[i] = w
		total += w
	end
	local r = math.random() * total
	for i, w in weights do
		r -= w
		if r <= 0 then
			return points[i]
		end
	end
	return points[#points]
end

-- Elite roll for a spawn: HeatElitePerStar x max(0, stars - 1).
function Spawner.rollElite(): boolean
	return math.random() < World.eliteChance()
end

-- One enemy of the wave: archetype from the bracket, marker by proximity, elite by heat.
function Spawner.spawnOne(wave: number, archetype: string?): Model
	local id = archetype or Enemies.rollArchetype(wave, World.bracketShift())
	return Enemy.spawn(id, wave, Spawner.pickMarker(), { elite = Spawner.rollElite() })
end

-- Blocks until the wave is over (budget spent and no enemies alive) or a skip is requested.
-- Returns true when AUTO SKIP rolled the wave early: the budget is spent, AutoSkipWaveSec has passed,
-- and whatever is still alive carries into the next wave.
function Spawner.runWave(wave: number): boolean
	local budget = Spawner.budgetFor(wave)
	local remaining = budget
	local surge = math.floor(budget * Config.OpeningSurgePct / 100)
	local spawned = 0
	local startedAt = os.clock()
	local tally: { [string]: number } = {}
	local elites = 0
	publishLeft(budget + Enemy.count())

	while remaining > 0 and not World.skipRequested and not World.runOver do
		if World.spawnsPaused then
			task.wait(0.25)
			continue
		end
		if Enemy.count() < Config.MaxActiveEnemies then
			local model = Spawner.spawnOne(wave)
			local id = tostring(model:GetAttribute("Archetype"))
			tally[id] = (tally[id] or 0) + 1
			if model:GetAttribute("Elite") == true then
				elites += 1
			end
			remaining -= 1
			spawned += 1
		else
			-- At the cap: the rest of the budget queues and backfills the moment something dies.
			publishLeft(remaining + Enemy.count())
			task.wait(0.1)
			continue
		end
		publishLeft(remaining + Enemy.count())
		local interval = if spawned <= surge
			then Config.SpawnInterval * Config.OpeningSurgeIntervalMult
			else Config.SpawnInterval
		task.wait(interval * World.spawnIntervalMult())
	end
	local parts = {}
	for _, row in Enemies.List do
		if tally[row.id] then
			table.insert(parts, string.format("%d %s", tally[row.id], row.id))
		end
	end
	Log.event(
		"Wave",
		"Wave %d composition (bracket %d): %s%s",
		wave,
		Enemies.bracketIndex(wave, World.bracketShift()),
		table.concat(parts, ", "),
		if elites > 0 then string.format(", %d elite", elites) else ""
	)

	while Enemy.count() > 0 and not World.skipRequested and not World.runOver do
		publishLeft(Enemy.count())
		if World.autoSkipActive() and os.clock() - startedAt >= Config.AutoSkipWaveSec then
			return true
		end
		task.wait(0.2)
	end
	-- Game over leaves the enemies to the run-over beat (freeze and fade); a debug skip just clears them.
	if World.skipRequested and not World.runOver then
		Enemy.killAll()
	end
	publishLeft(0)
	return false
end

return Spawner
