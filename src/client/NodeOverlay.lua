--!strict
-- Debug MAP > Show nodes (brief 7): every node part under Workspace.Bank.Nodes drawn locally as a translucent
-- box in its type colour (Config.NodeShowColor) with a small billboard `TAG · name · key attributes`, toggled
-- per type. Local only: the parts stay invisible for everyone else and on the server. Move nodes in Studio
-- (edit mode) and export them with `lune run tools/exportnodes.luau`; this overlay is how they are reviewed.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local NodeOverlay = {}

NodeOverlay.TYPES = {
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
}
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
}
-- Which attributes the billboard shows per type (the rest stay in Studio's Properties panel).
local KEYS = {
	Zones = { "Depth", "Label", "Links" },
	Doors = { "Group", "Opens", "TriggerWave", "DoorStyle" },
	SpawnBoxes = { "Zone", "RequiresDoor", "AllowedTypes", "Weight" },
	BagSpots = { "Zone", "Gold" },
	JobSpots = { "Zone", "Pool" },
	BossWalls = { "Zone" },
	DealerSpots = { "Zone" },
	Van = {},
	Lineup = {},
	Hatch = { "Zone" },
	VaultRoom = { "Door" },
	Fences = {},
}

NodeOverlay.on = false
NodeOverlay.shown = {} :: { [string]: boolean }
for _, t in NodeOverlay.TYPES do
	NodeOverlay.shown[t] = t ~= "Zones" -- zones are big: off until asked for
end

local drawn: { [BasePart]: { transparency: number, gui: BillboardGui } } = {}

-- Type and name; `full` adds the key attributes (unused for now: they read in Studio's Properties panel).
local function label(part: BasePart, typeName: string, full: boolean?): string
	local bits = { SHORT[typeName] or typeName, part.Name }
	if full then
		for _, k in KEYS[typeName] or {} do
			local v = part:GetAttribute(k)
			if v ~= nil and v ~= "" then
				table.insert(bits, string.format("%s %s", k, tostring(v)))
			end
		end
	end
	return table.concat(bits, " · ")
end

local function clear()
	for part, d in drawn do
		if part.Parent then
			part.Transparency = d.transparency
		end
		d.gui:Destroy()
	end
	drawn = {}
end

-- Redraw from the current parts (also picks up nodes moved or re-read since the last draw).
function NodeOverlay.refresh()
	clear()
	if not NodeOverlay.on then
		return
	end
	local bank = Workspace:FindFirstChild("Bank")
	local nodes = bank and bank:FindFirstChild("Nodes")
	if not nodes then
		return
	end
	for _, typeName in NodeOverlay.TYPES do
		local f = nodes:FindFirstChild(typeName)
		if not f or not NodeOverlay.shown[typeName] then
			continue
		end
		local hex = (Config.NodeShowColor :: any)[typeName] or "FFFFFF"
		local color = Color3.fromHex(hex)
		for _, p in f:GetChildren() do
			if not p:IsA("BasePart") then
				continue
			end
			local before = p.Transparency
			p.Color = color
			p.Material = Enum.Material.ForceField
			p.Transparency = if typeName == "Zones" then 0.9 else 0.55
			local gui = Instance.new("BillboardGui")
			gui.Name = "NodeTag"
			gui.Adornee = p
			gui.AlwaysOnTop = false -- behind walls and floors: one room at a time
			gui.LightInfluence = 0
			gui.MaxDistance = if typeName == "Zones" then 150 else 60
			gui.Size = UDim2.fromOffset(170, 16)
			gui.StudsOffsetWorldSpace = Vector3.new(0, p.Size.Y / 2 + 1, 0)
			local t = Instance.new("TextLabel")
			t.BackgroundTransparency = 0.4
			t.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
			t.BorderSizePixel = 0
			t.Size = UDim2.fromScale(1, 1)
			t.Font = Enum.Font.GothamBold
			t.TextSize = 10
			t.TextColor3 = color
			t.Text = label(p, typeName)
			t.Parent = gui
			gui.Parent = p
			drawn[p] = { transparency = before, gui = gui }
		end
	end
end

------------------------------------------------------------------ Path debug
-- Each pathing enemy's route as a thin line with dots at the waypoints, red while the enemy is stuck.
local pathFolder: Folder? = nil
function NodeOverlay.drawPaths(paths: { any })
	if pathFolder then
		pathFolder:Destroy()
		pathFolder = nil
	end
	if #paths == 0 then
		return
	end
	local f = Instance.new("Folder")
	f.Name = "PathDebug"
	f.Parent = Workspace
	pathFolder = f
	local function seg(a: Vector3, b: Vector3, color: Color3)
		local len = (b - a).Magnitude
		if len < 0.05 then
			return
		end
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = color
		p.Size = Vector3.new(0.15, 0.15, len)
		p.CFrame = CFrame.lookAt((a + b) / 2, b)
		p.Parent = f
	end
	for _, path in paths do
		local color = if path.stuck then Color3.fromHex("E8554D") else Color3.fromHex("6FB8FF")
		local prev: Vector3 = path.from
		for _, pt in path.pts do
			local p = pt + Vector3.new(0, 0.4, 0)
			seg(prev, p, color)
			local dot = Instance.new("Part")
			dot.Shape = Enum.PartType.Ball
			dot.Anchored = true
			dot.CanCollide = false
			dot.CanQuery = false
			dot.CanTouch = false
			dot.Material = Enum.Material.Neon
			dot.Color = color
			dot.Size = Vector3.new(0.5, 0.5, 0.5)
			dot.Position = p
			dot.Parent = f
			prev = p
		end
	end
end

function NodeOverlay.setOn(on: boolean)
	NodeOverlay.on = on
	NodeOverlay.refresh()
end

function NodeOverlay.setType(typeName: string, on: boolean)
	NodeOverlay.shown[typeName] = on
	NodeOverlay.refresh()
end

return NodeOverlay
