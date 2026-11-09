--!strict
-- Brief 10: the login streak (server). A 28-day track (StreakTrack.lua, Config.StreakRewards) on the player's fake
-- clock: the first hub entry of a fake day sends the modal (Juice "StreakOpen") and the day is claimed from it.
--   lastClaimDay == today      nothing to claim (Round 27b: the modal still opens once a session, StreakOpenEverySession,
--                              on today's ticked card with the next reward's countdown and GET IT NOW)
--   lastClaimDay == today - 1  the next day (day + 1, 28 wraps to StreakLoopFrom)
--   older                      lost: RESTORE (fake R$, product streak_restore; VIP: free VipStreakRestores per
--                              VipStreakRestoreDays) keeps the day and claims it, START OVER claims day 1
--   never                      day 1
-- Round 27b: streak.count is the days in a row (the calendar's number). GET IT NOW (product streak_skip,
-- StreakSkipsPerDay) claims the next day's reward today: the track and the count step on, today stays claimed.
-- Crate rewards roll and open now (CrateOpen with the reward's rarity floor) and go back to the client for the crate
-- scene; nothing is banked. MARLOW's daily announce waits behind an unclaimed modal (Jobs.hold) and plays once the day
-- is claimed. Logs: [GHS Streak] <name> day N claim / lost at N / restore paid|vip / reset / skip paid.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Clock = require(Shared.Clock)
local Remotes = require(Shared.Remotes)
local StreakTrack = require(Shared.StreakTrack)
local Profiles = require(script.Parent.Profiles)
local PlayerState = require(script.Parent.PlayerState)
local Runs = require(script.Parent.Runs)
local Grants = require(script.Parent.Grants)
local CrateOpen = require(script.Parent.CrateOpen)
local DailyCrate = require(script.Parent.DailyCrate)
local Purchases = require(script.Parent.Purchases)
local Jobs = require(script.Parent.Jobs)
local Log = require(script.Parent.Log)

local Streak = {}

local offered: { [Player]: number } = {} -- the fake day the modal was last sent for
local lostLogged: { [Player]: number } = {}

local function today(profile: Profiles.Profile): number
	return Clock.day(Clock.fake(os.time(), profile))
end
Streak.today = today

-- Free VIP restores left in the current window.
function Streak.vipLeft(profile: Profiles.Profile, day: number): number
	if not profile.vip.active or Config.VipStreakRestores <= 0 then
		return 0
	end
	local s = profile.streak
	if s.vipRestoreDay <= 0 or day - s.vipRestoreDay >= Config.VipStreakRestoreDays then
		return Config.VipStreakRestores
	end
	return math.max(0, Config.VipStreakRestores - s.vipRestoresUsed)
end

-- Paid skips left today (math.huge when unlimited).
local function skipsLeft(profile: Profiles.Profile, day: number): number
	if Config.StreakSkipsPerDay <= 0 then
		return math.huge
	end
	local used = if profile.streak.skipDay == day then profile.streak.skipsToday else 0
	return math.max(0, Config.StreakSkipsPerDay - used)
end

export type View = {
	state: string, -- claim | lost | claimed (nothing to claim today)
	day: number, -- claim / lost: the day a claim (or a restore) lands on; claimed: today's claimed day
	count: number, -- the calendar: days in a row once this claim lands (lost: the streak that was lost)
	nextDay: number, -- the track day after `day`
	vip: boolean,
	vipLeft: number,
	price: number, -- RESTORE
	skipPrice: number,
	canSkip: boolean,
}

-- What the modal shows today; nil when there is nothing to claim, unless `withClaimed` (the session's first open).
function Streak.view(player: Player, withClaimed: boolean?): View?
	local profile = Profiles.get(player)
	if not profile or not Config.StreakEnabled then
		return nil
	end
	local d = today(profile)
	local s = profile.streak
	local st, day = StreakTrack.state(s, d)
	local state: string = st
	if state == "none" and not withClaimed then
		return nil
	end
	local count = if state == "claim"
		then (if s.lastClaimDay == d - 1 then s.count + 1 else 1)
		elseif state == "lost" then math.max(1, s.count)
		else math.max(1, s.count)
	return {
		state = if state == "none" then "claimed" else state,
		day = if state == "none" then math.max(1, s.day) else day,
		count = count,
		nextDay = StreakTrack.nextDay(if state == "none" then s.day else day),
		vip = profile.vip.active,
		vipLeft = Streak.vipLeft(profile, d),
		price = Config.StreakRestorePrice,
		skipPrice = Config.StreakSkipPrice,
		canSkip = state == "none" and skipsLeft(profile, d) > 0,
	}
end

function Streak.pending(player: Player): boolean
	return Streak.view(player) ~= nil
end

-- Sends the modal once per fake day while there is something to claim (force: again, for the debug buttons;
-- session: also with nothing to claim, the session's first open). Hub only.
function Streak.offer(player: Player, force: boolean?, session: boolean?)
	if not player.Parent or Runs.inRunCycle(player) then
		return
	end
	local profile = Profiles.get(player)
	local view = Streak.view(player, session and Config.StreakOpenEverySession)
	if not profile or not view then
		return
	end
	local d = today(profile)
	if offered[player] == d and not force and not session then
		return
	end
	if view.state ~= "claimed" then
		offered[player] = d
	end
	if view.state == "lost" and lostLogged[player] ~= d then
		lostLogged[player] = d
		Log.event("Streak", "%s lost at %d", player.Name, view.day)
	end
	Remotes.Juice:FireClient(player, "StreakOpen", view)
end

-- Grants one day. Crate rewards open now: their rolls go back for the crate scene. `count` is the new streak count.
local function grantDay(player: Player, profile: Profiles.Profile, day: number, count: number, how: string): any
	local source = "streak day " .. day
	local results = {}
	local crates = {}
	for _, r in StreakTrack.rewards(day) do
		if r.kind == "crate" and r.id == "daily" then
			-- Round 27d: a daily crate at this week's tier.
			table.insert(
				crates,
				DailyCrate.rollStreak(player, StreakTrack.crateTier(day), math.max(1, r.amount or 1), r.floor, source)
			)
		elseif r.kind == "crate" and r.id then
			local rolls = CrateOpen.open(player, r.id, math.max(1, r.amount or 1), source, r.floor)
			table.insert(crates, { crateId = r.id, results = rolls })
		else
			table.insert(
				results,
				Grants.apply(player, { kind = r.kind, id = r.id, amount = r.amount, sec = r.sec }, { source = source })
			)
		end
	end
	profile.streak.day = day
	profile.streak.lastClaimDay = today(profile)
	profile.streak.count = count
	Profiles.markDirty(player)
	PlayerState.get(player).dirty = true
	Log.event(
		"Streak",
		"%s day %d claim%s, %d in a row",
		player.Name,
		day,
		if how ~= "" then " (" .. how .. ")" else "",
		count
	)
	-- MARLOW's card was waiting behind the modal (and behind the crate scene, if the day opened one).
	task.delay(if #crates > 0 then 8 else 1.5, function()
		if player.Parent and not Runs.inRunCycle(player) then
			Jobs.announce(player)
		end
	end)
	return { ok = true, day = day, results = results, crates = crates }
end

-- action: "claim" (today's day) | "over" (START OVER on a lost streak) | "vip" (VIP's free RESTORE).
function Streak.claim(player: Player, action: string): any
	local profile = Profiles.get(player)
	if not profile then
		return { ok = false, reason = "PROFILE LOADING" }
	end
	if Runs.inRun(player) then
		return { ok = false, reason = "NOT IN A RUN" }
	end
	local d = today(profile)
	local s = profile.streak
	local state, day = StreakTrack.state(s, d)
	if state == "none" then
		return { ok = false, reason = "ALREADY CLAIMED" }
	end
	if action == "claim" then
		if state ~= "claim" then
			return { ok = false, reason = "STREAK LOST" }
		end
		return grantDay(player, profile, day, if s.lastClaimDay == d - 1 then s.count + 1 else 1, "")
	elseif action == "over" then
		if state ~= "lost" then
			return { ok = false, reason = "NOTHING TO START OVER" }
		end
		-- Round 27g: START OVER only resets the streak; day 1 then waits to be claimed like any first day (the modal
		-- rolls its row back and shows CLAIM), rather than paying out a day you never saw claimed.
		local st = profile.streak
		st.day, st.count, st.lastClaimDay = 0, 0, 0
		Profiles.markDirty(player)
		PlayerState.get(player).dirty = true
		Log.event("Streak", "%s reset", player.Name)
		return { ok = true, reset = true }
	elseif action == "vip" then
		if state ~= "lost" then
			return { ok = false, reason = "NOTHING TO RESTORE" }
		end
		if Streak.vipLeft(profile, d) <= 0 then
			return { ok = false, reason = "NO FREE RESTORES LEFT" }
		end
		if s.vipRestoreDay <= 0 or d - s.vipRestoreDay >= Config.VipStreakRestoreDays then
			s.vipRestoreDay = d
			s.vipRestoresUsed = 0
		end
		s.vipRestoresUsed += 1
		Log.event("Streak", "%s restore vip", player.Name)
		return grantDay(player, profile, day, s.count + 1, "restore")
	end
	return { ok = false, reason = "UNKNOWN ACTION" }
end

-- RESTORE for fake Robux: the purchase path debits and logs it, the grant claims the kept day.
Purchases.register("streak_restore", {
	check = function(player, profile)
		local state = StreakTrack.state(profile.streak, today(profile))
		if state ~= "lost" or not Config.StreakEnabled then
			return "Nothing to restore"
		end
		if Runs.inRun(player) then
			return "Not during a run"
		end
		return nil
	end,
	grant = function(player, profile)
		local _, day = StreakTrack.state(profile.streak, today(profile))
		Log.event("Streak", "%s restore paid", player.Name)
		return grantDay(player, profile, day, profile.streak.count + 1, "restore")
	end,
})

-- Round 27b: GET IT NOW claims the next day's reward today (today's day already claimed).
Purchases.register("streak_skip", {
	check = function(player, profile)
		local d = today(profile)
		if not Config.StreakEnabled or StreakTrack.state(profile.streak, d) ~= "none" then
			return "Claim today's reward first"
		end
		if skipsLeft(profile, d) <= 0 then
			return "Come back tomorrow"
		end
		if Runs.inRun(player) then
			return "Not during a run"
		end
		return nil
	end,
	grant = function(player, profile)
		local d = today(profile)
		local s = profile.streak
		if s.skipDay ~= d then
			s.skipDay = d
			s.skipsToday = 0
		end
		s.skipsToday += 1
		local day = StreakTrack.nextDay(s.day)
		Log.event("Streak", "%s skip paid day %d", player.Name, day)
		return grantDay(player, profile, day, s.count + 1, "skip"), nil
	end,
})

------------------------------------------------------------------ Debug
-- The next claim lands on day n (the modal opens on it now).
function Streak.debugSetDay(player: Player, n: number)
	local profile = Profiles.get(player)
	if not profile then
		return
	end
	n = math.clamp(math.floor(n), 1, StreakTrack.LENGTH)
	local d = today(profile)
	local s = profile.streak
	if n == 1 then
		s.day, s.lastClaimDay, s.count = 0, 0, 0
	else
		s.day, s.lastClaimDay, s.count = n - 1, d - 1, n - 1
	end
	s.skipsToday = 0
	Profiles.markDirty(player)
	PlayerState.get(player).dirty = true
	Log.event("Streak", "%s set to day %d (debug)", player.Name, n)
	Streak.offer(player, true)
end

-- Two days since the last claim: the modal opens on STREAK LOST.
function Streak.debugBreak(player: Player)
	local profile = Profiles.get(player)
	if not profile then
		return
	end
	local s = profile.streak
	if s.day < 1 then
		s.day = 11
		s.count = 11
	end
	s.lastClaimDay = today(profile) - 2
	Profiles.markDirty(player)
	PlayerState.get(player).dirty = true
	Log.event("Streak", "%s streak broken at day %d (debug)", player.Name, s.day)
	Streak.offer(player, true)
end

function Streak.printStats(player: Player)
	local profile = Profiles.get(player)
	if not profile then
		return
	end
	local s = profile.streak
	local d = today(profile)
	local state, day = StreakTrack.state(s, d)
	print(
		string.format(
			"[GHS Streak] %s: day %d, %d in a row, last claim fake day %d (today %d) -> %s day %d, VIP restores left %d, skips left %s",
			player.Name,
			s.day,
			s.count,
			s.lastClaimDay,
			d,
			state,
			day,
			Streak.vipLeft(profile, d),
			tostring(skipsLeft(profile, d))
		)
	)
end

function Streak.init()
	Jobs.hold = Streak.pending
	Remotes.StreakClaim.OnServerInvoke = function(player: Player, action: any): any
		if action == "view" then
			return Streak.view(player, true)
		end
		return Streak.claim(player, tostring(action))
	end
	Profiles.Loaded:Connect(function(player: Player)
		-- On join and on a debug profile reset: the session's open (with nothing to claim too).
		task.delay(Config.StreakOpenDelaySec, Streak.offer, player, true, true)
	end)
	Players.PlayerRemoving:Connect(function(player)
		offered[player] = nil
		lostLogged[player] = nil
	end)
	-- A fake day can turn mid-session (the debug +1 day): anyone in the hub gets the new day's modal.
	task.spawn(function()
		while true do
			task.wait(3)
			for _, p in Players:GetPlayers() do
				Streak.offer(p)
			end
		end
	end)
end

return Streak
