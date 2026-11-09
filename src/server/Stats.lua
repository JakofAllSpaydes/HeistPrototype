--!strict
-- All stat math lives here. Brief 12: one shared resolver. Every bonus to a stat is a source { id, stat, value }
-- that the system granting it registers for the player (in-run cards and dealer stands, the held gun's Armory level,
-- the Skill Web, class passives and mastery, boosts, timed buffs like Adrenaline and Overclock). Sources are added
-- and removed, never edited; Stats.resolve folds a stat's live sources by its mode (Config.StatDefs) and caches the
-- answer until the next change. Every hook reads a bonused stat through Stats.resolve / Stats.mult / Stats.time.
--   haste    points add; a time divides by (1 + h / 100), a rate multiplies by it
--   resist   1 - prod(1 - r): never 100%
--   softcap  base x (1 + max x h / (h + k) / 100): the ceiling is an asymptote
--   additive plain sum (any stat not in StatDefs)
--   capped   plain sum (plus the def's base), hard ceiling
-- Different stats still multiply with each other (damage x elite damage x crit); within one stat the mode rules.
-- The client never computes a stat; it displays what StateSync sends (resolved values included).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Weapons = require(Shared.Weapons)
local Types = require(Shared.Types)
local Upgrades = require(Shared.Upgrades)

local Stats = {}

------------------------------------------------------------------ The resolver
export type Source = { id: string, stat: string, value: number, untilT: number? }
type Book = {
	byId: { [string]: Source },
	byStat: { [string]: { [string]: Source } },
	cache: { [string]: number },
	expiry: number, -- the earliest untilT among the live sources (math.huge = none)
}
type Def = { mode: string, max: number?, k: number?, cap: number?, base: string? }

local ADDITIVE: Def = { mode = "additive" }
local books: { [Player]: Book } = setmetatable({} :: any, { __mode = "k" })

-- Debug Stats log (Config.StatsLogEnabled is the default).
Stats.logEnabled = Config.StatsLogEnabled

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function bookOf(player: Player): Book
	local b = books[player]
	if not b then
		b = { byId = {}, byStat = {}, cache = {}, expiry = math.huge }
		books[player] = b
	end
	return b
end

function Stats.def(stat: string): Def
	local defs = Config.StatDefs :: { [string]: Def }
	local d = defs[stat]
	if d then
		return d
	end
	local root = string.match(stat, "^([^%.]+)%.")
	if root and defs[root] then
		return defs[root]
	end
	return ADDITIVE
end

function Stats.mode(stat: string): string
	return Stats.def(stat).mode
end

local function softcap(def: Def, h: number): number
	if h <= 0 then
		return math.max(h, -50) -- a malus is linear (and never halves you twice)
	end
	local max = def.max or Config.MoveSpeedSoftMax
	local k = math.max(def.k or Config.MoveSpeedK, 1)
	return max * h / (h + k)
end

local function fold(book: Book, stat: string): number
	local def = Stats.def(stat)
	local list = book.byStat[stat]
	if def.mode == "resist" then
		local keep = 1
		if list then
			for _, s in list do
				keep *= 1 - math.min(s.value, 95) / 100
			end
		end
		return (1 - keep) * 100
	end
	local sum = 0
	if list then
		for _, s in list do
			sum += s.value
		end
	end
	if def.mode == "softcap" then
		return softcap(def, sum)
	elseif def.mode == "capped" then
		local base = if def.base then tonumber((Config :: any)[def.base]) or 0 else 0
		return math.clamp(base + sum, 0, def.cap or 100)
	end
	return sum
end

local function purge(player: Player, book: Book)
	local t = now()
	if t < book.expiry then
		return
	end
	local nextExpiry = math.huge
	for id, s in book.byId do
		local u = s.untilT
		if u then
			if u <= t then
				book.byId[id] = nil
				local list = book.byStat[s.stat]
				if list then
					list[id] = nil
				end
				book.cache[s.stat] = nil
			else
				nextExpiry = math.min(nextExpiry, u)
			end
		end
	end
	book.expiry = nextExpiry
	local _ = player
end

local function logChange(player: Player, stat: string)
	if not Stats.logEnabled then
		return
	end
	print(
		string.format(
			"[GHS Stats] %s %s %s <- %d sources",
			player.Name,
			stat,
			Stats.fmt(stat, Stats.resolve(player, stat)),
			Stats.count(player, stat)
		)
	)
end

local function detach(book: Book, id: string): string?
	local s = book.byId[id]
	if not s then
		return nil
	end
	book.byId[id] = nil
	local list = book.byStat[s.stat]
	if list then
		list[id] = nil
	end
	book.cache[s.stat] = nil
	return s.stat
end

-- Register a source. An id that exists is replaced (removed, then added); a value of 0 only removes it.
-- `untilT` (server time) makes it expire on its own.
function Stats.add(player: Player, id: string, stat: string, value: number, untilT: number?)
	local book = bookOf(player)
	local old = detach(book, id)
	if value ~= 0 and value == value then
		local s: Source = { id = id, stat = stat, value = value, untilT = untilT }
		book.byId[id] = s
		local list = book.byStat[stat]
		if not list then
			list = {}
			book.byStat[stat] = list
		end
		list[id] = s
		book.cache[stat] = nil
		if untilT then
			book.expiry = math.min(book.expiry, untilT)
		end
		logChange(player, stat)
	end
	if old and old ~= stat then
		logChange(player, old)
	elseif old and (value == 0 or value ~= value) then
		logChange(player, old)
	end
end

-- Like add, but a no-op when the same source is already there (for systems that re-assert every tick).
function Stats.set(player: Player, id: string, stat: string, value: number, untilT: number?)
	local s = bookOf(player).byId[id]
	if s and s.stat == stat and s.value == value and s.untilT == untilT then
		return
	end
	if not s and value == 0 then
		return
	end
	Stats.add(player, id, stat, value, untilT)
end

function Stats.remove(player: Player, id: string)
	local stat = detach(bookOf(player), id)
	if stat then
		logChange(player, stat)
	end
end

-- Remove every source whose id starts with `prefix` ("card:", "web:", "buff:"). Returns how many went.
function Stats.removeGroup(player: Player, prefix: string): number
	local book = bookOf(player)
	local ids = {}
	for id in book.byId do
		if string.sub(id, 1, #prefix) == prefix then
			table.insert(ids, id)
		end
	end
	local stats: { [string]: boolean } = {}
	for _, id in ids do
		local stat = detach(book, id)
		if stat then
			stats[stat] = true
		end
	end
	for stat in stats do
		logChange(player, stat)
	end
	return #ids
end

function Stats.has(player: Player, id: string): boolean
	return bookOf(player).byId[id] ~= nil
end

function Stats.clear(player: Player)
	books[player] = nil
end

-- The resolved value in the stat's own unit: haste / additive / capped points (capped clamped), softcap's effective
-- percent, resist's combined percent.
function Stats.resolve(player: Player, stat: string): number
	local book = bookOf(player)
	purge(player, book)
	local v = book.cache[stat]
	if v == nil then
		v = fold(book, stat)
		book.cache[stat] = v
	end
	return v :: number
end

-- The raw sum of a stat's sources (what the cards add up to before the mode).
function Stats.points(player: Player, stat: string): number
	local book = bookOf(player)
	purge(player, book)
	local sum = 0
	local list = book.byStat[stat]
	if list then
		for _, s in list do
			sum += s.value
		end
	end
	return sum
end

-- The multiplier a stat applies: 1 + r / 100 (haste: the speed factor; resist: 1 - r / 100, the damage you take),
-- floored at StatMultFloor so maluses never zero or flip anything.
function Stats.mult(player: Player, stat: string): number
	local r = Stats.resolve(player, stat)
	if Stats.mode(stat) == "resist" then
		return math.max(0.05, 1 - r / 100)
	end
	return math.max(Config.StatMultFloor, 1 + r / 100)
end

-- A time under a haste stat: base / (1 + h / 100), never under `floor`.
function Stats.time(player: Player, stat: string, base: number, floor: number?): number
	return math.max(floor or 0, base / Stats.mult(player, stat))
end

-- Several stats' points summed into one multiplier (damage + this gun's typed damage, a haste and its typed twin).
function Stats.multOf(player: Player, stats: { string }): number
	local sum = 0
	for _, s in stats do
		sum += Stats.resolve(player, s)
	end
	return math.max(Config.StatMultFloor, 1 + sum / 100)
end

function Stats.count(player: Player, stat: string): number
	local book = bookOf(player)
	purge(player, book)
	local n = 0
	local list = book.byStat[stat]
	if list then
		for _ in list do
			n += 1
		end
	end
	return n
end

function Stats.sourcesOf(player: Player, stat: string): { Source }
	local book = bookOf(player)
	purge(player, book)
	local out = {}
	local list = book.byStat[stat]
	if list then
		for _, s in list do
			table.insert(out, s)
		end
	end
	table.sort(out, function(a, b)
		return a.id < b.id
	end)
	return out
end

-- A capped stat at its ceiling (crit at 100%: the crit cards leave this player's draws).
function Stats.isMaxed(player: Player, stat: string): boolean
	local def = Stats.def(stat)
	return def.mode == "capped" and Stats.resolve(player, stat) >= (def.cap or 100)
end

-- "+23%" / "-23%" (haste on a time shows the time saved) / "x1.4".
function Stats.fmt(stat: string, value: number): string
	local mode = Stats.mode(stat)
	if mode == "haste" then
		return string.format("+%g haste", math.round(value * 10) / 10)
	elseif mode == "resist" then
		return string.format("-%d%%", math.round(value))
	end
	return string.format("%+g", math.round(value * 10) / 10)
end

-- Every stat with a source: { stat, mode, resolved, sources }.
function Stats.report(player: Player): { { stat: string, mode: string, resolved: number, sources: { Source } } }
	local book = bookOf(player)
	purge(player, book)
	local names = {}
	for stat, list in book.byStat do
		if next(list) ~= nil then
			table.insert(names, stat)
		end
	end
	table.sort(names)
	local out = {}
	for _, stat in names do
		table.insert(out, {
			stat = stat,
			mode = Stats.mode(stat),
			resolved = Stats.resolve(player, stat),
			sources = Stats.sourcesOf(player, stat),
		})
	end
	return out
end

-- The debug STATS block (the Stats button).
function Stats.print(player: Player)
	print(string.format("[GHS Stats] STATS %s ----------------", player.Name))
	for _, row in Stats.report(player) do
		local parts = {}
		for _, s in row.sources do
			table.insert(parts, string.format("%s %+g", s.id, math.round(s.value * 10) / 10))
		end
		print(
			string.format(
				"[GHS Stats]   %-16s %-8s %-12s <- %s",
				row.stat,
				row.mode,
				Stats.fmt(row.stat, row.resolved),
				table.concat(parts, ", ")
			)
		)
	end
	local area = Stats.resolve(player, "area")
	print(
		string.format(
			"[GHS Area] %s area %+d%% from %d sources",
			player.Name,
			math.round(area),
			Stats.count(player, "area")
		)
	)
end

------------------------------------------------------------------ Source maps
-- Upgrade card stat id -> resolver stat. Cards and dealer stands register `card:<n>` sources through UpgradeShop.
Stats.CardStat = {
	Damage = "damage",
	FireRate = "fireRate",
	MagSize = "magSize",
	ReloadSpeed = "reload",
	CritChance = "critChance",
	HeadshotMult = "headshot",
	MoveSpeed = "moveSpeed",
	Accuracy = "accuracy",
	Pierce = "pierce",
	Ricochet = "ricochet",
	Splash = "splash",
	Multishot = "multishot",
	Lifesteal = "lifesteal",
	Incendiary = "incendiary",
	Cryo = "cryo",
	Concussive = "concussive",
	MaxHP = "maxHp",
	HPRegen = "hpRegen",
	Armor = "armor",
	AbilityCooldown = "cooldown",
	AbilityPower = "abilityPower",
	CashGain = "cashGain",
	Wildfire = "wildfire",
	Shatter = "shatter",
	Aftershock = "aftershock",
	ElementalPower = "elementalPower",
	Accelerant = "accelerant",
	TurretDamage = "turretDamage",
	HealPower = "healPower",
	DeadEyeTime = "deadEyeTime",
	BlastRadius = "area", -- brief 12: folded into AREA
	Area = "area",
	Demolition = "demolition",
} :: { [string]: string }

function Stats.cardStat(statId: string): string
	return Stats.CardStat[statId] or string.lower(string.sub(statId, 1, 1)) .. string.sub(statId, 2)
end

-- Skill Web modifier field -> resolver stat; `pct` fields are fractions (x100 to points).
Stats.WebStat = {
	damagePct = "damage",
	critPct = "critChance",
	headshotPct = "headshot",
	eliteDamagePct = "eliteDamage",
	bossDamagePct = "bossDamage",
	abilityDamagePct = "abilityDamage",
	maxHpPct = "maxHp",
	armorFlat = "armor",
	damageTakenPct = "damageTaken",
	hpRegenFlat = "hpRegenFlat",
	armorDelayPct = "armorDelay",
	revivePct = "revive",
	bleedOutFlat = "bleedOut",
	moveSpeedPct = "moveSpeed",
	reloadPct = "reload",
	cooldownPct = "cooldown",
	interactPct = "interact",
	bagValuePct = "bagValue",
	pickupRadiusPct = "pickupRadius",
	pickupSpeedPct = "pickup",
	bankedPct = "banked",
	startCashFlat = "startCash",
	dealerPct = "dealerDiscount",
	cardLuck = "cardLuck",
	dealerLuck = "dealerLuck",
	crateLuck = "crateLuck",
	typeDamagePct = "typeDamage",
	typeMagPct = "typeMag",
	typeAmmoFlat = "typeAmmo",
} :: { [string]: string }

-- A self buff's multipliers (PlayerState.buffFor); brief 12 registers them as `buff:<id>:*` sources.
export type Buffs = {
	fireRateMult: number,
	moveSpeedMult: number,
	reloadSpeedMult: number,
	damageMult: number,
	pierceAdd: number, -- extra pierce (dead eye)
	spreadMult: number?, -- Round 19c: x spread (dead eye's accuracy); nil = 1
}

------------------------------------------------------------------ The held gun and the computed sheet
-- The held gun's Armory level as sources (`armory:gun`): damage, mag, reload and fire rate points. Re-registered
-- whenever the gun in hand changes (PlayerState.computed checks the uid).
function Stats.registerGun(player: Player, held: Types.Held)
	Stats.removeGroup(player, "armory:")
	local level = held.level or 0
	if level <= 0 then
		return
	end
	Stats.add(player, "armory:gun:dmg", "damage", (Weapons.levelDmgMult(level) - 1) * 100)
	Stats.add(player, "armory:gun:mag", "magSize", (Weapons.levelMagMult(level) - 1) * 100)
	Stats.add(player, "armory:gun:reload", "reload", (Weapons.levelReloadDiv(level) - 1) * 100)
	Stats.add(player, "armory:gun:rate", "fireRate", (Weapons.levelRateMult(level) - 1) * 100)
end

-- Damage per shot of a gun at its base x rarity x (1 + every damage source / 100). `extra` adds points for this gun
-- only (its typed damage, its archetype's synergy).
function Stats.weaponDamage(player: Player, weaponId: string, rarity: number, extra: number?): number
	local w = Weapons.ById[weaponId]
	local pts = Stats.resolve(player, "damage") + Stats.resolve(player, "typeDamage." .. w.archetype) + (extra or 0)
	return w.baseDmg * math.max(Config.StatMultFloor, 1 + pts / 100) * Config.RarityDmgMult[rarity]
end

-- The archetype synergies raise their own guns' damage: ELEMENTAL POWER an Elemental gun's, DEMOLITION an Explosive
-- gun's (Round 25), as damage points for that gun.
local function archetypePoints(player: Player, archetype: string): number
	if archetype == "Elemental" then
		return math.max(0, Stats.resolve(player, "elementalPower"))
	elseif archetype == "Explosive" then
		return math.max(0, Stats.resolve(player, "demolition"))
	end
	return 0
end

local function plus(player: Player, stat: string): number
	return 1 + math.max(0, Stats.resolve(player, stat)) / 100
end

function Stats.compute(player: Player, held: Types.Held): Types.Computed
	local w = Weapons.ById[held.weaponId]
	local arch = w.archetype
	local R = function(stat: string): number
		return Stats.resolve(player, stat)
	end
	local elemMult = plus(player, "elementalPower")
	local rateMult = Stats.mult(player, "fireRate")
	local reloadMult = Stats.multOf(player, { "reload", "typeReload." .. arch })
	local magMult = Stats.multOf(player, { "magSize", "typeMag." .. arch })
	local spread = math.clamp(1 - R("accuracy") / 100, 0.05, 3)
	return {
		damage = Stats.weaponDamage(player, held.weaponId, held.rarity, archetypePoints(player, arch)),
		fireRate = w.fireRate * rateMult,
		magSize = math.max(1, math.round(w.magSize * magMult) + math.floor(R("typeAmmo." .. arch))),
		reloadTime = w.reloadTime / reloadMult,
		maxHP = math.max(1, math.round(Config.PlayerMaxHP * Stats.mult(player, "maxHp"))),
		hpRegen = (Config.PlayerHPRegenPerSec + R("hpRegenFlat")) * Stats.mult(player, "hpRegen"),
		moveSpeed = Config.PlayerWalkSpeed * Stats.mult(player, "moveSpeed"),
		critChance = R("critChance"),
		headshotMult = Config.HeadshotMult * Stats.mult(player, "headshot"),
		cashGain = Stats.mult(player, "cashGain"),
		abilityCdr = 1 - 1 / Stats.mult(player, "cooldown"), -- the share of a cooldown haste takes off (display)
		abilityPower = Stats.mult(player, "abilityPower"),
		incendiaryPower = math.max(0, R("incendiary") / 100) * elemMult,
		cryoPower = math.max(0, R("cryo") / 100) * elemMult,
		concussivePower = math.max(0, R("concussive") / 100) * elemMult,
		spreadMult = spread,
		pierce = math.max(0, R("pierce")) + Weapons.builtInPierce(w, held.rarity),
		ricochet = math.max(0, R("ricochet")),
		splash = math.max(0, R("splash")),
		multishot = math.max(0, R("multishot")),
		lifesteal = math.max(0, R("lifesteal")),
		wildfire = math.clamp(R("wildfire"), 0, Config.WildfireMaxPct),
		shatter = math.max(0, R("shatter")),
		aftershock = math.max(0, R("aftershock")),
		fireAbilityMult = plus(player, "accelerant"),
		turretDmgMult = plus(player, "turretDamage"),
		healMult = plus(player, "healPower"),
		deadEyeTimeMult = plus(player, "deadEyeTime"),
		blastRadiusMult = Stats.mult(player, "area"), -- brief 12: every explosion radius is the area stat
		areaMult = Stats.mult(player, "area"),
		explosiveDmgMult = plus(player, "demolition"),
	}
end

-- DPS as shown on tags and the held slot: damage x shots per second x pellets.
function Stats.weaponDps(player: Player, held: Types.Held, st: Types.Computed): number
	local w = Weapons.ById[held.weaponId]
	return st.damage * Weapons.effectiveRate(w, Stats.mult(player, "fireRate")) * w.pellets
end

function Stats.upgradePrice(n: number): number
	return math.round(Config.UpgradePrice * Config.UpgradePriceMult ^ n)
end

------------------------------------------------------------------ What the HUD shows
-- The tracker badge and tip for one card stat: the resolved total the way the card labels read (COOLDOWN shows the
-- share of a cooldown saved, -23% from +30 haste), and the sources behind it.
export type CardView = { text: string, n: number, lines: { string } }

local function shownPct(statId: string, stat: string, player: Player): number
	local mode = Stats.mode(stat)
	local r = Stats.resolve(player, stat)
	if mode == "haste" then
		local m = Stats.mult(player, stat)
		local u = Upgrades.byId(statId)
		if u and u.negative then
			return (1 - 1 / m) * 100 -- the time saved, shown as the card's reduction
		end
		return (m - 1) * 100
	end
	return r
end

local function sourceName(id: string): string
	local kind = string.match(id, "^([^:]+)") or id
	local names = {
		card = "CARD",
		dealer = "DEALER",
		web = "WEB",
		armory = "ARMORY",
		buff = "BUFF",
		passive = "MASTERY",
		boost = "BOOST",
		vip = "VIP",
		overclock = "OVERCLOCK",
		field = "MED BAG",
		debug = "DEBUG",
	}
	return names[kind] or string.upper(kind)
end

function Stats.cardView(player: Player, statId: string): CardView
	local stat = Stats.cardStat(statId)
	local shown = shownPct(statId, stat, player)
	local u = Upgrades.byId(statId)
	local text
	if Upgrades.isElement(statId) then
		text = string.format("%d%%", math.round(Stats.resolve(player, stat)))
	elseif u and u.negative then
		text = string.format("-%s%s", tostring(math.round(shown)), Upgrades.unit(statId))
	else
		text = Upgrades.pctText(math.round(shown * 10) / 10, nil)
		if Upgrades.unit(statId) ~= "%" then
			text = string.format("%+g", math.round(shown * 10) / 10)
		end
	end
	local lines = {}
	for _, s in Stats.sourcesOf(player, stat) do
		local v = if u and u.negative then -s.value else s.value
		table.insert(lines, string.format("%s %+g", sourceName(s.id), math.round(v * 10) / 10))
	end
	return { text = text, n = #lines, lines = lines }
end

return Stats
