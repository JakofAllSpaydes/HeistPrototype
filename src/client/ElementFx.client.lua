--!strict
-- Round 24v: the Elemental weapons' look. Flame / frost streams: a particle jet on the shooter's muzzle while the
-- ticks keep coming (your own from your trigger, teammates' from the server's StreamTick). The arc gun: jagged neon
-- bolts from the muzzle through every enemy the server chained (Lightning). Your own fx leave the first-person
-- viewmodel's muzzle when you're in first person.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent:WaitForChild("ClientState"))
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local player = Players.LocalPlayer
local STREAM_HOLD = 0.16 -- the jet stays on this long after the last tick

local function muzzleFor(userId: number): Attachment?
	if userId == player.UserId and ClientState.firstPerson then
		local v = ClientState.viewMuzzleAtt
		if v and v.Parent then
			return v
		end
	end
	local p = Players:GetPlayerByUserId(userId)
	local char = p and p.Character
	local gun = char and char:FindFirstChild("HeldGun")
	local m = gun and gun:FindFirstChild("Muzzle")
	return if m and m:IsA("Attachment") then m else nil
end

------------------------------------------------------------------ streams
local function jet(element: string): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "ElementJet"
	e.EmissionDirection = Enum.NormalId.Front -- gun space -Z is the muzzle's forward
	e.LightEmission = if element == "fire" then 1 else 0.6
	-- Round 24aa: denser jets; the flame uses Roblox's fire texture (the built-in Fire effect's), spun at random.
	e.Rate = if element == "fire" then 280 else 240
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-120, 120)
	e.SpreadAngle = Vector2.new(9, 9)
	e.Drag = 2.2
	e.LockedToPart = false
	if element == "fire" then
		e.Texture = "rbxasset://textures/particles/fire_main.dds"
		e.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromHex("FFE6A0")),
			ColorSequenceKeypoint.new(0.35, Color3.fromHex("FF8A2A")),
			ColorSequenceKeypoint.new(1, Color3.fromHex("B3261E")),
		})
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 2.4) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
		e.Lifetime = NumberRange.new(0.38, 0.55)
		e.Speed = NumberRange.new(48, 57) -- Round 24aa: reaches the longer flame range
		e.Acceleration = Vector3.new(0, 5, 0)
	else
		e.Color = ColorSequence.new(Color3.fromHex("FFFFFF"), Color3.fromHex("8FD3FF"))
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 2.0) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
		e.Lifetime = NumberRange.new(0.35, 0.5)
		e.Speed = NumberRange.new(30, 36)
		e.Acceleration = Vector3.new(0, -3, 0)
	end
	e.Enabled = false
	return e
end

type Stream = {
	att: Attachment,
	emitter: ParticleEmitter,
	smoke: ParticleEmitter?,
	muzzle: Attachment,
	element: string,
	last: number,
}

-- Round 24aa: a soft dark smoke trailing the flame.
local function smokeTrail(): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "ElementSmoke"
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.EmissionDirection = Enum.NormalId.Front
	e.Color = ColorSequence.new(Color3.fromHex("3A3330"), Color3.fromHex("1A1716"))
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 3.4) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.75), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.6, 0.9)
	e.Speed = NumberRange.new(26, 32)
	e.Drag = 2.5
	e.Rate = 45
	e.SpreadAngle = Vector2.new(10, 10)
	e.Acceleration = Vector3.new(0, 6, 0)
	e.Rotation = NumberRange.new(0, 360)
	e.Enabled = false
	return e
end
local streams: { [number]: Stream } = {}

local function stream(userId: number, element: string)
	local m = muzzleFor(userId)
	if not m or not m.Parent then
		return
	end
	local s = streams[userId]
	if not s or s.muzzle ~= m or s.element ~= element or not s.att.Parent then
		if s then
			s.att:Destroy()
		end
		local att = Instance.new("Attachment")
		att.Name = "ElementJetAtt"
		att.CFrame = m.CFrame
		att.Parent = m.Parent
		local e = jet(element)
		e.Parent = att
		local smoke = if element == "fire" then smokeTrail() else nil
		if smoke then
			smoke.Parent = att
		end
		s = { att = att, emitter = e, smoke = smoke, muzzle = m, element = element, last = 0 }
		streams[userId] = s
	end
	local cur = s :: Stream
	cur.last = os.clock()
	cur.emitter.Enabled = true
	if cur.smoke then
		cur.smoke.Enabled = true
	end
end

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for id, s in streams do
		if not s.att.Parent then
			streams[id] = nil
		elseif now - s.last > STREAM_HOLD and s.emitter.Enabled then
			s.emitter.Enabled = false
			if s.smoke then
				s.smoke.Enabled = false
			end
		end
	end
end)

------------------------------------------------------------------ lightning
local BOLT = Color3.fromHex("9FE6FF")
local function boltPart(a: Vector3, b: Vector3, width: number): Part
	local d = b - a
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = BOLT
	p.Size = Vector3.new(width, width, math.max(d.Magnitude, 0.05))
	p.CFrame = CFrame.lookAt(a + d / 2, b)
	p.Parent = Workspace.CurrentCamera
	return p
end

local function arc(from: Vector3, to: Vector3, parts: { BasePart })
	-- A jagged bolt: a few kinks off the straight line, thinning toward the far end.
	local kinks = math.clamp(math.floor((to - from).Magnitude / 4), 2, 7)
	local prev = from
	for i = 1, kinks do
		local t = i / kinks
		local pt = from:Lerp(to, t)
		if i < kinks then
			pt += Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 1.4
		end
		table.insert(parts, boltPart(prev, pt, 0.12 * (1 - t * 0.5)))
		prev = pt
	end
end

local function lightning(userId: number, points: { Vector3 })
	local m = muzzleFor(userId)
	local from = if m then m.WorldPosition else nil
	if not from then
		return
	end
	local parts: { BasePart } = {}
	local cur = from
	for _, pt in points do
		if typeof(pt) == "Vector3" then
			arc(cur, pt, parts)
			cur = pt
		end
	end
	local light = Instance.new("PointLight")
	light.Color = BOLT
	light.Range = 10
	light.Brightness = 3
	if parts[1] then
		light.Parent = parts[1]
	end
	task.delay(0.07, function()
		for _, p in parts do
			p:Destroy()
		end
	end)
end

------------------------------------------------------------------ plasma beam
-- Round 24ab: the beam follows its shooter's cursor while it holds: yours from your own aim every frame,
-- teammates' from the PlasmaBeamAim updates.
local liveAim: { [number]: Vector3 } = {}
local PLASMA_DEFAULT = Color3.fromHex("5BFF9A")
local function plasmaBeam(
	userId: number,
	dir: Vector3,
	range: number,
	width: number,
	dur: number,
	aim: Vector3?,
	colorHex: string?
)
	local PLASMA = if colorHex then Color3.fromHex(colorHex) else PLASMA_DEFAULT
	local m = muzzleFor(userId)
	if not m then
		return
	end
	local function rod(color: Color3, transparency: number): Part
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = color
		p.Transparency = transparency
		p.Shape = Enum.PartType.Cylinder
		p.Parent = Workspace.CurrentCamera
		return p
	end
	liveAim[userId] = nil
	local outer = rod(PLASMA, 0.3)
	local core = rod(Color3.new(1, 1, 1), 0)
	local light = Instance.new("PointLight")
	light.Color = PLASMA
	light.Range = 10 + width * 4
	light.Brightness = 4
	light.Parent = core
	-- Holds for `dur` from the muzzle along the fired direction, flickering a touch, then thins and fades.
	local fade = Config.PlasmaBeamFadeSec
	local t0 = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local age = os.clock() - t0
		local mm = muzzleFor(userId) or m
		local from = if mm and mm.Parent then mm.WorldPosition else nil
		if not from or age > dur + fade then
			conn:Disconnect()
			outer:Destroy()
			core:Destroy()
			return
		end
		local k = if age <= dur then 1 else 1 - (age - dur) / fade
		local flicker = 1 + math.sin(age * 60) * 0.06
		local w = width * k * flicker
		-- Through the aim point when we have it (the line the damage takes), out to the full range.
		local cur = aim
		if userId == player.UserId and player.Character and age <= dur then
			cur = ClientState.cursorAimPoint(player.Character)
		elseif liveAim[userId] then
			cur = liveAim[userId]
		end
		local through = if cur and (cur - from).Magnitude > 1 then (cur - from).Unit else dir
		local to = from + through * range
		local d = to - from
		local cf = CFrame.lookAt(from + d / 2, to) * CFrame.Angles(0, math.rad(90), 0)
		outer.Size = Vector3.new(d.Magnitude, math.max(0.05, w), math.max(0.05, w))
		outer.CFrame = cf
		outer.Transparency = 0.3 + 0.7 * (1 - k)
		local cw = math.max(0.06, w * 0.35)
		core.Size = Vector3.new(d.Magnitude, cw, cw)
		core.CFrame = cf
		core.Transparency = 1 - k
	end)
	ClientState.Juice:Fire("Shake", { amp = 0.08 + width * 0.06, dur = math.max(0.15, dur) })
end

ClientState.Juice:Connect(function(name: string, data: any)
	if name == "LocalStream" then
		stream(player.UserId, tostring(data.element))
	elseif name == "StreamTick" and typeof(data) == "table" then
		local id = tonumber(data.userId) or 0
		if id ~= player.UserId then
			stream(id, tostring(data.element))
		end
	elseif name == "PlasmaBeam" and typeof(data) == "table" and typeof(data.dir) == "Vector3" then
		plasmaBeam(
			tonumber(data.userId) or 0,
			data.dir,
			tonumber(data.range) or 160,
			tonumber(data.width) or 1,
			tonumber(data.dur) or 0.1,
			if typeof(data.aim) == "Vector3" then data.aim else nil,
			if typeof(data.color) == "string" then data.color else nil
		)
	elseif name == "PlasmaBeamAim" and typeof(data) == "table" and typeof(data.aim) == "Vector3" then
		liveAim[tonumber(data.userId) or 0] = data.aim
	elseif name == "Lightning" and typeof(data) == "table" and typeof(data.points) == "table" then
		lightning(tonumber(data.userId) or 0, data.points)
	end
end)
