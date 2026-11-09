--!strict
-- Round 30d: the one roll for any pool that mixes item types (the daily crate, the daily shop, the gun crate's bonus
-- roll, any future mixed crate). Three steps, always in this order:
--   1. category   by each category's weight, among the categories that have something to give (at or above `floor`)
--   2. rarity     by `rarityWeights` over the rarities that category can give (`forceRarity` wins when it can);
--                 a category with a single rarity (relics) skips the weights
--   3. item       the category's own picker for that rarity
-- Pass `rng` (a Random) for a seeded roll that every client repeats exactly (the daily shop); without it math.random.
-- Categories are plain tables, so a caller can build its own; the builders below cover the common ones.
local Weapons = require(script.Parent.Weapons)
local Wraps = require(script.Parent.Wraps)

export type Picked = { kind: string, id: string, rarity: number, on: string? }

export type Category = {
	id: string,
	weight: number,
	rarities: { number }?, -- the rarities it rolls over (default 1..5)
	has: (rarity: number) -> boolean, -- can it give something of this rarity?
	pick: (rarity: number, rng: Random?) -> Picked?,
}

export type Spec = {
	categories: { Category },
	rarityWeights: { number }, -- by rarity (1 Common .. 5 Legendary)
	floor: number?, -- the lowest rarity it may give
	forceRarity: number?, -- debug Force rarity (used when the category can give it)
	rng: Random?,
}

local MixedRoll = {}

local ALL = { 1, 2, 3, 4, 5 }

local function unit(rng: Random?): number
	return if rng then rng:NextNumber() else math.random()
end

-- One entry of `list`, weighted (entries weighing 0 or less never come up). nil when nothing weighs anything.
function MixedRoll.weighted<T>(list: { T }, weightOf: (T) -> number, rng: Random?): T?
	local total = 0
	for _, x in list do
		total += math.max(0, weightOf(x))
	end
	if total <= 0 then
		return nil
	end
	local r = unit(rng) * total
	for _, x in list do
		local w = math.max(0, weightOf(x))
		r -= w
		if r <= 0 and w > 0 then
			return x
		end
	end
	return list[#list]
end

-- Rolls once. Returns the item and the category it came from (nil, nil when nothing can be given).
function MixedRoll.roll(spec: Spec): (Picked?, string?)
	local lo = spec.floor or 1
	local function usable(c: Category): { number }
		local out = {}
		local list: { number } = c.rarities or ALL
		for _, r in list do
			if r >= lo and c.has(r) then
				table.insert(out, r)
			end
		end
		return out
	end
	local open: { Category } = {}
	for _, c in spec.categories do
		if c.weight > 0 and #usable(c) > 0 then
			table.insert(open, c)
		end
	end
	local cat = MixedRoll.weighted(open, function(c: Category): number
		return c.weight
	end, spec.rng)
	if not cat then
		return nil, nil
	end
	local rs = usable(cat)
	local rarity: number
	if spec.forceRarity and table.find(rs, spec.forceRarity) then
		rarity = spec.forceRarity
	elseif #rs == 1 then
		rarity = rs[1]
	else
		rarity = MixedRoll.weighted(rs, function(r: number): number
			return spec.rarityWeights[r] or 0
		end, spec.rng) or rs[1]
	end
	return cat.pick(rarity, spec.rng), cat.id
end

------------------------------------------------------------------ Category builders
export type Entry = { kind: string, id: string, rarity: number }

-- Any flat list of items of one kind: an item of the rolled rarity at random. `skip` leaves some out (the day's
-- shop items already drawn, things owned).
function MixedRoll.list(id: string, weight: number, items: { Entry }, skip: ((Entry) -> boolean)?): Category
	local function at(r: number): { Entry }
		local out = {}
		for _, e in items do
			if e.rarity == r and not (skip and skip(e)) then
				table.insert(out, e)
			end
		end
		return out
	end
	return {
		id = id,
		weight = weight,
		has = function(r: number): boolean
			return #at(r) > 0
		end,
		pick = function(r: number, rng: Random?): Picked?
			local pool = at(r)
			if #pool == 0 then
				return nil
			end
			local i = if rng then rng:NextInteger(1, #pool) else math.random(1, #pool)
			local e = pool[i]
			return { kind = e.kind, id = e.id, rarity = e.rarity }
		end,
	}
end

-- Per-gun shop wraps for one profile. The rarity is the GUN's: an owned gun of that rarity, weighted by how many
-- shop wraps it is missing (a gun with all of them is never picked), then one of the wraps it lacks by `wrapWeight`.
function MixedRoll.wraps(profile: any, weight: number, wrapWeight: (string) -> number): Category
	local function guns(r: number): { { id: string, missing: { Wraps.Wrap } } }
		local out = {}
		local owned = if profile and profile.weapons then profile.weapons else {}
		-- Sorted ids so a seeded roll is repeatable.
		local ids = {}
		for weaponId in owned do
			table.insert(ids, weaponId)
		end
		table.sort(ids)
		for _, weaponId in ids do
			local w = Weapons.ById[weaponId]
			if w and w.rarity == r then
				local missing = Wraps.missingOn(profile, weaponId)
				if #missing > 0 then
					table.insert(out, { id = weaponId, missing = missing })
				end
			end
		end
		return out
	end
	return {
		id = "wrap",
		weight = weight,
		has = function(r: number): boolean
			return #guns(r) > 0
		end,
		pick = function(r: number, rng: Random?): Picked?
			local gun = MixedRoll.weighted(guns(r), function(g): number
				return #g.missing
			end, rng)
			if not gun then
				return nil
			end
			local wrap = MixedRoll.weighted(gun.missing, function(w: Wraps.Wrap): number
				return wrapWeight(w.id)
			end, rng) or gun.missing[1]
			return { kind = "wrap", id = wrap.id, rarity = r, on = gun.id }
		end,
	}
end

-- Nothing at all (a chance-based roll's miss): always available at the given rarities.
function MixedRoll.none(weight: number, rarities: { number }?): Category
	return {
		id = "none",
		weight = weight,
		rarities = rarities or { 1 },
		has = function(_r: number): boolean
			return true
		end,
		pick = function(_r: number, _rng: Random?): Picked?
			return nil
		end,
	}
end

return MixedRoll
