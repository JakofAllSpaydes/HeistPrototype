--!strict
-- The map lives in the place as Workspace.Room (synced by Rojo from src/map/Room.model.json, regenerate
-- with `lune run tools/genmap.luau`): the arena plus the hub yard on its south wall. This module reads
-- spawn points, pillars, the van, the queue zones, the stations and the yard props from it, and only
-- builds the map in code if the folder is missing, so a fresh clone still plays.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local BagSpots = require(ReplicatedStorage.Shared.BagSpots)
local Ground = require(ReplicatedStorage.Shared.Ground)
local World = require(script.Parent.World)
local Slot = require(script.Parent.Slot)

export type Zone = { index: number, pad: BasePart, gate: BasePart?, billboardAnchor: BasePart? }
export type Station = { tab: string, panel: BasePart, label: BasePart }
-- The vault closet on the north wall (brief 4): the sliding door, its amber frame (the beacon), the sign,
-- the ceiling lights, the gas anchor and the floor volume that counts as "inside".
export type Vault = {
	door: BasePart,
	doorClosed: CFrame,
	doorOpen: CFrame,
	beacons: { BasePart },
	sign: BasePart?,
	lights: { BasePart },
	gas: BasePart?,
	front: Vector3, -- floor point just outside the door (markers, the prompt)
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number,
}

-- Brief 7: every map hands out the same shape (Room.forMap). The arena wraps its markers, bag spots,
-- pillars, closet vault and dealer position; THE BANK's view is built by MapLoader from its nodes.
export type SpawnBox = {
	name: string,
	zone: string,
	cframe: CFrame, -- the box volume (a random point inside, dropped to the ground, is the spawn)
	size: Vector3,
	weight: number,
	allowed: { [string]: boolean }?, -- archetype ids; nil = all
	requiresDoor: string?, -- a door group that must be open; nil = always on
	mouth: string, -- the opening it stands behind, for the logs
	whileVault: boolean?, -- only while the vault is open (the vault room's vent)
}
export type BagSpot = { name: string, position: Vector3, zone: string, gold: boolean }
export type JobSpot = {
	name: string,
	cframe: CFrame,
	zone: string,
	pool: { string }?, -- job kinds this spot draws; nil = every kind
	label: string?,
	pillar: boolean?, -- arena: the beacon stands beside this pillar, pushed toward the room center
}
export type DealerSpot = { name: string, cframe: CFrame, zone: string }
export type BossWall = { name: string, cframe: CFrame, size: Vector3, zone: string }
export type MapView = {
	id: string,
	floorTop: number, -- the main floor (fallback height)
	spawnBoxes: { SpawnBox },
	bagSpots: { BagSpot },
	vaultSpots: { Vector3 }, -- the vault burst's spots
	jobSpots: { JobSpot },
	dealerSpots: { DealerSpot },
	bossWalls: { BossWall },
	van: CFrame?, -- where the van parks on run start (nil: the arena's drive in from the yard)
	lineup: CFrame?, -- the crew's line on run start, facing along LookVector (nil: the arena spawn)
	runEndLine: CFrame?, -- the run end line (nil: where the crew stands, as on the arena)
	hub: any?, -- brief 8: Room.forMap("Hub") only: the hub's view (HubMap.View: spawn, pads, booths, board, van, range)
}

local Room = {
	center = Vector3.new(0, 0, 0),
	spawnPoints = {} :: { Vector3 },
	pillars = {} :: { Vector3 },
	folder = nil :: Folder?,
	PropNames = { "Lockpick", "Hotwire", "Keypad", "Charges", "Safe", "Freq", "Cut" },
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
	vault = nil :: Vault?, -- nil when the map has no VaultDoor (the vault job is then never drawn)
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
	-- North wall with the vault closet (mirrors genmap without the shelves and sign).
	local vs = Config.VaultSize
	local vdHalf = Config.VaultDoorWidth / 2
	local nSeg = (size + 2) / 2 - vdHalf
	local nSegCenter = vdHalf + nSeg / 2
	local steel = Color3.fromRGB(70, 72, 80)
	part("WallN_L", Vector3.new(nSeg, wallH, 1), CFrame.new(-nSegCenter, wallH / 2, -half - 0.5), dark, concrete, room)
	part("WallN_R", Vector3.new(nSeg, wallH, 1), CFrame.new(nSegCenter, wallH / 2, -half - 0.5), dark, concrete, room)
	part(
		"VaultDoor",
		Vector3.new(Config.VaultDoorWidth, wallH, 1),
		CFrame.new(0, wallH / 2, -half - 0.5),
		steel,
		Enum.Material.DiamondPlate,
		room
	)
	for _, side in { -1, 1 } do
		local beacon = part(
			if side < 0 then "VaultBeaconL" else "VaultBeaconR",
			Vector3.new(0.5, wallH, 1.4),
			CFrame.new(side * (vdHalf + 0.25), wallH / 2, -half - 0.5),
			amber,
			Enum.Material.Neon,
			room
		)
		beacon.CanCollide = false
	end
	local vFront = -half - 1
	local vCenterZ = vFront - vs / 2
	part("VaultFloor", Vector3.new(vs, 2, vs), CFrame.new(0, floorTop - 1, vCenterZ), darker, concrete, room)
	part("VaultWallN", Vector3.new(vs + 2, wallH, 1), CFrame.new(0, wallH / 2, vFront - vs - 0.5), dark, concrete, room)
	part(
		"VaultWallE",
		Vector3.new(1, wallH, vs + 1),
		CFrame.new(vs / 2 + 0.5, wallH / 2, vCenterZ - 0.5),
		dark,
		concrete,
		room
	)
	part(
		"VaultWallW",
		Vector3.new(1, wallH, vs + 1),
		CFrame.new(-vs / 2 - 0.5, wallH / 2, vCenterZ - 0.5),
		dark,
		concrete,
		room
	)
	part(
		"VaultCeiling",
		Vector3.new(vs + 2, 1, vs + 2),
		CFrame.new(0, wallH + 0.5, vCenterZ - 0.5),
		dark,
		concrete,
		room
	)
	local gas =
		part("VaultGas", Vector3.new(1, 1, 1), CFrame.new(0, wallH - 1, vCenterZ), amber, Enum.Material.Neon, room)
	gas.CanCollide = false
	gas.Transparency = 1
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
		Room.vanHome = van:GetPivot()
		-- Brief 8: every run slot drives its own copy (two runs can start at once); the hub keeps the original
		-- (Hub.init puts it away).
		Room.van = if Slot.isHub then van else van:Clone()
	end
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

	-- The vault closet.
	Room.vault = nil
	local door = room:FindFirstChild("VaultDoor")
	if door and door:IsA("BasePart") then
		local beacons = {}
		for _, name in { "VaultBeaconL", "VaultBeaconR" } do
			local b = room:FindFirstChild(name)
			if b and b:IsA("BasePart") then
				table.insert(beacons, b)
			end
		end
		local lights = {}
		for i = 1, 4 do
			local l = room:FindFirstChild("VaultLight" .. i)
			if l and l:IsA("BasePart") then
				table.insert(lights, l)
			end
		end
		local sign = room:FindFirstChild("VaultSign")
		local gas = room:FindFirstChild("VaultGas")
		local vs = Config.VaultSize
		local front = -(Config.RoomSize / 2 + 1)
		Room.vault = {
			door = door,
			doorClosed = door.CFrame,
			doorOpen = door.CFrame + Vector3.new(0, door.Size.Y, 0),
			beacons = beacons,
			sign = if sign and sign:IsA("BasePart") then sign else nil,
			lights = lights,
			gas = if gas and gas:IsA("BasePart") then gas else nil,
			front = Vector3.new(door.Position.X, Config.FloorTop, door.Position.Z + 4),
			minX = door.Position.X - vs / 2,
			maxX = door.Position.X + vs / 2,
			minZ = front - vs,
			maxZ = front,
		}
	end

	-- Brief 8: the hub's pieces (pads, stations, props, tier pad) belong to the hub slot, the closet vault to the
	-- arena's: a slot only sees what it runs, so nothing is dressed or reset twice.
	if not Slot.isHub then
		Room.props = {}
		Room.tierPads = {}
		Room.tierPadBase = nil
		Room.zones = {}
		Room.stations = {}
	end
	if Slot.mapId ~= "Arena" then
		Room.vault = nil
	end

	Lighting.Ambient = Color3.fromRGB(70, 70, 80)
	Lighting.OutdoorAmbient = Color3.fromRGB(90, 90, 100)
	Lighting.Brightness = 2
	Lighting.ClockTime = 14
end

function Room.randomSpawnPoint(): Vector3
	return Room.spawnPoints[math.random(#Room.spawnPoints)]
end

-- Inside the vault closet's floor volume (XZ), past the door line.
function Room.insideVault(position: Vector3): boolean
	local v = Room.vault
	if not v then
		return false
	end
	return position.X >= v.minX and position.X <= v.maxX and position.Z >= v.minZ and position.Z <= v.maxZ
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
	return CFrame.new(px, pad.Position.Y + 3, pad.Position.Z + pad.Size.Z / 2 + 3)
end

-- Inside a queue pad (XZ), with a little margin so the edge never flickers.
function Room.insideZone(zone: Zone, position: Vector3, margin: number?): boolean
	local pad = zone.pad
	local m = margin or 0
	return math.abs(position.X - pad.Position.X) <= pad.Size.X / 2 + m
		and math.abs(position.Z - pad.Position.Z) <= pad.Size.Z / 2 + m
end

------------------------------------------------------------------ Per-map views (brief 7)
local views: { [string]: MapView } = {}
local builders: { [string]: () -> MapView? } = {}

-- The arena: its eight markers as spawn boxes (zone "arena", no door, a point-sized box so the spawn is the
-- marker itself), the twelve bag spots, the pillars as job spots, the closet's spots and the dealer position.
local function arenaView(): MapView
	local boxes: { SpawnBox } = {}
	for i, p in Room.spawnPoints do
		table.insert(boxes, {
			name = "marker" .. i,
			zone = "arena",
			cframe = CFrame.new(p),
			size = Vector3.zero,
			weight = 1,
			allowed = nil,
			requiresDoor = nil,
			mouth = "marker " .. i,
		})
	end
	local spots: { BagSpot } = {}
	for i, p in BagSpots.Arena do
		table.insert(spots, { name = "spot" .. i, position = p, zone = "arena", gold = true })
	end
	local jobs: { JobSpot } = {}
	for i, p in Room.pillars do
		table.insert(jobs, { name = "pillar" .. i, cframe = CFrame.new(p), zone = "arena", pillar = true })
	end
	local d = Config.DealerStallPosition
	return {
		id = "Arena",
		floorTop = Config.FloorTop,
		spawnBoxes = boxes,
		bagSpots = spots,
		vaultSpots = BagSpots.Vault,
		jobSpots = jobs,
		dealerSpots = { { name = "stall", cframe = CFrame.new(d.X, Config.FloorTop, d.Z), zone = "arena" } },
		bossWalls = {},
		van = nil,
		lineup = nil,
		runEndLine = nil,
	}
end

-- MapLoader registers maps built from nodes; a registered builder runs once, on the first forMap.
function Room.registerMap(id: string, build: () -> MapView?)
	builders[id] = build
	views[id] = nil
end

-- Drop a cached view (debug Recompute nodes, a re-registered map).
function Room.invalidate(id: string?)
	if id then
		views[id] = nil
	else
		views = {}
	end
end

-- The positions of a map. Unknown or unbuilt maps fall back to the arena so a run never starts on nothing.
function Room.forMap(id: string): MapView
	local v = views[id]
	if v then
		return v
	end
	local build = builders[id]
	local built = if build then build() else nil
	if not built then
		if id ~= "Arena" then
			warn(string.format("[GHS Room] no view for map %s; using the arena", id))
		end
		built = views.Arena or arenaView()
		views.Arena = built
	end
	views[id] = built
	return built :: MapView
end

-- The map the current (or last) run is on.
function Room.current(): MapView
	return Room.forMap(World.map)
end

-- The current map's spawn box nearest a point (or a named one), and a spawn point in it.
function Room.nearestBox(position: Vector3?, name: string?): (SpawnBox?, Vector3)
	local best: SpawnBox? = nil
	local bestDist = math.huge
	for _, box in Room.current().spawnBoxes do
		if name and box.name ~= name then
			continue
		end
		local d = if position then (box.cframe.Position - position).Magnitude else math.random()
		if d < bestDist then
			bestDist = d
			best = box
		end
	end
	if best then
		return best, Room.pointInBox(best)
	end
	return nil, Room.randomSpawnPoint()
end

-- A random point in a spawn box, dropped to the ground under it (the box itself for point-sized boxes).
function Room.pointInBox(box: SpawnBox): Vector3
	local s = box.size
	local local_ = Vector3.new((math.random() - 0.5) * s.X, 0, (math.random() - 0.5) * s.Z)
	local p = box.cframe:PointToWorldSpace(local_)
	if s.Magnitude < 0.01 then
		return p
	end
	return Vector3.new(p.X, Ground.y(p + Vector3.new(0, s.Y / 2, 0), p.Y - s.Y / 2), p.Z)
end

return Room
