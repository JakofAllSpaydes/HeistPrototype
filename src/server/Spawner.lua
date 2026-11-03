--!strict
-- Wave budget -> enemy drip. Opening surge, cap with backfill, ends when budget is spent and none alive.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Enemy = require(script.Parent.Enemy)
local Room = require(script.Parent.Room)
local World = require(script.Parent.World)

local Spawner = {}

function Spawner.budgetFor(wave: number): number
	return Config.WaveBudgetBase + Config.WaveBudgetPerWave * (wave - 1)
end

-- Blocks until the wave is over (budget spent and no enemies alive) or a skip is requested.
function Spawner.runWave(wave: number)
	local budget = Spawner.budgetFor(wave)
	local remaining = budget
	local surge = math.floor(budget * Config.OpeningSurgePct / 100)
	local spawned = 0

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
		local interval = if spawned <= surge then Config.SpawnInterval * Config.OpeningSurgeIntervalMult else Config.SpawnInterval
		task.wait(interval)
	end

	while Enemy.count() > 0 and not World.skipRequested do
		task.wait(0.2)
	end
	if World.skipRequested then
		Enemy.killAll()
	end
end

return Spawner
