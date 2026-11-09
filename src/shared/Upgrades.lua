--!strict
-- Stat list, display names per stat x tier, magnitude matrix and tradeoff rules for the pick-3 and the dealer.
-- Brief 5: every stat has a category (gun | element | utility); the generator draws a category by
-- Config.CategoryWeights, then a stat inside it.
local Config = require(script.Parent.Config)
local Classes = require(script.Parent.Classes)

-- unit: "%" for percent stats, "" for flat counts (Pierce). additive = added in points, not multiplying a base.
-- noMalus: never picked as the malus side of a tradeoff card (flat counts would go negative; elements; cash gain).
-- negative: the stored value is shown negated (ABILITY COOLDOWN +12 in the tracker reads "-12%").
-- requires: a conditional (synergy) stat. It never enters the normal category draw; a card slot offers it at
-- Config.SynergyChance only while every condition holds (Upgrades.meets). Keys, all of which must hold:
--   element = "<element stat id>"  the player holds that element (Incendiary / Cryo / Concussive)
--   anyElement = true              the player holds at least one element
--   class = "<class id>"           the player's equipped class (Classes.lua ids: TORCH, ENGINEER, DOC, ...)
--   archetype = "<archetype>"      Round 25: a gun of that archetype in either loadout slot (Explosive, Elemental)
--   owns = "<stat id>"             Round 25: the player holds that upgrade (Splash: the kill explosions)
--   anyOf = { Requires, ... }       Round 25: passes when ANY one of these passes (on top of the keys above)
export type Requires = {
	element: string?,
	anyElement: boolean?,
	class: string?,
	archetype: string?,
	owns: string?,
	anyOf: { Requires }?,
}
export type Stat = {
	id: string,
	name: string,
	short: string,
	additive: boolean,
	unit: string,
	category: string,
	noMalus: boolean?,
	negative: boolean?,
	effect: string?, -- elements: the effect the percent raises (Burn / Slow / Stun); synergy stats: what it raises
	requires: Requires?,
	tag: string?, -- Round 25: the synergy pill's word ("EXPLOSIVE"), when `requires` alone can't name it
}

local Upgrades = {}

-- Round 25: shared conditions (cast per alternative so the mixed shapes type-check).
local ELEMENT_REQ: Requires = { anyOf = { { anyElement = true } :: Requires, { archetype = "Elemental" } :: Requires } }
local EXPLOSIVE_REQ: Requires = {
	anyOf = {
		{ archetype = "Explosive" } :: Requires,
		{ owns = "Splash" } :: Requires,
		{ class = "INITIATE" } :: Requires,
	},
}

-- The categories the normal draw weighs (Config.CategoryWeights). Conditional stats are category "synergy" and
-- are drawn on their own (Config.SynergyChance), never through these.
Upgrades.Categories = { "gun", "element", "defense", "utility" }

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
		id = "Concussive", -- (Round 21: shown as Stun, was Impact; the id stays for saves and logic)
		name = "Stun Ammo",
		short = "STN",
		effect = "Stun",
		additive = true,
		unit = "%",
		category = "element",
		noMalus = true,
	},
	-- Round 25: Defense. Max HP and HP Regen (their numbers were already in the matrix), and ARMOR: flat points of
	-- shield over HP that soak hits first and refill after ArmorRegenDelay seconds without damage.
	{ id = "MaxHP", name = "Max HP", short = "HP", additive = false, unit = "%", category = "defense" },
	{ id = "HPRegen", name = "HP Regen", short = "REG", additive = false, unit = "%", category = "defense" },
	{
		id = "Armor",
		name = "Armor",
		short = "ARM",
		additive = true,
		unit = "",
		category = "defense",
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
	-- Synergy (conditional): offered only while `requires` holds; never a tradeoff, never a malus. Every one is
	-- additive percent points of its own effect (numbers per effect in Config, "Synergy upgrades").
	-- Element boosters.
	{
		id = "Wildfire",
		name = "Wildfire",
		short = "WLD",
		effect = "Burn Spread",
		additive = true,
		unit = "%",
		category = "synergy",
		noMalus = true,
		requires = { element = "Incendiary" },
	},
	{
		id = "Shatter",
		name = "Shatter",
		short = "SHR",
		effect = "Dmg vs Chilled",
		additive = true,
		unit = "%",
		category = "synergy",
		noMalus = true,
		requires = { element = "Cryo" },
	},
	{
		id = "Aftershock",
		name = "Aftershock",
		short = "AFT",
		effect = "Shockwave",
		additive = true,
		unit = "%",
		category = "synergy",
		noMalus = true,
		requires = { element = "Concussive" },
	},
	{
		id = "ElementalPower",
		name = "Elemental Power",
		short = "ELM",
		effect = "All Elements",
		additive = true,
		unit = "%",
		category = "synergy",
		noMalus = true,
		-- Round 25: an Elemental gun counts too, and the card raises that gun's damage as well.
		requires = ELEMENT_REQ,
		tag = "ELEMENT",
	},
	-- Round 25: EXPLOSIVE synergies. Offered with an Explosive gun in the loadout, the Splash upgrade (kill
	-- explosions) or INITIATE (Frag / Claymore); each raises all of them.
	{
		id = "Demolition",
		name = "Demolition",
		short = "DEM",
		effect = "Explosion Dmg",
		additive = true,
		unit = "%",
		category = "synergy",
		noMalus = true,
		requires = EXPLOSIVE_REQ,
		tag = "EXPLOSIVE",
	},
	-- Class synergies: one per class, on the abilities it owns.
	{
		id = "Accelerant",
		name = "Accelerant",
		short = "ACL",
		effect = "Fire Ability Dmg",
		additive = true,
		unit = "%",
		category = "synergy",
		noMalus = true,
		requires = { class = "TORCH" },
	},
	{
		id = "TurretDamage",
		name = "Turret Damage",
		short = "TRD",
		effect = "Turret Damage",
		additive = true,
		unit = "%",
		category = "synergy",
		noMalus = true,
		-- Brief 12: INITIATE's turret and ENGINEER's sentry both take it.
		requires = { anyOf = { { class = "ENGINEER" } :: Requires, { class = "INITIATE" } :: Requires } },
		tag = "TURRET",
	},
	{
		id = "HealPower",
		name = "Healing",
		short = "HEL",
		effect = "Healing",
		additive = true,
		unit = "%",
		category = "synergy",
		noMalus = true,
		requires = { class = "DOC" },
	},
	{
		id = "DeadEyeTime",
		name = "Dead Eye Time",
		short = "DET",
		effect = "Dead Eye Time",
		additive = true,
		unit = "%",
		category = "synergy",
		noMalus = true,
		requires = { class = "SHARPSHOOTER" },
	},
	{
		id = "BlastRadius",
		name = "Blast Radius",
		short = "BLR",
		effect = "Blast Radius",
		additive = true,
		unit = "%",
		category = "synergy",
		noMalus = true,
		-- Round 25: an explosive synergy now (was INITIATE only): Frag, Claymore, Explosive guns, Splash.
		requires = EXPLOSIVE_REQ,
		tag = "EXPLOSIVE",
	},
} :: { Stat }

-- Card name per stat x tier (1..5).
Upgrades.TierNames = {
	Damage = { "Sharpened", "Honed", "Lethal", "Brutal", "Apocalyptic" },
	FireRate = { "Quick Finger", "Trigger Happy", "Rapid Fire", "Hailstorm", "Bullet Hell" },
	MagSize = { "Extra Clip", "Extended Mag", "Drum Mag", "Belt Fed", "Bottomless" },
	ReloadSpeed = { "Fast Hands", "Slick Reload", "Speed Loader", "Lightning Hands", "Instant Swap" },
	MaxHP = { "Thick Skin", "Toughened", "Iron Hide", "Juggernaut", "Immortal" },
	Armor = { "Padding", "Kevlar", "Plate Carrier", "Riot Gear", "Juggernaut Suit" },
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
	Concussive = { "Stun Ammo", "Stun Ammo", "Stun Ammo", "Stun Ammo", "Stun Ammo" },
	AbilityCooldown = { "Quick Reset", "Fast Recharge", "Overcharged", "Hair Trigger", "Perpetual" },
	AbilityPower = { "Amped", "Boosted", "Supercharged", "Overload", "Maximum" },
	CashGain = { "Pocket Change", "Loose Cash", "Big Spender", "High Roller", "Kingpin" },
	Wildfire = { "Kindling", "Spreading Flames", "Brushfire", "Wildfire", "Firestorm" },
	Shatter = { "Brittle", "Cracked Ice", "Shatter", "Glass Cannon", "Absolute Zero" },
	Aftershock = { "Tremor", "Shockwave", "Aftershock", "Quake", "Earthshaker" },
	ElementalPower = { "Attuned", "Charged", "Elemental", "Primal", "Avatar" },
	Accelerant = { "Lighter Fluid", "Accelerant", "Napalm", "Inferno", "Hellfire" },
	TurretDamage = { "Tuned Barrels", "Calibrated", "Hot Loads", "Killbox", "Sentry Gun" },
	HealPower = { "Bedside Manner", "Triage", "Field Medic", "Surgeon", "Miracle Worker" },
	DeadEyeTime = { "Steady Breath", "Held Breath", "Patient", "In The Zone", "Time Stops" },
	BlastRadius = { "Bigger Bang", "Shrapnel", "Wide Blast", "Demo Expert", "Ground Zero" },
	Demolition = { "Hot Powder", "Shaped Charge", "Demolition", "High Yield", "Big Boom" },
} :: { [string]: { string } }

-- Magnitude per stat x tier (1..5). Percent for "%" stats, flat count for "" stats. Elements: the power a later
-- take adds (the first take is 100%).
Upgrades.Magnitude = {
	Damage = { 15, 22, 30, 40, 55 },
	FireRate = { 12, 18, 25, 35, 50 },
	MagSize = { 20, 30, 45, 60, 80 },
	ReloadSpeed = { 15, 22, 30, 40, 55 },
	MaxHP = { 15, 25, 35, 50, 70 },
	Armor = { 15, 25, 35, 50, 70 }, -- armor points (a shield over HP that refills out of combat)
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
	AbilityPower = { 8, 12, 18, 25, 35 }, -- % more ability damage, heal, placeable HP and buff strength (Round 25:
	-- durations / radii take Config.AbilityPowerDurationShare / RadiusShare of it)
	CashGain = { 15, 25, 35, 50, 70 }, -- % more cash from kills, bags and job payouts
	-- Synergy (conditional) stats.
	Wildfire = { 40, 50, 60, 75, 90 }, -- % of a burn's strength that jumps to nearby enemies when the burner dies
	Shatter = { 15, 22, 30, 40, 55 }, -- % more bullet damage to chilled enemies (frozen: x Config.ShatterFrozenMult)
	Aftershock = { 30, 45, 60, 80, 100 }, -- % of gun damage a stagger sends to enemies around the target
	ElementalPower = { 10, 15, 20, 28, 36 }, -- % more power on every held element and more Elemental gun damage
	Accelerant = { 15, 22, 30, 40, 55 }, -- % more Molotov, Flame Turret and Inferno damage (brief 12)
	TurretDamage = { 15, 22, 30, 40, 55 }, -- % more Turret and Sentry damage per shot (brief 12)
	HealPower = { 15, 22, 30, 40, 55 }, -- % more Stim Shot, Med Bag and Heal Drone healing (brief 12)
	DeadEyeTime = { 15, 22, 30, 40, 55 }, -- % longer Dead Eye
	BlastRadius = { 10, 15, 20, 28, 36 }, -- % wider Frag, Claymore, Explosive gun and Splash blasts
	Demolition = { 12, 18, 25, 33, 45 }, -- % more Frag, Claymore, Explosive gun and Splash damage
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

-- A conditional (synergy) stat: it carries a `requires` table.
function Upgrades.isConditional(statId: string): boolean
	local s = Upgrades.byId(statId)
	return s ~= nil and s.requires ~= nil
end

-- The condition filter: true when every key of the stat's `requires` holds for a player who holds `owned` (the
-- run's tracker items by stat id) and has `classId` equipped. Stats without `requires` always pass.
-- Round 25: `archetypes` = the archetypes in the player's loadout (both slots), for `archetype` conditions.
local function holds(r: Requires, owned: { [string]: any }, classId: string, archetypes: { [string]: boolean }): boolean
	if r.anyOf then
		local any = false
		for _, alt in r.anyOf do
			if holds(alt, owned, classId, archetypes) then
				any = true
				break
			end
		end
		if not any then
			return false
		end
	end
	if r.archetype and not archetypes[r.archetype] then
		return false
	end
	if r.owns and not owned[r.owns] then
		return false
	end
	if r.element and not owned[r.element] then
		return false
	end
	if r.anyElement then
		local any = false
		for _, s in Upgrades.Stats do
			if s.category == "element" and owned[s.id] then
				any = true
				break
			end
		end
		if not any then
			return false
		end
	end
	if r.class and r.class ~= classId then
		return false
	end
	return true
end

function Upgrades.meets(
	stat: Stat,
	owned: { [string]: any },
	classId: string,
	archetypes: { [string]: boolean }?
): boolean
	local r = stat.requires
	if not r then
		return true
	end
	return holds(r, owned, classId, archetypes or {})
end

-- The pill on a conditional card says why it showed up: "FIRE SYNERGY" (an element), "ELEMENT SYNERGY" (any
-- element), "TORCH SYNERGY" (a class). nil for ordinary stats.
function Upgrades.synergyTag(statId: string): string?
	local s = Upgrades.byId(statId)
	local r = s and s.requires
	if not r then
		return nil
	end
	local why = "SYNERGY"
	if s and s.tag then
		why = s.tag
	elseif r.class then
		why = Classes.displayName(r.class) -- brief 12: PYRO SYNERGY, not the TORCH id
	elseif r.element then
		-- "Fire Ammo" -> "FIRE"
		why = string.upper((string.match(Upgrades.statName(r.element), "^(%S+)") or r.element))
	elseif r.anyElement then
		why = "ELEMENT"
	end
	return if why == "SYNERGY" then why else why .. " SYNERGY"
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
-- "BURN" over "ON EVERY SHOT" for the first take (Round 21: was "NEW" over "BURN ON EVERY SHOT"), then "+30%" over
-- "BURN". Synergy: "+40%" over its effect ("BURN SPREAD").
function Upgrades.cardTexts(statId: string, value: number): (string, string)
	local effect = Upgrades.effectName(statId)
	if effect then
		if Upgrades.isNewElement(statId, value) then
			return effect, "ON EVERY SHOT"
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

-- The tracker badge: elements show their power ("130%"), utility, defense and synergy the running total ("-12%",
-- "+40" armor), gun stats the count.
function Upgrades.badgeText(statId: string, item: { count: number, pct: number }): string
	local cat = Upgrades.category(statId)
	if cat == "element" then
		return string.format("%s%%", fmtValue(item.pct))
	elseif cat == "utility" or cat == "synergy" or cat == "defense" then
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
