--!strict
-- Brief 13: relics. Each map owns a small set of ultra-rare masks (Config.RelicsPerMap) that only its gun crates can
-- drop (RelicService.lua). A relic is an ordinary mask everywhere (Masks.List carries these rows, equipped through
-- the profile's masks.equipped by id) except its saleType "Relic" (the catalog's source tag: never sold, never in
-- the store, the daily crate, the pass or a bundle), its `relic` rarity above Legendary and the RELIC tag. They have
-- no stats. The first gun crate a profile opens drops Config.StarterRelic for the whole party (the tutorial), as the
-- first of the guarantees (Relics.guarantees).
-- Placeholder masks in THE BANK's palette until art lands. The Arena has none.
local Config = require(script.Parent.Config)

export type Relic = {
	id: string,
	name: string, -- THE TELLER (the popup's and the rail's name)
	map: string, -- the map whose gun crates drop it
	color: string,
	accent: string?,
	type: string,
	shape: string,
	rarity: number, -- Rarity.Relic
	saleType: string, -- "Relic"
	source: string, -- "relic"
	relic: boolean,
}

local Relics = {}

Relics.RARITY = 6 -- Rarity.Relic (above Legendary)

Relics.List = {
	{
		id = "bank_teller",
		name = "The Teller",
		map = "TheBank",
		color = "C9A46A",
		accent = "3A2A16",
		type = "Face",
		shape = "halfmask",
		rarity = 6,
		saleType = "Relic",
		source = "relic",
		relic = true,
	},
	{
		id = "bank_guard",
		name = "The Guard",
		map = "TheBank",
		color = "2E3B4E",
		accent = "E8B64C",
		type = "Head",
		shape = "helmet",
		rarity = 6,
		saleType = "Relic",
		source = "relic",
		relic = true,
	},
	{
		id = "bank_manager",
		name = "The Manager",
		map = "TheBank",
		color = "1E1A16",
		accent = "E8B64C",
		type = "Face",
		shape = "mono",
		rarity = 6,
		saleType = "Relic",
		source = "relic",
		relic = true,
	},
	{
		id = "bank_vault",
		name = "The Vault",
		map = "TheBank",
		color = "8C9399",
		accent = "FFD36B",
		type = "Head",
		shape = "crown",
		rarity = 6,
		saleType = "Relic",
		source = "relic",
		relic = true,
	},
} :: { Relic }

Relics.ById = {} :: { [string]: Relic }
for _, r in Relics.List do
	Relics.ById[r.id] = r
end

-- A map's relics in list order, at most Config.RelicsPerMap (empty for a map with none).
function Relics.forMap(mapId: string?): { Relic }
	local out = {}
	for _, r in Relics.List do
		if r.map == mapId and #out < Config.RelicsPerMap then
			table.insert(out, r)
		end
	end
	return out
end

-- Guaranteed drops. Each has a stable id that a profile records once it has had it (profile.relics.guarantees), so a
-- guarantee added later still reaches every existing profile on its next qualifying gun crate. The built-in one is
-- `first_crate` (Config.StarterRelic on any map); Config.RelicGuarantees adds more. `map` "" = any map. Never reuse
-- or rename an id: a renamed one would drop again for everyone.
export type Guarantee = { id: string, relic: string, map: string }

function Relics.guarantees(): { Guarantee }
	local out: { Guarantee } = { { id = "first_crate", relic = Config.StarterRelic, map = "" } }
	for _, g in Config.RelicGuarantees :: { any } do
		table.insert(out, { id = tostring(g.id), relic = tostring(g.relic), map = tostring(g.map or "") })
	end
	return out
end

function Relics.isRelic(id: string?): boolean
	return id ~= nil and Relics.ById[id] ~= nil
end

-- THE TELLER
function Relics.title(id: string): string
	local r = Relics.ById[id]
	return if r then string.upper(r.name) else string.upper(id)
end

return Relics
