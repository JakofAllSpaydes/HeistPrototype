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
local Room = require(script.Parent.Room)
local World = require(script.Parent.World)
local Log = require(script.Parent.Log)
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
	local top = if profile then (profile.topWave[World.partyKey()] or profile.topWave["TheBank:Normal"] or 0) else 0
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
	icon.Text = string.sub(class.name, 1, 1)
	icon.TextColor3 = DARK
	icon.Parent = circle
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromScale(0.26, 0)
	label.Size = UDim2.fromScale(0.74, 1)
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = string.format("LV %d · TOP WAVE %d ★", level, top)
	label.TextColor3 = GOLD
	label.TextStrokeTransparency = 0.4
	label.Parent = gui
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
