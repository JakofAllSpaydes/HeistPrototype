--!strict
-- All stat math lives here. final = base * (1 + sum of upgrade pct) * rarityMult.
-- The client never computes a stat; it displays what StateSync sends.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Weapons = require(Shared.Weapons)
local Types = require(Shared.Types)

local Stats = {}

local function pct(upgrades: { [string]: Types.TrackerItem }, id: string): number
	local u = upgrades[id]
	return if u then u.pct / 100 else 0
end

-- Raw points for an additive stat (chances in %, flat counts).
local function points(upgrades: { [string]: Types.TrackerItem }, id: string): number
	local u = upgrades[id]
	return if u then u.pct else 0
end

-- Multiplier for a multiplicative stat, floored so a pile of maluses never hits zero or flips sign.
local function mult(upgrades: { [string]: Types.TrackerItem }, id: string): number
	return math.max(0.2, 1 + pct(upgrades, id))
end

function Stats.weaponDamage(weaponId: string, rarity: number, dmgPct: number): number
	local w = Weapons.ById[weaponId]
	return w.baseDmg * math.max(0.2, 1 + dmgPct) * Config.RarityDmgMult[rarity]
end

export type Buffs = { fireRateMult: number, moveSpeedMult: number, reloadSpeedMult: number }

-- DPS as shown on tags and the held slot: damage x shots per second x pellets.
function Stats.weaponDps(weaponId: string, rarity: number, upgrades: { [string]: Types.TrackerItem }): number
	local w = Weapons.ById[weaponId]
	return Stats.weaponDamage(weaponId, rarity, pct(upgrades, "Damage"))
		* Weapons.effectiveRate(w, mult(upgrades, "FireRate"))
		* w.pellets
end

function Stats.compute(upgrades: { [string]: Types.TrackerItem }, held: Types.Held, buffs: Buffs?): Types.Computed
	local w = Weapons.ById[held.weaponId]
	local crit = upgrades.CritChance
	local b = buffs or { fireRateMult = 1, moveSpeedMult = 1, reloadSpeedMult = 1 }
	return {
		damage = Stats.weaponDamage(held.weaponId, held.rarity, pct(upgrades, "Damage")),
		fireRate = w.fireRate * mult(upgrades, "FireRate") * b.fireRateMult,
		magSize = math.max(1, math.round(w.magSize * mult(upgrades, "MagSize"))),
		reloadTime = w.reloadTime / (mult(upgrades, "ReloadSpeed") * b.reloadSpeedMult),
		maxHP = math.max(1, math.round(Config.PlayerMaxHP * mult(upgrades, "MaxHP"))),
		hpRegen = Config.PlayerHPRegenPerSec * mult(upgrades, "HPRegen"),
		moveSpeed = Config.PlayerWalkSpeed * mult(upgrades, "MoveSpeed") * b.moveSpeedMult,
		critChance = math.max(0, Config.BaseCritChancePct + (if crit then crit.pct else 0)),
		headshotMult = Config.HeadshotMult * mult(upgrades, "HeadshotMult"),
		greed = mult(upgrades, "Greed"),
		spreadMult = math.clamp(1 - pct(upgrades, "Accuracy"), 0.05, 3),
		pierce = math.max(0, math.floor(points(upgrades, "Pierce"))) + Weapons.builtInPierce(w, held.rarity),
		ricochet = math.max(0, points(upgrades, "Ricochet")),
		splash = math.max(0, points(upgrades, "Splash")),
		multishot = math.max(0, points(upgrades, "Multishot")),
		lifesteal = math.max(0, points(upgrades, "Lifesteal")),
	}
end

function Stats.upgradePrice(n: number): number
	return math.round(Config.UpgradePrice * Config.UpgradePriceMult ^ n)
end

function Stats.weaponPrice(n: number): number
	return math.round(Config.WeaponPrice * Config.WeaponPriceMult ^ n)
end

return Stats
