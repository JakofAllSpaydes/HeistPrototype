--!strict
-- Brief 12: drones. DOC's Heal Drone, SWARM's attack drones (DRONE, SURGE) and the AEGIS shield drone all live here.
-- A drone is an orbit round its caster (shared DroneOrbit: radius, height, phase, speed), evaluated on the server
-- clock: no part, no physics, no pathfinding, no collision. The server keeps the logic (targets, line of sight,
-- shots, heals, damage credited to the caster); every client draws the meshes from DroneSpawn / DroneGone and the
-- batched DroneShots. Drones never block movement or shots and can't be targeted.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local DroneOrbit = require(Shared.DroneOrbit)
local Remotes = require(script.Parent.SlotRemotes)
local PlayerState = require(script.Parent.Parent.PlayerState)
local Stats = require(script.Parent.Parent.Stats)
local Log = require(script.Parent.Parent.Log)
local Enemy = require(script.Parent.Enemy)
local Pause = require(script.Parent.Pause)
local World = require(script.Parent.World)

local Drones = {}

export type Drone = {
	id: number,
	kind: string, -- heal | attack | aegis
	owner: Player,
	spec: DroneOrbit.Spec,
	born: number,
	untilT: number,
	power: number, -- heal: HP / s; attack: unused (UPLINK reads the gun each shot); aegis: contact DPS
	range: number,
	nextTick: number, -- heal tick / next shot
	nextPick: number, -- attack: next target pick
	target: Model?,
	nextFetch: number, -- SURGE: next bag / cash fetch
	hp: number, -- aegis
	maxHp: number,
	lastPos: Vector3,
	shown: { [Player]: number }, -- heal floats once a second per player
	shownAt: { [Player]: number },
}

local drones: { [number]: Drone } = {}
local nextId = 0
local shots: { any } = {} -- batched for the next flush
local flushAt = 0

-- Injected by Abilities.init (it owns the kill credit, cash and juice path): damage one enemy for the caster.
Drones.hit = nil :: ((Player, Model, number, Vector3, boolean, any?) -> boolean)?
-- Per-kind tick hooks other modules add (SWARM's attack / aegis behaviour lives in Swarm.lua).
Drones.tickers = {} :: { [string]: (Drone, number) -> () }
Drones.onGone = {} :: { [string]: (Drone, string) -> () }

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function rootOf(player: Player): BasePart?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

function Drones.position(d: Drone, t: number?): Vector3
	local root = rootOf(d.owner)
	if root then
		d.lastPos = root.Position + DroneOrbit.offset(d.spec, t or now())
	end
	return d.lastPos
end

function Drones.shot(d: Drone, to: Vector3, extra: { [string]: any }?)
	local s: { [string]: any } = { i = d.id, to = to }
	if extra then
		for k, v in extra do
			s[k] = v
		end
	end
	table.insert(shots, s)
end

function Drones.ofOwner(owner: Player, kind: string?): { Drone }
	local out = {}
	for _, d in drones do
		if d.owner == owner and (kind == nil or d.kind == kind) then
			table.insert(out, d)
		end
	end
	table.sort(out, function(a, b)
		return a.id < b.id
	end)
	return out
end

function Drones.count(owner: Player, kind: string?): number
	return #Drones.ofOwner(owner, kind)
end

function Drones.remove(d: Drone, reason: string)
	if not drones[d.id] then
		return
	end
	drones[d.id] = nil
	local hook = Drones.onGone[d.kind]
	if hook then
		hook(d, reason)
	end
	World.fireRun("DroneGone", { id = d.id, reason = reason })
end

-- A new drone for `owner`. `spec` is its orbit; `sec` its life.
function Drones.spawn(owner: Player, kind: string, sec: number, spec: DroneOrbit.Spec, opts: { [string]: any }?): Drone
	nextId += 1
	local t = now()
	local root = rootOf(owner)
	local d: Drone = {
		id = nextId,
		kind = kind,
		owner = owner,
		spec = spec,
		born = t,
		untilT = t + sec,
		power = 0,
		range = 0,
		nextTick = t,
		nextPick = t,
		target = nil,
		nextFetch = t,
		hp = 0,
		maxHp = 0,
		lastPos = if root then root.Position else Vector3.zero,
		shown = {},
		shownAt = {},
	}
	if opts then
		for k, v in opts do
			(d :: any)[k] = v
		end
	end
	drones[d.id] = d
	World.fireRun("DroneSpawn", {
		id = d.id,
		kind = kind,
		owner = owner.UserId,
		spec = spec,
		born = d.born,
		untilT = d.untilT,
		hp = d.hp,
		maxHp = d.maxHp,
		radius = (opts and opts.bubble) or nil,
	})
	return d
end

------------------------------------------------------------------ Heal drone (DOC)
local function heal(player: Player, amount: number): number
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 or amount <= 0 then
		return 0
	end
	local before = hum.Health
	hum.Health = math.min(hum.MaxHealth, hum.Health + amount)
	return hum.Health - before
end

-- An ally reviving a downed teammate first (within range), then the lowest HP share; ties go to the caster.
local function healTarget(d: Drone, from: Vector3): Player?
	local best: Player? = nil
	local bestShare = math.huge
	local reviverBest: Player? = nil
	local reviverShare = math.huge
	for _, player in World.runAudience() do
		local state = PlayerState.get(player)
		local root = rootOf(player)
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if not root or not hum or not PlayerState.isStanding(state) then
			continue
		end
		if (root.Position - from).Magnitude > d.range then
			continue
		end
		local share = hum.Health / math.max(1, hum.MaxHealth)
		if share >= 1 then
			continue
		end
		local reviving = false
		for _, other in World.runAudience() do
			local os_ = PlayerState.get(other)
			if os_.downed and os_.reviver == player then
				reviving = true
				break
			end
		end
		if reviving and share < reviverShare then
			reviverShare = share
			reviverBest = player
		end
		if share < bestShare or (share == bestShare and player == d.owner) then
			bestShare = share
			best = player
		end
	end
	return reviverBest or best
end

local function healTick(d: Drone, t: number)
	if t < d.nextTick then
		return
	end
	d.nextTick = t + Config.FieldTickSec
	local pos = Drones.position(d, t)
	local target = healTarget(d, pos)
	if not target then
		return
	end
	local healed = heal(target, d.power * Config.FieldTickSec)
	local head = target.Character and target.Character:FindFirstChild("Head") :: BasePart?
	if head then
		Drones.shot(d, head.Position, { h = true })
	end
	if healed <= 0 then
		return
	end
	d.shown[target] = (d.shown[target] or 0) + healed
	if t - (d.shownAt[target] or 0) >= 1 and head then
		d.shownAt[target] = t
		local shown = math.round(d.shown[target])
		d.shown[target] = 0
		if shown > 0 then
			Remotes.Juice:FireClient(target, "Heal", { position = head.Position, amount = shown })
		end
	end
end
Drones.tickers.heal = healTick

-- DOC's Heal Drone: HealDroneHps x ABILITY POWER x HEALING, HealDroneRange, HealDroneSec.
function Drones.summonHealer(owner: Player, hps: number, range: number, sec: number): Drone
	local d = Drones.spawn(owner, "heal", sec, DroneOrbit.shoulder(Drones.count(owner, "heal")), {
		power = hps,
		range = range,
	})
	Log.event("Ability", "%s summoned a heal drone (%.1f HP/s, r%d, %ds)", owner.Name, hps, range, sec)
	return d
end

------------------------------------------------------------------ Lifecycle
function Drones.clearOwner(owner: Player, reason: string): number
	local n = 0
	for _, d in table.clone(drones) do
		if d.owner == owner then
			Drones.remove(d, reason)
			n += 1
		end
	end
	return n
end

function Drones.clearAll()
	for _, d in table.clone(drones) do
		Drones.remove(d, "cleared")
	end
	table.clear(shots)
end

function Drones.all(): { [number]: Drone }
	return drones
end

function Drones.init()
	Pause.onTick(function(dt)
		for _, d in drones do
			d.untilT += dt
			d.nextTick += dt
		end
	end)
	RunService.Heartbeat:Connect(function()
		if Pause.active() then
			return
		end
		local t = now()
		for _, d in table.clone(drones) do
			if not d.owner.Parent or t >= d.untilT then
				Drones.remove(d, if d.owner.Parent then "expired" else "left")
				continue
			end
			local state = PlayerState.get(d.owner)
			if state.bledOut then
				Drones.remove(d, "owner out")
				continue
			end
			local tick = Drones.tickers[d.kind]
			if tick then
				tick(d, t)
			end
		end
		if #shots > 0 and t >= flushAt then
			flushAt = t + 0.1
			World.fireRun("DroneShots", { list = shots })
			shots = {}
		end
	end)
	local _ = Stats
	local _e = Enemy
end

return Drones
