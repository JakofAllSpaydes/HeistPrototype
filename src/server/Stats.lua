--!strict
-- All stat math lives here. final = base x level mult x (1 + sum of upgrade pct) x rarityMult.
-- The Armory level (Weapons.atLevel) applies before rarity and in-run upgrades, everywhere the weapon
-- appears. The client never computes a stat; it displays what StateSync sends.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Weapons = require(Shared.Weapons)
local Types = require(Shared.Types)
local Skills = require(Shared.Skills)

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

function Stats.weaponDamage(
	weaponId: string,
	rarity: number,
	dmgPct: number,
	level: number?,
	bonus: Weapons.Bonus?
): number
	return Weapons.damageAt(weaponId, rarity, dmgPct, level, bonus)
end

-- A self buff (stim, stim shot, dead eye): multipliers on top of upgrades.
export type Buffs = {
	fireRateMult: number,
	moveSpeedMult: number,
	reloadSpeedMult: number,
	damageMult: number,
	pierceAdd: number, -- extra pierce (dead eye)
	spreadMult: number?, -- Round 19c: x spread (dead eye's accuracy); nil = 1
}

-- DPS as shown on tags and the held slot: damage x shots per second x pellets.
function Stats.weaponDps(
	weaponId: string,
	rarity: number,
	upgrades: { [string]: Types.TrackerItem },
	level: number?,
	skills: Skills.Mods?
): number
	local w = Weapons.ById[weaponId]
	local bonus = if skills then Skills.weaponBonus(skills, w.archetype) else nil
	return Stats.weaponDamage(weaponId, rarity, pct(upgrades, "Damage"), level, bonus)
		* Weapons.effectiveRate(w, mult(upgrades, "FireRate") * Weapons.levelRateMult(level or 0))
		* w.pellets
end

-- Brief 9: `skills` is the player's armed Skill Web modifier table (Skills.modifiers): percents add at the Armory
-- stage (weapon damage / mag / reload through Weapons.atLevel) or to the base before the run's upgrade multipliers.
function Stats.compute(
	upgrades: { [string]: Types.TrackerItem },
	held: Types.Held,
	buffs: Buffs?,
	skills: Skills.Mods?
): Types.Computed
	local w = Weapons.ById[held.weaponId]
	local sk = skills or Skills.zero()
	local bonus = Skills.weaponBonus(sk, w.archetype)
	local base = Weapons.atLevel(w, held.level or 0, bonus)
	local crit = upgrades.CritChance
	local b: Buffs = buffs
		or { fireRateMult = 1, moveSpeedMult = 1, reloadSpeedMult = 1, damageMult = 1, pierceAdd = 0, spreadMult = 1 }
	-- ELEMENTAL POWER (synergy) raises every held element's power; an element not held stays at 0.
	local elemMult = 1 + math.max(0, pct(upgrades, "ElementalPower"))
	local function boost(id: string): number
		return 1 + math.max(0, pct(upgrades, id))
	end
	-- Round 25: the archetype synergies raise their own guns' damage: ELEMENTAL POWER an Elemental gun's,
	-- DEMOLITION an Explosive gun's (it raises Frag / Claymore / Splash through explosiveDmgMult too).
	local archMult = if w.archetype == "Elemental"
		then elemMult
		elseif w.archetype == "Explosive" then boost("Demolition")
		else 1
	return {
		damage = Stats.weaponDamage(held.weaponId, held.rarity, pct(upgrades, "Damage"), held.level, bonus)
			* b.damageMult
			* archMult,
		fireRate = base.fireRate * mult(upgrades, "FireRate") * b.fireRateMult,
		magSize = math.max(1, math.round(base.magSize * mult(upgrades, "MagSize"))),
		reloadTime = base.reloadTime / (mult(upgrades, "ReloadSpeed") * b.reloadSpeedMult),
		maxHP = math.max(1, math.round(Config.PlayerMaxHP * (1 + sk.maxHpPct) * mult(upgrades, "MaxHP"))),
		hpRegen = (Config.PlayerHPRegenPerSec + sk.hpRegenFlat) * mult(upgrades, "HPRegen"),
		moveSpeed = Config.PlayerWalkSpeed * (1 + sk.moveSpeedPct) * mult(upgrades, "MoveSpeed") * b.moveSpeedMult,
		critChance = math.max(0, Config.BaseCritChancePct + sk.critPct * 100 + (if crit then crit.pct else 0)),
		headshotMult = Config.HeadshotMult * (1 + sk.headshotPct) * mult(upgrades, "HeadshotMult"),
		cashGain = mult(upgrades, "CashGain"),
		abilityCdr = math.clamp(points(upgrades, "AbilityCooldown"), -100, Config.AbilityCooldownCap) / 100,
		abilityPower = mult(upgrades, "AbilityPower"),
		incendiaryPower = power(upgrades, "Incendiary") * elemMult,
		cryoPower = power(upgrades, "Cryo") * elemMult,
		concussivePower = power(upgrades, "Concussive") * elemMult,
		spreadMult = math.clamp(1 - pct(upgrades, "Accuracy"), 0.05, 3) * (b.spreadMult or 1),
		pierce = math.max(0, math.floor(points(upgrades, "Pierce")))
			+ Weapons.builtInPierce(w, held.rarity)
			+ b.pierceAdd,
		ricochet = math.max(0, points(upgrades, "Ricochet")),
		splash = math.max(0, points(upgrades, "Splash")),
		multishot = math.max(0, points(upgrades, "Multishot")),
		lifesteal = math.max(0, points(upgrades, "Lifesteal")),
		wildfire = math.clamp(points(upgrades, "Wildfire"), 0, Config.WildfireMaxPct),
		shatter = math.max(0, points(upgrades, "Shatter")),
		aftershock = math.max(0, points(upgrades, "Aftershock")),
		fireAbilityMult = boost("Accelerant"),
		turretDmgMult = boost("TurretDamage"),
		healMult = boost("HealPower"),
		deadEyeTimeMult = boost("DeadEyeTime"),
		blastRadiusMult = boost("BlastRadius"),
		explosiveDmgMult = boost("Demolition"),
	}
end

function Stats.upgradePrice(n: number): number
	return math.round(Config.UpgradePrice * Config.UpgradePriceMult ^ n)
end

return Stats
