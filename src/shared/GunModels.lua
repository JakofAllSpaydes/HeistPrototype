--!strict
-- Art pass (stand-in models): one procedural builder for every gun the game shows — the held gun, floor guns, the
-- store / crate models and the UI viewport icons. Each weapon gets a recognisable silhouette from a small spec
-- (receiver, handguard, barrel, stock, mag, sight, action) instead of the old single block.
--
-- Gun space: -Z is the muzzle, +Y is up, the receiver ("Body", the root Part) is centred on the origin. Every other
-- piece is a child of the root, joined by a Weld (static) or a Motor6D (moving pieces the animator drives: Mag,
-- Slide, Bolt, Pump, Lever, Charge, Barrels). Attachments on the root: Muzzle, Grip (right hand), MagWell (where a
-- fresh mag goes), Eject (the port, +X out), Butt (the stock's shoulder pad); Foregrip (left hand) sits on the root
-- or on the pump / barrels so the hand rides with them.
-- Parts tagged with the "Wrap" attribute take the equipped wrap; "Rarity" parts take the drop rarity colour.
local Config = require(script.Parent.Config)
local Weapons = require(script.Parent.Weapons)
local Wraps = require(script.Parent.Wraps)
local Rarity = require(script.Parent.Rarity)

export type Opts = {
	rarity: number?, -- colours the Rarity accents (nil = the gun's Armory rarity)
	wrapId: string?, -- paints the Wrap parts
	anchored: boolean?, -- anchor the root (floor guns); pieces stay welded to it
	archetype: string?, -- for ids with no spec and no Weapons entry (showcase guns)
}

type Spec = {
	kind: string, -- pistol | smg | rifle | bullpup | shotgun | sniper | lmg
	len: number, -- receiver length
	h: number, -- receiver height
	w: number, -- receiver width
	guard: number, -- handguard length in front of the receiver
	barrel: number, -- bare barrel past the handguard
	bd: number, -- barrel diameter
	grip: number, -- pistol grip length
	stock: string, -- none | fixed | wood | wire | tube | thumb
	stockLen: number,
	mag: string, -- pistol | stick | curved | drum | box | small | grip | tube | top | none
	magLen: number,
	sight: string, -- iron | red | scope | carry | none
	action: string, -- slide | bolt | pump | lever | break | auto
	metal: string, -- hex
	furn: string, -- hex: grip / handguard / stock
	furnMat: string, -- Enum.Material name for the furniture
	brake: boolean,
	bipod: boolean,
	rail: boolean,
	double: boolean,
}

local KIND: { [string]: { [string]: any } } = {
	pistol = {
		len = 1.05,
		h = 0.46,
		w = 0.26,
		guard = 0,
		barrel = 0.06,
		bd = 0.12,
		grip = 0.62,
		stock = "none",
		stockLen = 0,
		mag = "pistol",
		magLen = 0,
		sight = "iron",
		action = "slide",
	},
	smg = {
		len = 1.1,
		h = 0.46,
		w = 0.3,
		guard = 0.45,
		barrel = 0.25,
		bd = 0.12,
		grip = 0.55,
		stock = "fixed",
		stockLen = 0.6,
		mag = "stick",
		magLen = 0.7,
		sight = "iron",
		action = "auto",
	},
	rifle = {
		len = 1.15,
		h = 0.5,
		w = 0.32,
		guard = 0.75,
		barrel = 0.45,
		bd = 0.13,
		grip = 0.55,
		stock = "fixed",
		stockLen = 0.7,
		mag = "stick",
		magLen = 0.72,
		sight = "iron",
		action = "auto",
	},
	bullpup = {
		len = 1.9,
		h = 0.56,
		w = 0.32,
		guard = 0.2,
		barrel = 0.35,
		bd = 0.13,
		grip = 0.55,
		stock = "none",
		stockLen = 0,
		mag = "stick",
		magLen = 0.6,
		sight = "red",
		action = "auto",
	},
	shotgun = {
		len = 1.0,
		h = 0.5,
		w = 0.32,
		guard = 0.95,
		barrel = 0.6,
		bd = 0.17,
		grip = 0.55,
		stock = "fixed",
		stockLen = 0.65,
		mag = "tube",
		magLen = 0,
		sight = "iron",
		action = "pump",
	},
	sniper = {
		len = 1.3,
		h = 0.46,
		w = 0.3,
		guard = 0.9,
		barrel = 0.9,
		bd = 0.13,
		grip = 0.55,
		stock = "thumb",
		stockLen = 0.62,
		mag = "small",
		magLen = 0.32,
		sight = "scope",
		action = "bolt",
	},
	lmg = {
		len = 1.3,
		h = 0.58,
		w = 0.36,
		guard = 0.8,
		barrel = 0.65,
		bd = 0.16,
		grip = 0.55,
		stock = "fixed",
		stockLen = 0.6,
		mag = "box",
		magLen = 0.6,
		sight = "carry",
		action = "auto",
		bipod = true,
	},
}

local BY_ARCHETYPE = {
	Pistol = "pistol",
	SMG = "smg",
	Rifle = "rifle",
	Shotgun = "shotgun",
	Sniper = "sniper",
	LMG = "lmg",
}

-- Per-gun overrides on top of the archetype's kind. Colours: steel 2E3036, black polymer 1E1F22, wood 7A4A26.
local SPECS: { [string]: { [string]: any } } = {
	M1911 = { kind = "pistol", metal = "3A3D44", furn = "5A3A22", furnMat = "Wood" },
	Glock = { kind = "pistol", len = 1.0, metal = "26272B", furn = "1E1F22" },
	Deagle = { kind = "pistol", len = 1.25, h = 0.54, w = 0.3, metal = "B8BCC2", furn = "1E1F22", barrel = 0 },
	Gold1911 = { kind = "pistol", metal = "E8B64C", furn = "3B2414", furnMat = "Wood" },
	Hornet = { kind = "pistol", metal = "3B3F4A", furn = "202430", rail = true },
	UZI = {
		kind = "smg",
		len = 1.0,
		h = 0.5,
		guard = 0.12,
		barrel = 0.18,
		stock = "wire",
		mag = "grip",
		magLen = 0.4,
		metal = "2E3036",
		furn = "1E1F22",
	},
	MP5 = { kind = "smg", guard = 0.5, barrel = 0.12, mag = "curved", magLen = 0.66, metal = "2A2C31", furn = "1E1F22" },
	P90 = {
		kind = "bullpup",
		len = 1.55,
		h = 0.6,
		guard = 0,
		barrel = 0.14,
		mag = "top",
		sight = "red",
		metal = "2A2B2E",
		furn = "2A2B2E",
	},
	PS90 = {
		kind = "bullpup",
		len = 1.55,
		h = 0.6,
		guard = 0,
		barrel = 0.3,
		mag = "top",
		sight = "scope",
		metal = "3A3A36",
		furn = "C9B98F",
	},
	MAC10 = {
		kind = "smg",
		len = 0.8,
		h = 0.56,
		guard = 0,
		barrel = 0.24,
		stock = "none",
		mag = "grip",
		magLen = 0.5,
		metal = "2B2B30",
		furn = "2B2B30",
	},
	Skorpion = {
		kind = "smg",
		len = 0.95,
		h = 0.4,
		guard = 0.12,
		barrel = 0.22,
		stock = "wire",
		stockLen = 0.55,
		mag = "curved",
		magLen = 0.5,
		metal = "2E3036",
		furn = "6E5A3A",
		furnMat = "Wood",
	},
	StormLinker = { kind = "smg", sight = "red", rail = true, metal = "3B3F4A", furn = "202430" },
	["AK-47"] = {
		kind = "rifle",
		mag = "curved",
		stock = "wood",
		metal = "2E3036",
		furn = "7A4A26",
		furnMat = "Wood",
	},
	M4A1 = { kind = "rifle", stock = "tube", sight = "red", rail = true, metal = "26282C", furn = "1E1F22" },
	["SCAR-H"] = {
		kind = "rifle",
		len = 1.25,
		mag = "stick",
		magLen = 0.6,
		sight = "red",
		rail = true,
		metal = "B59F74",
		furn = "2A2B2E",
	},
	AUG = { kind = "bullpup", len = 1.8, sight = "scope", barrel = 0.45, metal = "2E3036", furn = "5C7A52" },
	FAL = {
		kind = "rifle",
		len = 1.3,
		guard = 0.8,
		barrel = 0.55,
		magLen = 0.6,
		stock = "wood",
		metal = "2E3036",
		furn = "7A4E2D",
		furnMat = "Wood",
	},
	Exogun = { kind = "rifle", sight = "red", rail = true, metal = "3B3F4A", furn = "202430" },
	["SPAS-12"] = { kind = "shotgun", stock = "wire", metal = "2A2B2E", furn = "1E1F22" },
	SawedOff = {
		kind = "shotgun",
		len = 0.6,
		guard = 0.5,
		barrel = 0.55,
		bd = 0.16,
		double = true,
		action = "break",
		mag = "none",
		stock = "none",
		metal = "3A3D44",
		furn = "6B4226",
		furnMat = "Wood",
	},
	Model1887 = {
		kind = "shotgun",
		action = "lever",
		stock = "wood",
		metal = "2E3036",
		furn = "8A5A2B",
		furnMat = "Wood",
	},
	AWP = { kind = "sniper", brake = true, metal = "2E3036", furn = "4F5B3A" },
	M82 = {
		kind = "sniper",
		len = 1.55,
		h = 0.56,
		w = 0.34,
		guard = 0.95,
		barrel = 0.9,
		bd = 0.16,
		stock = "fixed",
		stockLen = 0.6,
		mag = "small",
		magLen = 0.42,
		brake = true,
		bipod = true,
		action = "auto",
		metal = "3A3D44",
		furn = "2E3036",
	},
	Mosin = {
		kind = "sniper",
		len = 1.3,
		guard = 1.2,
		barrel = 0.5,
		stock = "wood",
		mag = "none",
		metal = "2E3036",
		furn = "5A3A22",
		furnMat = "Wood",
	},
	Railcaster = { kind = "sniper", metal = "3B3F4A", furn = "202430" },
	M249 = { kind = "lmg", metal = "2E3036", furn = "1E1F22" },
	RPK = {
		kind = "lmg",
		len = 1.25,
		h = 0.5,
		mag = "drum",
		stock = "wood",
		sight = "iron",
		metal = "2E3036",
		furn = "7A4A26",
		furnMat = "Wood",
	},
}

local GunModels = {}

local DARK = Color3.fromHex("17181B")
local BRASS = Color3.fromHex("C9A043")
local LENS = Color3.fromHex("6FB6FF")

-- The resolved spec for a weapon id (the archetype's kind plus the gun's overrides).
local function specFor(weaponId: string, archetype: string?): Spec
	local over = SPECS[weaponId]
	local w = Weapons.ById[weaponId]
	local kindName = (over and over.kind) or BY_ARCHETYPE[(w and w.archetype) or archetype or "Rifle"] or "rifle"
	local s: { [string]: any } = {
		metal = "2E3036",
		furn = "1E1F22",
		furnMat = "SmoothPlastic",
		brake = false,
		bipod = false,
		rail = false,
		double = false,
	}
	for k, v in KIND[kindName] or KIND.rifle do
		s[k] = v
	end
	if over then
		for k, v in over do
			s[k] = v
		end
	end
	s.kind = kindName
	-- Global size dial: every length scales, so a bigger gun keeps its proportions.
	local k = Config.GunModelScale
	for _, key in { "len", "h", "w", "guard", "barrel", "bd", "grip", "stockLen", "magLen" } do
		s[key] = (s[key] :: number) * k
	end
	return (s :: any) :: Spec
end

GunModels.kindOf = function(weaponId: string, archetype: string?): string
	local over = SPECS[weaponId]
	local w = Weapons.ById[weaponId]
	return (over and over.kind) or BY_ARCHETYPE[(w and w.archetype) or archetype or "Rifle"] or "rifle"
end

local function mat(name: string): Enum.Material
	local ok, m = pcall(function()
		return (Enum.Material :: any)[name]
	end)
	return if ok and m then m else Enum.Material.SmoothPlastic
end

local function newPart(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

type Builder = {
	root: Part,
	box: (
		self: Builder,
		name: string,
		size: Vector3,
		cf: CFrame,
		color: Color3,
		m: Enum.Material,
		parent: BasePart?
	) -> Part,
	cyl: (
		self: Builder,
		name: string,
		length: number,
		d: number,
		cf: CFrame,
		color: Color3,
		m: Enum.Material,
		parent: BasePart?
	) -> Part,
	bar: (self: Builder, name: string, a: Vector3, b: Vector3, t: number, color: Color3, parent: BasePart?) -> Part,
	motor: (self: Builder, piece: BasePart, pivot: CFrame?) -> Motor6D,
}

-- Pieces are built in gun space (root at the origin) and welded to `parent` (default: the root).
local function builder(root: Part): Builder
	local b = {} :: any
	b.root = root
	local function join(p: BasePart, parent: BasePart?)
		local to = parent or root
		local wd = Instance.new("Weld")
		wd.Name = "Weld"
		wd.Part0 = to
		wd.Part1 = p
		wd.C0 = to.CFrame:ToObjectSpace(p.CFrame)
		wd.Parent = p
		p.Parent = to
	end
	function b.box(_self, name, size, cf, color, m, parent)
		local p = newPart(name, size, cf, color, m)
		join(p, parent)
		return p
	end
	-- A cylinder lying along gun Z (Roblox cylinders run along X).
	function b.cyl(_self, name, length, d, cf, color, m, parent)
		local p = newPart(name, Vector3.new(length, d, d), cf * CFrame.Angles(0, math.rad(90), 0), color, m)
		p.Shape = Enum.PartType.Cylinder
		join(p, parent)
		return p
	end
	-- A square rod from a to b.
	function b.bar(_self, name, a, c, t, color, parent)
		local len = (c - a).Magnitude
		local p = newPart(name, Vector3.new(t, t, len), CFrame.lookAt((a + c) / 2, c), color, Enum.Material.Metal)
		join(p, parent)
		return p
	end
	-- Swap a piece's Weld for a Motor6D the animator can drive. `pivot` (gun space) is the hinge; default: the piece.
	function b.motor(_self, piece, pivot)
		local wd = piece:FindFirstChild("Weld")
		local to = if wd and wd:IsA("Weld") then wd.Part0 :: BasePart else root
		if wd then
			wd:Destroy()
		end
		local pv = pivot or piece.CFrame
		local m = Instance.new("Motor6D")
		m.Name = piece.Name .. "Joint"
		m.Part0 = to
		m.Part1 = piece
		m.C0 = to.CFrame:ToObjectSpace(pv)
		m.C1 = piece.CFrame:ToObjectSpace(pv)
		m.Parent = piece
		return m
	end
	return b :: Builder
end

local function tag(p: BasePart, attr: string)
	p:SetAttribute(attr, true)
	if attr == "Wrap" then
		p:SetAttribute("BaseColor", p.Color)
		p:SetAttribute("BaseMaterial", p.Material.Name)
	end
end

local function attach(parent: BasePart, name: string, cf: CFrame): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = parent.CFrame:ToObjectSpace(cf)
	a.Parent = parent
	return a
end

-- Builds the gun for `weaponId` and returns its root Part ("Body"), at the origin, not parented.
function GunModels.build(weaponId: string, opts: Opts?): Part
	local o: Opts = opts or {}
	local s = specFor(weaponId, o.archetype)
	local metal = Color3.fromHex(s.metal)
	local furn = Color3.fromHex(s.furn)
	local furnMat = mat(s.furnMat)
	local metalMat = Enum.Material.Metal
	local L, H, W = s.len, s.h, s.w
	local isPistol = s.kind == "pistol"
	local bullpup = s.kind == "bullpup"

	-- Root: the receiver (for a pistol, the frame under the slide).
	local rootSize = if isPistol then Vector3.new(W, H * 0.45, L * 0.86) else Vector3.new(W, H, L)
	local root = newPart("Body", rootSize, CFrame.identity, metal, metalMat)
	root.Anchored = o.anchored == true
	root:SetAttribute("GunKind", s.kind)
	root:SetAttribute("GunAction", s.action)
	root:SetAttribute("GunMag", s.mag)
	root:SetAttribute("WeaponId", weaponId)
	local b = builder(root)
	local top = if isPistol then H * 0.225 + H * 0.55 else H / 2 -- top of the gun (slide / receiver)
	local bottom = if isPistol then -H * 0.225 else -H / 2
	local front = if isPistol then -L * 0.43 else -L / 2

	-- Pistol slide (moves on every shot).
	local slide: Part? = nil
	if isPistol then
		slide = b:box(
			"Slide",
			Vector3.new(W * 1.04, H * 0.55, L),
			CFrame.new(0, H * 0.225 + H * 0.275, -L * 0.07),
			metal,
			metalMat
		)
		local sl = slide :: Part
		-- Serrations and the port read as darker bands.
		b:box(
			"Serrations",
			Vector3.new(W * 1.06, H * 0.3, L * 0.18),
			CFrame.new(0, H * 0.5, L * 0.3),
			DARK,
			metalMat,
			sl
		)
		b:box(
			"Port",
			Vector3.new(W * 0.5, H * 0.04, L * 0.22),
			CFrame.new(W * 0.1, top + 0.005, -L * 0.05),
			DARK,
			metalMat,
			sl
		)
		b:motor(sl)
		front = -L * 0.57
	end

	-- Rarity strips down both sides of the receiver.
	local stripY = if isPistol then 0 else -H * 0.12
	local stripLen = if isPistol then L * 0.5 else L * 0.55
	for _, side in { -1, 1 } do
		local p = b:box(
			"RarityStrip",
			Vector3.new(0.03, H * 0.16, stripLen),
			CFrame.new(side * (W / 2 + 0.01), stripY, if bullpup then -L * 0.15 else 0),
			metal,
			Enum.Material.SmoothPlastic
		)
		tag(p, "Rarity")
	end

	-- Ejection port on the right.
	if not isPistol and s.action ~= "break" then
		b:box(
			"EjectPort",
			Vector3.new(0.03, H * 0.28, L * 0.22),
			CFrame.new(W / 2 + 0.005, H * 0.18, if bullpup then L * 0.12 else -L * 0.05),
			DARK,
			metalMat
		)
	end
	attach(
		root,
		"Eject",
		CFrame.new(W / 2 + 0.05, if isPistol then top - 0.05 else H * 0.18, if bullpup then L * 0.12 else -L * 0.05)
			* CFrame.Angles(0, math.rad(-90), 0)
	)

	-- Pistol grip (raked back) + trigger guard.
	local gz = if isPistol then L * 0.3 elseif bullpup then -L * 0.2 elseif s.mag == "grip" then 0 else L * 0.22
	local gripH = s.grip
	local rake = if s.mag == "grip" then math.rad(-6) else math.rad(-16)
	local gripCF = CFrame.new(0, bottom - gripH / 2 + 0.06, gz) * CFrame.Angles(rake, 0, 0)
	local grip = b:box("Grip", Vector3.new(W * 0.86, gripH, if isPistol then 0.34 else 0.3), gripCF, furn, furnMat)
	tag(grip, "Wrap")
	b:box("TriggerGuard", Vector3.new(W * 0.25, 0.05, 0.3), CFrame.new(0, bottom - 0.2, gz - 0.33), DARK, metalMat)
	b:box("TriggerGuardFront", Vector3.new(W * 0.25, 0.2, 0.05), CFrame.new(0, bottom - 0.1, gz - 0.47), DARK, metalMat)
	b:box("Trigger", Vector3.new(W * 0.15, 0.12, 0.04), CFrame.new(0, bottom - 0.08, gz - 0.3), DARK, metalMat)
	attach(root, "Grip", gripCF * CFrame.new(0.06, 0.04, 0))

	-- Handguard (the pump on a pump gun, the forend on a break-action).
	local gy = if isPistol then 0 else -H * 0.06
	local gh = H * 0.8
	local guardPart: Part? = nil
	local barrelsPart: Part? = nil
	local by = if isPistol then H * 0.5 else H * 0.16
	local barrelLen = s.guard + s.barrel + (if isPistol then 0 else 0.05)
	if s.action == "break" then
		-- Break-action: both barrels hinge down at the receiver's front; the forend rides with them.
		local bp = b:box(
			"Barrels",
			Vector3.new(s.bd * 2.1, s.bd * 1.05, barrelLen),
			CFrame.new(0, by, front - barrelLen / 2),
			metal,
			metalMat
		)
		barrelsPart = bp
		for _, side in { -1, 1 } do
			b:cyl(
				"Barrel",
				barrelLen + 0.02,
				s.bd,
				CFrame.new(side * s.bd * 0.52, by, front - barrelLen / 2),
				DARK,
				metalMat,
				bp
			)
		end
		local forend = b:box(
			"Handguard",
			Vector3.new(W * 0.9, gh * 0.7, s.guard),
			CFrame.new(0, gy - 0.05, front - s.guard / 2),
			furn,
			furnMat,
			bp
		)
		tag(forend, "Wrap")
		guardPart = forend
		b:motor(bp, CFrame.new(0, bottom + 0.05, front))
	elseif s.guard > 0 then
		local pumpLen = if s.action == "pump" then s.guard * 0.55 else s.guard
		local pz = if s.action == "pump" then front - s.guard * 0.55 else front - s.guard / 2
		local py = if s.action == "pump" then by - s.bd / 2 - 0.1 else gy
		local ph = if s.action == "pump" then s.bd * 1.6 else gh
		local name = if s.action == "pump" then "Pump" else "Handguard"
		local hg = b:box(name, Vector3.new(W * 0.92, ph, pumpLen), CFrame.new(0, py, pz), furn, furnMat)
		tag(hg, "Wrap")
		guardPart = hg
		if s.action ~= "pump" then
			-- Vent slots so long handguards don't read as a plank.
			for i = 1, 3 do
				local z = front - s.guard * (0.25 + (i - 1) * 0.22)
				b:box(
					"Vent",
					Vector3.new(W * 0.95, gh * 0.18, 0.08),
					CFrame.new(0, gy + gh * 0.12, z),
					DARK,
					metalMat,
					hg
				)
			end
		else
			b:motor(hg)
		end
	end

	-- Barrel (single).
	local muzzleZ = front - barrelLen
	if s.action ~= "break" then
		b:cyl("Barrel", barrelLen, s.bd, CFrame.new(0, by, front - barrelLen / 2 + 0.02), DARK, metalMat)
	end
	if s.brake then
		b:cyl("Brake", 0.24, s.bd * 1.9, CFrame.new(0, by, muzzleZ - 0.1), DARK, metalMat)
		muzzleZ -= 0.22
	end
	attach(root, "Muzzle", CFrame.new(0, by, muzzleZ - 0.04))

	-- Front sight post on iron-sighted guns.
	if s.sight == "iron" or s.sight == "carry" then
		local fz = if s.guard > 0 then front - s.guard - 0.02 else front + 0.08
		b:box("FrontSight", Vector3.new(0.05, 0.16, 0.05), CFrame.new(0, by + s.bd / 2 + 0.06, fz), DARK, metalMat)
		if s.sight == "iron" then
			b:box("RearSight", Vector3.new(W * 0.5, 0.08, 0.07), CFrame.new(0, top + 0.04, L * 0.32), DARK, metalMat)
		end
	end

	-- Shotgun mag tube under the barrel.
	if s.mag == "tube" then
		b:cyl(
			"Tube",
			s.guard + 0.05,
			s.bd * 0.8,
			CFrame.new(0, by - s.bd / 2 - 0.1, front - (s.guard + 0.05) / 2),
			DARK,
			metalMat
		)
	end

	-- Top rail.
	if s.rail then
		b:box("Rail", Vector3.new(W * 0.45, 0.05, L * 0.9), CFrame.new(0, top + 0.025, 0), DARK, metalMat)
	end

	-- Optics.
	local sightY = top
	if s.sight == "red" then
		local base = top + (if s.rail then 0.05 else 0)
		b:box("SightBase", Vector3.new(W * 0.6, 0.06, 0.32), CFrame.new(0, base + 0.03, -L * 0.05), DARK, metalMat)
		local body = b:box(
			"RedDot",
			Vector3.new(W * 0.7, 0.24, 0.3),
			CFrame.new(0, base + 0.18, -L * 0.05),
			Color3.fromHex("1C1D20"),
			metalMat
		)
		local lens = b:box(
			"Lens",
			Vector3.new(W * 0.55, 0.16, 0.02),
			CFrame.new(0, base + 0.19, -L * 0.05 - 0.15),
			Color3.fromHex("FF5A4A"),
			Enum.Material.Glass,
			body
		)
		lens.Transparency = 0.35
		sightY = base + 0.19
	elseif s.sight == "scope" then
		local sl = math.min(L * 0.8, 1.1)
		local sy = top + 0.24
		b:box("ScopeMountF", Vector3.new(0.1, 0.18, 0.1), CFrame.new(0, top + 0.09, -sl * 0.3), DARK, metalMat)
		b:box("ScopeMountR", Vector3.new(0.1, 0.18, 0.1), CFrame.new(0, top + 0.09, sl * 0.25), DARK, metalMat)
		local tube = b:cyl("Scope", sl, 0.17, CFrame.new(0, sy, 0), Color3.fromHex("1A1B1E"), metalMat)
		b:cyl("ScopeBell", 0.3, 0.27, CFrame.new(0, sy, -sl / 2 - 0.1), Color3.fromHex("1A1B1E"), metalMat, tube)
		b:cyl("ScopeEye", 0.2, 0.22, CFrame.new(0, sy, sl / 2 + 0.05), Color3.fromHex("1A1B1E"), metalMat, tube)
		local lens = b:cyl("ScopeLens", 0.02, 0.23, CFrame.new(0, sy, -sl / 2 - 0.26), LENS, Enum.Material.Glass, tube)
		lens.Transparency = 0.15
		b:box(
			"Turret",
			Vector3.new(0.1, 0.12, 0.1),
			CFrame.new(0, sy + 0.12, 0),
			Color3.fromHex("1A1B1E"),
			metalMat,
			tube
		)
		sightY = sy
	elseif s.sight == "carry" then
		b:box("CarryHandle", Vector3.new(W * 0.45, 0.08, L * 0.5), CFrame.new(0, top + 0.22, L * 0.05), DARK, metalMat)
		b:box("CarryPostF", Vector3.new(W * 0.4, 0.2, 0.08), CFrame.new(0, top + 0.1, -L * 0.18), DARK, metalMat)
		b:box("CarryPostR", Vector3.new(W * 0.4, 0.2, 0.08), CFrame.new(0, top + 0.1, L * 0.28), DARK, metalMat)
		sightY = top + 0.26
	end
	root:SetAttribute("SightY", sightY)

	-- Stock.
	local rear = if isPistol then L * 0.43 else L / 2
	local buttZ = rear
	if s.stock == "fixed" or s.stock == "thumb" then
		local sh = H * (if s.stock == "thumb" then 1.25 else 1.05)
		local st = b:box(
			"Stock",
			Vector3.new(W * 0.88, sh, s.stockLen),
			CFrame.new(0, -H * 0.1, rear + s.stockLen / 2),
			furn,
			furnMat
		)
		tag(st, "Wrap")
		if s.stock == "thumb" then
			b:box(
				"ThumbHole",
				Vector3.new(W * 0.92, sh * 0.25, s.stockLen * 0.35),
				CFrame.new(0, -H * 0.02, rear + s.stockLen * 0.3),
				DARK,
				metalMat,
				st
			)
		end
		b:box(
			"ButtPad",
			Vector3.new(W * 0.92, sh * 1.05, 0.08),
			CFrame.new(0, -H * 0.1, rear + s.stockLen + 0.04),
			DARK,
			Enum.Material.Rubber,
			st
		)
		buttZ = rear + s.stockLen + 0.08
	elseif s.stock == "wood" then
		local st = b:box(
			"Stock",
			Vector3.new(W * 0.84, H * 0.85, s.stockLen),
			CFrame.new(0, -H * 0.25, rear + s.stockLen / 2 - 0.02) * CFrame.Angles(math.rad(9), 0, 0),
			furn,
			furnMat
		)
		tag(st, "Wrap")
		b:box(
			"ButtPad",
			Vector3.new(W * 0.86, H * 1.0, 0.06),
			CFrame.new(0, -H * 0.25 - s.stockLen * 0.08, rear + s.stockLen + 0.01) * CFrame.Angles(math.rad(9), 0, 0),
			DARK,
			Enum.Material.Rubber,
			st
		)
		buttZ = rear + s.stockLen + 0.04
	elseif s.stock == "wire" then
		local t = 0.06
		local e = rear + s.stockLen
		b:bar("StockTop", Vector3.new(0, H * 0.25, rear), Vector3.new(0, H * 0.2, e), t, DARK)
		b:bar("StockBottom", Vector3.new(0, -H * 0.4, rear), Vector3.new(0, -H * 0.55, e), t, DARK)
		local pad = b:box("ButtPad", Vector3.new(W * 0.8, H * 0.95, 0.07), CFrame.new(0, -H * 0.18, e), furn, furnMat)
		tag(pad, "Wrap")
		buttZ = e + 0.04
	elseif s.stock == "tube" then
		b:cyl("BufferTube", s.stockLen * 0.7, 0.14, CFrame.new(0, H * 0.12, rear + s.stockLen * 0.35), DARK, metalMat)
		local st = b:box(
			"Stock",
			Vector3.new(W * 0.85, H * 0.95, s.stockLen * 0.5),
			CFrame.new(0, -H * 0.02, rear + s.stockLen * 0.72),
			furn,
			furnMat
		)
		tag(st, "Wrap")
		buttZ = rear + s.stockLen * 0.97
	elseif bullpup then
		-- The receiver is the stock: a butt pad on its rear face.
		b:box(
			"ButtPad",
			Vector3.new(W * 1.02, H * 1.02, 0.08),
			CFrame.new(0, 0, rear + 0.04),
			DARK,
			Enum.Material.Rubber
		)
		buttZ = rear + 0.08
	end
	attach(root, "Butt", CFrame.new(0, if bullpup then 0 else -H * 0.1, buttZ))
	root:SetAttribute("ButtZ", buttZ)

	-- Magazine.
	local mz = if bullpup then L * 0.22 elseif isPistol then gz else -L * 0.12
	local magPart: Part? = nil
	local magWell = CFrame.new(0, bottom, mz)
	local magColor = if s.furnMat == "Wood" then metal else furn
	if s.mag == "stick" or s.mag == "small" then
		local ml = s.magLen
		local cf = CFrame.new(0, bottom, mz) * CFrame.Angles(math.rad(7), 0, 0) * CFrame.new(0, -ml / 2 + 0.06, 0)
		magPart =
			b:box("Mag", Vector3.new(W * 0.66, ml, if s.mag == "small" then 0.42 else 0.32), cf, magColor, metalMat)
	elseif s.mag == "curved" then
		-- A banana: three segments, each canted further forward.
		local segL = s.magLen / 3
		local p = Vector3.new(0, bottom + 0.06, mz)
		local first: Part? = nil
		for i, deg in { 6, 18, 30 } do
			local a = math.rad(deg)
			local d = Vector3.new(0, -math.cos(a), -math.sin(a))
			local seg = b:box(
				if i == 1 then "Mag" else "MagSeg",
				Vector3.new(W * 0.66, segL + 0.03, 0.32),
				CFrame.new(p + d * segL / 2) * CFrame.Angles(a, 0, 0),
				magColor,
				metalMat,
				first
			)
			if i == 1 then
				first = seg
			end
			p += d * segL
		end
		magPart = first
	elseif s.mag == "drum" then
		local drum = b:box("Mag", Vector3.new(W * 0.6, 0.2, 0.2), CFrame.new(0, bottom - 0.1, mz), magColor, metalMat)
		local disc =
			newPart("Drum", Vector3.new(W * 1.15, 0.78, 0.78), CFrame.new(0, bottom - 0.5, mz), magColor, metalMat)
		disc.Shape = Enum.PartType.Cylinder
		local wd = Instance.new("Weld")
		wd.Part0 = drum
		wd.Part1 = disc
		wd.C0 = drum.CFrame:ToObjectSpace(disc.CFrame)
		wd.Parent = disc
		disc.Parent = drum
		magPart = drum
	elseif s.mag == "box" then
		-- Belt-fed: the ammo box hangs off the left side under the receiver.
		magPart = b:box(
			"Mag",
			Vector3.new(W * 1.5, s.magLen, 0.6),
			CFrame.new(-W * 0.35, bottom - s.magLen / 2 + 0.04, mz),
			Color3.fromHex("4F5B3A"),
			Enum.Material.Fabric
		)
	elseif s.mag == "pistol" then
		-- Hidden in the grip; only the base plate shows under it.
		magPart =
			b:box("Mag", Vector3.new(W * 0.7, gripH * 0.96, 0.26), gripCF * CFrame.new(0, -0.04, 0.01), DARK, metalMat)
		magWell = gripCF * CFrame.new(0, -gripH / 2, 0)
	elseif s.mag == "grip" then
		local ml = gripH + s.magLen
		magPart = b:box(
			"Mag",
			Vector3.new(W * 0.62, ml, 0.24),
			gripCF * CFrame.new(0, -s.magLen / 2 - 0.02, 0.01),
			DARK,
			metalMat
		)
		magWell = gripCF * CFrame.new(0, -gripH / 2, 0)
	elseif s.mag == "top" then
		local tm = b:box(
			"Mag",
			Vector3.new(W * 0.9, 0.12, L * 0.6),
			CFrame.new(0, top + 0.06, -L * 0.1),
			Color3.fromHex("3A3A3A"),
			Enum.Material.Glass
		)
		tm.Transparency = 0.25
		magPart = tm
		magWell = CFrame.new(0, top, -L * 0.1)
	elseif s.mag == "tube" then
		magWell = CFrame.new(0, bottom - 0.02, -L * 0.1) -- the loading port
	elseif s.mag == "none" then
		magWell = CFrame.new(0, top + 0.04, L * 0.05) -- loaded from the top (stripper clip / breech)
		if s.action == "break" then
			magWell = CFrame.new(0, by, front + 0.04)
		end
	end
	if magPart then
		b:motor(magPart)
	end
	attach(root, "MagWell", magWell)

	-- Action pieces.
	if s.action == "bolt" then
		local bz = L * 0.3
		local handle =
			b:box("Bolt", Vector3.new(0.26, 0.06, 0.06), CFrame.new(W / 2 + 0.13, H * 0.22, bz), metal, metalMat)
		local knob =
			newPart("BoltKnob", Vector3.new(0.13, 0.13, 0.13), CFrame.new(W / 2 + 0.27, H * 0.18, bz), DARK, metalMat)
		knob.Shape = Enum.PartType.Ball
		local wd = Instance.new("Weld")
		wd.Part0 = handle
		wd.Part1 = knob
		wd.C0 = handle.CFrame:ToObjectSpace(knob.CFrame)
		wd.Parent = knob
		knob.Parent = handle
		b:motor(handle, CFrame.new(W / 2, H * 0.22, bz))
	elseif s.action == "lever" then
		local lever =
			b:box("Lever", Vector3.new(W * 0.3, 0.06, 0.42), CFrame.new(0, bottom - 0.24, gz - 0.12), DARK, metalMat)
		b:box(
			"LeverLoop",
			Vector3.new(W * 0.3, 0.2, 0.06),
			CFrame.new(0, bottom - 0.14, gz + 0.08),
			DARK,
			metalMat,
			lever
		)
		b:motor(lever, CFrame.new(0, bottom - 0.04, gz - 0.33))
	elseif s.action == "auto" and not isPistol then
		local ch = b:box(
			"Charge",
			Vector3.new(0.12, 0.07, 0.1),
			CFrame.new(W / 2 + 0.06, H * 0.25, if bullpup then -L * 0.25 else L * 0.15),
			DARK,
			metalMat
		)
		b:motor(ch)
	end

	-- Bipod legs folded under the handguard.
	if s.bipod then
		local z0 = front - s.guard * 0.85
		for _, side in { -1, 1 } do
			b:bar(
				"BipodLeg",
				Vector3.new(side * W * 0.25, gy - gh / 2 - 0.04, z0),
				Vector3.new(side * W * 0.35, gy - gh / 2 - 0.08, z0 + 0.5),
				0.05,
				DARK
			)
		end
	end

	-- Left hand: under the handguard / pump / forend, a cupped grip for pistols and stubby SMGs.
	local fore: CFrame
	local foreParent: BasePart = root
	local palmUp = CFrame.fromMatrix(Vector3.zero, Vector3.yAxis, Vector3.zAxis, Vector3.xAxis)
	if isPistol or (s.guard <= 0.15 and not bullpup) then
		fore = gripCF * CFrame.new(-0.22, -0.06, -0.06)
	elseif guardPart then
		local gp = guardPart :: Part
		foreParent = gp
		local fz = if s.action == "pump" or s.action == "break"
			then gp.CFrame.Position.Z
			else front - math.min(s.guard * 0.25, 0.2)
		fore = CFrame.new(0, gp.CFrame.Position.Y - gp.Size.Y / 2 - 0.08, fz) * palmUp
	else
		fore = CFrame.new(0, bottom - 0.08, front + 0.2) * palmUp
	end
	attach(foreParent, "Foregrip", fore)
	if barrelsPart then
		barrelsPart:SetAttribute("Breaks", true)
	end

	GunModels.setRarity(root, o.rarity or (Weapons.ById[weaponId] and Weapons.ById[weaponId].rarity) or 1)
	if o.wrapId then
		GunModels.applyWrap(root, o.wrapId)
	end
	return root
end

-- Every BasePart of a gun (the root and its pieces).
function GunModels.parts(root: BasePart): { BasePart }
	local out: { BasePart } = { root }
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(out, d)
		end
	end
	return out
end

function GunModels.setRarity(root: BasePart, rarity: number)
	local c = Rarity.color(rarity)
	for _, p in GunModels.parts(root) do
		if p:GetAttribute("Rarity") == true then
			p.Color = c
			p.Material = if rarity >= Rarity.Epic then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end
	end
end

-- Paint the Wrap parts: a colour (and material), or nil to put back each part's own furniture.
function GunModels.paint(root: BasePart, color: Color3?, material: Enum.Material?)
	for _, p in GunModels.parts(root) do
		if p:GetAttribute("Wrap") == true then
			if color then
				p.Color = color
				p.Material = material or Enum.Material.SmoothPlastic
			else
				local base = p:GetAttribute("BaseColor")
				local bm = p:GetAttribute("BaseMaterial")
				if typeof(base) == "Color3" then
					p.Color = base
				end
				p.Material = if typeof(bm) == "string" then mat(bm) else Enum.Material.SmoothPlastic
			end
		end
	end
end

function GunModels.applyWrap(root: BasePart, wrapId: string?)
	local w = wrapId and Wraps.ById[wrapId]
	if w then
		GunModels.paint(root, Color3.fromHex(w.color), Wraps.material(w))
	else
		GunModels.paint(root, nil)
	end
end

-- The Wrap parts' current look, to put back after a preview.
export type Snapshot = { [BasePart]: { color: Color3, material: Enum.Material } }
function GunModels.snapshot(root: BasePart): Snapshot
	local snap: Snapshot = {}
	for _, p in GunModels.parts(root) do
		if p:GetAttribute("Wrap") == true then
			snap[p] = { color = p.Color, material = p.Material }
		end
	end
	return snap
end

function GunModels.restore(snap: Snapshot)
	for p, v in snap do
		if p.Parent then
			p.Color = v.color
			p.Material = v.material
		end
	end
end

-- Move a built (or unparented) gun so its root sits at `cf`, carrying every piece along.
function GunModels.pivot(root: BasePart, cf: CFrame)
	local inv = root.CFrame:Inverse()
	for _, p in GunModels.parts(root) do
		if p ~= root then
			p.CFrame = cf * (inv * p.CFrame)
		end
	end
	root.CFrame = cf
end

-- Hand-carry rest pose: the C0 of the hand -> gun Motor6D when nothing animates it (the hub, store mannequins,
-- crew line-ups). The gun points along the hand's forward with the grip in the palm, like the old held block.
function GunModels.restC0(root: BasePart): CFrame
	local g = root:FindFirstChild("Grip")
	local gp = if g and g:IsA("Attachment") then g.Position else Vector3.new(0, -0.4, 0.3)
	return CFrame.new(0, -0.2, 0) * CFrame.new(-gp)
end

-- Joins a gun to a character's right hand with the "GunJoint" Motor6D (in the rest pose). Returns the motor.
function GunModels.mountToHand(root: BasePart, hand: BasePart): Motor6D
	root.Anchored = false
	local c0 = GunModels.restC0(root)
	if hand.Name == "Right Arm" then
		c0 = CFrame.new(0, -hand.Size.Y / 2 + 0.25, 0) * c0 -- R6: the "hand" is the end of the arm
	end
	GunModels.pivot(root, hand.CFrame * c0)
	local m = Instance.new("Motor6D")
	m.Name = "GunJoint"
	m.Part0 = hand
	m.Part1 = root
	m.C0 = c0
	m.C1 = CFrame.identity
	m.Parent = root
	return m
end

-- A gun as a Model (PrimaryPart = Body), centred on its bounding box, muzzle toward -X: the store / icon layout.
function GunModels.model(weaponId: string, opts: Opts?): Model
	local root = GunModels.build(weaponId, opts)
	local m = Instance.new("Model")
	m.Name = "Gun"
	root.Parent = m
	m.PrimaryPart = root
	local cf, _size = m:GetBoundingBox()
	-- Recentre: the box centre to the origin, then turn so the muzzle (-Z) faces -X.
	local offset = cf.Position
	GunModels.pivot(root, CFrame.Angles(0, math.rad(90), 0) * CFrame.new(-offset))
	return m
end

return GunModels
