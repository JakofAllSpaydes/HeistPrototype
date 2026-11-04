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
	-- Meta (Armory): how the gun is acquired and what its levels cost. Prices.lua holds the numbers.
	saleType: string, -- Direct | Crate | Event
	unlockCost: number?, -- nil = Prices.weaponUnlock
	upgBaseCost: number?, -- nil = Prices.weaponUpgrade
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
} :: { Weapon }

Weapons.ById = {} :: { [string]: Weapon }
for _, w in Weapons.List do
	Weapons.ById[w.id] = w
end

Weapons.Starter = "M1911"

-- Owned by every fresh profile: one gun of each archetype, so every type is testable without buying.
Weapons.DefaultOwned = { "M1911", "UZI", "AK-47", "SPAS-12", "AWP", "M249" }

-- Showcase entries for the Weapons tab only: fake Crate / Event guns that render with their acquisition
-- label and can never be unlocked, rolled or dealt (they are not in Weapons.List).
export type Showcase = { id: string, displayName: string, archetype: string, saleType: string, hint: string }
Weapons.Showcase = {
	{ id = "Exogun", displayName = "Exogun", archetype = "Rifle", saleType = "Crate", hint = "Energy" },
	{ id = "StormLinker", displayName = "StormLinker", archetype = "SMG", saleType = "Crate", hint = "Automatic" },
	{ id = "Railcaster", displayName = "Railcaster", archetype = "Sniper", saleType = "Event", hint = "Charged" },
	{ id = "Hornet", displayName = "Hornet", archetype = "Pistol", saleType = "Event", hint = "Burst" },
} :: { Showcase }

-- Armory level math (Config.Upg*Pct): applied to the base stats before rarity and in-run upgrades,
-- everywhere the weapon appears (starter, rolls, crate deals, floor tags).
function Weapons.levelDmgMult(level: number): number
	return 1 + Config.UpgDmgPct * math.max(0, level)
end

function Weapons.levelMagMult(level: number): number
	return 1 + Config.UpgMagPct * math.max(0, level)
end

function Weapons.levelReloadDiv(level: number): number
	return 1 + Config.UpgReloadPct * math.max(0, level)
end

function Weapons.levelRateMult(level: number): number
	return 1 + Config.UpgFireRatePct * math.max(0, level)
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

-- Gold cost of the next level: upgBaseCost x RarityUpgCostMult ^ level (both 100 / 1.0 in the prototype).
function Weapons.upgradeCost(w: Weapon, level: number): number
	return math.round((w.upgBaseCost or Prices.weaponUpgrade) * Config.RarityUpgCostMult ^ math.max(0, level))
end

function Weapons.unlockCost(w: Weapon): number
	return w.unlockCost or Prices.weaponUnlock
end

return Weapons
