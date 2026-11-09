--!strict
-- Brief 13: the street dressing's life on each client (the server only places pieces: Dressing.lua). Light bars
-- strobe red / blue, the searchlights sweep the facade, the stage 3 helicopter flies its HeliPath loop on the server
-- clock (so every client sees it in the same place) with spinning rotors, its spotlight on the crew member the
-- server names and, on boss waves, dust kicked up under it. A siren bed per stage plays from the street, ducked
-- while a wave is fought and faint inside the bank; new pieces land with a dust puff when you are on the street.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Ground = require(Shared:WaitForChild("Ground"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))

------------------------------------------------------------------ Puffs
local function puff(at: Vector3)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(6, 0.5, 6)
	p.CFrame = CFrame.new(at + Vector3.new(0, 0.5, 0))
	p.Parent = Workspace
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.Lifetime = NumberRange.new(0.8, 1.4)
	e.Speed = NumberRange.new(6, 12)
	e.SpreadAngle = Vector2.new(70, 70)
	e.Size = NumberSequence.new(2.5, 6)
	e.Transparency = NumberSequence.new(0.5, 1)
	e.Color = ColorSequence.new(Color3.fromHex("B8AE9C"))
	e.Parent = p
	e:Emit(24)
	task.delay(2, function()
		p:Destroy()
	end)
end

ClientState.Juice:Connect(function(name: string, data: any)
	if name == "DressingPuff" and typeof(data) == "table" and typeof(data.positions) == "table" then
		for _, at in data.positions do
			if typeof(at) == "Vector3" then
				puff(at)
			end
		end
	end
end)

------------------------------------------------------------------ The live folder
local bank = Workspace:WaitForChild("Bank", 30)
if not bank then
	return
end
local live = bank:WaitForChild("DressingLive", 60)
if not live then
	return
end

-- Light bars: every part named LightRed / LightBlue / LightWhite in the live folder.
local lights: { [BasePart]: { phase: number, light: PointLight? } } = {}
-- Searchlights: Head, Lens and Shaft rotate together about the head.
type Sweep = { head: BasePart, parts: { { part: BasePart, base: CFrame } }, phase: number }
local sweeps: { [Model]: Sweep } = {}
-- The helicopter: every part's offset from the root, and the rotors'.
type Heli = {
	model: Model,
	root: BasePart,
	parts: { { part: BasePart, offset: CFrame, spin: string? } },
	hub: CFrame,
	tail: CFrame,
	spot: BasePart?,
	shaft: BasePart?,
	dust: BasePart?,
	sound: Sound?,
	path: { Vector3 },
	lengths: { number },
	total: number,
}
local heli: Heli? = nil
local vehicles: { [Model]: boolean } = {} -- Round 30d: the pieces with light bars (cruisers, the SWAT van, ambulance)

local function addPiece(m: Instance)
	if not m:IsA("Model") then
		return
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and (d.Name == "LightRed" or d.Name == "LightBlue" or d.Name == "LightWhite") then
			lights[d] = {
				phase = if d.Name == "LightRed" then 0 else 0.5,
				light = d:FindFirstChildOfClass("PointLight"),
			}
			vehicles[m] = true -- Round 30d: the siren plays from the nearest of these
		end
	end
	local head = m:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		local parts = {}
		for _, n in { "Head", "Lens", "Shaft" } do
			local p = m:FindFirstChild(n)
			if p and p:IsA("BasePart") then
				table.insert(parts, { part = p, base = p.CFrame })
			end
		end
		sweeps[m] = { head = head, parts = parts, phase = math.random() * math.pi * 2 }
	end
	if m.Name == "Helicopter" then
		local root = m:FindFirstChild("Root")
		if not root or not root:IsA("BasePart") then
			return
		end
		local rootCF = root.CFrame
		local hubPart = m:FindFirstChild("Hub")
		local tailPart = m:FindFirstChild("TailRotor")
		local h: Heli = {
			model = m,
			root = root,
			parts = {},
			hub = rootCF:Inverse() * (if hubPart and hubPart:IsA("BasePart") then hubPart.CFrame else rootCF),
			tail = rootCF:Inverse() * (if tailPart and tailPart:IsA("BasePart") then tailPart.CFrame else rootCF),
			spot = m:FindFirstChild("Spot") :: BasePart?,
			shaft = m:FindFirstChild("SpotShaft") :: BasePart?,
			dust = m:FindFirstChild("Dust") :: BasePart?,
			sound = nil,
			path = {},
			lengths = {},
			total = 0,
		}
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") and d ~= h.spot and d ~= h.shaft and d ~= h.dust then
				table.insert(h.parts, {
					part = d,
					offset = rootCF:Inverse() * d.CFrame,
					spin = if d.Name == "Rotor" then "main" elseif d.Name == "TailRotor" then "tail" else nil,
				})
			end
		end
		local count = tonumber(m:GetAttribute("Count")) or 0
		local alt = tonumber(m:GetAttribute("Altitude")) or Config.HeliAltitude
		for i = 1, count do
			local p = m:GetAttribute("P" .. i)
			if typeof(p) == "Vector3" then
				table.insert(h.path, Vector3.new(p.X, alt, p.Z))
			end
		end
		for i, p in h.path do
			local q = h.path[i % #h.path + 1]
			local len = (q - p).Magnitude
			h.lengths[i] = len
			h.total += len
		end
		local body = m:FindFirstChild("Body")
		local s = body and body:FindFirstChildOfClass("Sound")
		if s then
			s.SoundId = Config.HeliRotorSound
			s.Volume = Config.HeliRotorVolume
			s:Play()
			h.sound = s
		end
		heli = h
	end
end

for _, c in live:GetChildren() do
	addPiece(c)
end
live.ChildAdded:Connect(function(c)
	task.defer(addPiece, c)
end)
live.ChildRemoved:Connect(function(c)
	for part in table.clone(lights) do
		if not part:IsDescendantOf(live) then
			lights[part] = nil
		end
	end
	if c:IsA("Model") then
		sweeps[c] = nil
		vehicles[c] = nil
		local h = heli
		if h and h.model == c then
			heli = nil
		end
	end
end)

------------------------------------------------------------------ The siren bed
local emitter = Instance.new("Part")
emitter.Name = "DressingSirens"
emitter.Anchored = true
emitter.CanCollide = false
emitter.CanQuery = false
emitter.CanTouch = false
emitter.Transparency = 1
emitter.Size = Vector3.new(1, 1, 1)
local street = live:GetAttribute("Street")
emitter.CFrame = CFrame.new(if typeof(street) == "Vector3" then street else Vector3.zero)
emitter.Parent = Workspace.CurrentCamera or Workspace
local bed = Instance.new("Sound")
bed.Name = "SirenBed"
bed.Looped = true
bed.Volume = 0
bed.RollOffMode = Enum.RollOffMode.InverseTapered
bed.RollOffMinDistance = Config.DressingAmbienceRollOff[1] or 60
bed.RollOffMaxDistance = Config.DressingAmbienceRollOff[2] or 420
bed.SoundGroup = UI.soundGroup("SFX")
bed.Parent = emitter

local function refreshBed()
	local id = live:GetAttribute("Ambience")
	local want = if typeof(id) == "string" then id else ""
	if want == "" then
		bed:Stop()
		bed.SoundId = ""
		return
	end
	if bed.SoundId ~= want then
		bed.SoundId = want
		bed:Play()
	elseif not bed.IsPlaying then
		bed:Play()
	end
end
live:GetAttributeChangedSignal("Ambience"):Connect(refreshBed)
refreshBed()

------------------------------------------------------------------ The frame
local function posOnLoop(h: Heli, dist: number): (Vector3, Vector3)
	local d = dist % math.max(h.total, 1)
	for i, len in h.lengths do
		if d <= len or i == #h.lengths then
			local a, b = h.path[i], h.path[i % #h.path + 1]
			local t = if len > 0 then math.clamp(d / len, 0, 1) else 0
			return a:Lerp(b, t), (b - a)
		end
		d -= len
	end
	local first: Vector3 = h.path[1] or Vector3.zero
	return first, Vector3.new(0, 0, -1)
end

local acc = 0
local sirenAcc = 0
local hasVehicle = false
local insideMult = 1 -- Round 30d: DressingInsideMult while you stand inside the bank

-- Inside the bank = inside any zone volume but the street (the node parts are there, hidden, on every client).
local function insideBank(p: Vector3): boolean
	local nodes = bank:FindFirstChild("Nodes")
	local zones = nodes and nodes:FindFirstChild("Zones")
	if not zones then
		return false
	end
	for _, z in zones:GetChildren() do
		if z:IsA("BasePart") and z.Name ~= "street" then
			local o = z.CFrame:PointToObjectSpace(p)
			local h = z.Size / 2
			if math.abs(o.X) <= h.X and math.abs(o.Y) <= h.Y and math.abs(o.Z) <= h.Z then
				return true
			end
		end
	end
	return false
end
RunService.RenderStepped:Connect(function(dt)
	local now = ClientState.serverNow()
	-- Light bars: alternate halves.
	if next(lights) then
		local beat = (now * Config.DressingFlashHz) % 1
		for part, l in lights do
			local on = ((beat + l.phase) % 1) < 0.5
			part.Transparency = if on then 0 else 0.75
			local light = l.light
			if light then
				light.Enabled = on
			end
		end
	end
	-- Searchlights: a slow sweep about the head, tilted up at the facade.
	for _, s in sweeps do
		local period = math.max(Config.SearchlightSweepSec, 0.5)
		local yaw = math.rad(Config.SearchlightSweepDeg) * math.sin(now / period * math.pi * 2 + s.phase)
		local pivot = s.parts[1].base.Position
		local rot = CFrame.new(pivot)
			* CFrame.Angles(0, yaw, 0)
			* CFrame.Angles(math.rad(14), 0, 0)
			* CFrame.new(-pivot)
		for _, e in s.parts do
			e.part.CFrame = rot * e.base
		end
	end
	-- The helicopter.
	local h = heli
	if h and #h.path >= 2 and h.model.Parent then
		local speed = tonumber(h.model:GetAttribute("Speed")) or Config.HeliSpeed
		local pos, tangent = posOnLoop(h, now * speed)
		local flat = Vector3.new(tangent.X, 0, tangent.Z)
		local look = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
		local bob = math.sin(now * 0.9) * 1.2
		local rootCF = CFrame.lookAt(pos + Vector3.new(0, bob, 0), pos + look) * CFrame.Angles(0, 0, math.rad(-12))
		local mainSpin = CFrame.Angles(0, now * 22 % (math.pi * 2), 0)
		local tailSpin = CFrame.Angles(now * 30 % (math.pi * 2), 0, 0)
		for _, e in h.parts do
			if e.spin == "main" then
				e.part.CFrame = rootCF * h.hub * mainSpin * (h.hub:Inverse() * e.offset)
			elseif e.spin == "tail" then
				e.part.CFrame = rootCF * h.tail * tailSpin * (h.tail:Inverse() * e.offset)
			else
				e.part.CFrame = rootCF * e.offset
			end
		end
		-- The spotlight on the named crew member (else straight down).
		local spotFrom = (rootCF * CFrame.new(0, 0.3, -6.5)).Position
		local targetId = tonumber(h.model:GetAttribute("SpotTarget"))
		local target: Vector3? = nil
		if targetId then
			local p = Players:GetPlayerByUserId(targetId)
			local r = p and p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if r then
				target = r.Position
			end
		end
		local aim = target or (spotFrom - Vector3.new(0, 80, 0))
		local spot, shaft = h.spot, h.shaft
		if spot then
			spot.CFrame = CFrame.lookAt(spotFrom, aim)
		end
		if shaft then
			local len = math.min((aim - spotFrom).Magnitude, 200)
			shaft.Size = Vector3.new(shaft.Size.X, shaft.Size.Y, len)
			shaft.CFrame = CFrame.lookAt(spotFrom, aim) * CFrame.new(0, 0, -len / 2)
		end
		-- Boss waves: dust kicked up under it.
		acc += dt
		local dust = h.dust
		if dust and acc > 0.25 then
			acc = 0
			local boss = live:GetAttribute("Boss") == true
			local emitterFx = dust:FindFirstChildOfClass("ParticleEmitter")
			if emitterFx then
				emitterFx.Enabled = boss
			end
			if boss then
				local g = Ground.y(pos, pos.Y - 100, 0, 200)
				dust.CFrame = CFrame.new(pos.X, g + 0.5, pos.Z)
			end
		end
	end
	-- The siren bed: louder on boss waves, ducked while a wave is fought. Round 30d: it plays from the police
	-- vehicle nearest you (a short roll-off), so it is loud only beside the cars and faint or gone anywhere else.
	sirenAcc += dt
	if sirenAcc >= 0.25 then
		sirenAcc = 0
		local cam = Workspace.CurrentCamera
		local from = if cam then cam.CFrame.Position else Vector3.zero
		local best: Vector3? = nil
		local bestD = math.huge
		for v in vehicles do
			if v.Parent then
				local p = v:GetPivot().Position
				local d = (p - from).Magnitude
				if d < bestD then
					best, bestD = p, d
				end
			end
		end
		hasVehicle = best ~= nil
		local char = game:GetService("Players").LocalPlayer.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		insideMult = if root and insideBank(root.Position) then Config.DressingInsideMult else 1
		local hh = heli
		if hh and hh.sound then
			hh.sound.Volume = Config.HeliRotorVolume * insideMult
		end
		if best then
			emitter.CFrame = CFrame.new(best + Vector3.new(0, 3, 0))
		end
	end
	local sync = ClientState.sync
	local fighting = sync ~= nil and sync.waveState == "Wave"
	local boss = live:GetAttribute("Boss") == true
	bed.Volume = if not hasVehicle
		then 0
		else Config.DressingAmbienceVolume * (if boss then Config.DressingAmbienceBossMult else 1) * (if fighting
			then Config.DressingAmbienceCombatDuck
			else 1) * insideMult
end)
