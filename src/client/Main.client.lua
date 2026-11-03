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
require(script.Parent:WaitForChild("DebugPanel")).init()

-- Hold Left Alt to free the mouse and click HUD tiles.
UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if input.KeyCode == Enum.KeyCode.LeftAlt and not gameProcessed then
		ClientState.setBlock("alt", true)
	end
end)
UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.KeyCode == Enum.KeyCode.LeftAlt then
		ClientState.setBlock("alt", false)
	end
end)
