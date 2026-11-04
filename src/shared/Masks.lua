--!strict
-- Avatar masks. A mask is a head recolor plus a simple accessory Part welded to the head (`shape` is the
-- geometry it draws), worn in the hub and carried into the run. `type` is the Roblox avatar category it
-- would be sold under (Head or Face accessory) and `rarity` colors its tile. `default` is owned by every
-- fresh profile.
export type Mask = {
	id: string,
	name: string,
	color: string, -- hex, head recolor and accessory color
	type: string, -- Head | Face (the UGC accessory category)
	shape: string, -- visor | bandana | none (what the accessory Part looks like)
	rarity: number, -- 1..5, Rarity.Colors
	saleType: string, -- Direct | Crate | Event
	price: number?, -- nil = Prices.mask
}

local Masks = {}

Masks.List = {
	{
		id = "default",
		name = "Plain",
		color = "F2E6C8",
		type = "Head",
		shape = "none",
		rarity = 1,
		saleType = "Direct",
	},
	{
		id = "red",
		name = "Red Bandana",
		color = "E8554D",
		type = "Face",
		shape = "bandana",
		rarity = 1,
		saleType = "Direct",
	},
	{
		id = "blue",
		name = "Blue Visor",
		color = "4D9FE8",
		type = "Face",
		shape = "visor",
		rarity = 2,
		saleType = "Direct",
	},
	{
		id = "green",
		name = "Green Bandana",
		color = "8FE3A1",
		type = "Face",
		shape = "bandana",
		rarity = 2,
		saleType = "Direct",
	},
	{
		id = "gold",
		name = "Gold Visor",
		color = "E8B64C",
		type = "Face",
		shape = "visor",
		rarity = 3,
		saleType = "Direct",
	},
	{
		id = "purple",
		name = "Purple Visor",
		color = "A864E8",
		type = "Face",
		shape = "visor",
		rarity = 4,
		saleType = "Direct",
	},
	{
		id = "crate",
		name = "Chrome Visor",
		color = "C8D0DA",
		type = "Face",
		shape = "visor",
		rarity = 4,
		saleType = "Crate",
	},
	{
		id = "event",
		name = "Night Bandana",
		color = "23232B",
		type = "Head",
		shape = "bandana",
		rarity = 5,
		saleType = "Event",
	},
} :: { Mask }

Masks.ById = {} :: { [string]: Mask }
for _, m in Masks.List do
	Masks.ById[m.id] = m
end

Masks.Default = "default"

return Masks
