--!strict
-- Where bags can land. Arena: twelve floor spots between the pillar rows (tagged Parts in the real map
-- later). Vault: a grid inside the vault closet on the north wall. Everything derives from Config so the
-- map generator and the server agree.
local Config = require(script.Parent.Config)

local BagSpots = {}

local y = Config.FloorTop
local spacing = Config.RoomSize / (Config.PillarGrid + 1)
local half = spacing / 2

-- Midpoints of the pillar grid's cells, one ring in from the walls: (±1.5, ±1.5), (±1.5, ±0.5), (±0.5, ±1.5) cells.
BagSpots.Arena = {} :: { Vector3 }
for _, sx in { -1, 1 } do
	for _, sz in { -1, 1 } do
		table.insert(BagSpots.Arena, Vector3.new(sx * spacing * 1.5, y, sz * spacing * 1.5))
		table.insert(BagSpots.Arena, Vector3.new(sx * spacing * 1.5, y, sz * half))
		table.insert(BagSpots.Arena, Vector3.new(sx * half, y, sz * spacing * 1.5))
	end
end

-- Inside the vault: two columns, VaultBagSpots / 2 rows deep.
BagSpots.Vault = {} :: { Vector3 }
local front = -(Config.RoomSize / 2 + 1) -- the closet starts just past the north wall
local rows = math.max(1, math.ceil(Config.VaultBagSpots / 2))
local depth = Config.VaultSize - 7 -- rows stop short of the back wall
for r = 1, rows do
	local z = front - 3 - (r - 1) * (depth / math.max(rows - 1, 1))
	for _, sx in { -1, 1 } do
		if #BagSpots.Vault < Config.VaultBagSpots then
			table.insert(BagSpots.Vault, Vector3.new(sx * Config.VaultSize / 4, y, z))
		end
	end
end

return BagSpots
