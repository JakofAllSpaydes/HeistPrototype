--!strict
-- The pause on the client (brief 5): a dim overlay with `PAUSED · NAMES`, the time left (`RESUMES IN 4:32`, red for
-- the last PauseCountdownSec), and two votes: VOTE TO EXTEND (+PauseExtendSec, as often as everyone agrees) and VOTE
-- TO RESUME (everyone; solo at once). Input is held (the gun is held and the mouse is free; the server anchors the
-- character). Vote toasts while the party votes. On Resumed every
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
local overlay: {
	gui: ScreenGui,
	names: TextLabel,
	count: TextLabel,
	extend: TextButton,
	resume: TextButton,
}? =
	nil

local function fmt(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end
local resumeAt = 0
local countdownSec = 10

local function show(data: any)
	if overlay then
		overlay.gui:Destroy()
	end
	-- Phones render UI.S at about half scale: RESUME stays a thumb-sized target there.
	local function S(n: number): number
		return UI.S(n * (if ClientState.isMobile then 1.4 else 1))
	end
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
		FontFace = Theme.Fonts.display,
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
		FontFace = Theme.Fonts.display,
		TextSize = S(18),
		TextColor3 = Theme.Colors.textDim,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.4, S(44)),
		Size = UDim2.fromOffset(S(600), S(24)),
		Parent = gui,
	})
	local count = UI.text({
		Text = "",
		FontFace = Theme.Fonts.display,
		TextSize = S(20),
		TextColor3 = Theme.Colors.amber,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.4, S(74)),
		Size = UDim2.fromOffset(S(600), S(26)),
		Parent = gui,
	})
	-- Two votes side by side: EXTEND (+5 min, stacks) and RESUME; everyone has to agree (solo: at once).
	local row = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.4, S(112)),
		Size = UDim2.fromOffset(S(460), S(58)),
		Parent = gui,
	})
	UI.list(row, Enum.FillDirection.Horizontal, S(12), Enum.HorizontalAlignment.Center)
	local function voteButton(text: string, color: Color3, order: number, action: string): TextButton
		local b = UI.button({
			Text = text,
			FontFace = Theme.Fonts.display,
			TextSize = S(18),
			TextColor3 = Theme.Colors.bg,
			BackgroundColor3 = color,
			Size = UDim2.new(0.5, -S(6), 1, 0),
			LayoutOrder = order,
			Parent = row,
		})
		UI.corner(b, S(12))
		UI.stroke(b, Theme.Colors.black, S(2), 0.4)
		b.Activated:Connect(function()
			UI.punch(b, 0.9, 0.15)
			Remotes.PauseAction:FireServer(action)
		end)
		return b
	end
	local extend = voteButton("VOTE TO EXTEND", Theme.Colors.blue, 1, "extend")
	local resume = voteButton("VOTE TO RESUME", Theme.Colors.cash, 2, "resume")
	overlay = { gui = gui, names = names, count = count, extend = extend, resume = resume }
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
		elseif name == "PauseExtended" and typeof(data) == "table" then
			resumeAt = tonumber(data.resumeAt) or resumeAt
			UI.sound(Theme.Sounds.toast, 1.3, 0.5)
			ClientState.Juice:Fire("Toast", { text = "PAUSE EXTENDED" })
			local o = overlay
			if o then
				UI.punch(o.count, 1.3, 0.3)
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
			else string.format("RESUMES IN %s", fmt(left))
		o.count.TextColor3 = if left <= countdownSec then Theme.Colors.red else Theme.Colors.amber
		-- The two votes with their counts (from the sync).
		local pv = ClientState.sync and (ClientState.sync :: any).pause
		if pv then
			local need = tonumber(pv.needed) or 1
			o.extend.Text = string.format(
				"VOTE TO EXTEND +%dm  %d/%d",
				math.floor((tonumber(pv.extendSec) or 300) / 60),
				tonumber(pv.extendVotes) or 0,
				need
			)
			o.resume.Text = string.format("VOTE TO RESUME  %d/%d", tonumber(pv.resumeVotes) or 0, need)
			o.extend.BackgroundColor3 = if pv.myExtend then Theme.Colors.gold else Theme.Colors.blue
			o.resume.BackgroundColor3 = if pv.myResume then Theme.Colors.gold else Theme.Colors.cash
		end
	end)
end

return PauseUI
