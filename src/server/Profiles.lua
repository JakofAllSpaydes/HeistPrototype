--!strict
-- Player profiles over DataStoreService ("GHS_Profiles_v1"): Gold, owned weapons and their Armory levels,
-- the starter, classes, ability levels, masks, wraps, top wave, lifetime stats. One session cache per
-- player, loaded on join before the character spawns, written on every purchase / equip (debounced),
-- on the run payout, on leave and every ProfileAutosaveSec. UpdateAsync with 3 tries and 1 / 2 / 4s
-- backoff. When the DataStore is unavailable (Studio without API access) the module falls back to an
-- in-memory profile and warns once.
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Weapons = require(Shared.Weapons)
local Classes = require(Shared.Classes)
local Masks = require(Shared.Masks)
local Emotes = require(Shared.Emotes)
local Signal = require(Shared.Signal)
local Skills = require(Shared.Skills)
local Log = require(script.Parent.Log)

export type WeaponEntry = { level: number, wrap: string? }
export type Profile = {
	gold: number,
	weapons: { [string]: WeaponEntry }, -- presence = owned
	starterWeaponId: string,
	starterWeaponId2: string?, -- Round 24z: the second starter (the run's second gun slot); nil = empty
	favorites: { [string]: boolean }, -- Round 24y: weapon ids the player hearted (the Weapons tab sorts them first)
	classes: { owned: { [string]: boolean }, equipped: string },
	abilities: { [string]: number }, -- ability id -> level
	masks: { owned: { [string]: boolean }, equipped: string },
	emotes: { owned: { [string]: boolean }, squad: string, mvp: string }, -- line-up pose and MVP flex
	wraps: { owned: { [string]: boolean } },
	topWave: { [string]: number }, -- "<mapId>:<difficulty>" ("Arena:Normal", "TheBank:Hard") -> wave
	topBanked: { [string]: number }, -- "<mapId>:<difficulty>" -> best TOTAL BANKED in one run
	topTime: { [string]: number }, -- "<mapId>:<difficulty>" -> longest time survived (seconds)
	level: number, -- account level (Progression.lua)
	xp: number, -- XP into the current level
	lastHeistDay: number, -- UTC day number of the last completed run (FIRST HEIST OF THE DAY)
	-- Brief 5: weapon and class mastery XP (Mastery.lua); tiers from Config.WeaponMasteryTiers / ClassMasteryTiers.
	mastery: { weapons: { [string]: { xp: number } }, classes: { [string]: { xp: number } } },
	stats: {
		kills: number,
		matchesPlayed: number,
		goldEarned: number,
		bagsCollected: number,
		goldBanked: number,
		xp: number,
		timeSurvived: number,
		weaponMasteryXp: number, -- lifetime mastery XP earned, all guns
		classMasteryXp: number, -- lifetime mastery XP earned, all classes
	},
	pendingPayout: number, -- Gold granted this session that has not reached the store yet
	-- Round 16: per-account client options (Profiles.OPTIONS lists the keys), e.g. hotwireSymbols (colorblind).
	options: { [string]: boolean },
	-- Brief 6 (v3): the fake monetization layer.
	fakeRobux: number, -- the fake R$ balance every purchase debits (Purchases.lua)
	reviveTokens: number, -- SELF-REVIVE / REVIVE EVERYBODY spend these
	boosts: { [string]: { expiresAt: number } }, -- boost id -> os.time it runs out (real clock)
	vip: { active: boolean, since: number, renewsAt: number, ever: boolean }, -- fake clock
	vipGiftDay: number, -- the fake UTC day the VIP daily Gold was last claimed
	pass: {
		season: number,
		level: number,
		xp: number, -- into the current level (past the last level: toward the next overflow Gold)
		tier: number, -- 0 free, 1 PREMIUM, 2 PREMIUM+
		claimed: { [string]: { free: boolean?, p1: boolean?, p2: boolean? } }, -- "L7" -> lanes claimed
		seasonOver: any?, -- { season, name, autoClaimed } waiting for the SEASON OVER sheet
	},
	jobs: {
		dailyResetDay: number,
		weeklyResetWeek: number,
		daily: { any },
		bounty: { any },
		rerollUsed: number, -- rerolls spent on dailyResetDay
		announcedDay: number, -- MARLOW announced this day's jobs
		boardSeenDay: number, -- the board was opened on this day (the beacon stops pulsing)
	},
	cratePity: { [string]: number }, -- crate id -> opens since the last Epic+
	crateOpens: { [string]: number }, -- crate id -> banked free opens (bundles, the pass)
	purchases: { { id: string, price: number, at: number } }, -- the readout log (last Config.PurchaseLogKeep)
	clockOffset: number, -- seconds added to UTC for this player's fake clock (debug advance day)
	dailyReroll: { day: number, count: number }, -- Round 18: FEATURED daily items rerolled `count` times on `day`
	-- Brief 9 (v5): the Skill Web. owned = node ids bought (START is implicit, never stored); seen = affordable nodes
	-- the player has seen on the web (a node that became affordable since pulses once on open). A respec is a wipe.
	skills: { owned: { [string]: boolean }, seen: { [string]: boolean } },
	version: number,
}

-- The options a client may set with Remotes.SetOption, and their defaults.
local OPTIONS: { [string]: boolean } = {
	hotwireSymbols = false, -- Hotwire COLORBLIND: the colorblind-safe palette plus a letter on each wire and socket
}

type Entry = {
	profile: Profile,
	dirty: boolean,
	saveAt: number, -- os.clock when the debounced save fires, 0 = none pending
	saving: boolean,
	lastSave: number,
}

local STORE_NAME = "GHS_Profiles_v1"
-- 2 (brief 5): the claymore moved SHARPSHOOTER -> INITIATE and turret / barricade INITIATE -> ENGINEER. Levels are
-- keyed by ability id, so they move with the ability; the migration only logs it. Eagle Eye, Frag and Overclock
-- start at level 0 (absent).
-- 3 (brief 6): fake Robux, revive tokens, boosts, VIP, the pass, Jobs, crate pity / opens, the purchase log.
-- 4 (brief 7): records are keyed <mapId>:<difficulty>. Every run before brief 7 was on the arena (whose id was
-- the placeholder "TheBank"), so TheBank:* moves to Arena:* once; a run on the real Bank then writes TheBank:*.
-- 5 (brief 9): the Skill Web's owned / seen sets, empty on migration.
local VERSION = 5
local RETRY_BACKOFF = { 1, 2, 4 }

local Profiles = {}
Profiles.OPTIONS = OPTIONS
Profiles.Loaded = Signal.new() -- (player, profile)
Profiles.available = true -- false once the DataStore refused us; everything stays in memory

local store: DataStore? = nil
local entries: { [Player]: Entry } = {}
local warned = false

function Profiles.key(player: Player): string
	return "p_" .. player.UserId
end

local function lockKey(player: Player): string
	return "lock_" .. player.UserId
end

local function unavailable(reason: any)
	if not warned then
		warned = true
		warn(
			"[GHS Profiles] DataStore unavailable, using in-memory profiles (enable Studio Access to API Services): "
				.. tostring(reason)
		)
	end
	Profiles.available = false
end

function Profiles.fresh(): Profile
	return {
		gold = Config.StartingGold,
		weapons = (function()
			-- One gun of each archetype is owned from the start so every type can be tested without buying.
			local owned = { [Weapons.Starter] = { level = 0 } }
			for _, id in Weapons.DefaultOwned do
				if Weapons.ById[id] then
					owned[id] = { level = 0 }
				end
			end
			return owned
		end)(),
		starterWeaponId = Weapons.Starter,
		favorites = {},
		classes = { owned = { [Classes.Default] = true }, equipped = Classes.Default },
		abilities = {},
		masks = { owned = { [Masks.Default] = true }, equipped = Masks.Default },
		emotes = (function()
			local owned = {}
			for _, id in Emotes.DefaultOwned do
				owned[id] = true
			end
			return { owned = owned, squad = Emotes.DefaultSquad, mvp = Emotes.DefaultMvp }
		end)(),
		wraps = { owned = {} },
		topWave = {},
		topBanked = {},
		topTime = {},
		level = 1,
		xp = 0,
		lastHeistDay = 0,
		mastery = { weapons = {}, classes = {} },
		stats = {
			kills = 0,
			matchesPlayed = 0,
			goldEarned = 0,
			bagsCollected = 0,
			goldBanked = 0,
			xp = 0,
			timeSurvived = 0,
			weaponMasteryXp = 0,
			classMasteryXp = 0,
		},
		pendingPayout = 0,
		options = table.clone(OPTIONS),
		fakeRobux = Config.FakeRobuxStart,
		reviveTokens = Config.ReviveTokensStart,
		boosts = {},
		vip = { active = false, since = 0, renewsAt = 0, ever = false },
		vipGiftDay = 0,
		pass = { season = 0, level = 1, xp = 0, tier = 0, claimed = {}, seasonOver = nil },
		jobs = {
			dailyResetDay = 0,
			weeklyResetWeek = 0,
			daily = {},
			bounty = {},
			rerollUsed = 0,
			announcedDay = 0,
			boardSeenDay = 0,
		},
		cratePity = {},
		crateOpens = {},
		purchases = {},
		clockOffset = 0,
		dailyReroll = { day = 0, count = 0 },
		skills = { owned = {}, seen = {} },
		version = VERSION,
	}
end

-- Brief 7: the best topWave across every map and difficulty, and the map it was on (the hub tag's suffix).
function Profiles.bestTopWave(p: Profile): (number, string?)
	local best, bestMap = 0, nil
	for key, v in p.topWave do
		if v > best then
			best = v
			bestMap = string.match(key, "^([^:]+):")
		end
	end
	return best, bestMap
end

local function num(v: any, default: number): number
	return if typeof(v) == "number" and v == v then v else default
end

-- Fill anything a stored profile is missing (older versions, hand edits) so the rest of the server never nil-checks.
local function migrate(raw: any): Profile
	local p = Profiles.fresh()
	if typeof(raw) ~= "table" then
		return p
	end
	if typeof(raw.gold) == "number" then
		p.gold = math.max(0, math.floor(raw.gold))
	end
	if typeof(raw.weapons) == "table" then
		p.weapons = {}
		for id, entry in raw.weapons do
			if Weapons.ById[id] and typeof(entry) == "table" then
				p.weapons[id] = {
					level = math.max(0, math.floor(tonumber(entry.level) or 0)),
					wrap = if typeof(entry.wrap) == "string" then entry.wrap else nil,
				}
			end
		end
	end
	-- Older stores: every default-owned gun is granted so the testable set is always there.
	for _, id in Weapons.DefaultOwned do
		if Weapons.ById[id] and not p.weapons[id] then
			p.weapons[id] = { level = 0 }
		end
	end

	if
		typeof(raw.starterWeaponId2) == "string"
		and p.weapons[raw.starterWeaponId2]
		and raw.starterWeaponId2 ~= raw.starterWeaponId
	then
		p.starterWeaponId2 = raw.starterWeaponId2
	end
	if typeof(raw.starterWeaponId) == "string" and p.weapons[raw.starterWeaponId] then
		p.starterWeaponId = raw.starterWeaponId
	elseif not p.weapons[p.starterWeaponId] then
		p.starterWeaponId = (next(p.weapons)) :: string
	end
	if typeof(raw.classes) == "table" then
		if typeof(raw.classes.owned) == "table" then
			for id, v in raw.classes.owned do
				if Classes.ById[id] and v then
					p.classes.owned[id] = true
				end
			end
		end
		if typeof(raw.classes.equipped) == "string" and p.classes.owned[raw.classes.equipped] then
			p.classes.equipped = raw.classes.equipped
		end
	end
	if typeof(raw.abilities) == "table" then
		for id, level in raw.abilities do
			if Classes.AbilityById[id] and typeof(level) == "number" then
				p.abilities[id] = math.max(0, math.floor(level))
			end
		end
	end
	if typeof(raw.masks) == "table" then
		if typeof(raw.masks.owned) == "table" then
			for id, v in raw.masks.owned do
				if Masks.ById[id] and v then
					p.masks.owned[id] = true
				end
			end
		end
		if typeof(raw.masks.equipped) == "string" and p.masks.owned[raw.masks.equipped] then
			p.masks.equipped = raw.masks.equipped
		end
	end
	if typeof(raw.emotes) == "table" then
		if typeof(raw.emotes.owned) == "table" then
			for id, v in raw.emotes.owned do
				if Emotes.ById[id] and v then
					p.emotes.owned[id] = true
				end
			end
		end
		if typeof(raw.emotes.squad) == "string" and p.emotes.owned[raw.emotes.squad] then
			p.emotes.squad = raw.emotes.squad
		end
		if typeof(raw.emotes.mvp) == "string" and p.emotes.owned[raw.emotes.mvp] then
			p.emotes.mvp = raw.emotes.mvp
		end
	end
	if typeof(raw.favorites) == "table" then
		for id, v in raw.favorites do
			if v == true and typeof(id) == "string" then
				p.favorites[id] = true
			end
		end
	end
	if typeof(raw.wraps) == "table" and typeof(raw.wraps.owned) == "table" then
		for id, v in raw.wraps.owned do
			if v then
				p.wraps.owned[id] = true
			end
		end
	end
	if typeof(raw.topWave) == "table" then
		for k, v in raw.topWave do
			if typeof(k) == "string" and typeof(v) == "number" then
				p.topWave[k] = math.floor(v)
			end
		end
	end
	if typeof(raw.topBanked) == "table" then
		for k, v in raw.topBanked do
			if typeof(k) == "string" and typeof(v) == "number" then
				p.topBanked[k] = math.floor(v)
			end
		end
	end
	if typeof(raw.topTime) == "table" then
		for k, v in raw.topTime do
			if typeof(k) == "string" and typeof(v) == "number" then
				p.topTime[k] = math.floor(v)
			end
		end
	end
	if typeof(raw.level) == "number" then
		p.level = math.max(1, math.floor(raw.level))
	end
	if typeof(raw.xp) == "number" then
		p.xp = math.max(0, math.floor(raw.xp))
	end
	if typeof(raw.lastHeistDay) == "number" then
		p.lastHeistDay = math.floor(raw.lastHeistDay)
	end
	if typeof(raw.mastery) == "table" then
		for _, kind in { "weapons", "classes" } do
			local src = raw.mastery[kind]
			if typeof(src) == "table" then
				for id, entry in src do
					local valid = if kind == "weapons" then Weapons.ById[id] ~= nil else Classes.ById[id] ~= nil
					if valid and typeof(entry) == "table" and typeof(entry.xp) == "number" then
						(p.mastery :: any)[kind][id] = { xp = math.max(0, math.floor(entry.xp)) }
					end
				end
			end
		end
	end
	if typeof(raw.stats) == "table" then
		for k in p.stats do
			local v = raw.stats[k]
			if typeof(v) == "number" then
				(p.stats :: any)[k] = math.floor(v)
			end
		end
	end
	if typeof(raw.pendingPayout) == "number" then
		p.pendingPayout = math.max(0, math.floor(raw.pendingPayout))
	end
	if typeof(raw.options) == "table" then
		for k in OPTIONS do
			if typeof(raw.options[k]) == "boolean" then
				p.options[k] = raw.options[k]
			end
		end
	end
	-- Brief 6 (v3). A v2 store has none of these: the fresh defaults stand (100,000 fake R$, 3 tokens).
	if typeof(raw.fakeRobux) == "number" then
		p.fakeRobux = math.max(0, math.floor(raw.fakeRobux))
	end
	if typeof(raw.reviveTokens) == "number" then
		p.reviveTokens = math.max(0, math.floor(raw.reviveTokens))
	end
	if typeof(raw.boosts) == "table" then
		for id, b in raw.boosts do
			if typeof(id) == "string" and typeof(b) == "table" and typeof(b.expiresAt) == "number" then
				p.boosts[id] = { expiresAt = b.expiresAt }
			end
		end
	end
	if typeof(raw.vip) == "table" then
		p.vip.active = raw.vip.active == true
		p.vip.since = num(raw.vip.since, 0)
		p.vip.renewsAt = num(raw.vip.renewsAt, 0)
		p.vip.ever = raw.vip.ever == true or p.vip.active
	end
	p.vipGiftDay = num(raw.vipGiftDay, 0)
	if typeof(raw.pass) == "table" then
		local rp = raw.pass
		p.pass.season = math.floor(num(rp.season, 0))
		p.pass.level = math.max(1, math.floor(num(rp.level, 1)))
		p.pass.xp = math.max(0, math.floor(num(rp.xp, 0)))
		p.pass.tier = math.clamp(math.floor(num(rp.tier, 0)), 0, 2)
		if typeof(rp.claimed) == "table" then
			for k, lanes in rp.claimed do
				if typeof(k) == "string" and typeof(lanes) == "table" then
					p.pass.claimed[k] =
						{ free = lanes.free == true or nil, p1 = lanes.p1 == true or nil, p2 = lanes.p2 == true or nil }
				end
			end
		end
		if typeof(rp.seasonOver) == "table" then
			p.pass.seasonOver = rp.seasonOver
		end
	end
	if typeof(raw.jobs) == "table" then
		local rj = raw.jobs
		p.jobs.dailyResetDay = math.floor(num(rj.dailyResetDay, 0))
		p.jobs.weeklyResetWeek = math.floor(num(rj.weeklyResetWeek, 0))
		p.jobs.rerollUsed = math.floor(num(rj.rerollUsed, 0))
		p.jobs.announcedDay = math.floor(num(rj.announcedDay, 0))
		p.jobs.boardSeenDay = math.floor(num(rj.boardSeenDay, 0))
		for _, key in { "daily", "bounty" } do
			local list = rj[key]
			if typeof(list) == "table" then
				local out = {}
				for _, e in list do
					if typeof(e) == "table" and typeof(e.id) == "string" then
						table.insert(out, {
							id = e.id,
							progress = math.max(0, math.floor(num(e.progress, 0))),
							claimed = e.claimed == true,
						})
					end
				end
				(p.jobs :: any)[key] = out
			end
		end
	end
	for _, key in { "cratePity", "crateOpens" } do
		local src = raw[key]
		if typeof(src) == "table" then
			for id, n in src do
				if typeof(id) == "string" and typeof(n) == "number" then
					(p :: any)[key][id] = math.max(0, math.floor(n))
				end
			end
		end
	end
	if typeof(raw.purchases) == "table" then
		for _, e in raw.purchases do
			if typeof(e) == "table" and typeof(e.id) == "string" then
				table.insert(p.purchases, { id = e.id, price = num(e.price, 0), at = num(e.at, 0) })
			end
		end
	end
	p.clockOffset = num(raw.clockOffset, 0)
	if typeof(raw.dailyReroll) == "table" then
		p.dailyReroll.day = math.floor(num(raw.dailyReroll.day, 0))
		p.dailyReroll.count = math.max(0, math.floor(num(raw.dailyReroll.count, 0)))
	end
	-- Brief 9 (v5): only known node ids survive (a renamed node drops out instead of breaking the set).
	if typeof(raw.skills) == "table" then
		for _, key in { "owned", "seen" } do
			local src = raw.skills[key]
			if typeof(src) == "table" then
				for id, v in src do
					if v == true and typeof(id) == "string" and Skills.ById[id] then
						(p.skills :: any)[key][id] = true
					end
				end
			end
		end
	end
	local fromVersion = tonumber(raw.version) or 1
	if raw ~= nil and fromVersion < 4 then
		local moved = 0
		for _, records in { p.topWave, p.topBanked, p.topTime } do
			for key, v in table.clone(records) do
				local diff = string.match(key, "^TheBank:(.+)$")
				if diff then
					records[key] = nil
					records["Arena:" .. diff] = math.max(records["Arena:" .. diff] or 0, v)
					moved += 1
				end
			end
		end
		Log.event(
			"Profile",
			"v%d -> v4: %d record%s moved TheBank:* -> Arena:*",
			fromVersion,
			moved,
			if moved == 1 then "" else "s"
		)
	end
	if fromVersion < 2 and p.classes.owned.SHARPSHOOTER and (p.abilities.claymore or 0) > 0 then
		Log.event("Profile", "v1 -> v2: claymore LV %d now on INITIATE's Z", p.abilities.claymore)
	end
	if raw ~= nil and fromVersion < 5 then
		Log.event("Profile", "v%d -> v5", fromVersion)
	end
	if raw ~= nil and fromVersion < 3 then
		Log.event(
			"Profile",
			"v%d -> v3: R$ %d fake balance, %d revive tokens",
			fromVersion,
			p.fakeRobux,
			p.reviveTokens
		)
	end
	return p
end

-- A store call with the brief's retry: 3 tries, 1 / 2 / 4s. Returns ok, result.
local function withRetry(what: string, fn: () -> any): (boolean, any)
	local lastErr: any = nil
	for attempt = 1, #RETRY_BACKOFF do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		local msg = tostring(result)
		-- Studio without API access (403), or the service is off: no point retrying.
		if string.find(msg, "403") or string.find(msg, "not enabled") or string.find(msg, "API Services") then
			unavailable(msg)
			return false, result
		end
		Log.event("Profile", "%s failed (try %d/%d): %s", what, attempt, #RETRY_BACKOFF, msg)
		task.wait(RETRY_BACKOFF[attempt])
	end
	return false, lastErr
end

local function getStore(): DataStore?
	if not Profiles.available then
		return nil
	end
	if store then
		return store
	end
	local ok, s = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = s
	else
		unavailable(s)
	end
	return store
end

-- The session lock: a small record per player naming the server that holds the profile, so a second
-- server (or a stale one) never grants the same payout twice. Advisory in the prototype: a foreign lock is
-- logged and taken over.
local function takeLock(player: Player)
	local s = getStore()
	if not s then
		return
	end
	withRetry("lock " .. player.Name, function()
		return s:UpdateAsync(lockKey(player), function(old: any)
			if typeof(old) == "table" and old.jobId ~= game.JobId and os.time() - (tonumber(old.at) or 0) < 120 then
				Log.event(
					"Profile",
					"%s's profile was locked by another server (%s); taking over",
					player.Name,
					tostring(old.jobId)
				)
			end
			return { jobId = game.JobId, at = os.time() }
		end)
	end)
end

local function releaseLock(player: Player)
	local s = getStore()
	if not s then
		return
	end
	pcall(function()
		s:UpdateAsync(lockKey(player), function(old: any)
			if typeof(old) == "table" and old.jobId ~= game.JobId then
				return nil -- someone else holds it now; leave it alone
			end
			return { jobId = "", at = 0 }
		end)
	end)
end

local function load(player: Player): Profile
	local s = getStore()
	if not s then
		return Profiles.fresh()
	end
	local ok, raw = withRetry("load " .. player.Name, function()
		return s:GetAsync(Profiles.key(player))
	end)
	if not ok then
		Log.event("Profile", "%s: load failed, starting from a fresh in-memory profile this session", player.Name)
		return Profiles.fresh()
	end
	takeLock(player)
	local p = migrate(raw)
	Log.event(
		"Profile",
		"%s loaded: LV %d (%d XP), %d gold, %d weapons, class %s, mask %s, top wave %d%s",
		player.Name,
		p.level,
		p.xp,
		p.gold,
		(function()
			local n = 0
			for _ in p.weapons do
				n += 1
			end
			return n
		end)(),
		p.classes.equipped,
		p.masks.equipped,
		Profiles.bestTopWave(p),
		if raw == nil then " (new)" else ""
	)
	return p
end

-- Write the session cache to the store. The transform writes the whole profile (the cache is the truth
-- for a session); pendingPayout is cleared on a successful write since gold already holds the payout.
function Profiles.save(player: Player, reason: string): boolean
	local e = entries[player]
	if not e then
		return false
	end
	e.dirty = false
	e.saveAt = 0
	local s = getStore()
	if not s then
		return false
	end
	if e.saving then
		e.dirty = true -- another write is in flight; the autosave picks this up
		return false
	end
	e.saving = true
	local snapshot = HttpService:JSONEncode(e.profile)
	local ok = withRetry("save " .. player.Name, function()
		return s:UpdateAsync(Profiles.key(player), function()
			local data = HttpService:JSONDecode(snapshot)
			data.pendingPayout = 0
			return data
		end)
	end)
	e.saving = false
	if ok then
		e.lastSave = os.clock()
		e.profile.pendingPayout = 0
		Log.event("Profile", "%s saved (%s)", player.Name, reason)
	else
		e.dirty = true
		Log.event("Profile", "%s: save failed (%s), %d gold pending", player.Name, reason, e.profile.pendingPayout)
	end
	return ok
end

function Profiles.get(player: Player): Profile?
	local e = entries[player]
	return if e then e.profile else nil
end

-- Yields until the profile is loaded (join) or the player is gone.
function Profiles.waitFor(player: Player): Profile?
	while player.Parent do
		local p = Profiles.get(player)
		if p then
			return p
		end
		task.wait(0.1)
	end
	return nil
end

-- A purchase / equip changed the profile: write within ProfileSaveDebounceSec.
function Profiles.markDirty(player: Player)
	local e = entries[player]
	if not e then
		return
	end
	e.dirty = true
	if e.saveAt == 0 then
		e.saveAt = os.clock() + Config.ProfileSaveDebounceSec
	end
end

-- Gold payout at the summary: lands in the cache at once, then a write. A failed write leaves it in
-- pendingPayout and the hub loop retries until it lands.
function Profiles.grantPayout(player: Player, amount: number, reason: string)
	local e = entries[player]
	if not e or amount <= 0 then
		return
	end
	e.profile.gold += amount
	e.profile.stats.goldEarned += amount
	e.profile.pendingPayout += amount
	task.spawn(Profiles.save, player, reason)
end

function Profiles.addGold(player: Player, amount: number, reason: string)
	local e = entries[player]
	if not e then
		return
	end
	e.profile.gold = math.max(0, e.profile.gold + amount)
	Profiles.markDirty(player)
	Log.event(
		"Profile",
		"%s %s%d gold (%s), now %d",
		player.Name,
		if amount >= 0 then "+" else "",
		amount,
		reason,
		e.profile.gold
	)
end

-- Charge Gold. Returns false (and touches nothing) when short.
function Profiles.tryCharge(player: Player, amount: number): boolean
	local e = entries[player]
	if not e or e.profile.gold < amount then
		return false
	end
	e.profile.gold -= amount
	Profiles.markDirty(player)
	return true
end

-- Wipe and reload: the store entry is replaced by a fresh profile.
function Profiles.reset(player: Player)
	local e = entries[player]
	if not e then
		return
	end
	e.profile = Profiles.fresh()
	e.dirty = true
	Profiles.save(player, "reset")
	Profiles.Loaded:Fire(player, e.profile)
	Log.event("Profile", "%s reset to a fresh profile", player.Name)
end

function Profiles.unlockAll(player: Player)
	local e = entries[player]
	if not e then
		return
	end
	local p = e.profile
	for _, w in Weapons.List do
		if not p.weapons[w.id] then
			p.weapons[w.id] = { level = 0 }
		end
	end
	for _, c in Classes.List do
		p.classes.owned[c.id] = true
	end
	for _, m in Masks.List do
		p.masks.owned[m.id] = true
	end
	for _, e in Emotes.List do
		p.emotes.owned[e.id] = true
	end
	Profiles.markDirty(player)
	Log.event("Profile", "%s unlocked everything", player.Name)
end

local function onPlayer(player: Player)
	local profile = load(player)
	if not player.Parent then
		return
	end
	entries[player] = { profile = profile, dirty = false, saveAt = 0, saving = false, lastSave = os.clock() }
	Profiles.Loaded:Fire(player, profile)
end

function Profiles.init()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayer, player)
	end)
	for _, p in Players:GetPlayers() do
		task.spawn(onPlayer, p)
	end
	Players.PlayerRemoving:Connect(function(player)
		local e = entries[player]
		if not e then
			return
		end
		Profiles.save(player, "leave")
		releaseLock(player)
		entries[player] = nil
	end)
	game:BindToClose(function()
		if RunService:IsStudio() and not Profiles.available then
			return
		end
		for player, e in entries do
			if e.dirty or e.profile.pendingPayout > 0 then
				Profiles.save(player, "shutdown")
			end
			releaseLock(player)
		end
	end)

	-- Debounced writes, the pending-payout retry and the autosave.
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			for player, e in entries do
				if e.saving then
					continue
				end
				if e.saveAt > 0 and now >= e.saveAt then
					task.spawn(Profiles.save, player, "purchase / equip")
				elseif e.profile.pendingPayout > 0 and now - e.lastSave >= 5 then
					task.spawn(Profiles.save, player, "payout retry")
				elseif
					(e.dirty or now - e.lastSave >= Config.ProfileAutosaveSec)
					and now - e.lastSave >= Config.ProfileAutosaveSec
				then
					task.spawn(Profiles.save, player, "autosave")
				end
			end
		end
	end)
end

return Profiles
