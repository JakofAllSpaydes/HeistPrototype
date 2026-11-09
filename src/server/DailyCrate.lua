--!strict
-- Brief 10: the daily crate (server). One podium in the hub (Hub.lua builds it from the DailyCrate node), one crate a
-- fake day, unlocked by playing: any run that reaches a summary sets dailyCrate.unlockedDay = today for each member
-- (RunEnd calls DailyCrate.unlock). States per player, on the player as attributes so each client draws its own
-- podium: DailyCrate = locked | ready | claimed (off when DailyCrateEnabled is false), DailyCrateTier = the level
-- band's tier, DailyCrateFirst = the first-ever open is still to come.
--   tier    from the level only (DailyCrateTierByLevel); its rarity weights are DailyCrateTierOdds[tier]
--   pool    Catalog.dailyPool (Direct guns and masks); the first daily crate a profile ever opens rolls from the guns
--           only (DailyCrateFirstIsGun), every open after that (a reroll on the first day too) from the mix
--   open    Remotes.DailyCrateOpen: the server rolls and grants (normal dupe handling) before the client's crate scene
--   reroll  ROLL AGAIN at a claimed podium through the fake-Robux purchase path (product dailycrate_reroll)
-- A crate not opened by the fake-day boundary is gone (no stacking). Logs: [GHS Daily] <name> unlocked day N /
-- opened <tier> level N -> <item> <rarity> / reroll paid / expired unopened.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Clock = require(Shared.Clock)
local Remotes = require(Shared.Remotes)
local Catalog = require(Shared.Catalog)
local Crates = require(Shared.Crates)
local Rarity = require(Shared.Rarity)
local Profiles = require(script.Parent.Profiles)
local PlayerState = require(script.Parent.PlayerState)
local Runs = require(script.Parent.Runs)
local Grants = require(script.Parent.Grants)
local Purchases = require(script.Parent.Purchases)
local CrateOpen = require(script.Parent.CrateOpen)
local Hub = require(script.Parent.Hub)
local Log = require(script.Parent.Log)

local DailyCrate = {}

-- Debug: this player's crate rolls as this tier (Force daily tier), nil = by level.
DailyCrate.forcedTier = {} :: { [Player]: string }

local lastDay: { [Player]: number } = {}

local function today(profile: Profiles.Profile): number
	return Clock.day(Clock.fake(os.time(), profile))
end

function DailyCrate.tierFor(level: number): string
	local tier = "basic"
	for _, band in Config.DailyCrateTierByLevel :: { { any } } do
		if level >= (tonumber(band[1]) or 1) then
			tier = tostring(band[2])
		end
	end
	return tier
end

function DailyCrate.tierOf(player: Player, profile: Profiles.Profile): string
	return DailyCrate.forcedTier[player] or DailyCrate.tierFor(profile.level)
end

export type State = "off" | "locked" | "ready" | "claimed"

function DailyCrate.state(profile: Profiles.Profile): State
	if not Config.DailyCrateEnabled then
		return "off"
	end
	local d = today(profile)
	local dc = profile.dailyCrate
	if dc.unlockedDay ~= d then
		return "locked"
	elseif dc.claimedDay == d then
		return "claimed"
	end
	return "ready"
end

-- Publishes the state on the player (each client renders its own podium from these).
function DailyCrate.refresh(player: Player)
	local profile = Profiles.get(player)
	if not profile then
		return
	end
	player:SetAttribute("DailyCrate", DailyCrate.state(profile))
	player:SetAttribute("DailyCrateTier", DailyCrate.tierOf(player, profile))
	player:SetAttribute("DailyCrateFirst", Config.DailyCrateFirstIsGun and not profile.dailyCrate.everOpened)
end

-- A run reached its summary: the crate is unlocked for this fake day (every member, any map, any wave).
function DailyCrate.unlock(player: Player)
	local profile = Profiles.get(player)
	if not profile or not Config.DailyCrateEnabled then
		return
	end
	local d = today(profile)
	if profile.dailyCrate.unlockedDay ~= d then
		profile.dailyCrate.unlockedDay = d
		Profiles.markDirty(player)
		PlayerState.get(player).dirty = true
		Log.event("Daily", "%s unlocked day %d", player.Name, d)
		-- Round 27c: the summary's side card (tap it: to the lobby, the podium opens on arrival).
		Remotes.Juice:FireClient(player, "DailyUnlocked", { tier = DailyCrate.tierOf(player, profile) })
	end
	DailyCrate.refresh(player)
end

------------------------------------------------------------------ The roll
local function pickRarity(weights: { number }): number
	local total = 0
	for r = 1, 5 do
		total += weights[r]
	end
	if total <= 0 then
		return 1
	end
	local x = math.random() * total
	for r = 1, 5 do
		x -= weights[r]
		if x < 0 then
			return r
		end
	end
	return 5
end

-- One item from the tier's weights over the pool (guns only when gunOnly); rarities the pool lacks weigh nothing.
-- `floor`: the lowest rarity (Round 27d: the streak's RARE+ / EPIC+ days roll the daily crate above it).
local function rollItem(player: Player, tierId: string, gunOnly: boolean, floor: number?): Catalog.Item?
	local tier = (Config.DailyCrateTierOdds :: any)[tierId] or (Config.DailyCrateTierOdds :: any).basic
	local kind = if gunOnly then "weapon" else nil
	local weights = {}
	for r = 1, 5 do
		weights[r] = if #Catalog.dailyItems(kind, r) > 0 and r >= (floor or 1) then (tier.weights[r] or 0) else 0
	end
	local rarity = pickRarity(weights)
	local forced = CrateOpen.forced[player] -- the debug panel's Force rarity lands here too
	if forced and #Catalog.dailyItems(kind, forced) > 0 then
		CrateOpen.forced[player] = nil
		rarity = forced
	end
	local items = Catalog.dailyItems(kind, rarity)
	if #items == 0 then
		items = Catalog.dailyItems(kind, nil)
	end
	if #items == 0 then
		return nil
	end
	return items[math.random(1, #items)]
end

-- Rolls, grants and logs one open. Returns the crate scene's rows.
local function openOne(
	player: Player,
	profile: Profiles.Profile,
	gunOnly: boolean,
	source: string,
	tierOverride: string?,
	floor: number?
): any
	local tierId = tierOverride or DailyCrate.tierOf(player, profile)
	local item = rollItem(player, tierId, gunOnly, floor)
	if not item then
		return nil
	end
	local ups = {}
	local res = Grants.apply(
		player,
		{ kind = item.kind, id = item.id },
		{ source = "daily crate " .. tierId, deferMastery = ups }
	)
	Log.event(
		"Daily",
		"%s opened %s level %d -> %s %s%s%s",
		player.Name,
		tierId,
		profile.level,
		item.id,
		Rarity.name(item.rarity),
		if res.dupe then " (dupe)" else "",
		if source ~= "" then " (" .. source .. ")" else ""
	)
	return {
		crateId = Crates.dailyId(tierId),
		results = {
			{
				kind = item.kind,
				id = item.id,
				rarity = item.rarity,
				name = res.name,
				new = res.new,
				dupe = res.dupe,
				gold = res.gold,
				mastery = res.mastery,
				pity = false,
				masteryUps = ups,
			},
		},
	}
end

-- Round 27d: the login streak's crates are daily crates at the week's tier (Config.StreakCrateTierByWeek), `count`
-- rolls, above `floor` on the big days; the first-gun rule applies to a profile's first ever. The podium's own state
-- is untouched. Returns { crateId, results } for the crate scene.
function DailyCrate.rollStreak(player: Player, tierId: string, count: number, floor: number?, source: string): any
	local profile = Profiles.get(player)
	local out = { crateId = Crates.dailyId(tierId), results = {} }
	if not profile then
		return out
	end
	for _ = 1, math.max(1, count) do
		local gunOnly = Config.DailyCrateFirstIsGun and not profile.dailyCrate.everOpened
		local data = openOne(player, profile, gunOnly, source, tierId, floor)
		if data then
			profile.dailyCrate.everOpened = true
			table.insert(out.results, data.results[1])
		end
	end
	Profiles.markDirty(player)
	PlayerState.get(player).dirty = true
	DailyCrate.refresh(player)
	return out
end

function DailyCrate.open(player: Player): any
	local profile = Profiles.get(player)
	if not profile then
		return { ok = false, reason = "PROFILE LOADING" }
	end
	if Runs.inRunCycle(player) then
		return { ok = false, reason = "NOT IN A RUN" }
	end
	local state = DailyCrate.state(profile)
	if state ~= "ready" then
		return {
			ok = false,
			reason = if state == "locked"
				then "PLAY A MATCH TO UNLOCK"
				elseif state == "claimed" then "BACK TOMORROW"
				else "DAILY CRATE IS OFF",
		}
	end
	local gunOnly = Config.DailyCrateFirstIsGun and not profile.dailyCrate.everOpened
	local data = openOne(player, profile, gunOnly, if gunOnly then "first: gun" else "")
	if not data then
		return { ok = false, reason = "NOTHING TO ROLL" }
	end
	profile.dailyCrate.claimedDay = today(profile)
	profile.dailyCrate.everOpened = true
	Profiles.markDirty(player)
	PlayerState.get(player).dirty = true
	DailyCrate.refresh(player)
	data.ok = true
	return data
end

-- ROLL AGAIN: the fake-Robux path debits and logs it; the same tier and the mixed pool; the podium stays claimed.
local function rerollsLeft(profile: Profiles.Profile): number
	if Config.DailyCrateRerollMaxPerDay <= 0 then
		return math.huge
	end
	local used = if profile.dailyCrate.rerollDay == today(profile) then profile.dailyCrate.rerollsToday else 0
	return math.max(0, Config.DailyCrateRerollMaxPerDay - used)
end

-- Round 27c: BUY 1 at any podium state (the sheet offers it while locked): one open from your tier, the first-gun
-- rule included; the day's free crate is untouched.
Purchases.register("dailycrate_buy", {
	check = function(player, _profile)
		if not Config.DailyCrateEnabled then
			return "The daily crate is off"
		end
		if Runs.inRunCycle(player) then
			return "Not during a run"
		end
		return nil
	end,
	grant = function(player, profile)
		local gunOnly = Config.DailyCrateFirstIsGun and not profile.dailyCrate.everOpened
		Log.event("Daily", "%s buy paid", player.Name)
		local data = openOne(player, profile, gunOnly, if gunOnly then "bought, first: gun" else "bought")
		if not data then
			return nil, "Nothing to roll"
		end
		profile.dailyCrate.everOpened = true
		DailyCrate.refresh(player)
		return data, nil
	end,
})

Purchases.register("dailycrate_reroll", {
	check = function(player, profile)
		if not Config.DailyCrateRerollEnabled then
			return "Roll again is off"
		end
		if DailyCrate.state(profile) ~= "claimed" then
			return "Open today's crate first"
		end
		if Runs.inRunCycle(player) then
			return "Not during a run"
		end
		if rerollsLeft(profile) <= 0 then
			return "No more rolls today"
		end
		return nil
	end,
	grant = function(player, profile)
		local d = today(profile)
		if profile.dailyCrate.rerollDay ~= d then
			profile.dailyCrate.rerollDay = d
			profile.dailyCrate.rerollsToday = 0
		end
		profile.dailyCrate.rerollsToday += 1
		Log.event("Daily", "%s reroll paid (%d today)", player.Name, profile.dailyCrate.rerollsToday)
		local data = openOne(player, profile, false, "reroll")
		if not data then
			return nil, "Nothing to roll"
		end
		DailyCrate.refresh(player)
		return data, nil
	end,
})

-- E at the podium: the state decides (the client's prompt already reads the same words).
local function onPrompt(player: Player)
	local profile = Profiles.get(player)
	if not profile then
		return
	end
	-- Round 27c: every state opens the podium sheet (contents, odds, what it takes, BUY 1 / ROLL AGAIN).
	local state = DailyCrate.state(profile)
	if state ~= "off" then
		Remotes.Juice:FireClient(player, "DailySheet", { state = state })
	end
end

------------------------------------------------------------------ Debug
function DailyCrate.debugUnlock(player: Player)
	DailyCrate.unlock(player)
end

-- Locked today again, never opened (the first-gun rule is live again).
function DailyCrate.debugReset(player: Player)
	local profile = Profiles.get(player)
	if not profile then
		return
	end
	profile.dailyCrate.unlockedDay = 0
	profile.dailyCrate.claimedDay = 0
	profile.dailyCrate.everOpened = false
	profile.dailyCrate.rerollsToday = 0
	Profiles.markDirty(player)
	PlayerState.get(player).dirty = true
	DailyCrate.refresh(player)
	Log.event("Daily", "%s daily crate reset (debug)", player.Name)
end

-- "auto" (or an unknown tier) goes back to the level band.
function DailyCrate.debugForceTier(player: Player, tier: string)
	if (Config.DailyCrateTierOdds :: any)[tier] then
		DailyCrate.forcedTier[player] = tier
	else
		DailyCrate.forcedTier[player] = nil
	end
	DailyCrate.refresh(player)
end

function DailyCrate.printStats(player: Player)
	local profile = Profiles.get(player)
	if not profile then
		return
	end
	local dc = profile.dailyCrate
	print(
		string.format(
			"[GHS Daily] %s: %s, tier %s (level %d%s), unlocked fake day %d, claimed %d (today %d), ever opened %s, rerolls today %d, pool %d items",
			player.Name,
			DailyCrate.state(profile),
			DailyCrate.tierOf(player, profile),
			profile.level,
			if DailyCrate.forcedTier[player] then ", forced" else "",
			dc.unlockedDay,
			dc.claimedDay,
			today(profile),
			tostring(dc.everOpened),
			if dc.rerollDay == today(profile) then dc.rerollsToday else 0,
			#Catalog.dailyPool()
		)
	)
end

function DailyCrate.init()
	Hub.onDailyPrompt = onPrompt
	Remotes.DailyCrateOpen.OnServerInvoke = function(player: Player): any
		return DailyCrate.open(player)
	end
	Profiles.Loaded:Connect(function(player: Player)
		local profile = Profiles.get(player)
		if profile then
			lastDay[player] = today(profile)
		end
		DailyCrate.refresh(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastDay[player] = nil
		DailyCrate.forcedTier[player] = nil
	end)
	-- The fake-day boundary (and level-ups between runs): republish, and log a crate that went unopened.
	task.spawn(function()
		while true do
			task.wait(2)
			for _, p in Players:GetPlayers() do
				local profile = Profiles.get(p)
				if profile then
					local d = today(profile)
					local prev = lastDay[p]
					if prev and prev ~= d then
						local dc = profile.dailyCrate
						if dc.unlockedDay == prev and dc.claimedDay ~= prev and Config.DailyCrateEnabled then
							Log.event("Daily", "%s expired unopened (fake day %d)", p.Name, prev)
						end
					end
					lastDay[p] = d
					DailyCrate.refresh(p)
				end
			end
		end
	end)
end

return DailyCrate
