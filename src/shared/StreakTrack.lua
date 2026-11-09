--!strict
-- Brief 10: the login streak's track math, shared by the server (Streak.lua) and the modal. Day keys are fake-day
-- numbers (Clock.day of the player's fake clock). `day` is the position on the 28-day track (1..28), `lastClaimDay`
-- the fake day of the last claim. The rewards are Config.StreakRewards.
local Config = require(script.Parent.Config)
local Rewards = require(script.Parent.Rewards)

local StreakTrack = {}

StreakTrack.LENGTH = 28
StreakTrack.WEEK = 7

export type Entry = { kind: string, id: string?, amount: number?, sec: number?, floor: number? }

-- The claim after `day` on the track: day + 1, wrapping 28 -> StreakLoopFrom (week 4 repeats). 0 (never) -> 1.
function StreakTrack.nextDay(day: number): number
	if day < 1 then
		return 1
	elseif day >= StreakTrack.LENGTH then
		return math.clamp(Config.StreakLoopFrom, 1, StreakTrack.LENGTH)
	end
	return day + 1
end

function StreakTrack.rewards(day: number): { Entry }
	local list = (Config.StreakRewards :: any)[math.clamp(day, 1, StreakTrack.LENGTH)]
	return if typeof(list) == "table" then list :: { Entry } else {}
end

function StreakTrack.isBig(day: number): boolean
	return day % StreakTrack.WEEK == 0
end

-- 1..4
function StreakTrack.week(day: number): number
	return math.clamp((math.max(day, 1) - 1) // StreakTrack.WEEK + 1, 1, 4)
end

export type State = "none" | "claim" | "lost"

-- What the first hub entry of `today` shows: nothing (claimed today), the next claim, or a lost streak.
-- Returns the state, the day the claim lands on (or the day a restore would land on), and for "lost" the same day.
function StreakTrack.state(streak: { day: number, lastClaimDay: number }, today: number): (State, number)
	local last = streak.lastClaimDay
	if last >= today and last > 0 then
		return "none", streak.day
	elseif last <= 0 or streak.day < 1 then
		return "claim", 1
	elseif last == today - 1 then
		return "claim", StreakTrack.nextDay(streak.day)
	end
	-- Missed at least one day: "YOU WERE ON DAY N", N = the day today's claim would have been.
	return "lost", StreakTrack.nextDay(streak.day)
end

-- Short copy for a reward tile ("300", "×2", "RARE+", "30M", "1,000").
function StreakTrack.short(r: Entry): string
	local k, n = r.kind, r.amount or 0
	if k == "crate" then
		local floor = r.floor or 1
		if floor >= 5 then
			return "LEGENDARY"
		elseif floor >= 4 then
			return "EPIC+"
		elseif floor >= 3 then
			return "RARE+"
		elseif floor >= 2 then
			return "UNCOMMON+"
		end
		return "×" .. Rewards.int(math.max(1, n))
	elseif k == "boost" then
		return Rewards.duration(r.sec or 0)
	end
	return Rewards.int(n)
end

-- Full copy ("ARMS CRATE · EPIC+", "1,000 PASS XP", "CASH BOOST · 30M").
function StreakTrack.name(r: Entry): string
	if r.kind == "crate" then
		local base = if r.id == "mask" then "MASK CRATE" else "ARMS CRATE"
		local floor = r.floor or 1
		if floor > 1 then
			return base .. " · " .. StreakTrack.short(r)
		end
		local n = math.max(1, r.amount or 1)
		return if n > 1 then string.format("%d × %s", n, base) else base
	elseif r.kind == "passxp" then
		return Rewards.int(r.amount or 0) .. " PASS XP"
	elseif r.kind == "boost" then
		return string.format("%s BOOST · %s", string.upper(r.id or ""), Rewards.duration(r.sec or 0))
	end
	return Rewards.name(r :: any)
end

return StreakTrack
