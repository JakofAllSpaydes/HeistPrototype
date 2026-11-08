--!strict
-- THE BANK's runtime tables (brief 7), read from the node parts under Workspace.Bank.Nodes: zones, doors,
-- spawn boxes, bag and job spots, boss walls, dealer spots, the van, the lineup, the hatch and the vault room.
-- Nothing reads src/map/Bank.nodes.model.json directly; this module reads the parts (so a node moved in Studio
-- moves here), validates every reference and prints one `[GHS Map] <type> <name> ...` line per node and one
-- `[GHS Map] ERROR <name>: <reason>` per bad reference. A map with errors still loads (Config.MapLoaderStrict
-- refuses a run on it instead). It also registers THE BANK's Room.forMap view and answers "which zone is this
-- point in" for everything that follows the crew.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Enemies = require(Shared.Enemies)
local Room = require(script.Parent.Room)
local Log = require(script.Parent.Log)
local World = require(script.Parent.World)
local PlayerState = require(script.Parent.PlayerState)
local Bags = require(script.Parent.Bags)
local CrewCall = require(script.Parent.CrewCall)
local Spawner = require(script.Parent.Spawner)
local EnemyPath = require(script.Parent.EnemyPath)
local TweenService = game:GetService("TweenService")

export type Volume = { cframe: CFrame, size: Vector3 }
export type Zone = { id: string, depth: number, label: string, parts: { Volume } }
export type DoorPart = {
	name: string,
	node: BasePart,
	cframe: CFrame,
	size: Vector3,
	style: string, -- chain | shutter | wheel | panel
	mesh: string?, -- name prefix of the asset parts to animate (wheel doors)
	meshMargin: number,
	opens: string?, -- the zone this part leads into (its own Opens)
	label: string,
	hide: { string }, -- Round 19: asset part names (prefixes) inside the node that vanish while open
	hideWall: boolean, -- Round 19: the largest geometry part inside the node (a door painted on a wall) vanishes too
}
export type Door = {
	group: string,
	parts: { DoorPart },
	opens: { string }, -- every zone the group opens
	triggerWave: number, -- 0 = the vault draw, -1 = open from the start
	interactTime: number,
	cashReward: number,
	pingText: string,
	label: string,
	priority: number,
	interact: string, -- Round 19: "hold", or a minigame kind (Charges, Lockpick, Keypad, Hotwire, Freq, Safe)
}
export type Box = Room.SpawnBox & { doorEver: boolean?, standsIn: string? }
export type Hatch = {
	cframe: CFrame,
	size: Vector3,
	mesh: string?,
	meshMargin: number,
	zone: string,
	ladderBottom: Vector3,
	ladderTop: Vector3,
}

local MapLoader = {}

MapLoader.MAP_ID = "TheBank"
MapLoader.loaded = false
MapLoader.bank = nil :: Model?
MapLoader.nodesFolder = nil :: Folder?
MapLoader.errors = 0
MapLoader.zones = {} :: { [string]: Zone }
MapLoader.zoneOrder = {} :: { Zone } -- deepest first (ties in a lookup go to the deeper zone)
MapLoader.links = {} :: { [string]: { { to: string, gate: string } } } -- the zone graph
MapLoader.doors = {} :: { [string]: Door }
MapLoader.boxes = {} :: { Box }
MapLoader.bagSpots = {} :: { Room.BagSpot }
MapLoader.jobSpots = {} :: { Room.JobSpot }
MapLoader.bossWalls = {} :: { Room.BossWall }
MapLoader.dealerSpots = {} :: { Room.DealerSpot }
MapLoader.van = nil :: CFrame?
MapLoader.vanLineupOffset = 12
MapLoader.lineup = nil :: CFrame?
MapLoader.hatch = nil :: Hatch?
MapLoader.vaultRoom = nil :: (Volume & { door: string })?
MapLoader.hatchOpen = false -- the tunnel's way up (closed until the vault first opens)

-- Job kinds a JobSpot's Pool may name (the minigame props by their lower-case names).
local POOL_KINDS = { hack = true, capture = true }
for _, name in Room.PropNames do
	POOL_KINDS[string.lower(name)] = true
end

local function fail(name: string, reason: string)
	MapLoader.errors += 1
	Log.event("Map", "ERROR %s: %s", name, reason)
end

local function str(p: Instance, key: string, default: string): string
	local v = p:GetAttribute(key)
	return if typeof(v) == "string" then v else default
end

local function num(p: Instance, key: string, default: number): number
	local v = p:GetAttribute(key)
	return if typeof(v) == "number" then v else default
end

local function bool(p: Instance, key: string): boolean
	return p:GetAttribute(key) == true
end

local function list(s: string): { string }
	local out = {}
	for item in string.gmatch(s, "[^,]+") do
		local t = string.gsub(item, "^%s*(.-)%s*$", "%1")
		if t ~= "" then
			table.insert(out, t)
		end
	end
	return out
end

local function partsIn(folder: Instance?, name: string): { BasePart }
	local f = folder and folder:FindFirstChild(name)
	local out = {}
	if f then
		for _, c in f:GetChildren() do
			if c:IsA("BasePart") then
				table.insert(out, c)
			end
		end
	end
	return out
end

-- Is a point inside an oriented box (plus `margin` studs on every side)?
function MapLoader.inVolume(cframe: CFrame, size: Vector3, point: Vector3, margin: number?): boolean
	local m = margin or 0
	local p = cframe:PointToObjectSpace(point)
	return math.abs(p.X) <= size.X / 2 + m and math.abs(p.Y) <= size.Y / 2 + m and math.abs(p.Z) <= size.Z / 2 + m
end

-- The zone a point stands in (the deepest one when volumes overlap), or nil outside every zone.
function MapLoader.zoneAt(point: Vector3): string?
	for _, z in MapLoader.zoneOrder do
		for _, v in z.parts do
			if MapLoader.inVolume(v.cframe, v.size, point) then
				return z.id
			end
		end
	end
	return nil
end

-- The zone nearest a point (for points between volumes: a player mid-jump, a spot just outside a wall).
function MapLoader.nearestZone(point: Vector3): string?
	local inside = MapLoader.zoneAt(point)
	if inside then
		return inside
	end
	local best, bestDist = nil, math.huge
	for _, z in MapLoader.zoneOrder do
		for _, v in z.parts do
			local p = v.cframe:PointToObjectSpace(point)
			local h = v.size / 2
			local d = Vector3.new(
				math.max(0, math.abs(p.X) - h.X),
				math.max(0, math.abs(p.Y) - h.Y),
				math.max(0, math.abs(p.Z) - h.Z)
			).Magnitude
			if d < bestDist then
				bestDist = d
				best = z.id
			end
		end
	end
	return best
end

-- Asset parts a door or hatch animates: geometry parts whose name starts with `prefix` and whose center lies in
-- the node's volume (+ margin).
function MapLoader.meshParts(cframe: CFrame, size: Vector3, prefix: string, margin: number): { BasePart }
	local out = {}
	local bank = MapLoader.bank
	local geo = bank and bank:FindFirstChild("Geometry")
	if not geo then
		return out
	end
	for _, d in geo:GetDescendants() do
		if
			d:IsA("BasePart")
			and string.sub(d.Name, 1, #prefix) == prefix
			and MapLoader.inVolume(cframe, size, d.Position, margin)
		then
			table.insert(out, d)
		end
	end
	return out
end

local function canonicalArchetype(name: string): string?
	local low = string.lower(name)
	for _, row in Enemies.List do
		if string.lower(row.id) == low then
			return row.id
		end
	end
	return nil
end

-- Brief 7: the import baked THE BANK at Config.BankOrigin; when BankOrigin changes the whole model (geometry and
-- nodes together) moves at load, so nodes always sit on the geometry.
local function placeBank(bank: Model)
	local geo = bank:FindFirstChild("Geometry")
	if not geo or not geo:IsA("Model") then
		return
	end
	local baked = geo.WorldPivot
	local target = Config.BankOrigin
	if baked.Position:FuzzyEq(target.Position, 0.01) and baked.LookVector:FuzzyEq(target.LookVector, 0.001) then
		return
	end
	local delta = target * baked:Inverse()
	bank:PivotTo(delta * bank:GetPivot())
	geo.WorldPivot = target
	Log.event("Map", "TheBank moved to BankOrigin (%d, %d, %d)", target.X, target.Y, target.Z)
end

-- Map geometry never moves on its own: everything the builder left unanchored is anchored.
-- Round 19: the street's crowd barriers stop players but not enemies (they spawn behind them and come over), and
-- paths treat them as open. Matched by Config.EnemyPassNames (geometry part names).
local function enemyPass(bank: Model)
	local PhysicsService = game:GetService("PhysicsService")
	pcall(function()
		PhysicsService:RegisterCollisionGroup("Enemy")
	end)
	pcall(function()
		PhysicsService:RegisterCollisionGroup("EnemyPass")
	end)
	PhysicsService:CollisionGroupSetCollidable("Enemy", "EnemyPass", false)
	local geo = bank:FindFirstChild("Geometry")
	if not geo then
		return
	end
	local n = 0
	for _, d in geo:GetDescendants() do
		if d:IsA("BasePart") and table.find(Config.EnemyPassNames, d.Name) then
			d.CollisionGroup = "EnemyPass"
			if not d:FindFirstChildOfClass("PathfindingModifier") then
				local m = Instance.new("PathfindingModifier")
				m.PassThrough = true
				m.Parent = d
			end
			n += 1
		end
	end
	Log.event("Map", "%d parts enemies walk through (%s)", n, table.concat(Config.EnemyPassNames, ", "))
end

local function anchorAll(bank: Model)
	local geo = bank:FindFirstChild("Geometry")
	if not geo then
		return
	end
	local n = 0
	for _, d in geo:GetDescendants() do
		if d:IsA("BasePart") and not d.Anchored then
			d.Anchored = true
			n += 1
		end
	end
	if n > 0 then
		Log.event("Map", "anchored %d loose geometry parts", n)
	end
end

------------------------------------------------------------------ Reading
local function readZones(nodes: Instance)
	for _, p in partsIn(nodes, "Zones") do
		local id = p.Name
		local z = MapLoader.zones[id]
		if not z then
			z = {
				id = id,
				depth = math.floor(num(p, "Depth", 0)),
				label = str(p, "Label", string.upper(id)),
				parts = {},
			}
			MapLoader.zones[id] = z
		end
		table.insert(z.parts, { cframe = p.CFrame, size = p.Size })
		-- Links (brief 7 addition): the zone graph, neighbour@gate. Any part may carry them; they merge.
		local links = MapLoader.links[id] or {}
		MapLoader.links[id] = links
		for _, item in list(str(p, "Links", "")) do
			local to, gate = string.match(item, "^([^@]+)@?(.*)$")
			if to then
				local dup = false
				for _, l in links do
					dup = dup or (l.to == to and l.gate == gate)
				end
				if not dup then
					table.insert(links, { to = to, gate = gate or "" })
				end
			end
		end
		Log.event("Map", "Zone %s depth %d %q (%d x %d x %d)", id, z.depth, z.label, p.Size.X, p.Size.Y, p.Size.Z)
	end
	for _, z in MapLoader.zones do
		table.insert(MapLoader.zoneOrder, z)
	end
	table.sort(MapLoader.zoneOrder, function(a, b)
		return a.depth > b.depth
	end)
end

local function zoneKnown(name: string, zoneId: string, what: string): boolean
	if MapLoader.zones[zoneId] then
		return true
	end
	fail(name, string.format("unknown %s zone '%s'", what, zoneId))
	return false
end

local function readDoors(nodes: Instance)
	for _, p in partsIn(nodes, "Doors") do
		local group = str(p, "Group", p.Name)
		local style = str(p, "DoorStyle", "panel")
		if style ~= "chain" and style ~= "shutter" and style ~= "wheel" and style ~= "panel" then
			fail(p.Name, "unknown DoorStyle '" .. style .. "' (chain / shutter / wheel / panel)")
			style = "panel"
		end
		local d = MapLoader.doors[group]
		if not d then
			local override = (Config.DoorTriggerWave :: any)[group]
			d = {
				group = group,
				parts = {},
				opens = {},
				triggerWave = if typeof(override) == "number" then override else math.floor(num(p, "TriggerWave", 0)),
				interactTime = num(p, "InteractTime", Config.DoorInteractTime),
				cashReward = num(p, "CashReward", Config.DoorOpenCashReward),
				pingText = str(p, "PingText", "OPEN THE DOOR"),
				label = str(p, "Label", group),
				priority = num(p, "Priority", 1),
				interact = str(p, "Interact", "hold"),
			}
			if d.interact ~= "hold" and not table.find(Room.PropNames, d.interact) then
				fail(
					p.Name,
					"Interact '"
						.. d.interact
						.. "' is not hold or a minigame ("
						.. table.concat(Room.PropNames, ", ")
						.. ")"
				)
				d.interact = "hold"
			end
			MapLoader.doors[group] = d
		end
		local opens = list(str(p, "Opens", ""))
		for _, zid in opens do
			if zoneKnown(p.Name, zid, "Opens") and not table.find(d.opens, zid) then
				table.insert(d.opens, zid)
			end
		end
		local mesh = str(p, "Mesh", "")
		local part: DoorPart = {
			name = p.Name,
			node = p,
			cframe = p.CFrame,
			size = p.Size,
			style = style,
			mesh = if mesh ~= "" then mesh else nil,
			meshMargin = num(p, "MeshMargin", 2),
			opens = opens[1],
			label = str(p, "Label", d.label),
			hide = list(str(p, "Hide", "")),
			hideWall = bool(p, "HideWall"),
		}
		if part.mesh then
			local found = MapLoader.meshParts(part.cframe, part.size, part.mesh, part.meshMargin)
			if #found == 0 then
				fail(p.Name, "Mesh '" .. part.mesh .. "' matches no geometry part inside the node")
				part.mesh = nil
			end
		end
		table.insert(d.parts, part)
		Log.event(
			"Map",
			"Door %s group %s %s opens %s trigger %s",
			p.Name,
			group,
			style,
			table.concat(opens, ","),
			if d.triggerWave == 0 then "vault" elseif d.triggerWave < 0 then "start" else "wave " .. d.triggerWave
		)
	end
end

local function readBoxes(nodes: Instance)
	for _, p in partsIn(nodes, "SpawnBoxes") do
		local zid = str(p, "Zone", "")
		zoneKnown(p.Name, zid, "Zone")
		local req = str(p, "RequiresDoor", "")
		if req ~= "" and not MapLoader.doors[req] then
			fail(p.Name, "RequiresDoor names unknown door group '" .. req .. "'")
		end
		local allowedRaw = str(p, "AllowedTypes", "all")
		local allowed: { [string]: boolean }? = nil
		if string.lower(allowedRaw) ~= "all" then
			local set = {}
			for _, a in list(allowedRaw) do
				local id = canonicalArchetype(a)
				if id then
					set[id] = true
				else
					fail(p.Name, "AllowedTypes names unknown archetype '" .. a .. "'")
				end
			end
			allowed = set
		end
		local b: Box = {
			name = p.Name,
			zone = zid,
			cframe = p.CFrame,
			size = p.Size,
			weight = num(p, "Weight", 1),
			allowed = allowed,
			requiresDoor = if req ~= "" then req else nil,
			mouth = str(p, "MouthName", p.Name),
			whileVault = bool(p, "WhileVault"),
			doorEver = bool(p, "DoorEver"),
			standsIn = MapLoader.zoneAt(p.Position),
		}
		table.insert(MapLoader.boxes, b)
		Log.event(
			"Map",
			"SpawnBox %s zone %s stands in %s door %s types %s weight %.2f mouth %q",
			p.Name,
			zid,
			b.standsIn or "-",
			req ~= "" and req or "-",
			allowedRaw,
			b.weight,
			b.mouth
		)
	end
end

local function readSpots(nodes: Instance)
	for _, p in partsIn(nodes, "BagSpots") do
		local zid = str(p, "Zone", "")
		zoneKnown(p.Name, zid, "Zone")
		table.insert(MapLoader.bagSpots, { name = p.Name, position = p.Position, zone = zid, gold = bool(p, "Gold") })
		Log.event("Map", "BagSpot %s zone %s%s", p.Name, zid, if bool(p, "Gold") then " gold" else "")
	end
	for _, p in partsIn(nodes, "JobSpots") do
		local zid = str(p, "Zone", "")
		zoneKnown(p.Name, zid, "Zone")
		local pool = list(str(p, "Pool", ""))
		for _, k in pool do
			if not POOL_KINDS[string.lower(k)] then
				fail(p.Name, "Pool names unknown job kind '" .. k .. "'")
			end
		end
		table.insert(MapLoader.jobSpots, {
			name = p.Name,
			cframe = p.CFrame,
			zone = zid,
			pool = if #pool > 0 then pool else nil,
			label = str(p, "Label", string.upper(p.Name)),
		})
		Log.event("Map", "JobSpot %s zone %s pool %s %q", p.Name, zid, table.concat(pool, ","), str(p, "Label", ""))
	end
	for _, p in partsIn(nodes, "BossWalls") do
		local zid = str(p, "Zone", "")
		zoneKnown(p.Name, zid, "Zone")
		table.insert(MapLoader.bossWalls, { name = p.Name, cframe = p.CFrame, size = p.Size, zone = zid })
		Log.event("Map", "BossWall %s zone %s", p.Name, zid)
	end
	for _, p in partsIn(nodes, "DealerSpots") do
		local zid = str(p, "Zone", "")
		zoneKnown(p.Name, zid, "Zone")
		table.insert(MapLoader.dealerSpots, { name = p.Name, cframe = p.CFrame, zone = zid })
		Log.event("Map", "DealerSpot %s zone %s", p.Name, zid)
	end
end

local function readSingles(nodes: Instance)
	local van = partsIn(nodes, "Van")[1]
	if van then
		MapLoader.van = van.CFrame
		MapLoader.vanLineupOffset = num(van, "LineupOffset", 12)
		Log.event("Map", "Van %s zone %s", van.Name, MapLoader.zoneAt(van.Position) or "-")
	else
		fail("Van", "no Van node: the run starts at the arena fallback")
	end
	local lineup = partsIn(nodes, "Lineup")[1]
	if lineup then
		MapLoader.lineup = lineup.CFrame
		Log.event("Map", "Lineup %s zone %s", lineup.Name, MapLoader.zoneAt(lineup.Position) or "-")
	end
	local hatch = partsIn(nodes, "Hatch")[1]
	if hatch then
		local zid = str(hatch, "Zone", "tunnel")
		zoneKnown(hatch.Name, zid, "Zone")
		local bottom = hatch:GetAttribute("LadderBottom")
		local top = hatch:GetAttribute("LadderTop")
		local mesh = str(hatch, "Mesh", "")
		MapLoader.hatch = {
			cframe = hatch.CFrame,
			size = hatch.Size,
			mesh = if mesh ~= "" then mesh else nil,
			meshMargin = num(hatch, "MeshMargin", 0),
			zone = zid,
			ladderBottom = hatch.CFrame:PointToWorldSpace(
				if typeof(bottom) == "Vector3" then bottom else Vector3.new(0, -25, 0)
			),
			ladderTop = hatch.CFrame:PointToWorldSpace(if typeof(top) == "Vector3" then top else Vector3.new(-5, 0, 0)),
		}
		if mesh ~= "" and #MapLoader.meshParts(hatch.CFrame, hatch.Size, mesh, num(hatch, "MeshMargin", 0)) == 0 then
			fail(hatch.Name, "Mesh '" .. mesh .. "' matches no geometry part inside the node")
		end
		Log.event("Map", "Hatch %s zone %s", hatch.Name, zid)
	end
	local vr = partsIn(nodes, "VaultRoom")[1]
	if vr then
		local door = str(vr, "Door", "D4")
		if not MapLoader.doors[door] then
			fail(vr.Name, "VaultRoom Door names unknown door group '" .. door .. "'")
		end
		MapLoader.vaultRoom = { cframe = vr.CFrame, size = vr.Size, door = door }
		Log.event("Map", "VaultRoom %s door %s", vr.Name, door)
	else
		fail("VaultRoom", "no VaultRoom node: the vault job is never drawn on this map")
	end
end

-- THE BANK as Room.forMap hands it out. Door gating sits on top (spotOpen / box filters).
local function buildView(): Room.MapView?
	if not MapLoader.loaded then
		return nil
	end
	local vaultSpots = {}
	for _, s in MapLoader.bagSpots do
		local vr = MapLoader.vaultRoom
		if s.zone == "vault" or (vr and MapLoader.inVolume(vr.cframe, vr.size, s.position)) then
			table.insert(vaultSpots, s.position)
		end
	end
	local van = MapLoader.van
	return {
		id = MapLoader.MAP_ID,
		floorTop = Config.FloorTop,
		spawnBoxes = MapLoader.boxes :: any,
		bagSpots = MapLoader.bagSpots,
		vaultSpots = vaultSpots,
		jobSpots = MapLoader.jobSpots,
		dealerSpots = MapLoader.dealerSpots,
		bossWalls = MapLoader.bossWalls,
		van = van,
		lineup = if van then van * CFrame.new(0, 0, -MapLoader.vanLineupOffset) else nil,
		runEndLine = MapLoader.lineup,
	}
end

-- (Re)read every node. Debug Recompute nodes calls this again after a Studio drag.
function MapLoader.read()
	local bank = MapLoader.bank
	local nodes = bank and bank:FindFirstChild("Nodes")
	MapLoader.errors = 0
	MapLoader.zones = {}
	MapLoader.zoneOrder = {}
	MapLoader.links = {}
	MapLoader.doors = {}
	MapLoader.boxes = {}
	MapLoader.bagSpots = {}
	MapLoader.jobSpots = {}
	MapLoader.bossWalls = {}
	MapLoader.dealerSpots = {}
	MapLoader.van = nil
	MapLoader.lineup = nil
	MapLoader.hatch = nil
	MapLoader.vaultRoom = nil
	MapLoader.loaded = false
	if not nodes then
		fail("Bank", "no Workspace.Bank.Nodes folder; THE BANK cannot be played")
		Room.invalidate(MapLoader.MAP_ID)
		return
	end
	MapLoader.nodesFolder = nodes :: Folder
	-- In Studio's edit mode nodes are translucent, labelled and clickable (tools/nodestyle.luau); in a running game
	-- nobody sees them and nothing hits them (debug Show nodes draws them locally).
	for _, d in nodes:GetDescendants() do
		if d:IsA("BasePart") then
			d.Transparency = 1
			d.CanQuery = false
			d.CanCollide = false
			d.CanTouch = false
		elseif d:IsA("BillboardGui") then
			d.Enabled = false
		end
	end
	readZones(nodes)
	readDoors(nodes)
	-- The zone graph's references: neighbours must be zones, gates door groups or "hatch".
	for id, links in MapLoader.links do
		for _, l in links do
			if not MapLoader.zones[l.to] then
				fail(id, "Links names unknown zone '" .. l.to .. "'")
			elseif l.gate ~= "" and l.gate ~= "hatch" and not MapLoader.doors[l.gate] then
				fail(id, "Links gate '" .. l.gate .. "' is not a door group or hatch")
			end
		end
	end
	readBoxes(nodes)
	readSpots(nodes)
	readSingles(nodes)
	if not next(MapLoader.zones) then
		fail("Zones", "no Zone nodes")
	end
	MapLoader.loaded = next(MapLoader.zones) ~= nil
	local doorCount = 0
	for _ in MapLoader.doors do
		doorCount += 1
	end
	Log.event(
		"Map",
		"TheBank: %d zones, %d door groups, %d spawn boxes, %d bag spots, %d job spots, %d error%s",
		#MapLoader.zoneOrder,
		doorCount,
		#MapLoader.boxes,
		#MapLoader.bagSpots,
		#MapLoader.jobSpots,
		MapLoader.errors,
		if MapLoader.errors == 1 then "" else "s"
	)
	Room.invalidate(MapLoader.MAP_ID)
	local after = MapLoader.onRead
	if after then
		after()
	end
	if MapLoader.bank and MapLoader.bank:FindFirstChild("LadderLink") then
		MapLoader.rebuildLadder()
		MapLoader.setHatch(MapLoader.hatchOpen, true)
	end
end

-- Is a zone open (reachable)? The door system (Doors.lua) replaces this; until a door system is installed only
-- the vault and the tunnel, behind the asset's solid wheel doors, are closed.
MapLoader.zoneOpen = function(zone: string): boolean
	return zone ~= "vault" and zone ~= "tunnel"
end

-- Is a spawn box on? The door system replaces this too (door gates, the vault window, the hatch).
MapLoader.boxOpen = function(b: any): boolean
	if b.whileVault or b.doorEver then
		return false
	end
	return MapLoader.zoneOpen(b.zone)
end

-- Doors installs this: the props re-dress after a re-read (Recompute nodes).
MapLoader.onRead = nil :: (() -> ())?

-- Is a graph edge's gate open? Doors installs the real one (door groups, the hatch); until then only ungated
-- edges are.
MapLoader.gateOpen = function(gate: string): boolean
	if gate == "hatch" then
		return MapLoader.hatchOpen
	end
	return gate == ""
end

-- Hops from `from` to every zone along open edges (brief 7: spawn pressure x ZoneDistanceMult ^ hops).
function MapLoader.hops(from: string): { [string]: number }
	local out: { [string]: number } = { [from] = 0 }
	local frontier = { from }
	while #frontier > 0 do
		local nextFrontier = {}
		for _, z in frontier do
			for _, l in MapLoader.links[z] or {} do
				if out[l.to] == nil and MapLoader.gateOpen(l.gate) then
					out[l.to] = out[z] + 1
					table.insert(nextFrontier, l.to)
				end
			end
		end
		frontier = nextFrontier
	end
	return out
end

-- Debug Stats, MAP block: time in each zone this run, the doors opened and when, contact time per box (run
-- averages) and the path budget use (wave average). Pieces from other modules come in as arguments.
function MapLoader.printStats(
	doorsOpened: { any },
	contactRun: { [string]: { sum: number, n: number } },
	pathHistory: { any }
)
	print("[GHS Stats] MAP " .. World.map .. " (crew zone " .. World.crewZone .. ")")
	local zones = {}
	for z, t in MapLoader.zoneTime do
		table.insert(zones, string.format("%s %ds", z, math.round(t)))
	end
	table.sort(zones)
	print("[GHS Stats]   time in zone: " .. (if #zones > 0 then table.concat(zones, ", ") else "-"))
	local doors = {}
	for _, d in doorsOpened do
		table.insert(doors, string.format("%s wave %d (%s)", d.group, d.wave, d.by))
	end
	print("[GHS Stats]   doors opened: " .. (if #doors > 0 then table.concat(doors, ", ") else "-"))
	local boxes = {}
	for name, r in contactRun do
		table.insert(boxes, string.format("%s %.1fs (%d)", name, r.sum / math.max(r.n, 1), r.n))
	end
	table.sort(boxes)
	print("[GHS Stats]   contact per box: " .. (if #boxes > 0 then table.concat(boxes, ", ") else "-"))
	local use, cps, n = 0, 0, 0
	for _, h in pathHistory do
		use += h.budgetUse
		cps += h.computesPerSec
		n += 1
	end
	print(
		string.format(
			"[GHS Stats]   path budget: %d%% avg (%.1f computes/s over %d wave%s)",
			if n > 0 then math.round(use / n * 100) else 0,
			if n > 0 then cps / n else 0,
			n,
			if n == 1 then "" else "s"
		)
	)
end

-- Can a run start on THE BANK? (MapLoaderStrict refuses one on a map with node errors.)
function MapLoader.playable(): boolean
	return MapLoader.loaded and (not Config.MapLoaderStrict or MapLoader.errors == 0)
end

------------------------------------------------------------------ The hatch and the ladder
-- The ladder is a TrussPart players climb as a normal Roblox ladder; enemies use a PathfindingLink (label
-- `ladder`, both ways) from the tunnel floor to the pavement beside the hole, which EnemyPath turns into a lift.
-- Closed, the lid is solid and the link is off; open, the lid swings up and the link is on.
local hatchParts: { { part: BasePart, closed: CFrame, collide: boolean } } = {}
local ladderLink: PathfindingLink? = nil
local linkHolder: BasePart? = nil

local function buildLadder()
	for _, h in hatchParts do
		if h.part.Parent then
			h.part.CFrame = h.closed
		end
	end
	hatchParts = {}
	if ladderLink then
		ladderLink:Destroy()
		ladderLink = nil
	end
	if linkHolder then
		linkHolder:Destroy()
		linkHolder = nil
	end
	local hatch = MapLoader.hatch
	local bank = MapLoader.bank
	if not hatch or not bank then
		return
	end
	if hatch.mesh then
		for _, p in MapLoader.meshParts(hatch.cframe, hatch.size, hatch.mesh, hatch.meshMargin) do
			table.insert(hatchParts, { part = p, closed = p.CFrame, collide = p.CanCollide })
		end
	end
	local holder = Instance.new("Part")
	holder.Name = "LadderLink"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.CFrame = CFrame.new(hatch.ladderTop)
	holder.Parent = bank
	local a0 = Instance.new("Attachment")
	a0.Name = "Bottom"
	a0.WorldPosition = hatch.ladderBottom
	a0.Parent = holder
	local a1 = Instance.new("Attachment")
	a1.Name = "Top"
	a1.WorldPosition = hatch.ladderTop
	a1.Parent = holder
	local link = Instance.new("PathfindingLink")
	link.Label = "ladder"
	link.IsBidirectional = true
	link.Attachment0 = a0
	link.Attachment1 = a1
	linkHolder = holder
	ladderLink = link
end

MapLoader.rebuildLadder = buildLadder

-- Open (lid swung up, non-solid, the ladder link on) or closed (lid down and solid, link off).
function MapLoader.setHatch(open: boolean, instant: boolean?)
	MapLoader.hatchOpen = open
	local hatch = MapLoader.hatch
	if not hatch then
		return
	end
	-- The lid hinges on its edge nearest the ladder top (the -X side of the node) and swings up 110 degrees.
	local hinge = hatch.cframe * CFrame.new(-hatch.size.X / 2, 0, 0)
	local swing = hinge * CFrame.Angles(0, 0, math.rad(-110)) * hinge:Inverse()
	for _, h in hatchParts do
		local goal = if open then swing * h.closed else h.closed
		h.part.CanCollide = if open then false else true
		if instant then
			h.part.CFrame = goal
		else
			TweenService:Create(h.part, TweenInfo.new(0.6, Enum.EasingStyle.Back), { CFrame = goal }):Play()
		end
	end
	if ladderLink then
		ladderLink.Parent = if open then linkHolder else nil
	end
end

------------------------------------------------------------------ The crew zone
-- The zone holding the most standing players (ties: the deeper zone), every CrewZoneSyncSec while a run is on
-- THE BANK. Debug Set crew zone pins it. Each change logs how long the crew held the zone it left.
MapLoader.pinnedZone = nil :: string?
MapLoader.zoneTime = {} :: { [string]: number } -- seconds the crew held each zone this run (Stats MAP block)
local zoneSince = 0

local function measureCrewZone(): string?
	local counts: { [string]: number } = {}
	for _, p in World.runAudience() do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and PlayerState.isStanding(PlayerState.get(p)) then
			local z = MapLoader.nearestZone(root.Position)
			if z then
				counts[z] = (counts[z] or 0) + 1
			end
		end
	end
	local best, bestN, bestDepth = nil, 0, -math.huge
	for z, n in counts do
		local depth = MapLoader.zones[z] and MapLoader.zones[z].depth or 0
		if n > bestN or (n == bestN and depth > bestDepth) then
			best, bestN, bestDepth = z, n, depth
		end
	end
	return best
end

local function setCrewZone(z: string)
	if World.crewZone == z then
		return
	end
	local now = os.clock()
	if World.crewZone ~= "arena" and zoneSince > 0 then
		Log.event("Zone", "wave %d crew %s for %.1f", World.wave, World.crewZone, now - zoneSince)
	end
	zoneSince = now
	World.crewZone = z
	local zone = MapLoader.zones[z]
	World.crewZoneLabel = if zone then zone.label else nil
	PlayerState.markAllDirty()
end

-- Run start: the crew zone starts where the line stands (the street on THE BANK, "arena" elsewhere).
function MapLoader.resetRun()
	MapLoader.zoneTime = {}
	MapLoader.pinnedZone = nil
	zoneSince = 0
	World.crewZone = "arena"
	World.crewZoneLabel = nil
	if World.map == MapLoader.MAP_ID and MapLoader.loaded then
		local lineup = Room.current().lineup
		setCrewZone((lineup and MapLoader.nearestZone(lineup.Position)) or "street")
	end
end

local function crewZoneLoop()
	while true do
		local dt = task.wait(Config.CrewZoneSyncSec)
		if World.map ~= MapLoader.MAP_ID or not MapLoader.loaded or not World.inRunCycle() then
			continue
		end
		if World.inRun() then
			local z = MapLoader.pinnedZone or measureCrewZone()
			if z then
				setCrewZone(z)
			end
			MapLoader.zoneTime[World.crewZone] = (MapLoader.zoneTime[World.crewZone] or 0) + dt
		end
	end
end

function MapLoader.init()
	task.spawn(crewZoneLoop)
	local bank = Workspace:FindFirstChild("Bank")
	if not bank or not bank:IsA("Model") then
		Log.event("Map", "no Workspace.Bank model (sync src/map/Bank.rbxm with Rojo); THE BANK is off")
		return
	end
	MapLoader.bank = bank
	placeBank(bank)
	anchorAll(bank)
	enemyPass(bank)
	MapLoader.read()
	buildLadder()
	MapLoader.setHatch(false, true)
	Room.registerMap(MapLoader.MAP_ID, buildView)
	-- Spots and boxes in closed zones never draw.
	local function onBank(): boolean
		return World.map == MapLoader.MAP_ID
	end
	Bags.spotOpen = function(s: Room.BagSpot): boolean
		return not onBank() or MapLoader.zoneOpen(s.zone)
	end
	CrewCall.spotOpen = function(s: Room.JobSpot): boolean
		return not onBank() or MapLoader.zoneOpen(s.zone)
	end
	Spawner.boxOpen = function(b: any): boolean
		return not onBank() or MapLoader.boxOpen(b)
	end
	Spawner.zoneHops = function(): { [string]: number }?
		if not onBank() then
			return nil
		end
		return MapLoader.hops(World.crewZone)
	end
	-- Paths share routes per zone pair on THE BANK; the arena is all one zone.
	EnemyPath.zoneAt = function(p: Vector3): string?
		if World.map ~= MapLoader.MAP_ID then
			return nil
		end
		return MapLoader.zoneAt(p)
	end
end

return MapLoader
