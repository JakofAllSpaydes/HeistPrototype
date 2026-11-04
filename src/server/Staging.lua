--!strict
-- The staging yard: where players spawn, where the minigame props and the tier pad stand, and the run start
-- door. Owns the Staging state's housekeeping: resets, teleports, clearing the arena between runs.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
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

local Staging = {}

local GOLD = Color3.fromHex("E8B64C")
local TEXT = Color3.fromHex("F2E6C8")
local GREY = Color3.fromHex("9BA0A8")
local DARK = Color3.fromHex("1A1A20")

local startPrompt: ProximityPrompt? = nil

-- Text on one face of a Part. Floor labels are rotated so the text reads from the east (where you stand).
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

function Staging.setTier(tier: number, who: string?)
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

function Staging.requestRun(player: Player?)
	if World.state ~= "Staging" then
		return
	end
	World.runRequested = true
	Log.event("Run", "START RUN pressed by %s", if player then player.Name else "debug")
end

-- Labels on the props and the tier pad, prompts on the door marker and the pad buttons.
local function decorate()
	for name, prop in Room.props do
		local caps = string.upper(name)
		surfaceLabel(prop.label, Enum.NormalId.Top, caps, GOLD, 60)
		surfaceLabel(prop.panel, Enum.NormalId.Right, caps, TEXT, 48)
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
			Staging.setTier(t, player.Name)
		end)
	end
	paintTier()

	local marker = Room.startMarker
	if marker then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "StartRun"
		prompt.ActionText = "START RUN"
		prompt.ObjectText = "ARENA DOOR"
		prompt.KeyboardKeyCode = Enum.KeyCode.F
		prompt.HoldDuration = 0.3
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = marker
		prompt.Triggered:Connect(function(player)
			Staging.requestRun(player)
		end)
		startPrompt = prompt
	end
end

-- Everything hostile or left over from the last run goes away.
function Staging.clearArena()
	Enemy.killAll()
	BigCrate.finishAll()
	CrewCall.finish(false, true)
	WeaponRoll.clearAll()
	Abilities.clearAll()
	Squad.clear()
	World.spawnsPaused = false
	World.enemiesLeft = 0
end

-- Where a freshly loaded character belongs. nil = the SpawnLocation in the yard; mid-run late joiners
-- skip the yard and land at the arena spawn.
function Staging.spawnCFrame(_player: Player): CFrame?
	if World.state == "Staging" then
		return nil
	end
	return CFrame.new(Room.arenaSpawn + Vector3.new((math.random() - 0.5) * 8, 3, 6)) -- arenaSpawn sits on the floor top
end

-- Back to the yard: clean arena, van put away (it only appears in the start animation), fresh state with
-- StagingCash, and a fresh character for everyone at the yard spawn (masks off, nothing anchored,
-- bled-out players back).
function Staging.enter()
	Staging.clearArena()
	local van = Room.van
	if van then
		van.Parent = nil
	end
	if startPrompt then
		startPrompt.Enabled = true
	end
	for player, state in PlayerState.all() do
		PlayerState.reset(state, Config.StagingCash)
		player:LoadCharacter()
	end
end

-- Run start: fresh run state for everyone where they stand; RunStart moves them.
function Staging.beginRun()
	if startPrompt then
		startPrompt.Enabled = false
	end
	for player, state in PlayerState.all() do
		PlayerState.reset(state, Config.StartingCash)
		if not player.Character then
			player:LoadCharacter()
		end
	end
end

function Staging.init()
	PlayerState.spawnCFrame = Staging.spawnCFrame
	decorate()
end

return Staging
