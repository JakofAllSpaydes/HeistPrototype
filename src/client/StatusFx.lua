--!strict
-- Element looks on enemies (brief 5), all client side off the attributes Elements.lua sets on the enemy model:
-- Burning (orange tint, embers), Chilled (blue tint, a frost crackle of white shards), Frozen (deep ice tint,
-- Ice material), MarkedUntil (SHARPSHOOTER's Eagle Eye: a red Highlight through walls, plus the ping ring on
-- EagleEye). ElementShock draws CONCUSSIVE's white shock ring at the hit. The tint composes with the hit flash
-- (WorldFx): a part mid-flash gets its restore color updated instead of being painted over.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent:WaitForChild("ClientState"))

local StatusFx = {}

local FIRE = Color3.fromRGB(255, 120, 30)
local ICE = Color3.fromRGB(70, 165, 255) -- a clear, saturated blue so a slowed enemy reads at a glance

local watched: { [Model]: boolean } = {}

local function bodyParts(model: Model): { BasePart }
	local out = {}
	for _, p in model:GetChildren() do
		-- The root is the visible body on these rigs; the head keeps its own (hitbox / stun) color.
		if p:IsA("BasePart") and p.Name ~= "Head" and p.Transparency < 1 then
			table.insert(out, p)
		end
	end
	return out
end

local function setColor(p: BasePart, c: Color3)
	if p:GetAttribute("Flashing") == true then
		p:SetAttribute("OrigColor", c)
	else
		p.Color = c
	end
end

local function baseColor(p: BasePart): Color3
	local c = p:GetAttribute("StatusBase") :: Color3?
	if not c then
		local orig = p:GetAttribute("OrigColor") :: Color3?
		c = if p:GetAttribute("Flashing") == true and orig then orig else p.Color
		p:SetAttribute("StatusBase", c)
	end
	return c :: Color3
end

local function emitter(root: BasePart, name: string, color: Color3, rise: boolean): ParticleEmitter
	local existing = root:FindFirstChild(name)
	if existing and existing:IsA("ParticleEmitter") then
		return existing
	end
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	-- Embers rise and glow; frost is bigger, brighter flakes (white into the ice blue) that drift down.
	e.Color = if rise then ColorSequence.new(color) else ColorSequence.new(Color3.new(1, 1, 1), color)
	e.LightEmission = if rise then 1 else 0.8
	e.Size = if rise
		then NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
		else NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0.1) })
	e.Lifetime = NumberRange.new(0.4, 0.8)
	e.Rate = if rise then 14 else 16
	e.Speed = NumberRange.new(1, 3)
	e.SpreadAngle = Vector2.new(35, 35)
	e.Acceleration = if rise then Vector3.new(0, 6, 0) else Vector3.new(0, -4, 0)
	e.Parent = root
	return e
end

local function clearEmitter(root: BasePart, name: string)
	local e = root:FindFirstChild(name)
	if e then
		e:Destroy()
	end
end

local function crackle(root: BasePart)
	local att = Instance.new("Attachment")
	att.Parent = root
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.Color = ColorSequence.new(Color3.new(1, 1, 1), ICE)
	e.LightEmission = 0.6
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) })
	e.Lifetime = NumberRange.new(0.2, 0.45)
	e.Speed = NumberRange.new(4, 9)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Drag = 3
	e.Parent = att
	e:Emit(12)
	task.delay(1, function()
		att:Destroy()
	end)
end

local function refresh(model: Model)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local burning = model:GetAttribute("Burning") == true
	local chilled = model:GetAttribute("Chilled") == true
	local frozen = model:GetAttribute("Frozen") == true
	local tint: Color3? = nil
	local amount = 0
	if frozen then
		tint, amount = ICE, 0.75
	elseif chilled then
		tint, amount = ICE, 0.55
	elseif burning then
		tint, amount = FIRE, 0.4
	end
	for _, p in bodyParts(model) do
		if tint then
			setColor(p, baseColor(p):Lerp(tint, amount))
		else
			local base = p:GetAttribute("StatusBase") :: Color3?
			if base then
				setColor(p, base)
				p:SetAttribute("StatusBase", nil)
			end
		end
		if frozen then
			if p:GetAttribute("StatusMat") == nil then
				p:SetAttribute("StatusMat", p.Material.Name)
			end
			p.Material = Enum.Material.Ice
		else
			local mat = p:GetAttribute("StatusMat")
			if typeof(mat) == "string" then
				p.Material = (Enum.Material :: any)[mat]
				p:SetAttribute("StatusMat", nil)
			end
		end
	end
	if root then
		if burning then
			emitter(root, "StatusEmbers", FIRE, true)
		else
			clearEmitter(root, "StatusEmbers")
		end
		if chilled or frozen then
			emitter(root, "StatusFrost", ICE, false)
		else
			clearEmitter(root, "StatusFrost")
		end
	end
end

-- Eagle Eye: a red Highlight through walls (the end-of-wave straggler look) until MarkedUntil passes.
local MARK_RED = Color3.fromHex("E8554D")
local marked: { [Model]: number } = {}
local function refreshMark(m: Model)
	local untilT = tonumber(m:GetAttribute("MarkedUntil")) or 0
	local on = untilT > ClientState.serverNow() and m:FindFirstChildOfClass("Humanoid") ~= nil
	local h = m:FindFirstChild("EagleMark")
	if on then
		marked[m] = untilT
		if not h then
			local hl = Instance.new("Highlight")
			hl.Name = "EagleMark"
			hl.FillColor = MARK_RED
			hl.FillTransparency = 0.5
			hl.OutlineColor = MARK_RED
			hl.OutlineTransparency = 0
			hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			hl.Parent = m
		end
	else
		marked[m] = nil
		if h then
			h:Destroy()
		end
	end
end

local function watch(model: Instance)
	if not model:IsA("Model") or watched[model] then
		return
	end
	watched[model] = true
	local m = model :: Model
	m.AttributeChanged:Connect(function(attr)
		if attr == "MarkedUntil" then
			refreshMark(m)
			return
		end
		if attr == "Burning" or attr == "Chilled" or attr == "Frozen" then
			if attr == "Chilled" and m:GetAttribute("Chilled") == true then
				local root = m:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root then
					crackle(root)
				end
			end
			refresh(m)
		end
	end)
	m.Destroying:Once(function()
		watched[m] = nil
	end)
end

-- CONCUSSIVE: a quick white ring at the hit.
local function shockRing(position: Vector3)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.15, 1, 1)
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Color = Color3.new(1, 1, 1)
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.15
	ring.Parent = Workspace:FindFirstChild("Effects") or Workspace
	TweenService:Create(ring, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.15, 6, 6),
		Transparency = 1,
	}):Play()
	task.delay(0.3, function()
		ring:Destroy()
	end)
end

-- Eagle Eye: a red ring sweeps out from the player to the mark radius, low on the floor.
local function eaglePing(position: Vector3, radius: number)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.12, 2, 2)
	ring.CFrame = CFrame.new(position.X, position.Y - 2.6, position.Z) * CFrame.Angles(0, 0, math.rad(90))
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Color = MARK_RED
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.5
	ring.Parent = Workspace:FindFirstChild("Effects") or Workspace
	TweenService:Create(ring, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.12, radius * 2, radius * 2),
		Transparency = 1,
	}):Play()
	task.delay(0.65, function()
		ring:Destroy()
	end)
end

function StatusFx.init()
	local folder = Workspace:WaitForChild("Enemies", 30)
	if folder then
		for _, m in folder:GetChildren() do
			watch(m)
		end
		folder.ChildAdded:Connect(watch)
	end
	ClientState.Juice:Connect(function(name: string, data: any)
		if typeof(data) ~= "table" or typeof(data.position) ~= "Vector3" then
			return
		end
		if name == "ElementShock" then
			shockRing(data.position)
		elseif name == "EagleEye" then
			eaglePing(data.position, tonumber(data.radius) or 60)
		end
	end)
	-- Marks run out on their own (no attribute change at the end).
	RunService.Heartbeat:Connect(function()
		local now = ClientState.serverNow()
		for m, untilT in marked do
			if now >= untilT or not m.Parent then
				refreshMark(m)
			end
		end
	end)
end

return StatusFx
