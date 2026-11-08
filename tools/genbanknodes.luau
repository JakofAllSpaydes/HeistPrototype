--!strict
-- Brief 7: the first node set for THE BANK, written once to src/map/Bank.nodes.model.json (Rojo maps it to
-- Workspace.Bank.Nodes). After this run the file is maintained in Studio: drag the parts, save the Nodes folder
-- (or the place) as XML, and run `lune run tools/exportnodes.luau <file>`; never edit attributes in the json.
--   lune run tools/genbanknodes.luau
--
-- How it was authored (Nov 2026, from src/map/Bank.rbxm read with Lune and rendered as floor plans):
--   street  y 0.5   grass plaza z -300..-230, road z -217..-150 fenced by the barriers at x = ±142, the bank
--                   steps z -120..-100; side pavements x ±(109..150); the hatch on the east pavement (134, -11).
--   lobby   y 5.5   x ±99.5, z -100..-3.7; front doors x ±8 at z -100; the curved stairs x ±(18.7..68.7),
--                   z -51..-4, arriving on the mezzanine between the newel posts at x ±(52..68), z -3.6.
--   upper   y 35.5  mezzanine z -3.7..23 over the back, side rooms and an office z 23..78.
--   back    y 5.5   the passages under the stairs (x ±(42.7..77.3) at z -3.5, between the mezzanine pillars),
--                   the teller area behind the 4-stud counter (x ±37.3, z -3..5), the side halls and the cross
--                   corridor z 28..61; stairwell openings x ±(50..70), z 54..93.
--   stairs  y -20 / -38.5  stairwells down to corner landings (z 102..122, y -20), double stairs to a centre
--                   landing (y -38.5) and the landing room z 52..101 with the wheel door at z 54.4.
--   vault   y -37.5 the safe-deposit room x ±16, z 15..53; its back wheel door (z 13.4) is the server door.
--   tunnel  y -37.5 server room x -16..40, z -26..11; a wheel door at x 38 (always open), the ramp up to the
--                   tunnel floor (y -24.5), the ladder (TrussPart at x 138.35) to the hatch lid at y 0.45.
-- All coordinates below are THE BANK's own (as the builder placed it); the bake offset (Config.BankOrigin, the
-- import's translation) is added on output so the nodes sit on the imported geometry.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local function vec(...: number)
	return { ... }
end
local Config = luau.load(fs.readFile("src/shared/Config.lua"), {
	debugName = "Config",
	environment = { Vector2 = { new = vec }, Vector3 = { new = vec }, CFrame = { new = vec } },
})() :: any
local O = Config.BankOrigin :: { number }
local OX, OY, OZ = O[1] or 0, O[2] or 0, O[3] or 0

-- Landmarks read from the imported geometry (in baked coordinates, converted back to the bank's own).
local geo = roblox.deserializeModel(fs.readFile("src/map/Bank.rbxm"))[1]
local function find(name: string, near: { number }): { number }
	local best, bestD = nil, math.huge
	for _, d in geo:GetDescendants() do
		if d:IsA("BasePart") and d.Name == name then
			local p = d.CFrame.Position
			local dx, dy, dz = p.X - OX - near[1], p.Y - OY - near[2], p.Z - OZ - near[3]
			local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
			if dist < bestD then
				bestD = dist
				best = { p.X - OX, p.Y - OY, p.Z - OZ }
			end
		end
	end
	assert(best, "landmark not found: " .. name)
	return best :: { number }
end
local vaultFront = find("vaultdoor", { 0.8, -28.6, 54.4 }) -- landing -> vault
local vaultBack = find("vaultdoor", { 0.8, -28.4, 13.4 }) -- vault -> server room
local tunnelDoor = find("vaultdoor", { 38.1, -28.4, -10.4 }) -- server room -> tunnel
local truss = find("Truss", { 138.35, -12.2, -11.15 })
print(
	string.format(
		"[genbanknodes] vault doors at z %.1f / %.1f, tunnel door x %.1f, ladder x %.1f",
		vaultFront[3],
		vaultBack[3],
		tunnelDoor[1],
		truss[1]
	)
)

------------------------------------------------------------------ model.json helpers
local function yaw(deg: number): { { number } }
	local r = math.rad(deg)
	local c, s = math.cos(r), math.sin(r)
	local function clean(v: number): number
		return if math.abs(v) < 1e-9 then 0 else math.round(v * 1e6) / 1e6
	end
	return { { clean(c), 0, clean(s) }, { 0, 1, 0 }, { clean(-s), 0, clean(c) } }
end

-- facing: yaw in degrees; 0 faces -Z (toward the street), 180 faces +Z (into the bank), 90 faces -X, -90 faces +X.
local function node(name: string, pos: { number }, size: { number }, facing: number?, attrs: { [string]: any }?): any
	local p = { pos[1] + OX, pos[2] + OY, pos[3] + OZ }
	return {
		name = name,
		className = "Part",
		properties = {
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Transparency = 1,
			Size = size,
			CFrame = { CFrame = { position = p, orientation = yaw(facing or 0) } },
		},
		attributes = attrs or {},
	}
end

local function folder(name: string, tag: string, children: { any }): any
	for _, c in children do
		c.properties.Tags = { tag }
	end
	return { name = name, className = "Folder", children = children }
end

local function both(
	name: string,
	x: number,
	y: number,
	z: number,
	size: { number },
	facing: number,
	attrs: any
): (any, any)
	local l = node(name .. "_l", { -x, y, z }, size, facing, table.clone(attrs))
	local mirrored = if facing == 90 then -90 elseif facing == -90 then 90 else facing
	local r = node(name .. "_r", { x, y, z }, size, mirrored, table.clone(attrs))
	return l, r
end

------------------------------------------------------------------ Zones (a zone is the union of its parts)
local zones = {}
local function zone(name: string, depth: number, label: string, pos: { number }, size: { number })
	table.insert(zones, node(name, pos, size, 0, { Depth = depth, Label = label }))
end
-- Street: the plaza, road and grass in front, the side pavements, the strip behind.
zone("street", 1, "STREET", { 0, 19, -212 }, { 300, 42, 224 })
zone("street", 1, "STREET", { -129.5, 19, 0 }, { 41, 42, 200 })
zone("street", 1, "STREET", { 129.5, 19, 0 }, { 41, 42, 200 })
zone("street", 1, "STREET", { 0, 19, 115 }, { 300, 42, 30 })
-- Lobby: the double-height ground floor in front of the counter, stairs included.
zone("lobby", 2, "LOBBY", { 0, 33, -51.85 }, { 199, 58, 96.3 })
-- Upper floor: mezzanine and the rooms off it.
zone("upper", 3, "UPPER FLOOR", { 0, 47.5, 37.15 }, { 199, 25, 81.7 })
-- Back of bank: passages, teller area, side halls, cross corridor; the side halls run on past the back rooms.
zone("back", 3, "BACK OF BANK", { 0, 19.75, 28.65 }, { 199, 28.5, 64.7 })
zone("back", 3, "BACK OF BANK", { -69.75, 19.75, 80.5 }, { 59.5, 28.5, 39 })
zone("back", 3, "BACK OF BANK", { 69.75, 19.75, 80.5 }, { 59.5, 28.5, 39 })
-- Vault stairs: both stairwells, the corner landings, the centre stairs and the landing room.
zone("stairs", 4, "VAULT STAIRS", { -60, -8.3, 88 }, { 22, 27.4, 70 })
zone("stairs", 4, "VAULT STAIRS", { 60, -8.3, 88 }, { 22, 27.4, 70 })
zone("stairs", 4, "VAULT STAIRS", { 0, -27.5, 111.5 }, { 142, 25, 23 })
zone("stairs", 4, "VAULT STAIRS", { 0, -20, 77 }, { 100, 40, 49 })
-- Vault room (also the VaultRoom node's volume).
zone("vault", 5, "VAULT", { 0, -28.5, 34 }, { 33, 21, 38 })
-- Server room + tunnel: the server room, the ramp and tunnel, the ladder shaft and the hatch top.
zone("tunnel", 6, "TUNNEL", { 12, -28.5, -8 }, { 57, 21, 38 })
zone("tunnel", 6, "TUNNEL", { 94, -19.5, -12 }, { 108, 39, 30 })
zone("tunnel", 6, "TUNNEL", { 132, 4, -11 }, { 12, 8, 12 })

------------------------------------------------------------------ Doors
local doors = {}
local function door(name: string, pos: { number }, size: { number }, facing: number, attrs: any)
	table.insert(doors, node(name, pos, size, facing, attrs))
end
local base = { InteractTime = 3, CashReward = 400 }
local function attrs(extra: { [string]: any }): { [string]: any }
	local t = table.clone(base)
	for k, v in extra do
		t[k] = v
	end
	return t
end
-- D1 front doors: the double door in the facade, a locked panel until wave 3.
door(
	"D1_front",
	{ 0, 14.3, -100.9 },
	{ 16, 17.5, 1 },
	0,
	attrs({
		Group = "D1",
		Opens = "lobby",
		TriggerWave = 3,
		DoorStyle = "panel",
		PingText = "OPEN THE BANK",
		Label = "FRONT DOORS",
		Priority = 1,
	})
)
-- D2 stair chains: across each stair's arrival on the mezzanine, between the newel posts.
local d2 = attrs({
	Group = "D2",
	Opens = "upper",
	TriggerWave = 8,
	DoorStyle = "chain",
	PingText = "CUT THE CHAINS",
	Label = "STAIR CHAINS",
	Priority = 3,
})
local d2l, d2r = both("D2_stair", 60.2, 38, -3.6, { 16, 3, 0.6 }, 0, d2)
table.insert(doors, d2l)
table.insert(doors, d2r)
-- D3 shutters: one in each passage under the stairs, and the counter grille (the 4-stud counter is a hop).
local d3 = attrs({
	Group = "D3",
	Opens = "back,stairs",
	TriggerWave = 6,
	DoorStyle = "shutter",
	PingText = "RAISE THE SHUTTERS",
	Label = "SHUTTERS",
	Priority = 2,
})
local d3l, d3r = both("D3_passage", 60, 14.6, -3.5, { 34.6, 18.2, 1 }, 0, d3)
table.insert(doors, d3l)
table.insert(doors, d3r)
door("D3_counter", { 0, 14.6, -3.6 }, { 74.6, 18.2, 0.6 }, 0, table.clone(d3))
-- D4: the wheel door onto the vault (the vault job's Safe dial) and the server door behind it, same group.
local d4 = { Group = "D4", TriggerWave = 0, DoorStyle = "wheel", Mesh = "vault", CashReward = 0, Priority = 4 }
door(
	"D4_vault",
	{ vaultFront[1] - 0.8, vaultFront[2], vaultFront[3] },
	{ 20, 18, 3 },
	0,
	(function()
		local t = table.clone(d4)
		t.Opens = "vault"
		t.Label = "VAULT DOOR"
		return t
	end)()
)
door(
	"D4_server",
	{ vaultBack[1] - 0.8, vaultBack[2], vaultBack[3] },
	{ 20, 18, 3 },
	0,
	(function()
		local t = table.clone(d4)
		t.Opens = "tunnel"
		t.Label = "SERVER ROOM"
		return t
	end)()
)
-- The server room's own wheel door onto the tunnel: dressing, swung open on load (TriggerWave -1).
door("T1_tunnel", { tunnelDoor[1], tunnelDoor[2], tunnelDoor[3] - 0.8 }, { 3, 18, 20 }, 0, {
	Group = "T1",
	Opens = "tunnel",
	TriggerWave = -1,
	DoorStyle = "wheel",
	Mesh = "vault",
	Label = "TUNNEL DOOR",
})

------------------------------------------------------------------ Spawn boxes (behind visible mouths)
local boxes = {}
local function box(name: string, pos: { number }, size: { number }, a: { [string]: any })
	a.Weight = a.Weight or 1
	a.AllowedTypes = a.AllowedTypes or "all"
	a.RequiresDoor = a.RequiresDoor or ""
	table.insert(boxes, node(name, pos, size, 0, a))
end
box("street_west", { -165, 3.5, -183 }, { 20, 6, 60 }, { Zone = "street", MouthName = "west fence" })
box("street_east", { 165, 3.5, -183 }, { 20, 6, 60 }, { Zone = "street", MouthName = "east fence" })
box("lobby_front", { 0, 3.5, -130 }, { 30, 6, 14 }, { Zone = "lobby", RequiresDoor = "D1", MouthName = "front doors" })
box(
	"lobby_win_l",
	{ -104, 8.5, -60 },
	{ 6, 6, 36 },
	{ Zone = "lobby", RequiresDoor = "D1", MouthName = "west bay window" }
)
box(
	"lobby_win_r",
	{ 104, 8.5, -60 },
	{ 6, 6, 36 },
	{ Zone = "lobby", RequiresDoor = "D1", MouthName = "east bay window" }
)
local balcony = "Henchman,Runner,Marksman"
box("upper_win_l", { -104, 39.5, 50 }, { 6, 6, 36 }, {
	Zone = "upper",
	RequiresDoor = "D2",
	AllowedTypes = balcony,
	MouthName = "west mezzanine window",
})
box("upper_win_r", { 104, 39.5, 50 }, { 6, 6, 36 }, {
	Zone = "upper",
	RequiresDoor = "D2",
	AllowedTypes = balcony,
	MouthName = "east mezzanine window",
})
box(
	"back_service",
	{ -86, 8.5, 92 },
	{ 18, 6, 10 },
	{ Zone = "back", RequiresDoor = "D3", MouthName = "service corner" }
)
box("back_win_l", { -104, 8.5, 50 }, { 6, 6, 36 }, { Zone = "back", RequiresDoor = "D3", MouthName = "west back bay" })
box("back_win_r", { 104, 8.5, 50 }, { 6, 6, 36 }, { Zone = "back", RequiresDoor = "D3", MouthName = "east back bay" })
box(
	"stairs_top_l",
	{ -60, 8.5, 57 },
	{ 16, 6, 5 },
	{ Zone = "stairs", RequiresDoor = "D3", MouthName = "west stairwell head" }
)
box(
	"stairs_top_r",
	{ 60, 8.5, 57 },
	{ 16, 6, 5 },
	{ Zone = "stairs", RequiresDoor = "D3", MouthName = "east stairwell head" }
)
box("vault_vent", { 0, -34.5, 20 }, { 12, 6, 6 }, {
	Zone = "vault",
	RequiresDoor = "D4",
	WhileVault = true,
	AllowedTypes = "Henchman,Runner",
	MouthName = "vault vent",
})
box("tunnel_far", { 141, -21.5, -20 }, { 8, 6, 10 }, {
	Zone = "tunnel",
	RequiresDoor = "D4",
	WhileVault = true,
	MouthName = "tunnel end",
})
box("hatch_yard", { 128.5, 3.5, -11 }, { 3, 6, 10 }, {
	Zone = "tunnel",
	RequiresDoor = "D4",
	DoorEver = true, -- stays on once the hatch has opened (the lid is one-way by then)
	MouthName = "hatch",
})

------------------------------------------------------------------ Bag spots
local bags = {}
local function bag(name: string, zoneId: string, pos: { number }, gold: boolean)
	table.insert(bags, node(name, pos, { 2, 2, 2 }, 0, { Zone = zoneId, Gold = gold }))
end
bag("street_grass_w", "street", { -70, 1.5, -265 }, true)
bag("street_grass_e", "street", { 70, 1.5, -265 }, false)
bag("street_steps_w", "street", { -90, 1.5, -130 }, false)
bag("street_steps_e", "street", { 90, 1.5, -130 }, true)
bag("street_pavement_e", "street", { 125, 1.5, 40 }, false)
bag("lobby_bay_w", "lobby", { -80, 6.5, -85 }, false)
bag("lobby_bay_e", "lobby", { 80, 6.5, -85 }, true)
bag("lobby_stairs", "lobby", { 0, 6.5, -30 }, false)
bag("lobby_counter", "lobby", { -60, 6.5, -15 }, false)
bag("lobby_side_e", "lobby", { 88, 6.5, -25 }, true)
bag("upper_rail_w", "upper", { -20, 37.5, 6 }, false)
bag("upper_rail_e", "upper", { 20, 37.5, 6 }, true)
bag("upper_room_w", "upper", { -70, 37.5, 50 }, true)
bag("upper_room_e", "upper", { 70, 37.5, 50 }, false)
bag("back_hall_w", "back", { -70, 6.5, 10 }, false)
bag("back_hall_e", "back", { 70, 6.5, 10 }, true)
bag("back_corridor_w", "back", { -88, 6.5, 45 }, false)
bag("back_corridor_e", "back", { 88, 6.5, 45 }, false)
bag("back_teller", "back", { 0, 6.5, 14 }, true)
bag("stairs_landing_w", "stairs", { -30, -37.5, 75 }, false)
bag("stairs_landing_e", "stairs", { 30, -37.5, 75 }, true)
bag("stairs_lower", "stairs", { 0, -37.5, 112 }, false)
for i, p in { { -8, 20 }, { 8, 20 }, { -8, 29 }, { 8, 29 }, { -8, 38 }, { 8, 38 }, { -8, 47 }, { 8, 47 } } do
	bag("vault_aisle" .. i, "vault", { p[1], -36.5, p[2] }, true)
end
bag("tunnel_server", "tunnel", { 0, -36.5, -15 }, false)
bag("tunnel_server_e", "tunnel", { 25, -36.5, -20 }, true)
bag("tunnel_ramp", "tunnel", { 100, -27, -11 }, false)
bag("tunnel_end", "tunnel", { 140, -23.5, -20 }, true)

------------------------------------------------------------------ Job spots
local jobs = {}
local function job(name: string, zoneId: string, pos: { number }, facing: number, pool: string, label: string)
	table.insert(jobs, node(name, pos, { 2, 2, 2 }, facing, { Zone = zoneId, Pool = pool, Label = label }))
end
job("teller_counter", "lobby", { 0, 6.5, -14 }, 180, "keypad,hack", "TELLER COUNTER")
job("mezzanine_office", "upper", { 0, 37.5, 50 }, 0, "lockpick,charges", "OFFICE")
job("electrical_panel", "back", { -90, 6.5, 45 }, -90, "hotwire,freq", "ELECTRICAL")
job("vault_landing", "stairs", { 0, -37.5, 80 }, 180, "capture", "VAULT LANDING")
job("server_room", "tunnel", { 10, -36.5, -10 }, 0, "hack,freq", "SERVER ROOM")
job("street_road", "street", { 0, 1.5, -183 }, 180, "capture", "THE STREET")

------------------------------------------------------------------ Boss walls (facing into the zone)
local walls = {
	node("street_fence_w", { -142, 6.5, -183 }, { 2, 12, 30 }, -90, { Zone = "street" }),
	node("lobby_side_w", { -99, 14.5, -20 }, { 2, 18, 20 }, -90, { Zone = "lobby" }),
	node("back_corridor", { 0, 14.5, 60.5 }, { 30, 18, 2 }, 0, { Zone = "back" }),
	node("stairs_blank", { -49.5, -30, 75 }, { 2, 16, 20 }, -90, { Zone = "stairs" }),
	node("tunnel_end", { 147, -18, -11 }, { 2, 12, 20 }, 90, { Zone = "tunnel" }),
}

------------------------------------------------------------------ Dealer spots, van, lineup, hatch, vault room
local dealers = {
	node("dealer_grass", { 0, 1.5, -270 }, { 4, 2, 4 }, 180, { Zone = "street" }),
	node("dealer_lobby", { 0, 6.5, -46 }, { 4, 2, 4 }, 0, { Zone = "lobby" }),
	node("dealer_corridor", { 0, 6.5, 45 }, { 4, 2, 4 }, 0, { Zone = "back" }),
	node("dealer_landing", { 0, -37.5, 72 }, { 4, 2, 4 }, 180, { Zone = "stairs" }),
}
local van = { node("van", { 0, 3.5, -262 }, { 8, 6, 14 }, 180, { LineupOffset = 12 }) }
local lineup = { node("lineup", { 0, 1.5, -238 }, { 20, 2, 4 }, 180, {}) }
-- The ladder link runs from the tunnel floor at the truss to the pavement beside the hole.
local hatch = {
	node("hatch", { 134, 0.7, -11.15 }, { 8, 1.2, 7.8 }, 0, {
		Zone = "tunnel",
		Mesh = "Part",
		MeshMargin = 0,
		LadderBottom = { Vector3 = { truss[1] - 1.6 - 134, -24.5 - 0.7, 0 } },
		LadderTop = { Vector3 = { -5.5, 0, 0 } },
	}),
}
local vaultRoom = { node("vault_room", { 0, -28.5, 34 }, { 33, 21, 38 }, 0, { Door = "D4" }) }

local out = {
	className = "Folder",
	children = {
		folder("Zones", "GHS_Zone", zones),
		folder("Doors", "GHS_Door", doors),
		folder("SpawnBoxes", "GHS_SpawnBox", boxes),
		folder("BagSpots", "GHS_BagSpot", bags),
		folder("JobSpots", "GHS_JobSpot", jobs),
		folder("BossWalls", "GHS_BossWall", walls),
		folder("DealerSpots", "GHS_DealerSpot", dealers),
		folder("Van", "GHS_Van", van),
		folder("Lineup", "GHS_Lineup", lineup),
		folder("Hatch", "GHS_Hatch", hatch),
		folder("VaultRoom", "GHS_VaultRoom", vaultRoom),
	},
}
fs.writeFile("src/map/Bank.nodes.model.json", serde.encode("json", out, true))
local n = 0
for _, f in out.children do
	n += #f.children
end
print(string.format("[genbanknodes] %d nodes -> src/map/Bank.nodes.model.json", n))
