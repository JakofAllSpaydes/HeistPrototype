--!strict
-- The room lives in the place as Workspace.Room (synced by Rojo from src/map/Room.model.json, regenerate
-- with `lune run tools/genmap.luau`). This module reads spawn points and pillars from it and only builds
-- the room in code if the folder is missing, so a fresh clone still plays.
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

-- Fallback only: mirrors tools/genmap.luau.
local function buildFallback(): Folder
	warn("[GHS Room] Workspace.Room not found, building it in code. Run `lune run tools/genmap.luau` and sync.")
	local room = folder("Room", Workspace)
	local size = Config.RoomSize
	local wallH = Config.WallHeight
	local dark = Color3.fromRGB(44, 44, 50)
	local darker = Color3.fromRGB(34, 34, 40)
	local half = size / 2
	part("Floor", Vector3.new(size, 2, size), CFrame.new(0, -1, 0), darker, Enum.Material.Concrete, room)
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
		end
	end
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Size = Vector3.new(8, 0.4, 8)
	spawn.CFrame = CFrame.new(0, 0.25, 0)
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.Transparency = 0.6
	spawn.Color = Color3.fromRGB(80, 80, 90)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = room
	local count = Config.SpawnPointCount
	local radius = math.min(Config.SpawnRingRadius, half - 4)
	for k = 1, count do
		local angle = (k - 1) / count * math.pi * 2
		local marker = part(
			"SpawnPoint" .. k,
			Vector3.new(3, 0.2, 3),
			CFrame.new(math.cos(angle) * radius, 0.15, math.sin(angle) * radius),
			Color3.fromRGB(120, 40, 40),
			Enum.Material.Neon,
			room
		)
		marker.CanCollide = false
		marker.Transparency = 0.4
	end
	return room
end

function Room.build()
	-- The default Baseplate's top face is at y = 0, same as the floor: remove it so nothing z-fights.
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end

	local existing = Workspace:FindFirstChild("Room")
	local room: Folder
	if existing and existing:IsA("Folder") then
		room = existing
	else
		room = buildFallback()
	end
	Room.folder = room
	folder("Enemies", Workspace)
	folder("GroundLoot", Workspace)
	folder("Effects", Workspace)

	-- Read spawn points and pillars from whatever is placed, so the designer can move them in Studio.
	Room.spawnPoints = {}
	Room.pillars = {}
	for _, child in room:GetChildren() do
		if not child:IsA("BasePart") then
			continue
		end
		if string.match(child.Name, "^SpawnPoint%d+$") then
			table.insert(Room.spawnPoints, Vector3.new(child.Position.X, 0, child.Position.Z))
		elseif string.match(child.Name, "^Pillar") then
			table.insert(Room.pillars, Vector3.new(child.Position.X, 0, child.Position.Z))
		end
	end
	if #Room.spawnPoints == 0 then
		warn("[GHS Room] No SpawnPointN parts in Workspace.Room; enemies will spawn on the ring from Config")
		local radius = Config.SpawnRingRadius
		for k = 1, Config.SpawnPointCount do
			local angle = (k - 1) / Config.SpawnPointCount * math.pi * 2
			table.insert(Room.spawnPoints, Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius))
		end
	end
	if #Room.pillars == 0 then
		table.insert(Room.pillars, Vector3.new(30, 0, 30))
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
