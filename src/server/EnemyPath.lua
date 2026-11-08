--!strict
-- Enemy navigation (brief 7). Two modes per enemy, chosen every steer:
--   direct  the target is within DirectRange and a ray from the enemy's feet to the target's feet is clear:
--           today's straight MoveTo, no path (the arena is almost always this).
--   path    PathfindingService: ComputeAsync from the enemy to the target, waypoints followed with MoveTo,
--           re-planned when the target moves RepathDistance from where the path was planned or every RepathSec.
--           Jump waypoints jump; a `ladder` link waypoint lifts the enemy along the ladder over LadderClimbSec.
-- Computes are budgeted (PathComputesPerSec across all enemies, oldest request first; an enemy without a
-- compute keeps its last path) and shared: a path is cached per (target zone, enemy zone) for PathCacheSec and a
-- crowd picks it up from its nearest waypoint. Three failed computes in a row walk direct for PathFailDirectSec.
-- Stuck (no progress toward the next waypoint for StuckSec) sidesteps; still stuck at StuckTeleportSec teleports
-- to a random point in the enemy's own spawn box. Placeables carry a `Structure` PathfindingModifier
-- (PathStructureCost): enemies route round a barricade when a route exists and go through (hit it) when not.
-- `[GHS Path]` prints the wave's computes per second, failure rate, stucks and teleports.
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Ground = require(Shared.Ground)
local Log = require(script.Parent.Log)
local Room = require(script.Parent.Room)

local EnemyPath = {}

-- Installed by MapLoader: the zone of a point on the current map (nil on the arena: everything is "arena").
EnemyPath.zoneAt = nil :: ((Vector3) -> string?)?
-- Installed by Abilities through Enemy: the placeables (hitbox parts) that get the Structure modifier.
EnemyPath.structures = nil :: (() -> { BasePart })?

export type State = {
	waypoints: { PathWaypoint }?,
	index: number,
	plannedTo: Vector3,
	plannedAt: number,
	pending: boolean,
	requestedAt: number,
	fails: number,
	directUntil: number,
	climbing: boolean,
	-- stuck clock
	lastCheck: number,
	lastDist: number,
	lastPos: Vector3,
	stuckFor: number,
	detourUntil: number,
	mode: string, -- direct | path
	modeAt: number, -- the direct check (a raycast) runs at most every 0.2 s
}

local stats = { computes = 0, fails = 0, stuck = 0, teleports = 0, startedAt = os.clock(), pinned = 0 }
local tokens = Config.PathComputesPerSec
local queue: { { d: any, from: Vector3, to: Vector3, key: string } } = {}
local cache: { [string]: { waypoints: { PathWaypoint }, at: number, to: Vector3 } } = {}

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

local function agentFor(archetype: string): any
	local agents = Config.PathAgent :: any
	local a = agents[string.lower(archetype)] or agents.default or { r = 2, h = 5 }
	return a
end

local function zoneOf(p: Vector3): string
	local f = EnemyPath.zoneAt
	return (f and f(p)) or "arena"
end

local function flatDist(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

function EnemyPath.new(): State
	local now = os.clock()
	return {
		waypoints = nil,
		index = 1,
		plannedTo = Vector3.zero,
		plannedAt = -math.huge,
		pending = false,
		requestedAt = 0,
		fails = 0,
		directUntil = 0,
		climbing = false,
		lastCheck = now,
		lastDist = math.huge,
		lastPos = Vector3.zero,
		stuckFor = 0,
		detourUntil = 0,
		mode = "direct",
		modeAt = -math.huge,
	}
end

-- Feet to feet, map geometry only (placeables are hit through, not walked round, in direct mode as today).
local function clearWalk(from: Vector3, to: Vector3): boolean
	if math.abs(from.Y - to.Y) > 6 then
		return false
	end
	local params = Ground.params()
	local a = from + Vector3.new(0, 1, 0)
	local b = Vector3.new(to.X, a.Y, to.Z)
	return Workspace:Raycast(a, b - a, params) == nil
end

-- Placeables get a Structure modifier the first time a path is computed near them.
local function tagStructures()
	local f = EnemyPath.structures
	if not f then
		return
	end
	for _, part in f() do
		if part.Parent and not part:FindFirstChild("PathStructure") then
			local m = Instance.new("PathfindingModifier")
			m.Name = "PathStructure"
			m.Label = "Structure"
			m.PassThrough = false
			m.Parent = part
		end
	end
end

local function feet(d: any): Vector3
	local root: BasePart = d.root
	local hum: Humanoid = d.humanoid
	return root.Position - Vector3.new(0, root.Size.Y / 2 + hum.HipHeight, 0)
end

-- Pick up a cached route from its nearest waypoint (within 15 studs, same floor).
local function fromCache(st: State, d: any, key: string, to: Vector3, now: number): boolean
	local c = cache[key]
	if not c or now - c.at > Config.PathCacheSec or (c.to - to).Magnitude > Config.RepathDistance then
		return false
	end
	local pos = feet(d)
	local best, bestDist = nil, 15
	for i, w in c.waypoints do
		local dist = (w.Position - pos).Magnitude
		if dist < bestDist and math.abs(w.Position.Y - pos.Y) < 4 then
			best = i
			bestDist = dist
		end
	end
	if not best then
		return false
	end
	st.waypoints = c.waypoints
	st.index = math.min(best + 1, #c.waypoints)
	st.plannedTo = to
	st.plannedAt = now
	return true
end

local function request(st: State, d: any, to: Vector3, now: number)
	if st.pending then
		return
	end
	local key = zoneOf(to) .. ">" .. zoneOf(d.root.Position) .. ">" .. string.lower(d.archetype)
	if fromCache(st, d, key, to, now) then
		return
	end
	st.pending = true
	st.requestedAt = now
	table.insert(queue, { d = d, from = feet(d), to = to, key = key })
end

local function compute(job: { d: any, from: Vector3, to: Vector3, key: string })
	local d = job.d
	local st: State = d.path
	local a = agentFor(d.archetype)
	local path = PathfindingService:CreatePath({
		AgentRadius = a.r,
		AgentHeight = a.h,
		AgentCanJump = true,
		AgentCanClimb = false,
		WaypointSpacing = 4,
		Costs = {
			Structure = Config.PathStructureCost,
			VaultGas = Config.PathGasCost,
			Door = math.huge,
		},
	})
	stats.computes += 1
	local ok = pcall(function()
		path:ComputeAsync(job.from, job.to)
	end)
	st.pending = false
	if d.dead then
		return
	end
	if ok and path.Status == Enum.PathStatus.Success then
		local wps = path:GetWaypoints()
		st.waypoints = wps
		st.index = math.min(2, #wps)
		st.plannedTo = job.to
		st.plannedAt = os.clock()
		st.fails = 0
		st.lastDist = math.huge
		cache[job.key] = { waypoints = wps, at = os.clock(), to = job.to }
	else
		stats.fails += 1
		st.fails += 1
		st.waypoints = nil
		st.plannedAt = os.clock()
		if st.fails >= 3 then
			st.fails = 0
			st.directUntil = os.clock() + Config.PathFailDirectSec
		end
	end
end

-- The budget: PathComputesPerSec tokens a second, the oldest request first.
local function pump(dt: number)
	tokens = math.min(Config.PathComputesPerSec, tokens + Config.PathComputesPerSec * dt)
	if #queue > 0 and tokens < 1 then
		stats.pinned += dt
	end
	while tokens >= 1 and #queue > 0 do
		local job = table.remove(queue, 1) :: any
		if job.d.dead then
			continue
		end
		tokens -= 1
		task.spawn(compute, job)
	end
end

-- The ladder: lifted along the link (no physics), then back on its feet at the far end.
local function climb(d: any, st: State, to: Vector3)
	st.climbing = true
	local root: BasePart = d.root
	local hum: Humanoid = d.humanoid
	local height = root.Size.Y / 2 + hum.HipHeight
	local target = to + Vector3.new(0, height, 0)
	root.Anchored = true
	local anim: AnimationTrack? = nil
	if Config.EnemyClimbAnimationId ~= "" then
		local animator = hum:FindFirstChildOfClass("Animator")
		if animator then
			local a = Instance.new("Animation")
			a.AnimationId = Config.EnemyClimbAnimationId
			anim = animator:LoadAnimation(a)
			if anim then
				anim:Play()
			end
		end
	end
	local look = root.CFrame.LookVector
	local tween = TweenService:Create(root, TweenInfo.new(Config.LadderClimbSec, Enum.EasingStyle.Linear), {
		CFrame = CFrame.lookAt(target, target + Vector3.new(look.X, 0, look.Z)),
	})
	tween:Play()
	task.delay(Config.LadderClimbSec, function()
		if anim then
			anim:Stop()
		end
		if root.Parent then
			root.Anchored = false
		end
		st.climbing = false
		st.lastDist = math.huge
	end)
end

local function teleportHome(d: any, st: State)
	local box = d.box
	local at = if box then Room.pointInBox(box) else Room.randomSpawnPoint()
	d.model:PivotTo(CFrame.new(at + Vector3.new(0, d.root.Size.Y / 2 + 1, 0)))
	stats.teleports += 1
	st.waypoints = nil
	st.stuckFor = 0
	st.detourUntil = 0
	Log.event("Path", "stuck %s at %s → teleport", d.archetype, zoneOf(d.root.Position))
end

-- One steer toward `targetPos` (a player's root or a placeable). Called from Enemy's chase every heartbeat.
-- `blocked`: a placeable is in reach and being hit, which is not being stuck.
function EnemyPath.steer(d: any, targetPos: Vector3, now: number, reach: number, blocked: boolean?)
	local st: State = d.path
	if st.climbing then
		return
	end
	local root: BasePart = d.root
	local hum: Humanoid = d.humanoid
	local pos = root.Position
	local dist = (targetPos - pos).Magnitude

	-- Mode: direct when close with a clear walk (or pathfinding off / after three failed computes).
	if now - st.modeAt >= 0.2 then
		st.modeAt = now
		local direct = now < st.directUntil
			or (dist <= Config.DirectRange and clearWalk(feet(d), targetPos - Vector3.new(0, 2.5, 0)))
		st.mode = if direct then "direct" else "path"
	end
	local direct = st.mode == "direct"

	-- The goal for this steer: the target, or the next waypoint.
	local goal = targetPos
	if not direct then
		local needPlan = not st.waypoints
			or (st.plannedTo - targetPos).Magnitude > Config.RepathDistance
			or now - st.plannedAt > Config.RepathSec
		if needPlan then
			request(st, d, Ground.at(targetPos), now)
		end
		local wps = st.waypoints
		if wps and st.index <= #wps then
			local w = wps[st.index]
			-- Reached: close in the flat and on its level (a few studs of slack for stairs).
			if flatDist(w.Position, feet(d)) < 3 and math.abs(w.Position.Y - feet(d).Y) < 5 then
				if w.Label == "ladder" and wps[st.index + 1] then
					climb(d, st, wps[st.index + 1].Position)
					st.index += 2
					return
				end
				st.index += 1
				st.lastDist = math.huge
				if wps[st.index] and wps[st.index].Action == Enum.PathWaypointAction.Jump then
					hum.Jump = true
				end
			end
			local nextW = wps[st.index]
			if nextW then
				goal = nextW.Position
				if nextW.Action == Enum.PathWaypointAction.Jump and flatDist(nextW.Position, pos) < 5 then
					hum.Jump = true
				end
			end
		end
	end

	-- Stuck: no progress toward the goal for StuckSec -> sidestep; StuckTeleportSec -> own spawn box.
	if now - st.lastCheck >= 0.25 then
		local step = now - st.lastCheck
		st.lastCheck = now
		local moved = (pos - st.lastPos).Magnitude
		st.lastPos = pos
		if dist > reach + 1 and not blocked and moved < 0.3 then
			st.stuckFor += step
		else
			st.stuckFor = 0
		end
		if st.stuckFor >= Config.StuckTeleportSec then
			teleportHome(d, st)
			return
		end
		if st.stuckFor >= Config.StuckSec and now >= st.detourUntil then
			if st.stuckFor - step < Config.StuckSec then
				stats.stuck += 1
			end
			local flat = Vector3.new(goal.X - pos.X, 0, goal.Z - pos.Z)
			local dir = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(1, 0, 0)
			local side = Vector3.new(-dir.Z, 0, dir.X) * (if math.random() < 0.5 then 1 else -1)
			hum:MoveTo(pos + side * 10 + dir * 4)
			hum.Jump = true
			st.detourUntil = now + 1
			st.waypoints = nil -- re-plan after the sidestep
			return
		end
	end
	if now < st.detourUntil then
		return
	end
	hum:MoveTo(goal)
end

-- Once per wave: computes per second, failure rate, stucks and teleports since the last line.
function EnemyPath.logWave(wave: number)
	local sec = math.max(1, os.clock() - stats.startedAt)
	Log.event(
		"Path",
		"wave %d computes/s %.1f fail %d%% stuck %d teleports %d%s",
		wave,
		stats.computes / sec,
		if stats.computes > 0 then math.round(stats.fails / stats.computes * 100) else 0,
		stats.stuck,
		stats.teleports,
		if stats.pinned > sec * 0.5 then " (budget pinned: raise DirectRange first)" else ""
	)
	EnemyPath.lastWave = {
		computesPerSec = stats.computes / sec,
		failPct = if stats.computes > 0 then stats.fails / stats.computes * 100 else 0,
		stuck = stats.stuck,
		teleports = stats.teleports,
		budgetUse = math.min(1, (stats.computes / sec) / math.max(1, Config.PathComputesPerSec)),
	}
	table.insert(EnemyPath.history, EnemyPath.lastWave)
	stats = { computes = 0, fails = 0, stuck = 0, teleports = 0, startedAt = os.clock(), pinned = 0 }
end
EnemyPath.lastWave = nil :: any
EnemyPath.history = {} :: { any }

-- What Path debug draws: each pathing enemy's remaining waypoints (and whether it is stuck).
function EnemyPath.debugView(list: { any }): { any }
	local out = {}
	for _, d in list do
		local st: State? = d.path
		if st and st.waypoints and st.mode == "path" then
			local pts = {}
			for i = st.index, math.min(#st.waypoints, st.index + 30) do
				table.insert(pts, st.waypoints[i].Position)
			end
			table.insert(out, { from = d.root.Position, pts = pts, stuck = st.stuckFor >= Config.StuckSec })
		end
	end
	return out
end

function EnemyPath.resetRun()
	queue = {}
	cache = {}
	EnemyPath.history = {}
	stats = { computes = 0, fails = 0, stuck = 0, teleports = 0, startedAt = os.clock(), pinned = 0 }
end

function EnemyPath.init()
	RunService.Heartbeat:Connect(function(dt)
		pump(dt)
		tagStructures()
	end)
end

return EnemyPath
