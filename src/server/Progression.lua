--!strict
-- The account level. XP is awarded once per player at the summary write (Config's Progression group:
-- waves cleared, kills, jobs, boss kills, minutes survived; x XpFirstHeistMult on the first completed run of
-- a UTC day). The curve is XpToLevel(n) = XpCurveBase x n ^ XpCurvePow with no cap; overflow carries so one
-- run can level several times, and every level-up grants LevelRewards (Gold, milestone masks). The
-- breakdown goes to the summary so the XP bar can replay it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local LevelRewards = require(Shared.LevelRewards)
local Masks = require(Shared.Masks)
local Profiles = require(script.Parent.Profiles)
local Log = require(script.Parent.Log)

local Progression = {}

export type LevelUp = { level: number, rewards: { LevelRewards.Reward }, line: string }
export type Award = {
	gained: number,
	first: boolean, -- first heist of the day: the multiplier applied
	mult: number,
	parts: { { label: string, xp: number } },
	fromLevel: number,
	fromXp: number,
	toLevel: number,
	toXp: number,
	levelUps: { LevelUp },
}

function Progression.xpToLevel(level: number): number
	return LevelRewards.xpToLevel(level)
end

function Progression.today(): number
	return math.floor(os.time() / 86400)
end

function Progression.level(player: Player): number
	local p = Profiles.get(player)
	return if p then p.level else 1
end

local function grant(player: Player, profile: Profiles.Profile, level: number): { LevelRewards.Reward }
	local rewards = LevelRewards.forLevel(level)
	for _, r in rewards do
		if r.kind == "gold" and r.amount then
			Profiles.grantPayout(player, r.amount, string.format("level %d reward", level))
		elseif r.kind == "mask" and r.id and Masks.ById[r.id] then
			profile.masks.owned[r.id] = true
		end
		-- pass_token / emote: kinds with no handler yet.
	end
	return rewards
end

-- Run inputs for one player.
export type RunInput = { wavesCleared: number, kills: number, jobs: number, bossKills: number, survivedSec: number }

function Progression.award(player: Player, input: RunInput): Award?
	local profile = Profiles.get(player)
	if not profile then
		return nil
	end
	local parts = {}
	local function part(label: string, xp: number)
		if xp > 0 then
			table.insert(parts, { label = label, xp = xp })
		end
	end
	part("WAVES", Config.XpPerWave * input.wavesCleared)
	part("KILLS", Config.XpPerKill * input.kills)
	part("JOBS", Config.XpPerJob * input.jobs)
	part("BOSS", Config.XpPerBoss * input.bossKills)
	part("SURVIVED", math.floor(Config.XpSurvivedPerMin * input.survivedSec / 60))
	local base = 0
	for _, p in parts do
		base += p.xp
	end
	local today = Progression.today()
	local first = profile.lastHeistDay ~= today
	profile.lastHeistDay = today
	local mult = if first then Config.XpFirstHeistMult else 1
	local gained = math.floor(base * mult)

	local fromLevel, fromXp = profile.level, profile.xp
	profile.xp += gained
	profile.stats.xp += gained
	local levelUps: { LevelUp } = {}
	while profile.xp >= Progression.xpToLevel(profile.level) do
		profile.xp -= Progression.xpToLevel(profile.level)
		profile.level += 1
		local rewards = grant(player, profile, profile.level)
		table.insert(levelUps, { level = profile.level, rewards = rewards, line = LevelRewards.line(profile.level) })
	end
	Profiles.markDirty(player)
	Log.event(
		"XP",
		"%s +%d XP (%d base%s): LV %d (%d) -> LV %d (%d / %d)%s",
		player.Name,
		gained,
		base,
		if first then string.format(", first heist x%.1f", mult) else "",
		fromLevel,
		fromXp,
		profile.level,
		profile.xp,
		Progression.xpToLevel(profile.level),
		if #levelUps > 0 then string.format(", %d level-up%s", #levelUps, if #levelUps == 1 then "" else "s") else ""
	)
	return {
		gained = gained,
		first = first,
		mult = mult,
		parts = parts,
		fromLevel = fromLevel,
		fromXp = fromXp,
		toLevel = profile.level,
		toXp = profile.xp,
		levelUps = levelUps,
	}
end

-- Debug: raw XP (levels up as it goes), a level, the daily flag.
function Progression.addXp(player: Player, amount: number)
	local profile = Profiles.get(player)
	if not profile then
		return
	end
	profile.xp += math.max(0, math.floor(amount))
	profile.stats.xp += math.max(0, math.floor(amount))
	while profile.xp >= Progression.xpToLevel(profile.level) do
		profile.xp -= Progression.xpToLevel(profile.level)
		profile.level += 1
		grant(player, profile, profile.level)
	end
	Profiles.markDirty(player)
	Log.event("XP", "%s +%d XP (debug): LV %d (%d)", player.Name, amount, profile.level, profile.xp)
end

function Progression.setLevel(player: Player, level: number)
	local profile = Profiles.get(player)
	if not profile then
		return
	end
	profile.level = math.max(1, math.floor(level))
	profile.xp = 0
	Profiles.markDirty(player)
	Log.event("XP", "%s set to LV %d (debug)", player.Name, profile.level)
end

function Progression.resetDaily(player: Player)
	local profile = Profiles.get(player)
	if not profile then
		return
	end
	profile.lastHeistDay = 0
	Profiles.markDirty(player)
	Log.event("XP", "%s's daily flag reset (debug)", player.Name)
end

return Progression
