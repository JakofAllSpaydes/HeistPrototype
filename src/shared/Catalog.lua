--!strict
-- Brief 10: the item catalog views that cross weapons and masks. The daily crate rolls from the normal unlockable
-- pool: every gun and mask whose `saleType` is Direct (the Gold-priced Armory / Locker items). Crate, Event, Bundle,
-- VIP and Pass items are exclusives and never drop from it; nor do the always-owned defaults (the starter guns and
-- the plain mask), which could only ever be duplicates. `saleType` is the catalog's existing source tag, so no new
-- field was added.
local Weapons = require(script.Parent.Weapons)
local Masks = require(script.Parent.Masks)

export type Item = { kind: string, id: string, rarity: number }

local Catalog = {}

local alwaysOwned: { [string]: boolean } = { [Weapons.Starter] = true }
for _, id in Weapons.DefaultOwned do
	alwaysOwned[id] = true
end

local pool: { Item }? = nil

-- Every daily-crate item, guns first, in catalog order.
function Catalog.dailyPool(): { Item }
	local cached = pool
	if cached then
		return cached
	end
	local out: { Item } = {}
	for _, w in Weapons.List do
		if w.saleType == "Direct" and not alwaysOwned[w.id] then
			table.insert(out, { kind = "weapon", id = w.id, rarity = w.rarity })
		end
	end
	for _, m in Masks.List do
		if m.saleType == "Direct" and m.id ~= Masks.Default then
			table.insert(out, { kind = "mask", id = m.id, rarity = m.rarity })
		end
	end
	pool = out
	return out
end

-- The pool narrowed to one kind ("weapon" for the first-ever open) and / or one rarity.
function Catalog.dailyItems(kind: string?, rarity: number?): { Item }
	local out = {}
	for _, it in Catalog.dailyPool() do
		if (kind == nil or it.kind == kind) and (rarity == nil or it.rarity == rarity) then
			table.insert(out, it)
		end
	end
	return out
end

return Catalog
