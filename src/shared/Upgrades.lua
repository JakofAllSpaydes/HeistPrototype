--!strict
-- Stat list, display names per stat x tier, magnitude matrix and tradeoff rules for the pick-3 and the dealer.
-- Brief 5: every stat has a category (gun | element | utility); the generator draws a category by
-- Config.CategoryWeights, then a stat inside it.
local Config = require(script.Parent.Config)

-- unit: "%" for percent stats, "" for flat counts (Pierce). additive = added in points, not multiplying a base.
-- noMalus: never picked as the malus side of a tradeoff card (flat counts would go negative; elements; cash gain).
-- negative: the stored value is shown negated (ABILITY COOLDOWN +12 in the tracker reads "-12%").
export type Stat = {
	id: string,
	name: string,
	short: string,
	additive: boolean,
	unit: string,
	category: string,
	noMalus: boolean?,
	negative: boolean?,
	effect: string?, -- elements: the effect the percent raises (Burn / Slow / Impact)
}

local Upgrades = {}

Upgrades.Categories = { "gun", "element", "utility" }

Upgrades.Stats = {
	{ id = "Damage", name = "Damage", short = "DMG", additive = false, unit = "%", category = "gun" },
	{ id = "FireRate", name = "Fire Rate", short = "RPM", additive = false, unit = "%", category = "gun" },
	{ id = "MagSize", name = "Mag Size", short = "MAG", additive = false, unit = "%", category = "gun" },
	{ id = "ReloadSpeed", name = "Reload Speed", short = "RLD", additive = false, unit = "%", category = "gun" },
	{ id = "CritChance", name = "Crit Chance", short = "CRT", additive = true, unit = "%", category = "gun" },
	{ id = "HeadshotMult", name = "Headshot Mult", short = "HS", additive = false, unit = "%", category = "gun" },
	{ id = "MoveSpeed", name = "Move Speed", short = "SPD", additive = false, unit = "%", category = "gun" },
	{ id = "Accuracy", name = "Accuracy", short = "ACC", additive = false, unit = "%", category = "gun" },
	{ id = "Pierce", name = "Pierce", short = "PRC", additive = true, unit = "", category = "gun", noMalus = true },
	{ id = "Ricochet", name = "Ricochet", short = "RIC", additive = true, unit = "%", category = "gun" },
	{ id = "Splash", name = "Splash", short = "SPL", additive = true, unit = "%", category = "gun" },
	{ id = "Multishot", name = "Multishot", short = "MLT", additive = true, unit = "%", category = "gun" },
	{ id = "Lifesteal", name = "Lifesteal", short = "LFS", additive = true, unit = "%", category = "gun" },
	-- Elements: the value is the effect's power in percent; every shot applies it. The first take grants 100% (the
	-- Config numbers); later takes add Magnitude[tier] (stronger burn and faster ticks, more slow, more knockback).
	-- Player-facing names are the ammo; `effect` is what the percent raises (the ids stay for saves and Config keys).
	{
		id = "Incendiary",
		name = "Fire Ammo",
		short = "FIR",
		effect = "Burn",
		additive = true,
		unit = "%",
		category = "element",
		noMalus = true,
	},
	{
		id = "Cryo",
		name = "Ice Ammo",
		short = "ICE",
		effect = "Slow",
		additive = true,
		unit = "%",
		category = "element",
		noMalus = true,
	},
	{
		id = "Concussive",
		name = "Impact Ammo",
		short = "IMP",
		effect = "Impact",
		additive = true,
		unit = "%",
		category = "element",
		noMalus = true,
	},
	-- Utility.
	{
		id = "AbilityCooldown",
		name = "Ability Cooldown",
		short = "CDR",
		additive = true,
		unit = "%",
		category = "utility",
		negative = true,
	},
	{ id = "AbilityPower", name = "Ability Power", short = "PWR", additive = false, unit = "%", category = "utility" },
	{
		id = "CashGain",
		name = "Cash Gain",
		short = "CSH",
		additive = false,
		unit = "%",
		category = "utility",
		noMalus = true,
	},
} :: { Stat }

-- Card name per stat x tier (1..5).
Upgrades.TierNames = {
	Damage = { "Sharpened", "Honed", "Lethal", "Brutal", "Apocalyptic" },
	FireRate = { "Quick Finger", "Trigger Happy", "Rapid Fire", "Hailstorm", "Bullet Hell" },
	MagSize = { "Extra Clip", "Extended Mag", "Drum Mag", "Belt Fed", "Bottomless" },
	ReloadSpeed = { "Fast Hands", "Slick Reload", "Speed Loader", "Lightning Hands", "Instant Swap" },
	MaxHP = { "Thick Skin", "Toughened", "Iron Hide", "Juggernaut", "Immortal" },
	HPRegen = { "Second Wind", "Field Patch", "Medkit", "Regenerator", "Phoenix" },
	MoveSpeed = { "Light Feet", "Sprinter", "Runner", "Blur", "Afterimage" },
	CritChance = { "Lucky Shot", "Keen Eye", "Marksman", "Deadeye", "Executioner" },
	HeadshotMult = { "Aim High", "Skull Cracker", "Brain Buster", "Decapitator", "Headhunter" },
	Accuracy = { "Steady Hands", "Tight Grouping", "Laser Focus", "Surgical", "Pinpoint" },
	Pierce = { "Punch Through", "Drill Rounds", "Overpenetrate", "Line Breaker", "Railgun" },
	Ricochet = { "Lucky Bounce", "Trick Shot", "Pinball", "Bank Shot", "Pool Shark" },
	Splash = { "Hot Rounds", "Frag Tips", "Blast Caps", "Demolition", "Fireworks" },
	Multishot = { "Double Tap", "Twin Bore", "Scatter", "Volley", "Wall of Lead" },
	Lifesteal = { "Vampire Rounds", "Bloodletter", "Leech", "Siphon", "Hemophage" },
	Incendiary = { "Fire Ammo", "Fire Ammo", "Fire Ammo", "Fire Ammo", "Fire Ammo" },
	Cryo = { "Ice Ammo", "Ice Ammo", "Ice Ammo", "Ice Ammo", "Ice Ammo" },
	Concussive = { "Impact Ammo", "Impact Ammo", "Impact Ammo", "Impact Ammo", "Impact Ammo" },
	AbilityCooldown = { "Quick Reset", "Fast Recharge", "Overcharged", "Hair Trigger", "Perpetual" },
	AbilityPower = { "Amped", "Boosted", "Supercharged", "Overload", "Maximum" },
	CashGain = { "Pocket Change", "Loose Cash", "Big Spender", "High Roller", "Kingpin" },
} :: { [string]: { string } }

-- Magnitude per stat x tier (1..5). Percent for "%" stats, flat count for "" stats. Elements: the power a later
-- take adds (the first take is 100%).
Upgrades.Magnitude = {
	Damage = { 15, 22, 30, 40, 55 },
	FireRate = { 12, 18, 25, 35, 50 },
	MagSize = { 20, 30, 45, 60, 80 },
	ReloadSpeed = { 15, 22, 30, 40, 55 },
	MaxHP = { 15, 25, 35, 50, 70 },
	HPRegen = { 50, 80, 120, 180, 260 },
	MoveSpeed = { 8, 12, 16, 22, 30 },
	CritChance = { 5, 10, 15, 22, 30 },
	HeadshotMult = { 20, 30, 45, 60, 80 },
	Accuracy = { 20, 30, 40, 55, 70 }, -- % less spread
	Pierce = { 1, 1, 2, 2, 3 }, -- extra enemies a bullet passes through
	Ricochet = { 15, 25, 35, 50, 65 }, -- % chance a hit bounces to a nearby enemy
	Splash = { 30, 45, 60, 80, 100 }, -- % of the killing hit dealt to enemies near a kill
	Multishot = { 15, 25, 35, 50, 70 }, -- % chance each shot fires an extra bullet
	Lifesteal = { 3, 5, 8, 12, 16 }, -- % of damage dealt healed
	Incendiary = { 20, 30, 45, 60, 80 }, -- % power a later take adds (the first take is 100%)
	Cryo = { 20, 30, 45, 60, 80 },
	Concussive = { 20, 30, 45, 60, 80 },
	AbilityCooldown = { 5, 8, 12, 16, 22 }, -- % shorter cooldowns (capped at Config.AbilityCooldownCap)
	AbilityPower = { 8, 12, 18, 25, 35 }, -- % more ability damage, heal and placeable HP
	CashGain = { 15, 25, 35, 50, 70 }, -- % more cash from kills, bags and job payouts
} :: { [string]: { number } }

Upgrades.TradeoffChance = Config.TradeoffChance
Upgrades.TradeoffMalusRatio = Config.TradeoffMalusRatio

function Upgrades.byId(id: string): Stat?
	for _, s in Upgrades.Stats do
		if s.id == id then
			return s
		end
	end
	return nil
end

function Upgrades.category(statId: string): string
	local s = Upgrades.byId(statId)
	return if s then s.category else "gun"
end

function Upgrades.isElement(statId: string): boolean
	return Upgrades.category(statId) == "element"
end

-- The power (percent) an element's first take grants: the effect at its Config numbers, on every shot.
function Upgrades.elementBase(_statId: string): number
	return 100
end

function Upgrades.magnitude(statId: string, tier: number): number
	local row = Upgrades.Magnitude[statId]
	return row[math.clamp(tier, 1, #row)]
end

function Upgrades.cardName(statId: string, tier: number): string
	local row = Upgrades.TierNames[statId]
	return row[math.clamp(tier, 1, #row)]
end

function Upgrades.statName(statId: string): string
	local s = Upgrades.byId(statId)
	return if s then s.name else statId
end

function Upgrades.shortName(statId: string): string
	local s = Upgrades.byId(statId)
	return if s then s.short else statId
end

function Upgrades.unit(statId: string): string
	local s = Upgrades.byId(statId)
	return if s then s.unit else "%"
end

local function fmtValue(value: number): string
	local v = math.abs(value)
	return if v == math.floor(v) then string.format("%d", v) else string.format("%.1f", v)
end

-- "+11%" / "-5%" / "+1" (flat); stats stored as a reduction (ability cooldown) read with the sign flipped.
function Upgrades.pctText(value: number, statId: string?): string
	local s = if statId then Upgrades.byId(statId) else nil
	local shown = if s and s.negative then -value else value
	local sign = if shown >= 0 then "+" else "-"
	return string.format("%s%s%s", sign, fmtValue(shown), if statId then Upgrades.unit(statId) else "%")
end

-- An element's effect noun in caps ("BURN"), nil for other stats.
function Upgrades.effectName(statId: string): string?
	local s = Upgrades.byId(statId)
	return if s and s.effect then string.upper(s.effect) else nil
end

-- An element card that grants the ammo (the first take, 100%) rather than strengthening it.
function Upgrades.isNewElement(statId: string, value: number): boolean
	return Upgrades.isElement(statId) and value >= Upgrades.elementBase(statId)
end

-- What a card shows: the big line and the small line under it. Gun / utility: "+22%" over "DAMAGE". Elements:
-- "NEW" over "BURN ON EVERY SHOT" for the first take, then "+30%" over "BURN".
function Upgrades.cardTexts(statId: string, value: number): (string, string)
	local effect = Upgrades.effectName(statId)
	if effect then
		if Upgrades.isNewElement(statId, value) then
			return "NEW", effect .. " ON EVERY SHOT"
		end
		return Upgrades.pctText(value, statId), effect
	end
	return Upgrades.pctText(value, statId), string.upper(Upgrades.statName(statId))
end

-- "+11% DAMAGE" / "-5% FIRE RATE" / "+1 PIERCE" / "+30% BURN" / "FIRE AMMO · BURN ON EVERY SHOT"
function Upgrades.effectLine(statId: string, value: number): string
	local effect = Upgrades.effectName(statId)
	if effect then
		if Upgrades.isNewElement(statId, value) then
			return string.format("%s · %s ON EVERY SHOT", string.upper(Upgrades.statName(statId)), effect)
		end
		return string.format("%s %s", Upgrades.pctText(value, statId), effect)
	end
	return string.format("%s %s", Upgrades.pctText(value, statId), string.upper(Upgrades.statName(statId)))
end

-- The tracker badge: elements show their power ("130%"), utility the running total ("-12%"), gun stats the count.
function Upgrades.badgeText(statId: string, item: { count: number, pct: number }): string
	local cat = Upgrades.category(statId)
	if cat == "element" then
		return string.format("%s%%", fmtValue(item.pct))
	elseif cat == "utility" then
		return Upgrades.pctText(item.pct, statId)
	end
	return string.format("x%d", item.count)
end

-- "T1 +8 · T2 +11 · T3 +15 · T4 +20 · T5 +28" (elements lead with the first take's 100%)
function Upgrades.tierTable(statId: string): string
	local parts = {}
	if Upgrades.isElement(statId) then
		table.insert(parts, string.format("FIRST %s%%", fmtValue(Upgrades.elementBase(statId))))
	end
	for tier, v in Upgrades.Magnitude[statId] do
		table.insert(parts, string.format("T%d +%s", tier, fmtValue(v)))
	end
	return table.concat(parts, " · ")
end

return Upgrades
