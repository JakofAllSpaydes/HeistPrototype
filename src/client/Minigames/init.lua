--!strict
-- Minigame registry: the server says which game to open (MinigameStart), the shared Frame hosts it and
-- reports the result. One module per game beside this one.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local HUD = require(script.Parent:WaitForChild("HUD"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local Frame = require(script.Frame)

local Minigames = {}

local specs: { [string]: Frame.GameSpec } = {
	Lockpick = require(script.Lockpick),
	Hotwire = require(script.Hotwire),
	Keypad = require(script.Keypad),
	Charges = require(script.Charges),
	Safe = require(script.Safe),
	Freq = require(script.Freq),
}

function Minigames.init()
	Frame.init()
	Remotes.MinigameStart.OnClientEvent:Connect(function(data: any)
		local spec = specs[tostring(data.name)]
		if not spec then
			warn("[GHS Minigame] no client module for " .. tostring(data.name))
			return
		end
		Frame.open(tostring(data.name), spec, tonumber(data.tier) or 1, tonumber(data.token) or 0)
	end)
	ClientState.Juice:Connect(function(name: string, data: any)
		if name == "MinigameDone" then
			HUD.get("toast").show(string.format("%s DONE", string.upper(tostring(data.name))), Theme.Colors.cash, 1.2)
		end
	end)
end

return Minigames
