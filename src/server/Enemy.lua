--!strict
-- One enemy archetype: body + red head Part with a Humanoid. Walks at the nearest player, melees on reach.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local PlayerState = require(script.Parent.PlayerState)

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
	dead: boolean,
}

local Enemy = {}

local template = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("EnemyTemplate") :: Model
local active: { [Model]: Data } = {}
local count = 0

function Enemy.count(): number
	return count
end

local function nearestPlayerRoot(from: Vector3): BasePart?
	local best: BasePart? = nil
	local bestDist = math.huge
	for _, player in Players:GetPlayers() do
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if root and hum and hum.Health > 0 then
			local d = (root.Position - from).Magnitude
			if d < bestDist then
				bestDist = d
				best = root
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

function Enemy.kill(model: Model, attacker: Player?)
	local d = active[model]
	if not d or d.dead then
		return
	end
	d.dead = true
	active[model] = nil
	count -= 1
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
	for model in table.clone(active) do
		Enemy.kill(model, nil)
	end
end

function Enemy.init()
	RunService.Heartbeat:Connect(function()
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
				d.target = nearestPlayerRoot(d.root.Position)
				if d.target then
					d.humanoid:MoveTo(d.target.Position)
				end
			end
			local target = d.target
			if target and target.Parent and now - d.lastSwing >= Config.EnemySwingCooldown then
				if (target.Position - d.root.Position).Magnitude <= Config.EnemyMeleeReach then
					d.lastSwing = now
					local player = Players:GetPlayerFromCharacter(target.Parent)
					if player then
						PlayerState.damage(player, d.dmg, "melee")
					end
				end
			end
		end
	end)
end

return Enemy
