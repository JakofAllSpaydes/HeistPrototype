--!strict
-- Weapon wraps: a Color3 swap on the gun's wrappable parts, equipped per weapon id. Owned once, applied to
-- any owned weapon.
export type Wrap = { id: string, name: string, color: string }

local Wraps = {}

Wraps.List = {
	{ id = "crimson", name = "Crimson", color = "C8323C" },
	{ id = "arctic", name = "Arctic", color = "DDE6EE" },
	{ id = "jade", name = "Jade", color = "3FA873" },
	{ id = "royal", name = "Royal", color = "4D5FE8" },
	{ id = "gold", name = "Gold Leaf", color = "E8B64C" },
	{ id = "void", name = "Void", color = "1A1A20" },
	-- Mastery wraps (brief 5, Config.MasteryWrapIds): never sold; a weapon's mastery tier unlocks them on that gun.
	{ id = "gunmetal", name = "Gunmetal", color = "5B6169" },
	{ id = "masterygold", name = "Gold", color = "D9A520" },
	{ id = "blackred", name = "Black-Red", color = "3A1014" },
} :: { Wrap }

Wraps.ById = {} :: { [string]: Wrap }
for _, w in Wraps.List do
	Wraps.ById[w.id] = w
end

return Wraps
