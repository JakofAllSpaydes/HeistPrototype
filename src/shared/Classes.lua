--!strict
-- The five classes and their three abilities (Q / E / Z), brief 5: INITIATE Frag / Adrenaline / Claymore,
-- ENGINEER Turret / Barricade / Overclock, DOC Stim Shot / Med Bag / Healing Turret, SHARPSHOOTER Eagle Eye /
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
	icon: string, -- short glyph for the tile
}
-- glyph: the class icon in its colored circle (pills, wells, the hub tag, the scoreboard).
export type Class = {
	id: string,
	name: string,
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
				id = "claymore",
				name = "Claymore",
				hotkey = "Z",
				system = "trigger",
				price = 150,
				description = "Plant it. Wait for the boom.",
				vars = { var("ClaymoreDamage", "DMG", Config.ClaymoreDamage) },
				icon = "CLM",
			}),
		},
	},
	{
		id = "ENGINEER",
		name = "Engineer",
		color = "D9822B",
		glyph = "🔧", -- the wrench over the turret
		abilities = {
			ability({
				id = "turret",
				name = "Turret",
				hotkey = "Q",
				system = "B",
				price = 250,
				description = "Hired muscle. Shoots anything that gets close.",
				vars = { var("Damage", "DMG", Config.TurretDmg), var("Hp", "HP", Config.TurretHP) },
				icon = "TRT",
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
				description = "Every placeable on the floor works faster; barricades get a shield.",
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
				id = "healturret",
				name = "Healing Turret",
				hotkey = "Z",
				system = "B",
				price = 250,
				description = "Beams the lowest teammate back to health.",
				vars = { var("BeamHeal", "BEAM HEAL", Config.HealTurretBeamHeal), var("Hp", "HP", Config.HealTurretHP) },
				icon = "HTR",
			}),
		},
	},
	{
		id = "SHARPSHOOTER",
		name = "Sharpshooter",
		color = "4D9FE8",
		glyph = "S",
		abilities = {
			ability({
				id = "eagleeye",
				name = "Eagle Eye",
				hotkey = "Q",
				system = "self",
				price = 150,
				description = "Mark everything nearby through walls. Marked enemies take more damage.",
				vars = {
					var("EagleEyeBonusPct", "BONUS DMG", Config.EagleEyeBonusPct * 100, "%"),
					var("EagleEyeRadius", "RADIUS", Config.EagleEyeRadius),
				},
				icon = "◉", -- an eye in a reticle
			}),
			ability({
				id = "deadeye",
				name = "Dead Eye",
				hotkey = "E",
				system = "self",
				price = 150,
				description = "Hit harder, move faster, shoot through them.",
				vars = {
					var("DmgPct", "DMG", Config.DeadEyeDmgPct, "%"),
					var("SpeedPct", "SPEED", Config.DeadEyeSpeedPct, "%"),
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
		name = "Torch",
		color = "E8554D",
		glyph = "T",
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
		},
	},
} :: { Class }

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

Classes.Default = "INITIATE"

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
