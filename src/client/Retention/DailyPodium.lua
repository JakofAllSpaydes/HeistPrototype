--!strict
-- Brief 10: the daily crate podium as this player sees it. The server builds the stand (Hub.lua: pedestal, trim,
-- spot, plaque, E prompt) and publishes the state on the player (DailyCrate.lua: attributes DailyCrate / DailyCrateTier
-- / DailyCrateFirst); every client draws its own crate on it, so each player sees their own state:
--   locked   lid shut, a chain across the front, dim spot and trim, plaque PLAY A MATCH TO UNLOCK, prompt PLAY A MATCH
--   ready    chain gone, lid half open, a glow from inside, a tall beacon column seen through walls, the lootbox swell
--            idling quietly within DailyCrateIdleRange, plaque DAILY CRATE · READY, prompt OPEN
--   claimed  lid shut, no chain, the spot warm, plaque BACK TOMORROW, prompt ROLL AGAIN · R$ 79
-- The crate is the store's crate model in the level band's tier colours. Coming back to the hub with the crate newly
-- unlocked, the chain snaps off with a clink and the beam lights while the party stands on the star.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Crates = require(Shared:WaitForChild("Crates"))

local Client = script.Parent.Parent
local ClientState = require(Client:WaitForChild("ClientState"))
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local Models = require(Client:WaitForChild("Store"):WaitForChild("Models"))

local DailyPodium = {}

local player = Players.LocalPlayer
local CRATE_SCALE = 1.45
local LID_OPEN_DEG = 38

local podium: Model? = nil
local crate: Models.CrateModel? = nil
local crateTier = ""
local lidRest: CFrame? = nil
local lidHinge: CFrame? = nil
local chain: Model? = nil
local beam: Part? = nil
local inner: Part? = nil
local idle: Sound? = nil
local tierLabel: TextLabel? = nil
local shown = "" -- the state last drawn while in the hub
local lidK = 0 -- 0 shut .. 1 half open (eased toward lidTarget)
local lidTarget = 0
local arrivalPending = false

local function stateNow(): string
	local s = player:GetAttribute("DailyCrate")
	return if typeof(s) == "string" then s else "locked"
end

local function tierNow(): string
	local t = player:GetAttribute("DailyCrateTier")
	return if typeof(t) == "string" then t else "basic"
end

local function tierDef(): any
	return (Config.DailyCrateTierOdds :: any)[tierNow()] or (Config.DailyCrateTierOdds :: any).basic
end

local function spotPart(): BasePart?
	local p = podium
	local s = p and p:FindFirstChild("CrateSpot")
	return if s and s:IsA("BasePart") then s else nil
end

local function prompt(): ProximityPrompt?
	local p = podium
	local a = p and p:FindFirstChild("PromptAnchor")
	local pr = a and a:FindFirstChild("DailyPrompt")
	return if pr and pr:IsA("ProximityPrompt") then pr else nil
end

local function localPart(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	mat: Enum.Material
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

------------------------------------------------------------------ Building
-- The chain: a row of links across the crate's front at the lid line, wrapping round the sides, and a padlock.
local function buildChain(c: Models.CrateModel)
	if chain then
		chain:Destroy()
	end
	local m = Instance.new("Model")
	m.Name = "Chain"
	local body = c.body
	local cf, size = body.CFrame, body.Size
	local y = size.Y / 2 - 0.12 * CRATE_SCALE
	local steel = Color3.fromRGB(150, 154, 162)
	local link = Vector3.new(0.34, 0.2, 0.08) * CRATE_SCALE
	local n = math.floor(size.X / (link.X * 0.8))
	for i = 0, n do
		local x = -size.X / 2 + i * (size.X / n)
		local p = localPart(
			m,
			"Link",
			link,
			cf * CFrame.new(x, y, -size.Z / 2 - 0.06) * CFrame.Angles(0, 0, if i % 2 == 0 then 0 else math.rad(90)),
			steel,
			Enum.Material.Metal
		)
		p.Size = if i % 2 == 0 then link else Vector3.new(link.Y, link.X, link.Z)
	end
	for _, side in { -1, 1 } do
		for i = 0, 3 do
			local z = -size.Z / 2 + (i + 0.5) * (size.Z / 4)
			localPart(
				m,
				"Link",
				Vector3.new(0.08, 0.2, 0.34) * CRATE_SCALE,
				cf * CFrame.new(side * (size.X / 2 + 0.06), y, z),
				steel,
				Enum.Material.Metal
			)
		end
	end
	local lock = localPart(
		m,
		"Padlock",
		Vector3.new(0.5, 0.55, 0.22) * CRATE_SCALE,
		cf * CFrame.new(0, y - 0.32 * CRATE_SCALE, -size.Z / 2 - 0.16),
		Color3.fromRGB(200, 160, 70),
		Enum.Material.Metal
	)
	localPart(
		m,
		"Shackle",
		Vector3.new(0.34, 0.26, 0.08) * CRATE_SCALE,
		lock.CFrame * CFrame.new(0, 0.38 * CRATE_SCALE, 0),
		steel,
		Enum.Material.Metal
	)
	m.Parent = c.model
	chain = m
end

local function buildCrate()
	local spot = spotPart()
	local p = podium
	if not spot or not p then
		return
	end
	if crate then
		crate.model:Destroy()
		crate = nil
	end
	chain, beam, inner, idle = nil, nil, nil, nil
	crateTier = tierNow()
	local c = Models.crate(Crates.dailyId(crateTier), spot.CFrame)
	c.model.Name = "DailyCrate"
	c.model:ScaleTo(CRATE_SCALE)
	c.model:PivotTo(spot.CFrame)
	for _, d in c.model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	c.model.Parent = p
	crate = c
	-- The lid hinges on its back top edge (+Z: the crate faces the room along -Z).
	local lidMain = c.lid.PrimaryPart
	if lidMain then
		lidRest = c.lid:GetPivot()
		lidHinge = lidMain.CFrame * CFrame.new(0, -lidMain.Size.Y / 2, lidMain.Size.Z / 2)
	end
	local def = tierDef()
	local trim = Color3.fromHex(def.trim)
	-- The glow from inside, seen through the open lid.
	local body = c.body
	inner = localPart(
		c.model,
		"InnerGlow",
		Vector3.new(body.Size.X * 0.82, 0.1, body.Size.Z * 0.82),
		body.CFrame * CFrame.new(0, body.Size.Y / 2 - 0.08, 0),
		trim,
		Enum.Material.Neon
	)
	-- The beacon column, seen through walls.
	local h = Config.DailyCrateBeamHeight
	local b = localPart(
		c.model,
		"Beacon",
		Vector3.new(h, 1.4, 1.4),
		CFrame.new(body.Position + Vector3.new(0, body.Size.Y / 2 + h / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		trim,
		Enum.Material.Neon
	)
	b.Shape = Enum.PartType.Cylinder
	b.Transparency = 1
	local hl = Instance.new("Highlight")
	hl.Name = "SeeThrough"
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.FillColor = trim
	hl.FillTransparency = 1
	hl.OutlineTransparency = 1
	hl.Adornee = b
	hl.Parent = b
	beam = b
	-- The quiet idle swell (a looped chime, 3D at the crate: inaudible past DailyCrateIdleRange).
	local s = Instance.new("Sound")
	s.Name = "IdleSwell"
	s.SoundId = Theme.Sounds.lootChimes
	s.Looped = true
	s.Volume = 0.14
	s.RollOffMode = Enum.RollOffMode.Linear
	s.RollOffMinDistance = 6
	s.RollOffMaxDistance = Config.DailyCrateIdleRange
	s.Parent = body
	idle = s
	buildChain(c)
	lidK = 0
end

-- The plaque: a small tier word over the main line (both local; the server's label is resized under it).
local function plaqueLabels(): (TextLabel?, TextLabel?)
	local p = podium
	local plaque = p and p:FindFirstChild("Plaque")
	local gui = plaque and plaque:FindFirstChild("Label")
	local main = gui and gui:FindFirstChild("PlaqueText")
	if not gui or not main or not main:IsA("TextLabel") then
		return nil, nil
	end
	if not tierLabel or tierLabel.Parent ~= gui then
		main.Size = UDim2.fromScale(1, 0.6)
		main.Position = UDim2.fromScale(0, 0.38)
		local t = Instance.new("TextLabel")
		t.Name = "Tier"
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, 0.34)
		t.Position = UDim2.fromScale(0, 0.04)
		t.FontFace = Theme.Fonts.display
		t.TextScaled = true
		t.Parent = gui
		tierLabel = t
	end
	return tierLabel, main
end

------------------------------------------------------------------ States
local function snapChain()
	local m = chain
	chain = nil
	if not m then
		return
	end
	UI.sound(Theme.Sounds.snip, 1.1, 0.5)
	task.delay(0.08, function()
		UI.sound(Theme.Sounds.click, 0.8, 0.5)
	end)
	local origin = m:GetPivot().Position
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = true
			local out = (d.Position - origin) * Vector3.new(1, 0, 1)
			local dir = if out.Magnitude > 0.01 then out.Unit else Vector3.new(0, 0, -1)
			d.AssemblyLinearVelocity = dir * (8 + math.random() * 8) + Vector3.new(0, 10 + math.random() * 8, 0)
			d.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 20
		end
	end
	task.delay(1.6, function()
		m:Destroy()
	end)
end

local function paint(state: string, arriving: boolean)
	local c = crate
	if not c then
		return
	end
	local def = tierDef()
	local trim = Color3.fromHex(def.trim)
	local p = podium
	-- Chain: only while locked (snapped off when it unlocks in front of you).
	if state == "locked" or state == "off" then
		if not chain then
			buildChain(c)
		end
	elseif chain then
		if arriving then
			snapChain()
		else
			chain:Destroy()
			chain = nil
		end
	end
	lidTarget = if state == "ready" then 1 else 0
	-- Spot and trim.
	local lamp = p and p:FindFirstChild("Spot")
	local light = lamp and lamp:FindFirstChildOfClass("SpotLight")
	if light then
		light.Brightness = if state == "ready" then 3 elseif state == "claimed" then 1.4 else 0.35
		light.Color = if state == "ready" then trim:Lerp(Color3.new(1, 1, 1), 0.5) else Color3.fromRGB(255, 226, 170)
	end
	if p then
		for _, d in p:GetChildren() do
			if d.Name == "Trim" and d:IsA("BasePart") then
				d.Transparency = if state == "ready" then 0 elseif state == "claimed" then 0.35 else 0.75
				d.Color = if state == "ready" then trim else Theme.Colors.gold
			end
		end
	end
	-- Plaque and prompt.
	local tl, main = plaqueLabels()
	if tl and main then
		tl.Text = string.upper(def.name) .. " DAILY CRATE"
		tl.TextColor3 = trim
		main.Text = if state == "ready"
			then "DAILY CRATE · READY"
			elseif state == "claimed" then "BACK TOMORROW"
			elseif state == "off" then ""
			else "PLAY A MATCH TO UNLOCK"
		main.TextColor3 = if state == "ready"
			then Theme.Colors.white
			elseif state == "claimed" then Theme.Colors.textDim
			else Theme.Colors.gold
	end
	local pr = prompt()
	if pr then
		pr.ObjectText = string.upper(def.name) .. " DAILY CRATE"
		pr.Enabled = state ~= "off" and (state ~= "claimed" or Config.DailyCrateRerollEnabled)
		pr.ActionText = if state == "ready"
			then "OPEN"
			elseif state == "claimed" then string.format("ROLL AGAIN · R$ %d", Config.DailyCrateRerollPrice)
			else "PLAY A MATCH"
	end
	if state ~= "ready" then
		c.setGlow(trim, 0)
	end
	if arriving and state == "ready" then
		task.delay(0.35, function()
			UI.sound(Theme.Sounds.lootRise, 1, 0.35)
		end)
	end
end

local function refresh()
	if not podium then
		return
	end
	if not crate or crateTier ~= tierNow() then
		buildCrate()
		shown = ""
	end
	if not ClientState.inHub() then
		return -- drawn on the way back in (so a newly unlocked crate snaps its chain in front of the party)
	end
	local s = stateNow()
	if s == shown then
		return
	end
	local arriving = shown == "locked" and s == "ready"
	if arriving then
		-- Let the party land on the star first.
		if not arrivalPending then
			arrivalPending = true
			task.delay(1.2, function()
				arrivalPending = false
				if stateNow() == "ready" and shown == "locked" then
					shown = "ready"
					paint("ready", true)
				else
					refresh()
				end
			end)
		end
		return
	end
	shown = s
	paint(s, false)
end

function DailyPodium.init()
	task.spawn(function()
		local hub = Workspace:WaitForChild("Hub", 60)
		local p = hub and hub:WaitForChild("DailyPodium", 60)
		if not p or not p:IsA("Model") then
			return
		end
		podium = p
		p:WaitForChild("CrateSpot", 10)
		p:WaitForChild("Plaque", 10)
		refresh()
		player:GetAttributeChangedSignal("DailyCrate"):Connect(refresh)
		player:GetAttributeChangedSignal("DailyCrateTier"):Connect(refresh)
		ClientState.Changed:Connect(refresh)
		local t0 = os.clock()
		RunService.Heartbeat:Connect(function(dt: number)
			local c = crate
			if not c then
				return
			end
			local ready = stateNow() == "ready" and shown == "ready"
			-- The lid eases toward its pose.
			local before = lidK
			lidK += math.clamp(lidTarget - lidK, -dt * 2.5, dt * 2.5)
			if lidK ~= before and lidRest and lidHinge then
				local hinge = lidHinge :: CFrame
				local k = 1 - (1 - lidK) ^ 2
				c.lid:PivotTo(
					hinge * CFrame.Angles(math.rad(LID_OPEN_DEG * k), 0, 0) * hinge:Inverse() * (lidRest :: CFrame)
				)
			end
			local def = tierDef()
			local trim = Color3.fromHex(def.trim)
			local t = os.clock() - t0
			local swell = (math.sin(t * 1.6) + 1) / 2
			if ready then
				c.setGlow(trim, 0.55 + swell * 0.45)
			end
			local inn = inner
			if inn then
				inn.Transparency = if ready then 0.15 + (1 - swell) * 0.35 else 1
			end
			local b = beam
			if b then
				local target = if ready then 0.55 + (1 - swell) * 0.15 else 1
				b.Transparency += (target - b.Transparency) * math.min(1, dt * 4)
				local hl = b:FindFirstChild("SeeThrough")
				if hl and hl:IsA("Highlight") then
					hl.FillTransparency = if ready then 0.78 + (1 - swell) * 0.1 else 1
					hl.Enabled = ready
				end
			end
			-- The swell idles only near the crate, in the hub, while it is ready.
			local s = idle
			if s then
				local char = player.Character
				local root = char and char:FindFirstChild("HumanoidRootPart")
				local near = root ~= nil
					and root:IsA("BasePart")
					and (root.Position - c.body.Position).Magnitude <= Config.DailyCrateIdleRange
				local want = ready and near and ClientState.inHub()
				if want and not s.IsPlaying then
					s:Play()
				elseif not want and s.IsPlaying then
					s:Stop()
				end
			end
		end)
	end)
end

return DailyPodium
