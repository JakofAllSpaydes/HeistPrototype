--!strict
-- Brief 6: the catalog. Every Robux-priced thing in the game is one row here (built from the data files), with
-- id, kind, price and what it grants. This is the table real DevProduct / gamepass ids map onto later.
-- kinds: crate · boost · gold · bundle · vip · pass · pass_skip · tokens · cash_pack · dealer_restock · robux_topup ·
-- item (FEATURED's daily single items) · job_refresh (a new Job in a claimed slot)
local Config = require(script.Parent.Config)
local Rewards = require(script.Parent.Rewards)
local Crates = require(script.Parent.Crates)
local BoostDefs = require(script.Parent.BoostDefs)
local GoldPacks = require(script.Parent.GoldPacks)
local Bundles = require(script.Parent.Bundles)
local CashPacks = require(script.Parent.CashPacks)
local ReviveTokenPacks = require(script.Parent.ReviveTokenPacks)
local PassSeason = require(script.Parent.PassSeason)
local DailyShop = require(script.Parent.DailyShop)
local JobPool = require(script.Parent.JobPool)

export type Product = {
	id: string,
	kind: string,
	name: string,
	price: number, -- list price in R$ (Products.priceFor gives the price for one profile)
	icon: Rewards.Reward, -- what the sheet and the cards draw
	sub: string?, -- a line under the price ("/ month", "+$5,000 MATCH CASH")
	-- grant data by kind
	crateId: string?,
	count: number?, -- crate opens, pass levels
	boostId: string?,
	sec: number?,
	gold: number?,
	tokens: number?,
	cash: number?,
	bundleId: string?,
	tier: number?, -- pass tier
	inRun: boolean?, -- sold during a run (the sheet runs over the live game)
	itemKind: string?, -- item: the reward kind and id it grants
	itemId: string?,
	jobBoard: string?, -- job_refresh: "daily" | "bounty"
}

local Products = {}
Products.List = {} :: { Product }
Products.ById = {} :: { [string]: Product }

local function add(p: Product)
	table.insert(Products.List, p)
	Products.ById[p.id] = p
end

for _, c in Crates.List do
	for _, n in Crates.Counts do
		add({
			id = Crates.productId(c.id, n),
			kind = "crate",
			name = string.format("%s ×%d", c.name, n),
			price = c.prices[n],
			icon = { kind = "crate", id = c.id, amount = n },
			crateId = c.id,
			count = n,
		})
	end
end

for _, b in BoostDefs.List do
	for _, d in b.durations do
		add({
			id = BoostDefs.productId(b.id, d.id),
			kind = "boost",
			name = string.format("%s BOOST · %s", b.name, d.label),
			price = d.price,
			icon = { kind = "boost", id = b.id, sec = d.sec },
			sub = b.desc,
			boostId = b.id,
			sec = d.sec,
		})
	end
end

for _, g in GoldPacks.List do
	add({
		id = g.id,
		kind = "gold",
		name = string.format("%s · %s GOLD", g.name, Rewards.int(g.gold)),
		price = g.price,
		icon = { kind = "gold", amount = g.gold },
		gold = g.gold,
	})
end

for _, b in Bundles.List do
	add({
		id = b.id,
		kind = "bundle",
		name = b.name,
		price = b.price,
		icon = b.hero :: any,
		sub = string.format("%d ITEMS", #b.contents),
		bundleId = b.id,
	})
end

for _, t in ReviveTokenPacks.List do
	add({
		id = t.id,
		kind = "tokens",
		name = t.name,
		price = t.price,
		icon = { kind = "tokens", amount = t.tokens },
		tokens = t.tokens,
		inRun = true,
	})
end

for _, c in CashPacks.List do
	add({
		id = c.id,
		kind = "cash_pack",
		name = c.name,
		price = c.price,
		icon = { kind = "cash", amount = c.cash },
		sub = "+$" .. Rewards.int(c.cash) .. " MATCH CASH",
		cash = c.cash,
		inRun = true,
	})
end

add({
	id = "vip",
	kind = "vip",
	name = "VIP MEMBERSHIP",
	price = Config.VipPrice,
	icon = { kind = "mask", id = "vip_gold" },
	sub = "/ month",
})

add({
	id = "pass_premium",
	kind = "pass",
	name = "PREMIUM PASS",
	price = Config.PassPremiumPrice,
	icon = { kind = "pass", amount = 1 },
	tier = 1,
})
add({
	id = "pass_premiumplus",
	kind = "pass",
	name = "PREMIUM+ PASS",
	price = Config.PassPremiumPlusPrice,
	icon = { kind = "pass", amount = 2 },
	tier = 2,
})
for _, n in PassSeason.SkipCounts do
	add({
		id = PassSeason.skipProductId(n),
		kind = "pass_skip",
		name = string.format("SKIP %d LEVEL%s", n, if n == 1 then "" else "S"),
		price = Config.PassSkipPrice * n,
		icon = { kind = "passskip", amount = n },
		count = n,
	})
end

for _, e in DailyShop.Pool do
	add({
		id = DailyShop.productId(e),
		kind = "item",
		name = Rewards.name(e :: any),
		price = DailyShop.price(e),
		icon = e :: any,
		sub = Rewards.kindLabel(e :: any),
		itemKind = e.kind,
		itemId = e.id,
	})
end

add({
	id = "daily_reroll",
	kind = "daily_reroll",
	name = "REROLL DAILY ITEMS",
	price = Config.DailyShopRerollPrice,
	icon = { kind = "restock", amount = 1 },
	sub = "A fresh set of daily items, just for you",
})

for _, board in { "daily", "bounty" } do
	add({
		id = "job_refresh_" .. board,
		kind = "job_refresh",
		name = if board == "daily" then "NEW DAILY JOB" else "NEW WEEKLY BOUNTY",
		price = JobPool.RefreshPrice[board],
		icon = { kind = "passxp", amount = 1 },
		sub = "Swap a finished Job for a fresh one with its own rewards",
		jobBoard = board,
	})
end

add({
	id = "dealer_restock",
	kind = "dealer_restock",
	name = "DEALER RESTOCK",
	price = 49,
	icon = { kind = "restock", amount = 1 },
	sub = "A fresh table of eight, free of match cash",
	inRun = true,
})

add({
	id = "robux_topup",
	kind = "robux_topup",
	name = "GET ROBUX",
	price = 0,
	icon = { kind = "robux", amount = Config.FakeRobuxTopUp },
	sub = "Prototype placeholder: adds R$ " .. Rewards.int(Config.FakeRobuxTopUp),
	inRun = true,
})

-- The price this profile pays: bundles lose their owned share, PREMIUM+ from PREMIUM costs the difference.
function Products.priceFor(p: Product, profile: any): number
	if p.kind == "bundle" and p.bundleId then
		local b = Bundles.ById[p.bundleId]
		local price = Bundles.priceFor(b, profile)
		return price
	elseif p.kind == "pass" and p.tier == 2 then
		local tier = if profile and profile.pass then tonumber(profile.pass.tier) or 0 else 0
		if tier >= 1 then
			return math.max(0, Config.PassPremiumPlusPrice - Config.PassPremiumPrice)
		end
	end
	return p.price
end

return Products
