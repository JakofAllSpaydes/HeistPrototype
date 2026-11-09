--!strict
-- The five classes and their three abilities (Q / E / Z), brief 5: INITIATE Frag / Adrenaline / Claymore,
-- ENGINEER Turret / Barricade / Overclock, DOC Stim Shot / Med Bag / Healing Turret, SHARPSHOOTER Eagle Vision /
-- Dead Eye / Flashbang, TORCH Molotov / Flame Turret / Oil Drum. All fifteen are live (Abilities.lua); every
-- number comes from Config so the designer tunes there.
-- `vars` lists the upgradeable variables shown as current > next in the Classes tab; everything else is static.
export type Var = { id: string, label: string, base: number, unit: string }
export type Ability = {
	id: string,
	name: string,
	hotkey: string, -- Q | E | Z
	system: string, -- A attackable placeable | B shooter NPC | C ground field | self | thrown | trigger
	price: number, -- in-match $ label
	description: string,
	vars: { Var },
	icon: string, -- the ability's pictogram id in client/UI/Icons.lua (also its text fallback)
}
-- The class emblem in its colored circle (pills, wells, the scoreboard) is the Icons.lua pictogram keyed by the
-- class id; glyph is the letter shown where no pictogram is drawn (the fallback, store art).
-- Brief 12: `id` is the saved key (profiles, mastery, Armory, stats) and never changes; `displayName` is what a
-- player reads (caps, the house style) and `name` its mixed-case twin. A rename costs no migration (TORCH -> PYRO).
export type Class = {
	id: string,
	name: string,
	displayName: string,
	color: string,
	glyph: string,
	abilities: { Ability },
	free: boolean?,
}

local Config = require(script.Parent.Config)

local Classes = {}

local function var(id: string, label: string, base: number, unit: string?): Var
	return { id = id, label = label, base = base, unit = unit or "" }
end

local function ability(t: { [string]: any }): Ability
	t.vars = t.vars or {}
	return t :: Ability
end

-- Carousel order (brief 5): INITIATE -> ENGINEER -> DOC -> SHARPSHOOTER -> TORCH. Ability levels are keyed by
-- ability id, so a level follows the ability when it moves class (the claymore went SHARPSHOOTER -> INITIATE,
-- turret and barricade INITIATE -> ENGINEER).
Classes.List = {
	{
		id = "INITIATE",
		name = "Initiate",
		displayName = "INITIATE",
		color = "E8B64C",
		glyph = "I",
		free = true,
		abilities = {
			ability({
				id = "frag",
				name = "Frag",
				hotkey = "Q",
				system = "thrown",
				price = 150,
				description = "Cook it, throw it, clear the room.",
				vars = { var("FragDamage", "DMG", Config.FragDamage) },
				icon = "FRG",
			}),
			ability({
				id = "stim", -- kept as the saved-level key; the player sees "Adrenaline"
				name = "Adrenaline",
				hotkey = "E",
				system = "self",
				price = 100,
				description = "Shoot, reload and move faster for a while.",
				vars = {
					var("FireRatePct", "FIRE RATE", (Config.AdrenalineFireRateMult - 1) * 100, "%"),
					var("ReloadPct", "RELOAD", (Config.AdrenalineReloadSpeedMult - 1) * 100, "%"),
					var("MovePct", "SPEED", (Config.AdrenalineMoveMult - 1) * 100, "%"),
				},
				icon = "ADR",
			}),
			ability({
				id = "turret",
				name = "Turret",
				hotkey = "Z",
				system = "B",
				price = 250,
				description = "Hired muscle. Shoots anything that gets close.",
				vars = { var("Damage", "DMG", Config.TurretDmg), var("Hp", "HP", Config.TurretHP) },
				icon = "TRT",
			}),
		},
	},
	{
		id = "ENGINEER",
		name = "Engineer",
		displayName = "ENGINEER",
		color = "D9822B",
		glyph = "E",
		abilities = {
			ability({
				id = "sentry", -- brief 12: replaces the turret on ENGINEER (the turret went to INITIATE)
				name = "Sentry",
				hotkey = "Q",
				system = "B",
				price = 300,
				description = "A heavy tripod gun. Takes a second to set up, then shreds.",
				vars = {
					var("SentryDamage", "DMG", Config.TurretDmg * Config.SentryDpsMult / 2),
					var("SentryHp", "HP", Config.SentryHp),
				},
				icon = "STY",
			}),
			ability({
				id = "barricade",
				name = "Barricade",
				hotkey = "E",
				system = "A",
				price = 150,
				description = "Blocks a path. Enemies have to break it.",
				vars = { var("Hp", "HP", Config.BarricadeHP) },
				icon = "WAL",
			}),
			ability({
				id = "overclock",
				name = "Overclock",
				hotkey = "Z",
				system = "self",
				price = 200,
				description = "Your gun and every placeable on the floor work faster; barricades get a shield.",
				vars = {
					var("RatePct", "RATE", (Config.OverclockRateMult - 1) * 100, "%"),
					var("ShieldHp", "SHIELD", Config.OverclockShieldHp),
				},
				icon = "OVC",
			}),
		},
	},
	{
		id = "DOC",
		name = "Doc",
		displayName = "DOC",
		color = "8FE3A1",
		glyph = "D",
		abilities = {
			ability({
				id = "stimshot",
				name = "Stim Shot",
				hotkey = "Q",
				system = "self",
				price = 100,
				description = "Heal up, shoot and reload faster for a while.",
				vars = {
					var("Heal", "HEAL", Config.StimShotHeal),
					var("FireRatePct", "FIRE RATE", (Config.StimShotFireRateMult - 1) * 100, "%"),
					var("ReloadPct", "RELOAD", (Config.StimShotReloadSpeedMult - 1) * 100, "%"),
				},
				icon = "SHT",
			}),
			ability({
				id = "medbag",
				name = "Med Bag",
				hotkey = "E",
				system = "C",
				price = 200,
				description = "Throw it down. Stand in it to heal.",
				vars = { var("HealPerSec", "HEAL / S", Config.MedBagHealPerSec) },
				icon = "BAG",
			}),
			ability({
				id = "healdrone", -- brief 12: replaces the healing turret
				name = "Heal Drone",
				hotkey = "Z",
				system = "drone",
				price = 250,
				description = "Follows you around and patches up whoever's hurting most.",
				vars = { var("HealDroneHps", "HEAL / S", Config.HealDroneHps) },
				icon = "HDR",
			}),
		},
	},
	{
		id = "SHARPSHOOTER",
		name = "Sharpshooter",
		displayName = "SHARPSHOOTER",
		color = "4D9FE8",
		glyph = "S",
		abilities = {
			ability({
				id = "eagleeye",
				name = "Eagle Vision", -- id stays "eagleeye" for saved levels
				hotkey = "Q",
				system = "self",
				price = 150,
				description = "Mark everything nearby through walls. Marked enemies are slowed.",
				vars = {
					var("EagleEyeSlowPct", "SLOW", Config.EagleEyeSlowPct * 100, "%"),
					var("EagleEyeRadius", "RADIUS", Config.EagleEyeRadius),
				},
				icon = "EGV",
			}),
			ability({
				id = "deadeye",
				name = "Dead Eye",
				hotkey = "E",
				system = "self",
				price = 150,
				description = "Hit harder, aim tighter, shoot through them.",
				vars = {
					var("DmgPct", "DMG", Config.DeadEyeDmgPct, "%"),
					var("AccuracyPct", "ACC", Config.DeadEyeAccuracyPct, "%"),
					var("Pierce", "PIERCE", Config.DeadEyePierce),
				},
				icon = "EYE",
			}),
			ability({
				id = "flashbang",
				name = "Flashbang",
				hotkey = "Z",
				system = "thrown",
				price = 120,
				description = "Freeze the room.",
				vars = {
					var("StunDuration", "STUN", Config.StunDuration, "s"),
					var("FlashRadius", "RADIUS", Config.FlashRadius),
				},
				icon = "FLS",
			}),
		},
	},
	{
		id = "TORCH",
		name = "Pyro", -- brief 12: TORCH is PYRO to the player; the id stays "TORCH" (no profile migration)
		displayName = "PYRO",
		color = "E8554D",
		glyph = "P",
		abilities = {
			ability({
				id = "molotov",
				name = "Molotov",
				hotkey = "Q",
				system = "C",
				price = 150,
				description = "Light the floor. Slows and burns whatever walks in.",
				vars = {
					var("BurnPerSec", "BURN / S", Config.MolotovBurnPerSec),
					var("MoveSlowPct", "SLOW", Config.MolotovMoveSlowPct, "%"),
				},
				icon = "MOL",
			}),
			ability({
				id = "flameturret",
				name = "Flame Turret",
				hotkey = "E",
				system = "B",
				price = 250,
				description = "A short, angry stream of fire.",
				vars = { var("FlameDps", "FLAME DPS", Config.FlameTurretDps), var("Hp", "HP", Config.FlameTurretHP) },
				icon = "FTR",
			}),
			ability({
				id = "inferno", -- brief 12: replaces the oil drum
				name = "Inferno",
				hotkey = "Z",
				system = "self",
				price = 200,
				description = "A ring of fire that moves with you. Burns and slows whatever crosses it.",
				vars = {
					var("InfernoBurnPerSec", "BURN / S", Config.InfernoBurnPerSec),
					var("InfernoSlowPct", "SLOW", Config.InfernoSlowPct, "%"),
				},
				icon = "INF",
			}),
		},
	},
} :: { Class }

-- Brief 12: the unassigned pool. Claymore, Oil Drum and Healing Turret keep their code, Config and assets; they fire
-- only with Config.UnassignedAbilitiesEnabled or a debug `Grant ability <id>` (any slot), candidates for later classes.
Classes.Unassigned = {
	ability({
		id = "claymore",
		name = "Claymore",
		hotkey = "Z",
		system = "trigger",
		price = 150,
		description = "Plant it. Wait for the boom.",
		vars = { var("ClaymoreDamage", "DMG", Config.ClaymoreDamage) },
		icon = "CLM",
	}),
	ability({
		id = "oildrum",
		name = "Oil Drum",
		hotkey = "Z",
		system = "A",
		price = 150,
		description = "Blocks like a barricade. Burns when it breaks.",
		vars = {
			var("DrumBurnPerSec", "BURN / S", Config.OilDrumBurnPerSec),
			var("DrumMoveSlowPct", "SLOW", Config.OilDrumMoveSlowPct, "%"),
		},
		icon = "OIL",
	}),
	ability({
		id = "healturret",
		name = "Healing Turret",
		hotkey = "Z",
		system = "B",
		price = 250,
		description = "Beams the lowest teammate back to health.",
		vars = { var("BeamHeal", "BEAM HEAL", Config.HealTurretBeamHeal), var("Hp", "HP", Config.HealTurretHP) },
		icon = "HTR",
	}),
} :: { Ability }

Classes.ById = {} :: { [string]: Class }
Classes.AbilityById = {} :: { [string]: Ability }
Classes.ClassOfAbility = {} :: { [string]: string }
for _, c in Classes.List do
	Classes.ById[c.id] = c
	for _, a in c.abilities do
		Classes.AbilityById[a.id] = a
		Classes.ClassOfAbility[a.id] = c.id
	end
end
-- Unassigned abilities resolve by id (saved levels stay valid) but belong to no class.
for _, a in Classes.Unassigned do
	Classes.AbilityById[a.id] = a
end

-- Round 25: the hotkey chips follow Config.AbilityKeys by slot (the per-ability `hotkey` fields are overwritten).
for _, c in Classes.List do
	for i, a in c.abilities do
		a.hotkey = Config.AbilityKeys[i] or a.hotkey
	end
end

Classes.Default = "INITIATE"

-- Brief 12: a player's three ability ids by slot: the class's kit with any debug grants (`grants[slot] = id`,
-- the unassigned pool included) laid over it.
function Classes.kit(classId: string, grants: { [number]: string }?): { string }
	local c = Classes.ById[classId] or Classes.ById[Classes.Default]
	local out = {}
	for i, a in c.abilities do
		local g = grants and grants[i]
		out[i] = if g and Classes.AbilityById[g] then g else a.id
	end
	return out
end

function Classes.isUnassigned(abilityId: string): boolean
	return Classes.AbilityById[abilityId] ~= nil and Classes.ClassOfAbility[abilityId] == nil
end

-- What a player reads for a class id ("PYRO" for TORCH); unknown ids read as themselves.
function Classes.displayName(classId: string): string
	local c = Classes.ById[classId]
	return if c then c.displayName else classId
end

-- Hotkey slot (1..3) of an ability in its class.
function Classes.slotOf(abilityId: string): number
	local classId = Classes.ClassOfAbility[abilityId]
	local c = classId and Classes.ById[classId]
	if c then
		for i, a in c.abilities do
			if a.id == abilityId then
				return i
			end
		end
	end
	return 1
end

return Classes
