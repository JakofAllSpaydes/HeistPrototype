--!strict
-- All stat math lives here. final = base x level mult x (1 + sum of upgrade pct) x rarityMult.
-- The Armory level (Weapons.atLevel) applies before rarity and in-run upgrades, everywhere the weapon
-- appears. The client never computes a stat; it displays what StateSync sends.
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

-- An element's power: its running total / 100 (100% on the first take), 0 when not held.
local function power(upgrades: { [string]: Types.TrackerItem }, id: string): number
	local u = upgrades[id]
	return if u then math.max(0, u.pct / 100) else 0
end

-- Multiplier for a multiplicative stat, floored so a pile of maluses never hits zero or flips sign.
local function mult(upgrades: { [string]: Types.TrackerItem }, id: string): number
	return math.max(0.2, 1 + pct(upgrades, id))
end

function Stats.weaponDamage(weaponId: string, rarity: number, dmgPct: number, level: number?): number
	return Weapons.damageAt(weaponId, rarity, dmgPct, level)
end

-- A self buff (stim, stim shot, dead eye): multipliers on top of upgrades.
export type Buffs = {
	fireRateMult: number,
	moveSpeedMult: number,
	reloadSpeedMult: number,
	damageMult: number,
	pierceAdd: number, -- extra pierce (dead eye)
}

-- DPS as shown on tags and the held slot: damage x shots per second x pellets.
function Stats.weaponDps(
	weaponId: string,
	rarity: number,
	upgrades: { [string]: Types.TrackerItem },
	level: number?
): number
	local w = Weapons.ById[weaponId]
	return Stats.weaponDamage(weaponId, rarity, pct(upgrades, "Damage"), level)
		* Weapons.effectiveRate(w, mult(upgrades, "FireRate") * Weapons.levelRateMult(level or 0))
		* w.pellets
end

function Stats.compute(upgrades: { [string]: Types.TrackerItem }, held: Types.Held, buffs: Buffs?): Types.Computed
	local w = Weapons.ById[held.weaponId]
	local base = Weapons.atLevel(w, held.level or 0)
	local crit = upgrades.CritChance
	local b = buffs or { fireRateMult = 1, moveSpeedMult = 1, reloadSpeedMult = 1, damageMult = 1, pierceAdd = 0 }
	return {
		damage = Stats.weaponDamage(held.weaponId, held.rarity, pct(upgrades, "Damage"), held.level) * b.damageMult,
		fireRate = base.fireRate * mult(upgrades, "FireRate") * b.fireRateMult,
		magSize = math.max(1, math.round(base.magSize * mult(upgrades, "MagSize"))),
		reloadTime = base.reloadTime / (mult(upgrades, "ReloadSpeed") * b.reloadSpeedMult),
		maxHP = math.max(1, math.round(Config.PlayerMaxHP * mult(upgrades, "MaxHP"))),
		hpRegen = Config.PlayerHPRegenPerSec * mult(upgrades, "HPRegen"),
		moveSpeed = Config.PlayerWalkSpeed * mult(upgrades, "MoveSpeed") * b.moveSpeedMult,
		critChance = math.max(0, Config.BaseCritChancePct + (if crit then crit.pct else 0)),
		headshotMult = Config.HeadshotMult * mult(upgrades, "HeadshotMult"),
		cashGain = mult(upgrades, "CashGain"),
		abilityCdr = math.clamp(points(upgrades, "AbilityCooldown"), -100, Config.AbilityCooldownCap) / 100,
		abilityPower = mult(upgrades, "AbilityPower"),
		incendiaryPower = power(upgrades, "Incendiary"),
		cryoPower = power(upgrades, "Cryo"),
		concussivePower = power(upgrades, "Concussive"),
		spreadMult = math.clamp(1 - pct(upgrades, "Accuracy"), 0.05, 3),
		pierce = math.max(0, math.floor(points(upgrades, "Pierce")))
			+ Weapons.builtInPierce(w, held.rarity)
			+ b.pierceAdd,
		ricochet = math.max(0, points(upgrades, "Ricochet")),
		splash = math.max(0, points(upgrades, "Splash")),
		multishot = math.max(0, points(upgrades, "Multishot")),
		lifesteal = math.max(0, points(upgrades, "Lifesteal")),
	}
end

function Stats.upgradePrice(n: number): number
	return math.round(Config.UpgradePrice * Config.UpgradePriceMult ^ n)
end

return Stats
