--!strict
-- The four classes and their three abilities (Q / E / Z), restated from GDD_7. Only INITIATE's abilities
-- are live (the prototype's barricade / turret / stim); the other nine are stubs that toast and print.
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
	live: boolean, -- false: STUB · PHASE 2
	icon: string, -- short glyph for the tile
}
export type Class = { id: string, name: string, color: string, abilities: { Ability }, free: boolean? }

local Config = require(script.Parent.Config)

local Classes = {}

local function var(id: string, label: string, base: number, unit: string?): Var
	return { id = id, label = label, base = base, unit = unit or "" }
end

local function ability(t: { [string]: any }): Ability
	t.live = t.live == true
	t.vars = t.vars or {}
	return t :: Ability
end

Classes.List = {
	{
		id = "INITIATE",
		name = "Initiate",
		color = "E8B64C",
		free = true,
		abilities = {
			ability({
				id = "barricade",
				name = "Barricade",
				hotkey = "Q",
				system = "A",
				price = 150,
				description = "Blocks a path. Enemies have to break it.",
				vars = { var("Hp", "HP", Config.BarricadeHP) },
				live = true,
				icon = "WAL",
			}),
			ability({
				id = "turret",
				name = "Turret",
				hotkey = "E",
				system = "B",
				price = 250,
				description = "Hired muscle. Shoots anything that gets close.",
				vars = { var("Damage", "DMG", Config.TurretDmg), var("Hp", "HP", Config.TurretHP) },
				live = true,
				icon = "TRT",
			}),
			ability({
				id = "stim",
				name = "Stim",
				hotkey = "Z",
				system = "self",
				price = 100,
				description = "Patch yourself up and speed up.",
				vars = {
					var("Heal", "HEAL", Config.StimHeal),
					var("FireRatePct", "FIRE RATE", (Config.StimFireRateMult - 1) * 100, "%"),
					var("ReloadPct", "RELOAD", (Config.StimReloadSpeedMult - 1) * 100, "%"),
				},
				live = true,
				icon = "STM",
			}),
		},
	},
	{
		id = "DOC",
		name = "Doc",
		color = "8FE3A1",
		abilities = {
			ability({
				id = "stimshot",
				name = "Stim Shot",
				hotkey = "Q",
				system = "self",
				price = 100,
				description = "Heal up, shoot and reload faster for a while.",
				vars = {
					var("Heal", "HEAL", 40),
					var("FireRatePct", "FIRE RATE", 30, "%"),
					var("ReloadPct", "RELOAD", 30, "%"),
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
				vars = { var("HealPerSec", "HEAL / S", 8) },
				icon = "BAG",
			}),
			ability({
				id = "healturret",
				name = "Healing Turret",
				hotkey = "Z",
				system = "B",
				price = 250,
				description = "Beams the lowest teammate back to health.",
				vars = { var("BeamHeal", "BEAM HEAL", 6), var("Hp", "HP", 150) },
				icon = "HTR",
			}),
		},
	},
	{
		id = "SHARPSHOOTER",
		name = "Sharpshooter",
		color = "4D9FE8",
		abilities = {
			ability({
				id = "claymore",
				name = "Claymore",
				hotkey = "Q",
				system = "trigger",
				price = 150,
				description = "Plant it. Wait for the boom.",
				vars = { var("ClaymoreDamage", "DMG", 220) },
				icon = "CLM",
			}),
			ability({
				id = "deadeye",
				name = "Dead Eye",
				hotkey = "E",
				system = "self",
				price = 150,
				description = "Hit harder, move faster.",
				vars = { var("DmgPct", "DMG", 25, "%"), var("SpeedPct", "SPEED", 20, "%") },
				icon = "EYE",
			}),
			ability({
				id = "flashbang",
				name = "Flashbang",
				hotkey = "Z",
				system = "thrown",
				price = 120,
				description = "Freeze the room.",
				vars = { var("StunDuration", "STUN", 3, "s"), var("FlashRadius", "RADIUS", 12) },
				icon = "FLS",
			}),
		},
	},
	{
		id = "TORCH",
		name = "Torch",
		color = "E8554D",
		abilities = {
			ability({
				id = "molotov",
				name = "Molotov",
				hotkey = "Q",
				system = "C",
				price = 150,
				description = "Light the floor. Slows and burns whatever walks in.",
				vars = { var("BurnPerSec", "BURN / S", 15), var("MoveSlowPct", "SLOW", 30, "%") },
				icon = "MOL",
			}),
			ability({
				id = "flameturret",
				name = "Flame Turret",
				hotkey = "E",
				system = "B",
				price = 250,
				description = "A short, angry stream of fire.",
				vars = { var("FlameDps", "FLAME DPS", 30), var("Hp", "HP", 150) },
				icon = "FTR",
			}),
			ability({
				id = "oildrum",
				name = "Oil Drum",
				hotkey = "Z",
				system = "A",
				price = 150,
				description = "Blocks like a barricade. Burns when it breaks.",
				vars = { var("DrumBurnPerSec", "BURN / S", 20), var("DrumMoveSlowPct", "SLOW", 30, "%") },
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
