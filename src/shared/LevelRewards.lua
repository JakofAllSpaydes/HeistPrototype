--!strict
-- What a level-up grants. Every level pays Config.LevelGold; the milestones add a mask (`mask` with
-- rewardMaskId). `pass_token` and `emote` exist as kinds with no handler yet (battle pass, emote drops).
local Config = require(script.Parent.Config)
local Masks = require(script.Parent.Masks)

export type Reward = { kind: string, amount: number?, id: string?, label: string }

local LevelRewards = {}

-- Rank names on the level card: the highest `from` at or below the level.
LevelRewards.Ranks = {
	{ from = 1, name = "ROOKIE" },
	{ from = 5, name = "RUNNER" },
	{ from = 10, name = "CREW" },
	{ from = 15, name = "SERGEANT" },
	{ from = 20, name = "LIEUTENANT" },
	{ from = 30, name = "CAPTAIN" },
	{ from = 40, name = "KINGPIN" },
}

function LevelRewards.rank(level: number): string
	local name = LevelRewards.Ranks[1].name
	for _, r in LevelRewards.Ranks do
		if level >= r.from then
			name = r.name
		end
	end
	return name
end

-- The curve: XpToLevel(n) = XpCurveBase x n ^ XpCurvePow (server and the level cards share it).
function LevelRewards.xpToLevel(level: number): number
	return math.max(1, math.floor(Config.XpCurveBase * math.max(1, level) ^ Config.XpCurvePow))
end

-- Milestones: level -> extra rewards.
LevelRewards.Milestones = {
	[5] = { { kind = "mask", id = "blue", label = "BLUE VISOR" } },
	[10] = { { kind = "mask", id = "gold", label = "GOLD VISOR" } },
	[25] = { { kind = "mask", id = "purple", label = "PURPLE VISOR" } },
	[50] = { { kind = "mask", id = "crate", label = "CHROME VISOR" } },
} :: { [number]: { Reward } }

function LevelRewards.forLevel(level: number): { Reward }
	local out: { Reward } = {}
	if Config.LevelGold > 0 then
		table.insert(
			out,
			{ kind = "gold", amount = Config.LevelGold, label = string.format("+%d GOLD", Config.LevelGold) }
		)
	end
	for _, r in LevelRewards.Milestones[level] or {} do
		local reward = table.clone(r)
		if reward.kind == "mask" and reward.id and Masks.ById[reward.id] then
			reward.label = string.upper(Masks.ById[reward.id].name)
		end
		table.insert(out, reward)
	end
	return out
end

-- One line for the level-up pop: "+100 GOLD · BLUE VISOR".
function LevelRewards.line(level: number): string
	local parts = {}
	for _, r in LevelRewards.forLevel(level) do
		table.insert(parts, r.label)
	end
	return table.concat(parts, " · ")
end

return LevelRewards
