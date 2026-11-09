--!strict
-- Brief 7 / 8: writes a map's nodes back from the node parts you moved in Studio.
--   lune run tools/exportnodes.luau <file> [bank | hub]
-- <file> is either a Nodes folder saved on its own (select Workspace.Bank.Nodes or Workspace.Hub.Nodes > Save to
-- File > .rbxmx) or a whole place. A whole place exports every map it holds (THE BANK -> src/map/Bank.nodes.model.json,
-- the hub -> src/map/Hub.nodes.model.json); a Nodes folder on its own goes to the map its type folders belong to
-- (or the one named as the second argument). Use the XML formats (.rbxmx / .rbxlx): Studio's binary saves are
-- zstd-compressed, which Lune 0.8.9 cannot read (tools/rbxl-uncompress.js rewrites one), and a whole-place XML save
-- carries newer property types it cannot read either, so the Nodes folder on its own as .rbxmx is the reliable route.
--
-- Round-trips each node part's Name, Size, CFrame and every Attribute; the CollectionService tag comes from the
-- type folder it sits in (Zones -> GHS_Zone, ...), so a part dragged into another folder changes type. Rojo picks
-- the file up; restart the play session (or debug MAP > Recompute nodes) to see it.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local style = require("./nodestyle")

type MapDef = { root: string, out: string, order: { string }, tags: { [string]: string } }

local MAPS: { [string]: MapDef } = {
	bank = {
		root = "Bank",
		out = "src/map/Bank.nodes.model.json",
		order = {
			"Zones",
			"Doors",
			"SpawnBoxes",
			"BagSpots",
			"JobSpots",
			"BossWalls",
			"DealerSpots",
			"Van",
			"Lineup",
			"Hatch",
			"VaultRoom",
			"Fences",
			"Offices",
		},
		tags = {
			Zones = "GHS_Zone",
			Doors = "GHS_Door",
			SpawnBoxes = "GHS_SpawnBox",
			BagSpots = "GHS_BagSpot",
			JobSpots = "GHS_JobSpot",
			BossWalls = "GHS_BossWall",
			DealerSpots = "GHS_DealerSpot",
			Van = "GHS_Van",
			Lineup = "GHS_Lineup",
			Hatch = "GHS_Hatch",
			VaultRoom = "GHS_VaultRoom",
			Fences = "GHS_Fence",
			Offices = "GHS_Office", -- Round 19f
		},
	},
	hub = {
		root = "Hub",
		out = "src/map/Hub.nodes.model.json",
		order = {
			"Spawn",
			"QueuePads",
			"Stations",
			"Board",
			"Van",
			"GarageDoor",
			"RangeDoor",
			"Range",
			"Dummies",
			"PropSpots",
			"TierPad",
			"DailyCrate", -- brief 10
		},
		tags = {
			Spawn = "GHS_Spawn",
			QueuePads = "GHS_QueuePad",
			Stations = "GHS_Station",
			Board = "GHS_Board",
			Van = "GHS_Van",
			GarageDoor = "GHS_GarageDoor",
			RangeDoor = "GHS_RangeDoor",
			Range = "GHS_Range",
			Dummies = "GHS_Dummy",
			PropSpots = "GHS_PropSpot",
			TierPad = "GHS_TierPad",
			DailyCrate = "GHS_DailyCrate",
		},
	},
}

local path = process.args[1]
local only = process.args[2] and string.lower(process.args[2]) or nil
if not path then
	error("usage: lune run tools/exportnodes.luau <Nodes.rbxmx | place.rbxlx> [bank | hub]")
end
if only and not MAPS[only] then
	error("the second argument names a map: bank or hub")
end

local function round(v: number): number
	return math.round(v * 1000) / 1000
end

local function attrValue(v: any): any
	local t = typeof(v)
	if t == "Vector3" then
		return { Vector3 = { round(v.X), round(v.Y), round(v.Z) } }
	elseif t == "number" then
		return round(v)
	end
	return v
end

local function exportPart(p: any, tag: string): any
	local cf = p.CFrame
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	local attrs = {}
	for k, v in p:GetAttributes() do
		attrs[k] = attrValue(v)
	end
	return {
		name = p.Name,
		className = "Part",
		properties = {
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Transparency = 1,
			Size = { round(p.Size.X), round(p.Size.Y), round(p.Size.Z) },
			CFrame = {
				CFrame = {
					position = { round(x), round(y), round(z) },
					orientation = {
						{ round(r00), round(r01), round(r02) },
						{ round(r10), round(r11), round(r12) },
						{ round(r20), round(r21), round(r22) },
					},
				},
			},
			Tags = { tag },
		},
		attributes = attrs,
	}
end

local function export(nodes: any, key: string)
	local def = MAPS[key]
	local count = 0
	local out = { className = "Folder", children = {} }
	for _, folderName in def.order do
		local f = nodes:FindFirstChild(folderName)
		local children = {}
		if f then
			for _, p in f:GetChildren() do
				if p:IsA("BasePart") then
					table.insert(children, style(folderName, exportPart(p, def.tags[folderName])))
					count += 1
				end
			end
			table.sort(children, function(a, b)
				return a.name < b.name
			end)
		else
			print(string.format("[exportnodes] %s: no %s folder; writing it empty", key, folderName))
		end
		table.insert(out.children, { name = folderName, className = "Folder", children = children })
	end
	fs.writeFile(def.out, serde.encode("json", out, true))
	print(string.format("[exportnodes] %s: %d nodes from %s -> %s", key, count, path, def.out))
end

-- Which map a bare Nodes folder belongs to: the one whose type folders it holds.
local function guess(nodes: any): string
	if nodes:FindFirstChild("QueuePads") or nodes:FindFirstChild("Range") or nodes:FindFirstChild("Stations") then
		return "hub"
	end
	return "bank"
end

local bytes = fs.readFile(path)
local isPlace = string.match(string.lower(path), "%.rbxlx?$") ~= nil
local done = 0
if isPlace then
	local ws = roblox.deserializePlace(bytes):GetService("Workspace")
	for key, def in MAPS do
		if only and key ~= only then
			continue
		end
		local m = ws:FindFirstChild(def.root)
		local nodes = m and m:FindFirstChild("Nodes")
		if nodes then
			export(nodes, key)
			done += 1
		end
	end
else
	for _, inst in roblox.deserializeModel(bytes) do
		local nodes = if inst.Name == "Nodes" then inst else inst:FindFirstChild("Nodes")
		if nodes then
			export(nodes, only or guess(nodes))
			done += 1
		end
	end
end
if done == 0 then
	error("no Nodes folder in " .. path .. " (expected Workspace.Bank.Nodes / Workspace.Hub.Nodes, or a Nodes folder)")
end
