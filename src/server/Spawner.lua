--!strict
-- Wave budget -> enemy drip. Opening surge, cap with backfill, ends when budget is spent and none alive.
-- Keeps World.enemiesLeft (unspawned + alive) current so the HUD can show "N LEFT".
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Enemy = require(script.Parent.Enemy)
local Room = require(script.Parent.Room)
local World = require(script.Parent.World)
local PlayerState = require(script.Parent.PlayerState)

local Spawner = {}

function Spawner.budgetFor(wave: number): number
	return Config.WaveBudgetBase + Config.WaveBudgetPerWave * (wave - 1)
end

local function publishLeft(n: number)
	if World.enemiesLeft ~= n then
		World.enemiesLeft = n
		PlayerState.markAllDirty()
	end
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
	publishLeft(budget + Enemy.count())

	while remaining > 0 and not World.skipRequested do
		if World.spawnsPaused then
			task.wait(0.25)
			continue
		end
		if Enemy.count() < Config.MaxActiveEnemies then
			Enemy.spawn(wave, Room.randomSpawnPoint())
			remaining -= 1
			spawned += 1
		end
		publishLeft(remaining + Enemy.count())
		local interval = if spawned <= surge
			then Config.SpawnInterval * Config.OpeningSurgeIntervalMult
			else Config.SpawnInterval
		task.wait(interval)
	end

	while Enemy.count() > 0 and not World.skipRequested do
		publishLeft(Enemy.count())
		if World.autoSkipActive() and os.clock() - startedAt >= Config.AutoSkipWaveSec then
			return true
		end
		task.wait(0.2)
	end
	if World.skipRequested then
		Enemy.killAll()
	end
	publishLeft(0)
	return false
end

return Spawner
