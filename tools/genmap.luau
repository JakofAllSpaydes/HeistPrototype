--!strict
-- Generates src/map/Room.model.json from Config so the room exists as real instances in the place.
-- Run with: lune run tools/genmap.luau   (then let Rojo sync, or `rojo build`)
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")

local Config = require("../src/shared/Config")

type Child = { name: string, className: string, properties: { [string]: any } }

local children: { Child } = {}

local function part(
	name: string,
	size: { number },
	pos: { number },
	color: { number },
	material: string,
	extra: { [string]: any }?
): Child
	local props: { [string]: any } = {
		Size = size,
		CFrame = { CFrame = { position = pos, orientation = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } } } },
		Color = color,
		Material = material,
		Anchored = true,
		TopSurface = "Smooth",
		BottomSurface = "Smooth",
	}
	if extra then
		for k, v in extra do
			props[k] = v
		end
	end
	local c = { name = name, className = "Part", properties = props }
	table.insert(children, c)
	return c
end

local size = Config.RoomSize
local wallH = Config.WallHeight
local half = size / 2
local dark = { 0.17, 0.17, 0.2 }
local darker = { 0.13, 0.13, 0.16 }

-- Floor: 2 studs thick, top face at y = 0. Delete the default Baseplate (top also at y = 0) or they z-fight.
part("Floor", { size, 2, size }, { 0, -1, 0 }, darker, "Concrete")
part("WallN", { size + 2, wallH, 1 }, { 0, wallH / 2, -half - 0.5 }, dark, "Concrete")
part("WallS", { size + 2, wallH, 1 }, { 0, wallH / 2, half + 0.5 }, dark, "Concrete")
part("WallE", { 1, wallH, size + 2 }, { half + 0.5, wallH / 2, 0 }, dark, "Concrete")
part("WallW", { 1, wallH, size + 2 }, { -half - 0.5, wallH / 2, 0 }, dark, "Concrete")

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

-- Spawn pad sits 0.05 above the floor so no face is coplanar.
table.insert(children, {
	name = "Spawn",
	className = "SpawnLocation",
	properties = {
		Size = { 8, 0.4, 8 },
		CFrame = { CFrame = { position = { 0, 0.25, 0 }, orientation = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } } } },
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

-- Spawn ring markers.
local count = Config.SpawnPointCount
local radius = math.min(Config.SpawnRingRadius, half - 4)
for k = 1, count do
	local angle = (k - 1) / count * math.pi * 2
	part(
		"SpawnPoint" .. k,
		{ 3, 0.2, 3 },
		{ math.cos(angle) * radius, 0.15, math.sin(angle) * radius },
		{ 0.47, 0.16, 0.16 },
		"Neon",
		{
			CanCollide = false,
			Transparency = 0.4,
		}
	)
end

local model = { className = "Folder", children = children }
local json = serde.encode("json", model, true)
fs.writeDir("src/map")
fs.writeFile("src/map/Room.model.json", json .. "\n")
print(string.format("Wrote src/map/Room.model.json with %d instances", #children))
process.exit(0)
