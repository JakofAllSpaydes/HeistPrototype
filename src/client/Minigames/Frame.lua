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
}

export type GameSpec = {
	title: string,
	hint: string,
	color: Color3,
	aspect: number, -- play area height / width
	open: (Host) -> (),
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
}

local Frame = {}

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local camera = Workspace.CurrentCamera :: Camera
local active: Active? = nil
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

-- Tap: fires on press (not release) so timing games feel immediate. Touch and mouse share it.
function Frame.press(host: Host, gui: GuiObject, fn: (Vector2) -> ())
	gui.Active = true
	host.track(gui.InputBegan:Connect(function(input: InputObject)
		if isPress(input) and host.alive() then
			fn(Vector2.new(input.Position.X, input.Position.Y))
		end
	end))
end

-- Drag: press on `handle`, move anywhere, release. One path for touch and mouse.
function Frame.drag(
	host: Host,
	handle: GuiObject,
	onStart: (Vector2) -> (),
	onMove: (Vector2) -> (),
	onEnd: (Vector2) -> ()
)
	handle.Active = true
	local current: InputObject? = nil
	host.track(handle.InputBegan:Connect(function(input: InputObject)
		if current or not isPress(input) or not host.alive() then
			return
		end
		current = input
		onStart(Vector2.new(input.Position.X, input.Position.Y))
	end))
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
end

local function sendResult(a: Active, outcome: string)
	Remotes.MinigameResult:FireServer(a.token, outcome, a.misses)
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
		Font = Theme.Fonts.display,
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

function Frame.open(name: string, spec: GameSpec, tier: number, token: number)
	if active then
		Frame.close("cancel")
	end
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
		Font = Theme.Fonts.display,
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
		Font = Theme.Fonts.mono,
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
		Font = Theme.Fonts.display,
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
	local content = UI.frame({
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, headerH),
		Size = UDim2.fromOffset(width, contentH),
		ClipsDescendants = true,
		Parent = panel,
	})

	local connections: { RBXScriptConnection } = {}
	local a: Active
	local host: Host = {
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
				UI.shake(panel, u(5), 0.25)
			end
			sendResult(a, outcome)
			task.delay(0.7, function()
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
	}
	active = a
	ClientState.setBlock("minigame", true)
	closeBtn.Activated:Connect(function()
		Frame.close("cancel")
	end)
	host.track(RunService.Heartbeat:Connect(function()
		if not a.closed then
			timer.Text = string.format("%.1fs", os.clock() - a.startedAt)
		end
	end))
	UI.sound(Theme.Sounds.call, 1.1, 0.4)
	spec.open(host)
end

function Frame.init()
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
