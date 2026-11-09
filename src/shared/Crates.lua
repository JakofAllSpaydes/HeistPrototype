--!strict
-- Brief 6: the two paid crates. The odds panel renders from the same weight table the server rolls with, so the
-- two can never disagree. Pool items are the Crate-saleType weapons (Weapons.lua) and masks (Masks.lua), each
-- sitting at its own rarity; the roll picks a rarity by weight (pity forces Epic+), then an item uniformly inside it.
local Config = require(script.Parent.Config)
local Weapons = require(script.Parent.Weapons)
local Masks = require(script.Parent.Masks)

export type Crate = {
	id: string, -- arms | mask (brief 10: daily_<tier>, lookup only)
	name: string,
	kind: string, -- weapon | mask (the pool's reward kind) | mixed (brief 10: the daily crate, guns and masks)
	color: string, -- the crate body
	trim: string,
	weights: { number }, -- Common / Uncommon / Rare / Epic / Legendary
	pool: { string }, -- item ids
	prices: { [number]: number }, -- opens -> R$
	tagline: string,
}

local Crates = {}

Crates.Counts = { 1, 3, 10 } -- OPEN 1 / OPEN 3 / OPEN 10

Crates.List = {
	{
		id = "arms",
		name = "ARMS CRATE",
		kind = "weapon",
		color = "2C3440",
		trim = "E8B64C",
		weights = { 40, 30, 18, 9, 3 },
		pool = { "MAC10", "Skorpion", "AUG", "PS90", "FAL", "Model1887", "Mosin", "Gold1911" },
		prices = { [1] = 129, [3] = 299, [10] = 799 },
		tagline = "8 CRATE-ONLY GUNS",
	},
	{
		id = "mask",
		name = "MASK CRATE",
		kind = "mask",
		color = "3A2440",
		trim = "A864E8",
		weights = { 45, 28, 17, 8, 2 },
		pool = { "c_grin", "c_camo", "c_aviator", "c_hockey", "c_neon", "c_ram", "c_chrome", "c_king" },
		prices = { [1] = 99, [3] = 249, [10] = 699 },
		tagline = "8 CRATE-ONLY MASKS",
	},
} :: { Crate }

Crates.ById = {} :: { [string]: Crate }
for _, c in Crates.List do
	Crates.ById[c.id] = c
end

-- Brief 10: the daily crate's tiers (Config.DailyCrateTierOdds) are looked up by id like the paid crates, so the
-- crate scene, the crate model and the art draw them unchanged. They are never in Crates.List (not sold, not on the
-- CRATES tab, no products); their pool is Catalog.dailyPool and the server rolls them (DailyCrate.lua).
Crates.DAILY_PREFIX = "daily_"
for tierId, t in Config.DailyCrateTierOdds :: { [string]: any } do
	Crates.ById[Crates.DAILY_PREFIX .. tierId] = {
		id = Crates.DAILY_PREFIX .. tierId,
		name = string.upper(t.name) .. " DAILY CRATE",
		kind = "mixed",
		color = t.color,
		trim = t.trim,
		weights = t.weights,
		pool = {},
		prices = {},
		tagline = "GUNS + MASKS",
	}
end

function Crates.dailyId(tierId: string): string
	return Crates.DAILY_PREFIX .. tierId
end

function Crates.itemRarity(crate: Crate, id: string): number
	if crate.kind == "weapon" then
		local w = Weapons.ById[id]
		return if w then w.rarity else 1
	end
	local m = Masks.ById[id]
	return if m then m.rarity else 1
end

-- Pool ids at one rarity.
function Crates.itemsAt(crate: Crate, rarity: number): { string }
	local out = {}
	for _, id in crate.pool do
		if Crates.itemRarity(crate, id) == rarity then
			table.insert(out, id)
		end
	end
	return out
end

-- The odds panel and the roll: weight per rarity, skipping any rarity the pool has nothing at.
function Crates.odds(crate: Crate, minRarity: number?): { number }
	local out = {}
	local total = 0
	for r = 1, 5 do
		local w = if r < (minRarity or 1) or #Crates.itemsAt(crate, r) == 0 then 0 else crate.weights[r]
		out[r] = w
		total += w
	end
	for r = 1, 5 do
		out[r] = if total > 0 then out[r] / total else 0
	end
	return out
end

function Crates.productId(crateId: string, count: number): string
	return string.format("crate_%s_%d", crateId, count)
end

function Crates.itemName(crate: Crate, id: string): string
	if crate.kind == "weapon" then
		local w = Weapons.ById[id]
		return if w then w.displayName else id
	end
	local m = Masks.ById[id]
	return if m then m.name else id
end

-- Which crate drops an item (for VIEW CRATE deep links), nil when none does.
function Crates.crateOf(kind: string, id: string): string?
	for _, c in Crates.List do
		if c.kind == kind and table.find(c.pool, id) then
			return c.id
		end
	end
	return nil
end

return Crates
