--!strict
-- The hub: the yard where players spawn, with the planning table, the queue zone, the three customization
-- stations (prompts that open the customization scene on a tab), the minigame props and the tier pad.
-- Owns the Hub state's housekeeping: resets, teleports, clearing the arena between runs, and the
-- TOP WAVE / class billboard over each character while they stand in the hub.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Classes = require(Shared.Classes)
local Maps = require(Shared.Maps)
local Room = require(script.Parent.Room)
local World = require(script.Parent.World)
local Log = require(script.Parent.Log)
local Profiles = require(script.Parent.Profiles)
local PlayerState = require(script.Parent.PlayerState)
local Enemy = require(script.Parent.Enemy)
local BigCrate = require(script.Parent.BigCrate)
local CrewCall = require(script.Parent.CrewCall)
local WeaponRoll = require(script.Parent.WeaponRoll)
local Abilities = require(script.Parent.Abilities)
local Squad = require(script.Parent.Squad)
local Bags = require(script.Parent.Bags)
local VaultJob = require(script.Parent.VaultJob)
local Boss = require(script.Parent.Boss)

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
	label.Font = Enum.Font.LuckiestGuy
	label.Text = text
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

------------------------------------------------------------------ TOP WAVE billboard
-- Above the character in the hub: TOP WAVE N with a star and the equipped class icon in a circle.
function Hub.refreshTag(player: Player)
	local state = PlayerState.get(player)
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	if not char or not head then
		return
	end
	local old = head:FindFirstChild("HubTag")
	if old then
		old:Destroy()
	end
	if World.inRunCycle() and World.isInParty(player) then
		return
	end
	local profile = state.profile
	-- Brief 7: the best top wave across maps, with that map's short name (LV 7 · TOP WAVE 14 ★ BANK).
	local top, topMap = 0, nil
	if profile then
		top, topMap = Profiles.bestTopWave(profile)
	end
	local level = if profile then profile.level else 1
	local class = Classes.ById[PlayerState.classOf(state)] or Classes.ById[Classes.Default]
	local gui = Instance.new("BillboardGui")
	gui.Name = "HubTag"
	gui.Adornee = head
	gui.AlwaysOnTop = false
	gui.Size = UDim2.fromScale(5, 1.3)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	gui.Parent = head
	local circle = Instance.new("Frame")
	circle.BackgroundColor3 = Color3.fromHex(class.color)
	circle.Size = UDim2.fromScale(0.22, 0.85)
	circle.Position = UDim2.fromScale(0.02, 0.075)
	circle.BorderSizePixel = 0
	circle.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = circle
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 1
	ratio.Parent = circle
	local icon = Instance.new("TextLabel")
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromScale(1, 1)
	icon.Font = Enum.Font.LuckiestGuy
	icon.TextScaled = true
	icon.Text = class.glyph
	icon.TextColor3 = DARK
	icon.Parent = circle
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromScale(0.26, 0)
	label.Size = UDim2.fromScale(0.74, 1)
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = string.format(
		"LV %d · TOP WAVE %d ★%s",
		level,
		top,
		if topMap and top > 0 then " " .. Maps.get(topMap).short else ""
	)
	label.TextColor3 = GOLD
	label.TextStrokeTransparency = 0.4
	label.Parent = gui
	-- Brief 6: the VIP gold tag, a small pill over the name line.
	if profile and profile.vip.active then
		local pill = Instance.new("Frame")
		pill.Name = "VipTag"
		pill.BackgroundColor3 = Color3.fromHex("F2C14E")
		pill.BorderSizePixel = 0
		pill.Position = UDim2.fromScale(0.26, -0.62)
		pill.Size = UDim2.fromScale(0.2, 0.55)
		pill.Parent = gui
		local pc = Instance.new("UICorner")
		pc.CornerRadius = UDim.new(0.3, 0)
		pc.Parent = pill
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromHex("FFF1C4")
		stroke.Thickness = 1.5
		stroke.Parent = pill
		local vt = Instance.new("TextLabel")
		vt.BackgroundTransparency = 1
		vt.Size = UDim2.fromScale(1, 1)
		vt.Font = Enum.Font.LuckiestGuy
		vt.TextScaled = true
		vt.Text = "VIP"
		vt.TextColor3 = DARK
		vt.Parent = pill
		gui.Size = UDim2.fromScale(5, 1.9)
		gui.StudsOffset = Vector3.new(0, 2.9, 0)
		circle.Size = UDim2.fromScale(0.22, 0.58)
		circle.Position = UDim2.fromScale(0.02, 0.36)
		label.Size = UDim2.fromScale(0.74, 0.68)
		label.Position = UDim2.fromScale(0.26, 0.32)
		pill.Position = UDim2.fromScale(0.26, 0)
		pill.Size = UDim2.fromScale(0.2, 0.3)
	end
end

function Hub.refreshAllTags()
	for _, p in Players:GetPlayers() do
		Hub.refreshTag(p)
	end
end

------------------------------------------------------------------ Dressing
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
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "Prompt"
		prompt.ActionText = "OPEN"
		prompt.ObjectText = station.tab
		prompt.KeyboardKeyCode = Enum.KeyCode.F
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 9
		prompt.RequiresLineOfSight = false
		prompt.Parent = station.panel
		prompt.Triggered:Connect(function(player)
			local state = PlayerState.get(player)
			if World.inRunCycle() and World.isInParty(player) then
				return
			end
			if not PlayerState.isStanding(state) then
				return
			end
			Remotes.Juice:FireClient(player, "OpenMeta", { tab = station.tab })
		end)
	end
end

------------------------------------------------------------------ MARLOW's job board (brief 6)
-- A corkboard by a planning table in the yard with the four Job cards pinned to it, a JOBS sign and a beacon (the
-- client pulses it until the day's board is opened); F opens the JOBS screen.
local function buildJobBoard()
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
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Prompt"
	prompt.ActionText = "OPEN"
	prompt.ObjectText = "MARLOW'S JOBS"
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = top
	prompt.Triggered:Connect(function(player)
		if World.inRunCycle() and World.isInParty(player) then
			return
		end
		Remotes.Juice:FireClient(player, "OpenJobs", {})
	end)
	m.Parent = Room.folder or workspace
	Hub.jobBoard = m
end

------------------------------------------------------------------ State housekeeping
-- Everything hostile or left over from the last run goes away.
function Hub.clearArena()
	Enemy.killAll()
	BigCrate.finishAll()
	CrewCall.finish(false, true)
	WeaponRoll.clearAll()
	Abilities.clearAll()
	Squad.clear()
	Bags.clearAll()
	VaultJob.resetRun()
	Boss.clear()
	Enemy.paused = false
	World.spawnsPaused = false
	World.enemiesLeft = 0
end

-- Where a freshly loaded character belongs: always the hub spawn (late joiners never land in the arena).
function Hub.spawnCFrame(_player: Player): CFrame?
	return Room.yardSpawn
end

-- Back to the hub for `players` (the party that just finished): clean arena, van put away, fresh state
-- with HubCash, a fresh character at the yard spawn (or wherever pendingSpawnCFrame says: PLAY AGAIN
-- puts the party back on the queue pad).
function Hub.enter(players: { Player })
	Hub.clearArena()
	local van = Room.van
	if van then
		van.Parent = nil
	end
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
function Hub.beginRun()
	for _, player in World.partyPlayers() do
		local state = PlayerState.get(player)
		PlayerState.reset(state, Config.StartingCash)
		if not player.Character then
			player:LoadCharacter()
		end
		local char = player.Character
		local head = char and char:FindFirstChild("Head")
		local tag = head and head:FindFirstChild("HubTag")
		if tag then
			tag:Destroy()
		end
	end
end

function Hub.init()
	PlayerState.spawnCFrame = Hub.spawnCFrame
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
