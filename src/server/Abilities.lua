--!strict
-- Q Auto Turret, E Barricade, Z Stim. Structures have HP, enemies attack them, they expire on a timer.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local PlayerState = require(script.Parent.PlayerState)
local Economy = require(script.Parent.Economy)
local Enemy = require(script.Parent.Enemy)
local Log = require(script.Parent.Log)

type Structure = {
	kind: string, -- turret | barricade
	owner: Player,
	model: Model,
	hitPart: BasePart, -- what enemies walk to and hit
	hp: number,
	maxHP: number,
	expiresAt: number,
	fill: Frame,
	lastShot: number,
	head: BasePart?,
}

local Abilities = {}

local folder: Folder
local structures: { [BasePart]: Structure } = {}

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function hpBar(part: BasePart, color: Color3): Frame
	local gui = Instance.new("BillboardGui")
	gui.Name = "HP"
	gui.Size = UDim2.fromScale(4, 0.5)
	gui.StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y / 2 + 1.2, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 80
	gui.Parent = part
	local back = Instance.new("Frame")
	back.BackgroundColor3 = Color3.fromHex("23232B")
	back.BorderSizePixel = 0
	back.Size = UDim2.fromScale(1, 1)
	back.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = back
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(1, 1)
	fill.Parent = back
	local c2 = Instance.new("UICorner")
	c2.CornerRadius = UDim.new(0.5, 0)
	c2.Parent = fill
	return fill
end

local function placementCFrame(char: Model, distance: number): CFrame
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local base = if root then root.CFrame else char:GetPivot()
	local _, yaw = base:ToEulerAnglesYXZ()
	local flat = CFrame.new(base.Position) * CFrame.Angles(0, yaw, 0)
	local pos = (flat * CFrame.new(0, 0, -distance)).Position
	return CFrame.new(pos.X, Config.FloorTop, pos.Z) * CFrame.Angles(0, yaw, 0)
end

local function register(s: Structure)
	structures[s.hitPart] = s
	s.hitPart:SetAttribute("StructureHP", s.hp)
	s.hitPart:SetAttribute("StructureMaxHP", s.maxHP)
end

local function destroyStructure(s: Structure, reason: string)
	if not structures[s.hitPart] then
		return
	end
	structures[s.hitPart] = nil
	Remotes.Juice:FireAllClients("StructureGone", { kind = s.kind, position = s.hitPart.Position, reason = reason })
	for _, p in s.model:GetDescendants() do
		if p:IsA("BasePart") then
			p.CanCollide = false
			TweenService:Create(p, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Size = Vector3.new(0.05, 0.05, 0.05),
				Transparency = 1,
			}):Play()
		end
	end
	task.delay(0.3, function()
		s.model:Destroy()
	end)
	Log.event("Ability", "%s's %s %s", s.owner.Name, s.kind, reason)
end

-- Enemies call this through Enemy.onStructureHit.
function Abilities.damageStructure(part: BasePart, amount: number)
	local s = structures[part]
	if not s then
		return
	end
	s.hp -= amount
	part:SetAttribute("StructureHP", s.hp)
	s.fill.Size = UDim2.fromScale(math.clamp(s.hp / s.maxHP, 0, 1), 1)
	Remotes.Juice:FireAllClients("StructureHit", { kind = s.kind, position = part.Position })
	if s.hp <= 0 then
		destroyStructure(s, "destroyed")
	end
end

-- Parts enemies may target.
function Abilities.targets(): { BasePart }
	local out = {}
	for part in structures do
		table.insert(out, part)
	end
	return out
end

local function onCooldown(state: PlayerState.State, id: string): boolean
	return (state.cooldowns[id] or 0) > now()
end

local function startCooldown(state: PlayerState.State, id: string, seconds: number)
	state.cooldowns[id] = now() + seconds
	state.dirty = true
end

local function placeTurret(player: Player, state: PlayerState.State, char: Model)
	local cf = placementCFrame(char, Config.StructurePlaceDistance)
	local model = Instance.new("Model")
	model.Name = "Turret"
	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = Vector3.new(2.4, 1, 2.4)
	base.CFrame = cf * CFrame.new(0, 0.5, 0)
	base.Anchored = true
	base.Color = Color3.fromRGB(70, 72, 80)
	base.Material = Enum.Material.Metal
	base.Parent = model
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.4, 1.2, 1.4)
	head.CFrame = cf * CFrame.new(0, 1.6, 0)
	head.Anchored = true
	head.CanCollide = false
	head.Color = Color3.fromHex("E8B64C")
	head.Material = Enum.Material.SmoothPlastic
	head.Parent = model
	local barrel = Instance.new("Part")
	barrel.Name = "Barrel"
	barrel.Size = Vector3.new(0.35, 0.35, 1.8)
	barrel.CFrame = head.CFrame * CFrame.new(0, 0, -1.2)
	barrel.Anchored = true
	barrel.CanCollide = false
	barrel.Color = Color3.fromRGB(40, 40, 46)
	barrel.Material = Enum.Material.Metal
	barrel.Parent = model
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = barrel
	weld.Parent = barrel
	model.PrimaryPart = base
	model.Parent = folder
	local s: Structure = {
		kind = "turret",
		owner = player,
		model = model,
		hitPart = base,
		hp = Config.TurretHP,
		maxHP = Config.TurretHP,
		expiresAt = now() + Config.TurretLifetime,
		fill = hpBar(base, Color3.fromHex("E8B64C")),
		lastShot = 0,
		head = head,
	}
	register(s)
	Remotes.Juice:FireAllClients("StructurePlaced", { kind = "turret", position = base.Position })
	Log.event("Ability", "%s placed a turret (%d HP, %ds)", player.Name, Config.TurretHP, Config.TurretLifetime)
end

local function placeBarricade(player: Player, state: PlayerState.State, char: Model)
	local cf = placementCFrame(char, Config.StructurePlaceDistance)
	local model = Instance.new("Model")
	model.Name = "Barricade"
	local wall = Instance.new("Part")
	wall.Name = "Wall"
	wall.Size = Config.BarricadeSize
	wall.CFrame = cf * CFrame.new(0, Config.BarricadeSize.Y / 2, 0)
	wall.Anchored = true
	wall.Color = Color3.fromRGB(110, 112, 120)
	wall.Material = Enum.Material.Metal
	wall.Parent = model
	local stripe = Instance.new("Part")
	stripe.Name = "Stripe"
	stripe.Size = Vector3.new(Config.BarricadeSize.X, 0.4, Config.BarricadeSize.Z + 0.05)
	stripe.CFrame = wall.CFrame * CFrame.new(0, Config.BarricadeSize.Y / 2 - 0.4, 0)
	stripe.Anchored = true
	stripe.CanCollide = false
	stripe.Color = Color3.fromHex("E8B64C")
	stripe.Material = Enum.Material.Neon
	stripe.Parent = model
	model.PrimaryPart = wall
	model.Parent = folder
	local s: Structure = {
		kind = "barricade",
		owner = player,
		model = model,
		hitPart = wall,
		hp = Config.BarricadeHP,
		maxHP = Config.BarricadeHP,
		expiresAt = now() + Config.BarricadeLifetime,
		fill = hpBar(wall, Color3.fromHex("9BA0A8")),
		lastShot = 0,
		head = nil,
	}
	register(s)
	Remotes.Juice:FireAllClients("StructurePlaced", { kind = "barricade", position = wall.Position })
	Log.event(
		"Ability",
		"%s placed a barricade (%d HP, %ds)",
		player.Name,
		Config.BarricadeHP,
		Config.BarricadeLifetime
	)
end

local function stim(player: Player, state: PlayerState.State)
	state.stimUntil = now() + Config.StimDuration
	PlayerState.applyCharacterStats(state)
	state.dirty = true
	Remotes.Juice:FireClient(player, "StimStart", { duration = Config.StimDuration, until_ = state.stimUntil })
	Log.event(
		"Ability",
		"%s used stim (%ds, x%.1f speed, x%.1f fire rate, x%.1f reload)",
		player.Name,
		Config.StimDuration,
		Config.StimMoveMult,
		Config.StimFireRateMult,
		Config.StimReloadSpeedMult
	)
end

function Abilities.use(player: Player, id: any)
	if typeof(id) ~= "string" then
		return
	end
	local state = PlayerState.get(player)
	local char = player.Character
	if not char or state.downed or state.bledOut then
		return
	end
	if onCooldown(state, id) then
		Remotes.Juice:FireClient(player, "AbilityDenied", { id = id })
		return
	end
	if id == "turret" then
		placeTurret(player, state, char)
		startCooldown(state, id, Config.TurretCooldown)
	elseif id == "barricade" then
		placeBarricade(player, state, char)
		startCooldown(state, id, Config.BarricadeCooldown)
	elseif id == "stim" then
		stim(player, state)
		startCooldown(state, id, Config.StimCooldown)
	end
end

local function turretTick(s: Structure, t: number)
	if t - s.lastShot < 1 / Config.TurretFireRate then
		return
	end
	local head = s.head
	if not head then
		return
	end
	local target = Enemy.nearest(head.Position, Config.TurretRange, nil)
	if not target then
		return
	end
	local tp = Enemy.rootPosition(target)
	if not tp then
		return
	end
	s.lastShot = t
	head.CFrame = CFrame.lookAt(head.Position, Vector3.new(tp.X, head.Position.Y, tp.Z))
	local muzzle = (head.CFrame * CFrame.new(0, 0, -2.1)).Position
	local state = PlayerState.get(s.owner)
	local st = PlayerState.computed(state)
	local killed = Enemy.damage(target, Config.TurretDmg, s.owner)
	local cash = 0
	if killed then
		cash = math.round(Config.CashPerKill * st.greed)
		Economy.addCash(state, cash)
	end
	Remotes.Juice:FireAllClients("TurretShot", { from = muzzle, to = tp })
	Remotes.Juice:FireClient(s.owner, "Hit", {
		position = tp,
		amount = Config.TurretDmg,
		headshot = false,
		crit = false,
		killed = killed,
		model = target,
		cash = cash,
		secondary = true,
	})
end

function Abilities.init()
	local existing = Workspace:FindFirstChild("Structures")
	if existing and existing:IsA("Folder") then
		folder = existing
	else
		folder = Instance.new("Folder")
		folder.Name = "Structures"
		folder.Parent = Workspace
	end
	Enemy.extraTargets = Abilities.targets
	Enemy.onStructureHit = Abilities.damageStructure
	Remotes.UseAbility.OnServerEvent:Connect(Abilities.use)

	RunService.Heartbeat:Connect(function()
		local t = now()
		for _, s in table.clone(structures) do
			if t >= s.expiresAt then
				destroyStructure(s, "expired")
			elseif s.kind == "turret" then
				turretTick(s, t)
			end
		end
		-- Stim expiry: drop the buff and resync.
		for player, state in PlayerState.all() do
			if state.stimUntil > 0 and t >= state.stimUntil then
				state.stimUntil = 0
				PlayerState.applyCharacterStats(state)
				state.dirty = true
				Remotes.Juice:FireClient(player, "StimEnd", {})
			end
		end
	end)
end

function Abilities.clearAll()
	for _, s in table.clone(structures) do
		destroyStructure(s, "cleared")
	end
end

return Abilities
