--!strict
-- Stat list, display names per stat x tier, magnitude matrix and tradeoff rules for the pick-3.
local Config = require(script.Parent.Config)

export type Stat = { id: string, name: string, short: string, additive: boolean }

local Upgrades = {}

-- additive = true means the magnitude is added in percentage points instead of multiplying a base.
-- Prototype list is gun-focused plus Move Speed so every pick is felt. Max HP, HP Regen and Greed are
-- still supported by Stats if you add them back here (names and magnitudes below).
Upgrades.Stats = {
	{ id = "Damage", name = "Damage", short = "DMG", additive = false },
	{ id = "FireRate", name = "Fire Rate", short = "RPM", additive = false },
	{ id = "MagSize", name = "Mag Size", short = "MAG", additive = false },
	{ id = "ReloadSpeed", name = "Reload Speed", short = "RLD", additive = false },
	{ id = "CritChance", name = "Crit Chance", short = "CRT", additive = true },
	{ id = "HeadshotMult", name = "Headshot Mult", short = "HS", additive = false },
	{ id = "MoveSpeed", name = "Move Speed", short = "SPD", additive = false },
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
} :: { [string]: { string } }

-- Magnitude in % per stat x tier (1..5). CritChance is in percentage points.
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

local function fmtPct(value: number): string
	local v = math.abs(value)
	return if v == math.floor(v) then string.format("%d", v) else string.format("%.1f", v)
end

-- "+11% DAMAGE" / "-5% FIRE RATE"
function Upgrades.effectLine(statId: string, pct: number): string
	local sign = if pct >= 0 then "+" else "-"
	return string.format("%s%s%% %s", sign, fmtPct(pct), string.upper(Upgrades.statName(statId)))
end

-- "+11%" / "-5%"
function Upgrades.pctText(pct: number): string
	local sign = if pct >= 0 then "+" else "-"
	return string.format("%s%s%%", sign, fmtPct(pct))
end

-- "T1 +8 · T2 +11 · T3 +15 · T4 +20 · T5 +28"
function Upgrades.tierTable(statId: string): string
	local parts = {}
	for tier, v in Upgrades.Magnitude[statId] do
		table.insert(parts, string.format("T%d +%d", tier, v))
	end
	return table.concat(parts, " · ")
end

return Upgrades
