--!strict
-- Bag pickup feedback (round 18). Bags have no button: standing near one fills it (server Bags.lua) and this
-- draws it with no text. Over each bag a ring of ticks lights up clockwise in the bag's color while a core dot
-- grows in the middle; the bag glows (Highlight) and slides toward whoever is filling it, lifting a little. On
-- BagCollected the ring pops and the bag shoots into the collector while the server shrinks it; your own pickups
-- tick higher with each bag of a streak. Reads the bag model's Progress / By / Kind attributes.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))

type Ring = {
	model: Model,
	color: Color3,
	base: Vector3, -- the bag's spot on the floor
	gui: BillboardGui,
	holder: Frame,
	segs: { Frame },
	core: Frame,
	glow: Highlight?,
	parts: { [BasePart]: CFrame }, -- each moving part's server CFrame (the beacon column stays put)
	shown: number, -- displayed fill, eased toward the Progress attribute
	lit: number, -- ticks lit
	pull: Vector3, -- the bag's current offset toward its filler
	done: boolean, -- collected: the server is shrinking it
	suckTo: Player?, -- ...and it shoots into this player
	suckT: number,
}

local BagChannel = {}

local localPlayer = Players.LocalPlayer
local effects = Workspace:WaitForChild("Effects")
local rings: { [Model]: Ring } = {}
local UNLIT = Color3.fromRGB(20, 20, 26)

local function rootOfUser(userId: number): BasePart?
	if userId == 0 then
		return nil
	end
	local p = Players:GetPlayerByUserId(userId)
	local char = p and p.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function track(ring: Ring, d: Instance)
	if d:IsA("BasePart") and d.Name ~= "Beacon" then
		ring.parts[d] = d.CFrame
	end
end

local function build(model: Model)
	local body = model:WaitForChild("Body", 5) :: BasePart?
	if not body or not model.Parent or rings[model] then
		return
	end
	local gold = model:GetAttribute("Kind") == "gold"
	local color = if gold then Theme.Colors.gold else Theme.Colors.cash
	-- Sized in studs, so it shrinks with distance and never covers the screen; AlwaysOnTop so walls and the
	-- bag itself never hide it.
	local gui = Instance.new("BillboardGui")
	gui.Name = "FillRing"
	gui.Adornee = body
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromScale(2.8, 2.8)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0)
	gui.MaxDistance = Config.BagRingMaxDistance
	gui.LightInfluence = 0
	gui.Enabled = false
	gui.Parent = body
	local holder = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0.8),
		Parent = gui,
	})
	local segs = {}
	local n = math.max(4, Config.BagRingSegments)
	for i = 1, n do
		local a = (i - 0.5) / n * math.pi * 2
		local seg = UI.frame({
			BackgroundColor3 = UNLIT,
			BackgroundTransparency = 0.35,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5 + math.sin(a) * 0.4, 0.5 - math.cos(a) * 0.4),
			Size = UDim2.fromScale(0.085, 0.2),
			Rotation = math.deg(a),
			Parent = holder,
		})
		UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = seg })
		table.insert(segs, seg)
	end
	local core = UI.frame({
		BackgroundColor3 = color,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0, 0),
		Parent = holder,
	})
	UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = core })
	UI.stroke(core, Theme.Colors.black, 1.5, 0.4)
	local ring: Ring = {
		model = model,
		color = color,
		base = body.Position,
		gui = gui,
		holder = holder,
		segs = segs,
		core = core,
		glow = nil,
		parts = {},
		shown = 0,
		lit = 0,
		pull = Vector3.zero,
		done = false,
		suckTo = nil,
		suckT = 0,
	}
	for _, d in model:GetChildren() do
		track(ring, d)
	end
	model.ChildAdded:Connect(function(d)
		track(ring, d)
	end)
	rings[model] = ring
end

local function setGlow(ring: Ring, on: boolean)
	if on and not ring.glow then
		local h = Instance.new("Highlight")
		h.Adornee = ring.model
		h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		h.FillColor = ring.color
		h.OutlineColor = ring.color
		h.FillTransparency = 1
		h.OutlineTransparency = 0.2
		h.Parent = ring.model
		ring.glow = h
	elseif not on and ring.glow then
		ring.glow:Destroy()
		ring.glow = nil
	end
end

-- Moves the bag's parts to their server spot plus `offset` (client-side only; the server never moves a bag).
local function place(ring: Ring, offset: Vector3)
	for p, cf in ring.parts do
		if p.Parent then
			p.CFrame = cf + offset
		end
	end
end

local function update(ring: Ring, dt: number)
	local model = ring.model
	local target = tonumber(model:GetAttribute("Progress")) or 0
	local by = tonumber(model:GetAttribute("By")) or 0
	if ring.done then
		-- Collected: ease into the collector's chest while the server shrinks the parts.
		if not ring.suckTo then
			return
		end
		ring.suckT += dt
		local t = math.clamp(ring.suckT / math.max(Config.BagSuckSec, 0.01), 0, 1)
		local char = (ring.suckTo :: Player).Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local to = root.Position - ring.base
			place(ring, ring.pull:Lerp(to, t * t))
		end
		return
	end
	-- Ease toward the server's fill; a drop (drain, or a new filler) eases too, a little slower.
	local rate = if target > ring.shown then 24 else 10
	ring.shown += (target - ring.shown) * (1 - math.exp(-dt * rate))
	local shown = ring.shown
	local active = shown > 0.01 or by ~= 0
	ring.gui.Enabled = active
	setGlow(ring, by ~= 0)
	if ring.glow then
		ring.glow.FillTransparency = 1 - 0.55 * shown
	end
	if active then
		local n = #ring.segs
		local lit = math.clamp(math.floor(shown * n + 0.5), 0, n)
		if lit ~= ring.lit then
			for i, seg in ring.segs do
				local on = i <= lit
				seg.BackgroundColor3 = if on then ring.color else UNLIT
				seg.BackgroundTransparency = if on then 0 else 0.35
			end
			if lit > ring.lit then
				UI.punch(ring.segs[lit], 1.6, 0.18)
			end
			ring.lit = lit
		end
		-- Grows with the fill; a drained bag reads dimmer.
		local s = 0.75 + 0.35 * shown
		ring.holder.Size = UDim2.fromScale(s, s)
		ring.core.Size = UDim2.fromScale(0.44 * shown, 0.44 * shown)
		ring.core.BackgroundTransparency = if by ~= 0 then 0 else 0.4
	end
	-- Slide toward the filler as it fills (ease-in, so it tugs at the end), back home when nobody fills it.
	local want = Vector3.zero
	local root = rootOfUser(by)
	if root then
		local flat = Vector3.new(root.Position.X - ring.base.X, 0, root.Position.Z - ring.base.Z)
		if flat.Magnitude > 0.5 then
			local reach = math.min(Config.BagPullStuds, flat.Magnitude - 1.5)
			want = flat.Unit * math.max(0, reach) * shown * shown + Vector3.new(0, 0.7 * shown, 0)
		end
	end
	local was = ring.pull
	ring.pull = was:Lerp(want, 1 - math.exp(-dt * 14))
	if (ring.pull - was).Magnitude > 0.001 then
		place(ring, ring.pull)
	end
end

local function collected(data: any)
	local model = effects:FindFirstChild("Bag_" .. tostring(data.id))
	local ring = model and rings[model :: Model]
	local userId = tonumber(data.userId) or 0
	if ring then
		-- Full ring, a pop, then it fades with the bag.
		for _, seg in ring.segs do
			seg.BackgroundColor3 = ring.color
			seg.BackgroundTransparency = 0
		end
		ring.core.Size = UDim2.fromScale(0.44, 0.44)
		ring.gui.Enabled = true
		UI.punch(ring.holder, 1.5, 0.2)
		for _, d in ring.holder:GetDescendants() do
			if d:IsA("Frame") then
				UI.tween(d, { BackgroundTransparency = 1 }, 0.22, nil, nil, 0.08)
			end
		end
		setGlow(ring, true)
		if ring.glow then
			ring.glow.FillTransparency = 0.2
			UI.tween(ring.glow, { FillTransparency = 1, OutlineTransparency = 1 }, 0.22)
		end
		ring.done = true
		ring.suckTo = Players:GetPlayerByUserId(userId)
		ring.suckT = 0
	end
	if userId == localPlayer.UserId then
		-- Each bag of a streak ticks a step higher.
		local streak = math.min(tonumber(data.streak) or 0, 8)
		UI.sound(Theme.Sounds.hit, 1 + 0.12 * streak, 0.3)
	end
end

local function watch(child: Instance)
	if child:IsA("Model") and string.match(child.Name, "^Bag_%d+$") then
		task.spawn(build, child)
	end
end

function BagChannel.init()
	for _, child in effects:GetChildren() do
		watch(child)
	end
	effects.ChildAdded:Connect(watch)
	effects.ChildRemoved:Connect(function(child)
		if child:IsA("Model") then
			rings[child] = nil
		end
	end)
	ClientState.Juice:Connect(function(name: string, data: any)
		if name == "BagCollected" and data then
			collected(data)
		end
	end)
	RunService.Heartbeat:Connect(function(dt)
		for model, ring in rings do
			if model.Parent then
				update(ring, dt)
			else
				rings[model] = nil
			end
		end
	end)
end

return BagChannel
