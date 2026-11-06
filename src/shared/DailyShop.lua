--!strict
-- Round 17c: FEATURED's daily items. Config.DailyShopItems single items a fake UTC day, drawn the same for everyone
-- (seeded by the day number) from the things you otherwise only get from crates or past events, each sold on its own
-- for fake Robux at a price by rarity. Products.lua builds one `item_<kind>_<id>` product per pool entry.
local Config = require(script.Parent.Config)
local Crates = require(script.Parent.Crates)
local Rewards = require(script.Parent.Rewards)

export type Entry = { kind: string, id: string }

local DailyShop = {}

DailyShop.PriceByRarity = { 99, 149, 249, 399, 699 } -- R$, Common .. Legendary

-- Every crate item plus the past-event cosmetics.
DailyShop.Pool = {} :: { Entry }
for _, c in Crates.List do
	for _, id in c.pool do
		table.insert(DailyShop.Pool, { kind = c.kind, id = id })
	end
end
table.insert(DailyShop.Pool, { kind = "mask", id = "event" }) -- Night Bandana (event)
table.insert(DailyShop.Pool, { kind = "emote", id = "victory" }) -- Victory (event)

function DailyShop.productId(e: Entry): string
	return string.format("item_%s_%s", e.kind, e.id)
end

function DailyShop.price(e: Entry): number
	return DailyShop.PriceByRarity[math.clamp(Rewards.rarity(e :: any), 1, 5)]
end

-- The day's items (a fake UTC day number), in display order.
function DailyShop.forDay(day: number): { Entry }
	local rng = Random.new(day * 7919 + 17)
	local pool = table.clone(DailyShop.Pool)
	local out = {}
	for _ = 1, math.min(Config.DailyShopItems, #pool) do
		local i = rng:NextInteger(1, #pool)
		table.insert(out, pool[i])
		table.remove(pool, i)
	end
	return out
end

function DailyShop.offeredOn(day: number, kind: string, id: string): boolean
	for _, e in DailyShop.forDay(day) do
		if e.kind == kind and e.id == id then
			return true
		end
	end
	return false
end

return DailyShop
