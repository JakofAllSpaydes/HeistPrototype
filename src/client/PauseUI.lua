--!strict
-- The pause on the client (brief 5): a dim overlay with `PAUSED · NAMES` and RESUME (any player), input held
-- (the gun is held and the mouse is free; the server anchors the character), and the last PauseCountdownSec
-- before PauseMaxSec counting down to the auto-resume. Vote toasts while the party votes. On Resumed every
-- deadline the client keeps from a juice event (the side job pill and marker) moves by the pause length
-- (CrewCallUI and Markers listen too).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Remotes = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Remotes"))

local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local PauseUI = {}

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local overlay: { gui: ScreenGui, names: TextLabel, count: TextLabel }? = nil
local resumeAt = 0
local countdownSec = 10

local function show(data: any)
	if overlay then
		overlay.gui:Destroy()
	end
	local S = UI.S
	local gui = UI.new("ScreenGui", {
		Name = "PauseOverlay",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 50,
		Parent = playerGui,
	}) :: ScreenGui
	local dim = UI.frame({
		BackgroundColor3 = Theme.Colors.black,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = gui,
	})
	UI.tween(dim, { BackgroundTransparency = 0.45 }, 0.25)
	local title = UI.text({
		Text = "PAUSED",
		Font = Theme.Fonts.display,
		TextSize = S(72),
		TextColor3 = Theme.Colors.text,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromOffset(S(600), S(80)),
		Parent = gui,
	})
	UI.stroke(title, Theme.Colors.black, S(3), 0.2)
	UI.punch(title, 1.3, 0.35)
	local names = UI.text({
		Text = tostring(data.names or ""),
		Font = Theme.Fonts.display,
		TextSize = S(18),
		TextColor3 = Theme.Colors.textDim,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.4, S(44)),
		Size = UDim2.fromOffset(S(600), S(24)),
		Parent = gui,
	})
	local count = UI.text({
		Text = "",
		Font = Theme.Fonts.display,
		TextSize = S(20),
		TextColor3 = Theme.Colors.amber,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.4, S(74)),
		Size = UDim2.fromOffset(S(600), S(26)),
		Parent = gui,
	})
	local resume = UI.button({
		Text = "RESUME",
		Font = Theme.Fonts.display,
		TextSize = S(22),
		TextColor3 = Theme.Colors.bg,
		BackgroundColor3 = Theme.Colors.cash,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.4, S(112)),
		Size = UDim2.fromOffset(S(220), S(54)),
		Parent = gui,
	})
	UI.corner(resume, S(12))
	UI.stroke(resume, Theme.Colors.black, S(2), 0.4)
	resume.Activated:Connect(function()
		UI.punch(resume, 0.9, 0.15)
		Remotes.PauseAction:FireServer("resume")
	end)
	overlay = { gui = gui, names = names, count = count }
	resumeAt = tonumber(data.resumeAt) or 0
	countdownSec = tonumber(data.countdownSec) or 10
	ClientState.setBlock("pause", true)
	ClientState.lockMovement("pause", true)
	UI.sound(Theme.Sounds.call, 0.6, 0.6)
end

local function hide()
	ClientState.setBlock("pause", false)
	ClientState.lockMovement("pause", false)
	local o = overlay
	overlay = nil
	if o then
		o.gui:Destroy()
	end
end

function PauseUI.init()
	ClientState.Juice:Connect(function(name: string, data: any)
		if name == "Paused" then
			show(data)
		elseif name == "Resumed" or name == "HubEnter" then
			hide()
			if name == "Resumed" then
				UI.sound(Theme.Sounds.wave, 1.1, 0.5)
				ClientState.Juice:Fire("Toast", { text = "RESUMED" })
			end
		elseif name == "PauseVote" and typeof(data) == "table" and data.on then
			ClientState.Juice:Fire("Toast", {
				text = string.format(
					"%s VOTED TO PAUSE · %d/%d",
					string.upper(tostring(data.name or "")),
					tonumber(data.votes) or 0,
					tonumber(data.needed) or 1
				),
			})
		end
	end)
	RunService.Heartbeat:Connect(function()
		local o = overlay
		if not o then
			return
		end
		local left = resumeAt - ClientState.serverNow()
		o.count.Text = if left <= countdownSec
			then string.format("RESUMING IN %d", math.max(0, math.ceil(left)))
			else ""
	end)
end

return PauseUI
