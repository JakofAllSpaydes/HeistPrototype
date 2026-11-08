--!strict
-- Wave budget -> enemy drip. Each spawn rolls its archetype from the wave's composition bracket (shifted by
-- heat) and its marker by proximity to the crew (NearRange x NearWeightMult, FarRange x1, beyond x
-- FarWeightMult), with the opening surge, the MaxActiveEnemies cap (the rest queues and backfills at once)
-- and the elite roll. Keeps World.enemiesLeft (unspawned + alive) current so the HUD can show "N LEFT".
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Enemies = require(Shared.Enemies)
local Enemy = require(script.Parent.Enemy)
local EnemyPath = require(script.Parent.EnemyPath)
local Room = require(script.Parent.Room)
local World = require(script.Parent.World)
local PlayerState = require(script.Parent.Parent.PlayerState)
local Log = require(script.Parent.Parent.Log)
local Heat = require(script.Parent.Heat)
local Pause = require(script.Parent.Pause)
local Ground = require(Shared.Ground)

local Spawner = {}

-- The regular budget (heat's par is computed on it); boss waves spawn BossWaveBudgetPct of it alongside the boss.
-- The difficulty's budgetMult scales it (Round 16).
function Spawner.regularBudget(wave: number): number
	local base = Config.WaveBudgetBase + Config.WaveBudgetPerWave * (wave - 1)
	return math.max(1, math.round(base * (Enemies.difficulty(World.partySettings.difficultyId).budgetMult or 1)))
end

function Spawner.budgetFor(wave: number): number
	local budget = Spawner.regularBudget(wave)
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

-- The proximity multiplier for a box: NearRange x NearWeightMult, FarRange x1, beyond x FarWeightMult.
local function proximity(point: Vector3): number
	local d = nearestPlayerDistance(point)
	return if d <= Config.NearRange
		then Config.NearWeightMult
		elseif d <= Config.FarRange then 1
		else Config.FarWeightMult
end

-- Brief 7: the door system installs this on THE BANK (a box behind a closed door, or in the closed vault,
-- never draws). nil: every box is open (the arena).
Spawner.boxOpen = nil :: ((any) -> boolean)?
-- MapLoader installs this on THE BANK: hops from the crew zone to every zone along the open graph.
Spawner.zoneHops = nil :: (() -> { [string]: number }?)?

-- Per wave: spawns per box (the elite least-used rule) and contact times per box (the [GHS Spawn] log).
local boxSpawns: { [string]: number } = {}
local contacts: { [string]: { number } } = {}
local warned = false
local warnedBoxes: { [string]: boolean } = {}

-- Standing in the crew's zone (the zone volume holding the box's centre, not its Zone attribute: a box behind a
-- fence or a window stands outside every zone and feeds its zone even while the crew holds it).
local function inCrewZone(box: any): boolean
	return Config.SpawnNeverInCrewZone and box.standsIn ~= nil and box.standsIn == World.crewZone
end

-- The eligible boxes for an archetype: open, allowing it, not standing in the crew zone. None: every open box
-- (logged once per wave).
local function eligible(archetype: string?): { any }
	local all = Room.current().spawnBoxes
	local open = Spawner.boxOpen
	local out, openBoxes = {}, {}
	for _, box in all do
		if open and not open(box) then
			continue
		end
		table.insert(openBoxes, box)
		if archetype and box.allowed and not box.allowed[archetype] then
			continue
		end
		if inCrewZone(box) then
			continue
		end
		table.insert(out, box)
	end
	if #out == 0 and #openBoxes > 0 then
		if not warned then
			warned = true
			Log.event("Spawn", "WARN no eligible box wave %d", World.wave)
		end
		return openBoxes
	end
	return out
end

-- A spawn box weighted by how close the crew is: enemies mostly arrive from where the action is. Brief 7:
-- x ZoneDistanceMult ^ (zone hops from the crew zone along the open graph); an elite takes the eligible box with
-- the fewest spawns this wave (EliteLeastUsedBox).
function Spawner.pickBox(archetype: string?, elite: boolean?): Room.SpawnBox?
	local boxes = eligible(archetype)
	if #boxes == 0 then
		return nil
	end
	if elite and Config.EliteLeastUsedBox then
		local best, bestN = nil, math.huge
		for _, box in boxes do
			local n = boxSpawns[box.name] or 0
			if n < bestN then
				best, bestN = box, n
			end
		end
		return best
	end
	local hopsOf = Spawner.zoneHops
	local hops = if hopsOf then hopsOf() else nil
	local weights = {}
	local total = 0
	for i, box in boxes do
		local w = box.weight * proximity(box.cframe.Position)
		if hops then
			w *= Config.ZoneDistanceMult ^ (hops[box.zone] or 8)
		end
		weights[i] = w
		total += w
	end
	local r = math.random() * total
	for i, w in weights do
		r -= w
		if r <= 0 then
			return boxes[i]
		end
	end
	return boxes[#boxes]
end

-- Elite roll for a spawn: HeatElitePerStar x max(0, stars - 1).
function Spawner.rollElite(): boolean
	return math.random() < World.eliteChance()
end

-- A spawn point in plain sight of a standing player and closer than SpawnLosBuffer re-rolls once: nobody pops
-- in front of anyone.
local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Include
local function inPlainSight(point: Vector3): boolean
	losParams.FilterDescendantsInstances = (Ground.params() :: any).FilterDescendantsInstances
	for _, player in World.runAudience() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and PlayerState.isStanding(PlayerState.get(player)) then
			local eye = root.Position + Vector3.new(0, 1.5, 0)
			local to = point + Vector3.new(0, 3, 0)
			if (to - eye).Magnitude < Config.SpawnLosBuffer and Workspace:Raycast(eye, to - eye, losParams) == nil then
				return true
			end
		end
	end
	return false
end

-- Round 25: MapLoader installs its zone lookup (it requires this module, so no require back). nil on the arena.
Spawner.zoneAt = nil :: ((Vector3) -> string?)?

-- Round 25: a spawn point that is really inside its box's room. Re-rolls (up to 8) a point whose floor fell
-- through to a lower level (outside the box's height), that stands in another zone or none (the outer ledge of
-- THE BANK's upper floor, the street side of a wall), or that sits inside solid geometry. Last resort: the box's
-- centre on its floor.
local function pointFor(box: any): Vector3
	local want = box.standsIn or box.zone
	local bottom = box.cframe.Position.Y - box.size.Y / 2
	local top = box.cframe.Position.Y + box.size.Y / 2
	local zoneAt = Spawner.zoneAt
	for _ = 1, 8 do
		local p = Room.pointInBox(box)
		local ok = p.Y >= bottom - 1.5 and p.Y <= top + 1.5
		if ok and zoneAt and want then
			ok = zoneAt(p + Vector3.new(0, 2.5, 0)) == want
		end
		if ok then
			ok = Ground.isClear(p, 1, 4)
		end
		if ok then
			return p
		end
	end
	if not warnedBoxes[box.name] then
		warnedBoxes[box.name] = true
		Log.event(
			"Spawn",
			"WARN box %s: no clean point in 8 tries, using its centre (drag it inside the room?)",
			box.name
		)
	end
	local c = box.cframe.Position
	return Vector3.new(c.X, Ground.y(c + Vector3.new(0, box.size.Y / 2, 0), bottom), c.Z)
end

-- Round 21: where a stranded straggler warps (EnemyPath): an eligible box picked like a spawn (weighted toward the
-- crew, never in its zone), at a point nobody sees and no closer than CatchUpMinPlayerDistance to anyone.
EnemyPath.relocate = function(): Vector3?
	for _ = 1, 6 do
		local box = Spawner.pickBox(nil)
		if not box then
			return nil
		end
		local p = pointFor(box)
		if not inPlainSight(p) and nearestPlayerDistance(p) >= Config.CatchUpMinPlayerDistance then
			return p
		end
	end
	return nil
end

-- One enemy of the wave: archetype from the bracket, box by proximity (and zone hops), elite by heat.
function Spawner.spawnOne(wave: number, archetype: string?): Model
	local id = archetype or Enemies.rollArchetype(wave, World.bracketShift())
	local elite = Spawner.rollElite()
	local box = Spawner.pickBox(id, elite)
	local at = if box then pointFor(box) else Room.randomSpawnPoint()
	if box and inPlainSight(at) then
		at = pointFor(box)
	end
	local model = Enemy.spawn(id, wave, at, { elite = elite, box = box })
	if box then
		boxSpawns[box.name] = (boxSpawns[box.name] or 0) + 1
		local d = Enemy.data(model)
		if d then
			d.mem.spawnedAt = os.clock()
		end
	end
	return model
end

-- An enemy's first hit on a player: the contact time for its box this wave.
local function onContact(d: any)
	if d.mem.contacted or not d.box or not d.mem.spawnedAt then
		return
	end
	d.mem.contacted = true
	local list = contacts[d.box.name] or {}
	contacts[d.box.name] = list
	table.insert(list, os.clock() - d.mem.spawnedAt)
end
Enemy.onContact = onContact

-- Run-long contact averages per box (debug Stats MAP block).
Spawner.contactRun = {} :: { [string]: { sum: number, n: number } }

local function logContacts(wave: number)
	local names = {}
	for name in contacts do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		local list = contacts[name]
		local sum = 0
		for _, t in list do
			sum += t
		end
		local avg = sum / math.max(#list, 1)
		Log.event("Spawn", "wave %d box %s contact %.1f (%d of %d)", wave, name, avg, #list, boxSpawns[name] or 0)
		local r = Spawner.contactRun[name] or { sum = 0, n = 0 }
		r.sum += sum
		r.n += #list
		Spawner.contactRun[name] = r
	end
	contacts = {}
	boxSpawns = {}
	warned = false
end

function Spawner.resetRun()
	contacts = {}
	boxSpawns = {}
	warned = false
	Spawner.contactRun = {}
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
		if Pause.active() then
			startedAt += Pause.hold() -- no spawns while paused, and the AUTO SKIP clock waits too
			continue
		end
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
	if remaining <= 0 then
		Heat.waveSpawned(wave) -- the budget is spent: the wave clears with its last tagged death
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
		if Pause.active() then
			startedAt += Pause.hold()
		end
		publishLeft(Enemy.count())
		if World.autoSkipActive() then
			Heat.onAutoSkip(wave)
			if os.clock() - startedAt >= Config.AutoSkipWaveSec then
				logContacts(wave)
				return true
			end
		end
		task.wait(0.2)
	end
	-- Game over leaves the enemies to the run-over beat (freeze and fade); a debug skip just clears them,
	-- unscored.
	if World.skipRequested and not World.runOver then
		Heat.cancelAll()
		Enemy.killAll()
	end
	publishLeft(0)
	logContacts(wave)
	return false
end

return Spawner
