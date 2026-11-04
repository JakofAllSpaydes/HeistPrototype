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
	}
	count += 1
	return model
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

function Enemy.kill(model: Model, attacker: Player?)
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
	-- Shrink out, no ragdoll.
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

-- Returns true if this damage killed the enemy.
function Enemy.damage(model: Model, amount: number, attacker: Player?): boolean
	local d = active[model]
	if not d or d.dead then
		return false
	end
	d.hp -= amount
	model:SetAttribute("HP", d.hp)
	if d.hp <= 0 then
		Enemy.kill(model, attacker)
		return true
	end
	return false
end

function Enemy.killAll()
	Enemy.frozen = false
	for model in table.clone(active) do
		Enemy.kill(model, nil)
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
