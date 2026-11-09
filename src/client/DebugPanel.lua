--!strict
-- Backtick toggles a small panel top-right. Each row sends a Debug remote; the server validates.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Enemies = require(Shared:WaitForChild("Enemies"))

local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local HUD = require(script.Parent:WaitForChild("HUD"))
local NodeOverlay = require(script.Parent:WaitForChild("NodeOverlay"))
local Input = require(script.Parent:WaitForChild("Input"))
local InputMonitor = require(script.Parent:WaitForChild("InputMonitor"))
local Haptics = require(script.Parent:WaitForChild("Haptics"))
local GamepadMap = require(Shared:WaitForChild("GamepadMap"))
local Sprint = require(script.Parent:WaitForChild("Sprint"))
local GamepadNav = require(script.Parent:WaitForChild("GamepadNav"))

local DebugPanel = {}

-- Brief 11 step 3: Sprint log on screen, a toast per finished sprint.
Sprint.Ended:Connect(function(rec: any)
	if not Sprint.showLog then
		return
	end
	local toast = HUD.get("toast")
	if toast then
		toast.show(
			string.format("SPRINT %s %.2fs · %s", string.upper(rec.device), rec.sec, string.upper(rec.reason)),
			if rec.reason == "fire" and rec.sec < 0.5 then Theme.Colors.malus else Theme.Colors.gold,
			1.5
		)
	end
end)

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

	-- Round 17c: the panel scrolls once it is taller than the screen (it grew past the bottom edge).
	local panel = UI.new("ScrollingFrame", {
		Name = "Panel",
		BackgroundColor3 = Theme.Colors.panel,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -S(20), 0, S(72)),
		Size = UDim2.fromOffset(S(240), S(300)),
		CanvasSize = UDim2.fromOffset(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = S(5),
		ScrollBarImageColor3 = Theme.Colors.gold,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
		Active = true,
		Parent = g,
	}) :: ScrollingFrame
	UI.corner(panel, S(10))
	UI.stroke(panel, Theme.Colors.gold, S(1.5))
	UI.pad(panel, S(8), S(8), S(8), S(8))
	local layout = UI.list(panel, Enum.FillDirection.Vertical, S(4))
	local function fit()
		local vp = (workspace.CurrentCamera :: Camera).ViewportSize
		local h = math.min(layout.AbsoluteContentSize.Y + S(16), vp.Y - S(72) - S(16))
		panel.Size = UDim2.fromOffset(S(240), math.max(S(60), h))
	end
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fit)
	task.defer(fit)
	UI.text({
		Text = "DEBUG  (` to close)",
		FontFace = Theme.Fonts.display,
		TextSize = S(14),
		TextColor3 = Theme.Colors.gold,
		Size = UDim2.new(1, 0, 0, S(20)),
		LayoutOrder = 0,
		Parent = panel,
	})

	local rh = S(26)

	-- Brief 11: INPUT. The monitor, a forced device, live look / assist dials (GamepadMap.live: they win over Config
	-- until Reset), the haptics test and the input settings reset.
	local function inputHeader(order: number, text: string)
		UI.text({
			Text = text,
			FontFace = Theme.Fonts.display,
			TextSize = S(12),
			TextColor3 = Theme.Colors.amber,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, 0, 0, S(16)),
			LayoutOrder = order,
			Parent = panel,
		})
	end
	inputHeader(0.1, "INPUT")
	local ri1 = row(panel, 0.11, rh)
	local monBtn: TextButton
	monBtn = btn(ri1, if InputMonitor.visible() then "Input monitor ON" else "Input monitor", 0.5, function()
		InputMonitor.setVisible(not InputMonitor.visible())
		monBtn.Text = if InputMonitor.visible() then "Input monitor ON" else "Input monitor"
		monBtn.TextColor3 = if InputMonitor.visible() then Theme.Colors.gold else Theme.Colors.text
	end, Theme.Colors.amber)
	local devices = { "auto", "keyboard", "touch", "gamepad" }
	local devBtn: TextButton
	devBtn = btn(ri1, "Device: " .. (Input.forcedDevice or "auto"), 0.5, function()
		local cur = Input.forcedDevice or "auto"
		local i = table.find(devices, cur) or 1
		local nextD = devices[i % #devices + 1]
		Input.forceDevice(if nextD == "auto" then nil else nextD)
		devBtn.Text = "Device: " .. nextD
	end, Theme.Colors.amber)
	-- A dial: label, value, - and +. get / set read and write GamepadMap.live (nil = the Config value).
	local function dial(order: number, label: string, key: string, step: number, lo: number, hi: number, path: string?)
		local r = row(panel, order, rh)
		local function get(): number
			local v = GamepadMap.cfg(key)
			if path then
				v = v[path]
			end
			return tonumber(v) or 0
		end
		local valueBtn: TextButton
		local function set(v: number)
			v = math.clamp(math.round(v / step) * step, lo, hi)
			if path then
				local t = table.clone(GamepadMap.cfg(key))
				t[path] = v
				GamepadMap.live[key] = t
			else
				GamepadMap.live[key] = v
			end
			valueBtn.Text = string.format("%s %s", label, tostring(v))
		end
		btn(r, "-", 0.2, function()
			set(get() - step)
		end)
		valueBtn = btn(r, string.format("%s %s", label, tostring(get())), 0.6, function()
			-- tap the value: back to Config
			GamepadMap.live[key] = nil
			valueBtn.Text = string.format("%s %s", label, tostring(get()))
		end, Theme.Colors.amber)
		btn(r, "+", 0.2, function()
			set(get() + step)
		end)
	end
	dial(0.12, "Look speed", "GamepadLookSpeed", 10, 30, 600)
	dial(0.121, "Look curve", "GamepadLookCurve", 0.1, 1, 4)
	dial(0.122, "Dead zone", "GamepadLookDeadZone", 0.02, 0, 0.5)
	dial(0.123, "Assist gamepad", "AimAssistScale", 0.05, 0, 1.5, "gamepad")
	dial(0.124, "Assist touch", "AimAssistScale", 0.05, 0, 1.5, "touch")
	local ri2 = row(panel, 0.13, rh)
	btn(ri2, "Haptics test", 0.5, function()
		Haptics.test()
	end, Theme.Colors.amber)
	local ri3 = row(panel, 0.131, rh)
	local sprintBtn: TextButton
	local navBtn: TextButton
	navBtn = btn(ri3, if GamepadNav.showNav then "Show nav ON" else "Show nav", 0.5, function()
		GamepadNav.showNav = not GamepadNav.showNav
		navBtn.Text = if GamepadNav.showNav then "Show nav ON" else "Show nav"
	end, Theme.Colors.amber)
	sprintBtn = btn(ri3, if Sprint.showLog then "Sprint log ON" else "Sprint log on screen", 0.5, function()
		Sprint.showLog = not Sprint.showLog
		sprintBtn.Text = if Sprint.showLog then "Sprint log ON" else "Sprint log on screen"
	end, Theme.Colors.amber)
	btn(ri2, "Reset input settings", 0.5, function()
		Remotes.SetInputSetting:FireServer("reset", true)
		table.clear(GamepadMap.live)
		build()
	end, Theme.Colors.red)

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
		FontFace = Theme.Fonts.body,
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
	local r4b = row(panel, 4.5, rh)
	toggles.nocd = btn(r4b, "No cooldowns", 0.5, function()
		send("NoCooldowns")
	end)
	btn(r4b, "Synergy", 0.5, function()
		send("ForceSynergy")
	end, Color3.fromHex("5CE1E6"))

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
	btn(r6, "Tradeoff", 0.34, function()
		send("ForceTradeoff")
	end)
	btn(r6, "Element", 0.33, function()
		send("ForceElement")
	end, Color3.fromHex("FF8A3C"))
	btn(r6, "Drop crate", 0.33, function()
		send("DropCrate")
	end, Theme.Colors.gold)

	-- Brief 4: spawn any archetype at the marker nearest you; ELITE prefixes the next spawns.
	UI.text({
		Text = "ENEMIES (spawn near you)",
		TextSize = S(10),
		TextColor3 = Theme.Colors.grey,
		Size = UDim2.new(1, 0, 0, S(14)),
		LayoutOrder = 17,
		Parent = panel,
	})
	local elitePrefix = false
	-- Brief 7: spawn at a chosen box (cycled in the MAP group); "nearest" uses the box nearest you.
	local boxNames = { "nearest" }
	do
		local bank = workspace:FindFirstChild("Bank")
		local nodes = bank and bank:FindFirstChild("Nodes")
		local boxes = nodes and nodes:FindFirstChild("SpawnBoxes")
		if boxes then
			for _, b in boxes:GetChildren() do
				table.insert(boxNames, b.Name)
			end
		end
	end
	local boxIndex = 1
	local rE1 = row(panel, 18, rh)
	local rE2 = row(panel, 19, rh)
	for i, e in Enemies.List do
		btn(if i <= 4 then rE1 else rE2, e.name, if i <= 4 then 0.25 else 0.25, function()
			send(
				"SpawnEnemy",
				(if elitePrefix then "elite:" else "")
					.. e.id
					.. (if boxIndex > 1 then "@" .. boxNames[boxIndex] else "")
			)
		end, Color3.fromHex(e.color):Lerp(Theme.Colors.text, 0.45))
	end
	toggles.elite = btn(rE2, "ELITE", 0.25, function()
		elitePrefix = not elitePrefix
		local b = toggles.elite
		if b then
			b.TextColor3 = if elitePrefix then Theme.Colors.gold else Theme.Colors.text
		end
	end)
	local rE3 = row(panel, 20, rh)
	btn(rE3, "Boss", 0.25, function()
		send("SpawnBoss")
	end, Theme.Colors.red)
	btn(rE3, "Cash bag", 0.25, function()
		send("SpawnBag", "cash")
	end, Theme.Colors.cash)
	btn(rE3, "Gold bag", 0.25, function()
		send("SpawnBag", "gold")
	end, Theme.Colors.gold)
	btn(rE3, "Open vault", 0.25, function()
		send("OpenVault")
	end, Theme.Colors.amber)
	-- Heat as pace, the vault's gas and a Loot Rush burst.
	local rE4 = row(panel, 21, rh)
	local heatBox = UI.new("TextBox", {
		PlaceholderText = "Heat…",
		Text = "",
		TextSize = S(11),
		FontFace = Theme.Fonts.body,
		TextColor3 = Theme.Colors.text,
		PlaceholderColor3 = Theme.Colors.grey,
		BackgroundColor3 = Theme.Colors.bg,
		Size = UDim2.new(0.25, -S(4), 1, 0),
		ClearTextOnFocus = false,
		Parent = rE4,
	}) :: TextBox
	UI.corner(heatBox, S(6))
	UI.stroke(heatBox, Theme.Colors.grey, S(1), 0.5)
	btn(rE4, "Set heat", 0.25, function()
		send("SetHeat", tonumber(heatBox.Text))
	end, Theme.Colors.gold)
	heatBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			send("SetHeat", tonumber(heatBox.Text))
		end
	end)
	btn(rE4, "Gas vault", 0.25, function()
		send("GasVault")
	end, Theme.Colors.red)
	-- (Seal vault sits in the MAP group.)
	btn(rE4, "Loot rush", 0.25, function()
		send("LootRush")
	end, Theme.Colors.cash)

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
	-- Account level (brief 4): +500 XP, set level, reset the daily flag.
	local r12b = row(panel, 16.5, rh)
	btn(r12b, "+500 XP", 0.3, function()
		send("AddXp", 500)
	end, Theme.Colors.gold)
	local levelBox = UI.new("TextBox", {
		PlaceholderText = "Level…",
		Text = "",
		TextSize = S(11),
		FontFace = Theme.Fonts.body,
		TextColor3 = Theme.Colors.text,
		PlaceholderColor3 = Theme.Colors.grey,
		BackgroundColor3 = Theme.Colors.bg,
		Size = UDim2.new(0.25, -S(4), 1, 0),
		ClearTextOnFocus = false,
		Parent = r12b,
	}) :: TextBox
	UI.corner(levelBox, S(6))
	UI.stroke(levelBox, Theme.Colors.grey, S(1), 0.5)
	btn(r12b, "Set", 0.15, function()
		send("SetLevel", tonumber(levelBox.Text))
	end)
	btn(r12b, "Reset daily (x2 + crate)", 0.3, function()
		send("ResetDaily")
	end, Theme.Colors.malus)
	-- Brief 5: +100 mastery on the held gun and the equipped class (tier-ups pop and apply at once).
	local r12c = row(panel, 16.6, rh)
	btn(r12c, "+100 mastery", 1 / 3, function()
		send("AddMastery")
	end, Theme.Colors.gold)
	btn(r12c, "Open dealer", 1 / 3, function()
		send("OpenDealer")
	end, Theme.Colors.amber)
	btn(r12c, "Pause / resume", 1 / 3, function()
		send("TogglePause")
	end)
	-- Brief 9: the Skill Web. Grant: pick a branch, then a ring (the ring's first unowned node, rules ignored).
	local rS1 = row(panel, 16.7, rh)
	btn(rS1, "Unlock all skills", 1 / 3, function()
		send("UnlockSkills")
	end, Theme.Colors.gold)
	btn(rS1, "Reset skills", 1 / 3, function()
		send("ResetSkills")
	end, Theme.Colors.malus)
	btn(rS1, "+10,000 Gold", 1 / 3, function()
		send("AddGold", 10000)
	end, Theme.Colors.gold)
	local rS2 = row(panel, 16.8, rh)
	local rS3 = row(panel, 16.9, rh)
	local grantBranch = "DAMAGE"
	local branchBtns: { [string]: TextButton } = {}
	local function paintBranches()
		for id, b in branchBtns do
			b.BackgroundColor3 = if id == grantBranch then Theme.Colors.blue else Theme.Colors.panel2
		end
	end
	for _, id in { "DAMAGE", "SURVIVAL", "SPEED", "CASH", "LUCK", "ARSENAL" } do
		branchBtns[id] = btn(rS2, string.sub(id, 1, 4), 1 / 6, function()
			grantBranch = id
			paintBranches()
		end)
	end
	paintBranches()
	btn(rS3, "Grant ring", 1 / 6, function() end, Theme.Colors.grey)
	for ring = 1, 5 do
		btn(rS3, tostring(ring), 1 / 6, function()
			send("GrantSkill", { branch = grantBranch, ring = ring })
		end, Theme.Colors.gold)
	end

	-- Brief 6: monetization (fake balance, tokens, free crate opens, the fake clock, pass XP, Jobs, the readout).
	-- Force rarity above also lands on the next crate open.
	UI.text({
		Text = "MONETIZATION",
		TextSize = S(10),
		TextColor3 = Theme.Colors.grey,
		Size = UDim2.new(1, 0, 0, S(14)),
		LayoutOrder = 17,
		Parent = panel,
	})
	local function numberBox(parent: Instance, placeholder: string, w: number): TextBox
		local box = UI.new("TextBox", {
			PlaceholderText = placeholder,
			Text = "",
			TextSize = S(11),
			FontFace = Theme.Fonts.body,
			TextColor3 = Theme.Colors.text,
			PlaceholderColor3 = Theme.Colors.grey,
			BackgroundColor3 = Theme.Colors.bg,
			Size = UDim2.new(w, -S(4), 1, 0),
			ClearTextOnFocus = false,
			Parent = parent,
		}) :: TextBox
		UI.corner(box, S(6))
		UI.stroke(box, Theme.Colors.grey, S(1), 0.5)
		return box
	end
	local rM1 = row(panel, 17.1, rh)
	local robuxBox = numberBox(rM1, "R$…", 0.3)
	btn(rM1, "Set R$", 0.2, function()
		send("SetRobux", tonumber(robuxBox.Text) or 100000)
	end, Color3.fromHex("2FD46A"))
	local tokenBox = numberBox(rM1, "Tokens…", 0.3)
	btn(rM1, "Set tkn", 0.2, function()
		send("SetTokens", tonumber(tokenBox.Text) or 0)
	end, Color3.fromHex("3FD47A"))
	local rM2 = row(panel, 17.2, rh)
	btn(rM2, "+10 Arms", 1 / 3, function()
		send("CrateCredits", "arms")
	end, Theme.Colors.gold)
	btn(rM2, "+10 Mask", 1 / 3, function()
		send("CrateCredits", "mask")
	end, Theme.Colors.gold)
	btn(rM2, "+1 day", 1 / 3, function()
		send("AdvanceDay", 1)
	end, Theme.Colors.amber)
	local rM3 = row(panel, 17.3, rh)
	btn(rM3, "+1,000 pass", 1 / 3, function()
		send("AddPassXp", 1000)
	end, Color3.fromHex("E8792A"))
	btn(rM3, "Reset jobs", 1 / 3, function()
		send("ResetJobs")
	end, Theme.Colors.malus)
	btn(rM3, "Buy log", 1 / 3, function()
		send("PurchaseLog")
	end)
	-- Brief 10: the login streak (the modal opens on the set day / the lost streak right away; +1 day above) and the
	-- daily crate (unlock / reset for today; Force tier rolls that band whatever your level, AUTO goes back to it).
	local rR1 = row(panel, 17.4, rh)
	local streakBox = numberBox(rR1, "Day…", 0.25)
	btn(rR1, "Set streak day", 0.4, function()
		send("SetStreakDay", tonumber(streakBox.Text) or 1)
	end, Theme.Colors.gold)
	btn(rR1, "Break streak", 0.35, function()
		send("BreakStreak")
	end, Theme.Colors.malus)
	local rR2 = row(panel, 17.5, rh)
	btn(rR2, "Unlock daily crate", 0.5, function()
		send("UnlockDailyCrate")
	end, Theme.Colors.gold)
	btn(rR2, "Reset daily crate", 0.5, function()
		send("ResetDailyCrate")
	end, Theme.Colors.malus)
	local rR3 = row(panel, 17.6, rh)
	for _, tier in { "auto", "basic", "gold", "diamond", "elite" } do
		btn(rR3, string.upper(tier), 0.2, function()
			send("ForceDailyTier", tier)
		end, if tier == "auto" then Theme.Colors.grey else Theme.Colors.amber)
	end

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
	-- Brief 8: HUB (the warehouse: teleports, the range's dummies and moving targets, the garage, the pads).
	UI.text({
		Text = "HUB",
		FontFace = Theme.Fonts.display,
		TextSize = S(12),
		TextColor3 = Theme.Colors.amber,
		Size = UDim2.new(1, 0, 0, S(16)),
		LayoutOrder = 29,
		Parent = panel,
	})
	local rHub1 = row(panel, 29.1, rh)
	btn(rHub1, "To hub", 0.25, function()
		send("TeleportHub")
	end, Theme.Colors.blue)
	btn(rHub1, "To range", 0.25, function()
		send("TeleportRange")
	end, Theme.Colors.blue)
	btn(rHub1, "Reset dummies", 0.25, function()
		send("ResetDummies")
	end)
	btn(rHub1, "Open garage", 0.25, function()
		send("OpenGarage")
	end, Theme.Colors.amber)
	local rHub2 = row(panel, 29.2, rh)
	for pad = 1, 4 do
		local b = btn(rHub2, "Force pad " .. pad, 0.25, function()
			send("ForcePad", pad)
		end, Theme.Colors.gold)
		b.TextSize = S(9)
	end
	-- Spawn at range: the archetype row, ELITE and the boss (a moving target that stays in the range).
	local rangeElite = false
	local rHub3 = row(panel, 29.3, rh)
	local rHub4 = row(panel, 29.4, rh)
	for i, e in Enemies.List do
		local b = btn(if i <= 4 then rHub3 else rHub4, e.name, 0.25, function()
			send("RangeSpawn", (if rangeElite then "elite:" else "") .. e.id)
		end, Color3.fromHex(e.color):Lerp(Theme.Colors.text, 0.45))
		b.TextSize = S(9)
	end
	local rHub5 = row(panel, 29.5, rh)
	toggles.rangeElite = btn(rHub5, "ELITE", 0.5, function()
		rangeElite = not rangeElite
		local b = toggles.rangeElite
		if b then
			b.TextColor3 = if rangeElite then Theme.Colors.gold else Theme.Colors.text
		end
	end)
	btn(rHub5, "Range boss", 0.5, function()
		send("RangeSpawn", "boss")
	end, Theme.Colors.red)
	-- Brief 7: MAP (THE BANK's nodes and doors).
	UI.text({
		Text = "MAP",
		FontFace = Theme.Fonts.display,
		TextSize = S(12),
		TextColor3 = Theme.Colors.amber,
		Size = UDim2.new(1, 0, 0, S(16)),
		LayoutOrder = 30,
		Parent = panel,
	})
	local rMap1 = row(panel, 30.1, rh)
	toggles.nodes = btn(rMap1, if NodeOverlay.on then "Show nodes ON" else "Show nodes", 0.5, function()
		NodeOverlay.setOn(not NodeOverlay.on)
		local b = toggles.nodes
		b.Text = if NodeOverlay.on then "Show nodes ON" else "Show nodes"
		b.TextColor3 = if NodeOverlay.on then Theme.Colors.gold else Theme.Colors.text
	end, Theme.Colors.amber)
	btn(rMap1, "Recompute nodes", 0.5, function()
		send("RecomputeNodes")
		task.delay(0.5, NodeOverlay.refresh)
	end)
	-- Teleport to zone: one button per THE BANK zone.
	local zoneRow: Frame? = nil
	for i, z in { "street", "lobby", "upper", "back", "stairs", "vault", "tunnel" } do
		if (i - 1) % 4 == 0 then
			zoneRow = row(panel, 30.15 + math.floor((i - 1) / 4) * 0.001, rh)
		end
		local b = btn(zoneRow :: Frame, string.upper(z), 0.25, function()
			send("TeleportZone", z)
		end, Theme.Colors.blue)
		b.TextSize = S(9)
	end
	-- Open a door group (completes its objective) / close every door.
	local rDoor = row(panel, 30.17, rh)
	for _, gid in { "D1", "D2", "D3", "D5", "D4" } do
		local b = btn(rDoor, "Open " .. gid, 0.16, function()
			send("OpenDoor", gid)
		end, Theme.Colors.amber)
		b.TextSize = S(9)
	end
	local closeBtn = btn(rDoor, "Close all", 0.2, function()
		send("CloseAllDoors")
	end, Theme.Colors.malus)
	closeBtn.TextSize = S(9)
	local rVault = row(panel, 30.175, rh)
	btn(rVault, "Open vault", 1 / 3, function()
		send("OpenVault")
	end, Theme.Colors.amber)
	btn(rVault, "Gas vault", 1 / 3, function()
		send("GasVault")
	end, Theme.Colors.red)
	btn(rVault, "Seal vault", 1 / 3, function()
		send("SealVault")
	end, Theme.Colors.grey)
	-- Round 19c: zone gas now, SILENCE THE ALARM, CUT THE CHAIN.
	local rGas = row(panel, 30.18, rh)
	btn(rGas, "Zone gas", 0.25, function()
		send("ZoneGasNow")
	end, Theme.Colors.red)
	btn(rGas, "Lockdown", 0.25, function() -- Round 19d
		send("LockdownNow")
	end, Theme.Colors.red)
	btn(rGas, "Alarm job", 0.25, function()
		send("AlarmJob")
	end, Theme.Colors.amber)
	btn(rGas, "Cut job", 0.25, function()
		send("CutJob")
	end, Theme.Colors.amber)
	-- Round 19f: RAID THE OFFICE now / blow the nearest office open.
	local rOffice = row(panel, 30.185, rh)
	btn(rOffice, "Office job", 0.5, function()
		send("OfficeJob")
	end, Theme.Colors.amber)
	btn(rOffice, "Open office", 0.5, function()
		send("OpenOffice")
	end, Theme.Colors.amber)
	-- Pin the crew zone (or AUTO), and the path overlay.
	local pinRow: Frame? = nil
	for i, z in { "auto", "street", "lobby", "upper", "back", "stairs", "vault", "tunnel" } do
		if (i - 1) % 4 == 0 then
			pinRow = row(panel, 30.19 + math.floor((i - 1) / 4) * 0.001, rh)
		end
		local b = btn(pinRow :: Frame, if z == "auto" then "Zone AUTO" else "Pin " .. string.upper(z), 0.25, function()
			send("SetCrewZone", z)
		end, Theme.Colors.blue)
		b.TextSize = S(9)
	end
	local rPath = row(panel, 30.195, rh)
	btn(rPath, "Path debug", 1, function()
		send("PathDebug")
	end, Theme.Colors.blue)
	local rBox = row(panel, 30.18, rh)
	local boxBtn: TextButton
	boxBtn = btn(rBox, "Spawn at: nearest", 1, function()
		boxIndex = boxIndex % #boxNames + 1
		boxBtn.Text = "Spawn at: " .. boxNames[boxIndex]
	end, Theme.Colors.malus)
	-- Per-type toggles, four to a row.
	local typeRow: Frame? = nil
	for i, typeName in NodeOverlay.TYPES do
		if (i - 1) % 4 == 0 then
			typeRow = row(panel, 30.2 + math.floor((i - 1) / 4) * 0.01, rh)
		end
		local b: TextButton
		b = btn(typeRow :: Frame, typeName, 0.25, function()
			NodeOverlay.setType(typeName, not NodeOverlay.shown[typeName])
			b.TextColor3 = if NodeOverlay.shown[typeName] then Theme.Colors.gold else Theme.Colors.grey
		end)
		b.TextSize = S(9)
		b.TextColor3 = if NodeOverlay.shown[typeName] then Theme.Colors.gold else Theme.Colors.grey
	end
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
	if toggles.nocd and toggles.nocd.Parent then
		toggles.nocd.Text = if sync.noCooldowns then "No cooldowns ON" else "No cooldowns"
		toggles.nocd.TextColor3 = if sync.noCooldowns then Theme.Colors.gold else Theme.Colors.text
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

GamepadNav.register("debug", {
	back = function()
		DebugPanel.setVisible(false)
	end,
})

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
		FontFace = Theme.Fonts.display,
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
	ClientState.Juice:Connect(function(name: string, data: any)
		if name == "PathDebug" and typeof(data) == "table" then
			NodeOverlay.drawPaths(data.paths or {})
		end
	end)
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
