--!strict
-- Brief 7: the door objective's feedback on this client. The holder's bar bottom-centre (`OPENING · 2.1s`, the
-- revive bar's look, filled from the server's progress and kept while the fill holds after a release), and the
-- open beat for everyone: a short flash and the DoorOpenShake camera shake, plus the vault door's bass thud.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Lines = require(Shared:WaitForChild("CrewCall"):WaitForChild("Lines"))

local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local DoorUI = {}

local player = Players.LocalPlayer
local gui: ScreenGui? = nil
local bar: { root: Frame, fill: Frame, label: TextLabel }? = nil
local hideToken = 0
local lastTickProgress = 0

local function ensureBar()
	if bar and bar.root.Parent then
		return bar
	end
	local S = UI.S
	local g = UI.new("ScreenGui", {
		Name = "DoorHold",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 6,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui
	gui = g
	local root = UI.frame({
		BackgroundColor3 = Theme.Colors.bg,
		BackgroundTransparency = 0.2,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -S(150)),
		Size = UDim2.fromOffset(S(240), S(26)),
		Visible = false,
		Parent = g,
	})
	UI.corner(root, S(13))
	UI.stroke(root, Theme.Colors.amber, S(2))
	local fill = UI.frame({
		BackgroundColor3 = Theme.Colors.amber,
		Size = UDim2.fromScale(0, 1),
		Parent = root,
	})
	UI.corner(fill, S(13))
	local label = UI.text({
		Text = "",
		FontFace = Theme.Fonts.display,
		TextSize = S(13),
		TextColor3 = Theme.Colors.white,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = root,
	})
	UI.stroke(label, Theme.Colors.black, S(1.5), 0.3)
	local made = { root = root, fill = fill, label = label }
	bar = made
	return made
end

local function onProgress(data: any)
	local b = ensureBar()
	local progress = math.clamp(tonumber(data.progress) or 0, 0, 1)
	local holdSec = tonumber(data.holdSec) or 3
	local mine = data.byId == player.UserId
	if progress <= 0 or progress >= 1 then
		b.root.Visible = false
		return
	end
	-- Only the holder sees the bar; a released fill stays up (dimmed) while it keeps.
	if not mine and not b.root.Visible then
		return
	end
	b.root.Visible = true
	b.fill.Size = UDim2.fromScale(progress, 1)
	b.fill.BackgroundTransparency = if mine then 0 else 0.5
	b.label.Text = string.format(Lines.door.holdText, (1 - progress) * holdSec)
	if mine and progress > lastTickProgress + 0.18 then
		lastTickProgress = progress
		local pitch = 0.8 + progress * 0.6
		if data.style == "chain" then
			UI.sound(Theme.Sounds.snip, pitch, 0.15 + progress * 0.15)
		else
			UI.sound(Theme.Sounds.click, pitch, 0.12 + progress * 0.1)
		end
	end
	if progress <= 0 then
		lastTickProgress = 0
	end
	hideToken += 1
	local token = hideToken
	task.delay(2.5, function()
		if token == hideToken and b.root.Parent then
			b.root.Visible = false
		end
	end)
end

function DoorUI.init()
	ClientState.Juice:Connect(function(name: string, data: any)
		if name == "DoorProgress" then
			onProgress(data)
		elseif name == "DoorOpened" then
			lastTickProgress = 0
			local b = bar
			if b then
				b.root.Visible = false
			end
			local shake = tonumber(data.shake) or 0
			if shake > 0 then
				ClientState.Juice:Fire("Shake", { amp = shake * 1.6, dur = 0.5 })
				ClientState.Juice:Fire("RarityFlash", { color = Theme.Colors.amber, alpha = 0.28 })
				if data.style == "shutter" then
					UI.sound(Theme.Sounds.shutter, 1.15, 0.6)
				elseif data.style == "chain" then
					UI.sound(Theme.Sounds.snip, 0.9, 0.55)
					UI.sound(Theme.Sounds.crunch, 0.7, 0.4)
				end
				UI.sound(Theme.Sounds.crate, 0.6, 0.6)
				task.delay(0.15, function()
					UI.sound(Theme.Sounds.crate, 0.5, 0.4)
				end)
			end
		elseif name == "DoorThud" then
			UI.sound(Theme.Sounds.crate, 0.45, 0.8)
			ClientState.Juice:Fire("Shake", { amp = 0.35, dur = 0.35 })
		elseif name == "HubEnter" then
			local b = bar
			if b then
				b.root.Visible = false
			end
		end
	end)
	local _ = gui
end

return DoorUI
