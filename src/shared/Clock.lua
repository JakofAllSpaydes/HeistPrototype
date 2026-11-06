--!strict
-- Brief 6: the fake clock. Every live-ops timer (season, FEATURED rotation, VIP renewal, Job resets) runs on the
-- player's fake time: real UTC plus `profile.clockOffset` (the debug "advance season day" adds a day to it).
-- Server: os.time(). Client: the server time it last synced (ClientState.osNow), so both sides agree.
local Config = require(script.Parent.Config)

local Clock = {}

local DAY = 86400

function Clock.fake(realNow: number, profile: any): number
	local off = if profile and typeof(profile.clockOffset) == "number" then profile.clockOffset else 0
	return realNow + off
end

-- UTC day number (days since 1970-01-01).
function Clock.day(t: number): number
	return math.floor(t / DAY)
end

-- UTC week number, weeks starting Monday (1970-01-01 was a Thursday, so shift by 3 days).
function Clock.week(t: number): number
	return math.floor((t + 3 * DAY) / (7 * DAY))
end

function Clock.nextDay(t: number): number
	return (Clock.day(t) + 1) * DAY
end

function Clock.nextWeek(t: number): number
	return (Clock.week(t) + 1) * 7 * DAY - 3 * DAY
end

-- FEATURED: the rotation slot index and when it next turns.
function Clock.featuredSlot(t: number): number
	return math.floor((t - Config.FeaturedEpochUtc) / Config.FeaturedRotationSec)
end

function Clock.featuredEndsAt(t: number): number
	return Config.FeaturedEpochUtc + (Clock.featuredSlot(t) + 1) * Config.FeaturedRotationSec
end

-- "2d 14h", "6h 12m", "4m 05s".
function Clock.span(sec: number): string
	sec = math.max(0, math.floor(sec))
	local d = sec // DAY
	local h = (sec % DAY) // 3600
	local m = (sec % 3600) // 60
	local s = sec % 60
	if d > 0 then
		return string.format("%dd %dh", d, h)
	elseif h > 0 then
		return string.format("%dh %dm", h, m)
	end
	return string.format("%dm %02ds", m, s)
end

-- "mm:ss" (or "h:mm:ss" past an hour) for the boost chips.
function Clock.timer(sec: number): string
	sec = math.max(0, math.ceil(sec))
	if sec >= 3600 then
		return string.format("%d:%02d:%02d", sec // 3600, (sec % 3600) // 60, sec % 60)
	end
	return string.format("%d:%02d", sec // 60, sec % 60)
end

-- "62:14:05": total hours, minutes, seconds (the LEAVING IN / NEW JOBS IN countdowns).
function Clock.hms(sec: number): string
	sec = math.max(0, math.floor(sec))
	return string.format("%02d:%02d:%02d", sec // 3600, (sec % 3600) // 60, sec % 60)
end

-- "2D 16H 42M" (the weekly countdowns).
function Clock.dhm(sec: number): string
	sec = math.max(0, math.floor(sec))
	return string.format("%dD %02dH %02dM", sec // 86400, (sec % 86400) // 3600, (sec % 3600) // 60)
end

return Clock
