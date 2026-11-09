--!strict
-- Brief 8: the first node set for the warehouse hub, written once to src/map/Hub.nodes.model.json (Rojo maps it to
-- Workspace.Hub.Nodes). After this run the file is maintained in Studio: drag the parts, save Workspace.Hub.Nodes
-- as .rbxmx, and run `lune run tools/exportnodes.luau Nodes.rbxmx hub`; never edit attributes in the json.
--   lune run tools/genhubnodes.luau
--   lune run tools/genhubnodes.luau append   (brief 10: adds only the node types the file is missing, keeps the rest)
--
-- How it was authored (Nov 2026, from the builder's place read with Lune): coordinates below are relative to the
-- floor logo (the star), which tools/importhub.luau bakes onto Config.HubOrigin. North is -Z.
--   hall    floor y 1.0, x -60..60 (walls at x ±60.5), z -64.8..45 (north wall at -64.8)
--   pads    four yellow 15-stud pads at x -27 / -9 / 9 / 27, z -50.3, top y 2.9, on a 2-stud step along the north wall
--   board   the corkboard on the north wall at x 0, y 10.6 (11.2 x 7.7), between pads 2 and 3
--   booths  stages 3.5 high, an orange half-circle on each (the Station node): WEAPONS west (circle x -46.3, rig
--           x -52), CLASSES east (circle x 46.3, rig x 52),
--           AVATAR south (circle z 36, rig z 41.3)
--   garage  the north-east roll-up opening in the east wall: x 60.5, z -43.8, 17 wide, 16.5 high (no door panel in
--           the asset: the hub builds the shutter); the van was parked straddling it, nose out
--   range   the north-west opening in the west wall (x -60.5, z -43.8) onto the walled bay x -118.4..-60.5,
--           z -89.3..-18.3, floor y 1.1; the striped pad just outside the door (x -79..-60, z -56..-31)
-- Deviation from the brief (flagged in the README): the dummies stand at the far (west) end of the bay facing the
-- door, not on the striped pad by the door, so you shoot across the bay; the striped pad is the firing line.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local function vec(...: number)
	return { ... }
end
local Config = luau.load(fs.readFile("src/shared/Config.lua"), {
	debugName = "Config",
	environment = { Vector2 = { new = vec }, Vector3 = { new = vec }, CFrame = { new = vec } },
})() :: any
local O = Config.HubOrigin :: { number }
local OX, OY, OZ = O[1] or 0, O[2] or 0, O[3] or 0

-- Landmarks read from the imported geometry: the four pads' neon squares (the pads are the asset's own art).
local geo = roblox.deserializeModel(fs.readFile("src/map/Hub.rbxm"))[1]
local pads = {}
for _, d in geo:GetDescendants() do
	if
		d:IsA("BasePart")
		and d.Parent
		and d.Parent.Name == "Pad"
		and d.Material == roblox.Enum.Material.Neon
		and d.Size.X > 10
		and d.Size.Z > 10
	then
		local p = d.CFrame.Position
		table.insert(pads, { p.X - OX, p.Y + d.Size.Y / 2 - OY, p.Z - OZ })
	end
end
table.sort(pads, function(a, b)
	return a[1] < b[1]
end)
assert(#pads == 4, "expected four Pad neon squares, found " .. #pads)
print(
	string.format(
		"[genhubnodes] pads at x %.1f / %.1f / %.1f / %.1f, z %.1f, top y %.2f",
		pads[1][1],
		pads[2][1],
		pads[3][1],
		pads[4][1],
		pads[1][3],
		pads[1][2]
	)
)

------------------------------------------------------------------ model.json helpers
local function yaw(deg: number): { { number } }
	local r = math.rad(deg)
	local c, s = math.cos(r), math.sin(r)
	local function clean(v: number): number
		return if math.abs(v) < 1e-9 then 0 else math.round(v * 1e6) / 1e6
	end
	return { { clean(c), 0, clean(s) }, { 0, 1, 0 }, { clean(-s), 0, clean(c) } }
end

-- facing: yaw in degrees; 0 faces -Z (north, toward the pads), 180 faces +Z, 90 faces -X (west), -90 faces +X (east).
local function node(name: string, pos: { number }, size: { number }, facing: number?, attrs: { [string]: any }?): any
	local p = { pos[1] + OX, pos[2] + OY, pos[3] + OZ }
	return {
		name = name,
		className = "Part",
		properties = {
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Transparency = 1,
			Size = size,
			CFrame = { CFrame = { position = p, orientation = yaw(facing or 0) } },
		},
		attributes = attrs or {},
	}
end

local style = require("./nodestyle")

local function folder(name: string, tag: string, children: { any }): any
	for _, c in children do
		c.properties.Tags = { tag }
		style(name, c)
	end
	return { name = name, className = "Folder", children = children }
end

------------------------------------------------------------------ The hall
local spawn = { node("star", { 0, 1, 0 }, { 2, 1, 2 }, 0, {}) }

local queuePads = {}
for i, p in pads do
	table.insert(queuePads, node("pad" .. i, { p[1], p[2], p[3] }, { 14, 0.4, 14 }, 0, { Index = i }))
end

local board = { node("board", { 0, 10.6, -64.3 }, { 11.2, 7.7, 0.4 }, 180, {}) }

local stations = {
	-- Each booth node is the orange half-circle on its stage (walk onto it: the scene opens on that tab).
	node("weapons", { -46.3, 7.5, -0.8 }, { 19.8, 6, 6.9 }, -90, { Tab = "weapons", Rig = "Rig" }),
	node("classes", { 46.3, 7.5, -0.8 }, { 19.8, 6, 6.9 }, 90, { Tab = "classes", Rig = "Rig" }),
	node("avatar", { 0, 7.6, 36 }, { 19.5, 6, 6.8 }, 0, { Tab = "avatar", Rig = "Rig" }),
}

------------------------------------------------------------------ The garage
-- The van parks fully inside, nose to the door, so the shutter can come down behind nothing.
local van = { node("van", { 45, 1, -43.8 }, { 11, 9, 25 }, -90, { Mesh = "Van" }) }
local garage = { node("garage", { 60.5, 9.25, -43.8 }, { 17, 16.5, 1 }, -90, { Mesh = "", OpenSec = 1.2 }) }

------------------------------------------------------------------ The range (the old helicopter bay)
local rangeDoor = { node("range_door", { -60.5, 9.25, -43.8 }, { 17, 16.5, 1 }, 90, { Mesh = "" }) }
local range = { node("range", { -89.45, 13, -53.8 }, { 57.9, 24, 71 }, 0, {}) }
local dummies = {
	node("dummy1", { -108, 1.1, -42.3 }, { 3, 6, 2 }, -90, { Plates = false }),
	node("dummy2", { -108, 1.1, -53.8 }, { 3, 6, 2 }, -90, { Plates = true }),
	node("dummy3", { -108, 1.1, -65.3 }, { 3, 6, 2 }, -90, { Plates = false }),
}
local props = {}
for i, game in { "lockpick", "hotwire", "keypad", "charges", "safe", "freq", "cut" } do
	table.insert(props, node("prop_" .. game, { -120 + i * 4, 1.1, -85.8 }, { 4, 6, 1 }, 180, { Game = game }))
end
local tierPad = { node("tier", { -110, 1.1, -23.3 }, { 10, 0.4, 4 }, 0, {}) }

------------------------------------------------------------------ Brief 10: the daily crate podium
-- Round 27b: where the red and blue drums stood (dropped by Config.HubImportDropAt), on the hall floor in front of the
-- loading platform's east wall, south of its steps, in plain view from the star. The node is the pedestal's volume,
-- facing the star (yaw -115.5: +X, 25 degrees toward +Z).
local dailyCrate = { node("daily", { -30.4, 1.75, -15 }, { 6, 1.5, 4.4 }, -115.5, {}) }

local out = {
	className = "Folder",
	children = {
		folder("Spawn", "GHS_Spawn", spawn),
		folder("QueuePads", "GHS_QueuePad", queuePads),
		folder("Stations", "GHS_Station", stations),
		folder("Board", "GHS_Board", board),
		folder("Van", "GHS_Van", van),
		folder("GarageDoor", "GHS_GarageDoor", garage),
		folder("RangeDoor", "GHS_RangeDoor", rangeDoor),
		folder("Range", "GHS_Range", range),
		folder("Dummies", "GHS_Dummy", dummies),
		folder("PropSpots", "GHS_PropSpot", props),
		folder("TierPad", "GHS_TierPad", tierPad),
		folder("DailyCrate", "GHS_DailyCrate", dailyCrate),
	},
}
if process.args[1] == "append" then
	-- The file is maintained in Studio after the first run: add only the missing node types.
	local existing = serde.decode("json", fs.readFile("src/map/Hub.nodes.model.json"))
	local have = {}
	for _, f in existing.children do
		have[f.name] = true
	end
	local added = 0
	for _, f in out.children do
		if not have[f.name] then
			table.insert(existing.children, f)
			added += 1
			print(
				string.format(
					"[genhubnodes] append %s (%d node%s)",
					f.name,
					#f.children,
					if #f.children == 1 then "" else "s"
				)
			)
		end
	end
	fs.writeFile("src/map/Hub.nodes.model.json", serde.encode("json", existing, true))
	print(string.format("[genhubnodes] append: %d node type%s added", added, if added == 1 then "" else "s"))
	return
end
fs.writeFile("src/map/Hub.nodes.model.json", serde.encode("json", out, true))
local n = 0
for _, f in out.children do
	n += #f.children
end
print(string.format("[genhubnodes] %d nodes -> src/map/Hub.nodes.model.json", n))
