--!strict
-- Brief 7: builds src/map/Bank.rbxm (Rojo maps it to Workspace.Bank.Geometry) from the builder's place.
--   lune run tools/importbank.luau <Bank.rbxl | Bank.rbxlx>
-- Takes every Workspace child except Camera and Terrain, keeps the builder's hierarchy as it is, and moves the
-- whole set by Config.BankOrigin's offset so THE BANK sits clear of the arena and yard in edit mode too
-- (MapLoader only re-pivots at runtime when BankOrigin is changed afterwards). Nothing is renamed or re-authored.
--
-- Lune 0.8.9 reads binary places written with LZ4 or no compression and XML places. Studio saves binary places
-- zstd-compressed, which this Lune cannot read: save the builder's place as .rbxlx (File > Save to File As) first.
-- Its reflection database also predates the binary `Tags` type, so a binary place that carries CollectionService
-- tags fails to load: the XML save avoids that too.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local CFrame = roblox.CFrame
local Vector3 = roblox.Vector3

local function vec(...: number)
	return { ... }
end
local Config = luau.load(fs.readFile("src/shared/Config.lua"), {
	debugName = "Config",
	environment = { Vector2 = { new = vec }, Vector3 = { new = vec }, CFrame = { new = vec } },
})() :: any

local path = process.args[1]
if not path then
	error("usage: lune run tools/importbank.luau <Bank.rbxl | Bank.rbxlx>")
end
local origin = Config.BankOrigin :: { number }
local offset = Vector3.new(origin[1] or 0, origin[2] or 0, origin[3] or 0)

local game = roblox.deserializePlace(fs.readFile(path))
local ws = game:GetService("Workspace")

local root = roblox.Instance.new("Model")
root.Name = "Geometry"

local moved, kept = 0, 0
for _, child in ws:GetChildren() do
	if child.ClassName == "Camera" or child.ClassName == "Terrain" then
		continue
	end
	child.Parent = root
	kept += 1
end

-- Translate every part and every model pivot by the offset (attachments, welds and lights are relative).
for _, d in root:GetDescendants() do
	if d:IsA("BasePart") then
		local ok, cf = pcall(function()
			return d.CFrame
		end)
		if ok and cf then
			d.CFrame = cf + offset
			moved += 1
		end
	elseif d:IsA("Model") then
		local ok, pivot = pcall(function()
			return d.WorldPivot
		end)
		if ok and pivot then
			d.WorldPivot = pivot + offset
		end
	end
end
root.WorldPivot = CFrame.new(offset)

fs.writeFile("src/map/Bank.rbxm", roblox.serializeModel({ root }))
print(
	string.format(
		"[importbank] %d top-level children, %d parts moved by (%d, %d, %d) -> src/map/Bank.rbxm",
		kept,
		moved,
		offset.X,
		offset.Y,
		offset.Z
	)
)
