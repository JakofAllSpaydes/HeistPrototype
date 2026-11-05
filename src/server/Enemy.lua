--!strict
-- One enemy archetype: body + red head Part with a Humanoid. Walks at the nearest player, melees on reach.
-- No pathfinding: straight MoveTo, with a sidestep + jump when stuck and a re-spawn as a last resort.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local PlayerState = require(script.Parent.PlayerState)
local Room = require(script.Parent.Room)
local World = require(script.Parent.World)

type Data = {
	model: Model,
	root: BasePart,
	humanoid: Humanoid,
	hp: number,
	maxHP: number,
	dmg: number,
	target: BasePart?,
	lastRetarget: number,
	lastSwing: number,
	lastPos: Vector3,
	stuckFor: number,
	detourUntil: number,
	dead: boolean,
	stunUntil: number, -- server clock the stun ends (flashbang): stands still, no swings
	slowMult: number, -- walk speed multiplier while slowed (molotov / drum fire)
	slowUntil: number,
	headColor: Color3, -- the head's own color, restored when a stun ends
	flinchUntil: number, -- a bullet just landed: feet stop until this server clock (Config.EnemyHitFlinchSec)
	lastFlinch: number,
}

-- What the killing (or hitting) shot looked like: its direction, whether it took the head, and how hard it
-- throws a body: `force` scales the bullet throw (Config.RagdollForceByArchetype), `blast` switches to the
-- explosion throw with `blastT` 1 at the center and 0 at the edge of the blast.
-- `tick` marks turret rounds and field ticks: they never flinch an enemy (a fire field would hold its feet).
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

local template = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("EnemyTemplate") :: Model
local active: { [Model]: Data } = {}
local count = 0

function Enemy.count(): number
	return count
end

-- Nearest thing worth walking at: a living player's root or a structure part.
local function nearestTarget(from: Vector3): BasePart?
	local best: BasePart? = nil
	local bestDist = math.huge
	for _, player in World.runAudience() do
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local state = PlayerState.get(player)
		-- Downed players are dropped from targeting.
		if root and hum and hum.Health > 0 and not state.downed and not state.bledOut then
			local d = (root.Position - from).Magnitude
			if d < bestDist then
				bestDist = d
				best = root
			end
		end
	end
	local extra = Enemy.extraTargets
	if extra then
		for _, part in extra() do
			if part.Parent then
				local d = (part.Position - from).Magnitude
				if d < bestDist then
					bestDist = d
					best = part
				end
			end
		end
	end
	return best
end

function Enemy.spawn(wave: number, position: Vector3): Model
	local model = template:Clone()
	local root = model:WaitForChild("HumanoidRootPart") :: BasePart
	local head = model:WaitForChild("Head") :: BasePart
	local hum = model:WaitForChild("Humanoid") :: Humanoid
	model.PrimaryPart = root
	root.CollisionGroup = "Enemy"
	head.CollisionGroup = "Enemy"
	head.CFrame = root.CFrame * CFrame.new(0, root.Size.Y / 2 + head.Size.Y / 2, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = head
	weld.Parent = head
	model:PivotTo(CFrame.new(position + Vector3.new(0, root.Size.Y / 2 + 1, 0)))
	hum.WalkSpeed = Config.EnemyWalkSpeed
	model.Parent = Workspace:WaitForChild("Enemies")
	root:SetNetworkOwner(nil)

	local hp = Config.EnemyHP * Config.EnemyHPMultPerWave ^ (wave - 1)
	local dmg = Config.EnemyDmg * Config.EnemyDmgMultPerWave ^ (wave - 1)
	model:SetAttribute("MaxHP", hp)
	model:SetAttribute("HP", hp)
	active[model] = {
		model = model,
		root = root,
		humanoid = hum,
		hp = hp,
		maxHP = hp,
		dmg = dmg,
		target = nil,
		lastRetarget = -math.huge,
		lastSwing = 0,
		lastPos = root.Position,
		stuckFor = 0,
		detourUntil = 0,
		dead = false,
		stunUntil = 0,
		slowMult = 1,
		slowUntil = 0,
		headColor = head.Color,
		flinchUntil = 0,
		lastFlinch = -math.huge,
	}
	count += 1
	return model
end

-- Flashbang: the enemy stops where it stands and does not swing until the stun ends. Head goes white.
function Enemy.stun(model: Model, seconds: number)
	local d = active[model]
	if not d or d.dead then
		return
	end
	d.stunUntil = math.max(d.stunUntil, os.clock() + seconds)
	d.humanoid:MoveTo(d.root.Position)
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		head.Color = Color3.new(1, 1, 1)
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

function Enemy.stunned(model: Model): boolean
	local d = active[model]
	return d ~= nil and d.stunUntil > os.clock()
end

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
-- throws over; a headshot pops the head off. It lies RagdollSec, fades over RagdollFadeSec, then is removed.
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
	local head = model:FindFirstChild("Head")
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
		end
	end
	local pop = Config.RagdollHeadPop and hit ~= nil and hit.headshot == true and head ~= nil and head:IsA("BasePart")
	if pop and head then
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
	if pop and head and head:IsA("BasePart") then
		head:ApplyImpulse((flat * impulse * 0.6 + Vector3.new(0, lift * 1.5, 0)) * head.AssemblyMass)
	end
	task.delay(Config.RagdollSec, function()
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

-- A player kill (attacker set) knocks the body over while the floor has room (RagdollMaxActive); clears,
-- falls and the cap shrink the enemy out instead. `overkill` is the damage past the remaining HP as a share
-- of max HP (0 for a kill with nothing to spare).
function Enemy.kill(model: Model, attacker: Player?, hit: Hit?, overkill: number?)
	local d = active[model]
	if not d or d.dead then
		return
	end
	d.dead = true
	active[model] = nil
	count -= 1
	if attacker then
		local ks = PlayerState.get(attacker)
		ks.kills += 1
	end
	if attacker and Config.RagdollEnabled and corpseCount < Config.RagdollMaxActive and model.Parent then
		ragdoll(d, hit, overkill or 0)
	else
		shrinkOut(model)
	end
end

-- A bullet that did not kill: a shove along the shot and a short stop of the feet, at most once per
-- EnemyFlinchCooldownSec so a fast gun cannot hold an enemy in place.
local function flinch(d: Data, hit: Hit?)
	local now = os.clock()
	if now - d.lastFlinch < Config.EnemyFlinchCooldownSec then
		return
	end
	d.lastFlinch = now
	d.flinchUntil = now + Config.EnemyHitFlinchSec
	local dir = if hit and hit.dir then hit.dir else nil
	if dir and Config.EnemyHitKnockback > 0 then
		local flat = Vector3.new(dir.X, 0, dir.Z)
		if flat.Magnitude > 0.05 then
			d.root:ApplyImpulse(flat.Unit * Config.EnemyHitKnockback * d.root.AssemblyMass)
		end
	end
end

-- Returns true if this damage killed the enemy. `hit` carries the shot direction (knockback / ragdoll).
function Enemy.damage(model: Model, amount: number, attacker: Player?, hit: Hit?): boolean
	local d = active[model]
	if not d or d.dead then
		return false
	end
	local before = d.hp
	d.hp -= amount
	model:SetAttribute("HP", d.hp)
	if d.hp <= 0 then
		Enemy.kill(model, attacker, hit, (amount - math.max(before, 0)) / math.max(d.maxHP, 1))
		return true
	end
	if hit and not hit.tick then
		flinch(d, hit) -- bullets and blasts only; turret rounds and field ticks never stop an enemy's feet
	end
	return false
end

function Enemy.killAll()
	Enemy.frozen = false
	for model in table.clone(active) do
		Enemy.kill(model, nil)
	end
	for model in table.clone(corpses) do
		model:Destroy()
	end
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
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") then
				TweenService:Create(p, TweenInfo.new(fadeSec, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Transparency = 0.75,
				}):Play()
			end
		end
	end
end

-- Called every RetargetSec: re-pick the target and handle being stuck on a pillar.
local function steer(d: Data, now: number)
	local root = d.root
	d.target = nearestTarget(root.Position)
	local target = d.target
	if not target then
		return
	end
	local toTarget = target.Position - root.Position
	local dist = toTarget.Magnitude
	local moved = (root.Position - d.lastPos).Magnitude
	d.lastPos = root.Position

	if dist > Config.EnemyMeleeReach + 1 and moved < 0.5 then
		d.stuckFor += Config.RetargetSec
	else
		d.stuckFor = 0
	end

	if d.stuckFor >= Config.EnemyStuckTeleportSec then
		d.stuckFor = 0
		d.detourUntil = 0
		d.model:PivotTo(CFrame.new(Room.randomSpawnPoint() + Vector3.new(0, root.Size.Y / 2 + 1, 0)))
		return
	end

	if now < d.detourUntil then
		return -- keep walking the detour waypoint
	end

	if d.stuckFor >= Config.EnemyStuckDetourSec then
		local flat = Vector3.new(toTarget.X, 0, toTarget.Z)
		local dir = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(1, 0, 0)
		local side = Vector3.new(-dir.Z, 0, dir.X) * (if math.random() < 0.5 then 1 else -1)
		d.humanoid:MoveTo(root.Position + side * 10 + dir * 4)
		d.humanoid.Jump = true
		d.detourUntil = now + 1
		return
	end

	d.humanoid:MoveTo(target.Position)
end

function Enemy.init()
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
			-- Stun and slow drive the walk speed; a stunned enemy neither steers nor swings.
			local stunned = now < d.stunUntil
			if d.slowUntil > 0 and now >= d.slowUntil then
				d.slowUntil = 0
				d.slowMult = 1
			end
			local speed = if stunned or now < d.flinchUntil then 0 else Config.EnemyWalkSpeed * d.slowMult
			if d.humanoid.WalkSpeed ~= speed then
				d.humanoid.WalkSpeed = speed
				if not stunned then
					local head = model:FindFirstChild("Head")
					if head and head:IsA("BasePart") and head.Color ~= d.headColor then
						head.Color = d.headColor
					end
				end
			end
			if stunned then
				continue
			end
			if now - d.lastRetarget >= Config.RetargetSec then
				d.lastRetarget = now
				steer(d, now)
			end
			local target = d.target
			if target and target.Parent and now - d.lastSwing >= Config.EnemySwingCooldown then
				-- Structures are wide; measure to their surface rather than their center.
				local reach = Config.EnemyMeleeReach + math.max(target.Size.X, target.Size.Z) / 2
				if (target.Position - d.root.Position).Magnitude <= reach then
					d.lastSwing = now
					local player = Players:GetPlayerFromCharacter(target.Parent)
					if player then
						PlayerState.damage(player, d.dmg, "melee")
					elseif Enemy.onStructureHit then
						Enemy.onStructureHit(target, d.dmg)
					end
				end
			end
		end
	end)
end

return Enemy
