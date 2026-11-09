--!strict
-- Weapon wraps: a Color3 swap on the gun's wrappable parts, equipped per weapon id. Owned once, applied to
-- any owned weapon. Brief 6 adds rarity (the tile color), an acquisition saleType and an optional material
-- (the Legendary pass wraps glow).
export type Wrap = {
	id: string,
	name: string,
	color: string,
	rarity: number, -- 1..5 (default 1)
	saleType: string, -- Direct | Mastery | Bundle | Pass (default Direct)
	material: string?, -- an Enum.Material name for the grip (default SmoothPlastic)
}

local Wraps = {}

Wraps.List = {
	{ id = "crimson", name = "Crimson", color = "C8323C" },
	{ id = "arctic", name = "Arctic", color = "DDE6EE" },
	{ id = "jade", name = "Jade", color = "3FA873" },
	{ id = "royal", name = "Royal", color = "4D5FE8", rarity = 2 },
	{ id = "gold", name = "Gold Leaf", color = "E8B64C", rarity = 3 },
	{ id = "void", name = "Void", color = "1A1A20", rarity = 2 },
	-- Mastery wraps (brief 5, Config.MasteryWrapIds): never sold; a weapon's mastery tier unlocks them on that gun.
	{ id = "gunmetal", name = "Gunmetal", color = "5B6169", saleType = "Mastery" },
	{ id = "masterygold", name = "Gold", color = "D9A520", saleType = "Mastery" },
	{ id = "blackred", name = "Black-Red", color = "3A1014", saleType = "Mastery" },
	-- Brief 6: the MARKSMAN SET's Mosin wrap and the battle pass wraps (PassSeason.lua).
	{ id = "b_woodland", name = "Woodland", color = "5C6B3A", rarity = 3, saleType = "Bundle" },
	{ id = "p_carbon", name = "Carbon", color = "2E3138", rarity = 2, saleType = "Pass", material = "DiamondPlate" },
	{ id = "p_tigerwrap", name = "Tiger", color = "E8792A", rarity = 3, saleType = "Pass" },
	{ id = "p_inferno", name = "Inferno", color = "FF5A1F", rarity = 5, saleType = "Pass", material = "Neon" },
	{ id = "p_glacier", name = "Glacier", color = "9FE3FF", rarity = 5, saleType = "Pass", material = "Glass" },
} :: { Wrap }

Wraps.ById = {} :: { [string]: Wrap }
for _, w in Wraps.List do
	w.rarity = w.rarity or 1
	w.saleType = w.saleType or "Direct"
	Wraps.ById[w.id] = w
end

-- Round 30d: the shop wraps (saleType Direct) are owned PER GUN: Crimson on the AK and Crimson on the M1911 are
-- two unlocks, priced by the gun's rarity (Prices.wrapByGunRarity). Pass and bundle wraps stay owned once for every
-- gun; mastery wraps belong to the gun whose mastery unlocked them (MasteryCopy, checked by the callers).
-- profile.wraps.owned holds "<weaponId>|<wrapId>" for per-gun wraps and the plain wrap id for the others.
function Wraps.perGun(w: Wrap?): boolean
	return w ~= nil and w.saleType == "Direct"
end

function Wraps.key(weaponId: string, wrapId: string): string
	return weaponId .. "|" .. wrapId
end

-- Is this (non-mastery) wrap owned for this gun?
function Wraps.owns(profile: any, wrapId: string, weaponId: string?): boolean
	local owned = profile and profile.wraps and profile.wraps.owned
	if not owned then
		return false
	end
	local w = Wraps.ById[wrapId]
	if Wraps.perGun(w) then
		return weaponId ~= nil and owned[Wraps.key(weaponId, wrapId)] == true
	end
	return owned[wrapId] == true
end

-- The shop wraps a gun does not have yet (what the daily crate can give it), in list order.
function Wraps.missingOn(profile: any, weaponId: string): { Wrap }
	local out = {}
	for _, w in Wraps.List do
		if Wraps.perGun(w) and not Wraps.owns(profile, w.id, weaponId) then
			table.insert(out, w)
		end
	end
	return out
end

-- The Gold price of a shop wrap on a gun of this rarity.
function Wraps.priceFor(gunRarity: number): number
	local Prices = require(script.Parent.Prices) :: any
	local list = Prices.wrapByGunRarity :: { number }?
	return if list then list[math.clamp(math.floor(gunRarity), 1, #list)] or Prices.wrap else Prices.wrap
end

-- The grip material for a wrap (SmoothPlastic unless the wrap names one).
function Wraps.material(w: Wrap): Enum.Material
	local name = w.material
	if name then
		local ok, m = pcall(function()
			return (Enum.Material :: any)[name]
		end)
		if ok and m then
			return m
		end
	end
	return Enum.Material.SmoothPlastic
end

return Wraps
