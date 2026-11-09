--!strict
-- Brief 11 step 4: the INPUT settings page (CONTROLS). The game has no settings screen, so this is its own sheet:
-- opened from the hub (CONTROLS, bottom-left) and from the scoreboard in a run. Left: the settings (stored on the
-- profile under settings.input through Remotes.SetInputSetting); right: every binding, keyboard key and pad glyph
-- side by side (Config.GamepadMap). Esc / B / X close it. Walkable on a pad like every screen (GamepadNav "settings").
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local InputSettings = require(Shared:WaitForChild("InputSettings"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local InputGlyphs = require(script.Parent:WaitForChild("InputGlyphs"))
local GamepadNav = require(script.Parent:WaitForChild("GamepadNav"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local InputSettingsSheet = {}

local gui: ScreenGui? = nil
local open = false
local pending: { [string]: any } = {} -- sent, not yet back in the sync
local paintRows: () -> () = function() end

local LABELS: { [string]: string } = {
	sprintTouch = "SPRINT · TOUCH",
	sprintPc = "SPRINT · KEYBOARD",
	sprintPad = "SPRINT · PAD",
	lookSens = "LOOK SPEED · PAD",
	invertY = "INVERT LOOK · PAD",
	adsToggle = "AIM",
	aimAssist = "AIM ASSIST · PAD / TOUCH",
	haptics = "VIBRATION · PAD",
	glyphs = "BUTTON ICONS",
}

local CHOICE_TEXT: { [string]: { [string]: string } } = {
	sprintTouch = { push = "PUSH THROUGH", button = "BUTTON", off = "OFF" },
	sprintPc = { hold = "HOLD SHIFT", toggle = "TAP SHIFT" },
	sprintPad = { toggle = "CLICK L3", hold = "HOLD L3" },
	glyphs = { auto = "AUTO", playstation = "PLAYSTATION", xbox = "XBOX" },
}

-- The bindings column: label, action (and the context its pad button lives in).
local BINDINGS: { { label: string, action: string, ctx: string? } } = {
	{ label = "FIRE", action = "fire" },
	{ label = "AIM", action = "ads" },
	{ label = "RELOAD", action = "reload" },
	{ label = "INTERACT · REVIVE (HOLD)", action = "interact" },
	{ label = "SWAP GUNS", action = "swap" },
	{ label = "JUMP", action = "jump" },
	{ label = "ABILITY 1", action = "ability1" },
	{ label = "ABILITY 2", action = "ability2" },
	{ label = "ABILITY 3", action = "ability3" },
	{ label = "SPRINT", action = "sprint" },
	{ label = "CAMERA VIEW", action = "cameraCycle" },
	{ label = "UPGRADE PICK · DEALER TELEPORT", action = "upgrade" },
	{ label = "VOTE SKIP", action = "voteSkip" },
	{ label = "DEALER STANDS", action = "dealerNext" },
	{ label = "SCOREBOARD · PAUSE", action = "scoreboard" },
}

local function value(key: string): any
	local p = pending[key]
	if p ~= nil then
		return p
	end
	return (ClientState.inputSettings() :: any)[key]
end

local function valueText(key: string): string
	local v = value(key)
	local s = InputSettings.SCHEMA[key]
	if s.kind == "boolean" then
		if key == "adsToggle" then
			return if v then "TOGGLE" else "HOLD"
		end
		return if v then "ON" else "OFF"
	elseif s.kind == "number" then
		return tostring(v)
	end
	local t = CHOICE_TEXT[key]
	return if t and t[v] then t[v] else string.upper(tostring(v))
end

local function set(key: string, v: any)
	local clean = InputSettings.sanitize(key, v)
	if clean == nil then
		return
	end
	pending[key] = clean
	Remotes.SetInputSetting:FireServer(key, clean)
	UI.sound(Theme.Sounds.toast, 1.3, 0.3)
	paintRows()
end

local function step(key: string, dir: number)
	local s = InputSettings.SCHEMA[key]
	local v = value(key)
	if s.kind == "boolean" then
		set(key, not v)
	elseif s.kind == "number" then
		set(key, math.clamp(v + dir * s.step, s.min, s.max))
	else
		local i = table.find(s.choices, v) or 1
		set(key, s.choices[(i - 1 + dir) % #s.choices + 1])
	end
end

local function build()
	if gui then
		gui:Destroy()
	end
	local S = UI.S
	local mobile = ClientState.isMobile
	local g = UI.new("ScreenGui", {
		Name = "InputSettings",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 30,
		Enabled = false,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	}) :: ScreenGui
	gui = g
	local backdrop = UI.button({
		Name = "Backdrop",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Colors.black,
		BackgroundTransparency = 0.35,
		Size = UDim2.fromScale(1, 1),
		Selectable = false,
		Parent = g,
	})
	backdrop.Activated:Connect(function()
		InputSettingsSheet.close()
	end)
	local w = if mobile then S(720) else S(860)
	local rowH = S(if mobile then 40 else 38)
	local h = S(64) + rowH * #BINDINGS + S(24)
	local panel = UI.button({
		Name = "Panel",
		Text = "",
		AutoButtonColor = false,
		Selectable = false,
		BackgroundColor3 = Theme.Colors.panel,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(w, h),
		Parent = g,
	})
	UI.corner(panel, S(4))
	UI.stroke(panel, Theme.Colors.gold, S(2))
	UI.text({
		Text = "CONTROLS",
		FontFace = Theme.Fonts.display,
		TextSize = S(30),
		TextColor3 = Theme.Colors.gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(S(20), S(12)),
		Size = UDim2.new(1, -S(80), 0, S(36)),
		Parent = panel,
	})
	local x = UI.button({
		Name = "Close",
		Text = "X",
		FontFace = Theme.Fonts.display,
		TextSize = S(22),
		TextColor3 = Theme.Colors.text,
		BackgroundColor3 = Theme.Colors.panel2,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -S(12), 0, S(12)),
		Size = UDim2.fromOffset(S(40), S(40)),
		Parent = panel,
	})
	UI.corner(x, S(4))
	x.Activated:Connect(function()
		InputSettingsSheet.close()
	end)

	-- Left: settings.
	local left = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(S(20), S(64)),
		Size = UDim2.new(0.5, -S(30), 1, -S(80)),
		Parent = panel,
	})
	UI.list(left, Enum.FillDirection.Vertical, S(6))
	local valueButtons: { [string]: TextButton } = {}
	for i, key in InputSettings.ORDER do
		local row = UI.frame({
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, S(56)),
			LayoutOrder = i,
			Parent = left,
		})
		UI.text({
			Text = LABELS[key] or string.upper(key),
			FontFace = Theme.Fonts.display,
			TextSize = S(15),
			TextColor3 = Theme.Colors.textDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, 0, 0, S(18)),
			Parent = row,
		})
		local isNumber = InputSettings.SCHEMA[key].kind == "number"
		local function arrow(dir: number)
			local a = UI.button({
				Text = if dir < 0 then "-" else "+",
				FontFace = Theme.Fonts.display,
				TextSize = S(22),
				TextColor3 = Theme.Colors.text,
				BackgroundColor3 = Theme.Colors.panel2,
				AnchorPoint = Vector2.new(if dir < 0 then 0 else 1, 0),
				Position = UDim2.new(if dir < 0 then 0 else 1, 0, 0, S(20)),
				Size = UDim2.fromOffset(S(48), S(34)),
				Parent = row,
			})
			UI.corner(a, S(4))
			a.Activated:Connect(function()
				step(key, dir)
			end)
		end
		local vb = UI.button({
			Name = "Value",
			Text = "",
			FontFace = Theme.Fonts.display,
			TextSize = S(20),
			TextColor3 = Theme.Colors.bg,
			BackgroundColor3 = Theme.Colors.gold,
			Position = UDim2.new(0, if isNumber then S(54) else 0, 0, S(20)),
			Size = UDim2.new(1, if isNumber then -S(108) else 0, 0, S(34)),
			Parent = row,
		})
		UI.corner(vb, S(4))
		vb.Activated:Connect(function()
			step(key, 1)
		end)
		if isNumber then
			arrow(-1)
			arrow(1)
		end
		valueButtons[key] = vb
		if i == 1 then
			vb:SetAttribute("NavDefault", true)
		end
	end
	paintRows = function()
		for key, vb in valueButtons do
			vb.Text = valueText(key)
		end
	end
	paintRows()

	-- Right: the bindings, keyboard key and pad glyph.
	local right = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, S(10), 0, S(64)),
		Size = UDim2.new(0.5, -S(30), 1, -S(80)),
		Parent = panel,
	})
	UI.list(right, Enum.FillDirection.Vertical, 0)
	local chip = S(28)
	for i, b in BINDINGS do
		local row = UI.frame({
			BackgroundColor3 = if i % 2 == 0 then Theme.Colors.panel2 else Theme.Colors.panel,
			BackgroundTransparency = 0.2,
			Size = UDim2.new(1, 0, 0, rowH),
			LayoutOrder = i,
			Parent = right,
		})
		local kb = InputGlyphs.chip(b.action, chip, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, S(6), 0.5, 0),
			Parent = row,
		}, { device = "keyboard", context = b.ctx or "run" })
		local _ = kb
		InputGlyphs.chip(b.action, chip, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, S(80), 0.5, 0),
			Parent = row,
		}, { device = "gamepad", context = b.ctx or "run" })
		UI.text({
			Text = b.label,
			FontFace = Theme.Fonts.display,
			TextSize = S(15),
			TextColor3 = Theme.Colors.text,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(S(124), 0),
			Size = UDim2.new(1, -S(130), 1, 0),
			Parent = row,
		})
	end
end

function InputSettingsSheet.open()
	if open then
		return
	end
	if not gui then
		build()
	end
	open = true
	table.clear(pending)
	paintRows()
	local g = gui :: ScreenGui
	g.Enabled = true
	ClientState.setBlock("settings", true)
	ClientState.lockMovement("settings", true)
	local panel = g:FindFirstChild("Panel") :: GuiObject?
	if panel then
		UI.punch(panel, 1.03, 0.2)
	end
	UI.sound(Theme.Sounds.toast, 1.1, 0.3)
end

function InputSettingsSheet.close()
	if not open then
		return
	end
	open = false
	if gui then
		gui.Enabled = false
	end
	ClientState.setBlock("settings", false)
	ClientState.lockMovement("settings", false)
end

function InputSettingsSheet.isOpen(): boolean
	return open
end

function InputSettingsSheet.init()
	GamepadNav.register("settings", { gui = { "InputSettings" } })
	ClientState.Juice:Connect(function(name: string)
		if name == "OpenInputSettings" then
			InputSettingsSheet.open()
		elseif name == "HubEnter" or name == "RunStartBegin" then
			InputSettingsSheet.close()
		end
	end)
	-- The sync came back: what was pending is now the profile's.
	ClientState.Changed:Connect(function()
		if open then
			local s = ClientState.inputSettings() :: any
			for k, v in pending do
				if s[k] == v then
					pending[k] = nil
				end
			end
			paintRows()
		end
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if not open then
			return
		end
		if (input.KeyCode == Enum.KeyCode.Escape and not gameProcessed) or input.KeyCode == Enum.KeyCode.ButtonB then
			InputSettingsSheet.close()
		end
	end)
end

return InputSettingsSheet
