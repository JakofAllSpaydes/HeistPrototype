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
	sight: string, -- iron | red | holo | acog | medium | scope | carry | none (Round 24r/u: medium = mid scope, scope = snipers only)
	muzzle: string, -- Round 24r: none | flash | comp | supp (flash hider, compensator, suppressor)
	revolver: boolean, -- Round 24s: a pistol with a cylinder and hammer instead of a moving slide
	shroud: boolean, -- Round 24s: a perforated barrel shroud (MG42 style) over the front of the barrel
	body: string, -- Round 24w: receiver silhouette: slab | stepped | humped | tapered | round | boxy | tall
	special: string, -- Round 24v: launcher / elemental dressing: rpg | mgl | cluster | flamer | cryo | tesla | plasma
	custom: string, -- Round 24v: a gun that isn't a gun (tnt)
	profile: string, -- Round 24aa: a named silhouette for a gun whose real shape is iconic (deagle)
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
	launcher = {
		len = 0.9,
		h = 0.5,
		w = 0.32,
		guard = 0.3,
		barrel = 0.2,
		bd = 0.3,
		grip = 0.55,
		stock = "fixed",
		stockLen = 0.5,
		mag = "none",
		magLen = 0,
		sight = "bare",
		action = "auto",
	},
	energy = {
		len = 1.1,
		h = 0.56,
		w = 0.36,
		guard = 0.55,
		barrel = 0.2,
		bd = 0.18,
		grip = 0.55,
		stock = "fixed",
		stockLen = 0.5,
		mag = "none",
		magLen = 0,
		sight = "bare",
		action = "auto",
	},
	thrown = {
		len = 0.6,
		h = 0.4,
		w = 0.4,
		guard = 0,
		barrel = 0,
		bd = 0.1,
		grip = 0.3,
		stock = "none",
		stockLen = 0,
		mag = "none",
		magLen = 0,
		sight = "bare",
		action = "auto",
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
	Explosive = "launcher",
	Elemental = "energy",
}

-- Per-gun overrides on top of the archetype's kind. Colours: steel 2E3036, black polymer 1E1F22, wood 7A4A26.
local SPECS: { [string]: { [string]: any } } = {
	M1911 = { kind = "pistol", metal = "3A3D44", furn = "5A3A22", furnMat = "Wood" },
	Glock = { kind = "pistol", len = 1.0, metal = "26272B", furn = "1E1F22" },
	Deagle = {
		kind = "pistol",
		profile = "deagle",
		len = 1.3,
		h = 0.56,
		w = 0.32,
		grip = 0.72,
		sight = "red",
		rail = true,
		metal = "B8BCC2",
		furn = "1E1F22",
		barrel = 0,
	},
	Gold1911 = { kind = "pistol", metal = "E8B64C", furn = "3B2414", furnMat = "Wood" },
	Hornet = { kind = "pistol", metal = "3B3F4A", furn = "202430", rail = true, muzzle = "supp", sight = "holo" },
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
	MP5 = {
		kind = "smg",
		guard = 0.5,
		barrel = 0.12,
		mag = "curved",
		magLen = 0.66,
		sight = "holo",
		muzzle = "supp",
		metal = "2A2C31",
		furn = "1E1F22",
	},
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
		sight = "acog",
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
		sight = "red",
		mag = "curved",
		magLen = 0.5,
		metal = "2E3036",
		furn = "6E5A3A",
		furnMat = "Wood",
	},
	StormLinker = { kind = "smg", sight = "red", rail = true, muzzle = "flash", metal = "3B3F4A", furn = "202430" },
	["AK-47"] = {
		kind = "rifle",
		body = "humped",
		mag = "curved",
		stock = "wood",
		muzzle = "comp",
		metal = "2E3036",
		furn = "7A4A26",
		furnMat = "Wood",
	},
	M4A1 = {
		kind = "rifle",
		body = "stepped",
		stock = "tube",
		sight = "red",
		rail = true,
		muzzle = "flash",
		metal = "26282C",
		furn = "1E1F22",
	},
	["SCAR-H"] = {
		kind = "rifle",
		body = "boxy",
		len = 1.25,
		mag = "stick",
		magLen = 0.6,
		sight = "holo",
		rail = true,
		muzzle = "flash",
		metal = "B59F74",
		furn = "2A2B2E",
	},
	AUG = {
		kind = "bullpup",
		len = 1.8,
		sight = "acog",
		barrel = 0.45,
		muzzle = "flash",
		metal = "2E3036",
		furn = "5C7A52",
	},
	FAL = {
		kind = "rifle",
		body = "tapered",
		len = 1.3,
		guard = 0.8,
		barrel = 0.55,
		magLen = 0.6,
		stock = "wood",
		sight = "medium",
		muzzle = "flash",
		metal = "2E3036",
		furn = "7A4E2D",
		furnMat = "Wood",
	},
	Exogun = {
		kind = "rifle",
		body = "stepped",
		sight = "holo",
		rail = true,
		muzzle = "comp",
		metal = "3B3F4A",
		furn = "202430",
	},
	["SPAS-12"] = { kind = "shotgun", body = "boxy", stock = "wire", metal = "2A2B2E", furn = "1E1F22" },
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
		body = "round",
		action = "lever",
		stock = "wood",
		metal = "2E3036",
		furn = "8A5A2B",
		furnMat = "Wood",
	},
	AWP = { kind = "sniper", body = "round", brake = true, metal = "2E3036", furn = "4F5B3A" },
	M82 = {
		kind = "sniper",
		body = "boxy",
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
		body = "round",
		action = "bolt",
		len = 1.3,
		guard = 1.2,
		barrel = 0.5,
		stock = "wood",
		mag = "none",
		sight = "medium", -- Round 24u: mid zoom for variety (the AWP / M82 / Railcaster keep the sniper glass)
		metal = "2E3036",
		furn = "5A3A22",
		furnMat = "Wood",
	},
	Railcaster = { kind = "sniper", body = "boxy", muzzle = "supp", metal = "3B3F4A", furn = "202430" },
	M249 = { kind = "lmg", body = "tall", muzzle = "flash", metal = "2E3036", furn = "1E1F22" },
	-- Round 24s: more pistols / shotguns / snipers / LMGs.
	Python = {
		kind = "pistol",
		len = 1.15,
		h = 0.5,
		barrel = 0.35,
		revolver = true,
		mag = "none",
		metal = "8C9096",
		furn = "5A3A22",
		furnMat = "Wood",
	},
	M93R = {
		kind = "pistol",
		len = 1.15,
		barrel = 0.08,
		muzzle = "comp",
		rail = true,
		metal = "2A2C31",
		furn = "1E1F22",
	},
	AA12 = {
		kind = "shotgun",
		body = "stepped",
		len = 1.15,
		h = 0.56,
		guard = 0.55,
		barrel = 0.3,
		action = "auto",
		mag = "drum",
		stock = "fixed",
		sight = "holo",
		rail = true,
		muzzle = "flash",
		metal = "3A3D44",
		furn = "1E1F22",
	},
	M870 = {
		kind = "shotgun",
		sight = "red",
		rail = true,
		guard = 0.85,
		barrel = 0.55,
		stock = "wood",
		metal = "26282C",
		furn = "6B4226",
		furnMat = "Wood",
	},
	SVD = {
		kind = "sniper",
		body = "tapered",
		len = 1.3,
		guard = 0.85,
		barrel = 0.75,
		action = "auto",
		mag = "curved",
		magLen = 0.45,
		sight = "medium",
		stock = "wood",
		muzzle = "flash",
		metal = "2E3036",
		furn = "8A4E2A",
		furnMat = "Wood",
	},
	Kar98k = {
		kind = "sniper",
		body = "round",
		len = 1.25,
		guard = 1.25,
		barrel = 0.45,
		stock = "wood",
		mag = "none",
		sight = "iron",
		metal = "2E3036",
		furn = "6E4A2A",
		furnMat = "Wood",
	},
	PKM = {
		kind = "lmg",
		body = "tall",
		len = 1.3,
		h = 0.52,
		guard = 0.35,
		barrel = 0.85,
		mag = "box",
		stock = "wire",
		sight = "acog",
		rail = true,
		muzzle = "flash",
		metal = "2E3036",
		furn = "6B4226",
		furnMat = "Wood",
	},
	MG42 = {
		kind = "lmg",
		body = "tall",
		len = 1.35,
		h = 0.5,
		guard = 0.1,
		barrel = 0.95,
		shroud = true,
		mag = "box",
		stock = "fixed",
		sight = "iron",
		metal = "2A2B2E",
		furn = "4A3020",
		furnMat = "Wood",
	},
	-- Round 24v: Explosive / Elemental.
	RPG7 = {
		kind = "launcher",
		len = 0.8,
		h = 0.42,
		w = 0.3,
		guard = 0,
		barrel = 0,
		stock = "none",
		special = "rpg",
		metal = "4F5B3A",
		furn = "6B4226",
		furnMat = "Wood",
	},
	M32 = {
		kind = "launcher",
		len = 0.75,
		guard = 0.12,
		barrel = 0.35,
		bd = 0.32,
		stock = "tube",
		stockLen = 0.6,
		sight = "red",
		rail = true,
		special = "mgl",
		metal = "3A3D44",
		furn = "1E1F22",
	},
	ClusterLauncher = {
		kind = "launcher",
		len = 1.0,
		guard = 0.7,
		barrel = 0.35,
		bd = 0.3,
		action = "pump",
		mag = "tube",
		sight = "holo",
		rail = true,
		special = "cluster",
		body = "boxy",
		metal = "3A3D44",
		furn = "C2672A",
	},
	TNT = { kind = "thrown", custom = "tnt", metal = "B3261E", furn = "6B4226" },
	Flamethrower = {
		kind = "energy",
		special = "flamer",
		barrel = 0.3,
		bd = 0.24,
		metal = "3A3D44",
		furn = "8A2A1E",
		body = "boxy",
	},
	CryoSprayer = {
		kind = "energy",
		special = "cryo",
		barrel = 0.25,
		bd = 0.26,
		metal = "C9D6E0",
		furn = "2A3A4A",
		body = "stepped",
	},
	ArcGun = {
		kind = "energy",
		special = "tesla",
		guard = 0.35,
		barrel = 0.45,
		bd = 0.14,
		metal = "2E3036",
		furn = "1E2A3A",
		body = "tapered",
	},
	PlasmaCaster = {
		kind = "energy",
		special = "plasma",
		sight = "holo",
		rail = true,
		metal = "2A2B2E",
		furn = "1E3A2A",
		body = "stepped",
	},
	RPK = {
		kind = "lmg",
		body = "humped",
		len = 1.25,
		h = 0.5,
		mag = "drum",
		stock = "wood",
		sight = "iron",
		muzzle = "comp",
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
		muzzle = "none",
		revolver = false,
		shroud = false,
		body = "slab",
		special = "",
		custom = "",
		profile = "",
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
	if s.sight == "scope" and kindName ~= "sniper" then
		s.sight = "medium" -- Round 24u: the full sniper zoom is snipers only
	end
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
	wedge: (
		self: Builder,
		name: string,
		size: Vector3,
		cf: CFrame,
		color: Color3,
		m: Enum.Material,
		parent: BasePart?
	) -> BasePart,
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
	-- Round 24t: a wedge (full height at +Z, sloping to nothing at -Z) for sloped noses and chamfers.
	function b.wedge(_self, name, size, cf, color, m, parent)
		local w = Instance.new("WedgePart")
		w.Name = name
		w.Size = size
		w.CFrame = cf
		w.Color = color
		w.Material = m
		w.Anchored = false
		w.CanCollide = false
		w.CanQuery = false
		w.CanTouch = false
		w.Massless = true
		w.CastShadow = true
		join(w, parent)
		return w
	end
	-- A square rod from a to b.
	function b.bar(_self, name, a, c, t, color, parent)
		local len = (c - a).Magnitude
		-- Round 24ab: a vertical rod has no usable default up for lookAt (a NaN frame): use +Z as up then.
		local dir = c - a
		local up = if len > 0 and math.abs(dir.Unit.Y) > 0.98 then Vector3.zAxis else Vector3.yAxis
		local p = newPart(name, Vector3.new(t, t, len), CFrame.lookAt((a + c) / 2, c, up), color, Enum.Material.Metal)
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

	if s.custom == "tnt" then
		-- Round 24v: a TNT bundle: three red sticks in tape with a lit fuse. Held like a pistol (grip under the
		-- middle); the attachments every gun has are there so the animator, the viewmodel and the tracer all work.
		local root = newPart(
			"Body",
			Vector3.new(0.5, 0.18, 0.7),
			CFrame.identity,
			Color3.fromHex("C9B79A"),
			Enum.Material.Fabric
		)
		root.Anchored = o.anchored == true
		root:SetAttribute("GunKind", "thrown")
		root:SetAttribute("GunAction", "auto")
		root:SetAttribute("GunMag", "none")
		root:SetAttribute("WeaponId", weaponId)
		local b = builder(root)
		local red = Color3.fromHex("B3261E")
		for i, x in { -0.16, 0, 0.16 } do
			local y = if i == 2 then 0.2 else 0.08
			b:cyl("Stick", 0.72, 0.17, CFrame.new(x, y, 0), red, Enum.Material.SmoothPlastic)
			b:cyl(
				"StickCap",
				0.03,
				0.18,
				CFrame.new(x, y, -0.36),
				Color3.fromHex("E8DCC0"),
				Enum.Material.SmoothPlastic
			)
			b:cyl("StickCap", 0.03, 0.18, CFrame.new(x, y, 0.36), Color3.fromHex("E8DCC0"), Enum.Material.SmoothPlastic)
		end
		for _, z in { -0.2, 0.2 } do
			b:box(
				"Tape",
				Vector3.new(0.52, 0.36, 0.07),
				CFrame.new(0, 0.12, z),
				Color3.fromHex("2A2B2E"),
				Enum.Material.Fabric
			)
		end
		b:bar("Fuse", Vector3.new(0, 0.28, -0.36), Vector3.new(0.05, 0.42, -0.5), 0.03, Color3.fromHex("6B5A3A"))
		b:box(
			"Spark",
			Vector3.new(0.06, 0.06, 0.06),
			CFrame.new(0.05, 0.44, -0.52),
			Color3.fromHex("FFB13B"),
			Enum.Material.Neon
		)
		attach(root, "Grip", CFrame.new(0, -0.1, 0.05))
		attach(root, "Muzzle", CFrame.new(0, 0.12, -0.42))
		attach(root, "Butt", CFrame.new(0, 0, 0.4))
		attach(root, "MagWell", CFrame.new(0, 0.3, 0))
		root:SetAttribute("Sight", "bare")
		root:SetAttribute("SightY", 0.3)
		root:SetAttribute("SightZ", 0.4)
		root:SetAttribute("ButtZ", 0.4)
		GunModels.setRarity(root, o.rarity or (Weapons.ById[weaponId] and Weapons.ById[weaponId].rarity) or 1)
		return root
	end

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
	-- Round 24aa: the receiver's own top (top0) and the top the sights, rails and optics sit on (top): a body shape
	-- that rises above the receiver (Round 24w) lifts everything on top with it, so the sight line clears it.
	local top0 = top
	if not isPistol then
		local raise = ({
			stepped = H * 0.22,
			humped = W * 0.34,
			tapered = H * 0.24,
			round = W * 0.53,
			boxy = H * 0.3,
			tall = H * 0.34,
		} :: any)[s.body] or 0
		top += raise
	end
	local bottom = if isPistol then -H * 0.225 else -H / 2
	local front = if isPistol then -L * 0.43 else -L / 2

	-- Pistol slide (moves on every shot).
	local slide: Part? = nil
	if isPistol then
		local deagle = s.profile == "deagle"
		slide = b:box(
			"Slide",
			Vector3.new(W * 1.04, H * 0.55, if deagle then L * 0.52 else L),
			CFrame.new(0, H * 0.225 + H * 0.275, if deagle then L * 0.17 else -L * 0.07),
			metal,
			metalMat
		)
		local sl = slide :: Part
		if deagle then
			-- Round 24aa: the Desert Eagle's read. The slide is only the rear half; in front, a long squared barrel
			-- block (static: the real one's barrel doesn't move), full width low and narrowing at the top on sloped
			-- sides, ending in a flat face with the bore in it; an exposed hammer at the back.
			local zf, zb = -L * 0.64, -L * 0.09 -- barrel block front / back
			local bl = zb - zf
			local bz = (zf + zb) / 2
			local y0 = H * 0.225 -- bottom of the slide line
			local lowH, upH = H * 0.32, H * 0.23
			local block =
				b:box("BarrelBlock", Vector3.new(W * 1.02, lowH, bl), CFrame.new(0, y0 + lowH / 2, bz), metal, metalMat)
			b:box(
				"BarrelTop",
				Vector3.new(W * 0.58, upH, bl),
				CFrame.new(0, y0 + lowH + upH / 2, bz),
				metal,
				metalMat,
				block
			)
			local sideW = (W * 1.02 - W * 0.58) / 2
			for _, side in { -1, 1 } do
				-- Wedges filling the upper corners, high at the centre, sloping down to the sides.
				local rot = CFrame.Angles(0, math.rad(if side < 0 then 90 else -90), 0)
				b:wedge(
					"BarrelSlope",
					Vector3.new(bl, upH, sideW),
					CFrame.new(side * (W * 0.29 + sideW / 2), y0 + lowH + upH / 2, bz) * rot,
					metal,
					metalMat,
					block
				)
			end
			b:cyl("Bore", 0.03, H * 0.2, CFrame.new(0, y0 + lowH * 0.75, zf - 0.012), DARK, metalMat, block)
			b:box("FrameStep", Vector3.new(W * 1.06, 0.035, bl), CFrame.new(0, y0 + 0.02, bz), DARK, metalMat, block)
			b:box(
				"Hammer",
				Vector3.new(W * 0.4, 0.14, 0.12),
				CFrame.new(0, H * 0.72, L * 0.45) * CFrame.Angles(math.rad(-30), 0, 0),
				DARK,
				metalMat
			)
		end
		if s.revolver then
			-- Round 24s: a revolver. The "slide" is the static top strap; a fluted cylinder sits in front of the
			-- grip and a hammer at the back.
			local cy = H * 0.3
			local cyl = b:cyl("Cylinder", L * 0.34, H * 0.62, CFrame.new(0, cy, L * 0.02), metal, metalMat)
			for i = 0, 5 do
				local a = i * math.pi / 3
				b:box(
					"Flute",
					Vector3.new(0.03, 0.03, L * 0.3),
					CFrame.new(math.sin(a) * H * 0.3, cy + math.cos(a) * H * 0.3, L * 0.02),
					DARK,
					metalMat,
					cyl
				)
			end
			b:box(
				"Hammer",
				Vector3.new(W * 0.35, 0.12, 0.1),
				CFrame.new(0, top - 0.02, L * 0.45) * CFrame.Angles(math.rad(-25), 0, 0),
				DARK,
				metalMat
			)
			b:box(
				"TopRib",
				Vector3.new(W * 0.5, 0.05, L * 0.9),
				CFrame.new(0, top + 0.02, -L * 0.1),
				DARK,
				metalMat,
				sl
			)
			front = -L * 0.57
		end
	end
	if isPistol and slide and not s.revolver then
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
		front = if s.profile == "deagle" then -L * 0.64 else -L * 0.57
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
	local rake = if s.mag == "grip" then math.rad(-6) elseif s.profile == "deagle" then math.rad(-21) else math.rad(-16)
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
	if s.shroud then
		-- Round 24s: a perforated barrel shroud over the front of the barrel, two rows of cooling holes a side.
		local sl = s.barrel * 0.85
		local sz = front - sl / 2 - 0.02
		local shroud = b:cyl("Shroud", sl, s.bd * 2.3, CFrame.new(0, by, sz), metal, metalMat)
		local holes = math.max(4, math.floor(sl / 0.13))
		for i = 0, holes - 1 do
			local z = front - 0.08 - i * (sl - 0.12) / math.max(holes - 1, 1)
			for _, side in { -1, 1 } do
				for _, dy in { -0.35, 0.35 } do
					b:box(
						"ShroudHole",
						Vector3.new(0.02, s.bd * 0.45, 0.06),
						CFrame.new(side * s.bd * 1.16, by + dy * s.bd, z),
						Color3.fromHex("0C0C0E"),
						metalMat,
						shroud
					)
				end
			end
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
	elseif s.muzzle == "flash" and s.action ~= "break" then
		-- Round 24r: a slotted flash hider.
		local fl = 0.2
		b:cyl("FlashHider", fl, s.bd * 1.25, CFrame.new(0, by, muzzleZ - fl / 2), DARK, metalMat)
		for i = 0, 2 do
			local a = i * math.pi * 2 / 3
			b:box(
				"FlashSlot",
				Vector3.new(0.02, s.bd * 0.5, fl * 0.7),
				CFrame.new(math.sin(a) * s.bd * 0.62, by + math.cos(a) * s.bd * 0.62, muzzleZ - fl * 0.55)
					* CFrame.Angles(0, 0, -a),
				Color3.fromHex("0C0C0E"),
				metalMat
			)
		end
		muzzleZ -= fl
	elseif s.muzzle == "comp" and s.action ~= "break" then
		-- Round 24r: a boxy compensator with side ports.
		local cl = 0.22
		b:box("Comp", Vector3.new(s.bd * 1.5, s.bd * 1.4, cl), CFrame.new(0, by, muzzleZ - cl / 2), DARK, metalMat)
		for _, side in { -1, 1 } do
			for j = 0, 1 do
				b:box(
					"CompPort",
					Vector3.new(0.02, s.bd * 0.8, 0.04),
					CFrame.new(side * s.bd * 0.76, by, muzzleZ - 0.06 - j * 0.09),
					Color3.fromHex("0C0C0E"),
					metalMat
				)
			end
		end
		muzzleZ -= cl
	elseif s.muzzle == "supp" and s.action ~= "break" then
		-- Round 24r: a long suppressor can.
		local sl = if isPistol then 0.55 else 0.75
		b:cyl("Suppressor", sl, s.bd * 1.9, CFrame.new(0, by, muzzleZ - sl / 2), Color3.fromHex("1F2023"), metalMat)
		b:cyl("SuppressorCap", 0.04, s.bd * 1.95, CFrame.new(0, by, muzzleZ - sl + 0.02), DARK, metalMat)
		muzzleZ -= sl
	end
	attach(root, "Muzzle", CFrame.new(0, by, muzzleZ - 0.04))

	-- Round 24e/g: iron sights shaped after real ones. The aim line (ironSL, published as SightY) is where the
	-- front post's tip sits: for a notch it is level with the top of the rear sight, for a ring it is the ring's
	-- centre. Styles: pistol = a wide low rear block with a square notch and two dots, a thin post with a dot;
	-- smg / rifle / lmg / bullpup = a round rear ring between two tall wings, a post between two close ears
	-- (the "M" through the ring); shotgun = a bead in a shallow groove; carry handles = the ring on the handle.
	local ironSL: number? = nil
	local sightZ = L * 0.3 -- the rear of the sight picture (gun space Z): first-person ADS measures eye relief from it
	if s.sight == "iron" or s.sight == "none" or s.sight == "carry" then
		local notch = isPistol or s.kind == "shotgun"
		local SL = if s.sight == "carry"
			then top + 0.34
			elseif isPistol then top + 0.09
			elseif notch then top + 0.06
			else top + 0.11
		ironSL = SL
		local fz = if s.guard > 0 then front - s.guard - 0.02 else front + 0.08
		local base = by + s.bd / 2 - 0.02
		local WHITE = Color3.new(1, 1, 1)
		local NEON = Enum.Material.Neon

		-- Front.
		if s.kind == "shotgun" then
			b:box(
				"FrontStalk",
				Vector3.new(0.03, SL - base, 0.03),
				CFrame.new(0, (SL + base) / 2 - 0.02, fz),
				DARK,
				metalMat
			)
			b:box(
				"FrontSight",
				Vector3.new(0.05, 0.05, 0.05),
				CFrame.new(0, SL - 0.005, fz),
				Color3.fromHex("E8DDB0"),
				NEON
			)
		elseif isPistol then
			b:box("FrontSight", Vector3.new(0.035, SL - base, 0.04), CFrame.new(0, (SL + base) / 2, fz), DARK, metalMat)
			b:box("SightDot", Vector3.new(0.022, 0.022, 0.01), CFrame.new(0, SL - 0.02, fz + 0.022), WHITE, NEON)
		else
			b:box("FrontSight", Vector3.new(0.022, SL - base, 0.03), CFrame.new(0, (SL + base) / 2, fz), DARK, metalMat)
			for _, x in { -1, 1 } do
				b:box(
					"FrontEar",
					Vector3.new(0.018, SL - base + 0.025, 0.04),
					CFrame.new(x * 0.042, (SL + base + 0.025) / 2, fz),
					DARK,
					metalMat
				)
			end
			-- The base the post and ears stand on.
			b:box("FrontBase", Vector3.new(0.11, 0.05, 0.05), CFrame.new(0, base + 0.025, fz), DARK, metalMat)
		end

		-- Rear.
		local rz = if isPistol then L * 0.36 elseif s.sight == "carry" then L * 0.28 else L * 0.32
		sightZ = rz
		if notch then
			local rearW = if isPistol then W * 0.95 else W * 0.7
			local gap = if isPistol then 0.055 else 0.07
			local depth = if isPistol then 0.045 else 0.03
			local earW = (rearW - gap) / 2
			b:box(
				"RearSight",
				Vector3.new(rearW, SL - depth - top, 0.07),
				CFrame.new(0, (SL - depth + top) / 2, rz),
				DARK,
				metalMat
			)
			for _, x in { -1, 1 } do
				b:box(
					"RearEar",
					Vector3.new(earW, depth, 0.07),
					CFrame.new(x * (gap / 2 + earW / 2), SL - depth / 2, rz),
					DARK,
					metalMat
				)
				if isPistol then
					b:box(
						"SightDot",
						Vector3.new(0.022, 0.022, 0.01),
						CFrame.new(x * (gap / 2 + earW / 2), SL - 0.03, rz + 0.04),
						WHITE,
						NEON
					)
				end
			end
		else
			local rearBase = if s.sight == "carry" then top + 0.24 else top
			-- Round 24aa: a ghost ring: a bigger hole and a thin ring, short wings that only guard the lower half,
			-- so aiming through it keeps most of the view (the thick ring and tall wings blocked ~45% of it).
			local r = 0.055 -- the hole's radius
			local bar = 0.014
			-- The ring: eight short bars round the hole.
			for i = 0, 7 do
				local a = i * math.pi / 4
				local c = CFrame.new(0, SL, rz) * CFrame.Angles(0, 0, a) * CFrame.new(0, r + bar / 2, 0)
				b:box("RearRing", Vector3.new(r * 0.95, bar, 0.035), c, DARK, metalMat)
			end
			-- Post under the ring and the tall wings either side.
			b:box(
				"RearSight",
				Vector3.new(0.05, SL - r - rearBase, 0.05),
				CFrame.new(0, (SL - r + rearBase) / 2, rz),
				DARK,
				metalMat
			)
			local wingH = SL - r * 0.3 - rearBase
			for _, x in { -1, 1 } do
				b:box(
					"RearWing",
					Vector3.new(0.022, wingH, 0.06),
					CFrame.new(x * (r + bar + 0.035), rearBase + wingH / 2, rz),
					DARK,
					metalMat
				)
			end
			b:box(
				"RearBase",
				Vector3.new(r * 2 + bar * 2 + 0.17, 0.04, 0.08),
				CFrame.new(0, rearBase + 0.02, rz),
				DARK,
				metalMat
			)
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
		-- Round 24r: picatinny teeth.
		local n = math.max(4, math.floor(L * 0.9 / 0.09))
		for i = 0, n - 1 do
			local z = -L * 0.45 + (i + 0.5) * (L * 0.9 / n)
			b:box("RailTooth", Vector3.new(W * 0.5, 0.025, 0.035), CFrame.new(0, top + 0.06, z), DARK, metalMat)
		end
	end
	-- Round 24r: a charging handle knob on the left of rifles / smgs / lmgs.
	if not isPistol and s.kind ~= "shotgun" and s.action ~= "bolt" then
		b:box(
			"ChargingHandle",
			Vector3.new(0.08, 0.06, 0.1),
			CFrame.new(-W / 2 - 0.04, H * 0.22, if bullpup then L * 0.05 else -L * 0.15),
			DARK,
			metalMat
		)
	end

	-- Optics.
	local sightY = ironSL or top
	if s.sight == "red" then
		-- Round 24r: a tube red dot (Aimpoint style): round body on a riser.
		local base = top + (if s.rail then 0.05 else 0)
		local rz = -L * 0.05
		local body0 = Color3.fromHex("1C1D20")
		b:box("SightBase", Vector3.new(W * 0.5, 0.08, 0.2), CFrame.new(0, base + 0.04, rz), DARK, metalMat)
		local cy = base + 0.2
		local body = b:cyl("RedDot", 0.3, 0.2, CFrame.new(0, cy, rz), body0, metalMat)
		b:cyl("RedDotRing", 0.04, 0.23, CFrame.new(0, cy, rz - 0.14), body0, metalMat, body)
		b:cyl("RedDotRing", 0.04, 0.23, CFrame.new(0, cy, rz + 0.14), body0, metalMat, body)
		b:box("Turret", Vector3.new(0.07, 0.07, 0.07), CFrame.new(0.12, cy, rz), body0, metalMat, body)
		local lens =
			b:cyl("Lens", 0.02, 0.16, CFrame.new(0, cy, rz - 0.16), Color3.fromHex("FF5A4A"), Enum.Material.Glass, body)
		lens.Transparency = 0.4
		b:box(
			"Dot",
			Vector3.new(0.014, 0.014, 0.01),
			CFrame.new(0, cy, rz - 0.17),
			Color3.fromHex("FF2A1A"),
			Enum.Material.Neon,
			body
		)
		sightZ = rz + 0.16
		sightY = cy
	elseif s.sight == "holo" then
		-- Round 24r: a holographic sight (EOTech style): a squared body with an open window under a hood.
		local base = top + (if s.rail then 0.05 else 0)
		local hz = -L * 0.02
		local wh, ww = 0.17, W * 0.75
		local body0 = Color3.fromHex("1C1D20")
		local body =
			b:box("HoloBody", Vector3.new(W * 0.7, 0.07, 0.42), CFrame.new(0, base + 0.035, hz), body0, metalMat)
		for _, x in { -1, 1 } do
			b:box(
				"HoloHood",
				Vector3.new(0.035, wh, 0.36),
				CFrame.new(x * (ww / 2 + 0.017), base + 0.07 + wh / 2, hz - 0.02),
				body0,
				metalMat,
				body
			)
		end
		b:box(
			"HoloHood",
			Vector3.new(ww + 0.07, 0.035, 0.36),
			CFrame.new(0, base + 0.07 + wh + 0.017, hz - 0.02),
			body0,
			metalMat,
			body
		)
		b:box(
			"HoloButtons",
			Vector3.new(W * 0.5, 0.05, 0.1),
			CFrame.new(0, base + 0.095, hz + 0.16),
			DARK,
			metalMat,
			body
		)
		local glass = b:box(
			"HoloGlass",
			Vector3.new(ww, wh, 0.01),
			CFrame.new(0, base + 0.07 + wh / 2, hz - 0.19),
			Color3.fromHex("9FD8FF"),
			Enum.Material.Glass,
			body
		)
		glass.Transparency = 0.7
		sightY = base + 0.07 + wh * 0.55
		sightZ = hz + 0.2
	elseif s.sight == "acog" then
		-- Round 24r: a short fixed-power scope (ACOG style) with a fat objective and a fibre strip on top.
		local sl = 0.5
		local sy = top + 0.2
		local az = -L * 0.02
		local tan = Color3.fromHex("3A3A36")
		b:box("ScopeMountF", Vector3.new(W * 0.45, 0.12, 0.14), CFrame.new(0, top + 0.06, az), DARK, metalMat)
		local tube = b:cyl("Scope", sl, 0.17, CFrame.new(0, sy, az), tan, metalMat)
		b:cyl("ScopeBell", 0.16, 0.25, CFrame.new(0, sy, az - sl / 2 - 0.04), tan, metalMat, tube)
		b:cyl("ScopeEye", 0.1, 0.2, CFrame.new(0, sy, az + sl / 2 + 0.02), tan, metalMat, tube)
		b:box(
			"Turret",
			Vector3.new(0.06, 0.05, sl * 0.6),
			CFrame.new(0, sy + 0.11, az),
			Color3.fromHex("E07A2A"),
			Enum.Material.Neon,
			tube
		)
		local lens =
			b:cyl("ScopeLens", 0.02, 0.21, CFrame.new(0, sy, az - sl / 2 - 0.12), LENS, Enum.Material.Glass, tube)
		lens.Transparency = 0.2
		sightY = sy
		sightZ = az + sl / 2 + 0.12
	elseif s.sight == "medium" then
		-- Round 24u: a mid-power scope: shorter and slimmer than the sniper glass, low turrets, a hooded objective.
		local sl = math.min(L * 0.62, 0.8)
		local sy = top + 0.21
		local mz = -L * 0.02
		b:box("ScopeMountF", Vector3.new(0.09, 0.15, 0.09), CFrame.new(0, top + 0.075, mz - sl * 0.25), DARK, metalMat)
		b:box("ScopeMountR", Vector3.new(0.09, 0.15, 0.09), CFrame.new(0, top + 0.075, mz + sl * 0.22), DARK, metalMat)
		local tube = b:cyl("Scope", sl, 0.15, CFrame.new(0, sy, mz), Color3.fromHex("22242A"), metalMat)
		b:cyl("ScopeBell", 0.2, 0.22, CFrame.new(0, sy, mz - sl / 2 - 0.07), Color3.fromHex("22242A"), metalMat, tube)
		b:cyl("ScopeEye", 0.14, 0.19, CFrame.new(0, sy, mz + sl / 2 + 0.04), Color3.fromHex("22242A"), metalMat, tube)
		b:box(
			"Turret",
			Vector3.new(0.08, 0.08, 0.08),
			CFrame.new(0, sy + 0.1, mz),
			Color3.fromHex("22242A"),
			metalMat,
			tube
		)
		b:box(
			"Turret",
			Vector3.new(0.08, 0.08, 0.08),
			CFrame.new(0.1, sy, mz),
			Color3.fromHex("22242A"),
			metalMat,
			tube
		)
		local lens =
			b:cyl("ScopeLens", 0.02, 0.19, CFrame.new(0, sy, mz - sl / 2 - 0.18), LENS, Enum.Material.Glass, tube)
		lens.Transparency = 0.2
		sightY = sy
		sightZ = mz + sl / 2 + 0.13
	elseif s.sight == "scope" then
		local sl = math.min(L * 0.8, 1.1)
		local sy = top + 0.24
		b:box("ScopeMountF", Vector3.new(0.1, 0.18, 0.1), CFrame.new(0, top + 0.09, -sl * 0.3), DARK, metalMat)
		b:box("ScopeMountR", Vector3.new(0.1, 0.18, 0.1), CFrame.new(0, top + 0.09, sl * 0.25), DARK, metalMat)
		local tube = b:cyl("Scope", sl, 0.17, CFrame.new(0, sy, 0), Color3.fromHex("1A1B1E"), metalMat)
		sightZ = sl / 2 + 0.15
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
		sightY = ironSL or (top + 0.34) -- Round 24e: the ring on the handle's rear
	end
	root:SetAttribute("Sight", s.sight) -- Round 24n: iron | red | scope | carry | none (the first-person reticle reads it)
	root:SetAttribute("SightY", sightY)
	root:SetAttribute("SightZ", sightZ)

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
	-- Round 24t: the detail pass (references: blocky but refined). Two-tone receivers, dark recessed panels and
	-- ribbing, light accent caps and pins, sloped handguard noses, small coloured markings, stepped barrels, and
	-- inset panels on grips, stocks and mags. Pure decoration: no attachment or animated piece moves.
	local accent = metal:Lerp(Color3.fromRGB(205, 208, 214), 0.45)
	local insetC = Color3.fromHex("0F1012")
	local plastic = Enum.Material.SmoothPlastic
	if not isPistol then
		-- Lower receiver in the lighter tone, a touch proud of the upper.
		local lowerH = H * 0.42
		local lowerL = L * (if bullpup then 0.55 else 0.62)
		b:box(
			"LowerReceiver",
			Vector3.new(W * 1.04, lowerH, lowerL),
			CFrame.new(0, bottom + lowerH / 2 - 0.01, if bullpup then L * 0.1 else L * 0.04),
			accent,
			metalMat
		)
		for _, side in { -1, 1 } do
			-- A recessed panel on the upper receiver with a lighter frame line under it.
			b:box(
				"ReceiverInset",
				Vector3.new(0.02, H * 0.2, L * 0.3),
				CFrame.new(side * (W / 2 + 0.008), H * 0.14, -L * 0.1),
				insetC,
				plastic
			)
			b:box(
				"ReceiverSeam",
				Vector3.new(0.022, 0.025, L * 0.85),
				CFrame.new(side * (W / 2 + 0.006), bottom + lowerH, 0),
				insetC,
				plastic
			)
		end
		-- Takedown pins (light caps through the lower receiver).
		for _, z in { L * 0.27, -L * 0.18 } do
			b:box(
				"Pin",
				Vector3.new(W * 1.12, 0.05, 0.05),
				CFrame.new(0, bottom + lowerH * 0.55, z),
				accent:Lerp(Color3.new(1, 1, 1), 0.3),
				metalMat
			)
		end
		-- Selector on the left with fire / safe markings.
		b:box(
			"Selector",
			Vector3.new(0.03, 0.04, 0.12),
			CFrame.new(-W / 2 - 0.03, bottom + lowerH * 0.7, gz - 0.12) * CFrame.Angles(math.rad(-30), 0, 0),
			accent,
			metalMat
		)
		b:box(
			"Marking",
			Vector3.new(0.012, 0.035, 0.04),
			CFrame.new(-W / 2 - 0.02, bottom + lowerH * 0.95, gz - 0.06),
			Color3.fromHex("D9352B"),
			plastic
		)
		b:box(
			"Marking",
			Vector3.new(0.012, 0.035, 0.04),
			CFrame.new(-W / 2 - 0.02, bottom + lowerH * 0.95, gz - 0.2),
			Color3.fromHex("E8E8E8"),
			plastic
		)
		-- Magwell flare round the top of a box magazine.
		if s.mag == "stick" or s.mag == "small" or s.mag == "curved" then
			b:box("Magwell", Vector3.new(W * 0.86, 0.13, 0.44), CFrame.new(0, bottom - 0.04, mz), accent, metalMat)
		end
		-- Handguard: an end cap at the receiver, vertical ribs down both sides, a sloped nose.
		local hg = guardPart
		if hg and s.action ~= "pump" and s.action ~= "break" then
			b:box("EndCap", Vector3.new(W * 1.0, gh * 1.04, 0.07), CFrame.new(0, gy, front - 0.035), accent, metalMat)
			local n = math.max(3, math.floor(s.guard / 0.085))
			for i = 1, n - 1 do
				local z = front - 0.1 - (i - 0.5) * ((s.guard - 0.16) / (n - 1))
				for _, side in { -1, 1 } do
					b:box(
						"GuardRib",
						Vector3.new(0.02, gh * 0.62, 0.028),
						CFrame.new(side * (W * 0.46 + 0.008), gy, z),
						insetC,
						plastic,
						hg
					)
				end
			end
			b:wedge(
				"GuardNose",
				Vector3.new(W * 0.92, gh, 0.13),
				CFrame.new(0, gy, front - s.guard - 0.065),
				furn,
				furnMat,
				hg
			)
		end
		-- A stepped barrel: a thicker shank where it leaves the handguard.
		if s.action ~= "break" and s.barrel > 0.2 and not s.shroud then
			local shank = s.barrel * 0.35
			b:cyl(
				"BarrelShank",
				shank,
				s.bd * 1.35,
				CFrame.new(0, by, front - s.guard - shank / 2 - 0.02),
				metal,
				metalMat
			)
		end
		-- Recessed slots and a cheek riser on solid stocks.
		if s.stock == "fixed" or s.stock == "thumb" or s.stock == "tube" then
			local stockCz = if s.stock == "tube" then rear + s.stockLen * 0.72 else rear + s.stockLen / 2
			local stockLz = if s.stock == "tube" then s.stockLen * 0.5 else s.stockLen
			local sy = if s.stock == "tube" then -H * 0.02 else -H * 0.1
			for _, side in { -1, 1 } do
				for j = 0, 1 do
					b:box(
						"StockSlot",
						Vector3.new(0.02, H * 0.14, stockLz * 0.3),
						CFrame.new(
							side * (W * 0.44 + 0.008),
							sy + H * 0.12,
							stockCz - stockLz * 0.18 + j * stockLz * 0.36
						),
						insetC,
						plastic
					)
				end
			end
			b:box(
				"CheekRiser",
				Vector3.new(W * 0.7, 0.07, stockLz * 0.55),
				CFrame.new(0, sy + H * 0.5 + 0.03, stockCz + stockLz * 0.1),
				furn,
				furnMat
			)
		end
	else
		-- Pistol: an accessory rail under the dust cover, slide cuts, a light takedown lever.
		b:box(
			"FrameRail",
			Vector3.new(W * 0.7, 0.06, L * 0.25),
			CFrame.new(0, bottom - 0.03, front + L * 0.16),
			insetC,
			metalMat
		)
		b:box("Takedown", Vector3.new(W * 1.1, 0.04, 0.09), CFrame.new(0, bottom + 0.06, L * 0.02), accent, metalMat)
		if slide and not s.revolver then
			for _, side in { -1, 1 } do
				b:box(
					"SlideCut",
					Vector3.new(0.02, 0.025, L * 0.55),
					CFrame.new(side * (W * 0.52 + 0.006), top - H * 0.12, -L * 0.15),
					insetC,
					plastic,
					slide
				)
			end
		end
	end
	-- Grips: inset panels both sides and a base cap.
	for _, side in { -1, 1 } do
		b:box(
			"GripPanel",
			Vector3.new(0.02, gripH * 0.55, 0.17),
			gripCF * CFrame.new(side * (W * 0.43 + 0.008), -0.02, 0),
			insetC,
			plastic,
			grip
		)
	end
	b:box(
		"GripCap",
		Vector3.new(W * 0.9, 0.05, if isPistol then 0.36 else 0.32),
		gripCF * CFrame.new(0, -gripH / 2 - 0.015, 0),
		DARK,
		metalMat,
		grip
	)
	-- Magazines: an inset strip down each side and a wider base plate (they ride with the mag on reloads).
	local mp = magPart
	if mp and (s.mag == "stick" or s.mag == "small" or s.mag == "curved") then
		local ms = mp.Size
		for _, side in { -1, 1 } do
			b:box(
				"MagPanel",
				Vector3.new(0.02, ms.Y * 0.7, ms.Z * 0.4),
				mp.CFrame * CFrame.new(side * (ms.X / 2 + 0.008), 0, 0),
				insetC,
				plastic,
				mp
			)
		end
		if s.mag ~= "curved" then
			b:box(
				"MagBase",
				Vector3.new(ms.X * 1.15, 0.05, ms.Z * 1.12),
				mp.CFrame * CFrame.new(0, -ms.Y / 2 - 0.02, 0),
				accent,
				metalMat,
				mp
			)
		end
	end

	-- Round 24w: receiver silhouettes, so guns stop sharing one box. Each profile reshapes the top line of the
	-- receiver (the part you read from across the room); the root box stays as the mounting core.
	if not isPistol and s.custom == "" then
		local bodyC = metal
		if s.body == "stepped" then
			-- A raised rear upper (G36 / M4 flat-top0) dropping to a lower front, with a sloped step between.
			local rl = L * 0.5
			b:box(
				"UpperRear",
				Vector3.new(W * 1.02, H * 0.22, rl),
				CFrame.new(0, top0 + H * 0.11, L * 0.25),
				bodyC,
				metalMat
			)
			b:wedge(
				"UpperStep",
				Vector3.new(W * 1.02, H * 0.22, L * 0.14),
				CFrame.new(0, top0 + H * 0.11, -L * 0.07),
				bodyC,
				metalMat
			)
		elseif s.body == "humped" then
			-- A rounded dust cover along the top (AK), and a lower rear trunnion.
			local cover =
				b:cyl("DustCover", L * 0.86, W * 0.9, CFrame.new(0, top0 - W * 0.12, -L * 0.02), bodyC, metalMat)
			cover.Size = Vector3.new(cover.Size.X, W * 0.9, W * 0.9)
			b:box(
				"RearTrunnion",
				Vector3.new(W * 1.04, H * 0.3, L * 0.14),
				CFrame.new(0, -H * 0.2, L * 0.44),
				accent,
				metalMat
			)
		elseif s.body == "tapered" then
			-- A receiver that rakes down at the front (FAL / SVD): a sloped top plate.
			b:wedge(
				"TaperTop",
				Vector3.new(W * 1.0, H * 0.24, L * 0.55),
				CFrame.new(0, top0 + H * 0.12, -L * 0.05),
				bodyC,
				metalMat
			)
			b:box(
				"TaperRear",
				Vector3.new(W * 1.0, H * 0.24, L * 0.3),
				CFrame.new(0, top0 + H * 0.12, L * 0.36),
				bodyC,
				metalMat
			)
		elseif s.body == "round" then
			-- A slim round receiver (bolt guns): a tube along the top over a low stock-fed body.
			b:cyl("RoundReceiver", L * 0.95, W * 1.15, CFrame.new(0, top0 - W * 0.05, 0), bodyC, metalMat)
		elseif s.body == "boxy" then
			-- A tall, square upper with a chamfered nose (SCAR, M82, SPAS).
			b:box(
				"BoxUpper",
				Vector3.new(W * 1.08, H * 0.3, L * 0.78),
				CFrame.new(0, top0 + H * 0.15, L * 0.08),
				bodyC,
				metalMat
			)
			local nose = b:wedge(
				"BoxNose",
				Vector3.new(W * 1.08, H * 0.3, L * 0.16),
				CFrame.new(0, top0 + H * 0.15, -L * 0.39),
				bodyC,
				metalMat
			)
			nose.Name = "BoxNose"
		elseif s.body == "tall" then
			-- A belt-fed top cover (M249 / PKM / MG42): tall, ribbed, hinged at the rear.
			local cover = b:box(
				"TopCover",
				Vector3.new(W * 1.06, H * 0.34, L * 0.62),
				CFrame.new(0, top0 + H * 0.17, -L * 0.06),
				bodyC,
				metalMat
			)
			for i = 0, 3 do
				b:box(
					"CoverRib",
					Vector3.new(W * 1.08, 0.03, 0.04),
					CFrame.new(0, top0 + H * 0.34, -L * 0.3 + i * L * 0.15),
					insetC,
					plastic,
					cover
				)
			end
			b:box(
				"CoverHinge",
				Vector3.new(W * 1.1, 0.07, 0.07),
				CFrame.new(0, top0 + H * 0.3, L * 0.27),
				accent,
				metalMat,
				cover
			)
			b:box(
				"CoverLatch",
				Vector3.new(0.05, 0.08, 0.1),
				CFrame.new(W * 0.56, top0 + H * 0.2, -L * 0.34),
				accent,
				metalMat,
				cover
			)
		end
		-- Bolt guns get a bolt handle out to the right with a knob.
		if s.action == "bolt" then
			local hz = L * 0.18
			b:bar(
				"BoltHandle",
				Vector3.new(W * 0.45, top0 - 0.05, hz),
				Vector3.new(W * 0.45 + 0.22, top0 - 0.18, hz + 0.04),
				0.05,
				DARK
			)
			local knob = newPart(
				"BoltKnob",
				Vector3.new(0.1, 0.1, 0.1),
				CFrame.new(W * 0.45 + 0.25, top0 - 0.2, hz + 0.05),
				DARK,
				metalMat
			)
			knob.Shape = Enum.PartType.Ball
			local wd = Instance.new("Weld")
			wd.Part0 = root
			wd.Part1 = knob
			wd.C0 = root.CFrame:ToObjectSpace(knob.CFrame)
			wd.Parent = knob
			knob.Parent = root
		end
	end

	-- Round 24ab: each gun's own read. The generic pieces above give every gun the same skeleton; this adds the shapes
	-- that make the real one recognisable at a glance (an AK's gas tube and sight tower, an M4's A-frame and forward
	-- assist, a SPAS's perforated shield, a lever gun's loop, the bolt rifles' full-length wood and bands...).
	-- Everything is placed from that gun's own anchors (barrel by / front, handguard gy / gh, grip gripCF, stock rear).
	do
		local id = weaponId
		local muzzleZ0 = front - barrelLen -- where the bare barrel ends (before any muzzle device)
		local guardFront = front - s.guard
		local function loop(name: string, a: Vector3, c: Vector3, d: Vector3, e: Vector3, t: number, color: Color3)
			-- An open loop of rods a -> c -> d -> e (lever loops, carry handles, sling loops).
			b:bar(name, a, c, t, color)
			b:bar(name, c, d, t, color)
			b:bar(name, d, e, t, color)
		end
		local function bands(zs: { number }, w: number, h: number, y: number, color: Color3)
			for _, z in zs do
				b:box("Band", Vector3.new(w, h, 0.045), CFrame.new(0, y, z), color, metalMat)
			end
		end
		local function sideRails(z: number, len: number, y: number, halfW: number)
			for _, side in { -1, 1 } do
				b:box("SideRail", Vector3.new(0.04, 0.05, len), CFrame.new(side * halfW, y, z), DARK, metalMat)
				for i = 0, math.max(2, math.floor(len / 0.1)) - 1 do
					b:box(
						"SideRailTooth",
						Vector3.new(0.05, 0.06, 0.03),
						CFrame.new(side * (halfW + 0.01), y, z - len / 2 + 0.05 + i * 0.1),
						DARK,
						metalMat
					)
				end
			end
			b:box("BottomRail", Vector3.new(0.05, 0.04, len), CFrame.new(0, gy - gh / 2 - 0.02, z), DARK, metalMat)
		end

		if id == "M1911" or id == "Gold1911" then
			-- Barrel bushing at the slide's nose, a spur hammer, the grip safety's beavertail, the slide stop.
			b:cyl("Bushing", 0.04, H * 0.32, CFrame.new(0, H * 0.48, front - 0.01), accent, metalMat)
			b:box(
				"Hammer",
				Vector3.new(W * 0.3, 0.13, 0.08),
				CFrame.new(0, top - 0.03, L * 0.46) * CFrame.Angles(math.rad(-35), 0, 0),
				DARK,
				metalMat
			)
			b:box(
				"Beavertail",
				Vector3.new(W * 0.8, 0.07, 0.16),
				gripCF * CFrame.new(0, gripH / 2 - 0.02, 0.2) * CFrame.Angles(math.rad(20), 0, 0),
				metal,
				metalMat
			)
			b:box("SlideStop", Vector3.new(0.03, 0.05, 0.2), CFrame.new(-W * 0.55, H * 0.28, -L * 0.04), DARK, metalMat)
		elseif id == "Glock" then
			-- A blocky slide with bevelled top edges, finger grooves down the grip's front, no hammer.
			for _, side in { -1, 1 } do
				b:wedge(
					"SlideBevel",
					Vector3.new(L * 0.98, 0.07, 0.06),
					CFrame.new(side * (W * 0.52 - 0.03), top + 0.035, -L * 0.07)
						* CFrame.Angles(0, math.rad(if side < 0 then 90 else -90), 0),
					metal,
					metalMat
				)
			end
			for i = 0, 2 do
				b:box(
					"FingerGroove",
					Vector3.new(W * 0.7, 0.07, 0.05),
					gripCF * CFrame.new(0, gripH * 0.25 - i * 0.14, -0.17),
					furn,
					furnMat
				)
			end
		elseif id == "Python" then
			-- Full-length underlug and a ventilated top rib down the barrel.
			local bz = front - s.barrel / 2
			b:box(
				"Underlug",
				Vector3.new(W * 0.42, H * 0.22, s.barrel + 0.04),
				CFrame.new(0, by - s.bd / 2 - H * 0.08, bz),
				metal,
				metalMat
			)
			b:box(
				"VentRib",
				Vector3.new(W * 0.3, 0.06, s.barrel),
				CFrame.new(0, by + s.bd / 2 + 0.03, bz),
				metal,
				metalMat
			)
			for i = 0, 3 do
				b:box(
					"RibSlot",
					Vector3.new(W * 0.32, 0.03, 0.04),
					CFrame.new(0, by + s.bd / 2 + 0.035, front - 0.06 - i * s.barrel / 4),
					DARK,
					metalMat
				)
			end
		elseif id == "M93R" then
			-- The fold-down front grip ahead of the guard, an open-top slide showing the barrel, an extended mag.
			b:box(
				"FoldGrip",
				Vector3.new(W * 0.55, 0.34, 0.12),
				CFrame.new(0, bottom - 0.19, front + L * 0.14) * CFrame.Angles(math.rad(12), 0, 0),
				DARK,
				metalMat
			)
			b:box(
				"FoldHinge",
				Vector3.new(W * 0.7, 0.05, 0.08),
				CFrame.new(0, bottom - 0.02, front + L * 0.14),
				accent,
				metalMat
			)
			b:box(
				"SlideCutout",
				Vector3.new(W * 0.5, 0.02, L * 0.32),
				CFrame.new(0, top + 0.002, -L * 0.28),
				DARK,
				metalMat
			)
			b:cyl("OpenBarrel", L * 0.3, W * 0.36, CFrame.new(0, top - 0.04, -L * 0.28), accent, metalMat)
			local mp0 = magPart
			if mp0 then
				b:box(
					"MagExtension",
					Vector3.new(W * 0.66, 0.26, 0.25),
					gripCF * CFrame.new(0, -gripH / 2 - 0.12, 0.01),
					DARK,
					metalMat,
					mp0
				)
			end
		elseif id == "UZI" then
			-- The top cocking knob, a barrel nut, grooved sides.
			b:box("CockingKnob", Vector3.new(0.1, 0.09, 0.1), CFrame.new(0, top + 0.045, -L * 0.15), DARK, metalMat)
			b:cyl("BarrelNut", 0.08, s.bd * 2.1, CFrame.new(0, by, front - 0.04), DARK, metalMat)
			for _, side in { -1, 1 } do
				for i = 0, 2 do
					b:box(
						"SideGroove",
						Vector3.new(0.02, H * 0.5, 0.03),
						CFrame.new(side * (W / 2 + 0.008), H * 0.02, -L * 0.3 + i * 0.12),
						insetC,
						plastic
					)
				end
			end
		elseif id == "MP5" then
			-- The cocking tube over the barrel with its handle out front-left, and the slim tapered handguard.
			b:cyl(
				"CockingTube",
				s.guard + 0.1,
				0.09,
				CFrame.new(-W * 0.12, by + s.bd * 1.1, front - s.guard / 2),
				metal,
				metalMat
			)
			b:box(
				"CockingHandle",
				Vector3.new(0.14, 0.04, 0.05),
				CFrame.new(-W * 0.4, by + s.bd * 1.1, guardFront + 0.08) * CFrame.Angles(0, math.rad(20), 0),
				DARK,
				metalMat
			)
			b:box("Paddle", Vector3.new(W * 0.5, 0.04, 0.08), CFrame.new(0, bottom - 0.02, mz + 0.22), DARK, metalMat)
		elseif id == "P90" or id == "PS90" then
			-- The P90's forward loop: the trigger guard swept up into a handguard ahead of the grip.
			local yb = bottom - 0.36
			loop(
				"FrontLoop",
				Vector3.new(0, bottom, gz - 0.1),
				Vector3.new(0, yb, gz - 0.1),
				Vector3.new(0, yb, -L * 0.48),
				Vector3.new(0, bottom, -L * 0.5),
				0.07,
				furn
			)
			b:wedge(
				"RearSlope",
				Vector3.new(W * 1.02, H * 0.4, L * 0.18),
				CFrame.new(0, -H * 0.3, L * 0.41) * CFrame.Angles(0, math.rad(180), 0),
				furn,
				furnMat
			)
		elseif id == "MAC10" then
			-- A strap loop hanging under the nose, the top knob, a threaded barrel.
			loop(
				"StrapLoop",
				Vector3.new(-W * 0.3, bottom, front + 0.06),
				Vector3.new(-W * 0.3, bottom - 0.12, front + 0.06),
				Vector3.new(W * 0.3, bottom - 0.12, front + 0.06),
				Vector3.new(W * 0.3, bottom, front + 0.06),
				0.04,
				DARK
			)
			b:box("CockingKnob", Vector3.new(0.09, 0.09, 0.09), CFrame.new(0, top + 0.045, -L * 0.1), DARK, metalMat)
			for i = 0, 3 do
				b:cyl("Thread", 0.02, s.bd * 1.15, CFrame.new(0, by, muzzleZ0 + 0.03 + i * 0.04), accent, metalMat)
			end
		elseif id == "Skorpion" then
			-- A short barrel shroud and the wire stock folded over the top.
			b:cyl("BarrelShroud", 0.14, s.bd * 1.6, CFrame.new(0, by, front - 0.07), metal, metalMat)
			b:box("TopRib", Vector3.new(W * 0.3, 0.04, L * 0.7), CFrame.new(0, top + 0.02, -L * 0.05), DARK, metalMat)
		elseif id == "AK-47" or id == "RPK" then
			-- The wooden upper handguard over the gas tube, the gas block, the tall front sight tower at the muzzle and
			-- the big safety lever on the right.
			b:box(
				"UpperGuard",
				Vector3.new(W * 0.68, H * 0.24, s.guard * 0.72),
				CFrame.new(0, gy + gh / 2 + H * 0.1, front - s.guard * 0.4),
				furn,
				furnMat
			)
			b:cyl(
				"GasTube",
				s.guard * 0.3,
				s.bd * 0.95,
				CFrame.new(0, gy + gh / 2 + H * 0.1, front - s.guard * 0.88),
				metal,
				metalMat
			)
			b:box(
				"GasBlock",
				Vector3.new(W * 0.5, H * 0.42, 0.11),
				CFrame.new(0, by + H * 0.16, guardFront - 0.05),
				metal,
				metalMat
			)
			b:wedge(
				"SightTower",
				Vector3.new(W * 0.36, H * 0.5, 0.16),
				CFrame.new(0, by + H * 0.2, muzzleZ0 + 0.14) * CFrame.Angles(0, math.rad(180), 0),
				metal,
				metalMat
			)
			b:box(
				"SafetyLever",
				Vector3.new(0.03, 0.07, L * 0.42),
				CFrame.new(W / 2 + 0.025, H * 0.12, -L * 0.06),
				metal,
				metalMat
			)
			if id == "RPK" then
				-- The RPK's bipod under the front, folded back.
				for _, side in { -1, 1 } do
					b:bar(
						"RPKBipod",
						Vector3.new(side * 0.06, by - s.bd, muzzleZ0 + 0.3),
						Vector3.new(side * 0.12, by - s.bd - 0.12, muzzleZ0 + 0.8),
						0.04,
						DARK
					)
				end
			end
		elseif id == "M4A1" then
			-- The A-frame front sight / gas block, rails down the handguard, the forward assist, the brass deflector.
			b:wedge(
				"AFrame",
				Vector3.new(W * 0.3, H * 0.6, 0.18),
				CFrame.new(0, by + H * 0.3, guardFront - 0.1) * CFrame.Angles(0, math.rad(180), 0),
				DARK,
				metalMat
			)
			sideRails(front - s.guard / 2, s.guard * 0.85, gy, W * 0.46 + 0.02)
			b:cyl("ForwardAssist", 0.14, 0.1, CFrame.new(W * 0.56, top0 - H * 0.12, L * 0.24), metal, metalMat)
			b:box(
				"Deflector",
				Vector3.new(0.06, 0.09, 0.08),
				CFrame.new(W / 2 + 0.04, top0 - H * 0.1, L * 0.12),
				metal,
				metalMat
			)
		elseif id == "SCAR-H" then
			-- Railed handguard sides, the long side charging handle, a folding-stock hinge.
			sideRails(front - s.guard / 2, s.guard * 0.9, gy + gh * 0.15, W * 0.46 + 0.02)
			b:box(
				"SideCharger",
				Vector3.new(0.06, 0.07, L * 0.25),
				CFrame.new(-W * 0.55, top0 - H * 0.08, -L * 0.15),
				DARK,
				metalMat
			)
			b:box(
				"StockHinge",
				Vector3.new(W * 1.05, H * 0.5, 0.1),
				CFrame.new(0, -H * 0.05, rear + 0.05),
				DARK,
				metalMat
			)
		elseif id == "AUG" then
			-- The AUG's rounded housing, the vertical foregrip and the full-length trigger guard enclosure.
			b:cyl("Housing", L * 0.5, H * 1.08, CFrame.new(0, -H * 0.02, L * 0.24), furn, furnMat)
			b:box(
				"Foregrip",
				Vector3.new(W * 0.5, 0.42, 0.14),
				CFrame.new(0, bottom - 0.22, front + L * 0.06) * CFrame.Angles(math.rad(-8), 0, 0),
				furn,
				furnMat
			)
			loop(
				"Enclosure",
				Vector3.new(0, bottom, gz + 0.12),
				Vector3.new(0, bottom - 0.46, gz + 0.12),
				Vector3.new(0, bottom - 0.46, front + L * 0.06),
				Vector3.new(0, bottom - 0.42, front + L * 0.06),
				0.06,
				furn
			)
		elseif id == "FAL" then
			-- The exposed gas tube / plug ahead of the handguard and the carry handle folded on the left.
			b:cyl(
				"GasTube",
				s.barrel * 0.4,
				s.bd * 0.8,
				CFrame.new(0, by + s.bd * 1.3, guardFront - s.barrel * 0.2),
				metal,
				metalMat
			)
			b:cyl(
				"GasPlug",
				0.06,
				s.bd * 1.1,
				CFrame.new(0, by + s.bd * 1.3, guardFront - s.barrel * 0.4 - 0.02),
				accent,
				metalMat
			)
			b:box(
				"CarryHandle",
				Vector3.new(0.04, 0.05, L * 0.3),
				CFrame.new(-W * 0.6, top0 - H * 0.05, -L * 0.2),
				DARK,
				metalMat
			)
		elseif id == "SPAS-12" then
			-- The perforated heat shield over the barrel and the folding stock's hook.
			local sl = s.barrel + s.guard * 0.35
			local sz = muzzleZ0 + sl / 2 + 0.02
			local shield = b:box(
				"HeatShield",
				Vector3.new(s.bd * 2.1, s.bd * 1.5, sl),
				CFrame.new(0, by + s.bd * 0.45, sz),
				metal,
				metalMat
			)
			for i = 0, math.max(3, math.floor(sl / 0.12)) - 1 do
				for _, side in { -1, 1 } do
					b:box(
						"ShieldHole",
						Vector3.new(0.02, s.bd * 0.5, 0.06),
						CFrame.new(side * (s.bd * 1.05 + 0.005), by + s.bd * 0.5, muzzleZ0 + 0.08 + i * 0.12),
						insetC,
						plastic,
						shield
					)
				end
			end
			b:box(
				"StockHook",
				Vector3.new(W * 0.3, 0.16, 0.06),
				CFrame.new(0, -H * 0.62, rear + s.stockLen - 0.02),
				DARK,
				metalMat
			)
		elseif id == "SawedOff" then
			-- Twin exposed hammers and the hinge pin.
			for _, side in { -1, 1 } do
				b:box(
					"Hammer",
					Vector3.new(0.06, 0.14, 0.08),
					CFrame.new(side * W * 0.22, top - 0.02, L * 0.38) * CFrame.Angles(math.rad(-30), 0, 0),
					DARK,
					metalMat
				)
			end
			b:cyl(
				"HingePin",
				0.04,
				W * 1.1,
				CFrame.new(0, bottom + 0.06, front + 0.04) * CFrame.Angles(0, math.rad(90), 0),
				accent,
				metalMat
			)
		elseif id == "Model1887" then
			-- The lever loop round the grip: the 1887's signature.
			local yb = bottom - gripH * 0.85
			loop(
				"LeverLoop",
				Vector3.new(0, bottom - 0.02, gz - 0.42),
				Vector3.new(0, yb, gz - 0.36),
				Vector3.new(0, yb, gz + 0.12),
				Vector3.new(0, bottom - gripH * 0.55, gz + 0.16),
				0.05,
				metal
			)
			b:box(
				"Hammer",
				Vector3.new(0.07, 0.14, 0.09),
				CFrame.new(0, top0 + 0.04, L * 0.4) * CFrame.Angles(math.rad(-30), 0, 0),
				DARK,
				metalMat
			)
		elseif id == "M870" then
			-- Ribbed pump grip (rides with the pump).
			local pump = guardPart
			if pump then
				local ps = pump.Size
				for i = 0, 5 do
					b:box(
						"PumpRib",
						Vector3.new(ps.X * 1.06, ps.Y * 1.08, 0.03),
						pump.CFrame * CFrame.new(0, 0, -ps.Z / 2 + (i + 0.5) * ps.Z / 6),
						insetC,
						plastic,
						pump
					)
				end
			end
		elseif id == "AA12" then
			-- A square shroud round the barrel and a tall front post.
			b:box(
				"BarrelShroud",
				Vector3.new(s.bd * 2.2, s.bd * 2.2, s.barrel),
				CFrame.new(0, by, front - s.guard - s.barrel / 2),
				metal,
				metalMat
			)
			b:box(
				"FrontPost",
				Vector3.new(0.05, H * 0.35, 0.05),
				CFrame.new(0, by + s.bd * 1.1 + H * 0.17, muzzleZ0 + 0.08),
				DARK,
				metalMat
			)
		elseif id == "AWP" then
			-- A fluted barrel.
			for i = 0, 3 do
				local a = i * math.pi / 2 + math.pi / 4
				b:box(
					"Flute",
					Vector3.new(0.02, s.bd * 0.32, s.barrel * 0.8),
					CFrame.new(
						math.sin(a) * s.bd * 0.5,
						by + math.cos(a) * s.bd * 0.5,
						front - s.guard - s.barrel * 0.45
					) * CFrame.Angles(0, 0, -a),
					insetC,
					plastic
				)
			end
		elseif id == "M82" then
			-- The carry handle over the front of the receiver and the barrel's top shroud.
			loop(
				"CarryHandle",
				Vector3.new(0, top, -L * 0.48),
				Vector3.new(0, top + 0.18, -L * 0.45),
				Vector3.new(0, top + 0.18, -L * 0.25),
				Vector3.new(0, top, -L * 0.22),
				0.06,
				DARK
			)
			b:box(
				"BarrelShroud",
				Vector3.new(s.bd * 2, 0.06, s.guard * 0.9),
				CFrame.new(0, by + s.bd * 1.1, front - s.guard * 0.5),
				metal,
				metalMat
			)
		elseif id == "SVD" then
			-- The SVD's skeleton stock: a big hole through the wood.
			b:box(
				"StockHole",
				Vector3.new(W * 0.88, H * 0.42, s.stockLen * 0.45),
				CFrame.new(0, -H * 0.18, rear + s.stockLen * 0.42) * CFrame.Angles(math.rad(9), 0, 0),
				insetC,
				plastic
			)
			b:box(
				"CheekPad",
				Vector3.new(W * 0.7, 0.08, s.stockLen * 0.35),
				CFrame.new(0, H * 0.18, rear + s.stockLen * 0.35),
				furn,
				furnMat
			)
		elseif id == "Kar98k" or id == "Mosin" then
			-- Full-length wood under the barrel to near the muzzle, held by barrel bands; a hooded front sight.
			local wl = s.barrel * 0.55
			b:box(
				"ForeStock",
				Vector3.new(W * 0.78, H * 0.48, wl),
				CFrame.new(0, by - s.bd / 2 - H * 0.18, guardFront - wl / 2),
				furn,
				furnMat
			)
			bands({ front - s.guard * 0.45, guardFront - wl + 0.05 }, W * 0.84, H * 0.6, by - H * 0.08, metal)
			if id == "Kar98k" then
				b:box(
					"SightHood",
					Vector3.new(0.1, 0.06, 0.08),
					CFrame.new(0, by + s.bd / 2 + 0.1, muzzleZ0 + 0.05),
					DARK,
					metalMat
				)
			end
		elseif id == "M249" then
			-- A heat shield over the barrel and a carry handle on the barrel.
			b:box(
				"HeatShield",
				Vector3.new(s.bd * 1.7, 0.04, s.barrel * 0.6),
				CFrame.new(0, by + s.bd * 0.85, guardFront - s.barrel * 0.3),
				metal,
				metalMat
			)
			loop(
				"BarrelHandle",
				Vector3.new(W * 0.2, by, guardFront - 0.05),
				Vector3.new(W * 0.45, by + 0.2, guardFront - 0.1),
				Vector3.new(W * 0.45, by + 0.2, guardFront - 0.35),
				Vector3.new(W * 0.2, by, guardFront - 0.4),
				0.05,
				DARK
			)
		elseif id == "PKM" then
			-- The PKM's fluted barrel and the carry handle on it.
			for i = 0, 2 do
				local a = i * math.pi * 2 / 3
				b:box(
					"Flute",
					Vector3.new(0.02, s.bd * 0.32, s.barrel * 0.7),
					CFrame.new(math.sin(a) * s.bd * 0.5, by + math.cos(a) * s.bd * 0.5, guardFront - s.barrel * 0.42)
						* CFrame.Angles(0, 0, -a),
					insetC,
					plastic
				)
			end
			loop(
				"BarrelHandle",
				Vector3.new(0, by + s.bd * 0.5, guardFront - 0.05),
				Vector3.new(0, by + 0.24, guardFront - 0.1),
				Vector3.new(0, by + 0.24, guardFront - 0.36),
				Vector3.new(0, by + s.bd * 0.5, guardFront - 0.4),
				0.05,
				DARK
			)
		elseif id == "MG42" then
			-- The bipod hung under the front of the shroud.
			for _, side in { -1, 1 } do
				b:bar(
					"MG42Bipod",
					Vector3.new(side * 0.05, by - s.bd, muzzleZ0 + 0.45),
					Vector3.new(side * 0.22, by - s.bd - 0.55, muzzleZ0 + 0.3),
					0.045,
					DARK
				)
			end
			b:box("BipodMount", Vector3.new(0.14, 0.08, 0.1), CFrame.new(0, by - s.bd, muzzleZ0 + 0.45), DARK, metalMat)
		end
	end

	-- Round 24v: launcher / elemental dressing. Each may move the Muzzle (where projectiles, fx and tracers leave).
	local muzzleCF: CFrame? = nil
	local NEON = Enum.Material.Neon
	if s.special == "rpg" then
		-- A long tube over the grip, a flared venturi at the back, the warhead in the front, wooden heat shield.
		local tl = 2.0
		local ty = H * 0.35
		local tube = b:cyl("Tube", tl, 0.32, CFrame.new(0, ty, -0.15), metal, metalMat)
		b:cyl("Venturi", 0.22, 0.42, CFrame.new(0, ty, -0.15 + tl / 2 + 0.08), DARK, metalMat, tube)
		b:cyl("HeatShield", 0.55, 0.38, CFrame.new(0, ty, 0.1), furn, furnMat, tube)
		b:cyl(
			"WarheadNeck",
			0.18,
			0.22,
			CFrame.new(0, ty, -0.15 - tl / 2 - 0.08),
			Color3.fromHex("5C6B3A"),
			metalMat,
			tube
		)
		b:cyl("Warhead", 0.4, 0.42, CFrame.new(0, ty, -0.15 - tl / 2 - 0.36), Color3.fromHex("5C6B3A"), metalMat, tube)
		b:cyl(
			"WarheadTip",
			0.2,
			0.22,
			CFrame.new(0, ty, -0.15 - tl / 2 - 0.66),
			Color3.fromHex("5C6B3A"),
			metalMat,
			tube
		)
		b:cyl("WarheadNose", 0.08, 0.08, CFrame.new(0, ty, -0.15 - tl / 2 - 0.8), DARK, metalMat, tube)
		b:box("FlipSight", Vector3.new(0.04, 0.16, 0.04), CFrame.new(0, ty + 0.24, -0.6), DARK, metalMat, tube)
		b:box(
			"FrontGrip",
			Vector3.new(W * 0.8, 0.4, 0.22),
			CFrame.new(0, ty - 0.36, -0.55) * CFrame.Angles(math.rad(-10), 0, 0),
			furn,
			furnMat
		)
		muzzleCF = CFrame.new(0, ty, -0.15 - tl / 2 - 0.2)
	elseif s.special == "mgl" then
		-- A revolving six-round drum ahead of the grip and a stubby wide barrel.
		local dy = by - 0.05
		local drum = b:cyl("Drum", 0.42, 0.7, CFrame.new(0, dy, front + 0.18), metal, metalMat)
		for i = 0, 5 do
			local a = i * math.pi / 3
			b:cyl(
				"Chamber",
				0.44,
				0.16,
				CFrame.new(math.sin(a) * 0.22, dy + math.cos(a) * 0.22, front + 0.18),
				insetC,
				metalMat,
				drum
			)
		end
		b:cyl("DrumAxle", 0.48, 0.1, CFrame.new(0, dy, front + 0.18), accent, metalMat, drum)
		b:box("DrumFrame", Vector3.new(W * 0.6, 0.06, 0.6), CFrame.new(0, dy + 0.38, front + 0.18), DARK, metalMat)
	elseif s.special == "cluster" then
		-- Orange hazard bands round the fat barrel.
		for i = 0, 2 do
			b:cyl(
				"HazardBand",
				0.06,
				s.bd * 1.08,
				CFrame.new(0, by, front - s.guard - 0.06 - i * 0.12),
				Color3.fromHex("E8A33A"),
				plastic
			)
		end
	elseif s.special == "flamer" then
		-- A fuel tank under the body, a hose up to a wide nozzle, and a pilot light.
		local tank = b:cyl("FuelTank", L * 0.75, 0.42, CFrame.new(0, bottom - 0.28, -L * 0.15), furn, metalMat)
		b:cyl("TankCap", 0.06, 0.44, CFrame.new(0, bottom - 0.28, -L * 0.15 - L * 0.375), accent, metalMat, tank)
		b:bar(
			"Hose",
			Vector3.new(W * 0.4, bottom - 0.2, -L * 0.45),
			Vector3.new(W * 0.35, by - 0.05, front - s.guard),
			0.07,
			DARK
		)
		b:cyl("Nozzle", 0.22, s.bd * 1.8, CFrame.new(0, by, front - s.guard - s.barrel - 0.08), DARK, metalMat)
		b:box(
			"PilotLight",
			Vector3.new(0.06, 0.06, 0.06),
			CFrame.new(0, by - s.bd * 0.9, front - s.guard - s.barrel - 0.12),
			Color3.fromHex("4DA6FF"),
			NEON
		)
		muzzleCF = CFrame.new(0, by, front - s.guard - s.barrel - 0.22)
	elseif s.special == "cryo" then
		-- A coolant canister on top with a glowing window, frost-blue coils and a flared nozzle.
		local can =
			b:cyl("Coolant", L * 0.55, 0.3, CFrame.new(0, top + 0.22, L * 0.02), Color3.fromHex("E8F2F8"), metalMat)
		b:box(
			"CoolantWindow",
			Vector3.new(0.04, 0.12, L * 0.35),
			CFrame.new(0.15, top + 0.22, L * 0.02),
			Color3.fromHex("8FD3FF"),
			NEON,
			can
		)
		for i = 0, 2 do
			b:cyl(
				"Coil",
				0.05,
				s.bd * 1.7,
				CFrame.new(0, by, front - s.guard * 0.3 - i * 0.12),
				Color3.fromHex("8FD3FF"),
				NEON
			)
		end
		b:cyl("Nozzle", 0.2, s.bd * 2.1, CFrame.new(0, by, front - s.guard - s.barrel - 0.06), furn, metalMat)
		muzzleCF = CFrame.new(0, by, front - s.guard - s.barrel - 0.18)
	elseif s.special == "tesla" then
		-- Tesla rings down the barrel round a glowing core, capacitor cells on the sides.
		local coreLen = s.barrel + 0.1
		b:cyl(
			"ArcCore",
			coreLen,
			s.bd * 0.6,
			CFrame.new(0, by, front - s.guard - coreLen / 2),
			Color3.fromHex("9FE6FF"),
			NEON
		)
		for i = 0, 3 do
			b:cyl(
				"TeslaRing",
				0.05,
				s.bd * 2.6 - i * 0.04,
				CFrame.new(0, by, front - s.guard - 0.06 - i * (coreLen / 4)),
				accent,
				metalMat
			)
		end
		for _, side in { -1, 1 } do
			b:box(
				"Capacitor",
				Vector3.new(0.08, H * 0.4, L * 0.35),
				CFrame.new(side * (W / 2 + 0.05), 0, -L * 0.1),
				Color3.fromHex("9FE6FF"),
				NEON
			)
		end
		b:box(
			"ArcTip",
			Vector3.new(0.12, 0.12, 0.12),
			CFrame.new(0, by, front - s.guard - coreLen - 0.04) * CFrame.Angles(0, 0, math.rad(45)),
			Color3.fromHex("9FE6FF"),
			NEON
		)
		muzzleCF = CFrame.new(0, by, front - s.guard - coreLen - 0.1)
	elseif s.special == "plasma" then
		-- Glowing green cells down both sides and emitter rings at the muzzle.
		for _, side in { -1, 1 } do
			for j = 0, 2 do
				b:box(
					"PlasmaCell",
					Vector3.new(0.06, H * 0.22, 0.14),
					CFrame.new(side * (W / 2 + 0.03), H * 0.05, -L * 0.25 + j * 0.2),
					Color3.fromHex("5BFF9A"),
					NEON
				)
			end
		end
		for i = 0, 2 do
			b:cyl(
				"EmitterRing",
				0.06,
				s.bd * 2.2,
				CFrame.new(0, by, front - s.guard - 0.05 - i * 0.1),
				Color3.fromHex("5BFF9A"),
				NEON
			)
		end
	end
	if muzzleCF then
		local mzA = root:FindFirstChild("Muzzle")
		if mzA and mzA:IsA("Attachment") then
			mzA.CFrame = muzzleCF
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
