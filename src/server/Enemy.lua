--!strict
-- Enemy base: spawn (a Rig from the roster row, scaled by wave and party size), targeting and movement
-- helpers, damage / flinch / kill / ragdoll, stun and slow, and the per-archetype brains in
-- src/server/Enemies/ (Melee, Shooter, Marksman, Boomer, Grenadier, Heavy; Boss.lua adds its own). Every brain
-- gets the same `api` of helpers each heartbeat; no pathfinding, straight MoveTo with a sidestep + jump
-- when stuck and a re-spawn as a last resort.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Enemies = require(Shared.Enemies)
local Remotes = require(Shared.Remotes)
local PlayerState = require(script.Parent.PlayerState)
local Room = require(script.Parent.Room)
local World = require(script.Parent.World)
local Log = require(script.Parent.Log)
local Rig = require(script.Parent.Enemies.Rig)
local Hazards = require(script.Parent.Enemies.Hazards)

local BRAINS: { [string]: any } = {
	melee = require(script.Parent.Enemies.Melee),
	shooter = require(script.Parent.Enemies.Shooter),
	marksman = require(script.Parent.Enemies.Marksman),
	boomer = require(script.Parent.Enemies.Boomer),
	grenadier = require(script.Parent.Enemies.Grenadier),
	heavy = require(script.Parent.Enemies.Heavy),
}

export type Data = {
	model: Model,
	root: BasePart,
	head: BasePart,
	humanoid: Humanoid,
	archetype: string,
	row: Enemies.Row,
	brain: any,
	wave: number, -- the wave this enemy belongs to (heat clear time follows the last one tagged)
	elite: boolean,
	cashValue: number, -- match cash before greed and the heat multiplier
	hp: number,
	maxHP: number,
	dmg: number,
	speed: number,
	plates: { BasePart },
	target: BasePart?,
	lastRetarget: number,
	lastAttack: number,
	lastSteer: number,
	lastPos: Vector3,
	stuckFor: number,
	detourUntil: number,
	holding: boolean,
	dead: boolean,
	stunUntil: number, -- server clock the stun ends (flashbang): stands still, no attacks
	stunned: boolean,
	slowMult: number, -- walk speed multiplier while slowed (molotov / drum fire)
	slowUntil: number,
	headColor: Color3, -- the head's own color, restored when a stun ends
	lastFlinch: number,
	markUntil: number, -- Eagle Eye: server clock the mark ends...
	markBonus: number, -- ...and the extra damage share it takes from any source until then
	mem: { [string]: any }, -- the brain's scratch space
}

-- What the killing (or hitting) shot looked like: its direction, whether it took the head, and how hard it
-- throws a body: `force` scales the bullet throw (Config.RagdollForceByArchetype), `blast` switches to the
-- explosion throw with `blastT` 1 at the center and 0 at the edge of the blast.
-- `tick` marks turret rounds and field ticks: they never flinch an enemy.
export type Hit = {
	dir: Vector3?,
	headshot: boolean?,
	force: number?,
	blast: boolean?,
	blastT: number?,
	tick: boolean?,
}

local Enemy = {}

-- Abilities installs these so enemies can target and hit turrets / barricades without a require cycle.
Enemy.extraTargets = nil :: (() -> { BasePart })?
Enemy.onStructureHit = nil :: ((BasePart, number) -> ())?
-- Heat installs these: called when an enemy enters and when it dies, for the per-wave clear-time clock.
Enemy.onSpawn = nil :: ((Data) -> ())?
Enemy.onDeath = nil :: ((Data, Player?) -> ())?
-- Boss.lua registers its brain here (`attack = "boss"`).
Enemy.brains = BRAINS

local active: { [Model]: Data } = {}
local count = 0
local enemiesFolder: Folder

function Enemy.count(): number
	return count
end

-- Live enemies tagged with a wave.
function Enemy.countForWave(wave: number): number
	local n = 0
	for _, d in active do
		if not d.dead and d.wave == wave then
			n += 1
		end
	end
	return n
end

function Enemy.data(model: Model): Data?
	return active[model]
end

------------------------------------------------------------------ Targeting helpers (the brain api)
local function standingRoot(player: Player): BasePart?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local state = PlayerState.get(player)
	-- Downed and bled-out players are dropped from targeting.
	if root and hum and hum.Health > 0 and not state.downed and not state.bledOut then
		return root
	end
	return nil
end

local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude

local function losFilter(): { Instance }
	local filter: { Instance } = { enemiesFolder }
	for _, name in { "Effects", "GroundLoot" } do
		local f = Workspace:FindFirstChild(name)
		if f then
			table.insert(filter, f)
		end
	end
	return filter
end

-- Clear line from a point to a target part: nothing solid (walls, pillars, placeables) in between.
local function clearLine(from: Vector3, target: BasePart): boolean
	losParams.FilterDescendantsInstances = losFilter()
	local to = target.Position
	local result = Workspace:Raycast(from, to - from, losParams)
	if not result then
		return true
	end
	return result.Instance == target or result.Instance:IsDescendantOf(target.Parent :: Instance)
end

local function nearestPlayer(from: Vector3, needLos: boolean): (Player?, BasePart?)
	local best: Player? = nil
	local bestRoot: BasePart? = nil
	local bestDist = math.huge
	for _, player in World.runAudience() do
		local root = standingRoot(player)
		if root then
			local dist = (root.Position - from).Magnitude
			if dist < bestDist and (not needLos or clearLine(from + Vector3.new(0, 2, 0), root)) then
				bestDist = dist
				best = player
				bestRoot = root
			end
		end
	end
	return best, bestRoot
end

local function nearestStructure(from: Vector3, range: number): BasePart?
	local extra = Enemy.extraTargets
	if not extra then
		return nil
	end
	local best: BasePart? = nil
	local bestDist = range
	for _, part in extra() do
		if part.Parent then
			local d = (part.Position - from).Magnitude - math.max(part.Size.X, part.Size.Z) / 2
			if d < bestDist then
				bestDist = d
				best = part
			end
		end
	end
	return best
end

-- Nearest thing worth walking at: a living player's root or a placeable (melee kinds).
local function nearestTarget(from: Vector3): BasePart?
	local _, root = nearestPlayer(from, false)
	local best = root
	local bestDist = if root then (root.Position - from).Magnitude else math.huge
	local structure = nearestStructure(from, bestDist)
	if structure then
		best = structure
	end
	return best
end

-- A shot down a line: the first solid thing it meets, or any standing player within `radius` of the line.
local function rayPlayers(from: Vector3, dir: Vector3, range: number, radius: number): (Player?, Vector3?)
	losParams.FilterDescendantsInstances = losFilter()
	local result = Workspace:Raycast(from, dir * range, losParams)
	local wallDist = if result then (result.Position - from).Magnitude else range
	if result then
		-- Walls and pillars sit straight under the Room folder: no Model ancestor, no player.
		local hitModel = result.Instance:FindFirstAncestorOfClass("Model")
		local player = if hitModel then Players:GetPlayerFromCharacter(hitModel) else nil
		if player and standingRoot(player) then
			return player, result.Position
		end
	end
	local best: Player? = nil
	local bestAlong = wallDist
	local bestPos: Vector3? = nil
	for _, player in World.runAudience() do
		local root = standingRoot(player)
		if root then
			local rel = root.Position - from
			local along = rel:Dot(dir)
			if along > 0 and along < bestAlong then
				local off = (rel - dir * along).Magnitude
				if off <= radius then
					bestAlong = along
					best = player
					bestPos = from + dir * along
				end
			end
		end
	end
	return best, bestPos
end

local function muzzleOf(d: Data): Vector3
	local gun = d.model:FindFirstChild("Gun")
	local att = gun and gun:FindFirstChild("Muzzle")
	if att and att:IsA("Attachment") then
		return att.WorldPosition
	end
	return d.head.Position
end

local function hold(d: Data)
	if not d.holding then
		d.holding = true
		d.humanoid:MoveTo(d.root.Position)
	end
end

local function face(d: Data, point: Vector3)
	local pos = d.root.Position
	local flat = Vector3.new(point.X - pos.X, 0, point.Z - pos.Z)
	if flat.Magnitude < 0.5 then
		return
	end
	d.root.CFrame = CFrame.lookAt(pos, pos + flat.Unit)
end

local function damagePlayer(player: Player, amount: number, source: string)
	PlayerState.damage(player, amount, source)
end

local function hitStructure(part: BasePart, amount: number)
	local hook = Enemy.onStructureHit
	if hook then
		hook(part, amount)
	end
end

-- Melee: hit `target` if it is within reach and the cooldown is up. Structures take `structMult` x damage;
-- a player hit with `knockback` is thrown that many studs (their client applies it).
local function swing(
	d: Data,
	target: BasePart,
	now: number,
	dmgMult: number?,
	structMult: number?,
	knockback: number?
): boolean
	if now - d.lastAttack < d.row.cooldown then
		return false
	end
	-- Structures are wide; measure to their surface rather than their center.
	local reach = d.row.range + math.max(target.Size.X, target.Size.Z) / 2
	if (target.Position - d.root.Position).Magnitude > reach then
		return false
	end
	d.lastAttack = now
	local player = Players:GetPlayerFromCharacter(target.Parent)
	if player then
		damagePlayer(player, d.dmg * (dmgMult or 1), "melee")
		if knockback and knockback > 0 then
			local away = target.Position - d.root.Position
			local flat = Vector3.new(away.X, 0, away.Z)
			local dir = if flat.Magnitude > 0.1 then flat.Unit else d.root.CFrame.LookVector
			Remotes.Juice:FireClient(player, "Knockback", { dir = dir, studs = knockback })
		end
	else
		hitStructure(target, d.dmg * (dmgMult or 1) * (structMult or 1))
	end
	return true
end

-- Walk at a target with the stuck handling, and hit any placeable standing in the way.
local function chase(d: Data, target: BasePart, now: number)
	d.holding = false
	local root = d.root
	if Players:GetPlayerFromCharacter(target.Parent) then
		-- Blocked by a placeable: attack it until it breaks, then carry on (a Heavy stomps, a boss breaks it).
		local blocker = nearestStructure(root.Position, d.row.range + 1)
		if blocker and blocker ~= target then
			local mult = if d.row.boss then 100000 elseif d.row.attack == "heavy" then Config.HeavyPlaceableMult else 1
			swing(d, blocker, now, 1, mult)
		end
	end
	if now - d.lastSteer >= Config.RetargetInterval then
		local step = now - d.lastSteer
		d.lastSteer = now
		local toTarget = target.Position - root.Position
		local dist = toTarget.Magnitude
		local moved = (root.Position - d.lastPos).Magnitude
		d.lastPos = root.Position
		if dist > d.row.range + 1 and moved < 0.5 then
			d.stuckFor += step
		else
			d.stuckFor = 0
		end
		if d.stuckFor >= Config.EnemyStuckTeleportSec then
			d.stuckFor = 0
			d.detourUntil = 0
			d.model:PivotTo(CFrame.new(Room.randomSpawnPoint() + Vector3.new(0, root.Size.Y / 2 + 1, 0)))
			return
		end
		if d.stuckFor >= Config.EnemyStuckDetourSec and now >= d.detourUntil then
			local flat = Vector3.new(toTarget.X, 0, toTarget.Z)
			local dir = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(1, 0, 0)
			local side = Vector3.new(-dir.Z, 0, dir.X) * (if math.random() < 0.5 then 1 else -1)
			d.humanoid:MoveTo(root.Position + side * 10 + dir * 4)
			d.humanoid.Jump = true
			d.detourUntil = now + 1
			return
		end
	end
	if now < d.detourUntil then
		return -- keep walking the detour waypoint
	end
	d.humanoid:MoveTo(target.Position)
end

-- Remove an enemy without a kill (the Boomer after its burst): no cash, no body.
local function selfDestruct(d: Data)
	if d.dead then
		return
	end
	d.dead = true
	active[d.model] = nil
	count -= 1
	local hook = Enemy.onDeath
	if hook then
		hook(d, nil)
	end
	d.model:Destroy()
end

-- A Heavy plate comes off: unwelded, thrown clear, gone after a beat.
local function dropPlate(d: Data, plate: BasePart)
	local weld = plate:FindFirstChildOfClass("WeldConstraint")
	if weld then
		weld:Destroy()
	end
	plate.Massless = false
	plate.CanCollide = true
	plate.CanQuery = false
	plate.CollisionGroup = "Corpse"
	plate.Parent = Workspace:FindFirstChild("Effects") or Workspace
	local away = (plate.Position - d.root.Position)
	local flat = Vector3.new(away.X, 0, away.Z)
	local dir = if flat.Magnitude > 0.1 then flat.Unit else d.root.CFrame.LookVector
	plate:ApplyImpulse((dir * 18 + Vector3.new(0, 16, 0)) * plate.AssemblyMass)
	plate:ApplyAngularImpulse(
		Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 8 * plate.AssemblyMass
	)
	World.fireRun("PlateOff", { position = plate.Position, model = d.model })
	task.delay(3, function()
		if plate.Parent then
			TweenService:Create(plate, TweenInfo.new(0.4), { Transparency = 1 }):Play()
			task.delay(0.45, function()
				plate:Destroy()
			end)
		end
	end)
end

local api = {
	retargetInterval = Config.RetargetInterval,
	nearestPlayer = nearestPlayer,
	nearestStructure = nearestStructure,
	nearestTarget = nearestTarget,
	hasLos = function(d: Data, target: BasePart): boolean
		return clearLine(d.head.Position, target)
	end,
	rayPlayers = rayPlayers,
	muzzle = muzzleOf,
	hold = hold,
	face = face,
	chase = chase,
	swing = swing,
	damagePlayer = damagePlayer,
	damageStructure = hitStructure,
	blast = Hazards.blast,
	telegraph = Hazards.telegraph,
	fireField = Hazards.fire,
	fire = World.fireRun,
	selfDestruct = selfDestruct,
	dropPlate = dropPlate,
	losFilter = losFilter,
	structures = function(): { BasePart }
		local extra = Enemy.extraTargets
		return if extra then extra() else {}
	end,
	-- spawnAt (the boss's call-ins) is installed after Enemy.spawn below.
	spawnAt = nil :: ((string, Vector3) -> Model)?,
}

------------------------------------------------------------------ Spawn
export type SpawnOpts = { elite: boolean?, row: Enemies.Row?, brain: any? }

-- Spawn one `archetype` at a floor point, scaled for `wave` and the party size. opts.row / opts.brain let the
-- boss supply its own row and brain.
function Enemy.spawn(archetype: string, wave: number, position: Vector3, opts: SpawnOpts?): Model
	local row = (opts and opts.row) or Enemies.ById[archetype] or Enemies.ById[Enemies.Default]
	local elite = opts ~= nil and opts.elite == true and row.noElite ~= true
	local built = Rig.build(row, elite)
	local model, root, head, hum = built.model, built.root, built.head, built.humanoid
	model:PivotTo(CFrame.new(position + Vector3.new(0, root.Size.Y / 2 + 1, 0)))
	hum.WalkSpeed = row.speed
	model.Parent = enemiesFolder
	root:SetNetworkOwner(nil)

	local players = math.max(1, #World.runAudience())
	local hp = Enemies.hpAt(row, wave, players) * (if elite then Config.EliteHpMult else 1)
	local dmg = Enemies.dmgAt(row, wave)
	model:SetAttribute("MaxHP", hp)
	model:SetAttribute("HP", hp)
	model:SetAttribute("Wave", wave)
	active[model] = {
		model = model,
		root = root,
		head = head,
		humanoid = hum,
		archetype = row.id,
		row = row,
		brain = (opts and opts.brain) or BRAINS[row.attack] or BRAINS.melee,
		wave = wave,
		elite = elite,
		cashValue = row.cash * (if elite then Config.EliteCashMult else 1),
		hp = hp,
		maxHP = hp,
		dmg = dmg,
		speed = row.speed,
		plates = built.plates,
		target = nil,
		lastRetarget = -math.huge,
		lastAttack = 0,
		lastSteer = os.clock(), -- the stuck clock starts now, not at 0
		lastPos = root.Position,
		stuckFor = 0,
		detourUntil = 0,
		holding = false,
		dead = false,
		stunUntil = 0,
		stunned = false,
		slowMult = 1,
		slowUntil = 0,
		headColor = head.Color,
		lastFlinch = -math.huge,
		markUntil = 0,
		markBonus = 0,
		mem = {},
	}
	count += 1
	local d = active[model]
	if d.brain.init then
		d.brain.init(d, api)
	end
	local hook = Enemy.onSpawn
	if hook then
		hook(d)
	end
	return model
end

-- The boss calls in adds beside itself (Henchmen tagged with the current wave).
api.spawnAt = function(archetype: string, position: Vector3): Model
	return Enemy.spawn(archetype, World.wave, position)
end

------------------------------------------------------------------ Status effects
-- Flashbang: the enemy stops where it stands and does not attack until the stun ends. Head goes white (or
-- `headColor`: a CRYO freeze is ice blue).
function Enemy.stun(model: Model, seconds: number, headColor: Color3?)
	local d = active[model]
	if not d or d.dead then
		return
	end
	d.stunUntil = math.max(d.stunUntil, os.clock() + seconds)
	d.humanoid:MoveTo(d.root.Position)
	d.head.Color = headColor or Color3.new(1, 1, 1)
	if d.brain.onStun then
		d.brain.onStun(d, api)
	end
end

-- Fire fields: walk speed x mult until the time runs out. The stronger slow wins while both apply.
function Enemy.slow(model: Model, mult: number, seconds: number)
	local d = active[model]
	if not d or d.dead then
		return
	end
	local untilT = os.clock() + seconds
	if d.slowUntil <= os.clock() or mult < d.slowMult then
		d.slowMult = mult
	end
	d.slowUntil = math.max(d.slowUntil, untilT)
end

-- Eagle Eye: marked through walls (the client draws the red Highlight off MarkedUntil) and +bonus damage from
-- any source while it lasts. A second mark keeps the longer end and the bigger bonus.
function Enemy.mark(model: Model, seconds: number, bonus: number)
	local d = active[model]
	if not d or d.dead then
		return
	end
	local now = os.clock()
	if d.markUntil <= now then
		d.markBonus = bonus
	else
		d.markBonus = math.max(d.markBonus, bonus)
	end
	d.markUntil = math.max(d.markUntil, now + seconds)
	model:SetAttribute("MarkedUntil", Workspace:GetServerTimeNow() + (d.markUntil - now))
end

function Enemy.stunned(model: Model): boolean
	local d = active[model]
	return d ~= nil and d.stunUntil > os.clock()
end

------------------------------------------------------------------ Queries
-- Resolve a hit part to its enemy model, or nil if the part is not an enemy.
function Enemy.fromPart(part: Instance): Model?
	local model = part:FindFirstAncestorOfClass("Model")
	if model and active[model] then
		return model
	end
	return nil
end

-- Nearest live enemy to a point within range, skipping `exclude`.
function Enemy.nearest(position: Vector3, range: number, exclude: Model?): Model?
	local best: Model? = nil
	local bestDist = range
	for model, d in active do
		if d.dead or model == exclude then
			continue
		end
		local dist = (d.root.Position - position).Magnitude
		if dist < bestDist then
			bestDist = dist
			best = model
		end
	end
	return best
end

-- Nearest live enemy within `range` of a point whose direction from it is within `angleDeg` of `dir`
-- (point-blank shots: an enemy standing in the shooter is inside the ray's start).
function Enemy.nearestInCone(origin: Vector3, dir: Vector3, range: number, angleDeg: number): Model?
	local best: Model? = nil
	local bestDist = range
	local cosLimit = math.cos(math.rad(angleDeg))
	for model, d in active do
		if d.dead then
			continue
		end
		local rel = d.root.Position - origin
		local dist = rel.Magnitude
		if dist < bestDist and (dist < 0.5 or rel.Unit:Dot(dir) >= cosLimit) then
			bestDist = dist
			best = model
		end
	end
	return best
end

-- Every live enemy within radius of a point, skipping `exclude`.
function Enemy.within(position: Vector3, radius: number, exclude: Model?): { Model }
	local out = {}
	for model, d in active do
		if not d.dead and model ~= exclude and (d.root.Position - position).Magnitude <= radius then
			table.insert(out, model)
		end
	end
	return out
end

function Enemy.rootPosition(model: Model): Vector3?
	local d = active[model]
	return if d then d.root.Position else nil
end

------------------------------------------------------------------ Death
-- Bodies on the floor (ragdolls). They are not enemies any more: bullets pass through them (CanQuery off),
-- nothing targets them, and they only collide with the room (the Corpse collision group).
local corpses: { [Model]: boolean } = {}
local corpseCount = 0

local function shrinkOut(model: Model)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
			TweenService:Create(p, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Size = Vector3.new(0.05, 0.05, 0.05),
			}):Play()
		end
	end
	task.delay(0.22, function()
		model:Destroy()
	end)
end

-- Impulse, lift and spin for a kill: the gun's base, the overkill bonus and a little randomness; explosions
-- throw outward from the center with their own numbers, falling off toward the blast edge.
local function throwStrength(hit: Hit?, overkill: number): (number, number, number)
	local impulse, lift, spin
	if hit and hit.blast then
		local t = math.clamp(hit.blastT or 1, 0, 1)
		local edge = Config.RagdollBlastEdge
		local falloff = edge + (1 - edge) * t
		impulse = Config.RagdollBlastImpulse * falloff
		lift = Config.RagdollBlastLift * falloff
		spin = Config.RagdollBlastSpin * falloff
	else
		local force = if hit and hit.force then hit.force else 1
		impulse = Config.RagdollImpulse * force
		lift = Config.RagdollLift * force
		spin = Config.RagdollSpin * force
	end
	-- Overkill: damage past what was left, as a share of max HP, adds up to RagdollOverkillMax.
	local bonus = 1 + math.clamp(overkill, 0, 1) * Config.RagdollOverkillMax
	local v = Config.RagdollVariance
	local wobble = 1 + (math.random() * 2 - 1) * v
	return impulse * bonus * wobble, lift * bonus * wobble, spin * bonus * (1 + (math.random() * 2 - 1) * v)
end

-- The Humanoid goes (no more standing up or walking), the parts become a loose body that the killing shot
-- throws over; a headshot pops the head off. It lies RagdollLifetime, fades over RagdollFadeSec, then is removed.
local function ragdoll(d: Data, hit: Hit?, overkill: number)
	local model, root = d.model, d.root
	corpses[model] = true
	corpseCount += 1
	model.Destroying:Once(function()
		if corpses[model] then
			corpses[model] = nil
			corpseCount -= 1
		end
	end)
	d.humanoid:Destroy()
	local head = d.head
	local dir = if hit and hit.dir then hit.dir else Vector3.zero
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 0.05 then
		local a = math.random() * math.pi * 2
		flat = Vector3.new(math.cos(a), 0, math.sin(a))
	end
	flat = flat.Unit
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.CollisionGroup = "Corpse"
			p.CanQuery = false
			p.CanTouch = false
			p.CanCollide = true
			p.Massless = false
			p.Anchored = false
		elseif p:IsA("BillboardGui") or p:IsA("Highlight") or p:IsA("PointLight") then
			p:Destroy()
		end
	end
	local pop = Config.RagdollHeadPop and hit ~= nil and hit.headshot == true
	if pop then
		local weld = head:FindFirstChildOfClass("WeldConstraint")
		if weld then
			weld:Destroy()
		end
	end
	local impulse, lift, spin = throwStrength(hit, overkill)
	local mass = root.AssemblyMass
	root:ApplyImpulse((flat * impulse + Vector3.new(0, lift, 0)) * mass)
	root:ApplyAngularImpulse(
		Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 2 * spin * mass
	)
	if pop then
		head:ApplyImpulse((flat * impulse * 0.6 + Vector3.new(0, lift * 1.5, 0)) * head.AssemblyMass)
	end
	task.delay(Config.RagdollLifetime, function()
		if not model.Parent then
			return
		end
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") then
				TweenService:Create(p, TweenInfo.new(Config.RagdollFadeSec, Enum.EasingStyle.Quad), {
					Transparency = 1,
				}):Play()
			end
		end
		task.delay(Config.RagdollFadeSec + 0.05, function()
			model:Destroy()
		end)
	end)
end

-- Match cash a kill pays (before CASH GAIN): the row's cash x elite x the wave multiplier (CashWaveMult on the
-- enemy's own wave) x the heat multiplier.
function Enemy.cashFor(model: Model): number
	local d = active[model]
	if not d then
		return 0
	end
	local waveMult = 1 + Config.CashWaveMult * math.max(0, d.wave - 1)
	return math.round(d.cashValue * waveMult * World.cashMult())
end

-- A player kill (attacker set) knocks the body over while the floor has room (ActiveRagdolls); clears,
-- falls and the cap shrink the enemy out instead. `overkill` is the damage past the remaining HP as a share
-- of max HP (0 for a kill with nothing to spare). Returns the cash the kill pays (before greed).
function Enemy.kill(model: Model, attacker: Player?, hit: Hit?, overkill: number?): number
	local d = active[model]
	if not d or d.dead then
		return 0
	end
	local cash = if attacker then Enemy.cashFor(model) else 0
	d.dead = true
	active[model] = nil
	count -= 1
	if d.brain.onDeath then
		d.brain.onDeath(d, api, attacker)
	end
	if d.brain.cleanup then
		d.brain.cleanup(d)
	end
	if attacker then
		local ks = PlayerState.get(attacker)
		ks.kills += 1
	end
	local hook = Enemy.onDeath
	if hook then
		hook(d, attacker)
	end
	if attacker and Config.RagdollEnabled and corpseCount < Config.ActiveRagdolls and model.Parent then
		ragdoll(d, hit, overkill or 0)
	else
		shrinkOut(model)
	end
	return cash
end

-- A bullet that did not kill: a flinch pop every client plays off the FlinchAt attribute, at most once per
-- FlinchAnimRate. Never stops the feet. EnemyHitKnockback (0 by default) is the optional shove.
local function flinch(d: Data, hit: Hit?)
	local now = os.clock()
	if now - d.lastFlinch < Config.FlinchAnimRate then
		return
	end
	d.lastFlinch = now
	d.model:SetAttribute("FlinchAt", now)
	local dir = if hit and hit.dir then hit.dir else nil
	if dir and Config.EnemyHitKnockback > 0 then
		local flat = Vector3.new(dir.X, 0, dir.Z)
		if flat.Magnitude > 0.05 then
			d.root:ApplyImpulse(flat.Unit * Config.EnemyHitKnockback * d.root.AssemblyMass)
		end
	end
end

-- Returns whether this damage killed the enemy and the cash the kill pays (before greed; 0 on a non-kill).
-- `hit` carries the shot direction (knockback / ragdoll).
function Enemy.damage(model: Model, amount: number, attacker: Player?, hit: Hit?): (boolean, number)
	local d = active[model]
	if not d or d.dead then
		return false, 0
	end
	-- A brain can scale incoming damage (the staggered boss takes more).
	if d.brain.damageMult then
		amount *= d.brain.damageMult(d)
	end
	if d.markUntil > os.clock() then
		amount *= 1 + d.markBonus -- Eagle Eye
	end
	local before = d.hp
	d.hp -= amount
	model:SetAttribute("HP", d.hp)
	if d.hp <= 0 then
		local cash = Enemy.kill(model, attacker, hit, (amount - math.max(before, 0)) / math.max(d.maxHP, 1))
		return true, cash
	end
	if d.brain.onDamaged then
		d.brain.onDamaged(d, api)
	end
	if hit and not hit.tick and not d.row.noFlinch then
		flinch(d, hit) -- bullets and blasts only; turret rounds and field ticks never flinch an enemy
	end
	return false, 0
end

function Enemy.killAll()
	Enemy.frozen = false
	for model in table.clone(active) do
		Enemy.kill(model, nil)
	end
	for model in table.clone(corpses) do
		model:Destroy()
	end
	Hazards.clearAll()
end

-- Run over: every enemy stops where it stands and fades over `fadeSec`. killAll clears them afterwards.
Enemy.frozen = false
function Enemy.freezeAll(fadeSec: number)
	Enemy.frozen = true
	for model, d in active do
		if d.dead then
			continue
		end
		d.humanoid:MoveTo(d.root.Position)
		d.root.Anchored = true
		if d.brain.cleanup then
			d.brain.cleanup(d)
		end
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") then
				TweenService:Create(p, TweenInfo.new(fadeSec, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Transparency = 0.75,
				}):Play()
			end
		end
	end
end

-- Boss cutscene: enemies stand still (no brains) while `Enemy.paused` is set; nothing fades.
Enemy.paused = false

function Enemy.init()
	local existing = Workspace:FindFirstChild("Enemies")
	enemiesFolder = if existing and existing:IsA("Folder") then existing else Instance.new("Folder")
	if not enemiesFolder.Parent then
		enemiesFolder.Name = "Enemies"
		enemiesFolder.Parent = Workspace
	end
	Hazards.structureTargets = function()
		local extra = Enemy.extraTargets
		return if extra then extra() else {}
	end
	Hazards.hitStructure = hitStructure
	Hazards.init()

	RunService.Heartbeat:Connect(function()
		if Enemy.frozen then
			return
		end
		local now = os.clock()
		for model, d in active do
			if d.dead then
				continue
			end
			if not model.Parent or d.root.Position.Y < -50 then
				Enemy.kill(model, nil)
				continue
			end
			if Enemy.paused then
				-- The cutscene: everything stands still except the boss walking through the wall.
				if d.mem.cutsceneTarget then
					d.brain.tick(d, api, now)
				else
					hold(d)
				end
				continue
			end
			-- Stun and slow drive the walk speed; a stunned enemy neither steers nor attacks.
			local stunned = now < d.stunUntil
			if d.slowUntil > 0 and now >= d.slowUntil then
				d.slowUntil = 0
				d.slowMult = 1
			end
			local speed = if stunned then 0 else d.speed * d.slowMult
			if d.humanoid.WalkSpeed ~= speed then
				d.humanoid.WalkSpeed = speed
			end
			if stunned then
				d.stunned = true
				continue
			elseif d.stunned then
				d.stunned = false
				d.head.Color = d.headColor
			end
			d.brain.tick(d, api, now)
		end
	end)
	Log.event("Enemy", "%d archetypes in the roster", #Enemies.List)
end

return Enemy
