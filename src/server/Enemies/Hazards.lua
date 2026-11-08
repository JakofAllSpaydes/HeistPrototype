--!strict
-- Enemy-made hazards: blasts (Boomer, Grenadier shells, the boss volley) that hurt players and placeables
-- in a radius, fire patches that burn players standing in them (the molotov field look), and the red
-- telegraph circles that grow on the floor before a burst lands.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Ground = require(ReplicatedStorage.Shared.Ground)
local PlayerState = require(script.Parent.Parent.PlayerState)
local World = require(script.Parent.Parent.World)

local Hazards = {}

-- Installed by Enemy.lua (which Abilities feeds): the attackable placeables and how to hurt one.
Hazards.structureTargets = nil :: (() -> { BasePart })?
Hazards.hitStructure = nil :: ((BasePart, number) -> ())?

local RED = Color3.fromHex("E8554D")
local FIRE = Color3.fromRGB(255, 140, 40)

type Field = { model: Model, position: Vector3, radius: number, expiresAt: number, lastTick: number, dps: number }
local fields: { [Model]: Field } = {}
local folder: Folder

local function effects(): Folder
	if folder then
		return folder
	end
	local existing = Workspace:FindFirstChild("Effects")
	folder = if existing and existing:IsA("Folder") then existing else Instance.new("Folder")
	if not folder.Parent then
		folder.Name = "Effects"
		folder.Parent = Workspace
	end
	return folder
end

local function flat(a: Vector3, b: Vector3): number
	return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
end

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	return p
end

-- Standing players within `radius` of a floor point, with their roots.
function Hazards.playersWithin(position: Vector3, radius: number): { { player: Player, root: BasePart } }
	local out = {}
	for _, player in World.runAudience() do
		local state = PlayerState.get(player)
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and PlayerState.isStanding(state) and flat(root.Position, position) <= radius then
			table.insert(out, { player = player, root = root })
		end
	end
	return out
end

-- Damage everyone and every placeable in the radius. Returns how many players were hit.
function Hazards.blast(
	position: Vector3,
	radius: number,
	playerDmg: number,
	structureDmg: number,
	source: string
): number
	local hits = 0
	for _, entry in Hazards.playersWithin(position, radius) do
		PlayerState.damage(entry.player, playerDmg, source)
		hits += 1
	end
	local targets = Hazards.structureTargets
	local hit = Hazards.hitStructure
	if targets and hit and structureDmg > 0 then
		for _, p in targets() do
			if p.Parent and (p.Position - position).Magnitude <= radius + math.max(p.Size.X, p.Size.Z) / 2 then
				hit(p, structureDmg)
			end
		end
	end
	return hits
end

-- A red disc that grows from nothing to `radius` over `seconds`, then goes (the burst follows it).
function Hazards.telegraph(position: Vector3, radius: number, seconds: number, color: Color3?)
	-- Solid enough to read on a phone: the growing disc and a bright rim at the final radius.
	local disc = part({
		Name = "Telegraph",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.15, 0.4, 0.4),
		CFrame = CFrame.new(position.X, Ground.y(position) + 0.12, position.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color or RED,
		Material = Enum.Material.Neon,
		Transparency = Config.TelegraphTransparency,
		Parent = effects(),
	})
	local rim = part({
		Name = "TelegraphRim",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.1, radius * 2 + 0.6, radius * 2 + 0.6),
		CFrame = CFrame.new(position.X, Ground.y(position) + 0.1, position.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color or RED,
		Material = Enum.Material.Neon,
		Transparency = Config.TelegraphRimTransparency,
		Parent = effects(),
	})
	TweenService:Create(disc, TweenInfo.new(math.max(0.05, seconds), Enum.EasingStyle.Linear), {
		Size = Vector3.new(0.15, radius * 2, radius * 2),
	}):Play()
	task.delay(seconds + 0.1, function()
		disc:Destroy()
		rim:Destroy()
	end)
end

-- A burning patch that hurts players standing in it for `seconds` (every FieldTickSec).
function Hazards.fire(position: Vector3, radius: number, seconds: number, dps: number)
	local model = Instance.new("Model")
	model.Name = "EnemyFire"
	local disc = part({
		Name = "Disc",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, radius * 2, radius * 2),
		CFrame = CFrame.new(position.X, Ground.y(position) + 0.1, position.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = FIRE,
		Material = Enum.Material.Neon,
		Transparency = 0.55,
		Parent = model,
	})
	for _, offset in
		{
			Vector3.zero,
			Vector3.new(radius * 0.6, 0, 0),
			Vector3.new(-radius * 0.6, 0, 0),
			Vector3.new(0, 0, radius * 0.6),
			Vector3.new(0, 0, -radius * 0.6),
		}
	do
		local anchor = part({
			Name = "Flame",
			Size = Vector3.new(0.2, 0.2, 0.2),
			CFrame = CFrame.new(position.X, Ground.y(position) + 0.3, position.Z) * CFrame.new(offset),
			Transparency = 1,
			Parent = model,
		})
		local flame = Instance.new("Fire")
		flame.Size = if offset == Vector3.zero then radius * 1.4 else radius * 0.8
		flame.Heat = 12
		flame.Color = FIRE
		flame.SecondaryColor = RED
		flame.Parent = anchor
	end
	model.PrimaryPart = disc
	model.Parent = effects()
	fields[model] = {
		model = model,
		position = Ground.at(position),
		radius = radius,
		expiresAt = Workspace:GetServerTimeNow() + seconds,
		lastTick = 0,
		dps = dps,
	}
end

local function removeField(f: Field)
	if not fields[f.model] then
		return
	end
	fields[f.model] = nil
	for _, p in f.model:GetDescendants() do
		if p:IsA("BasePart") then
			TweenService:Create(p, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Transparency = 1,
			}):Play()
		elseif p:IsA("Fire") then
			p.Enabled = false
		end
	end
	task.delay(0.45, function()
		f.model:Destroy()
	end)
end

function Hazards.clearAll()
	for _, f in table.clone(fields) do
		removeField(f)
	end
	local fx = effects()
	for _, child in fx:GetChildren() do
		if child.Name == "Telegraph" or child.Name == "TelegraphRim" then
			child:Destroy()
		end
	end
end

function Hazards.init()
	RunService.Heartbeat:Connect(function()
		local t = Workspace:GetServerTimeNow()
		for _, f in table.clone(fields) do
			if t >= f.expiresAt then
				removeField(f)
			elseif t - f.lastTick >= Config.FieldTickSec then
				f.lastTick = t
				local amount = f.dps * Config.FieldTickSec
				for _, entry in Hazards.playersWithin(f.position, f.radius) do
					PlayerState.damage(entry.player, amount, "fire")
				end
			end
		end
	end)
end

return Hazards
