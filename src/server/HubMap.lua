--!strict
-- Brief 8: the warehouse hub's map loader. Workspace.Hub is the builder's warehouse (Geometry, from
-- tools/importhub.luau) plus its nodes (Nodes, src/map/Hub.nodes.model.json): one Part per node under a folder per
-- type, Name = id, Size / CFrame = the volume, Attributes = config (the brief 7 node spec). This reads them into the
-- hub's view, which the hub slot's Room hands out as Room.forMap("Hub") (spawn, pads, booths, the board, the van and
-- garage, the range, its dummies and prop spots; the run-only fields are empty). One `[GHS Map] hub …` line per node;
-- a missing or broken node is an `ERROR` line and that piece is off.
-- (THE BANK's loader is Run/MapLoader, one per run slot; the hub has a single loader shared by everyone.)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Room = require(script.Parent.Run.Room)
local Log = require(script.Parent.Log)

export type Station = { tab: string, part: BasePart, rig: Model? }
export type Door = { part: BasePart, mesh: Instance?, openSec: number }
export type Volume = { cframe: CFrame, size: Vector3 }
export type Dummy = { name: string, cframe: CFrame, plates: boolean }
export type View = {
	spawn: CFrame, -- the floor point on the star, facing the pads
	pads: { Room.Zone },
	stations: { Station },
	board: BasePart?,
	van: BasePart?, -- the Van node (the parked van's floor point and facing)
	vanModel: Model?,
	garage: Door?,
	rangeDoor: Door?,
	range: Volume?,
	dummies: { Dummy },
	propSpots: { [string]: CFrame }, -- by game id (lockpick ... cut)
	tierPad: Volume?,
}

local HubMap = {}

HubMap.MAP_ID = "Hub"
HubMap.model = nil :: Model?
HubMap.nodes = nil :: Instance?
HubMap.errors = 0
HubMap.loaded = false
HubMap.view = nil :: View?

local function fail(what: string, reason: string)
	HubMap.errors += 1
	Log.event("Map", "ERROR hub %s: %s", what, reason)
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
	table.sort(out, function(a, b)
		return a.Name < b.Name
	end)
	return out
end

local function str(p: Instance, key: string, default: string): string
	local v = p:GetAttribute(key)
	return if typeof(v) == "string" then v else default
end

local function num(p: Instance, key: string, default: number): number
	local v = p:GetAttribute(key)
	return if typeof(v) == "number" then v else default
end

-- A model named `name` in the geometry, the one nearest `near`.
local function nearestModel(name: string, near: Vector3, maxDist: number): Model?
	local model = HubMap.model
	local geo = model and model:FindFirstChild("Geometry")
	if not geo or name == "" then
		return nil
	end
	local best: Model? = nil
	local bestD = maxDist
	for _, d in geo:GetDescendants() do
		if d:IsA("Model") and d.Name == name then
			local d2 = (d:GetPivot().Position - near).Magnitude
			if d2 < bestD then
				bestD = d2
				best = d
			end
		end
	end
	return best
end

local function door(p: BasePart): Door
	local meshName = str(p, "Mesh", "")
	local mesh = if meshName ~= "" then nearestModel(meshName, p.Position, 30) else nil
	if meshName ~= "" and not mesh then
		local geo = HubMap.model and HubMap.model:FindFirstChild("Geometry")
		mesh = geo and geo:FindFirstChild(meshName, true)
		if not mesh then
			fail(p.Name, "Mesh " .. meshName .. " not found in the geometry; the hub builds a shutter")
		end
	end
	return { part = p, mesh = mesh, openSec = num(p, "OpenSec", Config.HubDoorRollSec) }
end

-- The import baked the hub at Config.HubOrigin; when HubOrigin changes the whole model moves at load (like THE BANK).
local function place(hub: Model)
	local geo = hub:FindFirstChild("Geometry")
	if not geo or not geo:IsA("Model") then
		return
	end
	local baked = geo.WorldPivot
	local target = Config.HubOrigin
	if baked.Position:FuzzyEq(target.Position, 0.01) and baked.LookVector:FuzzyEq(target.LookVector, 0.001) then
		return
	end
	local delta = target * baked:Inverse()
	hub:PivotTo(delta * hub:GetPivot())
	geo.WorldPivot = target
	Log.event("Map", "hub moved to HubOrigin (%d, %d, %d)", target.X, target.Y, target.Z)
end

function HubMap.read()
	local hub = HubMap.model
	local nodes = hub and hub:FindFirstChild("Nodes")
	HubMap.errors = 0
	HubMap.loaded = false
	HubMap.view = nil
	HubMap.nodes = nodes
	if not nodes then
		fail("Nodes", "no Workspace.Hub.Nodes folder; players spawn at HubOrigin with no pads or booths")
		Room.invalidate(HubMap.MAP_ID)
		return
	end
	-- Edit-mode boxes (tools/nodestyle.luau) go invisible and unclickable in a running game (debug Show nodes
	-- draws them locally).
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

	local view: View = {
		spawn = CFrame.new(Config.HubOrigin.Position),
		pads = {},
		stations = {},
		board = nil,
		van = nil,
		vanModel = nil,
		garage = nil,
		rangeDoor = nil,
		range = nil,
		dummies = {},
		propSpots = {},
		tierPad = nil,
	}

	local spawn = partsIn(nodes, "Spawn")[1]
	if spawn then
		local p = spawn.Position - Vector3.new(0, spawn.Size.Y / 2, 0)
		view.spawn = CFrame.lookAt(p, p + spawn.CFrame.LookVector * Vector3.new(1, 0, 1))
		Log.event("Map", "hub Spawn %s at (%.0f, %.1f, %.0f)", spawn.Name, p.X, p.Y, p.Z)
	else
		fail("Spawn", "no Spawn node; players spawn at HubOrigin")
	end

	local seen: { [number]: boolean } = {}
	for _, p in partsIn(nodes, "QueuePads") do
		local index = math.floor(num(p, "Index", #view.pads + 1))
		if seen[index] then
			fail(p.Name, "Index " .. index .. " is used twice")
			continue
		end
		seen[index] = true
		-- The billboard hangs over the pad's back edge (the side its node faces: the wall).
		local anchor = Instance.new("Part")
		anchor.Name = "PadBoard" .. index
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.Transparency = 1
		anchor.Size = Vector3.new(1, 1, 1)
		anchor.CFrame = CFrame.new(p.Position + p.CFrame.LookVector * (p.Size.Z / 2) + Vector3.new(0, 6.5, 0))
		anchor.Parent = nodes
		table.insert(view.pads, { index = index, pad = p, gate = nil, billboardAnchor = anchor })
		Log.event("Map", "hub QueuePad %s index %d", p.Name, index)
	end
	table.sort(view.pads, function(a, b)
		return a.index < b.index
	end)
	if #view.pads == 0 then
		fail("QueuePads", "no QueuePad nodes; there is no queue")
	end

	for _, p in partsIn(nodes, "Stations") do
		local tab = string.upper(str(p, "Tab", ""))
		if not table.find(Room.StationTabs, tab) then
			fail(p.Name, "Tab must be weapons / classes / avatar, got " .. tab)
			continue
		end
		local rig = nearestModel(str(p, "Rig", "Rig"), p.Position, 30)
		table.insert(view.stations, { tab = tab, part = p, rig = rig })
		Log.event("Map", "hub Station %s tab %s rig %s", p.Name, tab, if rig then rig:GetFullName() else "none")
	end

	view.board = partsIn(nodes, "Board")[1]
	if view.board then
		Log.event("Map", "hub Board %s", view.board.Name)
	else
		fail("Board", "no Board node; MARLOW's board is off (JOBS on the HUD still opens it)")
	end

	local van = partsIn(nodes, "Van")[1]
	if van then
		view.van = van
		local m = nearestModel(str(van, "Mesh", "Van"), van.Position, 60)
		view.vanModel = m
		Log.event("Map", "hub Van %s model %s", van.Name, if m then m:GetFullName() else "none")
		if not m then
			fail(van.Name, "no van model near the Van node (Mesh " .. str(van, "Mesh", "Van") .. ")")
		end
	end
	local garage = partsIn(nodes, "GarageDoor")[1]
	if garage then
		view.garage = door(garage)
		Log.event("Map", "hub GarageDoor %s", garage.Name)
	end
	local rangeDoor = partsIn(nodes, "RangeDoor")[1]
	if rangeDoor then
		view.rangeDoor = door(rangeDoor)
		Log.event("Map", "hub RangeDoor %s", rangeDoor.Name)
	end
	local range = partsIn(nodes, "Range")[1]
	if range then
		view.range = { cframe = range.CFrame, size = range.Size }
		Log.event("Map", "hub Range %s %.0f x %.0f", range.Name, range.Size.X, range.Size.Z)
	end
	for _, p in partsIn(nodes, "Dummies") do
		local base = p.Position - Vector3.new(0, p.Size.Y / 2, 0)
		local cf = CFrame.lookAt(base, base + p.CFrame.LookVector * Vector3.new(1, 0, 1))
		table.insert(view.dummies, { name = p.Name, cframe = cf, plates = p:GetAttribute("Plates") == true })
		Log.event("Map", "hub Dummy %s%s", p.Name, if p:GetAttribute("Plates") == true then " plates" else "")
	end
	for _, p in partsIn(nodes, "PropSpots") do
		local game = string.lower(str(p, "Game", ""))
		local known = false
		for _, name in Room.PropNames do
			if string.lower(name) == game then
				known = true
			end
		end
		if not known then
			fail(p.Name, "Game must be one of the minigame props, got " .. game)
			continue
		end
		local base = p.Position - Vector3.new(0, p.Size.Y / 2, 0)
		view.propSpots[game] = CFrame.lookAt(base, base + p.CFrame.LookVector * Vector3.new(1, 0, 1))
		Log.event("Map", "hub PropSpot %s game %s", p.Name, game)
	end
	local tier = partsIn(nodes, "TierPad")[1]
	if tier then
		view.tierPad = { cframe = tier.CFrame, size = tier.Size }
		Log.event("Map", "hub TierPad %s", tier.Name)
	end

	HubMap.view = view
	HubMap.loaded = true
	Room.invalidate(HubMap.MAP_ID)
	Log.event(
		"Map",
		"hub: %d pads, %d booths, %d dummies, %d prop spots, %d error%s",
		#view.pads,
		#view.stations,
		#view.dummies,
		(function()
			local n = 0
			for _ in view.propSpots do
				n += 1
			end
			return n
		end)(),
		HubMap.errors,
		if HubMap.errors == 1 then "" else "s"
	)
end

-- Inside the range volume (XZ and height), plus `margin` studs.
function HubMap.inRange(point: Vector3, margin: number?): boolean
	local v = HubMap.view
	local r = v and v.range
	if not r then
		return false
	end
	local p = r.cframe:PointToObjectSpace(point)
	local m = margin or 0
	return math.abs(p.X) <= r.size.X / 2 + m and math.abs(p.Y) <= r.size.Y / 2 + m and math.abs(p.Z) <= r.size.Z / 2 + m
end

function HubMap.init()
	local hub = Workspace:FindFirstChild("Hub")
	if not hub or not hub:IsA("Model") then
		Log.event(
			"Map",
			"no Workspace.Hub model (sync src/map/Hub.rbxm with Rojo; restart rojo serve after pulling brief 8)"
		)
		return
	end
	HubMap.model = hub
	place(hub)
	-- Map geometry never moves on its own.
	local geo = hub:FindFirstChild("Geometry")
	if geo then
		for _, d in geo:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
			end
		end
	end
	HubMap.read()
	-- Room.forMap("Hub"): the hub's view in the maps' shape (no spawn boxes, spots, dealer or boss walls).
	Room.registerMap(HubMap.MAP_ID, function(): Room.MapView?
		local v = HubMap.view
		if not v then
			return nil
		end
		return {
			id = HubMap.MAP_ID,
			floorTop = v.spawn.Position.Y,
			spawnBoxes = {},
			bagSpots = {},
			vaultSpots = {},
			jobSpots = {},
			dealerSpots = {},
			bossWalls = {},
			van = if v.van then v.van.CFrame else nil,
			lineup = nil,
			runEndLine = nil,
			hub = v,
		}
	end)
end

return HubMap
