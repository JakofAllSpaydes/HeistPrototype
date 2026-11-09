--!strict
-- Client entry: builds the HUD, then the overlay, reel, ground loot tags, crew call UI and debug panel.
-- Camera.client.lua and Gun.client.lua run on their own.
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local ClientState = require(script.Parent:WaitForChild("ClientState"))
local HUD = require(script.Parent:WaitForChild("HUD"))

-- Round 24d: phones and tablets stay in landscape (either way up), never portrait.
do
	local Players = game:GetService("Players")
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	-- Round 24m: also baked into the place (default.project.json StarterGui), and re-asserted whenever anything
	-- (a respawn, a core script) puts it back.
	local LANDSCAPE = Enum.ScreenOrientation.LandscapeSensor
	local function force()
		if playerGui.ScreenOrientation ~= LANDSCAPE then
			playerGui.ScreenOrientation = LANDSCAPE
		end
	end
	StarterGui.ScreenOrientation = LANDSCAPE
	force()
	playerGui:GetPropertyChangedSignal("ScreenOrientation"):Connect(force)
	Players.LocalPlayer.CharacterAdded:Connect(function()
		task.defer(force)
	end)
end

-- Our own health bar and no backpack. (The core player list follows hub / run below.)
task.spawn(function()
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end)
		if ok then
			break
		end
		task.wait(0.5)
	end
end)

-- Round 21: in the hub, Tab is Roblox's own player list (LEVEL / BEST WAVE leaderstats, the player menu); in a
-- run it goes back off so Tab opens our scoreboard.
local playerListOn: boolean? = nil
local function syncPlayerList()
	local want = ClientState.inHub()
	if want == playerListOn then
		return
	end
	playerListOn = want
	task.spawn(function()
		for _ = 1, 10 do
			if pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.PlayerList, want) then
				return
			end
			task.wait(0.5)
		end
	end)
end
ClientState.Changed:Connect(syncPlayerList)
syncPlayerList()

-- Brief 9 QUICK HANDS: a hold prompt the server marks with QuickHandsBase (the side job's HACK) runs shorter on this
-- client by the armed Skill Web's interactPct (the server never times the hold; doors scale on the server).
do
	local ProximityPromptService = game:GetService("ProximityPromptService")
	ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
		local base = prompt:GetAttribute("QuickHandsBase")
		if typeof(base) ~= "number" then
			return
		end
		local mods = ClientState.sync and (ClientState.sync :: any).skillMods
		local pct = if typeof(mods) == "table" then tonumber(mods.interactPct) or 0 else 0
		prompt.HoldDuration = base / (1 + math.max(0, pct))
	end)
end

HUD.init()
require(script.Parent:WaitForChild("PurchaseSheet")).init()
require(script.Parent:WaitForChild("UpgradeOverlay")).init()
require(script.Parent:WaitForChild("CrateReelUI")).init()
require(script.Parent:WaitForChild("StatusFx")).init()
require(script.Parent:WaitForChild("MasteryUI")).init()
require(script.Parent:WaitForChild("DealerUI")).init()
require(script.Parent:WaitForChild("PauseUI")).init()
require(script.Parent:WaitForChild("GroundLoot")).init()
require(script.Parent:WaitForChild("BagChannel")).init()
require(script.Parent:WaitForChild("CrewCallUI")).init()
require(script.Parent:WaitForChild("Markers")).init()
require(script.Parent:WaitForChild("DoorUI")).init()
require(script.Parent:WaitForChild("LockdownUI")).init() -- Round 19d
require(script.Parent:WaitForChild("Music")).init() -- Round 19d
require(script.Parent:WaitForChild("DayNight")).init() -- Round 21
require(script.Parent:WaitForChild("Minigames")).init()
require(script.Parent:WaitForChild("DownedUI")).init()
require(script.Parent:WaitForChild("PlayerTags")).init()
require(script.Parent:WaitForChild("TeammateMarkers")).init() -- Round 25
require(script.Parent:WaitForChild("Nameplates")).init()
require(script.Parent:WaitForChild("Spectate")).init()
require(script.Parent:WaitForChild("RunStartUI")).init()
require(script.Parent:WaitForChild("BoothMannequins")).init() -- brief 8
require(script.Parent:WaitForChild("RunEndUI")).init()
require(script.Parent:WaitForChild("BossCutscene")).init()
require(script.Parent:WaitForChild("Scoreboard")).init()
require(script.Parent:WaitForChild("QueueUI")).init()
require(script.Parent:WaitForChild("MetaScene")).init()
require(script.Parent:WaitForChild("Store"):WaitForChild("StoreScene")).init()
require(script.Parent:WaitForChild("Pass"):WaitForChild("PassScene")).init()
require(script.Parent:WaitForChild("Jobs"):WaitForChild("JobBoard")).init()
require(script.Parent:WaitForChild("Skills"):WaitForChild("SkillScene")).init() -- brief 9: the Skill Web
require(script.Parent:WaitForChild("Retention"):WaitForChild("StreakModal")).init() -- brief 10: the login streak
require(script.Parent:WaitForChild("DebugPanel")).init()

-- Ctrl toggles the camera lock (mouse free / locked). Hold Left Alt to free it temporarily.
UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
		if ClientState.combatOff() then
			return -- no hotkeys in the hub (the range excepted); the cursor is free there anyway
		end
		ClientState.mouseFree = not ClientState.mouseFree
		HUD.get("toast").show(if ClientState.mouseFree then "CAMERA UNLOCKED" else "CAMERA LOCKED", nil, 0.7)
	elseif input.KeyCode == Enum.KeyCode.LeftAlt then
		ClientState.mouseFreeHold = true
	end
end)
UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.KeyCode == Enum.KeyCode.LeftAlt then
		ClientState.mouseFreeHold = false
	end
end)
