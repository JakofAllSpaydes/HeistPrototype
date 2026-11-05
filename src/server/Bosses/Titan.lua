--!strict
-- TITAN · HEAVY RESPONSE. A 1.8-scale wide rig with a minigun and four plates. Walks at the nearest
-- player with a contact hit and knockback, destroys placeables in its path, never flinches. One ability
-- at a time, picked by cooldown and range: Sweep (barrels spin with a cone telegraph, then a beam swings
-- across the arc), Charge (red line to a locked player, then a run down it that stops at a wall with a
-- stagger), Volley (four Grenadier shells on the crew). Phase 2 at 66%: plates 1-2 fall, faster spin.
-- Phase 3 at 33%: plates 3-4 fall and Henchmen call-ins. Kill: heat, cash burst, bags, a crate with a
-- guaranteed Legendary, the TITAN DOWN beat. Every number is in Config's Boss group.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Enemies = require(Shared.Enemies)
local Remotes = require(Shared.Remotes)
local Server = script.Parent.Parent
local Room = require(Server.Room)
local World = require(Server.World)
local Log = require(Server.Log)
local PlayerState = require(Server.PlayerState)
local Economy = require(Server.Economy)
local Heat = require(Server.Heat)
local Bags = require(Server.Bags)
local BigCrate = require(Server.BigCrate)
local Grenadier = require(Server.Enemies.Grenadier)

local Titan = {}
Titan.id = "Titan"
Titan.name = "TITAN"
Titan.subtitle = "HEAVY RESPONSE"

local RED = Color3.fromHex("E8554D")
local BEAM = Color3.fromRGB(255, 150, 70)
local STRUCTURE_BREAK = 100000 -- placeables in its path just break

function Titan.row(): Enemies.Row
	return {
		id = Titan.id,
		name = Titan.name,
		hp = Config.TitanHp,
		speed = Config.TitanSpeed,
		dmg = Config.TitanMeleeDmg,
		range = 6,
		cooldown = 1.6,
		scale = Config.TitanScale,
		color = "2A2A30",
		cash = 0,
		attack = "boss",
		wide = true,
		plates = 4,
		boss = true,
		noFlinch = true,
		noElite = true,
	}
end

local function now(): number
	return os.clock()
end

local function floorY(): number
	return Config.FloorTop
end

local function rotateY(v: Vector3, a: number): Vector3
	return Vector3.new(v.X * math.cos(a) - v.Z * math.sin(a), 0, v.X * math.sin(a) + v.Z * math.cos(a))
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 0.05 then f.Unit else Vector3.zAxis
end

local function effects(): Instance
	return Workspace:FindFirstChild("Effects") or Workspace
end

local function neon(name: string, size: Vector3, cf: CFrame, color: Color3, transparency: number): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.Neon
	p.Transparency = transparency
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Parent = effects()
	return p
end

local function updateView(d: any)
	World.bossView = {
		id = Titan.id,
		name = Titan.name,
		hp = math.max(0, math.round(d.hp)),
		maxHP = math.round(d.maxHP),
		phase = d.mem.phase,
	}
	PlayerState.markAllDirty()
end

local function clearParts(list: { Instance }?)
	if not list then
		return
	end
	for _, inst in list do
		if inst.Parent then
			inst:Destroy()
		end
	end
end

local function clearVisuals(d: any)
	clearParts(d.mem.cone)
	clearParts(d.mem.beam)
	clearParts(d.mem.line)
	d.mem.cone = nil
	d.mem.beam = nil
	d.mem.line = nil
end

function Titan.init(d: any, api: any)
	local t = now()
	d.mem.phase = 1
	d.mem.cooldowns = { sweep = t + 4, charge = t + 7, volley = t + 11 }
	d.mem.nextAbilityAt = t + Config.BossAbilityGapSec
	d.mem.lastCallIn = t
	d.mem.ability = nil
	d.mem.staggerUntil = nil
	updateView(d)
	local _ = api
end

------------------------------------------------------------------ Phases and damage
function Titan.onDamaged(d: any, api: any)
	local share = d.hp / math.max(d.maxHP, 1)
	for i, pct in Config.TitanPhasePcts do
		if share <= pct and d.mem.phase < i + 1 then
			d.mem.phase = i + 1
			local plates: { BasePart } = d.plates
			for k = 2 * i - 1, 2 * i do
				local plate = plates[k]
				if plate then
					plates[k] = nil
					api.dropPlate(d, plate)
				end
			end
			api.fire("BossPhase", { phase = d.mem.phase, position = d.root.Position, name = Titan.name })
			Log.event("Boss", "%s phase %d at %d%% HP", Titan.name, d.mem.phase, math.round(share * 100))
		end
	end
	updateView(d)
end

function Titan.damageMult(d: any): number
	local until_ = d.mem.staggerUntil
	return if until_ and now() < until_ then Config.TitanStaggerDmgMult else 1
end

------------------------------------------------------------------ Abilities
local function endAbility(d: any, kind: string, cooldown: number)
	clearVisuals(d)
	d.mem.ability = nil
	d.mem.cooldowns[kind] = now() + cooldown
	d.mem.nextAbilityAt = now() + Config.BossAbilityGapSec
	d.speed = Config.TitanSpeed
end

-- Sweep: cone telegraph while the barrels spin, then the beam swings across the arc.
local function startSweep(d: any, api: any, t: number, root: BasePart)
	local m = d.mem
	m.ability = "sweep"
	m.stage = "spin"
	m.stageUntil = t + (if m.phase >= 2 then Config.TitanSweepSpinSecP2 else Config.TitanSweepSpinSec)
	m.base = flat(root.Position - d.root.Position)
	local center = Vector3.new(d.root.Position.X, floorY() + 0.12, d.root.Position.Z)
	local cone = {}
	local half = math.rad(Config.TitanSweepArc / 2)
	for k = 0, 4 do
		local a = -half + (2 * half) * k / 4
		local dir = rotateY(m.base, a)
		local ray = neon(
			"SweepCone",
			Vector3.new(0.5, 0.1, Config.TitanSweepRange),
			CFrame.lookAt(center, center + dir) * CFrame.new(0, 0, -Config.TitanSweepRange / 2),
			RED,
			0.72
		)
		table.insert(cone, ray)
	end
	m.cone = cone
	api.hold(d)
	api.fire("BossSweepSpin", { position = d.root.Position, sec = m.stageUntil - t })
end

local function sweepTick(d: any, api: any, t: number)
	local m = d.mem
	api.hold(d)
	if m.stage == "spin" then
		api.face(d, d.root.Position + m.base * 10)
		if t >= m.stageUntil then
			m.stage = "sweep"
			m.sweepStart = t
			m.lastSweepTick = 0
			clearParts(m.cone)
			m.cone = nil
			local a0 = Instance.new("Attachment")
			a0.Parent = Workspace.Terrain
			local a1 = Instance.new("Attachment")
			a1.Parent = Workspace.Terrain
			local beam = Instance.new("Beam")
			beam.Attachment0 = a0
			beam.Attachment1 = a1
			beam.Width0 = 1.4
			beam.Width1 = 0.8
			beam.FaceCamera = true
			beam.LightEmission = 1
			beam.Color = ColorSequence.new(BEAM)
			beam.Transparency = NumberSequence.new(0.1)
			beam.Parent = a0
			m.beam = { a0, a1 }
			api.fire("BossSweep", { position = d.root.Position, sec = Config.TitanSweepSec })
		end
		return
	end
	local s = (t - m.sweepStart) / math.max(Config.TitanSweepSec, 0.05)
	local half = math.rad(Config.TitanSweepArc / 2)
	local dir = rotateY(m.base, -half + 2 * half * math.clamp(s, 0, 1))
	api.face(d, d.root.Position + dir * 10)
	local from = api.muzzle(d)
	-- The beam stops at the first wall.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filter = api.losFilter()
	for _, player in World.runAudience() do
		if player.Character then
			table.insert(filter, player.Character)
		end
	end
	params.FilterDescendantsInstances = filter
	local hit = Workspace:Raycast(from, dir * Config.TitanSweepRange, params)
	local reach = if hit then (hit.Position - from).Magnitude else Config.TitanSweepRange
	local beam = m.beam
	if beam then
		(beam[1] :: Attachment).WorldPosition = from;
		(beam[2] :: Attachment).WorldPosition = from + dir * reach
	end
	if t - m.lastSweepTick >= 0.1 then
		m.lastSweepTick = t
		local tickDmg = Config.TitanSweepDps * 0.1
		local width = math.rad(Config.TitanSweepWidth)
		for _, player in World.runAudience() do
			local char = player.Character
			local proot = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not proot or not PlayerState.isStanding(PlayerState.get(player)) then
				continue
			end
			local rel = proot.Position - d.root.Position
			local dist = Vector3.new(rel.X, 0, rel.Z).Magnitude
			if dist > reach + 2 then
				continue
			end
			local angle = math.acos(math.clamp(flat(rel):Dot(dir), -1, 1))
			if angle <= width and api.hasLos(d, proot) then
				api.damagePlayer(player, tickDmg, "sweep")
			end
		end
		for _, part in api.structures() do
			local rel = part.Position - d.root.Position
			local dist = Vector3.new(rel.X, 0, rel.Z).Magnitude
			if dist <= reach + 2 and math.acos(math.clamp(flat(rel):Dot(dir), -1, 1)) <= width + 0.15 then
				api.damageStructure(part, tickDmg)
			end
		end
	end
	if s >= 1 then
		endAbility(d, "sweep", Config.TitanSweepCooldown)
	end
end

-- Charge: lock a player, draw the line, run it at 3x, stop at a wall with a stagger.
local function startCharge(d: any, api: any, t: number, player: Player, root: BasePart)
	local m = d.mem
	m.ability = "charge"
	m.stage = "telegraph"
	m.stageUntil = t + Config.TitanChargeTelegraphSec
	m.chargePlayer = player
	m.chargeRoot = root
	m.line = { neon("ChargeLine", Vector3.new(1.2, 0.1, 1), CFrame.new(d.root.Position), RED, 0.3) }
	api.hold(d)
	api.fire("BossCharge", { phase = "telegraph", position = d.root.Position, sec = Config.TitanChargeTelegraphSec })
end

local function drawLine(d: any, to: Vector3)
	local line = d.mem.line and d.mem.line[1]
	if not line then
		return
	end
	local a = Vector3.new(d.root.Position.X, floorY() + 0.12, d.root.Position.Z)
	local b = Vector3.new(to.X, floorY() + 0.12, to.Z)
	local len = math.max(1, (b - a).Magnitude)
	line.Size = Vector3.new(1.2, 0.1, len)
	line.CFrame = CFrame.lookAt(a, b) * CFrame.new(0, 0, -len / 2)
end

local function stagger(d: any, api: any, t: number)
	d.mem.staggerUntil = t + Config.TitanStaggerSec
	api.fire("BossStagger", { position = d.root.Position, sec = Config.TitanStaggerSec })
	endAbility(d, "charge", Config.TitanChargeCooldown)
	api.hold(d)
	Log.event("Boss", "%s hit a wall: staggered %.1fs", Titan.name, Config.TitanStaggerSec)
end

local function chargeTick(d: any, api: any, t: number)
	local m = d.mem
	if m.stage == "telegraph" then
		api.hold(d)
		local root: BasePart? = m.chargeRoot
		local target = if root and root.Parent then root.Position else d.root.Position + d.root.CFrame.LookVector * 20
		api.face(d, target)
		drawLine(d, target)
		if t >= m.stageUntil then
			local dir = flat(target - d.root.Position)
			m.chargeEnd = Vector3.new(target.X, d.root.Position.Y, target.Z) + dir * Config.TitanChargeOverrun
			m.chargeDir = dir
			m.stage = "run"
			m.runStart = t
			m.hitDone = false
			m.lastRunPos = d.root.Position
			clearParts(m.line)
			m.line = nil
			d.speed = Config.TitanSpeed * Config.TitanChargeSpeedMult
			d.holding = false
			d.humanoid:MoveTo(m.chargeEnd)
			api.fire("BossCharge", { phase = "run", position = d.root.Position })
		end
		return
	end
	-- Running the line.
	d.holding = false
	d.humanoid:MoveTo(m.chargeEnd)
	local pos = d.root.Position
	for _, part in api.structures() do
		if (part.Position - pos).Magnitude <= 6 + math.max(part.Size.X, part.Size.Z) / 2 then
			api.damageStructure(part, STRUCTURE_BREAK)
		end
	end
	if not m.hitDone then
		for _, player in World.runAudience() do
			local char = player.Character
			local proot = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if proot and PlayerState.isStanding(PlayerState.get(player)) then
				local rel = proot.Position - pos
				if Vector3.new(rel.X, 0, rel.Z).Magnitude <= 5.5 then
					m.hitDone = true
					api.damagePlayer(player, Config.TitanChargeDmg, "charge")
					Remotes.Juice:FireClient(
						player,
						"Knockback",
						{ dir = m.chargeDir, studs = Config.TitanChargeKnockback }
					)
					Log.event("Boss", "%s's charge hit %s", Titan.name, player.Name)
					break
				end
			end
		end
	end
	-- A wall ahead, or no progress: the stagger.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filter = api.losFilter()
	for _, player in World.runAudience() do
		if player.Character then
			table.insert(filter, player.Character)
		end
	end
	for _, part in api.structures() do
		table.insert(filter, part.Parent or part)
	end
	params.FilterDescendantsInstances = filter
	local ahead = Workspace:Raycast(pos, m.chargeDir * (d.root.Size.Z / 2 + 3), params)
	local moved = (pos - m.lastRunPos).Magnitude
	m.lastRunPos = pos
	if ahead or (t - m.runStart > 0.35 and moved < 0.15) then
		stagger(d, api, t)
		return
	end
	local left = m.chargeEnd - pos
	if Vector3.new(left.X, 0, left.Z).Magnitude < 4 or t - m.runStart > Config.TitanChargeMaxSec then
		endAbility(d, "charge", Config.TitanChargeCooldown)
		api.hold(d)
	end
end

-- Volley: four shells on the nearest four player positions (repeating when fewer).
local function startVolley(d: any, api: any, t: number)
	local m = d.mem
	local targets = {}
	for _, player in World.runAudience() do
		local char = player.Character
		local proot = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if proot and PlayerState.isStanding(PlayerState.get(player)) then
			table.insert(targets, proot.Position)
		end
	end
	if #targets == 0 then
		return
	end
	table.sort(targets, function(a, b)
		return (a - d.root.Position).Magnitude < (b - d.root.Position).Magnitude
	end)
	m.ability = "volley"
	m.stageUntil = t + Config.GrenadierTelegraphSec + 0.4
	local dmg = Enemies.dmgAt(Enemies.ById.Grenadier, World.wave)
	local from = api.muzzle(d)
	for i = 1, Config.TitanVolleyCount do
		local target = targets[((i - 1) % #targets) + 1]
		local jitter = if i > #targets
			then Vector3.new((math.random() - 0.5) * 6, 0, (math.random() - 0.5) * 6)
			else Vector3.zero
		Grenadier.lob(api, from, target + jitter, dmg, Titan.id)
	end
	api.hold(d)
	api.face(d, targets[1])
	api.fire("BossVolley", { position = d.root.Position, count = Config.TitanVolleyCount })
end

local function volleyTick(d: any, api: any, t: number)
	api.hold(d)
	if t >= d.mem.stageUntil then
		endAbility(d, "volley", Config.TitanVolleyCooldown)
	end
end

-- Phase 3: Henchmen from the marker nearest the boss.
local function callIn(d: any, api: any)
	local best = Room.spawnPoints[1]
	local bestDist = math.huge
	for _, p in Room.spawnPoints do
		local dist = (p - d.root.Position).Magnitude
		if dist < bestDist then
			bestDist = dist
			best = p
		end
	end
	for i = 1, Config.TitanCallInCount do
		local a = i / Config.TitanCallInCount * math.pi * 2
		api.spawnAt("Henchman", best + Vector3.new(math.cos(a) * 3, 0, math.sin(a) * 3))
	end
	api.fire("BossCallIn", { position = best, count = Config.TitanCallInCount, name = Titan.name })
	Log.event("Boss", "%s called in %d Henchmen", Titan.name, Config.TitanCallInCount)
end

------------------------------------------------------------------ Tick
function Titan.tick(d: any, api: any, t: number)
	local m = d.mem
	-- The cutscene walks it through the wall; everything else waits for the wave.
	if m.cutsceneTarget then
		d.holding = false
		d.humanoid:MoveTo(m.cutsceneTarget)
		return
	end
	if m.staggerUntil then
		if t < m.staggerUntil then
			api.hold(d)
			return
		end
		m.staggerUntil = nil
	end
	if m.ability == "sweep" then
		sweepTick(d, api, t)
		return
	elseif m.ability == "charge" then
		chargeTick(d, api, t)
		return
	elseif m.ability == "volley" then
		volleyTick(d, api, t)
		return
	end
	if m.phase >= 3 and t - m.lastCallIn >= Config.TitanCallInSec then
		m.lastCallIn = t
		callIn(d, api)
	end
	if t - d.lastRetarget >= api.retargetInterval then
		d.lastRetarget = t
		local _, root = api.nearestPlayer(d.root.Position, false)
		d.target = root
	end
	local target: BasePart? = d.target
	if not target or not target.Parent then
		api.hold(d)
		return
	end
	if t >= m.nextAbilityAt then
		local player = Players:GetPlayerFromCharacter(target.Parent)
		local dist = (target.Position - d.root.Position).Magnitude
		local los = api.hasLos(d, target)
		if
			player
			and t >= m.cooldowns.charge
			and dist >= Config.TitanChargeMinRange
			and dist <= Config.TitanChargeMaxRange
			and los
		then
			startCharge(d, api, t, player, target)
			return
		elseif t >= m.cooldowns.sweep and dist <= Config.TitanSweepRange and los then
			startSweep(d, api, t, target)
			return
		elseif t >= m.cooldowns.volley then
			startVolley(d, api, t)
			if m.ability then
				return
			end
		end
	end
	api.chase(d, target, t)
	api.swing(d, target, t, 1, STRUCTURE_BREAK, Config.TitanKnockback)
end

function Titan.onStun(d: any)
	clearVisuals(d)
	d.mem.ability = nil
	d.speed = Config.TitanSpeed
end

function Titan.cleanup(d: any)
	clearVisuals(d)
end

------------------------------------------------------------------ Kill
function Titan.onDeath(d: any, api: any, attacker: Player?)
	clearVisuals(d)
	World.bossView = nil
	PlayerState.markAllDirty()
	if not attacker then
		return
	end
	local pos = d.root.Position
	Heat.onBossKilled()
	for _, p in World.runAudience() do
		Economy.addCash(PlayerState.get(p), Config.TitanCashBurst)
	end
	local cashBags = math.floor(Config.BossBagBurst / 2)
	Bags.burstAround(pos, cashBags, Config.BossBagBurst - cashBags, Config.BossBagBurstRadius)
	BigCrate.drop(pos, { legendary = true, count = Config.BossCrateCount })
	api.fire("BossDown", {
		name = Titan.name,
		position = pos,
		cash = Config.TitanCashBurst,
		slowSec = 0.5,
		userId = attacker.UserId,
		killer = attacker.Name,
	})
	Log.event(
		"Boss",
		"%s DOWN by %s: +$%d each, %d bags, boss crate",
		Titan.name,
		attacker.Name,
		Config.TitanCashBurst,
		Config.BossBagBurst
	)
end

return Titan
