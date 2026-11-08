--!strict
-- The hub: the yard where players spawn, with the planning table, the queue zone, the three customization
-- stations (prompts that open the customization scene on a tab), the minigame props and the tier pad.
-- Owns the Hub state's housekeeping: resets, teleports, clearing the arena between runs, and the
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

-- The yard's corkboard by a planning table with the four Job cards pinned to it, a JOBS sign and a beacon (the
-- client pulses it until the day's board is opened); F opens the JOBS screen.
local function buildJobBoard()
	local hubBoard = HubMap.view and HubMap.view.board
	if hubBoard then
		buildHubBoard(hubBoard)
		return
	end
	local base = Config.JobBoardPosition
	local floor = Config.FloorTop
	local m = Instance.new("Model")
	m.Name = "JobBoard"
	local facing = CFrame.new(Vector3.new(base.X, floor, base.Z)) -- the board faces +Z
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
		p.Parent = m
		return p
	end
	-- Legs and the board.
	for _, x in { -3.2, 3.2 } do
		part(
			"Leg",
			Vector3.new(0.4, 7, 0.4),
			facing * CFrame.new(x, 3.5, 0),
			Color3.fromRGB(70, 50, 34),
			Enum.Material.Wood
		)
	end
	local frame = part(
		"Frame",
		Vector3.new(7.4, 4.6, 0.5),
		facing * CFrame.new(0, 4.8, 0),
		Color3.fromRGB(90, 62, 40),
		Enum.Material.Wood
	)
	local cork = part(
		"Cork",
		Vector3.new(6.8, 4, 0.3),
		facing * CFrame.new(0, 4.8, 0.15),
		Color3.fromRGB(184, 140, 92),
		Enum.Material.Sand
	)
	-- Four pinned cards: three dailies and the bigger bounty poster.
	local cards = {
		{ CFrame.new(-2.3, 5.6, 0.32) * CFrame.Angles(0, 0, math.rad(-4)), Vector3.new(1.5, 1.2, 0.04) },
		{ CFrame.new(-0.6, 5.7, 0.32) * CFrame.Angles(0, 0, math.rad(3)), Vector3.new(1.5, 1.2, 0.04) },
		{ CFrame.new(-1.5, 4.1, 0.32) * CFrame.Angles(0, 0, math.rad(-2)), Vector3.new(1.5, 1.2, 0.04) },
		{ CFrame.new(1.9, 4.9, 0.32) * CFrame.Angles(0, 0, math.rad(2)), Vector3.new(2.2, 3, 0.04) },
	}
	for i, c in cards do
		local paper = part(
			"Card" .. i,
			c[2],
			facing * c[1],
			if i == 4 then Color3.fromRGB(226, 205, 160) else Color3.fromRGB(242, 230, 200),
			Enum.Material.SmoothPlastic
		)
		part(
			"Pin",
			Vector3.new(0.14, 0.14, 0.14),
			paper.CFrame * CFrame.new(0, c[2].Y / 2 - 0.12, 0.06),
			Color3.fromRGB(232, 85, 77),
			Enum.Material.SmoothPlastic
		)
	end
	-- The JOBS sign over the board.
	local sign = part(
		"Sign",
		Vector3.new(3.4, 0.9, 0.3),
		facing * CFrame.new(0, 7.6, 0),
		Color3.fromRGB(26, 26, 32),
		Enum.Material.SmoothPlastic
	)
	surfaceLabel(sign, Enum.NormalId.Back, "JOBS", GOLD, 80)
	-- The beacon: a neon strip under the sign (the client pulses it while a new board waits).
	local beacon = part(
		"Beacon",
		Vector3.new(6.8, 0.18, 0.2),
		facing * CFrame.new(0, 7.05, 0.2),
		Color3.fromHex("E8B64C"),
		Enum.Material.Neon
	)
	local light = Instance.new("PointLight")
	light.Name = "BeaconLight"
	light.Color = Color3.fromHex("E8B64C")
	light.Range = 14
	light.Brightness = 1.5
	light.Parent = beacon
	-- The planning table in front of it.
	local top = part(
		"Table",
		Vector3.new(6, 0.4, 3.2),
		facing * CFrame.new(0, 2.8, 3.4),
		Color3.fromRGB(80, 56, 38),
		Enum.Material.Wood
	)
	for _, x in { -2.6, 2.6 } do
		for _, z in { 2.1, 4.7 } do
			part(
				"TableLeg",
				Vector3.new(0.3, 2.6, 0.3),
				facing * CFrame.new(x, 1.3, z),
				Color3.fromRGB(60, 42, 28),
				Enum.Material.Wood
			)
		end
	end
	local map = part(
		"Blueprint",
		Vector3.new(3.4, 0.05, 2.2),
		top.CFrame * CFrame.new(-0.4, 0.22, 0) * CFrame.Angles(0, math.rad(8), 0),
		Color3.fromRGB(46, 92, 160),
		Enum.Material.SmoothPlastic
	)
	surfaceLabel(map, Enum.NormalId.Top, "THE BANK", Color3.fromRGB(220, 235, 255), 40)
	local _ = cork
	local _2 = frame
	boardPrompt(top, 10)
	m.Parent = Room.folder or workspace
	Hub.jobBoard = m
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
	end
	-- The yard's van is only a template now: each run slot drives its own copy.
	if Room.van then
		Room.van.Parent = nil
	end
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
