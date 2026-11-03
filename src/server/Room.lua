--!strict
-- The one flat room: floor, walls, pillar grid, center spawn, spawn ring. Parts only.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local Room = {
	center = Vector3.new(0, 0, 0),
	spawnPoints = {} :: { Vector3 },
	pillars = {} :: { Vector3 },
	folder = nil :: Folder?,
}

local function part(
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	parent: Instance
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function folder(name: string, parent: Instance): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

function Room.build()
	local old = Workspace:FindFirstChild("Room")
	if old then
		old:Destroy()
	end
	local room = folder("Room", Workspace)
	Room.folder = room
	folder("Enemies", Workspace)
	folder("GroundLoot", Workspace)
	folder("Effects", Workspace)

	local size = Config.RoomSize
	local wallH = Config.WallHeight
	local dark = Color3.fromRGB(44, 44, 50)
	local darker = Color3.fromRGB(34, 34, 40)

	part("Floor", Vector3.new(size, 1, size), CFrame.new(0, -0.5, 0), darker, Enum.Material.Concrete, room)
	local half = size / 2
	part(
		"WallN",
		Vector3.new(size + 2, wallH, 1),
		CFrame.new(0, wallH / 2, -half - 0.5),
		dark,
		Enum.Material.Concrete,
		room
	)
	part(
		"WallS",
		Vector3.new(size + 2, wallH, 1),
		CFrame.new(0, wallH / 2, half + 0.5),
		dark,
		Enum.Material.Concrete,
		room
	)
	part(
		"WallE",
		Vector3.new(1, wallH, size + 2),
		CFrame.new(half + 0.5, wallH / 2, 0),
		dark,
		Enum.Material.Concrete,
		room
	)
	part(
		"WallW",
		Vector3.new(1, wallH, size + 2),
		CFrame.new(-half - 0.5, wallH / 2, 0),
		dark,
		Enum.Material.Concrete,
		room
	)

	-- Pillar grid. Symmetric around the center; the center pillar is skipped so the spawn is clear.
	Room.pillars = {}
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
			part(
				string.format("Pillar_%d_%d", i, j),
				Vector3.new(ps, wallH, ps),
				CFrame.new(x, wallH / 2, z),
				dark,
				Enum.Material.Concrete,
				room
			)
			table.insert(Room.pillars, Vector3.new(x, 0, z))
		end
	end

	-- Player spawn at the center.
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.CFrame = CFrame.new(0, 0.05, 0)
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.Transparency = 0.6
	spawn.Color = Color3.fromRGB(80, 80, 90)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = room

	-- Spawn ring markers.
	Room.spawnPoints = {}
	local count = Config.SpawnPointCount
	local radius = math.min(Config.SpawnRingRadius, half - 4)
	for k = 1, count do
		local angle = (k - 1) / count * math.pi * 2
		local pos = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		table.insert(Room.spawnPoints, pos)
		local marker = part(
			"SpawnPoint" .. k,
			Vector3.new(3, 0.2, 3),
			CFrame.new(pos + Vector3.new(0, 0.1, 0)),
			Color3.fromRGB(120, 40, 40),
			Enum.Material.Neon,
			room
		)
		marker.CanCollide = false
		marker.Transparency = 0.4
	end

	Lighting.Ambient = Color3.fromRGB(70, 70, 80)
	Lighting.OutdoorAmbient = Color3.fromRGB(90, 90, 100)
	Lighting.Brightness = 2
	Lighting.ClockTime = 14
end

function Room.randomSpawnPoint(): Vector3
	return Room.spawnPoints[math.random(#Room.spawnPoints)]
end

function Room.randomPillar(): Vector3
	return Room.pillars[math.random(#Room.pillars)]
end

return Room
