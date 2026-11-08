--!strict
-- The hub (brief 8: the builder's warehouse, Workspace.Hub, read by HubMap): the star where players spawn, the
-- three booths (OPEN opens the customization scene on a tab; each booth's rig is a mannequin the client dresses
-- in your loadout), MARLOW's board, the van in its garage (the departure beat on run start), the range door, and
-- the minigame props and tier pad standing in the range. Owns the hub's housekeeping (spawns, resets) and the
-- nameplate data (level, class, best wave, VIP) each character shows while they stand in the hub.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Fonts = require(Shared.Fonts)
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
function Hub.refreshTag(player: Player)
	local state = PlayerState.get(player)
	if Runs.inRunCycle(player) then
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
	prompt.KeyboardKeyCode = Enum.KeyCode.F
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
		prompt.KeyboardKeyCode = Enum.KeyCode.F
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
	-- Brief 8: the warehouse's three booths (their signs are the asset's): OPEN on each counter edge.
	local view = HubMap.view
	if view then
		for _, station in view.stations do
			stationPrompt(station.part, station.tab, Config.BoothPromptDistance)
		end
	end
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
	prompt.KeyboardKeyCode = Enum.KeyCode.F
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
	boardPrompt(anchor, Config.BoardPromptDistance)
	m.Parent = HubMap.model or workspace
	Hub.jobBoard = m
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
	p.Material = Enum.Material.CorrugatedPlate
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
		prompt.KeyboardKeyCode = Enum.KeyCode.F
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
	local value = Instance.new("CFrameValue")
	value.Value = home
	local conn = value.Changed:Connect(function(v)
		van:PivotTo(v :: any)
	end)
	local drive = math.max(0.2, Config.HubDepartSec - lead)
	TweenService:Create(value, TweenInfo.new(drive, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Value = home * CFrame.new(0, 0, -Config.HubVanDriveStuds),
	}):Play()
	task.wait(drive)
	conn:Disconnect()
	value:Destroy()
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
		if not player.Character then
			player:LoadCharacter()
		end
		player:SetAttribute("Plate", false)
	end
end

function Hub.init()
	HubMap.init()
	PlayerState.spawnCFrame = Hub.spawnCFrame
	local view = HubMap.view
	if view then
		Hub.garageShutter = buildShutter("GarageShutter", view.garage, false)
		Hub.rangeShutter = buildShutter("RangeShutter", view.rangeDoor, Config.RangeDoorOpen)
		prepareVan()
		-- The booth rigs: each client dresses them in its own player's loadout (client/BoothMannequins.lua).
		for _, station in view.stations do
			local rig = station.rig
			if rig then
				rig:SetAttribute("BoothTab", station.tab)
				local root = rig:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") then
					root.Anchored = true
				end
			end
		end
	end
	buildProps()
	decorate()
	buildJobBoard()
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
