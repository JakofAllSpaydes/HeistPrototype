--!strict
-- Brief 9: the Skill Web. 90 one-time account perks bought with Gold in the hub, on a hex web around START: six
-- branches (60 degree wedges, clockwise from the top) x five rings (1 + 2 + 3 + 4 + 5 = 15 nodes a branch). A node
-- can be bought when one of its six hex neighbours is owned (START counts, seams between wedges count) and the
-- Gold is there; the cost is by ring only (Config.SkillCostByRing). Nothing changes a rule: every node is a percent
-- or a flat number, and the run start folds the owned set into one modifier table (Skills.modifiers) that each hook
-- reads one field of, the way Armory levels already apply.
--
-- The node values live in Config.SkillNodes; this module turns them into defs (id, name, icon, effect, cell).
local Config = require(script.Parent.Config)
local SkillLayout = require(script.Parent.SkillLayout)

local Skills = {}

Skills.START = "START"

export type Effect = { stat: string, value: number, kind: string, filter: string? }
export type Node = {
	id: string,
	branch: string,
	ring: number,
	slot: number,
	name: string,
	icon: string,
	effect: Effect,
	line: string, -- one line of effect copy ("+3% weapon damage")
	cost: number, -- Gold (ring base x stat weight x repeat step, rounded; Round 26b)
	q: number,
	r: number,
}
export type Branch = { id: string, name: string, icon: string, color: string }

-- Clockwise from the top. icon: a UI/Icons.lua pictogram; color: the branch's accent (hex) over the panel colour.
Skills.Branches = {
	{ id = "DAMAGE", name = "DAMAGE", icon = "Damage", color = "E8554D" },
	{ id = "SURVIVAL", name = "SURVIVAL", icon = "heart", color = "4FC77A" },
	{ id = "SPEED", name = "SPEED", icon = "MoveSpeed", color = "4D9FE8" },
	{ id = "CASH", name = "CASH", icon = "cash", color = "E8B64C" },
	{ id = "LUCK", name = "LUCK", icon = "die", color = "A864E8" },
	{ id = "ARSENAL", name = "ARSENAL", icon = "arsenal", color = "E8792A" },
} :: { Branch }
Skills.BranchById = {} :: { [string]: Branch }
for _, b in Skills.Branches do
	Skills.BranchById[b.id] = b
end

-- Weapons.lua archetypes the ARSENAL nodes filter on (RIFLES covers every Rifle-archetype gun, bullpups included).
local ARCH = {
	pistol = "Pistol",
	smg = "SMG",
	rifle = "Rifle",
	shotgun = "Shotgun",
	sniper = "Sniper",
	lmg = "LMG",
	explosive = "Explosive",
	elemental = "Elemental",
}

-- Stat keys (Config.SkillNodes) -> the modifier field, name, pictogram, kind and the effect line's format.
-- kind: pct (a fraction, shown as a percent), flat (a number), luck (a count of LuckOddsStep shifts).
type StatDef = { field: string, name: string, icon: string, kind: string, fmt: string, filter: string? }
local STATS: { [string]: StatDef } = {
	damage = {
		field = "damagePct",
		name = "DAMAGE",
		icon = "Damage",
		kind = "pct",
		fmt = "+%s damage with every weapon",
	},
	crit = {
		field = "critPct",
		name = "CRIT CHANCE",
		icon = "CritChance",
		kind = "pct",
		fmt = "+%s chance a shot crits for double damage",
	},
	headshot = {
		field = "headshotPct",
		name = "HEADSHOT",
		icon = "HeadshotMult",
		kind = "pct",
		fmt = "+%s damage on headshots",
	},
	elite = {
		field = "eliteDamagePct",
		name = "ELITE DAMAGE",
		icon = "crown",
		kind = "pct",
		fmt = "+%s damage to elite enemies (weapons and abilities)",
	},
	boss = {
		field = "bossDamagePct",
		name = "BOSS DAMAGE",
		icon = "boss",
		kind = "pct",
		fmt = "+%s damage to TITAN, the boss (weapons and abilities)",
	},
	ability = {
		field = "abilityDamagePct",
		name = "ABILITY DAMAGE",
		icon = "AbilityPower",
		kind = "pct",
		fmt = "+%s damage from your class abilities",
	},
	maxHp = { field = "maxHpPct", name = "MAX HP", icon = "MaxHP", kind = "pct", fmt = "+%s max health" },
	armor = {
		field = "armorFlat",
		name = "ARMOR",
		icon = "Armor",
		kind = "flat",
		fmt = "+%s armor: soaks hits before your health, refills when you're not hit",
	},
	regen = {
		field = "hpRegenFlat",
		name = "HP REGEN",
		icon = "HPRegen",
		kind = "flat",
		fmt = "+%s health regenerated per second",
	},
	tough = {
		field = "damageTakenPct",
		name = "TOUGHNESS",
		icon = "classes",
		kind = "pct",
		fmt = "Take %s less damage from every hit",
	},
	armorRecovery = {
		field = "armorDelayPct",
		name = "ARMOR RECOVERY",
		icon = "ReloadSpeed",
		kind = "pct",
		fmt = "Armor starts refilling %s sooner after a hit",
	},
	revive = {
		field = "revivePct",
		name = "REVIVE SPEED",
		icon = "revive",
		kind = "pct",
		fmt = "Revive downed teammates %s faster",
	},
	lastStand = {
		field = "bleedOutFlat",
		name = "LAST STAND",
		icon = "heart",
		kind = "flat",
		fmt = "+%s seconds before you bleed out when downed",
	},
	move = {
		field = "moveSpeedPct",
		name = "MOVE SPEED",
		icon = "MoveSpeed",
		kind = "pct",
		fmt = "Move %s faster in runs",
	},
	reload = {
		field = "reloadPct",
		name = "RELOAD",
		icon = "ReloadSpeed",
		kind = "pct",
		fmt = "Reload every gun %s faster",
	},
	cooldown = {
		field = "cooldownPct",
		name = "COOLDOWN",
		icon = "AbilityCooldown",
		kind = "pct",
		fmt = "Class abilities recharge %s faster",
	},
	quickHands = {
		field = "interactPct",
		name = "QUICK HANDS",
		icon = "hand",
		kind = "pct",
		fmt = "Door and hack holds finish %s faster",
	},
	bagValue = {
		field = "bagValuePct",
		name = "BAG VALUE",
		icon = "moneybag",
		kind = "pct",
		fmt = "Cash bags pay you %s more",
	},
	magnet = {
		field = "pickupRadiusPct",
		name = "MAGNET",
		icon = "magnet",
		kind = "pct",
		fmt = "Start grabbing bags from %s farther away",
	},
	fastHands = {
		field = "pickupSpeedPct",
		name = "FAST HANDS",
		icon = "hand",
		kind = "pct",
		fmt = "Grab bags %s faster",
	},
	fence = {
		field = "bankedPct",
		name = "FENCE",
		icon = "goldbar",
		kind = "pct",
		fmt = "+%s Gold from the team's banked gold bags at run end",
	},
	seedMoney = {
		field = "startCashFlat",
		name = "SEED MONEY",
		icon = "cash",
		kind = "flat",
		fmt = "Start every run with $%s more cash",
	},
	haggle = {
		field = "dealerPct",
		name = "HAGGLE",
		icon = "shop",
		kind = "pct",
		fmt = "Everything at the in-run dealer costs %s less",
	},
	cardLuck = {
		field = "cardLuck",
		name = "CARD LUCK",
		icon = "lucky",
		kind = "luck",
		fmt = "+%s odds of rarer upgrade cards when you buy a pick-3 in a run",
	},
	dealerLuck = {
		field = "dealerLuck",
		name = "DEALER LUCK",
		icon = "shop",
		kind = "luck",
		fmt = "+%s odds of rarer upgrade cards at the in-run dealer",
	},
	crateLuck = {
		field = "crateLuck",
		name = "CRATE LUCK",
		icon = "crate",
		kind = "luck",
		fmt = "+%s odds of rarer weapons from in-run weapon crates (not SHOP crates)",
	},
}
-- ARSENAL: damage per weapon type, then mags / rounds.
for key, def in
	{
		pistols = { "pistol", "PISTOLS", "pistols" },
		smgs = { "smg", "SMGS", "SMGs" },
		rifles = { "rifle", "RIFLES", "rifles" },
		shotguns = { "shotgun", "SHOTGUNS", "shotguns" },
		snipers = { "sniper", "SNIPERS", "snipers" },
		lmgs = { "lmg", "LMGS", "LMGs" },
		explosives = { "explosive", "EXPLOSIVES", "explosives" },
		elemental = { "elemental", "ELEMENTAL", "elemental weapons" },
	} :: { [string]: { string } }
do
	STATS[key] = {
		field = "typeDamagePct",
		filter = ARCH[def[1]],
		name = def[2],
		icon = "arsenal",
		kind = "pct",
		fmt = "+%s damage with " .. def[3],
	}
end
for key, def in
	{
		pistolMags = { "pistol", "PISTOL MAGS", "pct", "+%s more rounds in every pistol mag" },
		smgMags = { "smg", "SMG MAGS", "pct", "+%s more rounds in every SMG mag" },
		rifleMags = { "rifle", "RIFLE MAGS", "pct", "+%s more rounds in every rifle mag" },
		lmgBelts = { "lmg", "LMG BELTS", "pct", "+%s more rounds in every LMG belt" },
		shotgunShells = { "shotgun", "SHOTGUN SHELLS", "flat", "+%s shell in every shotgun" },
		sniperMags = { "sniper", "SNIPER MAGS", "flat", "+%s round in every sniper mag" },
		explosiveAmmo = { "explosive", "EXPLOSIVE AMMO", "flat", "+%s rocket or grenade per explosive load" },
	} :: { [string]: { string } }
do
	STATS[key] = {
		field = if def[3] == "pct" then "typeMagPct" else "typeAmmoFlat",
		filter = ARCH[def[1]],
		name = def[2],
		icon = "MagSize",
		kind = def[3],
		fmt = def[4],
	}
end
Skills.Stats = STATS

local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII" }

local function fmtValue(kind: string, v: number): string
	if kind == "pct" then
		local p = v * 100
		return (if p == math.floor(p) then string.format("%d", p) else string.format("%.1f", p)) .. "%"
	elseif kind == "luck" then
		local p = v * Config.LuckOddsStep * 100
		return (if p == math.floor(p) then string.format("%d", p) else string.format("%.1f", p)) .. "%"
	end
	return if v == math.floor(v) then string.format("%d", v) else string.format("%.1f", v)
end
Skills.fmtValue = fmtValue

------------------------------------------------------------------ The defs
-- Round 26b: a tidy price (25s under 1,000, 50s under 5,000, 250s under 20,000, 500s above).
local function tidy(n: number): number
	local step = if n < 1000 then 25 elseif n < 5000 then 50 elseif n < 20000 then 250 else 500
	return math.max(step, math.round(n / step) * step)
end

Skills.List = {} :: { Node }
Skills.ById = {} :: { [string]: Node }
Skills.ByCell = {} :: { [string]: string } -- "q,r" -> node id ("0,0" -> START)
Skills.ByCell[SkillLayout.key(0, 0)] = Skills.START

do
	local rings = SkillLayout.rings()
	for w, branch in Skills.Branches do
		local rows = (Config.SkillNodes :: any)[branch.id] :: { { { any } } }
		-- How many times each stat appears in the branch: a stat that repeats gets numerals (DAMAGE I, II ...).
		local total: { [string]: number } = {}
		for _, row in rows do
			for _, e in row do
				total[e[1]] = (total[e[1]] or 0) + 1
			end
		end
		local seen: { [string]: number } = {}
		for ring = 1, SkillLayout.Rings do
			local row = rows[ring] or {}
			local cells = rings[ring][w]
			for slot, cell in cells do
				local e = row[slot]
				if not e then
					warn(string.format("[GHS Skills] %s ring %d has no node for slot %d", branch.id, ring, slot))
					continue
				end
				local key = tostring(e[1])
				local def = STATS[key]
				if not def then
					warn("[GHS Skills] unknown stat " .. key .. " in " .. branch.id)
					continue
				end
				seen[key] = (seen[key] or 0) + 1
				local n = seen[key]
				local value = tonumber(e[2]) or 0
				local weight = tonumber(e[3]) or (Config.SkillCostByStat :: any)[key] or 1
				local base = Config.SkillCostByRing[ring] or Config.SkillCostByRing[#Config.SkillCostByRing]
				local cost = tidy(base * weight * (1 + Config.SkillCostRepeatStep * (n - 1)))
				local node: Node = {
					id = string.format("%s_%s_%d", string.lower(branch.id), string.lower(key), n),
					branch = branch.id,
					ring = ring,
					slot = slot,
					name = if (total[key] or 0) > 1 then def.name .. " " .. (ROMAN[n] or tostring(n)) else def.name,
					icon = def.icon,
					effect = { stat = def.field, value = value, kind = def.kind, filter = def.filter },
					line = string.format(def.fmt, fmtValue(def.kind, value)),
					cost = cost,
					q = cell.q,
					r = cell.r,
				}
				table.insert(Skills.List, node)
				Skills.ById[node.id] = node
				Skills.ByCell[SkillLayout.key(cell.q, cell.r)] = node.id
			end
		end
	end
end

-- The web's static table: { id, q, r } for every node (START excluded).
function Skills.layout(): { { id: string, q: number, r: number } }
	local out = {}
	for _, n in Skills.List do
		table.insert(out, { id = n.id, q = n.q, r = n.r })
	end
	return out
end

-- Gold for a node (its ring's base x its stat's weight, Round 26b).
-- Round 26c: START is bought too (SkillStartCost): it unlocks the web.
function Skills.cost(id: string): number
	if id == Skills.START then
		return Config.SkillStartCost
	end
	local n = Skills.ById[id]
	return if n then n.cost else math.huge
end

local neighbourCache: { [string]: { string } } = {}
-- The ids of a cell's six hex neighbours that hold a node (START included).
function Skills.neighbours(id: string): { string }
	local cached = neighbourCache[id]
	if cached then
		return cached
	end
	local q, r = 0, 0
	local n = Skills.ById[id]
	if n then
		q, r = n.q, n.r
	elseif id ~= Skills.START then
		return {}
	end
	local out = {}
	for _, d in SkillLayout.DIRS do
		local other = Skills.ByCell[SkillLayout.key(q + d[1], r + d[2])]
		if other then
			table.insert(out, other)
		end
	end
	neighbourCache[id] = out
	return out
end

-- Owned: in the profile's set (Round 26c: START too, once bought; it unlocks the web).
function Skills.owns(owned: { [string]: any }?, id: string): boolean
	return owned ~= nil and owned[id] == true
end

-- The web is open once START is bought.
function Skills.unlocked(owned: { [string]: any }?): boolean
	return Skills.owns(owned, Skills.START)
end

-- Next to an owned hex (any of six, across wedge seams too). START needs no neighbour.
function Skills.adjacent(owned: { [string]: any }?, id: string): boolean
	if id == Skills.START then
		return true
	end
	for _, nb in Skills.neighbours(id) do
		if Skills.owns(owned, nb) then
			return true
		end
	end
	return false
end

-- Buyable right now: not owned, next to an owned hex, and the Gold covers it.
function Skills.affordable(owned: { [string]: any }?, gold: number, id: string): boolean
	return (id == Skills.START or Skills.ById[id] ~= nil)
		and not Skills.owns(owned, id)
		and Skills.adjacent(owned, id)
		and gold >= Skills.cost(id)
end

-- Every node buyable right now (the SKILLS badge, the summary line).
function Skills.affordableIds(owned: { [string]: any }?, gold: number): { string }
	local out = {}
	if not Config.SkillsEnabled then
		return out
	end
	if Skills.affordable(owned, gold, Skills.START) then
		table.insert(out, Skills.START)
	end
	for _, n in Skills.List do
		if Skills.affordable(owned, gold, n.id) then
			table.insert(out, n.id)
		end
	end
	return out
end

-- Steps from the nearest owned hex (0 = owned): the client's reveal state (1 revealed, 2 outlined, 3+ hidden).
-- Round 26c: before START is bought it counts as revealed (1), so ring 1 shows as ? around it and nothing farther.
function Skills.distances(owned: { [string]: any }?): { [string]: number }
	local dist: { [string]: number } = { [Skills.START] = if Skills.unlocked(owned) then 0 else 1 }
	for _, n in Skills.List do
		if Skills.owns(owned, n.id) then
			dist[n.id] = 0
		end
	end
	-- Relax until nothing changes (91 cells, a few passes).
	local changed = true
	while changed do
		changed = false
		for id, d in table.clone(dist) do
			for _, nb in Skills.neighbours(id) do
				if dist[nb] == nil or dist[nb] > d + 1 then
					dist[nb] = d + 1
					changed = true
				end
			end
		end
	end
	return dist
end

------------------------------------------------------------------ Modifiers
export type Mods = {
	nodes: number,
	damagePct: number,
	critPct: number,
	headshotPct: number,
	eliteDamagePct: number,
	bossDamagePct: number,
	abilityDamagePct: number,
	maxHpPct: number,
	armorFlat: number,
	damageTakenPct: number,
	hpRegenFlat: number,
	armorDelayPct: number,
	revivePct: number,
	bleedOutFlat: number,
	moveSpeedPct: number,
	reloadPct: number,
	cooldownPct: number,
	interactPct: number,
	bagValuePct: number,
	pickupRadiusPct: number,
	pickupSpeedPct: number,
	bankedPct: number,
	startCashFlat: number,
	dealerPct: number,
	cardLuck: number,
	dealerLuck: number,
	crateLuck: number,
	typeDamagePct: { [string]: number },
	typeMagPct: { [string]: number },
	typeAmmoFlat: { [string]: number },
}

Skills.SCALARS = {
	"damagePct",
	"critPct",
	"headshotPct",
	"eliteDamagePct",
	"bossDamagePct",
	"abilityDamagePct",
	"maxHpPct",
	"armorFlat",
	"damageTakenPct",
	"hpRegenFlat",
	"armorDelayPct",
	"revivePct",
	"bleedOutFlat",
	"moveSpeedPct",
	"reloadPct",
	"cooldownPct",
	"interactPct",
	"bagValuePct",
	"pickupRadiusPct",
	"pickupSpeedPct",
	"bankedPct",
	"startCashFlat",
	"dealerPct",
	"cardLuck",
	"dealerLuck",
	"crateLuck",
}

function Skills.zero(): Mods
	local m: any = { nodes = 0, typeDamagePct = {}, typeMagPct = {}, typeAmmoFlat = {} }
	for _, k in Skills.SCALARS do
		m[k] = 0
	end
	return m :: Mods
end

-- The owned set folded into one flat table, every node summed additively. SkillsEnabled false: all zeros.
function Skills.modifiers(owned: { [string]: any }?): Mods
	local m: any = Skills.zero()
	if not Config.SkillsEnabled or not owned then
		return m
	end
	for _, n in Skills.List do
		if owned[n.id] == true then
			m.nodes += 1
			local e = n.effect
			if e.filter then
				local t = m[e.stat]
				t[e.filter] = (t[e.filter] or 0) + e.value
			else
				m[e.stat] += e.value
			end
		end
	end
	return m :: Mods
end

-- What a modifier table (or a sync's copy of one) adds to a gun of this archetype: Armory-stage bonuses that add to
-- the level's own multipliers (dmg, mag, reload) and flat rounds.
function Skills.weaponBonus(mods: any, archetype: string?): { dmg: number, mag: number, ammo: number, reload: number }
	if typeof(mods) ~= "table" then
		return { dmg = 0, mag = 0, ammo = 0, reload = 0 }
	end
	local a = archetype or ""
	local function typed(t: any): number
		return if typeof(t) == "table" then tonumber(t[a]) or 0 else 0
	end
	return {
		dmg = (tonumber(mods.damagePct) or 0) + typed(mods.typeDamagePct),
		mag = typed(mods.typeMagPct),
		ammo = typed(mods.typeAmmoFlat),
		reload = tonumber(mods.reloadPct) or 0,
	}
end

-- The one-line summary the run start logs: "damage +9% hp +16% armor +20 ...".
function Skills.summary(m: Mods): string
	local parts = {}
	local function pct(label: string, v: number)
		if v ~= 0 then
			table.insert(parts, string.format("%s %+d%%", label, math.round(v * 100)))
		end
	end
	local function flat(label: string, v: number)
		if v ~= 0 then
			table.insert(parts, string.format("%s %+g", label, v))
		end
	end
	pct("damage", m.damagePct)
	pct("crit", m.critPct)
	pct("headshot", m.headshotPct)
	pct("elite", m.eliteDamagePct)
	pct("boss", m.bossDamagePct)
	pct("ability", m.abilityDamagePct)
	pct("hp", m.maxHpPct)
	flat("armor", m.armorFlat)
	pct("taken", -m.damageTakenPct)
	flat("regen", m.hpRegenFlat)
	pct("armorDelay", -m.armorDelayPct)
	pct("revive", m.revivePct)
	flat("bleed", m.bleedOutFlat)
	pct("move", m.moveSpeedPct)
	pct("reload", m.reloadPct)
	pct("cooldown", -m.cooldownPct)
	pct("holds", m.interactPct)
	pct("bag", m.bagValuePct)
	pct("magnet", m.pickupRadiusPct)
	pct("pickup", m.pickupSpeedPct)
	pct("fence", m.bankedPct)
	flat("seed$", m.startCashFlat)
	pct("dealer", -m.dealerPct)
	flat("cardLuck", m.cardLuck)
	flat("dealerLuck", m.dealerLuck)
	flat("crateLuck", m.crateLuck)
	local function typed(suffix: string, t: { [string]: number }, asPct: boolean)
		local keys = {}
		for k in t do
			table.insert(keys, k)
		end
		table.sort(keys)
		for _, k in keys do
			if asPct then
				pct(string.lower(k) .. suffix, t[k])
			else
				flat(string.lower(k) .. suffix, t[k])
			end
		end
	end
	typed("Dmg", m.typeDamagePct, true)
	typed("Mag", m.typeMagPct, true)
	typed("Ammo", m.typeAmmoFlat, false)
	return if #parts > 0 then table.concat(parts, " ") else "nothing"
end

return Skills
