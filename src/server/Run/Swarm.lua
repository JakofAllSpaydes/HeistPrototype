--!strict
-- Brief 12: SWARM, the sixth class. Nothing is aimed: every ability adds to the swarm, buffs it or protects you with it.
--   DRONE (Q)  one more attack drone (Drones.lua orbit) that shoots the nearest enemy it can see. No count cap:
--              duration / cooldown is how many you hold. UPLINK (passive): each shot is DroneWeaponDamagePct of your
--              equipped gun's resolved damage (the capped `droneInherit` stat), so the gun's Armory, cards and web
--              scale the swarm; switching guns re-reads the next shot.
--   SURGE (E)  every live drone fires SurgeFireMult x faster, shots ricochet, drones fetch bags to your feet.
--   AEGIS (Z)  a shield drone over you projects a bubble: enemy hits on anyone inside deplete its HP, melee enemies
--              touching it are body-blocked and burned, and it detonates when it breaks or runs out.
-- Mastery: I +DroneSec, II SURGE ricochets twice, III your kills keep your drones up (Mastery.onKill).
-- Kills by a drone are the caster's (MVP, Jobs, mastery, stats, the kill-extend): they go through Abilities' hitEnemy.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local DroneOrbit = require(Shared.DroneOrbit)
local AbilityGrowth = require(Shared.AbilityGrowth)
local PlayerState = require(script.Parent.Parent.PlayerState)
local Stats = require(script.Parent.Parent.Stats)
local Log = require(script.Parent.Parent.Log)
local Enemy = require(script.Parent.Enemy)
local Drones = require(script.Parent.Drones)
local Bags = require(script.Parent.Bags)
local World = require(script.Parent.World)
local AllyCallout = require(script.Parent.AllyCallout)
local Remotes = require(script.Parent.SlotRemotes)

local Swarm = {}

-- Injected by Abilities (its explosion: damage, knockback, the explosion feel). Falls back to a plain blast.
Swarm.explode = nil :: ((Player, Vector3, number, number, Color3) -> number)?

local SWARM_COLOR = Color3.fromHex(Config.DroneColor)

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function rootOf(player: Player): BasePart?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function level(state: PlayerState.State, id: string): number
	return PlayerState.abilityLevel(state, id)
end

------------------------------------------------------------------ Line of sight
local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude
local losRefreshAt = 0

local function refreshLos(t: number)
	if t < losRefreshAt then
		return
	end
	losRefreshAt = t + 1
	local list: { Instance } = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	for _, name in { "Structures", "Effects" } do
		local f = Workspace:FindFirstChild(name)
		if f then
			table.insert(list, f)
		end
	end
	losParams.FilterDescendantsInstances = list
end

-- Clear when nothing but an enemy (any enemy: a body in the way still takes the shot's place) is in between.
local function canSee(from: Vector3, to: Vector3): boolean
	local dir = to - from
	if dir.Magnitude < 0.1 then
		return true
	end
	local hit = Workspace:Raycast(from, dir, losParams)
	return hit == nil or Enemy.fromPart(hit.Instance) ~= nil
end

local function pickTarget(from: Vector3, range: number): Model?
	local list = {}
	for _, model in Enemy.within(from, range) do
		local ep = Enemy.rootPosition(model)
		if ep then
			table.insert(list, { m = model, d = (ep - from).Magnitude, p = ep })
		end
	end
	table.sort(list, function(a, b)
		return a.d < b.d
	end)
	for i = 1, math.min(#list, 4) do
		if canSee(from, list[i].p) then
			return list[i].m
		end
	end
	return nil
end

------------------------------------------------------------------ DRONE
local function surging(owner: Player, t: number): boolean
	return (Drones.surgeUntil[owner] or 0) > t
end

-- UPLINK: the share of the equipped gun's resolved damage each shot deals. A drone granted to another class by the
-- debug panel uses the base share so it still does something.
local function shotDamage(owner: Player): number
	local state = PlayerState.get(owner)
	local pct = if Stats.count(owner, "droneInherit") > 0
		then Stats.resolve(owner, "droneInherit")
		else Config.DroneWeaponDamagePct
	return PlayerState.computed(state).damage * pct / 100
end

local function ricochets(owner: Player): number
	return if PlayerState.passive(PlayerState.get(owner), "SWARM", 2)
		then Config.SwarmMasteryRicochet
		else Config.SurgeRicochet
end

local function shoot(d: Drones.Drone, from: Vector3, target: Model, t: number)
	local tp = Enemy.rootPosition(target)
	if not tp or not canSee(from, tp) then
		d.target = nil
		return
	end
	local hit = Drones.hit
	if not hit then
		return
	end
	local dmg = shotDamage(d.owner)
	local travel = tp - from
	hit(d.owner, target, dmg, tp, true, {
		dir = if travel.Magnitude > 0.1 then travel.Unit else nil,
		force = Config.RagdollTickForce,
		tick = true,
	})
	local extra: { [string]: any } = {}
	if surging(d.owner, t) then
		-- SURGE: the shot jumps on to the nearest enemies round the target it hasn't hit yet.
		local done = { [target] = true }
		local at = tp
		for k = 1, ricochets(d.owner) do
			local nextM: Model? = nil
			local best = Config.SurgeRicochetRange
			for _, m in Enemy.within(at, Config.SurgeRicochetRange) do
				local mp = Enemy.rootPosition(m)
				if mp and not done[m] and (mp - at).Magnitude <= best then
					best = (mp - at).Magnitude
					nextM = m
				end
			end
			local np = nextM and Enemy.rootPosition(nextM)
			if not nextM or not np then
				break
			end
			done[nextM] = true
			hit(d.owner, nextM, dmg, np, true, { force = Config.RagdollTickForce, tick = true })
			extra[if k == 1 then "r" else "r2"] = np
			at = np
		end
	end
	Drones.shot(d, tp, extra)
end

local function fetch(d: Drones.Drone, t: number)
	d.nextFetch = t + Config.SurgeFetchEverySec
	local root = rootOf(d.owner)
	if not root then
		return
	end
	local b = Bags.nearestFree(root.Position, Config.SurgeFetchRange, 4)
	if not b then
		return
	end
	local look = root.CFrame.LookVector
	local feet = root.Position + Vector3.new(look.X, 0, look.Z) * 2
	local from = Bags.moveTo(b, feet)
	Drones.shot(d, from, { f = true })
	Log.event("Swarm", "%s's drone fetched a %s bag (%.0f studs)", d.owner.Name, b.kind, (from - feet).Magnitude)
end

local function attackTick(d: Drones.Drone, t: number)
	refreshLos(t)
	local from = Drones.position(d, t)
	local target = d.target
	if target and (not Enemy.data(target) or not Enemy.rootPosition(target)) then
		target = nil
		d.target = nil
	end
	if t >= d.nextPick then
		d.nextPick = t + Config.DroneRetargetSec
		d.target = pickTarget(from, d.range)
		target = d.target
	end
	local surge = surging(d.owner, t)
	if surge and t >= d.nextFetch then
		fetch(d, t)
	end
	if target and t >= d.nextTick then
		d.nextTick = t + 1 / (Config.DroneFireRate * (if surge then Config.SurgeFireMult else 1))
		shoot(d, from, target, t)
	end
end
Drones.tickers.attack = attackTick

local lastCount: { [Player]: number } = setmetatable({} :: any, { __mode = "k" })

-- One more attack drone for `owner`.
function Swarm.summon(owner: Player, state: PlayerState.State): Drones.Drone
	local mine = Drones.ofOwner(owner, "attack")
	if #mine >= Config.DroneHardCap then
		Drones.remove(mine[1], "hardcap")
		Log.event("Swarm", "WARN hardcap %s (%d drones): the oldest was replaced", owner.Name, #mine)
	end
	local s: any = state
	s.swarmIndex = (s.swarmIndex or 0) + 1
	local base = AbilityGrowth.at("drone", "DroneSec", Config.DroneSec, level(state, "drone"))
	if PlayerState.passive(state, "SWARM", 1) then
		base += Config.SwarmMasteryDroneSec -- LONG RANGE (SWARM I)
	end
	local sec = base * PlayerState.abilityDurationAmp(state)
	local d = Drones.spawn(owner, "attack", sec, DroneOrbit.attack(s.swarmIndex), { range = Config.DroneRange })
	local n = Drones.count(owner, "attack")
	for _, at in Config.SwarmCalloutAt do
		if n >= at and (lastCount[owner] or 0) < at then
			AllyCallout.send(owner, "swarmUp", n)
		end
	end
	lastCount[owner] = n
	Log.event("Swarm", "%s summoned drone #%d (%d up, %ds)", owner.Name, s.swarmIndex, n, math.round(sec))
	return d
end

------------------------------------------------------------------ SURGE
function Swarm.surge(owner: Player, state: PlayerState.State)
	local sec = AbilityGrowth.at("surge", "SurgeSec", Config.SurgeSec, level(state, "surge"))
		* PlayerState.abilityDurationAmp(state)
	local untilT = math.max(Drones.surgeUntil[owner] or 0, now() + sec)
	Drones.surgeUntil[owner] = untilT
	state.abilityActive.surge = untilT
	state.dirty = true
	World.fireRun("SurgeStart", { owner = owner.UserId, untilT = untilT })
	Log.event(
		"Swarm",
		"%s surged %d drones (%ds, x%.1f fire, %d ricochet)",
		owner.Name,
		Drones.count(owner, "attack"),
		math.round(sec),
		Config.SurgeFireMult,
		ricochets(owner)
	)
end

------------------------------------------------------------------ AEGIS
local colliders: { [number]: BasePart } = {}

local function aegisTick(d: Drones.Drone, t: number)
	local root = rootOf(d.owner)
	local c = colliders[d.id]
	if root and c then
		c.CFrame = CFrame.new(root.Position)
	end
	if t < d.nextTick or not root then
		return
	end
	d.nextTick = t + Config.FieldTickSec
	local hit = Drones.hit
	if not hit then
		return
	end
	-- Contact: melee enemies pressed against the bubble burn.
	for _, model in Enemy.within(root.Position, Config.AegisRadius + 2) do
		local ep = Enemy.rootPosition(model)
		if ep then
			local away = ep - root.Position
			hit(d.owner, model, d.power * Config.FieldTickSec, ep, true, {
				dir = if away.Magnitude > 0.1 then away.Unit else nil,
				force = Config.RagdollTickForce,
				tick = true,
			})
		end
	end
end
Drones.tickers.aegis = aegisTick

local function detonate(d: any) -- a Drones.Drone (luau-lsp narrows it oddly through the onGone hook)
	local root = rootOf(d.owner)
	local at = if root then root.Position else d.lastPos
	local state = PlayerState.get(d.owner)
	local dmg = AbilityGrowth.at("aegis", "AegisBurst", Config.AegisBurst, level(state, "aegis"))
		* PlayerState.abilityPower(state)
	local radius = Config.AegisBurstRadius * Stats.mult(d.owner, "area")
	local boom = Swarm.explode
	local n = 0
	if boom then
		n = boom(d.owner, at, radius, dmg, SWARM_COLOR)
	else
		World.fireRun("Blast", { position = at, radius = radius, color = SWARM_COLOR, shake = 0.3 })
	end
	Log.event("Swarm", "%s's aegis detonated: %d dmg r%.1f, %d hit", d.owner.Name, math.round(dmg), radius, n)
end

Drones.onGone.aegis = function(d: Drones.Drone, reason: string)
	-- Round 29b: the Z tile's countdown stops when the bubble goes (broken early or out of time).
	if d.owner.Parent then
		local st = PlayerState.get(d.owner)
		if (st.abilityActive.aegis or 0) <= d.untilT + 0.01 then
			st.abilityActive.aegis = nil
			st.dirty = true
		end
	end
	local c = colliders[d.id]
	if c then
		c:Destroy()
		colliders[d.id] = nil
	end
	if reason == "expired" or reason == "broken" then
		detonate(d)
	end
end

function Swarm.aegis(owner: Player, state: PlayerState.State)
	for _, old in Drones.ofOwner(owner, "aegis") do
		Drones.remove(old, "replaced")
	end
	local hp = AbilityGrowth.at("aegis", "AegisHp", Config.AegisHp, level(state, "aegis"))
		* PlayerState.abilityPower(state)
	local sec = Config.AegisSec * PlayerState.abilityDurationAmp(state)
	local d = Drones.spawn(owner, "aegis", sec, DroneOrbit.center(), {
		hp = hp,
		maxHp = hp,
		power = Config.AegisContactDps * PlayerState.abilityPower(state),
		bubble = Config.AegisRadius,
	})
	-- The body-block: an invisible sphere that collides with enemies only (the Structure group never touches
	-- players), marked for pathing. It is not a placeable: nothing targets it and it never stands still.
	local root = rootOf(owner)
	local c = Instance.new("Part")
	c.Name = "AegisCollider"
	c.Shape = Enum.PartType.Ball
	c.Size = Vector3.new(Config.AegisRadius * 2, Config.AegisRadius * 2, Config.AegisRadius * 2)
	c.Anchored = true
	c.CanCollide = true
	c.CanQuery = false
	c.CanTouch = false
	c.Transparency = 1
	c.CollisionGroup = "Structure"
	c.CFrame = CFrame.new(if root then root.Position else d.lastPos)
	local mod = Instance.new("PathfindingModifier")
	mod.Label = "Aegis"
	mod.PassThrough = false
	mod.Parent = c
	c.Parent = Workspace:FindFirstChild("Effects") or Workspace
	colliders[d.id] = c
	-- Round 29b: the Z tile counts the bubble down like a buff (it detonates at 0).
	state.abilityActive.aegis = d.untilT
	state.dirty = true
	Log.event("Swarm", "%s raised an aegis (%d HP, %ds)", owner.Name, math.round(hp), math.round(sec))
end

-- Enemy hits on a player inside an AEGIS bubble (theirs or a teammate's): the bubble takes them. Ground hazards
-- (fire, gas) are not shots and pass. Returns what is left for the player.
local PASS = { gas = true, fire = true }
local function shield(player: Player, amount: number, source: string?): number
	if source and PASS[source] then
		return amount
	end
	local root = rootOf(player)
	if not root then
		return amount
	end
	for _, d in Drones.all() do
		if d.kind ~= "aegis" or d.hp <= 0 then
			continue
		end
		local center = rootOf(d.owner)
		if not center or (center.Position - root.Position).Magnitude > Config.AegisRadius + 0.5 then
			continue
		end
		local soak = math.min(d.hp, amount)
		d.hp -= soak
		amount -= soak
		World.fireRun("AegisHp", { id = d.id, hp = d.hp })
		if d.hp <= 0 then
			Drones.remove(d, "broken")
		end
		if amount <= 0 then
			return 0
		end
	end
	return amount
end

------------------------------------------------------------------ Logs
-- `[GHS Swarm] <name> drones <n> surge <on|off> aegis <hp>` for every player with a drone, once per wave end.
function Swarm.logWave(players: { Player })
	local t = now()
	for _, p in players do
		local n = Drones.count(p, "attack")
		local a = Drones.ofOwner(p, "aegis")[1]
		if n > 0 or a or (Drones.surgeUntil[p] or 0) > t then
			print(
				string.format(
					"[GHS Swarm] %s drones %d surge %s aegis %d",
					p.Name,
					n,
					if (Drones.surgeUntil[p] or 0) > t then "on" else "off",
					if a then math.round(a.hp) else 0
				)
			)
		end
	end
end

function Swarm.init()
	table.insert(PlayerState.shieldHooks, shield)
	RunService.Heartbeat:Connect(function()
		for p, untilT in Drones.surgeUntil do
			if untilT <= now() then
				Drones.surgeUntil[p] = nil
			end
		end
	end)
	local _ = Remotes
end

return Swarm
