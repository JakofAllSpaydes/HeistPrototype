--!strict
-- The map lives in the place as Workspace.Room (synced by Rojo from src/map/Room.model.json, regenerate
-- with `lune run tools/genmap.luau`): the arena plus the hub yard on its south wall. This module reads
-- spawn points, pillars, the van, the queue zones, the stations and the yard props from it, and only
-- builds the map in code if the folder is missing, so a fresh clone still plays.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

export type Zone = { index: number, pad: BasePart, gate: BasePart?, billboardAnchor: BasePart? }
export type Station = { tab: string, panel: BasePart, label: BasePart }

local Room = {
	center = Vector3.new(0, 0, 0),
	spawnPoints = {} :: { Vector3 },
	pillars = {} :: { Vector3 },
	folder = nil :: Folder?,
	PropNames = { "Lockpick", "Hotwire", "Keypad", "Charges", "Safe", "Freq" },
	StationTabs = { "WEAPONS", "CLASSES", "AVATAR" },
	arenaSpawn = Vector3.new(0, Config.FloorTop, 0), -- floor point where the van brakes and the crew lines up
	yardSpawn = CFrame.new(0, 3, 0), -- where characters stand in the hub, facing the door
	doorPosition = Vector3.new(0, 0, 0), -- floor point in the middle of the south wall opening
	van = nil :: Model?,
	vanHome = CFrame.identity, -- parked pivot of the van in the yard
	props = {} :: { [string]: { panel: BasePart, label: BasePart } },
	tierPads = {} :: { BasePart },
	tierPadBase = nil :: BasePart?,
	zones = {} :: { Zone }, -- queue zones, QueueZone1..N
	stations = {} :: { Station },
	table = nil :: BasePart?,
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

-- Fallback only: mirrors tools/genmap.luau (without the dressing).
local function buildFallback(): Folder
	warn("[GHS Room] Workspace.Room not found, building it in code. Run `lune run tools/genmap.luau` and sync.")
	local room = folder("Room", Workspace)
	local size = Config.RoomSize
	local wallH = Config.WallHeight
	local dark = Color3.fromRGB(44, 44, 50)
	local darker = Color3.fromRGB(34, 34, 40)
	local amber = Color3.fromHex("E8B64C")
	local blue = Color3.fromHex("4D9FE8")
	local half = size / 2
	local floorTop = Config.FloorTop
	local concrete = Enum.Material.Concrete
	part("Floor", Vector3.new(size, 2, size), CFrame.new(0, floorTop - 1, 0), darker, concrete, room)
	part("WallN", Vector3.new(size + 2, wallH, 1), CFrame.new(0, wallH / 2, -half - 0.5), dark, concrete, room)
	part("WallE", Vector3.new(1, wallH, size + 2), CFrame.new(half + 0.5, wallH / 2, 0), dark, concrete, room)
	part("WallW", Vector3.new(1, wallH, size + 2), CFrame.new(-half - 0.5, wallH / 2, 0), dark, concrete, room)
	local doorHalf = Config.DoorWidth / 2
	local segment = (size + 2) / 2 - doorHalf
	local segCenter = doorHalf + segment / 2
	part("WallS_L", Vector3.new(segment, wallH, 1), CFrame.new(-segCenter, wallH / 2, half + 0.5), dark, concrete, room)
	part("WallS_R", Vector3.new(segment, wallH, 1), CFrame.new(segCenter, wallH / 2, half + 0.5), dark, concrete, room)
	for _, side in { -1, 1 } do
		local frame = part(
			if side < 0 then "DoorFrameL" else "DoorFrameR",
			Vector3.new(0.4, wallH, 1.2),
			CFrame.new(side * (doorHalf + 0.2), wallH / 2, half + 0.5),
			amber,
			Enum.Material.Neon,
			room
		)
		frame.CanCollide = false
	end
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
				concrete,
				room
			)
		end
	end
	local pad = part(
		"ArenaSpawn",
		Vector3.new(8, 0.4, 8),
		CFrame.new(0, floorTop + 0.25, 0),
		Color3.fromRGB(80, 80, 90),
		Enum.Material.SmoothPlastic,
		room
	)
	pad.CanCollide = false
	pad.Transparency = 0.6
	local count = Config.SpawnPointCount
	local radius = math.min(Config.SpawnRingRadius, half - 4)
	for k = 1, count do
		local angle = (k - 1) / count * math.pi * 2
		local marker = part(
			"SpawnPoint" .. k,
			Vector3.new(3, 0.2, 3),
			CFrame.new(math.cos(angle) * radius, floorTop + 0.15, math.sin(angle) * radius),
			Color3.fromRGB(120, 40, 40),
			Enum.Material.Neon,
			room
		)
		marker.CanCollide = false
		marker.Transparency = 0.4
	end

	-- Yard.
	local yw, yd = Config.YardWidth, Config.YardDepth
	local yardNorth = half + 1
	local yardZ = yardNorth + yd / 2
	local asphalt = Color3.fromRGB(51, 51, 59)
	local yardWall = Color3.fromRGB(56, 56, 66)
	local panelGrey = Color3.fromRGB(66, 71, 87)
	local labelDark = Color3.fromRGB(26, 26, 31)
	part("YardFloor", Vector3.new(yw, 2, yd), CFrame.new(0, floorTop - 1, yardZ), asphalt, Enum.Material.Asphalt, room)
	part(
		"YardWallS",
		Vector3.new(yw + 2, wallH, 1),
		CFrame.new(0, wallH / 2, yardNorth + yd + 0.5),
		yardWall,
		concrete,
		room
	)
	part("YardWallE", Vector3.new(1, wallH, yd), CFrame.new(yw / 2 + 0.5, wallH / 2, yardZ), yardWall, concrete, room)
	part("YardWallW", Vector3.new(1, wallH, yd), CFrame.new(-yw / 2 - 0.5, wallH / 2, yardZ), yardWall, concrete, room)
	part(
		"Table",
		Vector3.new(10, 0.5, 5),
		CFrame.new(0, floorTop + 2.75, yardZ),
		labelDark,
		Enum.Material.SmoothPlastic,
		room
	)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Size = Vector3.new(8, 0.4, 8)
	spawn.CFrame = CFrame.new(0, floorTop + 0.25, yardZ + 9)
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.Transparency = 0.6
	spawn.Color = Color3.fromRGB(80, 80, 90)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = room
	local qz = Config.QueueZoneSize
	for i = 1, Config.QueueZoneCount do
		local zx = (i - 1 - (Config.QueueZoneCount - 1) / 2) * (qz + 6)
		local zone = part(
			"QueueZone" .. i,
			Vector3.new(qz, 0.2, qz),
			CFrame.new(zx, floorTop + 0.1, yardNorth + 2 + qz / 2),
			blue,
			Enum.Material.Neon,
			room
		)
		zone.CanCollide = false
		zone.Transparency = 0.7
		local gate = part(
			"QueueGate" .. i,
			Vector3.new(qz, 0.8, 0.8),
			CFrame.new(zx, 11.4, yardNorth + 2.4),
			blue,
			Enum.Material.Neon,
			room
		)
		gate.CanCollide = false
		local anchor = part(
			"QueueBillboard" .. i,
			Vector3.new(1, 1, 1),
			CFrame.new(zx, 14.5, yardNorth + 2.4),
			blue,
			Enum.Material.Neon,
			room
		)
		anchor.CanCollide = false
		anchor.Transparency = 1
	end
	local van = Instance.new("Model")
	van.Name = "Van"
	local vanY = floorTop + 1.4
	local body = part(
		"Body",
		Vector3.new(6, 4.2, 11),
		CFrame.new(14, vanY + 2.1, yardZ),
		Color3.fromRGB(51, 61, 92),
		Enum.Material.SmoothPlastic,
		van
	)
	van.PrimaryPart = body
	van.Parent = room
	local stationX = -yw / 2 + 1.3
	for i, name in Room.StationTabs do
		local z = yardNorth + 18 + (i - 1) * Config.StationSpacing
		part(
			"Station_" .. name,
			Vector3.new(0.6, 7, 7),
			CFrame.new(stationX, 3.5, z),
			panelGrey,
			Enum.Material.Metal,
			room
		)
		local label = part(
			"StationLabel_" .. name,
			Vector3.new(7, 0.2, 3),
			CFrame.new(stationX + 5.2, floorTop + 0.1, z) * CFrame.Angles(0, math.rad(90), 0),
			labelDark,
			Enum.Material.SmoothPlastic,
			room
		)
		label.CanCollide = false
	end
	local propX = yw / 2 - 1.3
	local propZ0 = yardNorth + 11
	for i, name in Room.PropNames do
		local z = propZ0 + (i - 1) * Config.PropSpacing
		part("Prop_" .. name, Vector3.new(0.6, 6, 4), CFrame.new(propX, 3, z), panelGrey, Enum.Material.Metal, room)
		local label = part(
			"PropLabel_" .. name,
			Vector3.new(6, 0.2, 3),
			CFrame.new(propX - 4.6, floorTop + 0.1, z) * CFrame.Angles(0, math.rad(-90), 0),
			labelDark,
			Enum.Material.SmoothPlastic,
			room
		)
		label.CanCollide = false
	end
	local padZ = propZ0 + #Room.PropNames * Config.PropSpacing + 2
	local base = part(
		"TierPad",
		Vector3.new(10, 0.4, 4),
		CFrame.new(propX - 4.6, floorTop + 0.2, padZ) * CFrame.Angles(0, math.rad(-90), 0),
		labelDark,
		Enum.Material.SmoothPlastic,
		room
	)
	base.CanCollide = false
	for t = 1, 3 do
		local button = part(
			"TierPad" .. t,
			Vector3.new(2.4, 0.6, 2.4),
			CFrame.new(propX - 4.6, floorTop + 0.7, padZ + (t - 2) * 3),
			Color3.fromRGB(77, 77, 87),
			Enum.Material.Metal,
			room
		)
		button.CanCollide = false
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
	if existing and existing:IsA("Folder") and existing:FindFirstChild("QueueZone1") then
		room = existing
	else
		if existing then
			existing:Destroy()
		end
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
			table.insert(Room.spawnPoints, Vector3.new(child.Position.X, Config.FloorTop, child.Position.Z))
		elseif string.match(child.Name, "^Pillar") then
			table.insert(Room.pillars, Vector3.new(child.Position.X, Config.FloorTop, child.Position.Z))
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
		table.insert(Room.pillars, Vector3.new(30, Config.FloorTop, 30))
	end

	-- Yard and sequence anchors.
	local arenaSpawn = room:FindFirstChild("ArenaSpawn")
	if arenaSpawn and arenaSpawn:IsA("BasePart") then
		Room.arenaSpawn = Vector3.new(arenaSpawn.Position.X, Config.FloorTop, arenaSpawn.Position.Z)
	end
	Room.doorPosition = Vector3.new(0, Config.FloorTop, Config.RoomSize / 2)
	local spawn = room:FindFirstChild("Spawn")
	if spawn and spawn:IsA("BasePart") then
		Room.yardSpawn = CFrame.new(spawn.Position.X, Config.FloorTop + 3, spawn.Position.Z)
	else
		Room.yardSpawn = CFrame.new(0, Config.FloorTop + 3, Config.RoomSize / 2 + 1 + Config.YardDepth / 2 + 9)
	end
	local van = room:FindFirstChild("Van")
	if van and van:IsA("Model") then
		local body = van:FindFirstChild("Body")
		if body and body:IsA("BasePart") then
			van.PrimaryPart = body
		end
		Room.van = van
		Room.vanHome = van:GetPivot()
	end
	local tbl = room:FindFirstChild("Table")
	Room.table = if tbl and tbl:IsA("BasePart") then tbl else nil
	Room.props = {}
	for _, name in Room.PropNames do
		local panel = room:FindFirstChild("Prop_" .. name)
		local label = room:FindFirstChild("PropLabel_" .. name)
		if panel and panel:IsA("BasePart") and label and label:IsA("BasePart") then
			Room.props[name] = { panel = panel, label = label }
		end
	end
	Room.tierPads = {}
	for t = 1, 3 do
		local pad = room:FindFirstChild("TierPad" .. t)
		if pad and pad:IsA("BasePart") then
			Room.tierPads[t] = pad
		end
	end
	local base = room:FindFirstChild("TierPad")
	Room.tierPadBase = if base and base:IsA("BasePart") then base else nil
	Room.zones = {}
	local i = 1
	while true do
		local pad = room:FindFirstChild("QueueZone" .. i)
		if not pad or not pad:IsA("BasePart") then
			break
		end
		local gate = room:FindFirstChild("QueueGate" .. i)
		local anchor = room:FindFirstChild("QueueBillboard" .. i)
		table.insert(Room.zones, {
			index = i,
			pad = pad,
			gate = if gate and gate:IsA("BasePart") then gate else nil,
			billboardAnchor = if anchor and anchor:IsA("BasePart") then anchor else nil,
		})
		i += 1
	end
	if #Room.zones == 0 then
		warn("[GHS Room] no QueueZone parts in Workspace.Room; regenerate the map")
	end
	Room.stations = {}
	for _, tab in Room.StationTabs do
		local panel = room:FindFirstChild("Station_" .. tab)
		local label = room:FindFirstChild("StationLabel_" .. tab)
		if panel and panel:IsA("BasePart") and label and label:IsA("BasePart") then
			table.insert(Room.stations, { tab = tab, panel = panel, label = label })
		end
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

-- A point just south of a queue pad (outside it), for stepping a player out.
function Room.outsideZone(zone: Zone, x: number?): CFrame
	local pad = zone.pad
	local px = if x
		then math.clamp(x, pad.Position.X - pad.Size.X / 2 + 2, pad.Position.X + pad.Size.X / 2 - 2)
		else pad.Position.X
	return CFrame.new(px, Config.FloorTop + 3, pad.Position.Z + pad.Size.Z / 2 + 3)
end

-- Inside a queue pad (XZ), with a little margin so the edge never flickers.
function Room.insideZone(zone: Zone, position: Vector3, margin: number?): boolean
	local pad = zone.pad
	local m = margin or 0
	return math.abs(position.X - pad.Position.X) <= pad.Size.X / 2 + m
		and math.abs(position.Z - pad.Position.Z) <= pad.Size.Z / 2 + m
end

return Room
