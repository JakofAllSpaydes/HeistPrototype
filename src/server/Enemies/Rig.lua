--!strict
-- Builds an enemy body from the roster row: the template rig (root + red head + Humanoid) scaled and
-- recolored, plus the parts that make the silhouette (a lean body, a belly, a backpack, a wide body with
-- armor plates, a gun with a muzzle). Elites get a glow, a bigger scale and an ELITE tag. All Parts.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Enemies = require(Shared.Enemies)

local Rig = {}

local template = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("EnemyTemplate") :: Model
local BASE_ROOT = Vector3.new(2, 4.5, 2)
local BASE_HEAD = 1.6
local STEEL = Color3.fromRGB(70, 72, 80)

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
end

-- An extra body Part welded to the root at a root-relative offset. Massless and non-colliding so the
-- Humanoid walks the same whatever is bolted on.
local function extra(
	root: BasePart,
	name: string,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = root.CFrame * offset
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = true
	p.CanTouch = false
	p.Massless = true
	p.Anchored = false
	p.CollisionGroup = "Enemy"
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	weld(root, p)
	p.Parent = root.Parent
	return p
end

-- A gun on the right side, pointing forward (-Z), with a Muzzle attachment at its tip.
local function gun(root: BasePart, scale: number, length: number, thick: number)
	local g = extra(
		root,
		"Gun",
		Vector3.new(thick, thick, length) * scale,
		CFrame.new(BASE_ROOT.X * 0.55 * scale, 0.3 * scale, -length * 0.25 * scale),
		Color3.fromRGB(36, 36, 42),
		Enum.Material.Metal
	)
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = Vector3.new(0, 0, -length * scale / 2)
	muzzle.Parent = g
end

local function eliteTag(head: BasePart)
	local gui = Instance.new("BillboardGui")
	gui.Name = "EliteTag"
	gui.Adornee = head
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromScale(3.2, 0.7)
	gui.StudsOffset = Vector3.new(0, 1.6, 0)
	gui.MaxDistance = 160
	gui.LightInfluence = 0
	gui.Parent = head
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	label.Text = "ELITE"
	label.TextColor3 = Color3.fromHex("F2E6C8")
	label.TextStrokeTransparency = 0.2
	label.Parent = gui
end

export type Built = { model: Model, root: BasePart, head: BasePart, humanoid: Humanoid, plates: { BasePart } }

function Rig.build(row: Enemies.Row, elite: boolean): Built
	local scale = row.scale * (if elite then Config.EliteScale else 1)
	local color = Enemies.color(row.id)
	local model = template:Clone()
	local root = model:WaitForChild("HumanoidRootPart") :: BasePart
	local head = model:WaitForChild("Head") :: BasePart
	local hum = model:WaitForChild("Humanoid") :: Humanoid
	model.PrimaryPart = root
	model.Name = row.id
	root.CollisionGroup = "Enemy"
	head.CollisionGroup = "Enemy"

	local rootSize = BASE_ROOT
	if row.lean then
		rootSize = Vector3.new(1.5, 4.3, 1.4)
	elseif row.wide then
		rootSize = Vector3.new(3, 4.5, 2.1)
	end
	root.Size = rootSize * scale
	root.Color = color
	root.Material = if row.wide then Enum.Material.Metal else Enum.Material.SmoothPlastic
	head.Size = Vector3.new(BASE_HEAD, BASE_HEAD, BASE_HEAD) * scale
	head.CFrame = root.CFrame * CFrame.new(0, root.Size.Y / 2 + head.Size.Y / 2, 0)
	weld(root, head)
	hum.HipHeight = 0.5 * scale

	local plates: { BasePart } = {}
	if row.round then
		-- The belly: a ball on the front that swells while the fuse runs.
		local belly =
			extra(root, "Belly", Vector3.new(2.6, 2.6, 2.6) * scale, CFrame.new(0, -0.4 * scale, -0.6 * scale), color)
		belly.Shape = Enum.PartType.Ball
	end
	if row.backpack then
		extra(
			root,
			"Backpack",
			Vector3.new(1.6, 2.2, 0.9) * scale,
			CFrame.new(0, 0.4 * scale, (rootSize.Z / 2 + 0.45) * scale),
			Color3.fromRGB(60, 66, 36)
		)
	end
	if row.wide then
		-- Two armor plates: chest first, shoulders second (Config.HeavyPlateHpPcts).
		local chest = extra(
			root,
			"Plate1",
			Vector3.new(rootSize.X + 0.4, 2.4, 0.35) * scale,
			CFrame.new(0, 0.5 * scale, -(rootSize.Z / 2 + 0.2) * scale),
			STEEL,
			Enum.Material.Metal
		)
		local shoulders = extra(
			root,
			"Plate2",
			Vector3.new(rootSize.X + 1.2, 0.6, rootSize.Z + 0.6) * scale,
			CFrame.new(0, (rootSize.Y / 2 - 0.2) * scale, 0),
			STEEL,
			Enum.Material.Metal
		)
		plates = { chest, shoulders }
	end
	if row.attack == "shooter" then
		gun(root, scale, 2.4, 0.35)
	elseif row.attack == "marksman" then
		gun(root, scale, 4.2, 0.3)
	elseif row.attack == "grenadier" then
		gun(root, scale, 1.8, 0.7)
	end

	if elite then
		local light = Instance.new("PointLight")
		light.Color = color
		light.Brightness = 2
		light.Range = 14
		light.Parent = root
		local glow = Instance.new("Highlight")
		glow.Name = "EliteGlow"
		glow.FillColor = color
		glow.FillTransparency = 0.6
		glow.OutlineColor = color
		glow.OutlineTransparency = 0.1
		glow.DepthMode = Enum.HighlightDepthMode.Occluded
		glow.Parent = model
		eliteTag(head)
	end

	model:SetAttribute("Archetype", row.id)
	model:SetAttribute("Elite", elite)
	return { model = model, root = root, head = head, humanoid = hum, plates = plates }
end

return Rig
