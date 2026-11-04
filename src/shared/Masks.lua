--!strict
-- Avatar masks. A mask is a head recolor plus a simple face accessory Part welded to the head (shape
-- per mask), worn in the hub and carried into the run. `default` is owned by every fresh profile.
export type Mask = {
	id: string,
	name: string,
	color: string, -- hex, head recolor and accessory color
	shape: string, -- visor | bandana | none
	saleType: string, -- Direct | Crate | Event
	price: number?, -- nil = Prices.mask
}

local Masks = {}

Masks.List = {
	{ id = "default", name = "Plain", color = "F2E6C8", shape = "none", saleType = "Direct" },
	{ id = "red", name = "Red Bandana", color = "E8554D", shape = "bandana", saleType = "Direct" },
	{ id = "blue", name = "Blue Visor", color = "4D9FE8", shape = "visor", saleType = "Direct" },
	{ id = "green", name = "Green Bandana", color = "8FE3A1", shape = "bandana", saleType = "Direct" },
	{ id = "gold", name = "Gold Visor", color = "E8B64C", shape = "visor", saleType = "Direct" },
	{ id = "purple", name = "Purple Visor", color = "A864E8", shape = "visor", saleType = "Direct" },
	{ id = "crate", name = "Chrome Visor", color = "C8D0DA", shape = "visor", saleType = "Crate" },
	{ id = "event", name = "Night Bandana", color = "23232B", shape = "bandana", saleType = "Event" },
} :: { Mask }

Masks.ById = {} :: { [string]: Mask }
for _, m in Masks.List do
	Masks.ById[m.id] = m
end

Masks.Default = "default"

return Masks
