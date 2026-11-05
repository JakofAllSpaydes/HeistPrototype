--!strict
-- Client entry: builds the HUD, then the overlay, reel, ground loot tags, crew call UI and debug panel.
-- Camera.client.lua and Gun.client.lua run on their own.
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local ClientState = require(script.Parent:WaitForChild("ClientState"))
local HUD = require(script.Parent:WaitForChild("HUD"))

-- Our own health bar and no backpack.
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

HUD.init()
require(script.Parent:WaitForChild("UpgradeOverlay")).init()
require(script.Parent:WaitForChild("WeaponReel")).init()
require(script.Parent:WaitForChild("GroundLoot")).init()
require(script.Parent:WaitForChild("CrewCallUI")).init()
require(script.Parent:WaitForChild("Markers")).init()
require(script.Parent:WaitForChild("Minigames")).init()
require(script.Parent:WaitForChild("DownedUI")).init()
require(script.Parent:WaitForChild("PlayerTags")).init()
require(script.Parent:WaitForChild("Spectate")).init()
require(script.Parent:WaitForChild("RunStartUI")).init()
require(script.Parent:WaitForChild("RunEndUI")).init()
require(script.Parent:WaitForChild("BossCutscene")).init()
require(script.Parent:WaitForChild("QueueUI")).init()
require(script.Parent:WaitForChild("MetaScene")).init()
require(script.Parent:WaitForChild("DebugPanel")).init()

-- Ctrl toggles the camera lock (mouse free / locked). Hold Left Alt to free it temporarily.
UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
		if ClientState.inHub() then
			return -- no hotkeys in the hub; the cursor is free there anyway
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
