--!strict
-- Brief 6: local 3D props for the premium sets: the paid crate (body, lid, trims and the seam strips that glow in
-- the rolled rarity), a gun from its Weapons.Look, a mask on a bust, a wrap on a display rifle, a coin for
-- currencies. Everything is anchored and built at the origin; the caller pivots it into place.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Weapons = require(Shared:WaitForChild("Weapons"))
local Masks = require(Shared:WaitForChild("Masks"))
local MaskShapes = require(Shared:WaitForChild("MaskShapes"))
local Wraps = require(Shared:WaitForChild("Wraps"))
local Crates = require(Shared:WaitForChild("Crates"))
local Rarity = require(Shared:WaitForChild("Rarity"))

local Models = {}

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

export type CrateModel = {
	model: Model,
	body: Part,
	lid: Model,
	seams: { Part },
	light: PointLight,
	setGlow: (Color3, number) -> (), -- seam color and intensity 0..1
}

-- A crate standing on `at` (its bottom center). Size ~2.6 x 2 x 2.
function Models.crate(crateId: string, at: CFrame): CrateModel
	local def = Crates.ById[crateId]
	local bodyColor = if def then Color3.fromHex(def.color) else Color3.fromRGB(40, 44, 52)
	local trim = if def then Color3.fromHex(def.trim) else Color3.fromHex("E8B64C")
	local m = Instance.new("Model")
	m.Name = "PaidCrate"
	local w, h, d = 2.8, 1.6, 2.0
	local base = at * CFrame.new(0, h / 2, 0)
	local body = part(m, "Body", Vector3.new(w, h, d), base, bodyColor, Enum.Material.Metal)
	-- Corner trims and bands.
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			part(
				m,
				"Corner",
				Vector3.new(0.18, h + 0.05, 0.18),
				base * CFrame.new(x * (w / 2 - 0.05), 0, z * (d / 2 - 0.05)),
				trim,
				Enum.Material.Metal
			)
		end
	end
	part(
		m,
		"Band",
		Vector3.new(w + 0.04, 0.16, d + 0.04),
		base * CFrame.new(0, -h / 2 + 0.12, 0),
		trim,
		Enum.Material.Metal
	)
	part(m, "Plate", Vector3.new(0.6, 0.5, 0.06), base * CFrame.new(0, 0, -d / 2 - 0.03), trim, Enum.Material.Metal)
	-- Seams: thin neon strips on the lid line, dark until the telegraph.
	local seams = {}
	for _, s in
		{
			{ Vector3.new(w + 0.06, 0.08, 0.06), CFrame.new(0, h / 2 - 0.02, -d / 2 - 0.02) },
			{ Vector3.new(w + 0.06, 0.08, 0.06), CFrame.new(0, h / 2 - 0.02, d / 2 + 0.02) },
			{ Vector3.new(0.06, 0.08, d + 0.06), CFrame.new(-w / 2 - 0.02, h / 2 - 0.02, 0) },
			{ Vector3.new(0.06, 0.08, d + 0.06), CFrame.new(w / 2 + 0.02, h / 2 - 0.02, 0) },
			{ Vector3.new(0.06, h - 0.3, 0.06), CFrame.new(0, 0, -d / 2 - 0.035) },
		}
	do
		local seam = part(m, "Seam", s[1], base * s[2], Color3.fromRGB(20, 20, 24), Enum.Material.Neon)
		table.insert(seams, seam)
	end
	-- The lid (its own model so it can blow off).
	local lid = Instance.new("Model")
	lid.Name = "Lid"
	local lidCf = at * CFrame.new(0, h + 0.2, 0)
	local lidMain = part(
		lid,
		"LidBody",
		Vector3.new(w + 0.1, 0.4, d + 0.1),
		lidCf,
		bodyColor:Lerp(Color3.new(1, 1, 1), 0.08),
		Enum.Material.Metal
	)
	part(
		lid,
		"LidTrim",
		Vector3.new(w + 0.14, 0.08, d + 0.14),
		lidCf * CFrame.new(0, -0.16, 0),
		trim,
		Enum.Material.Metal
	)
	part(lid, "LidStripe", Vector3.new(0.3, 0.42, d + 0.12), lidCf, trim, Enum.Material.Metal)
	lid.PrimaryPart = lidMain
	lid.Parent = m
	local glow = Instance.new("PointLight")
	glow.Range = 10
	glow.Brightness = 0
	glow.Color = trim
	glow.Parent = body
	m.PrimaryPart = body
	-- The pivot is the bottom center, so PivotTo stands the crate on whatever it is given.
	m.WorldPivot = at
	return {
		model = m,
		body = body,
		lid = lid,
		seams = seams,
		light = glow,
		setGlow = function(c: Color3, k: number)
			for _, s in seams do
				s.Color = Color3.fromRGB(20, 20, 24):Lerp(c, math.clamp(k, 0, 1))
			end
			glow.Color = c
			glow.Brightness = 4 * math.clamp(k, 0, 1)
		end,
	}
end

-- A gun from its look (generic rifle shape without one), centered on the origin, muzzle toward -X.
function Models.gun(weaponId: string, bodyColor: Color3?, wrapId: string?): Model
	local w = Weapons.ById[weaponId]
	local look = w and w.look
	local m = Instance.new("Model")
	m.Name = "Gun"
	local body = bodyColor or Rarity.color(if w then w.rarity else 1)
	local accent = if look then Color3.fromHex(look.color) else Color3.fromRGB(40, 40, 46)
	local len = if look then look.body * 1.6 else 2.4
	local barrel = if look then look.barrel * 1.6 else 0.9
	local o = CFrame.new()
	part(m, "Body", Vector3.new(len, 0.5, 0.32), o, body, Enum.Material.Metal)
	part(
		m,
		"Barrel",
		Vector3.new(barrel, 0.16, 0.16),
		o * CFrame.new(-len / 2 - barrel / 2, 0.08, 0),
		accent,
		Enum.Material.Metal
	)
	local wrap = wrapId and Wraps.ById[wrapId]
	part(
		m,
		"Grip",
		Vector3.new(0.28, 0.6, 0.26),
		o * CFrame.new(len * 0.22, -0.48, 0) * CFrame.Angles(0, 0, math.rad(-12)),
		if wrap then Color3.fromHex(wrap.color) else accent,
		if wrap then Wraps.material(wrap) else Enum.Material.Metal
	)
	if not look or look.stock then
		part(
			m,
			"Stock",
			Vector3.new(0.7, 0.46, 0.28),
			o * CFrame.new(len / 2 + 0.35, -0.05, 0),
			if wrap then Color3.fromHex(wrap.color) else accent,
			if wrap then Wraps.material(wrap) else Enum.Material.Wood
		)
	end
	if look and look.scope then
		part(
			m,
			"Scope",
			Vector3.new(len * 0.5, 0.2, 0.2),
			o * CFrame.new(-0.05, 0.38, 0),
			Color3.fromRGB(26, 26, 32),
			Enum.Material.Metal,
			Enum.PartType.Cylinder
		)
	end
	if not look or look.mag == "box" then
		part(m, "Mag", Vector3.new(0.24, 0.55, 0.2), o * CFrame.new(-len * 0.08, -0.5, 0), accent, Enum.Material.Metal)
	elseif look.mag == "tube" then
		part(m, "Tube", Vector3.new(len * 0.8, 0.14, 0.14), o * CFrame.new(-0.2, -0.16, 0), accent, Enum.Material.Metal)
	end
	m.PrimaryPart = m:FindFirstChild("Body") :: BasePart
	return m
end

-- A bust wearing a mask: a head ball, a neck, a shoulder plinth.
function Models.maskBust(maskId: string): Model
	local def = Masks.ById[maskId]
	local m = Instance.new("Model")
	m.Name = "MaskBust"
	local headColor = if def then Color3.fromHex(def.color) else Color3.fromRGB(240, 230, 200)
	local head = part(
		m,
		"Head",
		Vector3.new(1.2, 1.2, 1.2),
		CFrame.new(0, 0.5, 0),
		headColor,
		Enum.Material.SmoothPlastic,
		Enum.PartType.Ball
	)
	part(
		m,
		"Neck",
		Vector3.new(0.5, 0.5, 0.5),
		CFrame.new(0, -0.2, 0),
		Color3.fromRGB(30, 30, 34),
		Enum.Material.SmoothPlastic,
		Enum.PartType.Cylinder
	).CFrame = CFrame.new(
		0,
		-0.2,
		0
	) * CFrame.Angles(0, 0, math.rad(90))
	part(
		m,
		"Shoulders",
		Vector3.new(1.9, 0.5, 0.9),
		CFrame.new(0, -0.6, 0),
		Color3.fromRGB(30, 30, 34),
		Enum.Material.SmoothPlastic
	)
	if def then
		local mask = MaskShapes.build(head, def, "Mask", m)
		if mask then
			for _, p in MaskShapes.parts(mask) do
				p.Anchored = true
			end
		end
	end
	m.PrimaryPart = head
	return m
end

-- A spinning coin / token for currencies and boosts.
function Models.coin(color: Color3): Model
	local m = Instance.new("Model")
	m.Name = "Coin"
	local c =
		part(m, "Coin", Vector3.new(0.3, 1.6, 1.6), CFrame.new(), color, Enum.Material.Metal, Enum.PartType.Cylinder)
	part(
		m,
		"Rim",
		Vector3.new(0.34, 1.7, 1.7),
		CFrame.new(),
		color:Lerp(Color3.new(1, 1, 1), 0.3),
		Enum.Material.Neon,
		Enum.PartType.Cylinder
	).Transparency =
		0.6
	m.PrimaryPart = c
	return m
end

-- The 3D stand-in for a reward (crate reveals, the pass hero): guns, masks, wraps on a rifle, a coin otherwise.
function Models.item(r: { kind: string, id: string?, amount: number? }, rarity: number): Model
	local color = Rarity.color(math.clamp(rarity, 1, 5))
	if r.kind == "weapon" and r.id then
		return Models.gun(r.id, color)
	elseif r.kind == "mask" and r.id then
		return Models.maskBust(r.id)
	elseif r.kind == "wrap" and r.id then
		local w = Wraps.ById[r.id]
		return Models.gun("AK-47", if w then Color3.fromHex(w.color) else color, r.id)
	elseif r.kind == "gold" then
		return Models.coin(Color3.fromHex("E8B64C"))
	elseif r.kind == "tokens" then
		return Models.coin(Color3.fromHex("3FD47A"))
	end
	return Models.coin(color)
end

-- Every BasePart's anchored CFrame relative to the model pivot (for moving welded-by-hand models).
function Models.pivotAll(m: Model, cf: CFrame)
	m:PivotTo(cf)
end

return Models
