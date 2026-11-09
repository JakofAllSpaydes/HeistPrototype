--!strict
-- Brief 8: builds src/map/Hub.rbxm (Rojo maps it to Workspace.Hub.Geometry) from the builder's warehouse place.
--   lune run tools/importhub.luau <Lobby.rbxl | Lobby.rbxlx>
-- Takes every Workspace child except Camera and Terrain and moves the whole set so the floor logo (the star, the
-- spawn) lands on Config.HubOrigin, clear of the arena and THE BANK. Then:
--   * drops every model named by Config.HubImportDrop (matched against the names of the parts inside it, so the
--     builder's unnamed "Model" holding helicopterbase / helicopterblades ... is found and logged);
--   * brief 10: drops every model Config.HubImportDropAt places by name and position (the boxed shelving by the
--     range door is an unnamed `Model` of plain Parts, so only where it stands identifies it);
--   * strips scripts (the booth rigs carry the default Animate LocalScript);
--   * names the parked van's model `Van` (the hub drives it on run start; the Van node points at it).
-- Nothing else is renamed or re-authored.
--
-- Lune 0.8.9 reads binary places written with LZ4 or no compression and XML places. Studio saves binary places
-- zstd-compressed: run `node tools/rbxl-uncompress.js <in.rbxl> <out.rbxl>` first (it also drops the
-- CollectionService Tags property Lune's reflection rejects), or save the place as .rbxlx.
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
	error(
		"usage: lune run tools/importhub.luau <Lobby.rbxl | Lobby.rbxlx>; "
			.. "or: lune run tools/importhub.luau drop   (re-apply the HubImportDropAt drops to src/map/Hub.rbxm)"
	)
end
local origin = Config.HubOrigin :: { number }
local drop = Config.HubImportDrop :: { string }
local dropAt = (Config.HubImportDropAt or {}) :: { { name: string, models: { string }, at: { number }, radius: number } }

-- Brief 10: positional drops. `ax, az` is the floor star's x / z in the geometry's current frame. Only models directly
-- under a top-level child (the builder's `Lobby` folder) are candidates, so a matching model nested in a kept one stays.
local function dropByPosition(geometry: any, ax: number, az: number): number
	local n = 0
	for _, rule in dropAt do
		local names = {}
		for _, m in rule.models do
			names[m] = true
		end
		local hit = {}
		for _, top in geometry:GetChildren() do
			for _, m in top:GetChildren() do
				if m:IsA("Model") and names[m.Name] then
					local sx, sz, parts = 0, 0, 0
					for _, d in m:GetDescendants() do
						if d:IsA("BasePart") then
							local p = d.CFrame.Position
							sx += p.X
							sz += p.Z
							parts += 1
						end
					end
					if parts > 0 then
						local dx = sx / parts - ax - rule.at[1]
						local dz = sz / parts - az - rule.at[2]
						if math.sqrt(dx * dx + dz * dz) <= rule.radius then
							table.insert(hit, m)
						end
					end
				end
			end
		end
		for _, m in hit do
			print(
				string.format(
					"[importhub] dropped %s (%d descendants) for HubImportDropAt %q",
					m:GetFullName(),
					#m:GetDescendants(),
					rule.name
				)
			)
			m.Parent = nil
			n += 1
		end
		if #hit == 0 then
			print(string.format("[importhub] HubImportDropAt %q matched nothing (already dropped?)", rule.name))
		end
	end
	return n
end

-- `drop`: the place was imported before the rule existed; apply the positional drops to the baked geometry (the
-- star already sits on HubOrigin) and write it back.
if path == "drop" then
	local geometry = roblox.deserializeModel(fs.readFile("src/map/Hub.rbxm"))[1]
	local n = dropByPosition(geometry, origin[1] or 0, origin[3] or 0)
	fs.writeFile("src/map/Hub.rbxm", roblox.serializeModel({ geometry }))
	print(string.format("[importhub] drop: %d model%s dropped -> src/map/Hub.rbxm", n, if n == 1 then "" else "s"))
	return
end

local game = roblox.deserializePlace(fs.readFile(path))
local ws = game:GetService("Workspace")

local root = roblox.Instance.new("Model")
root.Name = "Geometry"

local kept = 0
for _, child in ws:GetChildren() do
	if child.ClassName == "Camera" or child.ClassName == "Terrain" then
		continue
	end
	if child:IsA("Folder") and #child:GetChildren() == 0 then
		continue -- the empty Catalog_Imports folder
	end
	child.Parent = root
	kept += 1
end

-- The anchor: the floor logo (the star) if there is one, else the middle of everything.
local anchor: any = nil
for _, d in root:GetDescendants() do
	if d:IsA("BasePart") and string.lower(d.Name) == "logo" then
		anchor = d.CFrame.Position
		break
	end
end
if not anchor then
	local sum, n = Vector3.new(0, 0, 0), 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			sum += d.CFrame.Position
			n += 1
		end
	end
	anchor = sum / math.max(n, 1)
	print("[importhub] no `logo` part: anchoring on the middle of the parts")
end
local offset = Vector3.new((origin[1] or 0) - anchor.X, origin[2] or 0, (origin[3] or 0) - anchor.Z)

-- Drop the listed models: a Model all of whose parts carry the key in their name (the smallest such model wins).
local dropped = 0
for _, key in drop do
	local k = string.lower(key)
	local candidates = {}
	for _, d in root:GetDescendants() do
		if d:IsA("Model") then
			local parts, hits = 0, 0
			for _, c in d:GetDescendants() do
				if c:IsA("BasePart") then
					parts += 1
					if string.find(string.lower(c.Name), k, 1, true) then
						hits += 1
					end
				end
			end
			if parts > 0 and hits == parts then
				table.insert(candidates, d)
			end
		end
	end
	for _, m in candidates do
		-- Only the outermost matching model (a model inside a dropped one goes with it).
		local p = m.Parent
		local nested = false
		while p and p ~= root do
			if table.find(candidates, p) then
				nested = true
				break
			end
			p = p.Parent
		end
		if not nested and m.Parent then
			print(
				string.format(
					"[importhub] dropped %s (%d descendants) for HubImportDrop %q",
					m:GetFullName(),
					#m:GetDescendants(),
					key
				)
			)
			m.Parent = nil
			dropped += 1
		end
	end
end

dropped += dropByPosition(root, anchor.X, anchor.Z)

-- Scripts never come along.
local stripped = 0
for _, d in root:GetDescendants() do
	if d:IsA("LuaSourceContainer") then
		d.Parent = nil
		stripped += 1
	end
end

-- The parked van: the model whose parts are all named van*.
local vanNamed = false
for _, d in root:GetDescendants() do
	if d:IsA("Model") and not vanNamed then
		local parts, hits = 0, 0
		for _, c in d:GetChildren() do
			if c:IsA("BasePart") then
				parts += 1
				if string.sub(string.lower(c.Name), 1, 3) == "van" then
					hits += 1
				end
			end
		end
		if parts >= 3 and hits == parts then
			print(string.format("[importhub] the van: %s (%d parts) -> named Van", d:GetFullName(), parts))
			d.Name = "Van"
			vanNamed = true
		end
	end
end
if not vanNamed then
	print("[importhub] no van model found (a model of van* parts); the hub will run without a van")
end

-- Translate every part and every model pivot by the offset (attachments, welds and lights are relative).
local moved = 0
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
root.WorldPivot = CFrame.new(origin[1] or 0, origin[2] or 0, origin[3] or 0)

fs.writeFile("src/map/Hub.rbxm", roblox.serializeModel({ root }))
print(
	string.format(
		"[importhub] %d top-level children, %d parts moved by (%.1f, %.1f, %.1f), %d dropped, %d scripts stripped -> src/map/Hub.rbxm",
		kept,
		moved,
		offset.X,
		offset.Y,
		offset.Z,
		dropped,
		stripped
	)
)
