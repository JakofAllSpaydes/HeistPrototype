--!strict
-- Brief 6: timed boosts. Run-only effects on a real-time clock from purchase (buying an active one extends it);
-- no boost touches Gold, XP, pass XP or paid-crate odds. The numbers are Config.PowerBoostPct / CashBoostPct /
-- LuckyWeightShift; durations and prices are here.
export type Duration = { id: string, label: string, sec: number, price: number }
export type Boost = {
	id: string, -- power | cash | lucky
	name: string,
	glyph: string, -- 3-letter text fallback; chips draw the client/UI/Icons.lua pictogram keyed by `id`
	color: string,
	desc: string,
	short: string, -- the chip's short label
	durations: { Duration },
}

local Config = require(script.Parent.Config)

local BoostDefs = {}

local function pct(x: number): string
	return string.format("+%d%%", math.round(x * 100))
end

BoostDefs.List = {
	{
		id = "power",
		name = "POWER",
		glyph = "PWR",
		color = "E8554D",
		desc = pct(Config.PowerBoostPct) .. " damage from weapons and abilities",
		short = pct(Config.PowerBoostPct) .. " DMG",
		durations = {
			{ id = "30m", label = "30 MIN", sec = 1800, price = 79 },
			{ id = "2h", label = "2 HR", sec = 7200, price = 199 },
			{ id = "24h", label = "24 HR", sec = 86400, price = 499 },
		},
	},
	{
		id = "cash",
		name = "CASH",
		glyph = "CSH",
		color = "8FE3A1",
		desc = pct(Config.CashBoostPct) .. " match cash from kills, cash bags and job payouts",
		short = pct(Config.CashBoostPct) .. " $",
		durations = {
			{ id = "30m", label = "30 MIN", sec = 1800, price = 79 },
			{ id = "2h", label = "2 HR", sec = 7200, price = 199 },
			{ id = "24h", label = "24 HR", sec = 86400, price = 499 },
		},
	},
	{
		id = "lucky",
		name = "LUCKY",
		glyph = "LCK",
		color = "A864E8",
		desc = "Gun crates and upgrade cards roll one bracket luckier",
		short = "LUCK +1",
		durations = {
			{ id = "30m", label = "30 MIN", sec = 1800, price = 149 },
			{ id = "2h", label = "2 HR", sec = 7200, price = 349 },
			{ id = "24h", label = "24 HR", sec = 86400, price = 899 },
		},
	},
} :: { Boost }

BoostDefs.ById = {} :: { [string]: Boost }
for _, b in BoostDefs.List do
	BoostDefs.ById[b.id] = b
end

-- The product id of one boost duration ("boost_power_2h").
function BoostDefs.productId(boostId: string, durationId: string): string
	return "boost_" .. boostId .. "_" .. durationId
end

return BoostDefs
