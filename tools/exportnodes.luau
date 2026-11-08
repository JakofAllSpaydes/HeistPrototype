--!strict
-- Brief 7: writes src/map/Bank.nodes.model.json back from the node parts you moved in Studio.
--   lune run tools/exportnodes.luau <file>
-- <file> is either the Nodes folder saved on its own (select Workspace.Bank.Nodes > Save to File > .rbxmx) or a
-- whole place. Use the XML formats (.rbxmx / .rbxlx): Studio's binary saves are zstd-compressed, which Lune 0.8.9
-- cannot read, and a whole-place XML save carries newer property types it cannot read either, so the Nodes
-- folder on its own as .rbxmx is the reliable route.
--
-- Round-trips each node part's Name, Size, CFrame and every Attribute; the CollectionService tag comes from the
-- type folder it sits in (Zones -> GHS_Zone, ...), so a part dragged into another folder changes type. Rojo picks
-- the file up; restart the play session (or debug MAP > Recompute nodes) to see it.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local style = require("./nodestyle")

local TAGS = {
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
}
local ORDER = {
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
}

local path = process.args[1]
if not path then
	error("usage: lune run tools/exportnodes.luau <Nodes.rbxmx | place.rbxlx>")
end
local bytes = fs.readFile(path)
local nodes: any = nil
local isPlace = string.match(string.lower(path), "%.rbxlx?$") ~= nil
if isPlace then
	local game = roblox.deserializePlace(bytes)
	local bank = game:GetService("Workspace"):FindFirstChild("Bank")
	nodes = bank and bank:FindFirstChild("Nodes")
else
	for _, inst in roblox.deserializeModel(bytes) do
		if inst.Name == "Nodes" then
			nodes = inst
		elseif inst:FindFirstChild("Nodes") then
			nodes = inst:FindFirstChild("Nodes")
		end
	end
end
if not nodes then
	error("no Nodes folder in " .. path .. " (expected Workspace.Bank.Nodes, or the Nodes folder saved on its own)")
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

local count = 0
local function exportPart(p: any, tag: string): any
	local cf = p.CFrame
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	local attrs = {}
	for k, v in p:GetAttributes() do
		attrs[k] = attrValue(v)
	end
	count += 1
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

local out = { className = "Folder", children = {} }
for _, folderName in ORDER do
	local f = nodes:FindFirstChild(folderName)
	local children = {}
	if f then
		for _, p in f:GetChildren() do
			if p:IsA("BasePart") then
				table.insert(children, style(folderName, exportPart(p, TAGS[folderName])))
			end
		end
		table.sort(children, function(a, b)
			return a.name < b.name
		end)
	else
		print("[exportnodes] no " .. folderName .. " folder; writing it empty")
	end
	table.insert(out.children, { name = folderName, className = "Folder", children = children })
end
fs.writeFile("src/map/Bank.nodes.model.json", serde.encode("json", out, true))
print(string.format("[exportnodes] %d nodes from %s -> src/map/Bank.nodes.model.json", count, path))
