--!strict
-- Brief 13: THE BANK's street dressing templates, written once to src/map/Bank.dressing.rbxmx (Rojo maps it to
-- Workspace.Bank.Dressing). Brick-built placeholders in the hub's palette until art lands: Cruiser, SwatVan,
-- Ambulance, Barricade, Tape, Cone, Sawhorse, Searchlight, Helicopter. They stand in a row behind the grass in edit
-- mode (Workspace.Bank.Dressing.Templates) so they can be reshaped / rescaled in Studio; at runtime Dressing.lua
-- takes the folder out of the world and clones a template onto every Dressing node whose Stage the run has reached.
-- Each template is a Model with a `Root` part at its ground centre facing -Z (the clone is pivoted on it).
--   lune run tools/genbankdressing.luau          (refuses to overwrite an existing file)
--   lune run tools/genbankdressing.luau force    (rewrites it: Studio edits to the templates are lost)
-- After editing templates in Studio, select Workspace.Bank.Dressing and Save to File over src/map/Bank.dressing.rbxmx.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local Enum = roblox.Enum

local OUT = "src/map/Bank.dressing.rbxmx"
if fs.isFile(OUT) and process.args[1] ~= "force" then
	print("[genbankdressing] " .. OUT .. " exists; pass `force` to rewrite it (Studio edits would be lost)")
	return
end

local function vec(...: number)
	return { ... }
end
local Config = luau.load(fs.readFile("src/shared/Config.lua"), {
	debugName = "Config",
	environment = { Vector2 = { new = vec }, Vector3 = { new = vec }, CFrame = { new = vec } },
})() :: any
local O = Config.BankOrigin :: { number }
local OX, OY, OZ = O[1] or 0, O[2] or 0, O[3] or 0

local function hex(h: string): any
	return Color3.fromRGB(
		tonumber(string.sub(h, 1, 2), 16),
		tonumber(string.sub(h, 3, 4), 16),
		tonumber(string.sub(h, 5, 6), 16)
	)
end

-- The hub's palette (near-black steel, warm amber, white, the job blue).
local C = {
	steel = hex("23262B"),
	dark = hex("1A1C20"),
	white = hex("E6E6E2"),
	glass = hex("2B3038"),
	navy = hex("1E2B3A"),
	concrete = hex("A9A8A2"),
	orange = hex("F26B1D"),
	yellow = hex("F2D23C"),
	red = hex("FF3C32"),
	blue = hex("3C78FF"),
	amber = hex("E8B64C"),
	warm = hex("FFF2D0"),
	tire = hex("141414"),
}

type PartSpec = { [string]: any }

local function part(
	model: any,
	name: string,
	size: { number },
	at: { number },
	color: any,
	material: any?,
	extra: PartSpec?
): any
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = Vector3.new(size[1], size[2], size[3])
	p.CFrame = CFrame.new(at[1], at[2], at[3])
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if extra then
		for k, v in extra do
			(p :: any)[k] = v
		end
	end
	p.Parent = model
	return p
end

local function wheel(model: any, x: number, y: number, z: number, d: number)
	local w = part(model, "Wheel", { 1.1, d, d }, { x, y, z }, C.tire, Enum.Material.SmoothPlastic)
	w.Shape = Enum.PartType.Cylinder
	return w
end

local function root(model: any): any
	return part(model, "Root", { 1, 0.2, 1 }, { 0, 0.1, 0 }, C.dark, nil, { Transparency = 1 })
end

-- A light bar: two flashing halves (LightRed / LightBlue, or LightWhite) the clients strobe.
local function lightBar(model: any, y: number, z: number, width: number, a: string, b: string)
	part(model, "LightBase", { width + 0.4, 0.35, 1 }, { 0, y, z }, C.steel)
	local colors = { LightRed = C.red, LightBlue = C.blue, LightWhite = C.warm }
	for i, name in { a, b } do
		local x = (i == 1 and -1 or 1) * width / 4
		local l = part(
			model,
			name,
			{ width / 2 - 0.1, 0.45, 0.9 },
			{ x, y + 0.38, z },
			colors[name],
			Enum.Material.Neon
		)
		local light = Instance.new("PointLight")
		light.Color = colors[name]
		light.Range = 18
		light.Brightness = 2
		light.Parent = l
	end
end

local function sideText(p: any, text: string, color: any)
	for _, face in { Enum.NormalId.Left, Enum.NormalId.Right } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 30
		gui.LightInfluence = 1
		gui.Parent = p
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = roblox.UDim2.fromScale(1, 1)
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.Text = text
		label.TextColor3 = color
		label.Parent = gui
	end
end

------------------------------------------------------------------ The templates
local builders: { [string]: (any) -> () } = {}

builders.Cruiser = function(m)
	part(m, "Body", { 6.4, 2.2, 14 }, { 0, 1.9, 0 }, C.white)
	part(m, "DoorBand", { 6.5, 1.0, 6.4 }, { 0, 1.9, 0.4 }, C.dark)
	part(m, "Cabin", { 5.6, 1.8, 6.5 }, { 0, 3.9, 0.6 }, C.glass, Enum.Material.Glass, { Transparency = 0.15 })
	part(m, "Roof", { 5.6, 0.25, 6.0 }, { 0, 4.9, 0.6 }, C.white)
	lightBar(m, 5.2, 0.4, 4.2, "LightRed", "LightBlue")
	for _, sx in { -1, 1 } do
		part(m, "Headlight", { 1.2, 0.6, 0.2 }, { sx * 2.2, 2.2, -7.05 }, C.warm, Enum.Material.Neon)
		part(m, "Taillight", { 1.2, 0.5, 0.2 }, { sx * 2.2, 2.3, 7.05 }, C.red, Enum.Material.Neon)
		for _, sz in { -1, 1 } do
			wheel(m, sx * 3.05, 1.1, sz * 4.4, 2.2)
		end
	end
	part(m, "PushBar", { 4.4, 1.2, 0.4 }, { 0, 1.4, -7.3 }, C.dark, Enum.Material.Metal)
end

builders.SwatVan = function(m)
	local body = part(m, "Body", { 7.5, 7, 17 }, { 0, 4.4, 0.6 }, C.navy)
	sideText(body, "SWAT", C.white)
	part(m, "Cab", { 7.3, 4.6, 4 }, { 0, 3.2, -9.6 }, C.navy)
	part(m, "Windshield", { 6.6, 2.0, 0.2 }, { 0, 4.4, -11.65 }, C.glass, Enum.Material.Glass, { Transparency = 0.15 })
	part(m, "Bumper", { 7.6, 1.0, 0.6 }, { 0, 1.4, -11.8 }, C.dark, Enum.Material.Metal)
	lightBar(m, 8.1, -6.5, 5, "LightRed", "LightBlue")
	for _, sx in { -1, 1 } do
		part(m, "Headlight", { 1.4, 0.7, 0.2 }, { sx * 2.6, 2.4, -11.7 }, C.warm, Enum.Material.Neon)
		wheel(m, sx * 3.5, 1.3, -8.4, 2.6)
		wheel(m, sx * 3.5, 1.3, 5.6, 2.6)
	end
end

builders.Ambulance = function(m)
	local body = part(m, "Body", { 7, 6.5, 12 }, { 0, 4.3, 2 }, C.white)
	part(m, "Stripe", { 7.1, 0.8, 12.1 }, { 0, 3.3, 2 }, C.red)
	sideText(body, "AMBULANCE", C.red)
	part(m, "Cab", { 6.8, 4.4, 4.5 }, { 0, 3.1, -6.3 }, C.white)
	part(m, "Windshield", { 6.2, 1.8, 0.2 }, { 0, 4.3, -8.6 }, C.glass, Enum.Material.Glass, { Transparency = 0.15 })
	lightBar(m, 7.8, -2.5, 4.6, "LightRed", "LightWhite")
	for _, sx in { -1, 1 } do
		part(m, "Headlight", { 1.3, 0.6, 0.2 }, { sx * 2.4, 2.3, -8.6 }, C.warm, Enum.Material.Neon)
		wheel(m, sx * 3.3, 1.2, -5.6, 2.4)
		wheel(m, sx * 3.3, 1.2, 5.2, 2.4)
	end
end

builders.Barricade = function(m)
	part(m, "Base", { 8, 1.6, 2.6 }, { 0, 0.8, 0 }, C.concrete, Enum.Material.Concrete)
	part(m, "Top", { 8, 1.6, 1.2 }, { 0, 2.4, 0 }, C.concrete, Enum.Material.Concrete)
	part(m, "Band", { 8.05, 0.35, 1.25 }, { 0, 2.9, 0 }, C.orange)
end

builders.Tape = function(m)
	for _, sx in { -1, 1 } do
		part(m, "Post", { 0.3, 3.6, 0.3 }, { sx * 17, 1.8, 0 }, C.steel, Enum.Material.Metal)
	end
	part(m, "Tape", { 34, 0.5, 0.06 }, { 0, 3.0, 0 }, C.yellow)
	part(m, "TapeLow", { 34, 0.5, 0.06 }, { 0, 1.8, 0 }, C.yellow)
end

builders.Cone = function(m)
	part(m, "Base", { 1.6, 0.2, 1.6 }, { 0, 0.1, 0 }, C.orange)
	part(m, "Low", { 1.0, 0.8, 1.0 }, { 0, 0.6, 0 }, C.orange)
	part(m, "Band", { 0.78, 0.4, 0.78 }, { 0, 1.2, 0 }, C.white)
	part(m, "High", { 0.6, 0.7, 0.6 }, { 0, 1.75, 0 }, C.orange)
	part(m, "Tip", { 0.35, 0.4, 0.35 }, { 0, 2.3, 0 }, C.orange)
end

builders.Sawhorse = function(m)
	for i = 0, 5 do
		part(m, "Stripe", { 1, 0.8, 0.32 }, { -2.5 + i, 2.6, 0 }, if i % 2 == 0 then C.orange else C.white)
	end
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local leg = part(m, "Leg", { 0.3, 2.8, 0.3 }, { sx * 2.6, 1.3, sz * 0.5 }, C.white)
			leg.CFrame = CFrame.new(sx * 2.6, 1.3, sz * 0.45) * CFrame.Angles(math.rad(sz * 12), 0, 0)
		end
	end
end

builders.Searchlight = function(m)
	part(m, "Base", { 2.2, 1, 2.2 }, { 0, 0.5, 0 }, C.steel, Enum.Material.Metal)
	part(m, "Post", { 0.5, 2, 0.5 }, { 0, 2, 0 }, C.steel, Enum.Material.Metal)
	part(m, "Head", { 1.8, 1.8, 2.4 }, { 0, 3.6, 0 }, C.dark, Enum.Material.Metal)
	local lens = part(m, "Lens", { 1.5, 1.5, 0.12 }, { 0, 3.6, -1.26 }, C.warm, Enum.Material.Neon)
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Front
	spot.Range = 60
	spot.Angle = 22
	spot.Brightness = 5
	spot.Color = C.warm
	spot.Parent = lens
	-- A faint shaft of light ahead of the lens (the clients sweep Head, Lens and Shaft together).
	part(
		m,
		"Shaft",
		{ 5, 5, 70 },
		{ 0, 3.6, -36.3 },
		C.warm,
		Enum.Material.Neon,
		{ Transparency = 0.94, CastShadow = false }
	)
end

builders.Helicopter = function(m)
	part(m, "Body", { 6, 5, 12 }, { 0, 2.6, 0 }, C.steel)
	part(m, "Cockpit", { 5.4, 3.4, 3.6 }, { 0, 2.9, -7.6 }, C.glass, Enum.Material.Glass, { Transparency = 0.2 })
	part(m, "Boom", { 1.4, 1.4, 13 }, { 0, 3.6, 12.4 }, C.steel)
	part(m, "Fin", { 0.3, 3.2, 2.6 }, { 0, 5.4, 18.4 }, C.steel)
	part(m, "Hub", { 1.1, 1.1, 1.1 }, { 0, 5.6, 0 }, C.dark, Enum.Material.Metal)
	part(m, "Rotor", { 34, 0.15, 1.2 }, { 0, 6.1, 0 }, C.dark, Enum.Material.Metal)
	part(m, "Rotor", { 1.2, 0.15, 34 }, { 0, 6.1, 0 }, C.dark, Enum.Material.Metal)
	part(m, "TailRotor", { 0.15, 4.2, 0.6 }, { 0.95, 4.0, 18.6 }, C.dark, Enum.Material.Metal)
	for _, sx in { -1, 1 } do
		part(m, "Skid", { 0.4, 0.4, 12 }, { sx * 2.7, -0.6, -0.8 }, C.dark, Enum.Material.Metal)
		part(m, "Strut", { 0.3, 1.0, 0.3 }, { sx * 2.7, -0.1, -4 }, C.dark, Enum.Material.Metal)
		part(m, "Strut", { 0.3, 1.0, 0.3 }, { sx * 2.7, -0.1, 2.5 }, C.dark, Enum.Material.Metal)
	end
	part(m, "NavRed", { 0.4, 0.4, 0.4 }, { -3.1, 2.6, -2 }, C.red, Enum.Material.Neon)
	-- The searchlight under the nose (the clients aim it at a crew member) and its shaft.
	local spotPart = part(m, "Spot", { 1, 1, 1 }, { 0, 0.3, -6.5 }, C.warm, Enum.Material.Neon)
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Front
	spot.Range = 140
	spot.Angle = 16
	spot.Brightness = 6
	spot.Color = C.warm
	spot.Parent = spotPart
	part(
		m,
		"SpotShaft",
		{ 6, 6, 80 },
		{ 0, -40, -6.5 },
		C.warm,
		Enum.Material.Neon,
		{ Transparency = 0.93, CastShadow = false }
	)
	-- Dust kicked up under it on boss waves (the clients move it to the ground and switch it on).
	local dust = part(m, "Dust", { 8, 0.2, 8 }, { 0, -60, 0 }, C.concrete, nil, { Transparency = 1 })
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "DustEmitter"
	pe.Enabled = false
	pe.Rate = 40
	pe.Lifetime = roblox.NumberRange.new(1.5, 2.5)
	pe.Speed = roblox.NumberRange.new(10, 18)
	pe.SpreadAngle = roblox.Vector2.new(80, 80)
	pe.Size = roblox.NumberSequence.new(3, 8)
	pe.Transparency = roblox.NumberSequence.new(0.6, 1)
	pe.Color = roblox.ColorSequence.new(hex("B8AE9C"))
	pe.Parent = dust
	local rotor = Instance.new("Sound")
	rotor.Name = "RotorSound"
	rotor.Looped = true
	rotor.RollOffMinDistance = 40
	rotor.RollOffMaxDistance = 600
	rotor.Parent = m:FindFirstChild("Body")
end

------------------------------------------------------------------ The file
local folder = Instance.new("Folder")
folder.Name = "Dressing"
local templates = Instance.new("Folder")
templates.Name = "Templates"
templates.Parent = folder
local order =
	{ "Cruiser", "SwatVan", "Ambulance", "Barricade", "Tape", "Cone", "Sawhorse", "Searchlight", "Helicopter" }
-- In edit mode the templates stand in a row behind the grass (bank coordinates z -340), facing the bank.
local x = -200
for _, name in order do
	local m = Instance.new("Model")
	m.Name = name
	root(m)
	builders[name](m)
	local place = CFrame.new(x + OX, OY + 0.5, -340 + OZ) * CFrame.Angles(0, math.pi, 0)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = place * d.CFrame
		end
	end
	m.Parent = templates
	x += if name == "Tape" or name == "Helicopter" then 50 else 30
end
fs.writeFile(OUT, roblox.serializeModel({ folder }, true))
print(string.format("[genbankdressing] %d templates -> %s", #order, OUT))
