--!strict
-- Brief 6: the battle pass seasons. One track of Config.PassLevels levels, three lanes per level read top to bottom:
-- FREE (everyone), PREMIUM (tier 1) and PREMIUM+ (tier 2, includes PREMIUM). The FREE lane has something every
-- level; PREMIUM+ carries the hero cosmetics at 10 / 20 / 30. Seasons run Config.SeasonLengthDays on the fake
-- clock from Config.SeasonEpochUtc; after the last defined season the list cycles (the number keeps counting).
-- Round 18c: the track never ends. Past Config.PassLevels every level is a BONUS level whose three cells come from
-- PassSeason.Bonus (twelve rows of Gold, tokens, crate opens, boosts and mastery, never cosmetics), cycling.
local Config = require(script.Parent.Config)
local Rewards = require(script.Parent.Rewards)

export type Cell = Rewards.Reward
export type Level = { free: Cell, p1: Cell, p2: Cell }
export type Season = {
	id: number,
	name: string,
	color: string, -- the banner / emblem color
	heroes: { Cell }, -- the PREMIUM+ heroes (10 / 20 / 30), drawn on the sell card
	grid: { Level },
}

local PassSeason = {}

PassSeason.Lanes = { "free", "p1", "p2" }
PassSeason.LaneTier = { free = 0, p1 = 1, p2 = 2 } :: { [string]: number }
PassSeason.LaneName = { free = "FREE", p1 = "PREMIUM", p2 = "PREMIUM+" } :: { [string]: string }
PassSeason.SkipCounts = { 1, 5, 10 }

local function gold(n: number): Cell
	return { kind = "gold", amount = n }
end
local function tokens(n: number): Cell
	return { kind = "tokens", amount = n }
end
local function crate(id: string, n: number): Cell
	return { kind = "crate", id = id, amount = n }
end
local function boost(id: string, sec: number): Cell
	return { kind = "boost", id = id, sec = sec }
end
local function mastery(n: number): Cell
	return { kind = "mastery", amount = n }
end
local function item(kind: string, id: string): Cell
	return { kind = kind, id = id }
end

-- Builds a 1..PassLevels grid from per-lane defaults plus overrides.
local function grid(
	free: { [number]: Cell },
	p1: { [number]: Cell },
	p2: { [number]: Cell },
	freeDefault: (number) -> Cell,
	p1Default: (number) -> Cell,
	p2Default: (number) -> Cell
): { Level }
	local out = {}
	for l = 1, Config.PassLevels do
		out[l] = {
			free = free[l] or freeDefault(l),
			p1 = p1[l] or p1Default(l),
			p2 = p2[l] or p2Default(l),
		}
	end
	return out
end

local function freeGold(l: number): Cell
	return gold(100 + math.floor(l / 3) * 25)
end
local function premiumGold(l: number): Cell
	return gold(200 + math.floor(l / 2) * 25)
end
local function plusDefault(l: number): Cell
	if l % 3 == 0 then
		return gold(500)
	end
	return crate(if l % 2 == 0 then "mask" else "arms", 1)
end

PassSeason.Seasons = {
	{
		id = 1,
		name = "NIGHT SHIFT",
		color = "E8792A",
		heroes = { item("wrap", "p_inferno"), item("mask", "p_phantom"), item("emote", "p_herolanding") },
		grid = grid({
			[3] = tokens(2),
			[5] = crate("arms", 1),
			[8] = item("mask", "p_tiger"),
			[10] = tokens(3),
			[12] = item("wrap", "p_carbon"),
			[15] = crate("mask", 1),
			[18] = item("emote", "p_shrug"),
			[20] = tokens(5),
			[22] = boost("cash", 1800),
			[25] = crate("arms", 1),
			[28] = tokens(5),
			[30] = gold(1000),
		}, {
			[2] = crate("arms", 1),
			[4] = tokens(3),
			[5] = item("wrap", "p_tigerwrap"),
			[7] = mastery(200),
			[9] = boost("power", 1800),
			[11] = crate("mask", 1),
			[13] = tokens(5),
			[15] = item("mask", "p_static"),
			[17] = mastery(300),
			[19] = crate("arms", 2),
			[21] = boost("lucky", 1800),
			[23] = tokens(5),
			[25] = item("emote", "p_hello"),
			[27] = crate("mask", 2),
			[29] = boost("cash", 7200),
			[30] = item("emote", "p_callout"),
		}, {
			[5] = boost("power", 7200),
			[10] = item("wrap", "p_inferno"),
			[15] = item("emote", "p_godlike"),
			[20] = item("mask", "p_phantom"),
			[25] = boost("power", 86400),
			[30] = item("emote", "p_herolanding"),
		}, freeGold, premiumGold, plusDefault),
	},
	{
		id = 2,
		name = "COLD CASE",
		color = "4DB8FF",
		heroes = { item("wrap", "p_glacier"), item("mask", "p_frostbite"), item("emote", "p_celebrate") },
		grid = grid({
			[4] = tokens(2),
			[6] = crate("mask", 1),
			[10] = tokens(3),
			[14] = crate("arms", 1),
			[20] = tokens(5),
			[24] = boost("lucky", 1800),
			[27] = crate("mask", 1),
			[30] = gold(1000),
		}, {
			[3] = crate("mask", 1),
			[6] = tokens(3),
			[8] = mastery(200),
			[12] = boost("cash", 1800),
			[16] = crate("arms", 2),
			[18] = mastery(300),
			[22] = tokens(5),
			[26] = boost("power", 7200),
			[30] = crate("mask", 3),
		}, {
			[10] = item("wrap", "p_glacier"),
			[20] = item("mask", "p_frostbite"),
			[25] = boost("lucky", 7200),
			[30] = item("emote", "p_celebrate"),
		}, freeGold, premiumGold, plusDefault),
	},
} :: { Season }

-- The bonus loop past the last level (shared by every season), one row per level, cycling.
PassSeason.Bonus = {
	{ free = gold(250), p1 = crate("arms", 1), p2 = crate("mask", 1) },
	{ free = tokens(2), p1 = gold(400), p2 = boost("power", 1800) },
	{ free = crate("arms", 1), p1 = mastery(200), p2 = gold(750) },
	{ free = gold(300), p1 = tokens(3), p2 = crate("arms", 2) },
	{ free = mastery(150), p1 = boost("cash", 1800), p2 = tokens(5) },
	{ free = crate("mask", 1), p1 = gold(500), p2 = boost("lucky", 1800) },
	{ free = gold(350), p1 = crate("mask", 1), p2 = mastery(400) },
	{ free = tokens(3), p1 = boost("power", 1800), p2 = crate("mask", 2) },
	{ free = boost("cash", 1800), p1 = mastery(250), p2 = gold(1000) },
	{ free = gold(400), p1 = crate("arms", 2), p2 = boost("power", 7200) },
	{ free = crate("arms", 1), p1 = tokens(5), p2 = tokens(8) },
	{ free = gold(500), p1 = crate("mask", 2), p2 = crate("arms", 3) },
} :: { Level }

function PassSeason.isBonus(level: number): boolean
	return level > Config.PassLevels
end

-- The season number at fake time `t` (1 from SeasonEpochUtc).
function PassSeason.numberAt(t: number): number
	local len = Config.SeasonLengthDays * 86400
	return math.max(1, math.floor((t - Config.SeasonEpochUtc) / len) + 1)
end

-- The definition season number `n` plays (cycles through the list).
function PassSeason.forNumber(n: number): Season
	local list = PassSeason.Seasons
	return list[((math.max(1, n) - 1) % #list) + 1]
end

function PassSeason.endsAt(n: number): number
	return Config.SeasonEpochUtc + n * Config.SeasonLengthDays * 86400
end

function PassSeason.cell(season: Season, level: number, lane: string): Cell?
	local row = if level > Config.PassLevels
		then PassSeason.Bonus[((level - Config.PassLevels - 1) % #PassSeason.Bonus) + 1]
		else season.grid[level]
	return if row then (row :: any)[lane] else nil
end

-- The level a PREMIUM+ hero sits at (10 / 20 / 30 on the default grid).
function PassSeason.heroLevel(season: Season, index: number): number
	return math.floor(Config.PassLevels * index / 3)
end

-- Every season and level an item appears in (VIEW PASS deep links).
function PassSeason.levelOf(kind: string, id: string): (number?, number?, string?)
	for _, s in PassSeason.Seasons do
		for l, row in s.grid do
			for _, lane in PassSeason.Lanes do
				local c = (row :: any)[lane]
				if c.kind == kind and c.id == id then
					return s.id, l, lane
				end
			end
		end
	end
	return nil, nil, nil
end

-- Cells claimable right now for a profile.pass table (reached levels, owned lanes, not yet claimed).
function PassSeason.claimableCount(pass: any): number
	if not pass then
		return 0
	end
	local n = 0
	local tier = tonumber(pass.tier) or 0
	for level = 1, tonumber(pass.level) or 1 do
		local c = pass.claimed and pass.claimed["L" .. level]
		for _, lane in PassSeason.Lanes do
			if (PassSeason.LaneTier[lane] or 9) <= tier and not (c and c[lane]) then
				n += 1
			end
		end
	end
	return n
end

function PassSeason.skipProductId(count: number): string
	return "pass_skip_" .. count
end

return PassSeason
