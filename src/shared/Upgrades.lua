--!strict
-- Stat list, display names per stat x tier, magnitude matrix and tradeoff rules for the pick-3.
local Config = require(script.Parent.Config)

-- unit: "%" for percent stats, "" for flat counts (Pierce). additive = added in points, not multiplying a base.
-- noMalus: never picked as the malus side of a tradeoff card (flat counts would go negative).
export type Stat = { id: string, name: string, short: string, additive: boolean, unit: string, noMalus: boolean? }

local Upgrades = {}

-- Prototype list is gun-focused plus Move Speed so every pick is felt. Max HP, HP Regen and Greed are
-- still supported by Stats if you add them back here (names and magnitudes below).
Upgrades.Stats = {
	{ id = "Damage", name = "Damage", short = "DMG", additive = false, unit = "%" },
	{ id = "FireRate", name = "Fire Rate", short = "RPM", additive = false, unit = "%" },
	{ id = "MagSize", name = "Mag Size", short = "MAG", additive = false, unit = "%" },
	{ id = "ReloadSpeed", name = "Reload Speed", short = "RLD", additive = false, unit = "%" },
	{ id = "CritChance", name = "Crit Chance", short = "CRT", additive = true, unit = "%" },
	{ id = "HeadshotMult", name = "Headshot Mult", short = "HS", additive = false, unit = "%" },
	{ id = "MoveSpeed", name = "Move Speed", short = "SPD", additive = false, unit = "%" },
	{ id = "Accuracy", name = "Accuracy", short = "ACC", additive = false, unit = "%" },
	{ id = "Pierce", name = "Pierce", short = "PRC", additive = true, unit = "", noMalus = true },
	{ id = "Ricochet", name = "Ricochet", short = "RIC", additive = true, unit = "%" },
	{ id = "Splash", name = "Splash", short = "SPL", additive = true, unit = "%" },
	{ id = "Multishot", name = "Multishot", short = "MLT", additive = true, unit = "%" },
	{ id = "Lifesteal", name = "Lifesteal", short = "LFS", additive = true, unit = "%" },
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
	Greed = { "Pocket Change", "Loose Cash", "Big Spender", "High Roller", "Kingpin" },
	Accuracy = { "Steady Hands", "Tight Grouping", "Laser Focus", "Surgical", "Pinpoint" },
	Pierce = { "Punch Through", "Drill Rounds", "Overpenetrate", "Line Breaker", "Railgun" },
	Ricochet = { "Lucky Bounce", "Trick Shot", "Pinball", "Bank Shot", "Pool Shark" },
	Splash = { "Hot Rounds", "Frag Tips", "Blast Caps", "Demolition", "Fireworks" },
	Multishot = { "Double Tap", "Twin Bore", "Scatter", "Volley", "Wall of Lead" },
	Lifesteal = { "Vampire Rounds", "Bloodletter", "Leech", "Siphon", "Hemophage" },
} :: { [string]: { string } }

-- Magnitude per stat x tier (1..5). Percent for "%" stats, flat count for "" stats.
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
	Greed = { 15, 25, 35, 50, 70 },
	Accuracy = { 20, 30, 40, 55, 70 }, -- % less spread
	Pierce = { 1, 1, 2, 2, 3 }, -- extra enemies a bullet passes through
	Ricochet = { 15, 25, 35, 50, 65 }, -- % chance a hit bounces to a nearby enemy
	Splash = { 30, 45, 60, 80, 100 }, -- % of the killing hit dealt to enemies near a kill
	Multishot = { 15, 25, 35, 50, 70 }, -- % chance each shot fires an extra bullet
	Lifesteal = { 3, 5, 8, 12, 16 }, -- % of damage dealt healed
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

-- "+11%" / "-5%" / "+1" (flat)
function Upgrades.pctText(value: number, statId: string?): string
	local sign = if value >= 0 then "+" else "-"
	return string.format("%s%s%s", sign, fmtValue(value), if statId then Upgrades.unit(statId) else "%")
end

-- "+11% DAMAGE" / "-5% FIRE RATE" / "+1 PIERCE"
function Upgrades.effectLine(statId: string, value: number): string
	return string.format("%s %s", Upgrades.pctText(value, statId), string.upper(Upgrades.statName(statId)))
end

-- "T1 +8 · T2 +11 · T3 +15 · T4 +20 · T5 +28"
function Upgrades.tierTable(statId: string): string
	local parts = {}
	for tier, v in Upgrades.Magnitude[statId] do
		table.insert(parts, string.format("T%d +%s", tier, fmtValue(v)))
	end
	return table.concat(parts, " · ")
end

return Upgrades
