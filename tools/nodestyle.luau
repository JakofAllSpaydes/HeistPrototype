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
}

local function hexColor(hex: string): { number }
	local r = tonumber(string.sub(hex, 1, 2), 16) or 255
	local g = tonumber(string.sub(hex, 3, 4), 16) or 255
	local b = tonumber(string.sub(hex, 5, 6), 16) or 255
	return { math.round(r / 255 * 1000) / 1000, math.round(g / 255 * 1000) / 1000, math.round(b / 255 * 1000) / 1000 }
end

local function label(typeName: string, name: string, attrs: { [string]: any }): string
	local bits = { SHORT[typeName] or typeName, name }
	for _, k in KEYS[typeName] or {} do
		local v = attrs[k]
		if v ~= nil and v ~= "" and type(v) ~= "table" then
			table.insert(bits, string.format("%s %s", k, tostring(v)))
		end
	end
	return table.concat(bits, " · ")
end

-- Dress a node (a model.json table: name, properties, attributes) of `typeName` in place and return it.
return function(typeName: string, node: any): any
	local hex = (Config.NodeShowColor :: any)[typeName] or "FFFFFF"
	local color = hexColor(hex)
	local zone = typeName == "Zones"
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
				AlwaysOnTop = true,
				LightInfluence = 0,
				MaxDistance = if zone then 600 else 220,
				Size = { UDim2 = { { 0, 260 }, { 0, 18 } } },
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
						TextSize = 11,
						TextColor3 = color,
						Text = label(typeName, node.name, node.attributes or {}),
					},
				},
			},
		},
	}
	return node
end
