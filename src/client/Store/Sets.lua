--!strict
-- Brief 6: the private sets the premium scenes play on, built locally on this client far from the map so nobody
-- else sees them: the SHOWROOM (dark, gold key light, a pedestal on the left for the mannequin), the CRATE ROOM
-- (one spotlight, the crate on a pedestal center frame) and the PASS STAGE. Each set is an enclosed room so the
-- sky never leaks in; while a set is up the lighting goes dark and warm (restored on close). The mannequin is a
-- local clone of the player's character standing on the set's pedestal, for previews (masks, poses, wraps,
-- class idles) without moving the real character.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Masks = require(Shared:WaitForChild("Masks"))
local MaskShapes = require(Shared:WaitForChild("MaskShapes"))
local Wraps = require(Shared:WaitForChild("Wraps"))
local Emotes = require(Shared:WaitForChild("Emotes"))
local Classes = require(Shared:WaitForChild("Classes"))

local Client = script.Parent.Parent
local RunStartUI = require(Client:WaitForChild("RunStartUI"))

local Sets = {}

export type Set = {
	name: string,
	model: Model,
	origin: CFrame, -- floor center, facing +Z toward the camera side
	pedestal: CFrame, -- where a mannequin / crate stands (on top of the pedestal)
	shot: CFrame, -- the camera's resting shot
	pullback: CFrame, -- where the camera eases in from
	lights: { Light },
}

local player = Players.LocalPlayer
local folder: Folder? = nil
local built: { [string]: Set } = {}

local GOLD = Color3.fromHex("F2C14E")

local function root(): Folder
	local f = folder
	if f and f.Parent then
		return f
	end
	local nf = Instance.new("Folder")
	nf.Name = "PremiumSets"
	nf.Parent = Workspace
	folder = nf
	return nf
end

local function part(
	parent: Instance,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- An enclosed room: floor, ceiling, four walls. `w` wide (X), `d` deep (Z), `h` tall. Returns the model.
local function room(name: string, origin: CFrame, w: number, d: number, h: number, wall: Color3, floor: Color3): Model
	local m = Instance.new("Model")
	m.Name = name
	part(m, Vector3.new(w, 1, d), origin * CFrame.new(0, -0.5, 0), floor, Enum.Material.Marble)
	part(m, Vector3.new(w, 1, d), origin * CFrame.new(0, h + 0.5, 0), wall)
	part(m, Vector3.new(w, h, 1), origin * CFrame.new(0, h / 2, -d / 2), wall)
	part(m, Vector3.new(w, h, 1), origin * CFrame.new(0, h / 2, d / 2), wall)
	part(m, Vector3.new(1, h, d), origin * CFrame.new(-w / 2, h / 2, 0), wall)
	part(m, Vector3.new(1, h, d), origin * CFrame.new(w / 2, h / 2, 0), wall)
	m.Parent = root()
	return m
end

local function light(
	parent: BasePart,
	kind: string,
	color: Color3,
	brightness: number,
	range: number,
	angle: number?
): Light
	local l: Light
	if kind == "spot" then
		local s = Instance.new("SpotLight")
		s.Angle = angle or 60
		s.Face = Enum.NormalId.Bottom
		s.Range = range
		l = s
	else
		local p = Instance.new("PointLight")
		p.Range = range
		l = p
	end
	l.Color = color
	l.Brightness = brightness
	l.Shadows = true
	l.Parent = parent
	return l
end

------------------------------------------------------------------ The sets
local function buildShowroom(): Set
	local origin = CFrame.new(3000, 600, 0)
	local m = room("Showroom", origin, 46, 34, 16, Color3.fromRGB(16, 15, 18), Color3.fromRGB(22, 20, 24))
	-- Gold strips along the back wall and the floor edge.
	for i = -1, 1 do
		part(m, Vector3.new(40, 0.15, 0.15), origin * CFrame.new(0, 4 + i * 4, -16.4), GOLD, Enum.Material.Neon)
	end
	part(m, Vector3.new(44, 0.12, 0.12), origin * CFrame.new(0, 0.06, -10), GOLD, Enum.Material.Neon)
	-- Display plinths and shelves in the back (soft shapes in the dark).
	for i = -2, 2 do
		local x = i * 8
		part(m, Vector3.new(3, 4, 3), origin * CFrame.new(x, 2, -14), Color3.fromRGB(30, 28, 34), Enum.Material.Marble)
		local glow = part(m, Vector3.new(2.6, 0.1, 2.6), origin * CFrame.new(x, 4.06, -14), GOLD, Enum.Material.Neon)
		glow.Transparency = 0.4
		part(
			m,
			Vector3.new(1.4, 1.4, 1.4),
			origin * CFrame.new(x, 4.8, -14) * CFrame.Angles(0, math.rad(30 + i * 20), 0),
			Color3.fromRGB(44, 52, 64),
			Enum.Material.Metal
		)
	end
	-- The mannequin pedestal, on the left of the frame (the store panel takes the right two thirds).
	local pedTop = origin * CFrame.new(-6.5, 0.6, 2)
	local ped = part(
		m,
		Vector3.new(1.2, 6, 6),
		pedTop * CFrame.new(0, -0.3, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(28, 26, 30),
		Enum.Material.Marble,
		Enum.PartType.Cylinder
	)
	local rim = part(
		m,
		Vector3.new(0.2, 6.3, 6.3),
		pedTop * CFrame.Angles(0, 0, math.rad(90)),
		GOLD,
		Enum.Material.Neon,
		Enum.PartType.Cylinder
	)
	rim.Transparency = 0.2
	local _ = ped
	-- Lights: a gold key from above-left, a cool rim from behind, a warm fill on the pedestal.
	local key = part(
		m,
		Vector3.new(1, 1, 1),
		origin * CFrame.new(-12, 14, 8) * CFrame.Angles(math.rad(-50), math.rad(-30), 0),
		GOLD,
		Enum.Material.Neon
	)
	key.Transparency = 1
	local lights = {
		light(key, "spot", GOLD, 6, 40, 70),
		light(
			part(m, Vector3.new(1, 1, 1), origin * CFrame.new(-6.5, 9, -6), GOLD, Enum.Material.Neon),
			"point",
			Color3.fromHex("6FA8FF"),
			1.4,
			16
		),
		light(
			part(m, Vector3.new(1, 1, 1), pedTop * CFrame.new(0, 3, 6), GOLD, Enum.Material.Neon),
			"point",
			Color3.fromHex("FFD9A0"),
			1.6,
			14
		),
	}
	for _, l in lights do
		local p = l.Parent :: BasePart
		p.Transparency = 1
	end
	local look = pedTop * CFrame.new(0, 2.6, 0)
	-- The camera stands in front and to the right so the pedestal reads in the left third of the frame.
	local shotPos = (origin * CFrame.new(-1.3, 3.6, 9)).Position
	local shot = CFrame.lookAt(shotPos, (origin * CFrame.new(-1.3, 2.9, 0)).Position)
	local _ = look
	return {
		name = "Showroom",
		model = m,
		origin = origin,
		pedestal = pedTop,
		shot = shot,
		pullback = shot * CFrame.new(0, 0.8, 5),
		lights = lights,
	}
end

local function buildCrateRoom(): Set
	local origin = CFrame.new(3200, 600, 0)
	local m = room("CrateRoom", origin, 40, 40, 18, Color3.fromRGB(10, 10, 12), Color3.fromRGB(16, 16, 19))
	local pedTop = origin * CFrame.new(0, 1.2, 0)
	part(
		m,
		Vector3.new(2.4, 7, 7),
		pedTop * CFrame.new(0, -0.6, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(26, 26, 30),
		Enum.Material.Marble,
		Enum.PartType.Cylinder
	)
	local rim = part(
		m,
		Vector3.new(0.2, 7.3, 7.3),
		pedTop * CFrame.Angles(0, 0, math.rad(90)),
		GOLD,
		Enum.Material.Neon,
		Enum.PartType.Cylinder
	)
	rim.Name = "Rim"
	rim.Transparency = 0.3
	local spot = part(m, Vector3.new(1, 1, 1), origin * CFrame.new(0, 16, 1), GOLD, Enum.Material.Neon)
	spot.Transparency = 1
	local lights = {
		light(spot, "spot", Color3.fromHex("FFF1D6"), 8, 30, 40),
		light(
			part(m, Vector3.new(1, 1, 1), origin * CFrame.new(0, 4, 8), GOLD, Enum.Material.Neon),
			"point",
			Color3.fromHex("FFD9A0"),
			0.8,
			16
		),
	}
	for _, l in lights do
		(l.Parent :: BasePart).Transparency = 1
	end
	local shot = CFrame.lookAt((origin * CFrame.new(0, 4.2, 9)).Position, (origin * CFrame.new(0, 2.8, 0)).Position)
	return {
		name = "CrateRoom",
		model = m,
		origin = origin,
		pedestal = pedTop,
		shot = shot,
		pullback = shot * CFrame.new(0, 1, 6),
		lights = lights,
	}
end

local function buildPassStage(): Set
	local origin = CFrame.new(3400, 600, 0)
	local orange = Color3.fromHex("E8792A")
	local m = room("PassStage", origin, 46, 34, 16, Color3.fromRGB(14, 13, 16), Color3.fromRGB(20, 18, 22))
	for i = 0, 6 do
		local stripe = part(
			m,
			Vector3.new(0.3, 12, 0.2),
			origin * CFrame.new(-18 + i * 6, 6, -16.4) * CFrame.Angles(0, 0, math.rad(20)),
			orange,
			Enum.Material.Neon
		)
		stripe.Transparency = 0.35
	end
	local pedTop = origin * CFrame.new(0, 0.8, 0)
	part(
		m,
		Vector3.new(1.6, 6.5, 6.5),
		pedTop * CFrame.new(0, -0.4, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(28, 26, 30),
		Enum.Material.Marble,
		Enum.PartType.Cylinder
	)
	local rim = part(
		m,
		Vector3.new(0.2, 6.8, 6.8),
		pedTop * CFrame.Angles(0, 0, math.rad(90)),
		orange,
		Enum.Material.Neon,
		Enum.PartType.Cylinder
	)
	rim.Transparency = 0.2
	local key = part(m, Vector3.new(1, 1, 1), origin * CFrame.new(-6, 14, 9), orange, Enum.Material.Neon)
	local fill = part(m, Vector3.new(1, 1, 1), origin * CFrame.new(5, 6, 6), orange, Enum.Material.Neon)
	local lights = {
		light(key, "spot", Color3.fromHex("FFC890"), 6, 40, 60),
		light(fill, "point", Color3.fromHex("7FB8FF"), 1.2, 16),
	}
	key.Transparency = 1
	fill.Transparency = 1
	-- The hero sits center-frame, a little high (the track takes the bottom of the screen).
	local shot = CFrame.lookAt((origin * CFrame.new(0, 2.2, 10)).Position, (origin * CFrame.new(0, 1.0, 0)).Position)
	return {
		name = "PassStage",
		model = m,
		origin = origin,
		pedestal = pedTop,
		shot = shot,
		pullback = shot * CFrame.new(0, 1, 6),
		lights = lights,
	}
end

function Sets.get(name: string): Set
	local s = built[name]
	if s and s.model.Parent then
		return s
	end
	local made = if name == "CrateRoom"
		then buildCrateRoom()
		elseif name == "PassStage" then buildPassStage()
		else buildShowroom()
	built[name] = made
	return made
end

------------------------------------------------------------------ Lighting
local saved: { [string]: any }? = nil
local cc: ColorCorrectionEffect? = nil
local holders = 0

-- Dark, warm, contrasty while any set is up. Reference counted so nested scenes restore once.
function Sets.dimWorld(on: boolean)
	if on then
		holders += 1
		if holders > 1 then
			return
		end
		saved = {
			Ambient = Lighting.Ambient,
			OutdoorAmbient = Lighting.OutdoorAmbient,
			Brightness = Lighting.Brightness,
			ExposureCompensation = Lighting.ExposureCompensation,
			EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale,
			EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale,
		}
		Lighting.Ambient = Color3.fromRGB(18, 16, 20)
		Lighting.OutdoorAmbient = Color3.fromRGB(18, 16, 20)
		Lighting.Brightness = 0.4
		Lighting.ExposureCompensation = 0.3
		Lighting.EnvironmentDiffuseScale = 0.2
		Lighting.EnvironmentSpecularScale = 0.6
		local e = Instance.new("ColorCorrectionEffect")
		e.Name = "PremiumGrade"
		e.Contrast = 0.12
		e.Saturation = 0.08
		e.TintColor = Color3.fromRGB(255, 244, 228)
		e.Parent = Lighting
		cc = e
	else
		holders = math.max(0, holders - 1)
		if holders > 0 then
			return
		end
		local s = saved
		if s then
			for k, v in s do
				(Lighting :: any)[k] = v
			end
		end
		saved = nil
		if cc then
			cc:Destroy()
			cc = nil
		end
	end
end

------------------------------------------------------------------ The mannequin
export type Mannequin = {
	model: Model,
	mask: (string?) -> (), -- preview a mask id (nil = the worn one)
	pose: (string) -> (), -- play an emote id once
	idle: (string?) -> (), -- loop a class idle
	wrap: (string?) -> (), -- preview a wrap id on the held gun's grip (nil = the equipped one)
	turn: (number) -> (), -- yaw offset (drag to turn)
	destroy: () -> (),
}

-- A local clone of the character on `at` (the pedestal top), facing the camera. nil while there is no character.
function Sets.mannequin(at: CFrame, facing: Vector3): Mannequin?
	local char = player.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then
		return nil
	end
	char.Archivable = true
	local ok, clone = pcall(function()
		return char:Clone()
	end)
	char.Archivable = false
	if not ok or not clone then
		return nil
	end
	local model = clone :: Model
	model.Name = "Mannequin"
	for _, d in model:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("BillboardGui") or d:IsA("ForceField") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.LocalTransparencyModifier = 0
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.PlatformStand = false
	end
	local hrp = model:FindFirstChild("HumanoidRootPart") :: BasePart
	hrp.Anchored = true
	local height = if hum then hum.HipHeight + hrp.Size.Y / 2 else 3
	local base =
		CFrame.lookAt(at.Position + Vector3.new(0, height, 0), at.Position + Vector3.new(facing.X, height, facing.Z))
	model:PivotTo(base)
	model.Parent = root()
	local yaw = 0
	local idleTrack: AnimationTrack? = nil
	local previewMask: BasePart? = nil
	local head = model:FindFirstChild("Head") :: BasePart?
	local wornHead = if head then head.Color else Color3.new(1, 1, 1)
	local grip = model:FindFirstChild("HeldGunWrap") :: BasePart?
	local wornGrip = if grip then grip.Color else nil
	local wornGripMat = if grip then grip.Material else nil
	local m: Mannequin
	m = {
		model = model,
		mask = function(id: string?)
			if previewMask then
				previewMask:Destroy()
				previewMask = nil
			end
			local worn = model:FindFirstChild("MaskPart")
			local def = id and Masks.ById[id]
			for _, p in MaskShapes.parts(worn) do
				p.LocalTransparencyModifier = if def then 1 else 0
			end
			if not head then
				return
			end
			if not def then
				head.Color = wornHead
				return
			end
			head.Color = Color3.fromHex(def.color)
			previewMask = MaskShapes.build(head, def, "PreviewMask", model)
			-- Epic+ masks sparkle on the stand too.
			if previewMask and def.rarity >= 4 then
				local sparkle = Instance.new("ParticleEmitter")
				sparkle.Color = ColorSequence.new(Color3.fromHex(def.accent or def.color))
				sparkle.LightEmission = 1
				sparkle.Size = NumberSequence.new(0.12, 0)
				sparkle.Lifetime = NumberRange.new(0.6, 1.1)
				sparkle.Rate = 12
				sparkle.Speed = NumberRange.new(0.6, 1.4)
				sparkle.SpreadAngle = Vector2.new(180, 180)
				sparkle.Parent = previewMask
			end
		end,
		pose = function(emoteId: string)
			local e = Emotes.ById[emoteId]
			if e then
				RunStartUI.playAnim(model, e.animationId, e.holdSec + 0.6)
			end
		end,
		idle = function(classId: string?)
			if idleTrack then
				idleTrack:Stop(0.2)
				idleTrack = nil
			end
			local id = Config.ClassIdleAnimationId[classId or Classes.Default]
				or Config.ClassIdleAnimationId[Classes.Default]
			if id then
				idleTrack = RunStartUI.playAnim(model, id, nil)
				if idleTrack then
					idleTrack.Looped = true
					idleTrack.Priority = Enum.AnimationPriority.Idle
				end
			end
		end,
		wrap = function(id: string?)
			if not grip then
				return
			end
			local w = id and Wraps.ById[id]
			if w then
				grip.Color = Color3.fromHex(w.color)
				grip.Material = Wraps.material(w)
			elseif wornGrip then
				grip.Color = wornGrip
				grip.Material = wornGripMat or Enum.Material.Metal
			end
		end,
		turn = function(delta: number)
			yaw += delta
			model:PivotTo(base * CFrame.Angles(0, yaw, 0))
		end,
		destroy = function()
			if idleTrack then
				idleTrack:Stop(0)
			end
			model:Destroy()
		end,
	}
	return m
end

return Sets
