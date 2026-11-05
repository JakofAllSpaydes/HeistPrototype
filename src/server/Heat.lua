--!strict
-- Heat as pace (GDD_7). A team meter, 0-5 in half stars, that starts at HeatStart and never decays; every
-- wave is scored once its last tagged enemy dies: clear time against a par (ParTimeBase + ParTimePerEnemy x
-- budget, plus BossParBonusSec on boss waves), AUTO SKIP during the wave, side jobs done or failed in it,
-- downs in it (capped), and a boss kill on top. Each component lands as its own +0.5 / -0.5 float with its
-- reason on every HUD. The effects of the stars (cash, elites, spawn pace, the bracket shift) live in World.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local World = require(script.Parent.World)
local Log = require(script.Parent.Log)
local Enemy = require(script.Parent.Enemy)
local Pause = require(script.Parent.Pause)

type Record = {
	wave: number,
	startedAt: number, -- os.clock at the WAVE N banner
	par: number,
	budget: number,
	spawned: number, -- enemies tagged with this wave so far
	dead: number,
	spawnedAll: boolean, -- the Spawner spent the budget
	downs: number,
	jobs: number,
	jobFails: number,
	autoSkip: boolean,
	boss: boolean,
	evaluated: boolean,
	clearSec: number?,
}

local Heat = {}

local records: { [number]: Record } = {}

-- A pause never counts against par: every open wave's clock start moves forward with it.
Pause.onTick(function(dt)
	for _, r in records do
		if not r.evaluated then
			r.startedAt += dt
		end
	end
end)
local history: { Record } = {} -- evaluated this run, for the Stats print

function Heat.reset()
	records = {}
	history = {}
	World.heat = math.clamp(Config.HeatStart, 0, 5)
	World.heatDirty = true
end

function Heat.parFor(wave: number, budget: number): number
	local par = Config.ParTimeBase + Config.ParTimePerEnemy * budget
	if World.isBossWave(wave) then
		par += Config.BossParBonusSec
	end
	return par
end

-- The WAVE N banner: the clock starts. A second chance restarts the same wave from scratch. `budget` is
-- the regular budget (par is computed on it even on boss waves); anything already tagged with the wave
-- (the boss, which steps in during the cutscene) counts as spawned.
function Heat.waveStarted(wave: number, budget: number)
	records[wave] = {
		wave = wave,
		startedAt = os.clock(),
		par = Heat.parFor(wave, budget),
		budget = budget,
		spawned = Enemy.countForWave(wave),
		dead = 0,
		spawnedAll = false,
		downs = 0,
		jobs = 0,
		jobFails = 0,
		autoSkip = false,
		boss = World.isBossWave(wave),
		evaluated = false,
	}
end

local function current(): Record?
	return records[World.wave]
end

-- Every component lands as its own float, a beat apart, so each reason reads.
local function apply(parts: { { delta: number, reason: string } })
	task.spawn(function()
		for i, part in parts do
			if part.delta ~= 0 then
				World.addHeat(part.delta, part.reason)
				if i < #parts then
					task.wait(0.45)
				end
			end
		end
	end)
end

local function evaluate(r: Record)
	if r.evaluated then
		return
	end
	r.evaluated = true
	records[r.wave] = nil
	local clear = os.clock() - r.startedAt
	r.clearSec = clear
	table.insert(history, r)
	local parts = {}
	local verdict: string
	if clear <= Config.FastClearPct * r.par then
		verdict = "fast"
		table.insert(parts, { delta = Config.HeatFastClear, reason = "FAST CLEAR" })
	elseif clear <= r.par then
		verdict = "par"
		table.insert(parts, { delta = Config.HeatParClear, reason = "PAR" })
	elseif clear > Config.SlowClearMult * r.par then
		verdict = "slow"
		table.insert(parts, { delta = Config.HeatSlowClear, reason = "SLOW" })
	else
		verdict = "over par"
	end
	if r.autoSkip then
		table.insert(parts, { delta = Config.HeatAutoSkip, reason = "AUTO SKIP" })
	end
	for _ = 1, r.jobs do
		table.insert(parts, { delta = Config.HeatJob, reason = "JOB" })
	end
	for _ = 1, r.jobFails do
		table.insert(parts, { delta = Config.HeatJobFail, reason = "JOB FAILED" })
	end
	if r.downs > 0 then
		local penalty = math.max(Config.HeatDownedMax, Config.HeatDowned * r.downs)
		table.insert(parts, { delta = penalty, reason = if r.downs > 1 then "DOWNS" else "DOWNED" })
	end
	local total = 0
	for _, p in parts do
		total += p.delta
	end
	local before = World.heat
	local after = math.clamp(math.round((before + total) * 2) / 2, 0, 5)
	print(
		string.format(
			"[GHS Heat] wave %d clear %.1fs par %.1fs heat %s%.1f → %.1f (%s%s%s%s)",
			r.wave,
			clear,
			r.par,
			if total >= 0 then "+" else "",
			total,
			after,
			verdict,
			if r.autoSkip then ", auto skip" else "",
			if r.jobs > 0 or r.jobFails > 0
				then string.format(
					", %d job%s",
					r.jobs,
					if r.jobFails > 0 then string.format(" / %d failed", r.jobFails) else ""
				)
				else "",
			if r.downs > 0 then string.format(", %d down", r.downs) else ""
		)
	)
	apply(parts)
end

-- Spawner: an enemy of `wave` entered; the budget is spent; a wave was skipped by debug.
function Heat.onSpawn(wave: number)
	local r = records[wave]
	if r then
		r.spawned += 1
	end
end

function Heat.waveSpawned(wave: number)
	local r = records[wave]
	if not r then
		return
	end
	r.spawnedAll = true
	if r.spawned > 0 and r.dead >= r.spawned then
		evaluate(r)
	end
end

function Heat.onEnemyDead(wave: number)
	local r = records[wave]
	if not r then
		return
	end
	r.dead += 1
	if r.spawnedAll and r.dead >= r.spawned then
		evaluate(r)
	end
end

function Heat.onAutoSkip(wave: number)
	local r = records[wave]
	if r then
		r.autoSkip = true
	end
end

-- Side jobs and downs count against the wave they happen in; the float lands at that wave's end.
function Heat.onJobDone()
	local r = current()
	if r then
		r.jobs += 1
	end
end

function Heat.onJobFailed()
	local r = current()
	if r then
		r.jobFails += 1
	end
end

function Heat.onDowned()
	local r = current()
	if r then
		r.downs += 1
	end
end

-- A boss kill lands at once, on top of the wave's own score.
function Heat.onBossKilled()
	World.addHeat(Config.HeatBossKill, "BOSS")
end

-- Debug skip, run over, hub: open waves are dropped unscored.
function Heat.cancelAll()
	records = {}
end

function Heat.set(value: number)
	local before = World.heat
	World.heat = math.clamp(math.round(value * 2) / 2, 0, 5)
	World.heatDirty = true
	World.fireRun("HeatChanged", { delta = World.heat - before, value = World.heat, reason = "DEBUG" })
end

-- The run's clear / par ratios so ParTimePerEnemy can be set from real runs (debug Stats button).
function Heat.printStats()
	print("[GHS Heat] clear / par this run:")
	if #history == 0 then
		print("  (no waves scored yet)")
		return
	end
	local sum = 0
	for _, r in history do
		local ratio = (r.clearSec or 0) / math.max(r.par, 0.1)
		sum += ratio
		print(
			string.format(
				"  wave %2d  budget %3d  clear %6.1fs  par %6.1fs  ratio %.2f%s",
				r.wave,
				r.budget,
				r.clearSec or 0,
				r.par,
				ratio,
				if r.boss then "  (boss)" else ""
			)
		)
	end
	print(string.format("  mean ratio %.2f over %d waves (1.00 = on par)", sum / #history, #history))
end

return Heat
