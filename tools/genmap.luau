--!strict
-- Generates src/map/Room.model.json from Config: the arena plus the hub yard on its south wall.
-- Run with: lune run tools/genmap.luau   (then let Rojo sync, or `rojo build`)
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")
local process = require("@lune/process")

-- Config.lua uses Roblox datatypes (Vector2 / Vector3) that Lune does not have. Load it with stubs;
-- the generator only reads plain numbers out of it.
local function vec(...: number)
	return { ... }
end
local Config = luau.load(fs.readFile("src/shared/Config.lua"), {
	debugName = "Config",
	environment = { Vector2 = { new = vec }, Vector3 = { new = vec } },
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

-- South wall has the run start door in the middle: two segments and a lit frame.
local doorHalf = Config.DoorWidth / 2
local segment = (size + 2) / 2 - doorHalf
local segCenter = doorHalf + segment / 2
part("WallS_L", { segment, wallH, 1 }, { -segCenter, wallH / 2, half + 0.5 }, dark, "Concrete")
part("WallS_R", { segment, wallH, 1 }, { segCenter, wallH / 2, half + 0.5 }, dark, "Concrete")
for _, side in { -1, 1 } do
	part(
		if side < 0 then "DoorFrameL" else "DoorFrameR",
		{ 0.4, wallH, 1.2 },
		{ side * (doorHalf + 0.2), wallH / 2, half + 0.5 },
		amber,
		"Neon",
		{ CanCollide = false }
	)
end

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

------------------------------------------------------------------ Hub (the yard, south of the arena)
local yw = Config.YardWidth
local yd = Config.YardDepth
local yardNorth = half + 1 -- just past the arena's south wall
local yardZ = yardNorth + yd / 2
local asphalt = { 0.2, 0.2, 0.23 }
local yardWall = { 0.22, 0.22, 0.26 }
local blue = { 0.3, 0.62, 0.91 }
local panelGrey = { 0.26, 0.28, 0.34 }
local labelDark = { 0.1, 0.1, 0.12 }

part("YardFloor", { yw, 2, yd }, { 0, floorTop - 1, yardZ }, asphalt, "Asphalt")
part("YardWallS", { yw + 2, wallH, 1 }, { 0, wallH / 2, yardNorth + yd + 0.5 }, yardWall, "Concrete")
part("YardWallE", { 1, wallH, yd }, { yw / 2 + 0.5, wallH / 2, yardZ }, yardWall, "Concrete")
part("YardWallW", { 1, wallH, yd }, { -yw / 2 - 0.5, wallH / 2, yardZ }, yardWall, "Concrete")

local tableZ = yardZ -- where the table stood; the spawn keeps its spot south of it
table.insert(children, {
	name = "Spawn",
	className = "SpawnLocation",
	properties = {
		Size = { 8, 0.4, 8 },
		CFrame = cframe({ 0, floorTop + 0.25, tableZ + 9 }),
		Color = { 0.31, 0.31, 0.35 },
		Material = "SmoothPlastic",
		Anchored = true,
		CanCollide = false,
		Transparency = 0.6,
		Neutral = true,
		Duration = 0,
		TopSurface = "Smooth",
		BottomSurface = "Smooth",
	},
})

-- Queue zone(s): a QueueZoneSize square pad in front of the arena door with a blue gate frame on its north
-- edge and a billboard anchor above the lintel. The server reads QueueZone<N>, QueueGate<N> and QueueBillboard<N>.
local qz = Config.QueueZoneSize
for i = 1, Config.QueueZoneCount do
	-- Several zones fan out along the door wall, the first centered on the door.
	local zx = (i - 1 - (Config.QueueZoneCount - 1) / 2) * (qz + 6)
	local zz = yardNorth + 2 + qz / 2
	part("QueueZone" .. i, { qz, 0.2, qz }, { zx, floorTop + 0.1, zz }, blue, "Neon", {
		CanCollide = false,
		Transparency = 0.7,
	})
	for _, sx in { -1, 1 } do
		part(
			string.format("QueueGate%dPost%s", i, if sx < 0 then "L" else "R"),
			{ 0.8, 11, 0.8 },
			{ zx + sx * (qz / 2 - 0.4), 5.5, yardNorth + 2.4 },
			blue,
			"Neon",
			{ CanCollide = false }
		)
	end
	part("QueueGate" .. i, { qz, 0.8, 0.8 }, { zx, 11.4, yardNorth + 2.4 }, blue, "Neon", { CanCollide = false })
	part("QueueBillboard" .. i, { 1, 1, 1 }, { zx, 14.5, yardNorth + 2.4 }, blue, "Neon", {
		CanCollide = false,
		Transparency = 1,
	})
end

-- Lamps in the yard corners so it reads as lit and outside.
for _, sx in { -1, 1 } do
	for _, sz in { 0.12, 0.88 } do
		local x = sx * (yw / 2 - 10)
		local z = yardNorth + yd * sz
		local label = string.format("Lamp_%s_%s", if sx < 0 then "W" else "E", if sz < 0.5 then "N" else "S")
		part(label .. "_Post", { 0.6, 14, 0.6 }, { x, 7, z }, { 0.3, 0.3, 0.34 }, "Metal")
		local head = part(label, { 1.6, 1, 1.6 }, { x, 14.5, z }, { 1, 0.9, 0.7 }, "Neon", { CanCollide = false })
		head.children = {
			{
				name = "Light",
				className = "PointLight",
				properties = { Brightness = 1.5, Range = 70, Color = { 1, 0.9, 0.72 }, Shadows = false },
			},
		}
	end
end

-- Van: a Parts box with wheels, parked beside the planning table facing the arena door (-Z). It only shows
-- inside the start animation (the server parks it away otherwise).
local vanParts: { Child } = {}
local vanX = 14
local vanY = floorTop + 1.4 -- body bottom sits on the wheels, wheels on the floor
part("Body", { 6, 4.2, 11 }, { vanX, vanY + 2.1, yardZ }, { 0.2, 0.24, 0.36 }, "SmoothPlastic", nil, vanParts)
part("Windshield", { 5.4, 1.5, 0.2 }, { vanX, vanY + 3.1, yardZ - 5.45 }, { 0.55, 0.7, 0.85 }, "Glass", {
	CanCollide = false,
	Transparency = 0.3,
}, vanParts)
part(
	"Stripe",
	{ 6.05, 0.5, 8 },
	{ vanX, vanY + 1.4, yardZ + 1 },
	amber,
	"SmoothPlastic",
	{ CanCollide = false },
	vanParts
)
for _, sx in { -1, 1 } do
	part(
		if sx < 0 then "HeadlightL" else "HeadlightR",
		{ 1.2, 0.6, 0.2 },
		{ vanX + sx * 2, vanY + 1, yardZ - 5.55 },
		{ 1, 0.95, 0.8 },
		"Neon",
		{ CanCollide = false },
		vanParts
	)
	for _, sz in { -1, 1 } do
		part(
			string.format("Wheel_%s%s", if sx < 0 then "L" else "R", if sz < 0 then "F" else "B"),
			{ 0.8, 2.2, 2.2 },
			{ vanX + sx * 3.2, floorTop + 1.1, yardZ + sz * 3.6 },
			{ 0.08, 0.08, 0.09 },
			"Rubber",
			{ Shape = "Cylinder", CanCollide = false },
			vanParts
		)
	end
end
table.insert(children, { name = "Van", className = "Model", properties = {}, children = vanParts })

-- Customization stations along the west wall: gun rack (WEAPONS), podium (CLASSES), mask wall (AVATAR).
-- Each is a panel with a floor label in front; the server adds the text and the prompt.
local stationX = -yw / 2 + 1.3
local stationZ0 = yardNorth + 18
local stations = { "WEAPONS", "CLASSES", "AVATAR" }
for i, name in stations do
	local z = stationZ0 + (i - 1) * Config.StationSpacing
	part("Station_" .. name, { 0.6, 7, 7 }, { stationX, 3.5, z }, panelGrey, "Metal")
	part("StationLabel_" .. name, { 7, 0.2, 3 }, { stationX + 5.2, floorTop + 0.1, z }, labelDark, "SmoothPlastic", {
		CanCollide = false,
		Yaw = 90,
	})
	if name == "WEAPONS" then
		-- Rack bars: three gun silhouettes.
		for k = 1, 3 do
			part(
				"RackGun" .. k,
				{ 0.4, 0.5, 2.4 },
				{ stationX + 0.5, 1.6 + k * 1.4, z - 2.2 + (k - 1) * 2.2 },
				{ 0.6, 0.63, 0.66 },
				"Metal",
				{ CanCollide = false }
			)
		end
	elseif name == "CLASSES" then
		part("Podium", { 3, 1.2, 3 }, { stationX + 3, floorTop + 0.6, z }, { 0.3, 0.3, 0.34 }, "Metal")
		part("PodiumTop", { 3.2, 0.2, 3.2 }, { stationX + 3, floorTop + 1.3, z }, amber, "Neon", { CanCollide = false })
	else
		-- Mask wall: a row of small colored cubes.
		local colors = { { 0.91, 0.33, 0.3 }, { 0.3, 0.62, 0.91 }, { 0.56, 0.89, 0.63 }, { 0.91, 0.71, 0.3 } }
		for k, c in colors do
			part(
				"MaskCube" .. k,
				{ 0.5, 1, 1 },
				{ stationX + 0.55, 4.5, z - 2.4 + (k - 1) * 1.6 },
				c,
				"SmoothPlastic",
				{ CanCollide = false }
			)
		end
	end
end

-- Minigame props along the east wall, PropSpacing apart, each a 4x6 panel with a floor label in front.
-- Out of the main path but still testable. The server adds the labels' text and the prompts.
local props = { "Lockpick", "Hotwire", "Keypad", "Charges", "Safe", "Freq" }
local propX = yw / 2 - 1.3
local propZ0 = yardNorth + 11
for i, name in props do
	local z = propZ0 + (i - 1) * Config.PropSpacing
	part("Prop_" .. name, { 0.6, 6, 4 }, { propX, 3, z }, panelGrey, "Metal")
	part("PropLabel_" .. name, { 6, 0.2, 3 }, { propX - 4.6, floorTop + 0.1, z }, labelDark, "SmoothPlastic", {
		CanCollide = false,
		Yaw = -90,
	})
end

-- Tier pad past the last prop: three buttons that set the minigame tier for the session.
local padZ = propZ0 + #props * Config.PropSpacing + 2
part("TierPad", { 10, 0.4, 4 }, { propX - 4.6, floorTop + 0.2, padZ }, labelDark, "SmoothPlastic", {
	CanCollide = false,
	Yaw = -90,
})
for t = 1, 3 do
	part(
		"TierPad" .. t,
		{ 2.4, 0.6, 2.4 },
		{ propX - 4.6, floorTop + 0.7, padZ + (t - 2) * 3 },
		{ 0.3, 0.3, 0.34 },
		"Metal",
		{
			CanCollide = false,
		}
	)
end

local model = { className = "Folder", children = children }
local json = serde.encode("json", model, true)
fs.writeDir("src/map")
fs.writeFile("src/map/Room.model.json", json .. "\n")
print(string.format("Wrote src/map/Room.model.json with %d top-level instances", #children))
process.exit(0)
