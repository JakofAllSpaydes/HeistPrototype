--!strict
-- Weapon and class mastery (brief 5): the tier math both sides share and the player-facing copy the tile
-- tooltips, the summary tier-up pop and the Classes tab show. Name in caps, one line under it, numbers filled
-- from Config at render time. The build rules live in server/Mastery.lua and the modules that read the passives.
local Config = require(script.Parent.Config)
local Wraps = require(script.Parent.Wraps)

local MasteryCopy = {}

MasteryCopy.Roman = { "I", "II", "III" }

-- Tier reached (0..#tiers) for an XP total.
function MasteryCopy.tierOf(xp: number, tiers: { number }): number
	local t = 0
	for i, need in tiers do
		if xp >= need then
			t = i
		end
	end
	return t
end

-- Progress inside the current tier: tier, XP into it, XP the next tier needs (0 when maxed).
function MasteryCopy.progress(xp: number, tiers: { number }): (number, number, number)
	local tier = MasteryCopy.tierOf(xp, tiers)
	local floor = if tier > 0 then tiers[tier] else 0
	local nextNeed = tiers[tier + 1]
	if not nextNeed then
		return tier, 0, 0
	end
	return tier, xp - floor, nextNeed - floor
end

function MasteryCopy.weaponTier(xp: number): number
	return MasteryCopy.tierOf(xp, Config.WeaponMasteryTiers)
end

function MasteryCopy.classTier(xp: number): number
	return MasteryCopy.tierOf(xp, Config.ClassMasteryTiers)
end

-- The mastery wrap a weapon tier unlocks, and the tier a mastery wrap needs (nil for a shop wrap).
function MasteryCopy.wrapFor(tier: number): Wraps.Wrap?
	local id = Config.MasteryWrapIds[tier]
	return if id then Wraps.ById[id] else nil
end

function MasteryCopy.wrapTier(wrapId: string): number?
	return table.find(Config.MasteryWrapIds, wrapId)
end

function MasteryCopy.weaponReward(tier: number): string
	local w = MasteryCopy.wrapFor(tier)
	return if w then string.upper(w.name) .. " WRAP" else ""
end

local function pct(n: number): string
	return string.format("%d%%", math.round(n * 100))
end

-- Per class, tiers 1..3: { name, line }. Functions so the numbers come from Config when shown.
local CLASS: { [string]: { () -> (string, string) } } = {
	INITIATE = {
		function()
			return "PATCHED UP", string.format("Stim heals %s HP", pct(Config.StimMasteryHealPct))
		end,
		function()
			return "DOUBLE DOWN",
				string.format("+%d Frag, +%d Claymore charge", Config.MasteryExtraCharges, Config.MasteryExtraCharges)
		end,
		function()
			return "ADRENALINE JUNKIE", "Kills during Stim extend it"
		end,
	},
	ENGINEER = {
		function()
			return "REINFORCED", string.format("Placeables +%s HP and fire rate", pct(Config.EngineerPlaceablePct))
		end,
		function()
			return "FIELD REPAIR", "Idle placeables self-repair"
		end,
		function()
			return "CREW OVERCLOCK", "Overclock boosts the whole crew's guns"
		end,
	},
	DOC = {
		function()
			return "WIDE NET", string.format("Med Bag and Healing Turret reach +%s", pct(Config.DocReachPct))
		end,
		function()
			return "TRIAGE", "Your heals revive downed allies"
		end,
		function()
			return "FIELD HOSPITAL",
				string.format(
					"Med Bag bigger range and heal, allies inside +%s damage",
					pct(Config.FieldHospitalDmgPct)
				)
		end,
	},
	SHARPSHOOTER = {
		function()
			return "DEAD CENTER", string.format("Headshots +%s×", tostring(Config.SharpHeadshotAdd))
		end,
		function()
			return "MARKSMAN'S KIT", "Snipers and pistols reload faster"
		end,
		function()
			return "OVERDRIVE", "Dead Eye headshots refill your mag and reduces cooldown"
		end,
	},
	TORCH = {
		function()
			return "SLOW BURN", "Burns tick twice as fast"
		end,
		function()
			return "HOT ROUNDS", "Your bullets set enemies on fire"
		end,
		function()
			return "BACKDRAFT", "Burning kills recharge Molotov"
		end,
	},
}

-- name, line for a class tier (1..3); "" when unknown.
function MasteryCopy.classReward(classId: string, tier: number): (string, string)
	local row = CLASS[classId]
	local f = row and row[tier]
	if not f then
		return "", ""
	end
	return f()
end

-- Tooltip lines for a tile: one per tier, earned ones marked.
function MasteryCopy.tooltip(kind: string, id: string, tier: number): { string }
	local out = {}
	local tiers = if kind == "weapon" then Config.WeaponMasteryTiers else Config.ClassMasteryTiers
	for t = 1, #tiers do
		local name, line
		if kind == "weapon" then
			name, line = MasteryCopy.weaponReward(t), string.format("%d kills", tiers[t])
		else
			name, line = MasteryCopy.classReward(id, t)
		end
		table.insert(
			out,
			string.format("%s %s %s · %s", if tier >= t then "✔" else "·", MasteryCopy.Roman[t] or "", name, line)
		)
	end
	return out
end

return MasteryCopy
