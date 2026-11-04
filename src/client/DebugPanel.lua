--!strict
-- Backtick toggles a small panel top-right. Each row sends a Debug remote; the server validates.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Rarity = require(Shared:WaitForChild("Rarity"))

local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local HUD = require(script.Parent:WaitForChild("HUD"))

local DebugPanel = {}

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local gui: ScreenGui? = nil
local toggles: { [string]: TextButton } = {}
local visible = false

local function send(command: string, args: any?)
	Remotes.Debug:FireServer(command, args)
end

local function row(parent: Instance, order: number, height: number): Frame
	local f = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, height),
		LayoutOrder = order,
		Parent = parent,
	})
	UI.list(f, Enum.FillDirection.Horizontal, UI.S(4))
	return f
end

local function btn(parent: Instance, text: string, widthScale: number, onClick: () -> (), color: Color3?): TextButton
	local S = UI.S
	local b = UI.button({
		Text = text,
		TextSize = S(11),
		TextColor3 = color or Theme.Colors.text,
		BackgroundColor3 = Theme.Colors.panel2,
		Size = UDim2.new(widthScale, -S(4), 1, 0),
		Parent = parent,
	})
	UI.corner(b, S(6))
	UI.stroke(b, color or Theme.Colors.grey, S(1), 0.5)
	b.Activated:Connect(function()
		UI.punch(b, 0.92, 0.12)
		onClick()
	end)
	return b
end

local function build()
	if gui then
		gui:Destroy()
	end
	local S = UI.S
	local g = UI.new("ScreenGui", {
		Name = "DebugPanel",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 20,
		Enabled = visible,
		Parent = playerGui,
	}) :: ScreenGui
	gui = g

	local panel = UI.frame({
		Name = "Panel",
		BackgroundColor3 = Theme.Colors.panel,
		BackgroundTransparency = 0.05,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -S(20), 0, S(72)),
		Size = UDim2.fromOffset(S(230), 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Active = true,
		Parent = g,
	})
	UI.corner(panel, S(10))
	UI.stroke(panel, Theme.Colors.gold, S(1.5))
	UI.pad(panel, S(8), S(8), S(8), S(8))
	UI.list(panel, Enum.FillDirection.Vertical, S(4))
	UI.text({
		Text = "DEBUG  (` to close)",
		Font = Theme.Fonts.display,
		TextSize = S(14),
		TextColor3 = Theme.Colors.gold,
		Size = UDim2.new(1, 0, 0, S(20)),
		LayoutOrder = 0,
		Parent = panel,
	})

	local rh = S(26)
	local r1 = row(panel, 1, rh)
	btn(r1, "+$1,000", 0.5, function()
		send("AddCash", 1000)
	end, Theme.Colors.cash)
	btn(r1, "+$10,000", 0.5, function()
		send("AddCash", 10000)
	end, Theme.Colors.cash)

	local r2 = row(panel, 2, rh)
	btn(r2, "Skip wave", 0.5, function()
		send("SkipWave")
	end)
	btn(r2, "Kill all", 0.5, function()
		send("KillAll")
	end)

	local r3 = row(panel, 3, rh)
	local box = UI.new("TextBox", {
		PlaceholderText = "Set wave…",
		Text = "",
		TextSize = S(11),
		Font = Theme.Fonts.body,
		TextColor3 = Theme.Colors.text,
		PlaceholderColor3 = Theme.Colors.grey,
		BackgroundColor3 = Theme.Colors.bg,
		Size = UDim2.new(0.6, -S(4), 1, 0),
		ClearTextOnFocus = false,
		Parent = r3,
	}) :: TextBox
	UI.corner(box, S(6))
	UI.stroke(box, Theme.Colors.grey, S(1), 0.5)
	btn(r3, "Apply", 0.4, function()
		send("SetWave", tonumber(box.Text))
	end)
	box.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			send("SetWave", tonumber(box.Text))
		end
	end)

	local r4 = row(panel, 4, rh)
	toggles.pause = btn(r4, "Pause spawns", 0.5, function()
		send("PauseSpawns")
	end)
	toggles.god = btn(r4, "God mode", 0.5, function()
		send("GodMode")
	end)

	UI.text({
		Text = "FORCE RARITY (next roll)",
		TextSize = S(10),
		TextColor3 = Theme.Colors.grey,
		Size = UDim2.new(1, 0, 0, S(14)),
		LayoutOrder = 5,
		Parent = panel,
	})
	local r5 = row(panel, 6, rh)
	for r = 1, 5 do
		btn(r5, Rarity.Letters[r], 0.2, function()
			send("ForceRarity", r)
		end, Rarity.color(r))
	end

	local r6 = row(panel, 7, rh)
	btn(r6, "Force tradeoff", 0.5, function()
		send("ForceTradeoff")
	end)
	btn(r6, "Drop crate", 0.5, function()
		send("DropCrate")
	end, Theme.Colors.gold)

	local r7 = row(panel, 8, rh)
	btn(r7, "Trigger call", 0.5, function()
		send("TriggerCall")
	end, Theme.Colors.blue)
	btn(r7, "Reset run", 0.5, function()
		send("ResetRun")
	end, Theme.Colors.malus)

	local r8 = row(panel, 9, rh)
	btn(r8, "Force queue start", 0.5, function()
		send("StartRun")
	end, Theme.Colors.cash)
	btn(r8, "Skip to run end", 0.5, function()
		send("EndRun")
	end, Theme.Colors.red)

	UI.text({
		Text = "PROFILE",
		TextSize = S(10),
		TextColor3 = Theme.Colors.grey,
		Size = UDim2.new(1, 0, 0, S(14)),
		LayoutOrder = 15,
		Parent = panel,
	})
	local r12 = row(panel, 16, rh)
	btn(r12, "+1,000 Gold", 1 / 3, function()
		send("AddGold", 1000)
	end, Theme.Colors.gold)
	btn(r12, "Unlock all", 1 / 3, function()
		send("UnlockAll")
	end, Theme.Colors.gold)
	btn(r12, "Reset profile", 1 / 3, function()
		send("ResetProfile")
	end, Theme.Colors.malus)

	local r8b = row(panel, 10, rh)
	btn(r8b, "Down me", 1 / 3, function()
		send("DownMe")
	end, Theme.Colors.malus)
	btn(r8b, "Down all", 1 / 3, function()
		send("DownAll")
	end, Theme.Colors.malus)
	btn(r8b, "Revive all", 1 / 3, function()
		send("ReviveAll")
	end, Theme.Colors.cash)

	UI.text({
		Text = "MINIGAMES (open · tier)",
		TextSize = S(10),
		TextColor3 = Theme.Colors.grey,
		Size = UDim2.new(1, 0, 0, S(14)),
		LayoutOrder = 11,
		Parent = panel,
	})
	local r9 = row(panel, 12, rh)
	for _, name in { "Lockpick", "Hotwire", "Keypad" } do
		btn(r9, name, 1 / 3, function()
			send("OpenMinigame", name)
		end)
	end
	local r10 = row(panel, 13, rh)
	for _, name in { "Charges", "Safe", "Freq" } do
		btn(r10, name, 1 / 3, function()
			send("OpenMinigame", name)
		end)
	end
	local r11 = row(panel, 14, rh)
	for t = 1, 3 do
		toggles["tier" .. t] = btn(r11, "Tier " .. t, 0.2, function()
			send("SetTier", t)
		end)
	end
	btn(r11, "Stats", 0.4, function()
		send("MinigameStats")
	end, Theme.Colors.gold)
end

local function refreshToggles()
	local sync = ClientState.sync
	if not sync then
		return
	end
	if toggles.pause and toggles.pause.Parent then
		toggles.pause.Text = if sync.spawnsPaused then "Resume spawns" else "Pause spawns"
		toggles.pause.TextColor3 = if sync.spawnsPaused then Theme.Colors.gold else Theme.Colors.text
	end
	if toggles.god and toggles.god.Parent then
		toggles.god.Text = if sync.god then "God mode ON" else "God mode"
		toggles.god.TextColor3 = if sync.god then Theme.Colors.gold else Theme.Colors.text
	end
	for t = 1, 3 do
		local b = toggles["tier" .. t]
		if b and b.Parent then
			b.TextColor3 = if sync.minigameTier == t then Theme.Colors.gold else Theme.Colors.text
		end
	end
end

function DebugPanel.setVisible(on: boolean)
	visible = on
	if gui then
		gui.Enabled = on
	end
	ClientState.setBlock("debug", on)
end

-- Mobile has no backtick: a small DBG chip top-left toggles the panel.
local function buildMobileToggle()
	if not ClientState.isMobile then
		return
	end
	local S = UI.S
	local g = UI.new("ScreenGui", {
		Name = "DebugToggle",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 21,
		Parent = playerGui,
	}) :: ScreenGui
	local chip = UI.button({
		Text = "DBG",
		Font = Theme.Fonts.display,
		TextSize = S(12),
		TextColor3 = Theme.Colors.gold,
		BackgroundColor3 = Theme.Colors.panel,
		BackgroundTransparency = 0.3,
		Position = UDim2.fromOffset(S(8), S(8)),
		Size = UDim2.fromOffset(S(44), S(26)),
		Parent = g,
	})
	UI.corner(chip, S(8))
	UI.stroke(chip, Theme.Colors.gold, S(1), 0.5)
	chip.Activated:Connect(function()
		local sync = ClientState.sync
		if sync and not sync.debugEnabled then
			return
		end
		DebugPanel.setVisible(not visible)
	end)
end

function DebugPanel.init()
	build()
	buildMobileToggle()
	HUD.Rebuilt:Connect(function()
		build()
		refreshToggles()
	end)
	ClientState.Changed:Connect(refreshToggles)
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Backquote then
			local sync = ClientState.sync
			if sync and not sync.debugEnabled then
				return
			end
			DebugPanel.setVisible(not visible)
		end
	end)
end

return DebugPanel
