--!strict
-- Brief 7: how a node part looks in Studio's edit mode, shared by genbanknodes.luau and exportnodes.luau so every
-- export keeps it. Nodes are translucent boxes in their type colour (Config.NodeShowColor) with a label
-- `TAG · name · key attributes`, selectable by clicking (zones are Locked so clicks reach what is inside them:
-- pick a zone in the Explorer under Workspace.Bank.Nodes.Zones). MapLoader hides all of it when the game runs.
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local function vec(...: number)
	return { ... }
end
local Config = luau.load(fs.readFile("src/shared/Config.lua"), {
	debugName = "Config",
	environment = { Vector2 = { new = vec }, Vector3 = { new = vec }, CFrame = { new = vec } },
})() :: any

local SHORT = {
	Zones = "ZONE",
	Doors = "DOOR",
	SpawnBoxes = "BOX",
	BagSpots = "BAG",
	JobSpots = "JOB",
	BossWalls = "WALL",
	DealerSpots = "DEALER",
	Van = "VAN",
	Lineup = "LINEUP",
	Hatch = "HATCH",
	VaultRoom = "VAULT",
	Fences = "FENCE",
	Offices = "OFFICE", -- Round 19f
	-- Brief 8: the hub.
	Spawn = "SPAWN",
	QueuePads = "PAD",
	Stations = "BOOTH",
	Board = "BOARD",
	GarageDoor = "GARAGE",
	RangeDoor = "RANGE DOOR",
	Range = "RANGE",
	Dummies = "DUMMY",
	PropSpots = "PROP",
	TierPad = "TIER",
	DailyCrate = "DAILY", -- brief 10
}
-- The attributes the label shows per type (the rest are in the Properties panel).
local KEYS = {
	Zones = { "Depth", "Links" },
	Doors = { "Group", "TriggerWave", "DoorStyle" },
	SpawnBoxes = { "Zone", "RequiresDoor", "AllowedTypes" },
	BagSpots = { "Zone", "Gold" },
	JobSpots = { "Zone", "Pool" },
	BossWalls = { "Zone" },
	DealerSpots = { "Zone" },
	Van = {},
	Lineup = {},
	Hatch = { "Zone" },
	VaultRoom = { "Door" },
	Fences = {},
	Offices = { "Zone" },
	Spawn = {},
	QueuePads = { "Index" },
	Stations = { "Tab" },
	Board = {},
	GarageDoor = { "Mesh" },
	RangeDoor = { "Mesh" },
	Range = {},
	Dummies = { "Plates" },
	PropSpots = { "Game" },
	TierPad = {},
	DailyCrate = {},
}

local function hexColor(hex: string): { number }
	local r = tonumber(string.sub(hex, 1, 2), 16) or 255
	local g = tonumber(string.sub(hex, 3, 4), 16) or 255
	local b = tonumber(string.sub(hex, 5, 6), 16) or 255
	return { math.round(r / 255 * 1000) / 1000, math.round(g / 255 * 1000) / 1000, math.round(b / 255 * 1000) / 1000 }
end

-- Type and name only: the attributes are in the Properties panel when the node is selected.
local function label(typeName: string, name: string, _attrs: { [string]: any }): string
	local _ = KEYS
	return (SHORT[typeName] or typeName) .. " · " .. name
end

-- Dress a node (a model.json table: name, properties, attributes) of `typeName` in place and return it.
return function(typeName: string, node: any): any
	local hex = (Config.NodeShowColor :: any)[typeName] or "FFFFFF"
	local color = hexColor(hex)
	local zone = typeName == "Zones" or typeName == "Range" -- volumes: Locked so clicks reach what is inside
	local props = node.properties
	props.Anchored = true
	props.CanCollide = false
	props.CanTouch = false
	props.CastShadow = false
	props.CanQuery = true -- clickable in Studio; MapLoader turns it off at runtime
	props.Locked = zone
	props.Transparency = if zone then 0.93 else 0.55
	props.Color = color
	props.Material = "SmoothPlastic"
	local size = props.Size :: { number }
	node.children = {
		{
			name = "NodeTag",
			className = "BillboardGui",
			properties = {
				-- Behind walls and floors, and only near: the labels read one room at a time.
				AlwaysOnTop = false,
				LightInfluence = 0,
				MaxDistance = if zone then 150 else 60,
				Size = { UDim2 = { { 0, 170 }, { 0, 16 } } },
				StudsOffsetWorldSpace = { 0, (size[2] or 1) / 2 + 1, 0 },
			},
			children = {
				{
					name = "Text",
					className = "TextLabel",
					properties = {
						BackgroundColor3 = { 0.08, 0.08, 0.1 },
						BackgroundTransparency = 0.4,
						BorderSizePixel = 0,
						Size = { UDim2 = { { 1, 0 }, { 1, 0 } } },
						Font = "GothamBold",
						TextSize = 10,
						TextColor3 = color,
						Text = label(typeName, node.name, node.attributes or {}),
					},
				},
			},
		},
	}
	return node
end
