--!strict
-- UI art pass: live 3D icons. A ViewportFrame showing the real model (the procedural gun from GunModels, a mask on
-- its bust, a gun wearing a wrap), framed automatically: the model's bounding box is fitted to the frame's aspect
-- with Config.ModelIconPad left round it, seen from a flattering angle (guns side-on with the muzzle left, a little
-- from above and swung toward the muzzle; busts near front-on). The background is transparent, so the icon sits in
-- any existing tile or well.
--
-- Cheap by design: each model is built once per id (a template cache, joints stripped) and cloned per icon, and a
-- static icon has no per-frame work. Only a "hover" icon while the pointer is over it, or an "always" icon while it
-- is visible, runs a RenderStepped sway (and the hover one stops once it has eased back). Tint / dim / locked go
-- through ImageColor3 / ImageTransparency. Destroying the icon (or any ancestor) drops its model, camera and
-- connections.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GunModels = require(Shared:WaitForChild("GunModels"))
local Weapons = require(Shared:WaitForChild("Weapons"))
local Wraps = require(Shared:WaitForChild("Wraps"))

local Client = script.Parent.Parent
local Models = require(Client:WaitForChild("Store"):WaitForChild("Models"))

local ModelIcon = {}

export type Opts = {
	angle: string?, -- "gun" (guns, wraps) | "bust" (masks) | "front"; default from the constructor
	yaw: number?, -- degrees, overrides the angle's
	pitch: number?, -- degrees, overrides the angle's
	pad: number?, -- share of the frame left empty on each side (default Config.ModelIconPad)
	motion: string?, -- nil = static | "hover" = sways while the pointer is over hoverTarget | "always" = sways while visible
	hoverTarget: GuiObject?, -- default: the icon's parent when it is a GuiObject, else the icon
	zIndex: number?,
	state: string?, -- "normal" | "dim" | "locked" | "shadow" (see ModelIcon.setState)
	-- Guns and wraps:
	rarity: number?, -- the Rarity accent strips (default: the gun's Armory rarity; a wrap's own rarity)
	wrapId: string?,
	wrapColor: string?, -- a wrap by its hex (the held-gun sync carries the colour, not the id)
	archetype: string?, -- showcase guns (not in Weapons.ById)
	weaponId: string?, -- wrap icons: the gun wearing it (default Config.ModelIconWrapGun)
}

type Icon = {
	vp: ViewportFrame,
	cam: Camera,
	opts: Opts,
	model: Model?,
	key: string?,
	center: Vector3,
	corners: { Vector3 }, -- the bounding box corners relative to its centre (world axes)
	yaw: number, -- radians
	pitch: number,
	pad: number,
	dist: number, -- solved camera distance
	aspect: number,
	sway: number, -- extra yaw (radians) from the motion
	t: number, -- motion clock
	hovered: boolean,
	step: RBXScriptConnection?,
	conns: { RBXScriptConnection },
}

local icons: { [ViewportFrame]: Icon } = {}

------------------------------------------------------------------ Model templates
local templates: { [string]: Model } = {}

-- Joints, attachments and lights mean nothing in a ViewportFrame: drop them so every clone is lighter.
local function strip(m: Model): Model
	for _, d in m:GetDescendants() do
		if
			d:IsA("JointInstance")
			or d:IsA("WeldConstraint")
			or d:IsA("Attachment")
			or d:IsA("Light")
			or d:IsA("ParticleEmitter")
		then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CastShadow = false
		end
	end
	return m
end

local function cached(key: string, build: () -> Model): Model
	local t = templates[key]
	if not t then
		t = strip(build())
		templates[key] = t
	end
	return (t :: Model):Clone()
end

local function wrapIdOf(o: Opts): string?
	if o.wrapId then
		return o.wrapId
	end
	local hex = o.wrapColor
	if hex then
		local want = string.upper(hex)
		for _, w in Wraps.List do
			if string.upper(w.color) == want then
				return w.id
			end
		end
	end
	return nil
end

local function gunRarity(weaponId: string, o: Opts): number
	if o.rarity then
		return o.rarity
	end
	local w = Weapons.ById[weaponId]
	if w then
		return w.rarity
	end
	for _, s in Weapons.Showcase do
		if s.id == weaponId then
			return s.rarity
		end
	end
	return 1
end

local function archetypeOf(weaponId: string, o: Opts): string?
	if o.archetype then
		return o.archetype
	end
	if Weapons.ById[weaponId] then
		return nil
	end
	for _, s in Weapons.Showcase do
		if s.id == weaponId then
			return s.archetype
		end
	end
	return nil
end

-- A clone of the gun's template, recoloured for this icon's rarity and wrap.
local function gunModel(weaponId: string, rarity: number, wrapId: string?, archetype: string?): Model
	local m = cached("gun|" .. weaponId .. "|" .. (archetype or ""), function()
		return GunModels.model(weaponId, { archetype = archetype })
	end)
	local root = m.PrimaryPart
	if root then
		GunModels.setRarity(root, rarity)
		if wrapId then
			GunModels.applyWrap(root, wrapId)
		end
	end
	return m
end

local function bustModel(maskId: string): Model
	return cached("mask|" .. maskId, function()
		return Models.maskBust(maskId)
	end)
end

------------------------------------------------------------------ Framing
local function rotAt(ic: Icon, sway: number): CFrame
	return CFrame.Angles(0, ic.yaw + sway, 0) * CFrame.Angles(-ic.pitch, 0, 0)
end

-- Camera distance so every box corner fits inside the padded frame (both FOV axes), looking at the box centre.
-- Corners in camera space: x right, y up, z toward the camera; a corner's depth is d - z.
local function fitDistance(ic: Icon, rot: CFrame): number
	local k = math.max(0.1, 1 - 2 * ic.pad)
	local tanV = math.tan(math.rad(Config.ModelIconFov) / 2) * k
	local tanH = tanV * ic.aspect
	local d = 0.5
	for _, c in ic.corners do
		local p = rot:VectorToObjectSpace(c)
		d = math.max(d, p.Z + math.abs(p.X) / tanH, p.Z + math.abs(p.Y) / tanV)
	end
	return d
end

-- The fit is solved once per model / aspect (for a moving icon, over its whole swing, so it never zooms as it turns).
local function solve(ic: Icon)
	if not ic.model then
		return
	end
	local d = fitDistance(ic, rotAt(ic, 0))
	if ic.opts.motion == "hover" or ic.opts.motion == "always" then
		local amp = math.rad(Config.ModelIconSwayDeg)
		for _, f in { -1, -0.5, 0.5, 1 } do
			d = math.max(d, fitDistance(ic, rotAt(ic, f * amp)))
		end
	end
	ic.dist = d
end

local function frame(ic: Icon)
	if not ic.model then
		return
	end
	ic.cam.CFrame = CFrame.new(ic.center) * rotAt(ic, ic.sway) * CFrame.new(0, 0, ic.dist)
end

local function aspectOf(ic: Icon): number
	local a = ic.vp.AbsoluteSize
	if a.X > 0 and a.Y > 0 then
		return a.X / a.Y
	end
	local s = ic.vp.Size
	if s.X.Scale == 0 and s.Y.Scale == 0 and s.X.Offset > 0 and s.Y.Offset > 0 then
		return s.X.Offset / s.Y.Offset
	end
	return 1
end

local function refit(ic: Icon)
	local a = aspectOf(ic)
	if math.abs(a - ic.aspect) > 0.005 then
		ic.aspect = a
		solve(ic)
		frame(ic)
	end
end

local function anglesFor(o: Opts, angle: string): (number, number)
	local yaw, pitch
	if angle == "bust" then
		yaw, pitch = 180 + Config.ModelIconBustYaw, Config.ModelIconBustPitch
	elseif angle == "front" then
		yaw, pitch = 180, 0
	else
		yaw, pitch = Config.ModelIconGunYaw, Config.ModelIconGunPitch
	end
	return math.rad(o.yaw or yaw), math.rad(o.pitch or pitch)
end

local function setModel(ic: Icon, model: Model?, angle: string)
	local old = ic.model
	if old then
		old:Destroy()
	end
	ic.model = model
	if not model then
		return
	end
	ic.yaw, ic.pitch = anglesFor(ic.opts, ic.opts.angle or angle)
	local cf, size = model:GetBoundingBox()
	ic.center = cf.Position
	local corners = {}
	local h = size / 2
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				table.insert(corners, cf:VectorToWorldSpace(Vector3.new(sx * h.X, sy * h.Y, sz * h.Z)))
			end
		end
	end
	ic.corners = corners
	-- The key light rides with the base view: from the upper left, slightly in front (camera space).
	local base = CFrame.Angles(0, ic.yaw, 0) * CFrame.Angles(-ic.pitch, 0, 0)
	ic.vp.LightDirection = base:VectorToWorldSpace(Vector3.new(0.5, -1, -0.6)).Unit
	model.Parent = ic.vp
	ic.aspect = aspectOf(ic)
	solve(ic)
	frame(ic)
end

------------------------------------------------------------------ Motion
local function stopStep(ic: Icon)
	local s = ic.step
	if s then
		s:Disconnect()
		ic.step = nil
	end
end

local function startStep(ic: Icon)
	if ic.step then
		return
	end
	local amp = math.rad(Config.ModelIconSwayDeg)
	local period = math.max(0.2, Config.ModelIconSwaySec)
	-- Pick the swing up from wherever an ease-back left it, so re-hovering never snaps.
	ic.t = math.asin(math.clamp(if amp > 0 then ic.sway / amp else 0, -1, 1)) / (2 * math.pi) * period
	ic.step = RunService.RenderStepped:Connect(function(dt: number)
		if ic.opts.motion == "always" and not ic.vp.Visible then
			return
		end
		if ic.opts.motion == "always" or ic.hovered then
			ic.t += dt
			ic.sway = math.sin(ic.t / period * 2 * math.pi) * amp
		else
			ic.sway += (0 - ic.sway) * math.min(1, dt * 8)
			if math.abs(ic.sway) < 0.002 then
				ic.sway = 0
				stopStep(ic)
			end
		end
		frame(ic)
	end)
end

local function cleanup(vp: ViewportFrame)
	local ic = icons[vp]
	if not ic then
		return
	end
	icons[vp] = nil
	stopStep(ic)
	for _, c in ic.conns do
		c:Disconnect()
	end
	table.clear(ic.conns)
	ic.model = nil
end

------------------------------------------------------------------ Public API
-- Tint / dim / lock without touching the model: "normal", "dim" (unowned / not yet), "locked" (drawn dark),
-- "shadow" (a black silhouette).
function ModelIcon.setState(vp: ViewportFrame, state: string?)
	if state == "dim" then
		vp.ImageColor3 = Color3.new(1, 1, 1)
		vp.ImageTransparency = Config.ModelIconDimTransparency
	elseif state == "locked" then
		vp.ImageColor3 = Color3.fromHex(Config.ModelIconLockedShade)
		vp.ImageTransparency = 0.15
	elseif state == "shadow" then
		vp.ImageColor3 = Color3.new(0, 0, 0)
		vp.ImageTransparency = 0.2
	else
		vp.ImageColor3 = Color3.new(1, 1, 1)
		vp.ImageTransparency = 0
	end
end

-- A multiply tint (and optional transparency) over the rendered model.
function ModelIcon.tint(vp: ViewportFrame, color: Color3, transparency: number?)
	vp.ImageColor3 = color
	if transparency then
		vp.ImageTransparency = transparency
	end
end

local function create(parent: Instance?, model: Model?, size: number | UDim2, o: Opts, angle: string): ViewportFrame
	local vp = Instance.new("ViewportFrame")
	vp.Name = "ModelIcon"
	vp.BackgroundTransparency = 1
	vp.BorderSizePixel = 0
	vp.Size = if typeof(size) == "number" then UDim2.fromOffset(size, size) else size
	vp.Ambient = Color3.fromHex(Config.ModelIconAmbient)
	vp.LightColor = Color3.fromHex(Config.ModelIconLight)
	if o.zIndex then
		vp.ZIndex = o.zIndex
	end
	local cam = Instance.new("Camera")
	cam.FieldOfView = Config.ModelIconFov
	cam.Parent = vp
	vp.CurrentCamera = cam
	local ic: Icon = {
		vp = vp,
		cam = cam,
		opts = o,
		model = nil,
		key = nil,
		center = Vector3.zero,
		corners = {},
		yaw = 0,
		pitch = 0,
		pad = o.pad or Config.ModelIconPad,
		dist = 10,
		aspect = 1,
		sway = 0,
		t = 0,
		hovered = false,
		step = nil,
		conns = {},
	}
	icons[vp] = ic
	setModel(ic, model, angle)
	ModelIcon.setState(vp, o.state)
	table.insert(
		ic.conns,
		vp:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			refit(ic)
		end)
	)
	vp.Destroying:Connect(function()
		cleanup(vp)
	end)
	if parent then
		vp.Parent = parent
	end
	if o.motion == "hover" then
		local target: GuiObject = o.hoverTarget or (if parent and parent:IsA("GuiObject") then parent else vp)
		table.insert(
			ic.conns,
			target.MouseEnter:Connect(function()
				ic.hovered = true
				startStep(ic)
			end)
		)
		table.insert(
			ic.conns,
			target.MouseLeave:Connect(function()
				ic.hovered = false
			end)
		)
	elseif o.motion == "always" then
		startStep(ic)
	end
	return vp
end

-- An icon showing `model` (taken over: it is parented into the icon and destroyed with it). `size` is a square px
-- size or a UDim2. Returns the ViewportFrame (AnchorPoint / Position are the caller's, like any icon).
function ModelIcon.new(parent: Instance?, model: Model?, size: number | UDim2, opts: Opts?): ViewportFrame
	return create(parent, model, size, opts or {}, "gun")
end

-- Swap the model an icon shows (the old one is destroyed); the framing and light follow.
function ModelIcon.setModel(vp: ViewportFrame, model: Model?, angle: string?)
	local ic = icons[vp]
	if not ic then
		if model then
			model:Destroy()
		end
		return
	end
	ic.key = nil
	setModel(ic, model, angle or "gun")
end

local function gunKey(weaponId: string, o: Opts): (string, number, string?, string?)
	local rarity = gunRarity(weaponId, o)
	local wrapId = wrapIdOf(o)
	local archetype = archetypeOf(weaponId, o)
	return table.concat({ "gun", weaponId, tostring(rarity), wrapId or "", archetype or "" }, "|"),
		rarity,
		wrapId,
		archetype
end

-- A gun by weapon id (showcase ids too). opts.rarity / wrapId / wrapColor / archetype.
function ModelIcon.weapon(parent: Instance?, weaponId: string, size: number | UDim2, opts: Opts?): ViewportFrame
	local o: Opts = opts or {}
	local key, rarity, wrapId, archetype = gunKey(weaponId, o)
	local vp = ModelIcon.new(parent, gunModel(weaponId, rarity, wrapId, archetype), size, o)
	icons[vp].key = key
	return vp
end

-- Point an existing icon at another gun (the held-gun slot). A no-op when nothing changed, so it is safe per sync.
function ModelIcon.setWeapon(vp: ViewportFrame, weaponId: string, opts: Opts?)
	local ic = icons[vp]
	if not ic then
		return
	end
	local o: Opts = opts or {}
	local key, rarity, wrapId, archetype = gunKey(weaponId, o)
	if ic.key == key then
		return
	end
	setModel(ic, gunModel(weaponId, rarity, wrapId, archetype), "gun")
	ic.key = key
end

-- A mask on its bust.
function ModelIcon.mask(parent: Instance?, maskId: string, size: number | UDim2, opts: Opts?): ViewportFrame
	local o: Opts = opts or {}
	local vp = create(parent, bustModel(maskId), size, o, "bust")
	icons[vp].key = "mask|" .. maskId
	return vp
end

-- A wrap, shown on a gun wearing it (opts.weaponId, default Config.ModelIconWrapGun); the accent strips take the
-- wrap's rarity.
function ModelIcon.wrap(parent: Instance?, wrapId: string, size: number | UDim2, opts: Opts?): ViewportFrame
	local o: Opts = opts or {}
	local w = Wraps.ById[wrapId]
	local gun = o.weaponId or Config.ModelIconWrapGun
	local rarity = o.rarity or (if w then w.rarity else 1)
	local vp = ModelIcon.new(parent, gunModel(gun, rarity, wrapId, nil), size, o)
	icons[vp].key = table.concat({ "wrap", wrapId, gun, tostring(rarity) }, "|")
	return vp
end

-- True when `r` (a Rewards.Reward) has a model icon: weapons, masks and wraps.
function ModelIcon.canShow(r: { kind: string, id: string? }): boolean
	return r.id ~= nil and r.id ~= "" and (r.kind == "weapon" or r.kind == "mask" or r.kind == "wrap")
end

-- The icon for a reward, or nil for kinds that keep their drawn art (currencies, tokens, boosts, badges ...).
function ModelIcon.item(
	parent: Instance?,
	r: { kind: string, id: string? },
	size: number | UDim2,
	opts: Opts?
): ViewportFrame?
	if not ModelIcon.canShow(r) then
		return nil
	end
	local id = r.id :: string
	if r.kind == "weapon" then
		return ModelIcon.weapon(parent, id, size, opts)
	elseif r.kind == "mask" then
		return ModelIcon.mask(parent, id, size, opts)
	end
	return ModelIcon.wrap(parent, id, size, opts)
end

return ModelIcon
