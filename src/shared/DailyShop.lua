--!strict
-- Round 17c: FEATURED's daily items. Config.DailyShopItems single items a fake UTC day, drawn the same for everyone
-- (seeded by the day number) from the things you otherwise only get from crates or past events, each sold on its own
-- for fake Robux at a price by rarity. Products.lua builds one `item_<kind>_<id>` product per pool entry.
local Config = require(script.Parent.Config)
local Crates = require(script.Parent.Crates)
local Rewards = require(script.Parent.Rewards)
local MixedRoll = require(script.Parent.MixedRoll) -- Round 30d

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

-- Round 18: REROLL (R$ Config.DailyShopRerollPrice) draws this profile a fresh set for the day; the count resets
-- with the day. The draw is seeded by (day, rerolls), so client and server agree without storing the list.
function DailyShop.rerollsOn(profile: any, day: number): number
	local r = profile and profile.dailyReroll
	if typeof(r) ~= "table" or tonumber(r.day) ~= day then
		return 0
	end
	return math.max(0, math.floor(tonumber(r.count) or 0))
end

-- The day's items (a fake UTC day number) after `rerolls` rerolls, in display order. Round 30d: each slot is the shared
-- mixed roll (MixedRoll: category by DailyShopCategoryWeights, then rarity by DailyShopRarityWeights, then an item),
-- seeded by the day so every client and the server draw the same set; nothing shows twice in a day.
local KINDS = { "weapon", "mask", "emote", "wrap" } -- fixed order: the seeded roll must see the same list everywhere

function DailyShop.forDay(day: number, rerolls: number?): { Entry }
	local rng = Random.new(day * 7919 + 17 + (rerolls or 0) * 104729)
	local byKind: { [string]: { MixedRoll.Entry } } = {}
	for _, e in DailyShop.Pool do
		local list = byKind[e.kind] or {}
		byKind[e.kind] = list
		table.insert(list, { kind = e.kind, id = e.id, rarity = math.clamp(Rewards.rarity(e :: any), 1, 5) })
	end
	local taken: { [string]: boolean } = {}
	local function skip(e: MixedRoll.Entry): boolean
		return taken[e.kind .. ":" .. e.id] == true
	end
	local out = {}
	for _ = 1, Config.DailyShopItems do
		local categories: { MixedRoll.Category } = {}
		for _, kind in KINDS do
			local list = byKind[kind]
			if list then
				local w = tonumber((Config.DailyShopCategoryWeights :: any)[kind]) or 0
				table.insert(categories, MixedRoll.list(kind, w, list, skip))
			end
		end
		local item = MixedRoll.roll({
			categories = categories,
			rarityWeights = Config.DailyShopRarityWeights,
			rng = rng,
		})
		if not item then
			break
		end
		taken[item.kind .. ":" .. item.id] = true
		table.insert(out, { kind = item.kind, id = item.id })
	end
	return out
end

function DailyShop.offeredOn(day: number, kind: string, id: string, rerolls: number?): boolean
	for _, e in DailyShop.forDay(day, rerolls) do
		if e.kind == kind and e.id == id then
			return true
		end
	end
	return false
end

return DailyShop
