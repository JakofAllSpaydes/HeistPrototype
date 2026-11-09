--!strict
-- Brief 10: the item catalog views that cross weapons and masks. The daily crate rolls from the normal unlockable
-- pool: every gun and mask whose `saleType` is Direct (the Gold-priced Armory / Locker items). Crate, Event, Bundle,
-- VIP and Pass items are exclusives and never drop from it. Round 27d: the default gun of each category (M1911, UZI,
-- AK-47, SPAS-12, AWP, M249: the Commons of the other weapon types) is in the pool too, so the Common band is wide;
-- only the plain mask stays out. `saleType` is the catalog's existing source tag, so no new field was added.
local Weapons = require(script.Parent.Weapons)
local Masks = require(script.Parent.Masks)

export type Item = { kind: string, id: string, rarity: number }

local Catalog = {}

local pool: { Item }? = nil

-- Every daily-crate item, guns first, in catalog order.
function Catalog.dailyPool(): { Item }
	local cached = pool
	if cached then
		return cached
	end
	local out: { Item } = {}
	for _, w in Weapons.List do
		if w.saleType == "Direct" then
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
