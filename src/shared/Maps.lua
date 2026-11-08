--!strict
-- The playable maps (brief 7). One row per map: the Create Match card renders the live rows in `sort` order
-- with one COMING SOON filler after them; the server's Room.forMap(id) is the only place positions on a map
-- come from. `root` is the map's folder / model under Workspace; `hasNodes` maps are read from their
-- Workspace.<root>.Nodes parts by MapLoader; `thumb` is an ImageLabel asset id ("" = the colour block with
-- the name, until art lands); `short` is the hub tag's suffix (TOP WAVE 14 ★ BANK).
local Config = require(script.Parent.Config)

export type Map = {
	id: string,
	name: string,
	short: string,
	thumb: string,
	color: string,
	root: string,
	hasNodes: boolean,
	sort: number,
	live: boolean,
}

local Maps = {}

Maps.List = {
	{
		id = "Arena",
		name = "ARENA",
		short = "ARENA",
		thumb = "", -- [IMG: TBA]
		color = "55657A",
		root = "Room",
		hasNodes = false,
		sort = 1,
		live = true,
	},
	{
		id = "TheBank",
		name = "THE BANK",
		short = "BANK",
		thumb = "", -- [IMG: TBA]
		color = "8A6A3A",
		root = "Bank",
		hasNodes = true,
		sort = 2,
		live = false, -- brief 7 step 4 puts it on the card
	},
} :: { Map }

table.sort(Maps.List, function(a, b)
	return a.sort < b.sort
end)

Maps.ById = {} :: { [string]: Map }
for _, m in Maps.List do
	Maps.ById[m.id] = m
end

-- The row for an id; unknown ids fall back to Config.DefaultMap, then the first row.
function Maps.get(id: string?): Map
	return (id and Maps.ById[id]) or Maps.ById[Config.DefaultMap] or Maps.List[1]
end

-- The rows a party can pick, in card order.
function Maps.live(): { Map }
	local out = {}
	for _, m in Maps.List do
		if m.live then
			table.insert(out, m)
		end
	end
	return out
end

-- A pickable id: the given one when it is live, else the default (when live), else the first live row.
function Maps.pickable(id: string?): string
	local m = id and Maps.ById[id]
	if m and m.live then
		return m.id
	end
	local d = Maps.ById[Config.DefaultMap]
	if d and d.live then
		return d.id
	end
	return Maps.live()[1].id
end

return Maps
