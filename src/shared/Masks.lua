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
	shape: string, -- what the accessory looks like (MaskShapes.lua): visor | bandana | none | goggles | skull | halfmask | mono | horns | helmet | crown | hood
	accent: string?, -- hex, a second color some shapes use (lenses, eye holes, trim)
	rarity: number, -- 1..5, Rarity.Colors
	saleType: string, -- Direct | Crate | Event | Bundle | VIP | Pass | Relic (brief 13: gun-crate drops only)
	price: number?, -- nil = Prices.mask
	map: string?, -- brief 13: a relic's map
	relic: boolean?, -- brief 13: a relic (Relics.lua)
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
	-- Brief 6: the MASK CRATE pool (Crates.lua), never Gold-priced.
	{
		id = "c_grin",
		name = "Grin Plate",
		color = "E9E2D0",
		accent = "2A2A2E",
		type = "Face",
		shape = "halfmask",
		rarity = 1,
		saleType = "Crate",
	},
	{
		id = "c_camo",
		name = "Camo Wrap",
		color = "5E6B3A",
		type = "Face",
		shape = "bandana",
		rarity = 1,
		saleType = "Crate",
	},
	{
		id = "c_aviator",
		name = "Aviator Goggles",
		color = "6B4A2B",
		accent = "F2A33C",
		type = "Face",
		shape = "goggles",
		rarity = 2,
		saleType = "Crate",
	},
	{
		id = "c_hockey",
		name = "Hockey Mask",
		color = "F2F0E8",
		accent = "B0242B",
		type = "Face",
		shape = "skull",
		rarity = 2,
		saleType = "Crate",
	},
	{
		id = "c_neon",
		name = "Neon Slit",
		color = "1C2230",
		accent = "35E8FF",
		type = "Face",
		shape = "mono",
		rarity = 3,
		saleType = "Crate",
	},
	{
		id = "c_ram",
		name = "Ram Horns",
		color = "3A3A40",
		accent = "D9CBA8",
		type = "Head",
		shape = "horns",
		rarity = 3,
		saleType = "Crate",
	},
	{
		id = "c_chrome",
		name = "Chrome Dome",
		color = "C8D0DA",
		accent = "7FE3FF",
		type = "Head",
		shape = "helmet",
		rarity = 4,
		saleType = "Crate",
	},
	{
		id = "c_king",
		name = "Heist King",
		color = "2A1A10",
		accent = "F2A33C",
		type = "Head",
		shape = "crown",
		rarity = 5,
		saleType = "Crate",
	},
	-- Brief 6: VIP (kept after a cancel), the MARKSMAN SET bundle, and the battle pass (PassSeason.lua).
	{
		id = "vip_gold",
		name = "VIP Gold Trim",
		color = "141418",
		accent = "F2C14E",
		type = "Face",
		shape = "visor",
		rarity = 5,
		saleType = "VIP",
	},
	{
		id = "b_ghillie",
		name = "Ghillie Hood",
		color = "4C5A2E",
		accent = "2B3318",
		type = "Head",
		shape = "hood",
		rarity = 3,
		saleType = "Bundle",
	},
	{
		id = "p_tiger",
		name = "Tiger Stripe",
		color = "E8792A",
		accent = "1A1A1E",
		type = "Face",
		shape = "bandana",
		rarity = 2,
		saleType = "Pass",
	},
	{
		id = "p_static",
		name = "Static Visor",
		color = "23232B",
		accent = "B8FF5C",
		type = "Face",
		shape = "mono",
		rarity = 3,
		saleType = "Pass",
	},
	{
		id = "p_phantom",
		name = "Phantom",
		color = "1A1024",
		accent = "B46CFF",
		type = "Face",
		shape = "skull",
		rarity = 5,
		saleType = "Pass",
	},
	{
		id = "p_frostbite",
		name = "Frostbite",
		color = "DDF4FF",
		accent = "4DB8FF",
		type = "Face",
		shape = "goggles",
		rarity = 5,
		saleType = "Pass",
	},
} :: { Mask }

-- Brief 13: the relic masks (Relics.lua) are mask rows too, saleType "Relic" (never sold anywhere).
for _, r in require(script.Parent.Relics).List do
	if r.kind == "mask" then -- Round 30d: relics can be other kinds later
		table.insert(Masks.List, r :: any)
	end
end

Masks.ById = {} :: { [string]: Mask }
for _, m in Masks.List do
	Masks.ById[m.id] = m
end

Masks.Default = "default"

return Masks
