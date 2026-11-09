--!strict
-- Brief 12: the look of the server's drones (Run/Drones.lua) and rings. Every drone is a small mesh this client moves
-- each frame along the same orbit the server evaluates (shared DroneOrbit on the server clock), lerped to the
-- caster: no physics, no collision, never in anyone's way. Shots come batched (DroneShots) and draw from a shared
-- pool of tracer parts. Also here: PYRO's Inferno ring (the molotov fire set drawn round the caster's feet, trailing
-- them), the AEGIS bubble and its HP bar, the sentry's ready beep. Everything scales with Config.MobileFxScale.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local DroneOrbit = require(Shared:WaitForChild("DroneOrbit"))
local Classes = require(Shared:WaitForChild("Classes"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local SCALE = if ClientState.isMobile then Config.MobileFxScale else 1

local folder = Instance.new("Folder")
folder.Name = "GHSDrones"
folder.Parent = Workspace

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	return p
end

local function rootOf(userId: number): BasePart?
	local p = Players:GetPlayerByUserId(userId)
	local char = p and p.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function swarmColor(): Color3
	local c = Classes.ById.SWARM
	return Color3.fromHex(if c then c.color else "6FE3D2")
end

------------------------------------------------------------------ Tracer pool
-- One shared pool of thin neon parts: a swarm of 40 firing 2 shots a second reuses the same few dozen parts.
local POOL_SIZE = math.max(8, math.round(32 * SCALE))
local pool: { Part } = {}
local poolNext = 1
for i = 1, POOL_SIZE do
	pool[i] = part({
		Name = "DroneTracer",
		Material = Enum.Material.Neon,
		Size = Vector3.new(0.08, 0.08, 1),
		Transparency = 1,
		Parent = folder,
	})
end

local function tracer(from: Vector3, to: Vector3, color: Color3, life: number, width: number?)
	local p = pool[poolNext]
	poolNext = poolNext % POOL_SIZE + 1
	local len = (to - from).Magnitude
	if len < 0.05 then
		return
	end
	local w = width or 0.08
	p.Size = Vector3.new(w, w, len)
	p.CFrame = CFrame.lookAt(from:Lerp(to, 0.5), to)
	p.Color = color
	p.Transparency = 0.1
	TweenService:Create(p, TweenInfo.new(life, Enum.EasingStyle.Linear), { Transparency = 1 }):Play()
end

------------------------------------------------------------------ Drones
type DroneView = {
	id: number,
	kind: string,
	owner: number,
	spec: DroneOrbit.Spec,
	model: Model,
	body: BasePart,
	bubble: BasePart?,
	bar: Frame?,
	barGui: BillboardGui?,
	maxHp: number,
	pos: Vector3?,
}
local views: { [number]: DroneView } = {}

local function buildDrone(kind: string, radius: number?): (Model, BasePart, BasePart?)
	local model = Instance.new("Model")
	model.Name = "Drone"
	local color = if kind == "heal" then Color3.fromHex(Config.HealDroneColor) else swarmColor()
	local body = part({
		Name = "Body",
		Size = if kind == "heal" then Vector3.new(0.8, 0.35, 0.8) else Vector3.new(0.65, 0.26, 0.65),
		Color = Color3.fromRGB(44, 46, 54),
		Material = Enum.Material.Metal,
		Parent = model,
	})
	if SCALE >= 1 or kind ~= "attack" then
		local strip = part({
			Name = "Glow",
			Size = Vector3.new(body.Size.X * 1.05, 0.08, body.Size.Z * 1.05),
			Color = color,
			Material = Enum.Material.Neon,
			Parent = model,
		})
		local w = Instance.new("WeldConstraint")
		w.Part0 = body
		w.Part1 = strip
		w.Parent = strip
	end
	local bubble: BasePart? = nil
	if kind == "aegis" then
		local r = radius or 7
		bubble = part({
			Name = "Bubble",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(r * 2, r * 2, r * 2),
			Color = swarmColor(),
			Material = Enum.Material.ForceField,
			Transparency = 0.1,
			Parent = model,
		})
	end
	model.PrimaryPart = body
	model.Parent = folder
	return model, body, bubble
end

local function hpBar(userId: number): (BillboardGui?, Frame?)
	local root = rootOf(userId)
	local char = root and root.Parent
	local head = char and char:FindFirstChild("Head")
	if not head then
		return nil, nil
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "AegisHP"
	gui.Size = UDim2.fromScale(4, 0.45)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
	gui.AlwaysOnTop = true
	gui.Adornee = head :: BasePart
	gui.Parent = folder
	local back = Instance.new("Frame")
	back.BackgroundColor3 = Color3.fromHex("14161C")
	back.BorderSizePixel = 0
	back.Size = UDim2.fromScale(1, 1)
	back.Parent = gui
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = swarmColor()
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(1, 1)
	fill.Parent = back
	return gui, fill
end

------------------------------------------------------------------ Hum: one emitter per caster, gain by count
local hums: { [number]: Sound } = {}
local function refreshHum(userId: number)
	local n = 0
	for _, v in views do
		if v.owner == userId then
			n += 1
		end
	end
	local s = hums[userId]
	if n == 0 or Config.DroneHumSoundId == "" then
		if s then
			s:Destroy()
			hums[userId] = nil
		end
		return
	end
	local root = rootOf(userId)
	if not root then
		return
	end
	if not s or s.Parent ~= root then
		if s then
			s:Destroy()
		end
		s = Instance.new("Sound")
		s.Name = "DroneHum"
		s.SoundId = Config.DroneHumSoundId
		s.Looped = true
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = 6
		s.RollOffMaxDistance = 60
		s.Parent = root
		s:Play()
		hums[userId] = s
	end
	s.Volume = math.min(Config.DroneHumMaxVolume, Config.DroneHumVolumePer * n)
end

local function soundAtPoint(position: Vector3, id: string, pitch: number, volume: number)
	local anchor = part({ Name = "DroneSound", Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1, Parent = folder })
	anchor.Position = position
	UI.soundAt(anchor, id, pitch, volume, 70)
	task.delay(3, function()
		anchor:Destroy()
	end)
end

-- Voice caps: a big swarm fires many shots a second; only this many zaps play per second.
local zapBudget = 0

local function onSpawn(data: any)
	local id = tonumber(data.id)
	if not id or views[id] then
		return
	end
	local spec = data.spec :: DroneOrbit.Spec
	local model, body, bubble = buildDrone(tostring(data.kind), tonumber(data.radius))
	local v: DroneView = {
		id = id,
		kind = tostring(data.kind),
		owner = tonumber(data.owner) or 0,
		spec = spec,
		model = model,
		body = body,
		bubble = bubble,
		maxHp = tonumber(data.maxHp) or 0,
	}
	if v.kind == "aegis" then
		v.barGui, v.bar = hpBar(v.owner)
	end
	views[id] = v
	local root = rootOf(v.owner)
	if root then
		v.pos = root.Position
		model:PivotTo(CFrame.new(root.Position))
		-- The whir up.
		UI.soundAt(root, Theme.Sounds.swap, if v.kind == "aegis" then 0.7 else 1.6, 0.25, 50)
	end
	refreshHum(v.owner)
end

local function onGone(data: any)
	local v = views[tonumber(data.id) or -1]
	if not v then
		return
	end
	views[v.id] = nil
	-- The 0.3s power-down fade (AEGIS: its burst is the server's Blast).
	for _, p in v.model:GetDescendants() do
		if p:IsA("BasePart") then
			TweenService:Create(p, TweenInfo.new(0.3), { Transparency = 1, Size = p.Size * 0.6 }):Play()
		end
	end
	if v.barGui then
		v.barGui:Destroy()
	end
	task.delay(0.35, function()
		v.model:Destroy()
	end)
	refreshHum(v.owner)
end

local function onShots(data: any)
	local list = data.list
	if typeof(list) ~= "table" then
		return
	end
	for _, s in list do
		local v = views[tonumber(s.i) or -1]
		if not v or typeof(s.to) ~= "Vector3" then
			continue
		end
		local from = v.body.Position
		if s.h then
			tracer(from, s.to, Color3.fromHex(Config.HealDroneColor), Config.FieldTickSec * 0.8, 0.12)
		elseif s.f then
			-- SURGE fetch: a thin line to the bag it pulls.
			tracer(from, s.to, Theme.Colors.cash, 0.25, 0.05)
		else
			tracer(from, s.to, swarmColor(), 0.07)
			if typeof(s.r) == "Vector3" then
				tracer(s.to, s.r, swarmColor(), 0.09) -- SURGE ricochet
			end
			if typeof(s.r2) == "Vector3" and typeof(s.r) == "Vector3" then
				tracer(s.r, s.r2, swarmColor(), 0.09)
			end
			if zapBudget > 0 then
				zapBudget -= 1
				UI.soundAt(v.body, Theme.Sounds.laser, 2.2, 0.06, 45)
			end
		end
	end
end

local function onAegisHp(data: any)
	local v = views[tonumber(data.id) or -1]
	if not v then
		return
	end
	local hp = tonumber(data.hp) or 0
	if v.bar then
		v.bar.Size = UDim2.fromScale(math.clamp(hp / math.max(1, v.maxHp), 0, 1), 1)
	end
	if v.bubble then
		v.bubble.Transparency = 0.6
		TweenService:Create(v.bubble, TweenInfo.new(0.2), { Transparency = 0.1 }):Play()
		UI.soundAt(v.body, Theme.Sounds.glass, 1.6, 0.12, 50) -- the crack
	end
end

------------------------------------------------------------------ Inferno ring
type Ring = {
	owner: number,
	radius: number,
	untilT: number,
	model: Model,
	anchors: { BasePart },
	rim: { BasePart },
	center: Vector3?,
	spin: number,
}
local rings: { [number]: Ring } = {}

local function endRing(userId: number)
	local r = rings[userId]
	if not r then
		return
	end
	rings[userId] = nil
	for _, d in r.model:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			d.Enabled = false
		elseif d:IsA("BasePart") then
			TweenService:Create(d, TweenInfo.new(0.4), { Transparency = 1 }):Play()
		end
	end
	task.delay(1.2, function()
		r.model:Destroy()
	end)
end

local function startRing(data: any)
	local userId = tonumber(data.owner) or 0
	endRing(userId)
	local radius = tonumber(data.radius) or Config.InfernoRadius
	local model = Instance.new("Model")
	model.Name = "Inferno"
	local fireColor = Color3.fromHex(Config.AllyFireColor)
	local fire2 = Color3.fromHex(Config.AllyFireSecondary)
	local anchors = {}
	-- Round 29b: flames by circumference (about one every 6.5 studs) so a big ring stays a ring of fire.
	local n = math.clamp(math.round(2 * math.pi * radius / 6.5 * SCALE), 6, 28)
	for _ = 1, n do
		local a = part({ Name = "Flame", Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1, Parent = model })
		-- Round 29b: flames locked to their anchor (no trail left on the map when you move); they rise while you
		-- stand and stay on the ring as it follows you.
		local f = Instance.new("ParticleEmitter")
		f.Name = "InfernoFlame"
		f.Texture = "rbxasset://textures/particles/fire_main.dds"
		f.LockedToPart = true
		-- Sized and coloured like the molotov's Fire (Size 3.2, Heat 9, the ally blue): a blue body with a pale core,
		-- tall flames, only now they ride their spot on the ring instead of trailing behind.
		f.LightEmission = 0.6
		f.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, fireColor:Lerp(fire2, 0.35)),
			ColorSequenceKeypoint.new(0.3, fireColor),
			ColorSequenceKeypoint.new(1, fireColor),
		})
		f.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1.8),
			NumberSequenceKeypoint.new(0.4, 3.2),
			NumberSequenceKeypoint.new(1, 0.8),
		})
		f.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(0.6, 0.5),
			NumberSequenceKeypoint.new(1, 1),
		})
		f.Lifetime = NumberRange.new(0.6, 0.9)
		f.Rate = 26
		f.Speed = NumberRange.new(5, 8)
		f.Acceleration = Vector3.new(0, 4, 0)
		f.Drag = 1
		f.SpreadAngle = Vector2.new(10, 10)
		f.EmissionDirection = Enum.NormalId.Top
		f.Rotation = NumberRange.new(0, 360)
		f.RotSpeed = NumberRange.new(-90, 90)
		f.Parent = a
		table.insert(anchors, a)
	end
	local rim = {}
	local segs = math.max(12, math.round(Config.AllyFieldRimSegments * SCALE))
	local segLen = 2 * math.pi * radius / segs * 1.08
	for _ = 1, segs do
		table.insert(
			rim,
			part({
				Name = "Rim",
				Size = Vector3.new(Config.AllyFieldRimStuds, 0.12, segLen),
				Color = fireColor,
				Material = Enum.Material.Neon,
				Transparency = Config.AllyFieldRimTransparency,
				Parent = model,
			})
		)
	end
	model.Parent = folder
	rings[userId] = {
		owner = userId,
		radius = radius,
		untilT = tonumber(data.untilT) or 0,
		model = model,
		anchors = anchors,
		rim = rim,
		center = nil,
		spin = 0,
	}
	local root = rootOf(userId)
	if root then
		UI.soundAt(root, Theme.Sounds.swap, 0.5, 0.4, 70) -- the whoosh as it lights
	end
end

------------------------------------------------------------------ Frame
RunService.RenderStepped:Connect(function(dt)
	local t = ClientState.serverNow()
	zapBudget = math.min(zapBudget + dt * Config.DroneZapsPerSec, Config.DroneZapsPerSec)
	local alpha = 1 - math.exp(-14 * dt)
	for _, v in views do
		local root = rootOf(v.owner)
		if not root then
			continue
		end
		local target = root.Position + DroneOrbit.offset(v.spec, t)
		local pos = (v.pos or target):Lerp(target, alpha)
		local vel = pos - (v.pos or pos)
		v.pos = pos
		local look = if vel.Magnitude > 0.01 then CFrame.lookAt(pos, pos + vel) else CFrame.new(pos)
		v.body.CFrame = look
		local bubble = v.bubble
		if bubble then
			bubble.CFrame = CFrame.new(root.Position)
		end
	end
	for userId, r in rings do
		local root = rootOf(userId)
		if not root then
			continue
		end
		-- Round 29b: the ring is bound to the caster's feet (it twists round them, never trails behind).
		local c = root.Position - Vector3.new(0, 2.9, 0)
		r.center = c
		r.spin += dt * 0.6
		for i, a in r.anchors do
			local ang = r.spin + (i / #r.anchors) * math.pi * 2
			a.Position = c + Vector3.new(math.cos(ang) * r.radius, 0.3, math.sin(ang) * r.radius)
		end
		for i, seg in r.rim do
			local ang = (i - 0.5) / #r.rim * math.pi * 2
			seg.CFrame = CFrame.new(c.X + math.cos(ang) * r.radius, c.Y + 0.1, c.Z + math.sin(ang) * r.radius)
				* CFrame.Angles(0, -ang, 0)
		end
		if r.untilT > 0 and t > r.untilT + 0.5 then
			endRing(userId) -- safety: the end event never came
		end
	end
end)

ClientState.Juice:Connect(function(name: string, data: any)
	if typeof(data) ~= "table" then
		return
	end
	if name == "DroneSpawn" then
		onSpawn(data)
	elseif name == "DroneGone" then
		onGone(data)
	elseif name == "DroneShots" then
		onShots(data)
	elseif name == "AegisHp" then
		onAegisHp(data)
	elseif name == "InfernoStart" then
		startRing(data)
	elseif name == "InfernoExtend" then
		-- BACKDRAFT pushed the end out: the safety end-check follows the new time.
		local r = rings[tonumber(data.owner) or 0]
		if r then
			r.untilT = tonumber(data.untilT) or r.untilT
		end
	elseif name == "InfernoEnd" then
		endRing(tonumber(data.owner) or 0)
	elseif name == "SentryReady" and typeof(data.position) == "Vector3" then
		soundAtPoint(data.position, Theme.Sounds.beep, 1.3, 0.35)
	elseif name == "SurgeStart" then
		-- The chorus swell; the caster's drones flare.
		local root = rootOf(tonumber(data.owner) or 0)
		if root then
			UI.soundAt(root, Theme.Sounds.upgrade, 1.25, 0.3, 70)
		end
		for _, v in views do
			if v.owner == tonumber(data.owner) and v.kind == "attack" then
				local glow = v.model:FindFirstChild("Glow")
				if glow and glow:IsA("BasePart") then
					glow.Color = Color3.new(1, 1, 1)
					TweenService:Create(glow, TweenInfo.new(0.6), { Color = swarmColor() }):Play()
				end
			end
		end
	end
end)

-- A respawned caster (new character): the hum moves with them.
Players.PlayerAdded:Connect(function(p)
	p.CharacterAdded:Connect(function()
		task.defer(refreshHum, p.UserId)
	end)
end)
for _, p in Players:GetPlayers() do
	p.CharacterAdded:Connect(function()
		task.defer(refreshHum, p.UserId)
	end)
end
