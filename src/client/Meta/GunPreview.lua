--!strict
-- The Weapons tab's live preview (Round 18c): a local copy of the held-gun model, the same geometry
-- PlayerState.refreshHeldVisual builds on the server (body in the hub's Common color, the gun's Weapons.Look bits,
-- the wrap band), welded to the right hand while the real held gun hides locally. Nothing replicates.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Weapons = require(Shared:WaitForChild("Weapons"))
local Wraps = require(Shared:WaitForChild("Wraps"))
local Rarity = require(Shared:WaitForChild("Rarity"))

local GunPreview = {}

GunPreview.Name = "MetaPreviewGun"

local function weld(a: BasePart, b: BasePart)
	local wc = Instance.new("WeldConstraint")
	wc.Part0 = a
	wc.Part1 = b
	wc.Parent = b
end

local function bit(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CFrame = cf
	p.Parent = parent
	return p
end

-- Builds the preview gun for `weaponId` (an unknown id, e.g. a showcase gun, gets the generic block) in `char`'s
-- right hand. Returns the model (its "Body" is the gun, its "Grip" the wrappable band) or nil without a hand.
function GunPreview.build(char: Model, weaponId: string, wrapId: string?): Model?
	local hand = (char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")) :: BasePart?
	if not hand or not hand:IsA("BasePart") then
		return nil
	end
	local w = Weapons.ById[weaponId]
	local look = w and w.look
	local bodyLen = if look then look.body else 1.6
	local m = Instance.new("Model")
	m.Name = GunPreview.Name
	local gun = bit(
		m,
		"Body",
		Vector3.new(0.35, 0.5, bodyLen),
		hand.CFrame * CFrame.new(0, -0.25, -0.1 - bodyLen / 2),
		Rarity.color(Rarity.Common),
		Enum.Material.Metal
	)
	weld(hand, gun)
	if look then
		local accent = Color3.fromHex(look.color)
		local function add(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material)
			weld(gun, bit(m, name, size, gun.CFrame * offset, color, material))
		end
		if look.barrel > 0 then
			add(
				"Barrel",
				Vector3.new(0.14, 0.14, look.barrel),
				CFrame.new(0, 0.08, -bodyLen / 2 - look.barrel / 2),
				accent,
				Enum.Material.Metal
			)
		end
		if look.stock then
			add(
				"Stock",
				Vector3.new(0.26, 0.4, 0.5),
				CFrame.new(0, -0.05, bodyLen / 2 + 0.25),
				accent,
				Enum.Material.Wood
			)
		end
		if look.scope then
			add(
				"Scope",
				Vector3.new(0.16, 0.16, bodyLen * 0.45),
				CFrame.new(0, 0.33, -0.05),
				Color3.fromRGB(26, 26, 32),
				Enum.Material.Metal
			)
		end
		if look.mag == "box" then
			add("Mag", Vector3.new(0.18, 0.42, 0.22), CFrame.new(0, -0.42, -bodyLen * 0.1), accent, Enum.Material.Metal)
		elseif look.mag == "tube" then
			add(
				"Tube",
				Vector3.new(0.12, 0.12, bodyLen * 0.8),
				CFrame.new(0, -0.12, -0.15),
				accent,
				Enum.Material.Metal
			)
		end
	end
	local wrap = wrapId and Wraps.ById[wrapId]
	local grip = bit(
		m,
		"Grip",
		Vector3.new(0.38, 0.22, 0.7),
		gun.CFrame * CFrame.new(0, -0.3, 0.3),
		if wrap then Color3.fromHex(wrap.color) else Color3.fromRGB(40, 40, 46),
		if wrap then Wraps.material(wrap) else Enum.Material.Metal
	)
	weld(gun, grip)
	m.PrimaryPart = gun
	m.Parent = char
	return m
end

-- Hide (or show again) the server's held gun and its wrap band on this client only.
function GunPreview.setServerGunHidden(char: Model, hidden: boolean)
	local v = if hidden then 1 else 0
	for _, name in { "HeldGun", "HeldGunWrap" } do
		local p = char:FindFirstChild(name)
		if p then
			if p:IsA("BasePart") then
				p.LocalTransparencyModifier = v
			end
			for _, d in p:GetDescendants() do
				if d:IsA("BasePart") then
					d.LocalTransparencyModifier = v
				end
			end
		end
	end
end

return GunPreview
