--!strict
-- Brief 6: JOBS, the daily quests and the weekly bounty. profile.jobs = { dailyResetDay, weeklyResetWeek,
-- daily = { 3 x { id, progress, claimed } }, bounty = { 1 x ... }, rerollUsed, announcedDay, boardSeenDay }.
-- Three dailies are drawn per fake UTC day from JobPool.Daily with no two of the same kind (a class Job only for a
-- class the player owns), one bounty per fake UTC week (Monday). Progress comes from the run event bus
-- (RunEvents) and persists across runs until the reset; a quarter crossed in a run toasts. CLAIM pays
-- DailyXp / DailyGold / DailyPassXp (the bounty WeeklyXp / WeeklyGold / WeeklyPassXp / WeeklyTokens); one free
-- REROLL per day. On the first hub entry after a reset MARLOW announces the new board.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Clock = require(Shared.Clock)
local JobPool = require(Shared.JobPool)
local Remotes = require(Shared.Remotes)
local Profiles = require(script.Parent.Profiles)
local PlayerState = require(script.Parent.PlayerState)
local World = require(script.Parent.World)
local Grants = require(script.Parent.Grants)
local Shop = require(script.Parent.Shop)
local RunEvents = require(script.Parent.RunEvents)
local Log = require(script.Parent.Log)

local Jobs = {}

type Entry = { id: string, progress: number, claimed: boolean }

-- Per run: entry key -> progress at the run's start (the summary ticks).
local runStart: { [Player]: { [string]: number } } = {}

local function now(profile: Profiles.Profile): number
	return Clock.fake(os.time(), profile)
end

local function draw(
	profile: Profiles.Profile,
	pool: { JobPool.Job },
	count: number,
	exclude: { [string]: boolean }
): { Entry }
	local candidates = {}
	for _, j in pool do
		if j.needsClass and not profile.classes.owned[j.needsClass] then
			continue
		end
		table.insert(candidates, j)
	end
	local out: { Entry } = {}
	local kinds: { [string]: boolean } = table.clone(exclude)
	for _ = 1, 200 do
		if #out >= count or #candidates == 0 then
			break
		end
		local i = math.random(1, #candidates)
		local j = candidates[i]
		table.remove(candidates, i)
		if not kinds[j.kind] then
			kinds[j.kind] = true
			table.insert(out, { id = j.id, progress = 0, claimed = false })
		end
	end
	return out
end

-- The board for the fake day / week (redraws on a reset).
function Jobs.normalize(player: Player): boolean
	local profile = Profiles.get(player)
	if not profile then
		return false
	end
	local j = profile.jobs
	local t = now(profile)
	local day, week = Clock.day(t), Clock.week(t)
	local changed = false
	if j.dailyResetDay ~= day or #j.daily == 0 then
		j.daily = draw(profile, JobPool.Daily, 3, {})
		j.dailyResetDay = day
		j.rerollUsed = 0
		changed = true
		local names = {}
		for _, e in j.daily do
			table.insert(names, e.id)
		end
		Log.event("Jobs", "%s: new dailies for day %d: %s", player.Name, day, table.concat(names, ", "))
	end
	if j.weeklyResetWeek ~= week or #j.bounty == 0 then
		j.bounty = draw(profile, JobPool.Bounty, 1, {})
		j.weeklyResetWeek = week
		changed = true
		Log.event(
			"Jobs",
			"%s: new bounty for week %d: %s",
			player.Name,
			week,
			if j.bounty[1] then j.bounty[1].id else "none"
		)
	end
	if changed then
		Profiles.markDirty(player)
		PlayerState.get(player).dirty = true
	end
	return changed
end

local function entries(profile: Profiles.Profile): { { key: string, entry: Entry, weekly: boolean } }
	local out = {}
	for i, e in profile.jobs.daily do
		table.insert(out, { key = "d" .. i, entry = e :: any, weekly = false })
	end
	for i, e in profile.jobs.bounty do
		table.insert(out, { key = "b" .. i, entry = e :: any, weekly = true })
	end
	return out
end

-- A run event: every matching Job moves (wave Jobs keep the best wave; the rest add up).
local function onEvent(player: Player, kind: string, amount: number, arg: string?)
	local profile = Profiles.get(player)
	if not profile then
		return
	end
	Jobs.normalize(player)
	for _, it in entries(profile) do
		local e = it.entry
		local def = JobPool.ById[e.id]
		if not def or def.kind ~= kind or e.claimed or e.progress >= def.target then
			continue
		end
		if def.arg and def.arg ~= arg then
			continue
		end
		local before = e.progress
		local start = runStart[player]
		if start and start[it.key] == nil then
			start[it.key] = before
		end
		if kind == "wave" then
			e.progress = math.min(def.target, math.max(e.progress, math.floor(amount)))
		else
			e.progress = math.min(def.target, e.progress + math.floor(amount))
		end
		if e.progress == before then
			continue
		end
		PlayerState.get(player).dirty = true
		-- A quarter crossed (or the finish) toasts in a run.
		local q0 = math.floor(before / def.target * 4)
		local q1 = math.floor(e.progress / def.target * 4)
		if q1 > q0 then
			local done = e.progress >= def.target
			Remotes.Juice:FireClient(player, "JobToast", {
				title = def.title,
				progress = e.progress,
				target = def.target,
				done = done,
				weekly = it.weekly,
			})
			if done then
				Profiles.markDirty(player)
				Log.event("Jobs", "%s finished %s (%s)", player.Name, def.id, if it.weekly then "bounty" else "daily")
			end
		end
	end
end

local function reward(weekly: boolean): { any }
	if weekly then
		return {
			{ kind = "xp", amount = Config.WeeklyXp },
			{ kind = "gold", amount = Config.WeeklyGold },
			{ kind = "passxp", amount = Config.WeeklyPassXp },
			{ kind = "tokens", amount = Config.WeeklyTokens },
		}
	end
	return {
		{ kind = "xp", amount = Config.DailyXp },
		{ kind = "gold", amount = Config.DailyGold },
		{ kind = "passxp", amount = Config.DailyPassXp },
	}
end
Jobs.reward = reward

local function claimKey(player: Player, profile: Profiles.Profile, key: string): { any }?
	for _, it in entries(profile) do
		if it.key == key then
			local e = it.entry
			local def = JobPool.ById[e.id]
			if not def or e.claimed or e.progress < def.target then
				return nil
			end
			e.claimed = true
			local results = Grants.applyAll(player, reward(it.weekly), { source = "job " .. def.id })
			return results
		end
	end
	return nil
end

------------------------------------------------------------------ Shop actions
Shop.register("jobsOpen", function(player, profile)
	Jobs.normalize(player)
	profile.jobs.boardSeenDay = Clock.day(now(profile))
	return { ok = true }
end)

Shop.register("jobClaim", function(player, profile, args)
	Jobs.normalize(player)
	local key = if typeof(args) == "table" then tostring(args.key) else ""
	local results = claimKey(player, profile, key)
	if not results then
		return { ok = false, reason = "Not ready" }
	end
	return { ok = true, data = { results = results } }
end)

Shop.register("jobClaimAll", function(player, profile)
	Jobs.normalize(player)
	local all = {}
	for _, it in entries(profile) do
		local r = claimKey(player, profile, it.key)
		if r then
			for _, x in r do
				table.insert(all, x)
			end
		end
	end
	if #all == 0 then
		return { ok = false, reason = "Nothing to claim" }
	end
	return { ok = true, data = { results = all } }
end)

-- One free REROLL per day on one daily: a new Job of a kind the board does not have.
Shop.register("jobReroll", function(player, profile, args)
	Jobs.normalize(player)
	local j = profile.jobs
	if j.rerollUsed >= Config.JobRerollsPerDay then
		return { ok = false, reason = "Reroll used today" }
	end
	local slot = if typeof(args) == "table" then math.floor(tonumber(args.slot) or 0) else 0
	local e = j.daily[slot]
	if not e or e.claimed then
		return { ok = false, reason = "Cannot reroll that card" }
	end
	local exclude: { [string]: boolean } = {}
	for i, other in j.daily do
		local def = JobPool.ById[other.id]
		if def then
			exclude[def.kind] = true
		end
		local _ = i
	end
	local fresh = draw(profile, JobPool.Daily, 1, exclude)
	if #fresh == 0 then
		return { ok = false, reason = "No other Jobs today" }
	end
	j.daily[slot] = fresh[1]
	j.rerollUsed += 1
	Log.event("Jobs", "%s rerolled %s -> %s", player.Name, e.id, fresh[1].id)
	return { ok = true, data = { slot = slot, id = fresh[1].id } }
end)

------------------------------------------------------------------ Runs and the hub
function Jobs.beginRun(players: { Player })
	for _, p in players do
		Jobs.normalize(p)
		runStart[p] = {}
	end
end

-- The summary ticks: every Job that moved this run, from -> to, done or not.
function Jobs.runSummary(player: Player): { any }
	local profile = Profiles.get(player)
	local start = runStart[player]
	local out = {}
	if not profile or not start then
		return out
	end
	for _, it in entries(profile) do
		local from = start[it.key]
		local def = JobPool.ById[it.entry.id]
		if from ~= nil and def and it.entry.progress > from then
			table.insert(out, {
				title = def.title,
				from = from,
				to = it.entry.progress,
				target = def.target,
				done = it.entry.progress >= def.target,
				weekly = it.weekly,
			})
		end
	end
	return out
end

-- MARLOW announces a new board on the first hub entry after a reset.
function Jobs.announce(player: Player)
	local profile = Profiles.get(player)
	if not profile then
		return
	end
	Jobs.normalize(player)
	local day = Clock.day(now(profile))
	if profile.jobs.announcedDay == day then
		return
	end
	profile.jobs.announcedDay = day
	Profiles.markDirty(player)
	Remotes.Juice:FireClient(player, "JobsAnnounce", { line = Config.JobAnnounceLine })
	Log.event("Jobs", "MARLOW announced the board to %s", player.Name)
end

-- Debug: fresh boards now.
function Jobs.reset(player: Player)
	local profile = Profiles.get(player)
	if not profile then
		return
	end
	profile.jobs.dailyResetDay = 0
	profile.jobs.weeklyResetWeek = 0
	profile.jobs.announcedDay = 0
	profile.jobs.boardSeenDay = 0
	Jobs.normalize(player)
	Log.event("Jobs", "%s: jobs reset (debug)", player.Name)
end

function Jobs.init()
	RunEvents.listen(onEvent)
	Profiles.Loaded:Connect(function(player: Player)
		task.delay(3, function()
			if player.Parent and not (World.inRunCycle() and World.isInParty(player)) then
				Jobs.announce(player)
			end
		end)
	end)
	-- A fake-clock day can turn mid-session: the board redraws and MARLOW calls it for anyone in the hub.
	task.spawn(function()
		while true do
			task.wait(5)
			for _, p in Players:GetPlayers() do
				if Jobs.normalize(p) and not (World.inRunCycle() and World.isInParty(p)) then
					Jobs.announce(p)
				end
			end
		end
	end)
end

return Jobs
