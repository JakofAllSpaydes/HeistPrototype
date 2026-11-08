--!strict
-- Owned weapon pool for the prototype. Rarity is rolled per instance, never stored here.
-- displayName is the copy the player sees; keep names as near-names.
-- Paper DPS at common (dmg x rate x pellets): pistols 128 / 140 / 135, SMGs 180 / 170, rifles 160 / 165 / 161,
-- shotguns 179 / 168, snipers 135 / 143 plus headshots, LMGs 169 / 171 (mid falloff, slow reloads). SMG and shotgun only hit that up close (Config.FalloffByArchetype); the sniper
-- never falls off. Rarity multiplies damage on top (Config.RarityDmgMult): the spread between the weakest
-- and strongest common (1.4x) stays under every rarity step, so a legendary pistol beats an epic rifle.
export type Weapon = {
	id: string,
	displayName: string,
	archetype: string,
	baseDmg: number,
	fireRate: number, -- shots per second
	magSize: number,
	reloadTime: number, -- seconds for the whole mag; with shellReload, seconds per shell
	spread: number, -- cone half-angle in degrees
	pellets: number, -- raycasts per shot (shotguns)
	auto: boolean, -- hold to fire
	shellReload: boolean, -- tube-fed: shells load one at a time and firing cancels the rest
	rarityWeights: { number }, -- multiplies the wave-bracket odds per rarity, 1 = unchanged
	burst: number, -- shots per trigger pull (1 = normal); fireRate is the rate inside the burst
	burstDelay: number, -- seconds between bursts
	pierceByRarity: { number }?, -- built-in pierce per rarity tier (snipers)
	-- Brief 6: the gun's own silhouette and accent color (held model and icon). nil = the generic block.
	look: Look?,
	-- Meta (Armory): how the gun is acquired and what its levels cost. Prices.lua holds the numbers.
	saleType: string, -- Direct | Crate | Event
	unlockCost: number?, -- nil = Prices.weaponUnlock
	upgBaseCost: number?, -- nil = Prices.weaponUpgrade
	rarity: number, -- Armory rarity 1..5 (Weapons.ArmoryRarity): the collection tile color, not the drop roll
	-- Round 24v: Explosive / Elemental weapons. nil mode = hitscan. The server (Run/SpecialFire.lua) reads these:
	--   projectile: proj = { kind, speed, gravity, fuse (0 = on contact), radius, directDetonate?, bomblets?, ... }
	--   charge: charge = { sec, maxCost, maxDmgMult, minWidth, maxWidth, minDur, maxDur, maxTicks, range } (a held beam)
	--   stream: stream = { element = "fire" | "frost", range, angle } (a cone every tick)
	--   chain: chain = { range, angle, chains, chainRange, decay } (lock-on lightning)
	mode: string?,
	tracer: string?, -- Round 24ad: hex for this gun's bullet line (energy guns); nil = the usual warm white
	proj: any?,
	charge: any?,
	stream: any?,
	chain: any?,
}

-- Silhouette of a gun (brief 6 guns): body length, barrel length, stock, mag kind and scope, plus its own accent
-- color. The held model and UI.gunIcon both draw from it, so each new gun reads differently at a glance.
export type Look = {
	color: string, -- hex accent (barrel, stock, mag)
	body: number, -- body length, studs (the generic gun is 1.6)
	barrel: number, -- barrel past the body, studs
	stock: boolean,
	mag: string, -- box | drum | tube | none
	scope: boolean,
}

local Config = require(script.Parent.Config)
local Prices = require(script.Parent.Prices)

local Weapons = {}

local function def(t: { [string]: any }): Weapon
	t.pellets = t.pellets or 1
	t.auto = t.auto or false
	t.shellReload = t.shellReload or false
	t.rarityWeights = t.rarityWeights or { 1, 1, 1, 1, 1 }
	t.burst = t.burst or 1
	t.burstDelay = t.burstDelay or 0
	t.saleType = t.saleType or "Direct"
	t.rarity = t.rarity or 1
	return t :: Weapon
end

-- Shots per second as actually delivered, with a fire-rate multiplier applied: bursts count the pause.
function Weapons.effectiveRate(w: Weapon, mult: number?): number
	local r = w.fireRate * (mult or 1)
	if w.burst > 1 and r > 0 then
		return w.burst / (w.burst / r + w.burstDelay)
	end
	return r
end

function Weapons.builtInPierce(w: Weapon, rarity: number): number
	local p = w.pierceByRarity
	return if p then (p[rarity] or p[#p] or 0) else 0
end

Weapons.List = {
	def({
		id = "M1911",
		displayName = "M1911",
		archetype = "Pistol",
		baseDmg = 32,
		fireRate = 4,
		magSize = 8,
		reloadTime = 1.2,
		spread = 1.2,
	}),
	def({
		id = "Glock",
		displayName = "Glock",
		archetype = "Pistol",
		baseDmg = 20,
		fireRate = 7,
		magSize = 17,
		reloadTime = 1.3,
		spread = 1.6,
	}),
	def({
		id = "UZI",
		displayName = "UZI",
		archetype = "SMG",
		baseDmg = 12,
		fireRate = 15,
		magSize = 32,
		reloadTime = 1.6,
		spread = 3.5,
		auto = true,
	}),
	def({
		id = "MP5",
		displayName = "MP5",
		archetype = "SMG",
		baseDmg = 15,
		fireRate = 12,
		magSize = 30,
		reloadTime = 1.7,
		spread = 2.2,
		auto = true,
	}),
	def({
		id = "AK-47",
		displayName = "AK-47",
		archetype = "Rifle",
		baseDmg = 20,
		fireRate = 8,
		magSize = 30,
		reloadTime = 2.2,
		spread = 2.0,
		auto = true,
	}),
	def({
		id = "M4A1",
		displayName = "M4A1",
		archetype = "Rifle",
		baseDmg = 15,
		fireRate = 11,
		magSize = 30,
		reloadTime = 1.9,
		spread = 1.5,
		auto = true,
	}),
	def({
		id = "SPAS-12",
		displayName = "SPAS-12",
		archetype = "Shotgun",
		baseDmg = 14,
		fireRate = 1.6,
		magSize = 8,
		reloadTime = 0.45, -- per shell (tube-fed); a full 8 takes 3.6s but you can stop and shoot any time
		spread = 7,
		pellets = 8,
		shellReload = true,
	}),
	def({
		id = "AWP",
		displayName = "AWP",
		archetype = "Sniper",
		baseDmg = 150,
		fireRate = 0.9,
		magSize = 5,
		reloadTime = 3.0,
		spread = 0.2,
		pierceByRarity = { 1, 1, 2, 3, 4 }, -- snipers always punch through; more at higher rarity
	}),
	-- Round 10 additions: one more of each type plus two LMGs (big mags, slow reloads, mid falloff).
	def({
		id = "Deagle",
		displayName = "Desert Eagle",
		archetype = "Pistol",
		baseDmg = 45,
		fireRate = 3,
		magSize = 7,
		reloadTime = 1.5,
		spread = 1.0,
	}),
	def({
		id = "P90",
		displayName = "P90",
		archetype = "SMG",
		baseDmg = 10,
		fireRate = 17,
		magSize = 50,
		reloadTime = 2.0,
		spread = 3.0,
		auto = true,
	}),
	def({
		id = "SCAR-H",
		displayName = "SCAR-H",
		archetype = "Rifle",
		baseDmg = 36,
		fireRate = 10, -- inside the burst
		burst = 3,
		burstDelay = 0.45, -- 3 shots per 0.75s = 4/s effective, DPS 144
		magSize = 21,
		reloadTime = 2.3,
		spread = 1.4,
	}),
	def({
		id = "SawedOff",
		displayName = "Sawed-Off",
		archetype = "Shotgun",
		baseDmg = 17,
		fireRate = 2.8, -- both barrels back to back; the 2-shell mag and reload are the real limiter
		magSize = 2,
		reloadTime = 0.6, -- sustained: 2 shots per (2 / 2.8 + 0.6)s = 1.5/s, about 155 DPS; paper DPS overstates it
		spread = 9,
		pellets = 6,
	}),
	def({
		id = "M82",
		displayName = "Barrett M82",
		archetype = "Sniper",
		baseDmg = 110,
		fireRate = 1.3,
		magSize = 10,
		reloadTime = 3.4,
		spread = 0.3,
		pierceByRarity = { 1, 1, 2, 3, 4 },
	}),
	def({
		id = "M249",
		displayName = "M249",
		archetype = "LMG",
		baseDmg = 13,
		fireRate = 13,
		magSize = 100,
		reloadTime = 4.5,
		spread = 2.8,
		auto = true,
	}),
	def({
		id = "RPK",
		displayName = "RPK",
		archetype = "LMG",
		baseDmg = 18,
		fireRate = 9.5,
		magSize = 75,
		reloadTime = 4.0,
		spread = 2.4,
		auto = true,
	}),
	-- Round 24s: two more each for the thin types (pistol / shotgun / sniper / LMG), Gold-unlocked (Direct).
	-- Paper DPS at common: Python 139, M93R 138 (burst), AA-12 173, M870 156, SVD 140, Kar98k 136, PKM 176, MG42 170.
	def({
		id = "Python",
		displayName = "Python .357",
		archetype = "Pistol",
		baseDmg = 58,
		fireRate = 2.4,
		magSize = 6,
		reloadTime = 2.0,
		spread = 0.9,
	}),
	def({
		id = "M93R",
		displayName = "M93R",
		archetype = "Pistol",
		baseDmg = 26,
		fireRate = 14, -- inside the burst
		burst = 3,
		burstDelay = 0.35, -- 3 shots per 0.56s = 5.3/s effective
		magSize = 21,
		reloadTime = 1.4,
		spread = 1.4,
	}),
	def({
		id = "AA12",
		displayName = "AA-12",
		archetype = "Shotgun",
		baseDmg = 9,
		fireRate = 3.2,
		magSize = 20,
		reloadTime = 3.2, -- drum: the whole mag at once
		spread = 8,
		pellets = 6,
		auto = true,
	}),
	def({
		id = "M870",
		displayName = "M870",
		archetype = "Shotgun",
		baseDmg = 15,
		fireRate = 1.3,
		magSize = 6,
		reloadTime = 0.5, -- per shell (pump tube)
		spread = 6.5,
		pellets = 8,
		shellReload = true,
	}),
	def({
		id = "SVD",
		displayName = "SVD",
		archetype = "Sniper",
		baseDmg = 70,
		fireRate = 2.0,
		magSize = 10,
		reloadTime = 2.6,
		spread = 0.4,
		pierceByRarity = { 1, 1, 2, 2, 3 }, -- the semi-auto pierces a step less than the bolts
	}),
	def({
		id = "Kar98k",
		displayName = "Kar98k",
		archetype = "Sniper",
		baseDmg = 170,
		fireRate = 0.8,
		magSize = 5,
		reloadTime = 2.5,
		spread = 0.15,
		pierceByRarity = { 1, 1, 2, 3, 4 },
	}),
	def({
		id = "PKM",
		displayName = "PKM",
		archetype = "LMG",
		baseDmg = 16,
		fireRate = 11,
		magSize = 100,
		reloadTime = 4.8,
		spread = 2.6,
		auto = true,
	}),
	def({
		id = "MG42",
		displayName = "MG42",
		archetype = "LMG",
		baseDmg = 8.5,
		fireRate = 20,
		magSize = 75,
		reloadTime = 4.2,
		spread = 3.2,
		auto = true,
	}),
	-- Round 24v: EXPLOSIVE. Damage is the blast's (full in the inner 60%, ExplosiveEdgeDmg at the rim). The RPG
	-- blows on contact; the grenade 0.25s after it lands (at once on a direct hit); the cluster splits into
	-- bomblets 0.5s after landing; thrown TNT sits 1s on its fuse.
	def({
		id = "RPG7",
		displayName = "RPG-7",
		archetype = "Explosive",
		baseDmg = 220,
		fireRate = 0.5,
		magSize = 1,
		reloadTime = 2.8,
		spread = 0.4,
		mode = "projectile",
		proj = { kind = "rocket", speed = 47.5, gravity = 2, fuse = 0, radius = 13 }, -- Round 24aa: half speed (was 95)
	}),
	def({
		id = "M32",
		displayName = "M32 MGL",
		archetype = "Explosive",
		baseDmg = 90,
		fireRate = 1.6,
		magSize = 6,
		reloadTime = 3.4,
		spread = 0.8,
		mode = "projectile",
		proj = {
			kind = "grenade",
			speed = 72,
			gravity = 55,
			fuse = 0.25,
			radius = 9,
			directDetonate = true,
			bounce = 0.4,
		},
	}),
	def({
		id = "ClusterLauncher",
		displayName = "Cluster Launcher",
		archetype = "Explosive",
		baseDmg = 55,
		fireRate = 1.0,
		magSize = 4,
		reloadTime = 0.6, -- per shell (pump tube)
		spread = 0.8,
		shellReload = true,
		mode = "projectile",
		proj = {
			kind = "cluster",
			speed = 62,
			gravity = 55,
			fuse = 0.5,
			radius = 6,
			bomblets = 6,
			bombletRadius = 5,
			bombletDmgMult = 0.55,
			bounce = 0.4,
		},
	}),
	def({
		id = "TNT",
		displayName = "TNT Bundle",
		archetype = "Explosive",
		baseDmg = 260,
		fireRate = 0.8,
		magSize = 3,
		reloadTime = 2.2,
		spread = 0,
		mode = "projectile",
		proj = { kind = "tnt", speed = 46, gravity = 70, fuse = 1.0, radius = 15, bounce = 0.12 },
	}),
	-- Round 24v: ELEMENTAL. The mag is fuel / charge; every tick (fireRate per second) spends one.
	def({
		id = "Flamethrower",
		displayName = "Flamethrower",
		archetype = "Elemental",
		baseDmg = 9,
		fireRate = 12,
		magSize = 120,
		reloadTime = 3.0,
		spread = 0,
		auto = true,
		mode = "stream",
		stream = { element = "fire", range = 22.5, angle = 14 }, -- Round 24aa: +25% reach (was 18)
	}),
	def({
		id = "CryoSprayer",
		displayName = "Cryo Sprayer",
		archetype = "Elemental",
		baseDmg = 6,
		fireRate = 12,
		magSize = 120,
		reloadTime = 3.0,
		spread = 0,
		auto = true,
		mode = "stream",
		stream = { element = "frost", range = 16, angle = 16 },
	}),
	def({
		id = "ArcGun",
		displayName = "Arc Gun",
		archetype = "Elemental",
		baseDmg = 11,
		fireRate = 12,
		magSize = 100,
		reloadTime = 2.6,
		spread = 0,
		auto = true,
		mode = "chain",
		chain = { range = 26, angle = 10, chains = 3, chainRange = 12, decay = 0.7 },
	}),
	def({
		id = "PlasmaCaster",
		displayName = "Plasma Caster",
		archetype = "Elemental",
		baseDmg = 45,
		fireRate = 1.6,
		magSize = 24,
		reloadTime = 2.4,
		spread = 0,
		mode = "charge",
		-- Hold to charge up to `sec`: a full charge spends maxCost cells for a beam maxDmgMult harder and wider.
		-- The beam passes through walls and every enemy on its line.
		charge = {
			sec = 1.4,
			maxCost = 6,
			maxDmgMult = 5,
			minWidth = 0.25, -- a thin laser uncharged...
			maxWidth = 3.5, -- ...a thick ray at full charge
			minDur = 0.08, -- seconds the beam holds uncharged (one hit)...
			maxDur = 1.0, -- ...and at full charge,
			maxTicks = 6, -- hitting this many times
			range = 160, -- set and long, whatever the charge
		},
	}),
	-- Round 24ad: the former showcase guns, now real. Crate / Event sale: no Gold unlock, no crate drops them yet;
	-- debug UNLOCK ALL grants them. Each has its own twist.
	def({
		id = "Exogun",
		displayName = "Exogun",
		archetype = "Rifle",
		baseDmg = 24,
		fireRate = 9,
		magSize = 40,
		reloadTime = 2.2,
		spread = 1.2,
		auto = true,
		saleType = "Crate",
		tracer = "5FE8FF", -- energy rounds: cyan lines
	}),
	def({
		id = "StormLinker",
		displayName = "StormLinker",
		archetype = "SMG",
		baseDmg = 14,
		fireRate = 15,
		magSize = 45,
		reloadTime = 1.8,
		spread = 2.6,
		auto = true,
		saleType = "Crate",
		tracer = "B07CFF", -- violet lines
	}),
	def({
		id = "Railcaster",
		displayName = "Railcaster",
		archetype = "Sniper",
		baseDmg = 160,
		fireRate = 0.9,
		magSize = 4,
		reloadTime = 3.0,
		spread = 0,
		saleType = "Event",
		-- A charged rail: hold to charge, release a thin blue slug-line that pierces walls and every enemy on it,
		-- harder the longer it charged. One round a shot.
		mode = "charge",
		charge = {
			sec = 1.1,
			maxCost = 1,
			maxDmgMult = 2.5,
			minWidth = 0.18,
			maxWidth = 0.55,
			minDur = 0.06,
			maxDur = 0.06,
			maxTicks = 1,
			range = 260,
			color = "7FD8FF",
		},
	}),
	def({
		id = "Hornet",
		displayName = "Hornet",
		archetype = "Pistol",
		baseDmg = 26,
		fireRate = 13, -- inside the burst
		burst = 3,
		burstDelay = 0.32,
		magSize = 15,
		reloadTime = 1.4,
		spread = 1.3,
		saleType = "Event",
	}),
	-- Brief 6: the ARMS CRATE pool (Crates.lua). Common-level paper DPS like the rest, each with its own look;
	-- never Gold-priced (saleType Crate). The FAL and the Mosin also come in bundles.
	def({
		id = "MAC10",
		displayName = "MAC-10",
		archetype = "SMG",
		baseDmg = 11,
		fireRate = 16,
		magSize = 30,
		reloadTime = 1.5,
		spread = 3.8,
		auto = true,
		saleType = "Crate",
		look = { color = "2B2B30", body = 0.9, barrel = 0.25, stock = false, mag = "box", scope = false },
	}),
	def({
		id = "Skorpion",
		displayName = "Skorpion",
		archetype = "SMG",
		baseDmg = 13,
		fireRate = 13,
		magSize = 20,
		reloadTime = 1.4,
		spread = 2.8,
		auto = true,
		saleType = "Crate",
		look = { color = "6E5A3A", body = 1.0, barrel = 0.35, stock = true, mag = "box", scope = false },
	}),
	def({
		id = "AUG",
		displayName = "AUG",
		archetype = "Rifle",
		baseDmg = 17,
		fireRate = 9.5,
		magSize = 30,
		reloadTime = 2.0,
		spread = 1.3,
		auto = true,
		saleType = "Crate",
		look = { color = "5C7A52", body = 1.4, barrel = 0.35, stock = false, mag = "box", scope = true },
	}),
	def({
		id = "PS90",
		displayName = "PS90",
		archetype = "SMG",
		baseDmg = 10,
		fireRate = 16,
		magSize = 50,
		reloadTime = 2.1,
		spread = 3.0,
		auto = true,
		saleType = "Crate",
		look = { color = "C9B98F", body = 1.3, barrel = 0.2, stock = false, mag = "none", scope = true },
	}),
	def({
		id = "FAL",
		displayName = "FAL",
		archetype = "Rifle",
		baseDmg = 34,
		fireRate = 4.8,
		magSize = 20,
		reloadTime = 2.2,
		spread = 1.1,
		saleType = "Crate",
		look = { color = "7A4E2D", body = 1.7, barrel = 0.55, stock = true, mag = "box", scope = false },
	}),
	def({
		id = "Model1887",
		displayName = "Model 1887",
		archetype = "Shotgun",
		baseDmg = 16,
		fireRate = 1.5,
		magSize = 6,
		reloadTime = 0.5, -- per shell (lever-action tube)
		spread = 6.5,
		pellets = 7,
		shellReload = true,
		saleType = "Crate",
		look = { color = "8A5A2B", body = 1.5, barrel = 0.7, stock = true, mag = "tube", scope = false },
	}),
	def({
		id = "Mosin",
		displayName = "Mosin",
		archetype = "Sniper",
		baseDmg = 160,
		fireRate = 0.85,
		magSize = 5,
		reloadTime = 2.8,
		spread = 0.2,
		pierceByRarity = { 1, 1, 2, 3, 4 },
		saleType = "Crate",
		look = { color = "5A3A22", body = 1.9, barrel = 0.9, stock = true, mag = "none", scope = true },
	}),
	def({
		id = "Gold1911",
		displayName = "1911 Gold",
		archetype = "Pistol",
		baseDmg = 36,
		fireRate = 3.8,
		magSize = 8,
		reloadTime = 1.1,
		spread = 1.0,
		saleType = "Crate",
		look = { color = "E8B64C", body = 0.85, barrel = 0.2, stock = false, mag = "box", scope = false },
	}),
} :: { Weapon }

-- Armory rarity: the tile and detail color on the Weapons tab (Rarity.Colors). The in-run drop rarity is still
-- rolled per instance and multiplies damage; this one is the gun's own tier in the collection.
Weapons.ArmoryRarity = {
	M1911 = 1,
	Glock = 1,
	UZI = 1,
	MP5 = 2,
	["AK-47"] = 1,
	M4A1 = 2,
	["SPAS-12"] = 1,
	AWP = 2,
	Deagle = 3,
	P90 = 3,
	["SCAR-H"] = 3,
	SawedOff = 2,
	M82 = 4,
	M249 = 2,
	RPK = 3,
	-- Round 24ad: the former showcase guns
	Exogun = 5,
	StormLinker = 4,
	Railcaster = 5,
	Hornet = 4,
	-- Round 24v: Explosive / Elemental
	RPG7 = 3,
	M32 = 3,
	ClusterLauncher = 4,
	TNT = 2,
	Flamethrower = 3,
	CryoSprayer = 3,
	ArcGun = 4,
	PlasmaCaster = 4,
	-- Round 24s
	Python = 2,
	M93R = 3,
	AA12 = 4,
	M870 = 1,
	SVD = 3,
	Kar98k = 2,
	PKM = 3,
	MG42 = 4,
	-- Brief 6 crate guns: the rarity is also the crate tier they drop at.
	MAC10 = 1,
	Skorpion = 1,
	AUG = 2,
	PS90 = 2,
	FAL = 3,
	Model1887 = 3,
	Mosin = 4,
	Gold1911 = 5,
} :: { [string]: number }

Weapons.ById = {} :: { [string]: Weapon }
for _, w in Weapons.List do
	w.rarity = Weapons.ArmoryRarity[w.id] or 1
	Weapons.ById[w.id] = w
end

Weapons.Starter = "M1911"

-- Owned by every fresh profile: one gun of each archetype, so every type is testable without buying.
Weapons.DefaultOwned = { "M1911", "UZI", "AK-47", "SPAS-12", "AWP", "M249" }

-- Showcase entries for the Weapons tab only: fake Crate / Event guns that render with their acquisition
-- label and can never be unlocked, rolled or dealt (they are not in Weapons.List). Their stats are
-- placeholders so the detail card reads like a real gun's.
export type Showcase = {
	id: string,
	displayName: string,
	archetype: string,
	saleType: string,
	hint: string,
	rarity: number,
	baseDmg: number,
	fireRate: number,
	magSize: number,
	reloadTime: number,
	pellets: number,
}
Weapons.Showcase = {
	-- Round 24ad: the four showcase guns are real weapons now (Weapons.List, Crate / Event sale: debug UNLOCK ALL).
} :: { Showcase }

-- Armory level math (Config.Upg*Pct): applied to the base stats before rarity and in-run upgrades,
-- everywhere the weapon appears (starter, rolls, crate deals, floor tags).
-- Round 19e: the weapon type as the cards print it (PISTOL, SMG, RIFLE, SHOTGUN, SNIPER, LMG); "" for an unknown id.
function Weapons.typeName(weaponId: string?): string
	local w = weaponId and Weapons.ById[weaponId]
	return if w then string.upper(w.archetype) else ""
end

-- Round 24ac: levels are mostly DAMAGE (a straight line). Mag, reload and fire rate rise on a soft cap: quick at
-- first, then flattening toward a small ceiling (UpgSoftCap), so a levelled gun still feels like its archetype (a
-- bolt-action stays slow, a 5-round mag stays small). soft(level, cap) -> 0..cap, about 63% of it at UpgSoftScale.
local function soft(level: number, cap: number): number
	return cap * (1 - math.exp(-math.max(0, level) / math.max(Config.UpgSoftScale, 1)))
end

function Weapons.levelDmgMult(level: number): number
	return 1 + Config.UpgDmgPct * math.max(0, level)
end

function Weapons.levelMagMult(level: number): number
	return 1 + soft(level, Config.UpgSoftCap.mag)
end

function Weapons.levelReloadDiv(level: number): number
	return 1 + soft(level, Config.UpgSoftCap.reload)
end

function Weapons.levelRateMult(level: number): number
	return 1 + soft(level, Config.UpgSoftCap.rate)
end

-- Base stats at an Armory level, before rarity and in-run upgrades.
function Weapons.atLevel(
	w: Weapon,
	level: number
): { dmg: number, fireRate: number, magSize: number, reloadTime: number }
	return {
		dmg = w.baseDmg * Weapons.levelDmgMult(level),
		fireRate = w.fireRate * Weapons.levelRateMult(level),
		magSize = math.max(1, math.round(w.magSize * Weapons.levelMagMult(level))),
		reloadTime = w.reloadTime / Weapons.levelReloadDiv(level),
	}
end

-- Damage per shot of a gun: Armory level, then in-run damage pct, then rarity (Stats.weaponDamage on the server;
-- the client uses it for the floor-gun tags, which show the viewer's own level and upgrades).
function Weapons.damageAt(weaponId: string, rarity: number, dmgPct: number, level: number?): number
	local w = Weapons.ById[weaponId]
	return Weapons.atLevel(w, level or 0).dmg * math.max(0.2, 1 + dmgPct) * Config.RarityDmgMult[rarity]
end

-- Gold cost of the next level: upgBaseCost x RarityUpgCostMult ^ level (both 100 / 1.0 in the prototype).
function Weapons.upgradeCost(w: Weapon, level: number): number
	return math.round((w.upgBaseCost or Prices.weaponUpgrade) * Config.RarityUpgCostMult ^ math.max(0, level))
end

function Weapons.unlockCost(w: Weapon): number
	return w.unlockCost or Prices.weaponUnlock
end

return Weapons
