--!strict
-- Generates src/map/Room.model.json from Config: the arena (brief 8: the hub is the warehouse, Workspace.Hub; the
-- yard, its stations, props, tier pad, queue pad, planning table and the arena door are gone).
-- Run with: lune run tools/genmap.luau   (then let Rojo sync, or `rojo build`)
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")
local process = require("@lune/process")

-- Config.lua uses Roblox datatypes (Vector2 / Vector3 / CFrame) that Lune's plain Luau does not have. Load it
-- with stubs; the generator only reads plain numbers out of it.
local function vec(...: number)
	return { ... }
end
local Config = luau.load(fs.readFile("src/shared/Config.lua"), {
	debugName = "Config",
	environment = { Vector2 = { new = vec }, Vector3 = { new = vec }, CFrame = { new = vec } },
})() :: any

type Child = { name: string, className: string, properties: { [string]: any }, children: { Child }? }

local children: { Child } = {}

local IDENTITY = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }

-- Rotation about Y so the part's front (-Z) turns by `yaw` degrees.
local function yawMatrix(yawDeg: number): { { number } }
	local r = math.rad(yawDeg)
	local c, s = math.cos(r), math.sin(r)
	return { { c, 0, s }, { 0, 1, 0 }, { -s, 0, c } }
end

local function cframe(pos: { number }, yawDeg: number?): { [string]: any }
	return { CFrame = { position = pos, orientation = if yawDeg then yawMatrix(yawDeg) else IDENTITY } }
end

local function part(
	name: string,
	size: { number },
	pos: { number },
	color: { number },
	material: string,
	extra: { [string]: any }?,
	parent: { Child }?
): Child
	local props: { [string]: any } = {
		Size = size,
		CFrame = cframe(pos, if extra then extra.Yaw else nil),
		Color = color,
		Material = material,
		Anchored = true,
		TopSurface = "Smooth",
		BottomSurface = "Smooth",
	}
	if extra then
		for k, v in extra do
			if k ~= "Yaw" then
				props[k] = v
			end
		end
	end
	local c: Child = { name = name, className = "Part", properties = props }
	table.insert(parent or children, c)
	return c
end

local size = Config.RoomSize
local wallH = Config.WallHeight
local half = size / 2
local floorTop = Config.FloorTop -- floor-level props sit on this; walls and pillars still start at y = 0
local dark = { 0.17, 0.17, 0.2 }
local darker = { 0.13, 0.13, 0.16 }
local amber = { 0.91, 0.71, 0.3 }

------------------------------------------------------------------ Arena
-- Floor: 2 studs thick, top face at FloorTop (above the default Baseplate's top at y = 0, so no z-fighting).
part("Floor", { size, 2, size }, { 0, floorTop - 1, 0 }, darker, "Concrete")
part("WallE", { 1, wallH, size + 2 }, { half + 0.5, wallH / 2, 0 }, dark, "Concrete")
part("WallW", { 1, wallH, size + 2 }, { -half - 0.5, wallH / 2, 0 }, dark, "Concrete")

-- South wall: solid (runs start from the warehouse hub; the van drives in from the Van node below).
part("WallS", { size + 2, wallH, 1 }, { 0, wallH / 2, half + 0.5 }, dark, "Concrete")

-- North wall carries the vault: two segments round a VaultDoorWidth opening, a heavy door that slides up,
-- an amber frame (the beacon), a VAULT sign, and a VaultSize closet behind it with a ceiling, two light
-- panels and a gas anchor in the ceiling. The server reads every Vault* part by name.
local vs = Config.VaultSize
local vdHalf = Config.VaultDoorWidth / 2
local nSeg = (size + 2) / 2 - vdHalf
local nSegCenter = vdHalf + nSeg / 2
local steel = { 0.27, 0.28, 0.31 }
part("WallN_L", { nSeg, wallH, 1 }, { -nSegCenter, wallH / 2, -half - 0.5 }, dark, "Concrete")
part("WallN_R", { nSeg, wallH, 1 }, { nSegCenter, wallH / 2, -half - 0.5 }, dark, "Concrete")
part("VaultDoor", { Config.VaultDoorWidth, wallH, 1 }, { 0, wallH / 2, -half - 0.5 }, steel, "DiamondPlate")
for _, side in { -1, 1 } do
	part(
		if side < 0 then "VaultBeaconL" else "VaultBeaconR",
		{ 0.5, wallH, 1.4 },
		{ side * (vdHalf + 0.25), wallH / 2, -half - 0.5 },
		amber,
		"Neon",
		{ CanCollide = false }
	)
end
part("VaultSign", { 10, 2, 0.3 }, { 0, wallH - 1.2, -half + 0.2 }, { 0.1, 0.1, 0.12 }, "SmoothPlastic", {
	CanCollide = false,
})
local vFront = -half - 1 -- the closet's open edge, just past the wall
local vCenterZ = vFront - vs / 2
part("VaultFloor", { vs, 2, vs }, { 0, floorTop - 1, vCenterZ }, { 0.11, 0.11, 0.13 }, "Concrete")
part("VaultWallN", { vs + 2, wallH, 1 }, { 0, wallH / 2, vFront - vs - 0.5 }, dark, "Concrete")
part("VaultWallE", { 1, wallH, vs + 1 }, { vs / 2 + 0.5, wallH / 2, vCenterZ - 0.5 }, dark, "Concrete")
part("VaultWallW", { 1, wallH, vs + 1 }, { -vs / 2 - 0.5, wallH / 2, vCenterZ - 0.5 }, dark, "Concrete")
part("VaultCeiling", { vs + 2, 1, vs + 2 }, { 0, wallH + 0.5, vCenterZ - 0.5 }, dark, "Concrete")
for i, sz in { -0.28, 0.28 } do
	local light = part(
		"VaultLight" .. i,
		{ vs * 0.5, 0.2, 4 },
		{ 0, wallH - 0.1, vCenterZ + sz * vs },
		{ 1, 0.95, 0.85 },
		"Neon",
		{ CanCollide = false, Transparency = 0.6 }
	)
	light.children = {
		{
			name = "Light",
			className = "PointLight",
			properties = { Brightness = 2, Range = 30, Color = { 1, 0.95, 0.85 }, Shadows = false, Enabled = false },
		},
	}
end
part("VaultGas", { 1, 1, 1 }, { 0, wallH - 1, vCenterZ }, { 0.5, 0.9, 0.4 }, "Neon", {
	CanCollide = false,
	Transparency = 1,
})
-- Two low shelves along the side walls so the room reads as a vault.
for _, sx in { -1, 1 } do
	part(
		if sx < 0 then "VaultShelfW" else "VaultShelfE",
		{ 2, 3, vs - 6 },
		{ sx * (vs / 2 - 1.5), floorTop + 1.5, vCenterZ - 1 },
		steel,
		"Metal"
	)
end

-- Pillar grid, symmetric, center pillar skipped so the spawn is clear.
local n = Config.PillarGrid
local spacing = size / (n + 1)
local ps = Config.PillarSize
for i = 1, n do
	for j = 1, n do
		local x = (i - (n + 1) / 2) * spacing
		local z = (j - (n + 1) / 2) * spacing
		if math.abs(x) < 0.01 and math.abs(z) < 0.01 then
			continue
		end
		part(string.format("Pillar_%d_%d", i, j), { ps, wallH, ps }, { x, wallH / 2, z }, dark, "Concrete")
	end
end

-- Arena spawn pad: where the van brakes and the crew lines up. Not a SpawnLocation; players spawn in the yard.
part("ArenaSpawn", { 8, 0.4, 8 }, { 0, floorTop + 0.25, 0 }, { 0.31, 0.31, 0.35 }, "SmoothPlastic", {
	CanCollide = false,
	Transparency = 0.6,
})

-- Spawn ring markers.
local count = Config.SpawnPointCount
local radius = math.min(Config.SpawnRingRadius, half - 4)
for k = 1, count do
	local angle = (k - 1) / count * math.pi * 2
	part(
		"SpawnPoint" .. k,
		{ 3, 0.2, 3 },
		{ math.cos(angle) * radius, floorTop + 0.15, math.sin(angle) * radius },
		{ 0.47, 0.16, 0.16 },
		"Neon",
		{
			CanCollide = false,
			Transparency = 0.4,
		}
	)
end

------------------------------------------------------------------ Nodes (brief 8)
-- The run start on the arena: the van brakes on the Van node (just inside the south wall, between the pillar rows,
-- after driving DriveIn studs from behind it) and the crew lines up on the Lineup node facing into the room. Same
-- spec as THE BANK nodes (a Part per node, the type folder, Attributes); hidden when the game runs.
local function nodePart(name: string, pos: { number }, sz: { number }, yawDeg: number, attrs: { [string]: any }): Child
	local c = part(name, sz, pos, { 0.61, 0.63, 0.66 }, "SmoothPlastic", {
		Yaw = yawDeg,
		CanCollide = false,
		CanTouch = false,
		CastShadow = false,
		Transparency = 0.55,
	}, {});
	(c :: any).attributes = attrs
	return c
end
table.insert(children, {
	name = "Nodes",
	className = "Folder",
	properties = {},
	children = {
		{
			name = "Van",
			className = "Folder",
			properties = {},
			children = { nodePart("van", { 40, floorTop, 83 }, { 11, 9, 25 }, 90, { DriveIn = 50 }) },
		},
		{
			name = "Lineup",
			className = "Folder",
			properties = {},
			children = { nodePart("lineup", { 16.7, floorTop, 78 }, { 2, 1, 2 }, 0, {}) },
		},
	},
})

local model = { className = "Folder", children = children }
local json = serde.encode("json", model, true)
fs.writeDir("src/map")
fs.writeFile("src/map/Room.model.json", json .. "\n")
print(string.format("Wrote src/map/Room.model.json with %d top-level instances", #children))
process.exit(0)
