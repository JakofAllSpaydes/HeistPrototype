--!strict
-- The hub (brief 8: the builder's warehouse, Workspace.Hub, read by HubMap): the star where players spawn, the
-- three booths (OPEN opens the customization scene on a tab; each booth's rig is a mannequin the client dresses
-- in your loadout), MARLOW's board, the van in its garage (the departure beat on run start), the range door, and
-- the minigame props and tier pad standing in the range. Owns the hub's housekeeping (spawns, resets) and the
-- nameplate data (level, class, best wave, VIP) each character shows while they stand in the hub.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Fonts = require(Shared.Fonts)
local Ground = require(Shared.Ground)
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Maps = require(Shared.Maps)
local Room = require(script.Parent.Run.Room)
local World = require(script.Parent.Run.World) -- the hub slot's World (the session-wide minigame tier)
local Runs = require(script.Parent.Runs)
local HubMap = require(script.Parent.HubMap)
local Log = require(script.Parent.Log)
local Profiles = require(script.Parent.Profiles)
local PlayerState = require(script.Parent.PlayerState)

local Hub = {}

local GOLD = Color3.fromHex("E8B64C")
local TEXT = Color3.fromHex("F2E6C8")
local GREY = Color3.fromHex("9BA0A8")
local DARK = Color3.fromHex("1A1A20")
local BLUE = Color3.fromHex("4D9FE8")

-- Text on one face of a Part. Floor labels are rotated so the text reads from where you stand.
local function surfaceLabel(part: BasePart, face: Enum.NormalId, text: string, color: Color3, size: number): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Label"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.FontFace = Fonts.display
	label.Text = string.upper(text)
	label.TextColor3 = color
	label.TextScaled = true
	label.Parent = gui
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = size
	constraint.Parent = label
	return label
end

local function paintTier()
	for t, pad in Room.tierPads do
		local on = t == World.minigameTier
		pad.Color = if on then GOLD else Color3.fromRGB(77, 77, 87)
		pad.Material = if on then Enum.Material.Neon else Enum.Material.Metal
		local label = pad:FindFirstChild("Label")
		local text = label and label:FindFirstChildOfClass("TextLabel")
		if text then
			text.TextColor3 = if on then DARK else TEXT
		end
	end
end

function Hub.setTier(tier: number, who: string?)
	local t = math.clamp(math.floor(tier), 1, 3)
	if t == World.minigameTier then
		return
	end
	World.minigameTier = t
	paintTier()
	PlayerState.markAllDirty()
	Remotes.Juice:FireAllClients("Toast", { text = string.format("MINIGAME TIER %d", t) })
	Log.event("Minigame", "tier set to %d by %s", t, who or "debug")
end

------------------------------------------------------------------ Hub nameplate
-- The nameplate over each character in the hub (client/Nameplates.lua draws it: level badge, name, VIP, class,
-- best top wave). The server only publishes the numbers as Player attributes; Plate = false hides it (runs).
-- Round 21: the Roblox player list (Tab in the hub) shows LEVEL and BEST WAVE from these leaderstats.
local function refreshLeaderstats(player: Player, profile: any)
	local folder = player:FindFirstChild("leaderstats")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "leaderstats"
		folder.Parent = player
	end
	local function stat(name: string, value: number)
		local v = folder:FindFirstChild(name) :: IntValue?
		if not v then
			local nv = Instance.new("IntValue")
			nv.Name = name
			nv.Parent = folder
			v = nv
		end
		(v :: IntValue).Value = value
	end
	stat("Level", if profile then profile.level else 1)
	stat("Best Wave", if profile then (Profiles.bestTopWave(profile)) else 0)
end

function Hub.refreshTag(player: Player)
	local state = PlayerState.get(player)
	refreshLeaderstats(player, state.profile)
	-- In a run, or (brief 8) in the training range: no plate.
	if Runs.inRunCycle(player) or state.inRange then
		player:SetAttribute("Plate", false)
		return
	end
	local profile = state.profile
	-- Brief 7: the best top wave across maps, with that map's short name (★ WAVE 14 BANK).
	local top, topMap = 0, nil
	if profile then
		top, topMap = Profiles.bestTopWave(profile)
	end
	player:SetAttribute("PlateLevel", if profile then profile.level else 1)
	player:SetAttribute("PlateTop", top)
	player:SetAttribute("PlateMap", if topMap and top > 0 then Maps.get(topMap).short else "")
	player:SetAttribute("PlateClass", PlayerState.classOf(state))
	player:SetAttribute("PlateVip", profile ~= nil and profile.vip.active == true)
	player:SetAttribute("Plate", true)
end

function Hub.refreshAllTags()
	for _, p in Players:GetPlayers() do
		Hub.refreshTag(p)
	end
end

------------------------------------------------------------------ Dressing
-- OPEN at a customization station: the scene on that tab (not from inside a run, not while downed).
local function stationPrompt(part: BasePart, tab: string, distance: number)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Prompt"
	prompt.ActionText = "OPEN"
	prompt.ObjectText = tab
	prompt.KeyboardKeyCode = Enum.KeyCode[Config.InteractKey]
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = distance
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	prompt.Triggered:Connect(function(player)
		local state = PlayerState.get(player)
		if Runs.inRunCycle(player) then
			return
		end
		if not PlayerState.isStanding(state) then
			return
		end
		Remotes.Juice:FireClient(player, "OpenMeta", { tab = tab })
	end)
end

-- Labels on the props, the tier pad and the stations; prompts on the pad buttons and the stations.
local function decorate()
	for name, prop in Room.props do
		local caps = string.upper(name)
		surfaceLabel(prop.label, Enum.NormalId.Top, caps, GOLD, 60)
		surfaceLabel(prop.panel, Enum.NormalId.Left, caps, TEXT, 48)
	end
	local base = Room.tierPadBase
	if base then
		surfaceLabel(base, Enum.NormalId.Top, "TIER", GREY, 40)
	end
	for t, pad in Room.tierPads do
		surfaceLabel(pad, Enum.NormalId.Top, tostring(t), TEXT, 60)
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "Prompt"
		prompt.ActionText = "TIER " .. t
		prompt.ObjectText = "MINIGAMES"
		prompt.KeyboardKeyCode = Enum.KeyCode[Config.InteractKey]
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 7
		prompt.RequiresLineOfSight = false
		prompt.Parent = pad
		prompt.Triggered:Connect(function(player)
			Hub.setTier(t, player.Name)
		end)
	end
	paintTier()

	for _, station in Room.stations do
		surfaceLabel(station.label, Enum.NormalId.Top, station.tab, GOLD, 60)
		surfaceLabel(station.panel, Enum.NormalId.Right, station.tab, TEXT, 48)
		stationPrompt(station.panel, station.tab, 9)
	end
	-- Brief 8: the warehouse's booths open by walking onto their half-circle (BoothWalkIn); the F prompt is only the
	-- fallback when that is switched off.
	local view = HubMap.view
	if view and not Config.BoothWalkIn then
		for _, station in view.stations do
			stationPrompt(station.part, station.tab, Config.BoothPromptDistance)
		end
	end
end

------------------------------------------------------------------ Booth walk-ins (brief 8)
-- Walk onto a booth's orange half-circle (its Station node) and the customization scene opens on that tab
-- (BoothWalkIn); it opens again only after you have stepped off. No prompt (BoothWalkIn false brings OPEN back).
local onBooth: { [Player]: string } = {}

local function boothAt(station: HubMap.Station, position: Vector3): boolean
	local p = station.part
	local o = p.CFrame:PointToObjectSpace(position)
	return math.abs(o.X) <= p.Size.X / 2
		and math.abs(o.Z) <= p.Size.Z / 2
		and o.Y >= -p.Size.Y / 2 - 1
		and o.Y <= p.Size.Y / 2 + 2
end

local function startBoothWalkIns()
	local view = HubMap.view
	if not view or #view.stations == 0 or not Config.BoothWalkIn then
		return
	end
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.1 then
			return
		end
		acc = 0
		for _, player in Players:GetPlayers() do
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local state = PlayerState.get(player)
			if not root or Runs.inRunCycle(player) or not PlayerState.isStanding(state) then
				onBooth[player] = nil
				continue
			end
			local here: string? = nil
			for _, station in view.stations do
				if boothAt(station, root.Position) then
					here = station.tab
					break
				end
			end
			if here and onBooth[player] ~= here then
				Remotes.Juice:FireClient(player, "OpenMeta", { tab = here })
				Log.event("Hub", "%s walked into the %s booth", player.Name, here)
			end
			onBooth[player] = here
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		onBooth[player] = nil
	end)
end

------------------------------------------------------------------ MARLOW's job board (brief 6)
-- Brief 8: the warehouse's own bulletin board on the north wall (the Board node). The client finds the model named
-- JobBoard: `Cork` is where the camera pushes in (its back faces the room), `Beacon` the strip it pulses until the
-- day's board is seen. F (OPEN) at the board opens the JOBS screen.
local function boardPrompt(parent: BasePart, distance: number)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Prompt"
	prompt.ActionText = "OPEN"
	prompt.ObjectText = "MARLOW'S JOBS"
	prompt.KeyboardKeyCode = Enum.KeyCode[Config.InteractKey]
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = distance
	prompt.RequiresLineOfSight = false
	prompt.Parent = parent
	prompt.Triggered:Connect(function(player)
		if Runs.inRunCycle(player) then
			return
		end
		Remotes.Juice:FireClient(player, "OpenJobs", {})
	end)
end

-- Round 20r: MARLOW himself, a default R15 in a dark suit standing in front of the board (MarlowOffset studs out
-- from its face, on the floor under that point) facing the room, with an idle and a small name tag. Returns his root.
local function buildMarlow(node: BasePart): BasePart?
	if not Config.MarlowNpc then
		return nil
	end
	local desc = Instance.new("HumanoidDescription")
	local suit = Color3.fromRGB(34, 36, 44)
	desc.HeadColor = Color3.fromRGB(196, 150, 116)
	desc.LeftArmColor = suit
	desc.RightArmColor = suit
	desc.TorsoColor = suit
	desc.LeftLegColor = Color3.fromRGB(24, 24, 30)
	desc.RightLegColor = Color3.fromRGB(24, 24, 30)
	local ok, made = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not made then
		Log.event("Hub", "no MARLOW rig (%s): the board's prompt stays on the board", tostring(made))
		return nil
	end
	local npc = made :: Model
	npc.Name = "Marlow"
	local hum = npc:FindFirstChildOfClass("Humanoid")
	local hrp = npc:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp or not hrp:IsA("BasePart") then
		npc:Destroy()
		return nil
	end
	for _, d in npc:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hrp.Anchored = true
	local front = node.CFrame.LookVector * Vector3.new(1, 0, 1)
	front = if front.Magnitude > 0.1 then front.Unit else Vector3.new(0, 0, 1)
	local spot = node.Position + front * Config.MarlowOffset
	local floor = Ground.y(Vector3.new(spot.X, node.Position.Y, spot.Z), spot.Y - 8, 2, 20)
	local at = Vector3.new(spot.X, floor + hum.HipHeight + hrp.Size.Y / 2, spot.Z)
	npc:PivotTo(CFrame.lookAt(at, at + front))
	npc.Parent = HubMap.model or workspace
	-- Round 25: his name tag is the booth keepers' one (client/BoothMannequins.lua: fades in close, hides behind
	-- menus), tagged GHSKeeper like them.
	npc:SetAttribute("BoothNpc", "MARLOW")
	npc:SetAttribute("BoothRole", Config.MarlowRole)
	CollectionService:AddTag(npc, "GHSKeeper")
	-- The idle (an Animator on the server replicates to every client).
	task.spawn(function()
		local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
		local anim = Instance.new("Animation")
		anim.AnimationId = Config.MarlowIdleAnimationId
		local okLoad, track = pcall(function()
			return (animator :: Animator):LoadAnimation(anim)
		end)
		if okLoad and track then
			track.Looped = true
			track:Play()
		end
	end)
	return hrp
end

local function buildHubBoard(node: BasePart)
	local m = Instance.new("Model")
	m.Name = "JobBoard"
	local function part(name: string, size: Vector3, cf: CFrame): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Size = size
		p.CFrame = cf
		p.Parent = m
		return p
	end
	-- The node faces the room; the client reads the Cork's back as the board's front.
	local front = node.CFrame.LookVector
	local cork = part("Cork", node.Size, CFrame.lookAt(node.Position, node.Position - front))
	cork.Transparency = 1
	local top = node.Position + Vector3.new(0, node.Size.Y / 2 + 0.35, 0) + front * 0.2
	local beacon = part("Beacon", Vector3.new(node.Size.X, 0.18, 0.2), CFrame.lookAt(top, top + front))
	beacon.Color = GOLD
	beacon.Material = Enum.Material.Neon
	local light = Instance.new("PointLight")
	light.Name = "BeaconLight"
	light.Color = GOLD
	light.Range = 14
	light.Brightness = 1.5
	light.Parent = beacon
	-- The prompt sits low on the board's face so it reaches the floor in front of it.
	local low = node.Position - Vector3.new(0, node.Size.Y / 2, 0) + front * 1
	local anchor = part("PromptAnchor", Vector3.new(1, 1, 1), CFrame.new(low))
	anchor.Transparency = 1
	m.Parent = HubMap.model or workspace
	Hub.jobBoard = m
	-- MARLOW stands in front of his board; the OPEN prompt is on him (on the board if he cannot be made).
	local marlow = buildMarlow(node)
	boardPrompt(marlow or anchor, Config.BoardPromptDistance)
end

-- MARLOW's board is the warehouse's bulletin board (the Board node); without one there is no board.
local function buildJobBoard()
	local node = HubMap.view and HubMap.view.board
	if node then
		buildHubBoard(node)
	else
		Log.event("Map", "hub: no Board node, MARLOW's board is off (the HUD's JOBS still opens it)")
	end
end

------------------------------------------------------------------ The daily crate podium (brief 10)
-- Built from the DailyCrate node (the pedestal's volume, facing the star; Round 27b: where the drums stood): a low
-- pedestal with a trimmed top, a spot above it, a slanted plaque in front and the E prompt. Everything that changes
-- per player (the crate model and its lid, the chain, the glow and beacon, the plaque's words, the prompt's words) is
-- drawn by each client for its own state (client/Retention/DailyPodium.lua); the server only builds the stand and
-- routes the prompt to DailyCrate.lua (Hub.onDailyPrompt, installed there so this module never requires it).
Hub.dailyPodium = nil :: Model?
Hub.onDailyPrompt = nil :: ((Player) -> ())?

local function buildDailyPodium()
	local node = HubMap.view and HubMap.view.dailyCrate
	if not node then
		return
	end
	local k = math.max(0.25, Config.DailyCratePodiumScale)
	local size = node.size * k
	local look = node.cframe.LookVector * Vector3.new(1, 0, 1)
	look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, 1)
	-- The pedestal stands on the node's floor, scaled about its base.
	local floor = node.cframe.Position - Vector3.new(0, node.size.Y / 2, 0)
	local base = CFrame.lookAt(floor, floor + look)
	local m = Instance.new("Model")
	m.Name = "DailyPodium"
	local function part(name: string, sz: Vector3, cf: CFrame, color: Color3, material: Enum.Material): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Size = sz
		p.CFrame = cf
		p.Color = color
		p.Material = material
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = m
		return p
	end
	local pedestal =
		part("Pedestal", size, base * CFrame.new(0, size.Y / 2, 0), Color3.fromRGB(30, 32, 38), Enum.Material.Metal)
	pedestal.CanCollide = true
	pedestal.CanQuery = true
	pedestal.CastShadow = true
	local topY = size.Y
	part(
		"Top",
		Vector3.new(size.X - 0.3 * k, 0.12 * k, size.Z - 0.3 * k),
		base * CFrame.new(0, topY + 0.06 * k, 0),
		Color3.fromRGB(52, 55, 62),
		Enum.Material.DiamondPlate
	)
	-- A thin gold trim around the top edge (dim neon: the client brightens it when the crate is ready).
	for _, e in
		{
			{ Vector3.new(size.X, 0.08 * k, 0.08 * k), CFrame.new(0, topY - 0.06 * k, -size.Z / 2) },
			{ Vector3.new(size.X, 0.08 * k, 0.08 * k), CFrame.new(0, topY - 0.06 * k, size.Z / 2) },
			{ Vector3.new(0.08 * k, 0.08 * k, size.Z), CFrame.new(-size.X / 2, topY - 0.06 * k, 0) },
			{ Vector3.new(0.08 * k, 0.08 * k, size.Z), CFrame.new(size.X / 2, topY - 0.06 * k, 0) },
		}
	do
		local t = part("Trim", e[1], base * e[2], GOLD, Enum.Material.Neon)
		t.Transparency = 0.35
	end
	-- Where the client sets its crate down (the top's centre, facing the room).
	local spot =
		part("CrateSpot", Vector3.new(1, 1, 1), base * CFrame.new(0, topY + 0.12 * k, 0), GOLD, Enum.Material.Plastic)
	spot.Transparency = 1
	-- The spot: a downward cone from high above. Round 27f: the emitter is invisible (a housing floating in mid-air
	-- read as a stray brick; nothing in the hall to hang it from).
	local lamp = part(
		"Spot",
		Vector3.new(1.2, 0.5, 1.2) * k,
		base * CFrame.new(0, topY + 11 * k, 0),
		Color3.fromRGB(24, 24, 28),
		Enum.Material.Metal
	)
	lamp.Transparency = 1
	local light = Instance.new("SpotLight")
	light.Name = "SpotLight"
	light.Face = Enum.NormalId.Bottom
	light.Angle = 45
	light.Range = 16 * k
	light.Brightness = 1.2
	light.Color = Color3.fromRGB(255, 226, 170)
	light.Parent = lamp
	-- The plaque leans out of the pedestal's front face; its words are the client's.
	local plaqueCf = base * CFrame.new(0, topY * 0.55, -size.Z / 2 - 0.12 * k) * CFrame.Angles(math.rad(18), 0, 0) -- front (-Z) to the room, tilted up
	local plaque = part(
		"Plaque",
		Vector3.new(math.min(size.X - 0.6 * k, 4.4 * k), 0.9 * k, 0.12 * k),
		plaqueCf,
		Color3.fromRGB(16, 16, 20),
		Enum.Material.SmoothPlastic
	)
	local label = surfaceLabel(plaque, Enum.NormalId.Front, "DAILY CRATE", GOLD, 64)
	label.Name = "PlaqueText"
	-- The prompt hangs in front of the pedestal, at hand height.
	local anchor = part(
		"PromptAnchor",
		Vector3.new(1, 1, 1),
		base * CFrame.new(0, topY + 1.2 * k, -size.Z / 2 - 0.6 * k),
		GOLD,
		Enum.Material.Plastic
	)
	anchor.Transparency = 1
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DailyPrompt"
	prompt.ActionText = "OPEN"
	prompt.ObjectText = "DAILY CRATE"
	prompt.KeyboardKeyCode = Enum.KeyCode[Config.InteractKey]
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = Config.DailyCratePromptDistance
	prompt.RequiresLineOfSight = false
	prompt.Enabled = Config.DailyCrateEnabled
	prompt.Parent = anchor
	prompt.Triggered:Connect(function(player)
		if Runs.inRunCycle(player) then
			return
		end
		local f = Hub.onDailyPrompt
		if f then
			f(player)
		end
	end)
	m.Parent = HubMap.model or Workspace
	Hub.dailyPodium = m
	Log.event(
		"Hub",
		"daily crate podium at (%.1f, %.1f, %.1f) scale %.2f",
		floor.X,
		floor.Y,
		floor.Z - Config.HubOrigin.Position.Z,
		k
	)
end

------------------------------------------------------------------ Roll-up doors (brief 8)
-- The warehouse's two openings (the garage, the range) have no door panel in the asset: each gets a corrugated
-- shutter filling its node. Down fills the opening; up rolls it into a short drum under the lintel. Everyone sees
-- and hears it (the shutter clip at the door).
local ROLLED = 0.9 -- studs of shutter left showing when it is up

function Hub.setShutter(shutter: BasePart?, open: boolean, instant: boolean?)
	if not shutter then
		return
	end
	local closed = shutter:GetAttribute("Closed")
	local height = shutter:GetAttribute("Height")
	if typeof(closed) ~= "CFrame" or typeof(height) ~= "number" then
		return
	end
	if shutter:GetAttribute("Open") == open and not instant then
		return
	end
	shutter:SetAttribute("Open", open)
	local y = if open then ROLLED else height
	local size = Vector3.new(shutter.Size.X, y, shutter.Size.Z)
	local cf = closed * CFrame.new(0, (height - y) / 2, 0)
	shutter.CanCollide = not open
	if instant then
		shutter.Size = size
		shutter.CFrame = cf
		return
	end
	local sec = shutter:GetAttribute("RollSec")
	TweenService:Create(
		shutter,
		TweenInfo.new(if typeof(sec) == "number" then sec else Config.HubDoorRollSec, Enum.EasingStyle.Quad),
		{ Size = size, CFrame = cf }
	):Play()
	Remotes.Juice:FireAllClients("HubDoor", { position = closed.Position, open = open })
end

local function buildShutter(name: string, door: HubMap.Door?, open: boolean): BasePart?
	if not door then
		return nil
	end
	local node = door.part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CastShadow = true
	p.Material = Enum.Material.DiamondPlate
	p.Color = Color3.fromRGB(92, 96, 104)
	p.Size = Vector3.new(node.Size.X, node.Size.Y, 0.4)
	p.CFrame = node.CFrame
	p:SetAttribute("Closed", node.CFrame)
	p:SetAttribute("Height", node.Size.Y)
	p:SetAttribute("RollSec", door.openSec)
	p.Parent = HubMap.model or workspace
	Hub.setShutter(p, open, true)
	return p
end

Hub.garageShutter = nil :: BasePart?
Hub.rangeShutter = nil :: BasePart?

------------------------------------------------------------------ The test props and the tier pad (brief 8: in the range)
-- The seven minigame props stand on their PropSpot nodes, the tier pad on its TierPad node; they register in the
-- hub slot's Room (Room.props / Room.tierPads) so decorate() labels them and F opens them exactly as from the yard.
local function buildProps()
	local view = HubMap.view
	if not view then
		return
	end
	local panelGrey = Color3.fromRGB(66, 71, 87)
	local labelDark = Color3.fromRGB(26, 26, 31)
	local folder = Instance.new("Folder")
	folder.Name = "RangeProps"
	folder.Parent = HubMap.model or workspace
	local function part(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = material
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = folder
		return p
	end
	for _, name in Room.PropNames do
		local spot = view.propSpots[string.lower(name)]
		if not spot then
			continue
		end
		local f = spot.LookVector
		-- The panel's Left face (decorate's label) faces the room; the floor label lies in front, reading from there.
		local panel = part(
			"Prop_" .. name,
			Vector3.new(0.6, 6, 4),
			CFrame.lookAt(spot.Position + Vector3.new(0, 3, 0), spot.Position + Vector3.new(0, 3, 0) + f)
				* CFrame.Angles(0, -math.pi / 2, 0),
			panelGrey,
			Enum.Material.Metal
		)
		local at = spot.Position + f * 2.6 + Vector3.new(0, 0.1, 0)
		local label = part(
			"PropLabel_" .. name,
			Vector3.new(3.6, 0.2, 2.2),
			CFrame.lookAt(at, at - f),
			labelDark,
			Enum.Material.SmoothPlastic
		)
		label.CanCollide = false
		Room.props[name] = { panel = panel, label = label }
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "Prompt"
		prompt.ActionText = "OPEN"
		prompt.ObjectText = string.upper(name)
		prompt.KeyboardKeyCode = Enum.KeyCode[Config.InteractKey]
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 9
		prompt.RequiresLineOfSight = false
		prompt.Parent = panel
		prompt.Triggered:Connect(function(player)
			if Runs.inRunCycle(player) then
				return
			end
			-- The hub slot's minigames (the same sessions, log and tier as the yard's props).
			Runs.mod(Runs.hub, "Minigames").open(player, name)
		end)
	end
	local tier = view.tierPad
	if tier then
		local base = part("TierPad", tier.size, tier.cframe, labelDark, Enum.Material.SmoothPlastic)
		base.CanCollide = false
		Room.tierPadBase = base
		Room.tierPads = {}
		for t = 1, 3 do
			local pad = part(
				"TierPad" .. t,
				Vector3.new(2.4, 0.6, 2.4),
				tier.cframe * CFrame.new((t - 2) * 3, 0.3, 0),
				Color3.fromRGB(77, 77, 87),
				Enum.Material.Metal
			)
			pad.CanCollide = false
			Room.tierPads[t] = pad
		end
	end
end

------------------------------------------------------------------ The van and the garage (brief 8)
-- The asset's van stands in the garage all the time, nose to the roll-up door. Its pivot is normalized at load to
-- the middle of its underside facing its nose, so PivotTo(a floor point facing a way) parks it there; the run
-- slots drive copies of it (Hub.vanTemplate) as their arrival van. Run start: the party fades into it, the door
-- rolls up, it pulls out through the door and is gone (the cut to the map); the door rolls back down
-- GarageCloseSec later and the van is parked again behind it. Everyone in the hub sees it leave.
local vanParts: { [BasePart]: number } = {}
local vanHome: CFrame? = nil
local departures = 0
local vanOut = false

local function normalizeVan(van: Model)
	van.PrimaryPart = nil
	local body: BasePart? = nil
	local bottom = math.huge
	for _, d in van:GetDescendants() do
		if d:IsA("BasePart") then
			if not body or d.Size.X * d.Size.Y * d.Size.Z > body.Size.X * body.Size.Y * body.Size.Z then
				body = d
			end
			bottom = math.min(bottom, d.Position.Y - d.Size.Y / 2)
		end
	end
	if not body then
		return
	end
	local center = van:GetBoundingBox().Position
	local look = body.CFrame.LookVector * Vector3.new(1, 0, 1)
	local base = Vector3.new(center.X, bottom, center.Z)
	van.WorldPivot = CFrame.lookAt(base, base + (if look.Magnitude > 0.1 then look.Unit else Vector3.new(0, 0, -1)))
end

local function setVanShown(on: boolean)
	for p, t in vanParts do
		if p.Parent then
			p.Transparency = if on then t else 1
			p.CanCollide = on
		end
	end
end

-- A copy of the asset's van for a map's drive-in (pivot at its underside, facing its nose), unparented.
function Hub.vanTemplate(): Model?
	local van = HubMap.view and HubMap.view.vanModel
	if not van then
		return nil
	end
	local copy = van:Clone()
	for _, d in copy:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			local t = vanParts[van:FindFirstChild(d.Name, true) :: any]
			if t then
				d.Transparency = t
			end
		end
	end
	return copy
end

-- Where the party sits while it fades into the van (the van's middle, a little up).
function Hub.vanSeat(): CFrame?
	local home = vanHome
	return if home then home + Vector3.new(0, 3, 0) else nil
end

-- The departure beat for a run's party (yields HubDepartSec). Two parties leaving close together: the door stays
-- up for the second and the van is parked again for it.
function Hub.depart(players: { Player })
	local view = HubMap.view
	local van = view and view.vanModel
	local home = vanHome
	if not van or not home then
		task.wait(Config.HubDepartSec)
		return
	end
	departures += 1
	van:PivotTo(home)
	setVanShown(true)
	vanOut = true
	for _, p in players do
		Remotes.Juice:FireClient(p, "HubDepart", { van = van, sec = Config.HubDepartSec })
	end
	Hub.setShutter(Hub.garageShutter, true)
	local roll = (view and view.garage and view.garage.openSec) or Config.HubDoorRollSec
	local lead = math.min(roll * 0.6, Config.HubDepartSec * 0.4)
	task.wait(lead)
	-- Out through the door: a dust ring where it pulls away, then it is gone.
	Remotes.Juice:FireAllClients("HubVanDust", { position = home.Position })
	-- Every client drives it smoothly (VanDrive); the server parks it at the end.
	local drive = math.max(0.2, Config.HubDepartSec - lead)
	local out = home * CFrame.new(0, 0, -Config.HubVanDriveStuds)
	Remotes.Juice:FireAllClients("VanDrive", {
		van = van,
		from = home,
		to = out,
		sec = drive,
		ease = "in",
		startedAt = Workspace:GetServerTimeNow(),
	})
	task.wait(drive)
	van:PivotTo(out)
	setVanShown(false)
	Log.event("Hub", "the van left the garage with %d", #players)
	task.delay(Config.GarageCloseSec, function()
		departures -= 1
		if departures > 0 then
			return
		end
		Hub.setShutter(Hub.garageShutter, false)
		task.wait(roll)
		if departures == 0 and vanOut then
			vanOut = false
			van:PivotTo(home)
			setVanShown(true)
		end
	end)
end

-- Debug Open garage: the departure beat with nobody in the van.
function Hub.openGarage()
	task.spawn(Hub.depart, {})
end

local function prepareVan()
	local view = HubMap.view
	local van = view and view.vanModel
	local node = view and view.van
	if not van or not node then
		return
	end
	normalizeVan(van)
	for _, d in van:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			vanParts[d] = d.Transparency
		end
	end
	local p = node.Position - Vector3.new(0, node.Size.Y / 2, 0)
	local look = node.CFrame.LookVector * Vector3.new(1, 0, 1)
	vanHome = CFrame.lookAt(p, p + (if look.Magnitude > 0.1 then look.Unit else Vector3.new(1, 0, 0)))
	van:PivotTo(vanHome :: CFrame)
end

------------------------------------------------------------------ State housekeeping
-- (Brief 8: clearing a map after a run is the run slot's job: Run/Main clearArena.)

-- Where a freshly loaded character belongs: always the hub spawn (late joiners never land in the arena).
function Hub.spawnCFrame(_player: Player): CFrame?
	local view = HubMap.view
	if view then
		return view.spawn + Vector3.new(0, 3, 0) -- on the star, facing the pads
	end
	return Room.yardSpawn
end

-- Back to the hub for `players` (the party that just finished; its slot has cleared its map): fresh state
-- with HubCash, a fresh character at the yard spawn (or wherever pendingSpawnCFrame says: PLAY AGAIN
-- puts the party back on the queue pad).
function Hub.enter(players: { Player })
	for _, player in players do
		local state = PlayerState.get(player)
		local pending = state.pendingSpawnCFrame -- PLAY AGAIN: the queue pad
		PlayerState.reset(state, Config.HubCash)
		state.pendingSpawnCFrame = pending
		player:LoadCharacter()
	end
	task.delay(0.5, Hub.refreshAllTags)
end

-- Run start: fresh run state for the party where they stand; RunStart moves them.
function Hub.beginRun(players: { Player })
	for _, player in players do
		local state = PlayerState.get(player)
		PlayerState.reset(state, Config.StartingCash)
		-- Brief 9: the Skill Web applies for the whole run; SEED MONEY lands on the starting cash.
		PlayerState.armSkills(state, "run start")
		state.cash += state.skillMods.startCashFlat
		if not player.Character then
			player:LoadCharacter()
		end
		player:SetAttribute("Plate", false)
	end
end

-- Round 25: a booth keeper. The rig's look comes from the avatar's HumanoidDescription (Config.BoothNpcs[tab]),
-- built as an R15 standing where the rig stood, facing its way, looping the R15 idle. The asset rig stays (its
-- BoothTab attribute) but turns invisible with its own name hidden.
local function buildBoothNpc(rig: Model, tab: string)
	local spec = (Config.BoothNpcs :: any)[tab]
	local rigRoot = rig:FindFirstChild("HumanoidRootPart")
	if not spec or not rigRoot or not rigRoot:IsA("BasePart") then
		return
	end
	local desc: HumanoidDescription? = nil
	local ok, got = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(spec.userId)
	end)
	if ok and got then
		desc = got
	else
		Log.event("Hub", "booth NPC %s: no avatar for user %d (%s), plain R15", spec.name, spec.userId, tostring(got))
		desc = Instance.new("HumanoidDescription")
	end
	local ok2, npc = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc :: HumanoidDescription, Enum.HumanoidRigType.R15)
	end)
	if not ok2 or not npc then
		Log.event("Hub", "booth NPC %s failed: %s", spec.name, tostring(npc))
		return
	end
	local model = npc :: Model
	model.Name = "BoothNpc_" .. tab
	model:SetAttribute("BoothNpc", spec.name)
	model:SetAttribute("BoothRole", spec.role)
	CollectionService:AddTag(model, "GHSKeeper")
	local hum = model:FindFirstChildOfClass("Humanoid")
	local hrp = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not hrp then
		model:Destroy()
		return
	end
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.NameDisplayDistance = 0 -- Round 25: never Roblox's own name over the keeper (only the client tag)
	hum.HealthDisplayDistance = 0
	hum.DisplayName = spec.name
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	hrp.Anchored = true
	model.PrimaryPart = hrp
	local box, size = rig:GetBoundingBox()
	local floor = box.Position.Y - size.Y / 2
	local look = rigRoot.CFrame.LookVector * Vector3.new(1, 0, 1)
	local at = Vector3.new(rigRoot.Position.X, floor + hum.HipHeight + hrp.Size.Y / 2, rigRoot.Position.Z)
	model:PivotTo(CFrame.lookAt(at, at + (if look.Magnitude > 0.1 then look.Unit else Vector3.new(0, 0, 1))))
	-- The asset rig hides (server-wide), its name with it.
	for _, d in rig:GetDescendants() do
		if d:IsA("BasePart") then
			d.Transparency = 1
			d.CanCollide = false
		elseif d:IsA("Decal") then
			d.Transparency = 1
		elseif d:IsA("Humanoid") then
			d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		elseif d:IsA("BillboardGui") then
			d.Enabled = false
		end
	end
	model.Parent = rig.Parent
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
	local anim = Instance.new("Animation")
	anim.AnimationId = Config.BoothNpcIdleAnim
	local ok3, track = pcall(function()
		return (animator :: Animator):LoadAnimation(anim)
	end)
	if ok3 and track then
		track.Looped = true
		track.Priority = Enum.AnimationPriority.Idle
		track:Play()
	end
	Log.event("Hub", "booth %s keeper %s ready", tab, spec.name)
end

function Hub.init()
	HubMap.init()
	PlayerState.spawnCFrame = Hub.spawnCFrame
	local view = HubMap.view
	if view then
		Hub.garageShutter = buildShutter("GarageShutter", view.garage, false)
		Hub.rangeShutter = buildShutter("RangeShutter", view.rangeDoor, Config.RangeDoorOpen)
		-- The range door's RANGE prompt is only a sign (walking through is enough; on touch it reads the same).
		local rd = view.rangeDoor
		if rd then
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "RangePrompt"
			prompt.ActionText = "WALK IN"
			prompt.ObjectText = "RANGE"
			prompt.KeyboardKeyCode = Enum.KeyCode[Config.InteractKey]
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = 12
			prompt.RequiresLineOfSight = false
			prompt.Parent = rd.part
			prompt.Triggered:Connect(function(player)
				Remotes.Juice:FireClient(player, "Toast", { text = "WALK IN · YOUR GUN IS LIVE INSIDE" })
			end)
		end
		prepareVan()
		-- Round 25: the booth keepers. Each rig gives way to a named R15 NPC (Config.BoothNpcs); the client draws
		-- the close-range name tag (client/BoothMannequins.lua).
		for _, station in view.stations do
			local rig = station.rig
			if rig then
				rig:SetAttribute("BoothTab", station.tab)
				local root = rig:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") then
					root.Anchored = true
				end
				task.spawn(buildBoothNpc, rig, station.tab)
			end
		end
	end
	buildProps()
	decorate()
	buildJobBoard()
	buildDailyPodium() -- brief 10
	startBoothWalkIns()
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(char)
			task.spawn(function()
				char:WaitForChild("Head", 5)
				task.wait(0.2)
				Hub.refreshTag(player)
			end)
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do
		onPlayer(p)
	end
end

return Hub
