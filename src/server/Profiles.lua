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
local Log = require(script.Parent.Log)

export type WeaponEntry = { level: number, wrap: string? }
export type Profile = {
	gold: number,
	weapons: { [string]: WeaponEntry }, -- presence = owned
	starterWeaponId: string,
	classes: { owned: { [string]: boolean }, equipped: string },
	abilities: { [string]: number }, -- ability id -> level
	masks: { owned: { [string]: boolean }, equipped: string },
	emotes: { owned: { [string]: boolean }, squad: string, mvp: string }, -- line-up pose and MVP flex
	wraps: { owned: { [string]: boolean } },
	topWave: { [string]: number }, -- "TheBank:Normal" -> wave
	topBanked: { [string]: number }, -- "TheBank:Normal" -> best TOTAL BANKED in one run
	stats: { kills: number, matchesPlayed: number, goldEarned: number, bagsCollected: number, goldBanked: number },
	pendingPayout: number, -- Gold granted this session that has not reached the store yet
	version: number,
}

type Entry = {
	profile: Profile,
	dirty: boolean,
	saveAt: number, -- os.clock when the debounced save fires, 0 = none pending
	saving: boolean,
	lastSave: number,
}

local STORE_NAME = "GHS_Profiles_v1"
local VERSION = 1
local RETRY_BACKOFF = { 1, 2, 4 }

local Profiles = {}
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
		topWave = { ["TheBank:Normal"] = 0 },
		topBanked = { ["TheBank:Normal"] = 0 },
		stats = { kills = 0, matchesPlayed = 0, goldEarned = 0, bagsCollected = 0, goldBanked = 0 },
		pendingPayout = 0,
		version = VERSION,
	}
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
		"%s loaded: %d gold, %d weapons, class %s, mask %s, top wave %d%s",
		player.Name,
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
		p.topWave["TheBank:Normal"] or 0,
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
