--!strict
-- Shared minigame panel: centered, crew-call frame style (dark at 92%, 2px colored border, LuckiestGuy
-- title, one-line hint, elapsed timer top-right, X). Owns input blocking, the result sent to the server,
-- the damage shake and the downed fail. A game draws into host.content and calls host.finish.
local HapticService = game:GetService("HapticService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Client = script.Parent.Parent
local ClientState = require(Client:WaitForChild("ClientState"))
local Haptics = require(Client:WaitForChild("Haptics"))
local InputGlyphs = require(Client:WaitForChild("InputGlyphs"))
local Glyphs = require(Shared:WaitForChild("Glyphs"))
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))

export type Host = {
	content: Frame, -- the play area, clipped
	panel: Frame,
	width: number, -- play area size in px
	height: number,
	tier: number,
	u: (number) -> number, -- design px (400 wide basis) -> screen px
	setHint: (string, Color3?) -> (),
	miss: () -> (), -- counts a miss and shakes the panel
	finish: (string) -> (), -- "done" | "fail": stamps, then closes and reports
	stamp: (string, Color3) -> (),
	haptic: (number) -> (),
	alive: () -> boolean,
	track: (RBXScriptConnection) -> RBXScriptConnection,
	onClose: (() -> ())?,
	-- Round 24 (mobile only): an invisible band around the panel, clear of the screen's left / right edges, that
	-- whole-area games pass to Frame.press / Frame.drag as an extra handle so a thumb need not land inside the box.
	zone: GuiObject?,
	-- Brief 11 step 5: the pad path, a third input into the same game state (set it in open).
	pad: PadSpec?,
}

-- A pad button edge reaches the game here (ButtonA / B / X / Y, the D-pad, L1 / R1, and ButtonL2 / ButtonR2 past
-- GamepadTriggerPress). Return true when the game used it; an unused B cancels the game (walking away). Sticks and
-- trigger depth are polled with Frame.stick / Frame.trigger. navWalk hands the D-pad, left stick and A to
-- GamepadNav so the pad walks the game's own buttons (Keypad, Charges).
export type PadSpec = {
	button: ((key: string, down: boolean) -> boolean?)?,
	navWalk: boolean?,
}

export type GameSpec = {
	title: string,
	hint: string,
	color: Color3,
	aspect: number, -- play area height / width
	open: (Host) -> (),
	padHint: string?, -- brief 11: the instruction line on a pad; {ButtonA}-style tokens become the glyph text
}

type Active = {
	token: number,
	name: string,
	host: Host,
	gui: ScreenGui,
	stroke: UIStroke,
	hint: TextLabel,
	timer: TextLabel,
	misses: number,
	startedAt: number,
	closed: boolean,
	connections: { RBXScriptConnection },
	origin: Vector3?, -- the prop; walking past MinigameCloseDistance from it closes the panel
	leavingAt: number?, -- Round 19i: when the player first went out of range (the cancel waits MinigameWalkAwayGraceSec)
}

local Frame = {}

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local camera = Workspace.CurrentCamera :: Camera
local active: Active? = nil
local trigHeld: { [string]: boolean } = {} -- brief 11: the triggers past the press depth (pad edges)
local DESIGN_WIDTH = 400

local function supportsHaptics(inputType: Enum.UserInputType): boolean
	local ok, supported = pcall(function()
		return HapticService:IsVibrationSupported(inputType)
	end)
	return ok and supported == true
end

-- A short pulse on whatever can vibrate (phone or gamepad). strength 0..1.
function Frame.haptic(strength: number)
	if not Config.MinigameHaptics then
		return
	end
	for _, inputType in { Enum.UserInputType.Touch, Enum.UserInputType.Gamepad1 } do
		if supportsHaptics(inputType) then
			pcall(function()
				HapticService:SetMotor(inputType, Enum.VibrationMotor.Small, strength)
				HapticService:SetMotor(inputType, Enum.VibrationMotor.Large, strength * 0.6)
			end)
			task.delay(0.08 + strength * 0.08, function()
				pcall(function()
					HapticService:SetMotor(inputType, Enum.VibrationMotor.Small, 0)
					HapticService:SetMotor(inputType, Enum.VibrationMotor.Large, 0)
				end)
			end)
		end
	end
end

local function isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function handleList(h: GuiObject | { GuiObject? }): { GuiObject }
	if typeof(h) == "Instance" then
		return { h :: GuiObject }
	end
	local out: { GuiObject } = {}
	for _, g in pairs(h :: { GuiObject? }) do
		if g then
			table.insert(out, g)
		end
	end
	return out
end

-- Tap: fires on press (not release) so timing games feel immediate. Touch and mouse share it.
-- `gui` may be a list (the play area plus host.zone); one press counts once even if two of them see it.
function Frame.press(host: Host, gui: GuiObject | { GuiObject? }, fn: (Vector2) -> ())
	local last: InputObject? = nil
	for _, g in handleList(gui) do
		g.Active = true
		host.track(g.InputBegan:Connect(function(input: InputObject)
			if input == last and input.UserInputType == Enum.UserInputType.Touch then
				return
			end
			if isPress(input) and host.alive() then
				last = input
				fn(Vector2.new(input.Position.X, input.Position.Y))
			end
		end))
	end
end

-- Drag: press on `handle`, move anywhere, release. One path for touch and mouse. Returns a release function
-- that drops the current hold (no onEnd), so a game can make the player press again (Freq after a lock).
function Frame.drag(
	host: Host,
	handle: GuiObject | { GuiObject? },
	onStart: (Vector2) -> (),
	onMove: (Vector2) -> (),
	onEnd: (Vector2) -> ()
): () -> ()
	local current: InputObject? = nil
	for _, g in handleList(handle) do
		g.Active = true
		host.track(g.InputBegan:Connect(function(input: InputObject)
			if current or not isPress(input) or not host.alive() then
				return
			end
			current = input
			onStart(Vector2.new(input.Position.X, input.Position.Y))
		end))
	end
	host.track(UserInputService.InputChanged:Connect(function(input: InputObject)
		local c = current
		if not c then
			return
		end
		if c.UserInputType == Enum.UserInputType.Touch then
			if input ~= c then
				return
			end
		elseif input.UserInputType ~= Enum.UserInputType.MouseMovement then
			return
		end
		onMove(Vector2.new(input.Position.X, input.Position.Y))
	end))
	host.track(UserInputService.InputEnded:Connect(function(input: InputObject)
		local c = current
		if not c then
			return
		end
		local same = if c.UserInputType == Enum.UserInputType.Touch
			then input == c
			else input.UserInputType == Enum.UserInputType.MouseButton1
		if same then
			current = nil
			onEnd(Vector2.new(input.Position.X, input.Position.Y))
		end
	end))
	return function()
		current = nil
	end
end

-- Straight line between two points in content-local px. Rotation pivots on the frame center, so the
-- line is placed by its midpoint.
function Frame.line(parent: Instance, a: Vector2, b: Vector2, thickness: number, color: Color3, zIndex: number?): Frame
	local line = UI.frame({
		BackgroundColor3 = color,
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = zIndex or 3,
		Parent = parent,
	})
	UI.corner(line, math.max(1, math.floor(thickness / 2)))
	Frame.setLine(line, a, b, thickness)
	return line
end

function Frame.setLine(line: Frame, a: Vector2, b: Vector2, thickness: number)
	local d = b - a
	local mid = (a + b) / 2
	line.Position = UDim2.fromOffset(mid.X, mid.Y)
	line.Size = UDim2.fromOffset(math.max(1, d.Magnitude), thickness)
	line.Rotation = math.deg(math.atan2(d.Y, d.X))
end

-- Center of a GuiObject in content-local px.
function Frame.centerOf(host: Host, gui: GuiObject): Vector2
	return gui.AbsolutePosition + gui.AbsoluteSize / 2 - host.content.AbsolutePosition
end

-- The topmost GuiObject under a screen point that satisfies `match`, or nil.
function Frame.hit(point: Vector2, match: (GuiObject) -> boolean): GuiObject?
	local list = playerGui:GetGuiObjectsAtPosition(point.X, point.Y)
	for _, gui in list do
		if match(gui) then
			return gui
		end
	end
	return nil
end

local function sendResult(a: Active, outcome: string)
	-- Brief 11: the device rides along so debug Stats can split the averages by it.
	Remotes.MinigameResult:FireServer(a.token, outcome, a.misses, ClientState.inputDevice)
end

------------------------------------------------------------------ brief 11 step 5: the pad

-- A stick (1 = left, 2 = right) as (x, y), y up; zero when no pad.
function Frame.stick(n: number): Vector2
	if not UserInputService.GamepadEnabled then
		return Vector2.zero
	end
	local want = if n == 2 then Enum.KeyCode.Thumbstick2 else Enum.KeyCode.Thumbstick1
	for _, s in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
		if s.KeyCode == want then
			return Vector2.new(s.Position.X, s.Position.Y)
		end
	end
	return Vector2.zero
end

-- A trigger's depth 0..1 ("ButtonR2" / "ButtonL2").
function Frame.trigger(key: string): number
	if not UserInputService.GamepadEnabled then
		return 0
	end
	for _, s in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
		if s.KeyCode.Name == key then
			return math.clamp(s.Position.Z, 0, 1)
		end
	end
	return 0
end

function Frame.onPad(): boolean
	return ClientState.inputDevice == "gamepad"
end

-- A rumble on the pad only (the zone ticks, tumblers, shocks), off with the vibration setting.
function Frame.padHaptic(strength: number, sec: number?, motor: string?)
	if ClientState.inputDevice ~= "gamepad" then
		return
	end
	Haptics.pulse({ motor = motor or "Small", strength = strength, sec = sec or 0.05 })
end

-- "{ButtonA} ON THE MARK" -> "✕ ON THE MARK" in the current glyph style.
function Frame.padText(template: string): string
	return (
		string.gsub(template, "{(%w+)}", function(button: string)
			return Glyphs.padText(button, InputGlyphs.style())
		end)
	)
end

local function destroy(a: Active)
	for _, c in a.connections do
		c:Disconnect()
	end
	a.connections = {}
	if a.host.onClose then
		pcall(a.host.onClose)
	end
	a.gui:Destroy()
	if active == a then
		active = nil
		ClientState.setBlock("minigame", false)
	end
end

local function stampOn(a: Active, text: string, color: Color3)
	local u = a.host.u
	local label = UI.text({
		Text = text,
		FontFace = Theme.Fonts.display,
		TextSize = u(56),
		TextColor3 = color,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 0, 0, u(70)),
		Rotation = -6,
		ZIndex = 20,
		Parent = a.host.content,
	})
	UI.stroke(label, Theme.Colors.black, u(3), 0.2)
	UI.punch(label, 1.8, 0.35)
	UI.sound(Theme.Sounds.reelLand, 0.9, 0.5)
end

function Frame.isOpen(): boolean
	return active ~= nil
end

function Frame.close(outcome: string)
	local a = active
	if not a or a.closed then
		return
	end
	a.closed = true
	sendResult(a, outcome)
	destroy(a)
end

function Frame.open(name: string, spec: GameSpec, tier: number, token: number, origin: Vector3?)
	if active then
		Frame.close("cancel")
	end
	table.clear(trigHeld)
	local vp = camera.ViewportSize
	local short = math.min(vp.X, vp.Y)
	local width = math.floor(short * Config.MinigamePanelPct)
	local headerH = math.floor(width * 0.17)
	local pad = math.floor(width * 0.03)
	local contentH = math.floor(width * spec.aspect)
	local totalH = headerH + contentH + pad
	-- Tall games on a wide screen: shrink to fit the height.
	local maxH = vp.Y * 0.92
	if totalH > maxH then
		local k = maxH / totalH
		width = math.floor(width * k)
		headerH = math.floor(headerH * k)
		pad = math.floor(pad * k)
		contentH = math.floor(contentH * k)
		totalH = headerH + contentH + pad
	end
	local unit = width / DESIGN_WIDTH
	local function u(n: number): number
		return math.round(n * unit)
	end

	local gui = UI.new("ScreenGui", {
		Name = "Minigame_" .. name,
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 10,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	}) :: ScreenGui
	local panel = UI.frame({
		Name = "Panel",
		BackgroundColor3 = Theme.Colors.bg,
		BackgroundTransparency = 0.08,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, u(30)),
		Size = UDim2.fromOffset(width, totalH),
		Active = true,
		Parent = gui,
	})
	UI.corner(panel, u(14))
	local stroke = UI.stroke(panel, spec.color, math.max(2, u(2)))
	UI.tween(panel, { Position = UDim2.fromScale(0.5, 0.5) }, 0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	UI.punch(panel, 0.92, 0.25)

	UI.text({
		Text = spec.title,
		FontFace = Theme.Fonts.display,
		TextSize = u(26),
		TextColor3 = spec.color,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(u(16), u(8)),
		Size = UDim2.new(1, -u(140), 0, u(32)),
		Parent = panel,
	})
	local hint = UI.text({
		Text = spec.hint,
		TextSize = u(12),
		TextColor3 = Theme.Colors.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(u(16), u(40)),
		Size = UDim2.new(1, -u(140), 0, u(18)),
		Parent = panel,
	})
	local timer = UI.text({
		Text = "0.0s",
		FontFace = Theme.Fonts.mono,
		TextSize = u(14),
		TextColor3 = Theme.Colors.textDim,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -u(56), 0, u(14)),
		Size = UDim2.fromOffset(u(80), u(20)),
		Parent = panel,
	})
	local closeBtn = UI.button({
		Text = "X",
		FontFace = Theme.Fonts.display,
		TextSize = u(18),
		TextColor3 = Theme.Colors.grey,
		BackgroundColor3 = Theme.Colors.panel2,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -u(10), 0, u(10)),
		Size = UDim2.fromOffset(u(34), u(34)),
		Parent = panel,
	})
	UI.corner(closeBtn, u(8))
	UI.stroke(closeBtn, Theme.Colors.grey, u(1), 0.5)
	closeBtn:SetAttribute("NavSkip", true) -- brief 11: B is the pad's way out
	local content = UI.frame({
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, headerH),
		Size = UDim2.fromOffset(width, contentH),
		ClipsDescendants = true,
		Parent = panel,
	})

	-- Round 24: the mobile touch band, behind the panel (Sibling ZIndex 0) so the panel's own buttons win.
	local zone: GuiObject? = nil
	if ClientState.isMobile then
		local edge = Config.MinigameTouchEdgePct
		local top = Config.MinigameTouchTopPct
		zone = UI.button({
			Name = "TouchZone",
			Text = "",
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Position = UDim2.fromScale(edge, top),
			Size = UDim2.fromScale(1 - edge * 2, 1 - top),
			ZIndex = 0,
			Parent = gui,
		})
	end

	local connections: { RBXScriptConnection } = {}
	local a: Active
	local host: Host = {
		zone = zone,
		content = content,
		panel = panel,
		width = width,
		height = contentH,
		tier = tier,
		u = u,
		setHint = function(text: string, color: Color3?)
			hint.Text = text
			hint.TextColor3 = color or Theme.Colors.textDim
		end,
		miss = function()
			if a.closed then
				return
			end
			a.misses += 1
			UI.shake(panel, u(4), 0.18)
			stroke.Color = Theme.Colors.red
			UI.tween(stroke, { Color = spec.color }, 0.35)
			UI.sound(Theme.Sounds.deny, 0.9, 0.35)
			Frame.haptic(0.4)
		end,
		finish = function(outcome: string)
			if a.closed then
				return
			end
			a.closed = true
			if outcome == "done" then
				stampOn(a, "DONE", Theme.Colors.cash)
				stroke.Color = Theme.Colors.cash
				UI.sound(Theme.Sounds.legendary, 1.2, 0.5)
				Frame.haptic(1)
			else
				stampOn(a, "FAILED", Theme.Colors.red)
				stroke.Color = Theme.Colors.red
				UI.sound(Theme.Sounds.deny, 0.7, 0.5)
			end
			sendResult(a, outcome)
			-- You are likely mid-combat: the gun and camera come back at once, and the panel slides off
			-- under the stamp instead of holding.
			if active == a then
				active = nil
				ClientState.setBlock("minigame", false)
			end
			local exit = math.max(Config.MinigameExitSec, 0.05)
			UI.tween(
				panel,
				{ Position = UDim2.new(0.5, 0, 0.5, u(140)), BackgroundTransparency = 1 },
				exit,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.In
			)
			UI.tween(stroke, { Transparency = 1 }, exit)
			task.delay(exit, function()
				destroy(a)
			end)
		end,
		stamp = function(text: string, color: Color3)
			stampOn(a, text, color)
		end,
		haptic = Frame.haptic,
		alive = function()
			return not a.closed
		end,
		track = function(c: RBXScriptConnection)
			table.insert(connections, c)
			return c
		end,
		onClose = nil,
	}
	a = {
		token = token,
		name = name,
		host = host,
		gui = gui,
		stroke = stroke,
		hint = hint,
		timer = timer,
		misses = 0,
		startedAt = os.clock(),
		closed = false,
		connections = connections,
		origin = origin,
	}
	active = a
	ClientState.setBlock("minigame", true)
	closeBtn.Activated:Connect(function()
		Frame.close("cancel")
	end)
	local player = Players.LocalPlayer
	host.track(RunService.Heartbeat:Connect(function()
		if a.closed then
			return
		end
		timer.Text = string.format("%.1fs", os.clock() - a.startedAt)
		-- Walked away from the prop: the panel closes as a cancel. Round 19i: only after MinigameWalkAwayGraceSec out
		-- of range, so a game already on its winning beat (the short success animation before DONE) still completes
		-- when you start walking off as you solve it; stepping back in range keeps it open.
		local from = a.origin
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if from and root and root:IsA("BasePart") then
			if (root.Position - from).Magnitude > Config.MinigameCloseDistance then
				local leftAt = a.leavingAt
				if not leftAt then
					a.leavingAt = os.clock()
					hint.Text = "TOO FAR FROM THE PROP"
					hint.TextColor3 = Theme.Colors.malus
				elseif os.clock() - leftAt >= Config.MinigameWalkAwayGraceSec then
					Frame.close("cancel")
				end
			else
				a.leavingAt = nil
			end
		end
	end))
	UI.sound(Theme.Sounds.call, 1.1, 0.4)
	spec.open(host)
	-- Brief 11: the pad's instruction line (and back to the mouse / touch one if the device changes mid-game).
	local function padLine()
		if a.closed or not spec.padHint then
			return
		end
		local padText = Frame.padText(spec.padHint)
		if Frame.onPad() and hint.Text == spec.hint then
			hint.Text = padText
		elseif not Frame.onPad() and hint.Text == padText then
			hint.Text = spec.hint
		end
	end
	padLine()
	host.track(ClientState.DeviceChanged:Connect(padLine))
	if host.pad and host.pad.navWalk then
		gui:SetAttribute("NavWalk", true)
	end
end

-- Brief 11: every pad input goes to the open game (above the combat map and GamepadNav), so a game never jumps,
-- fires or walks the character; B cancels unless the game uses it.
local WALK: { [string]: boolean } =
	{ DPadUp = true, DPadDown = true, DPadLeft = true, DPadRight = true, ButtonA = true, Thumbstick1 = true }
local function onPadInput(_name: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	local a = active
	if not a or a.closed or string.sub(input.UserInputType.Name, 1, 7) ~= "Gamepad" then
		return Enum.ContextActionResult.Pass
	end
	local key = input.KeyCode.Name
	local pad = a.host.pad
	if pad and pad.navWalk and WALK[key] then
		return Enum.ContextActionResult.Pass -- GamepadNav walks the game's buttons, Roblox's A presses them
	end
	if key == "Thumbstick1" or key == "Thumbstick2" then
		return Enum.ContextActionResult.Sink -- polled by the game (Frame.stick); the character stays put
	end
	local down: boolean? = nil
	if key == "ButtonL2" or key == "ButtonR2" then
		local z = input.Position.Z
		local pressed = if state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel
			then false
			elseif state == Enum.UserInputState.Begin and z == 0 then true
			else z >= Config.GamepadTriggerPress
		if pressed ~= (trigHeld[key] == true) then
			trigHeld[key] = pressed
			down = pressed
		end
	elseif state == Enum.UserInputState.Begin then
		down = true
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		down = false
	end
	if down ~= nil then
		local used = pad and pad.button and pad.button(key, down)
		if not used and key == "ButtonB" and down then
			Frame.close("cancel")
		end
	end
	return Enum.ContextActionResult.Sink
end

function Frame.init()
	local ContextActionService = game:GetService("ContextActionService")
	ContextActionService:BindActionAtPriority(
		"GHSMinigame",
		onPadInput,
		false,
		Enum.ContextActionPriority.High.Value + 40,
		Enum.KeyCode.ButtonA,
		Enum.KeyCode.ButtonB,
		Enum.KeyCode.ButtonX,
		Enum.KeyCode.ButtonY,
		Enum.KeyCode.ButtonL1,
		Enum.KeyCode.ButtonR1,
		Enum.KeyCode.ButtonL2,
		Enum.KeyCode.ButtonR2,
		Enum.KeyCode.ButtonL3,
		Enum.KeyCode.ButtonR3,
		Enum.KeyCode.DPadUp,
		Enum.KeyCode.DPadDown,
		Enum.KeyCode.DPadLeft,
		Enum.KeyCode.DPadRight,
		Enum.KeyCode.Thumbstick1,
		Enum.KeyCode.Thumbstick2
	)
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or not active then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.X then
			Frame.close("cancel")
		end
	end)
	ClientState.Juice:Connect(function(name: string)
		local a = active
		if not a then
			return
		end
		if name == "PlayerHit" and not a.closed then
			UI.shake(a.host.panel, a.host.u(Config.PanelShakePx * 2), 0.2)
		elseif name == "Downed" then
			-- Being downed closes the game as a fail.
			if not a.closed then
				a.closed = true
				sendResult(a, "fail")
				destroy(a)
			end
		end
	end)
end

return Frame
