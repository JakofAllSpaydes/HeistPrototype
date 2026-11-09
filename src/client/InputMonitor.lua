--!strict
-- Brief 11: the debug Input monitor. A panel on the left edge: the device, the live stick vectors and the look the
-- camera made of them, the X rule's state, then the last raw pad inputs and the action each resolved to. A human
-- check is one sweep: press every button once and read it here. Toggled from the debug panel's INPUT group.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GamepadMap = require(Shared:WaitForChild("GamepadMap"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local Input = require(script.Parent:WaitForChild("Input"))
local Sprint = require(script.Parent:WaitForChild("Sprint"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local InputMonitor = {}

local gui: ScreenGui? = nil
local header: TextLabel? = nil
local rows: { TextLabel } = {}
local leftDot: Frame? = nil
local rightDot: Frame? = nil
local on = false
local ROWS = 14

local function stickBox(parent: Instance, x: number, label: string): Frame
	local S = UI.S
	local box = UI.frame({
		BackgroundColor3 = Theme.Colors.bg,
		BackgroundTransparency = 0.2,
		Position = UDim2.fromOffset(x, 0),
		Size = UDim2.fromOffset(S(92), S(92)),
		Parent = parent,
	})
	UI.stroke(box, Theme.Colors.grey, S(1), 0.4)
	-- the dead zone ring
	local dz = GamepadMap.cfg("GamepadLookDeadZone")
	local ring = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(dz, dz),
		Parent = box,
	})
	UI.corner(ring, S(200))
	UI.stroke(ring, Theme.Colors.amber, S(1), 0.3)
	local dot = UI.frame({
		BackgroundColor3 = Theme.Colors.gold,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(S(12), S(12)),
		Parent = box,
	})
	UI.corner(dot, S(200))
	UI.text({
		Text = label,
		FontFace = Theme.Fonts.display,
		TextSize = S(14),
		TextColor3 = Theme.Colors.grey,
		Position = UDim2.new(0, 0, 1, S(2)),
		Size = UDim2.new(1, 0, 0, S(18)),
		Parent = box,
	})
	return dot
end

local function build()
	if gui then
		gui:Destroy()
	end
	local S = UI.S
	local g = UI.new("ScreenGui", {
		Name = "InputMonitor",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 19,
		Enabled = on,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	}) :: ScreenGui
	gui = g
	local panel = UI.frame({
		Name = "Panel",
		BackgroundColor3 = Theme.Colors.panel,
		BackgroundTransparency = 0.12,
		Position = UDim2.new(0, S(16), 0, S(120)),
		Size = UDim2.fromOffset(S(380), S(560)),
		Parent = g,
	})
	UI.stroke(panel, Theme.Colors.gold, S(1.5))
	UI.pad(panel, S(10), S(10), S(10), S(10))
	UI.text({
		Text = "INPUT MONITOR",
		FontFace = Theme.Fonts.display,
		TextSize = S(20),
		TextColor3 = Theme.Colors.gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, S(24)),
		Parent = panel,
	})
	header = UI.text({
		Text = "",
		FontFace = Theme.Fonts.body,
		TextSize = S(15),
		TextColor3 = Theme.Colors.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		RichText = true,
		Position = UDim2.fromOffset(0, S(28)),
		Size = UDim2.new(1, -S(200), 0, S(130)),
		Parent = panel,
	}) :: TextLabel
	local sticks = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, S(30)),
		Size = UDim2.fromOffset(S(192), S(112)),
		Parent = panel,
	})
	leftDot = stickBox(sticks, 0, "L STICK")
	rightDot = stickBox(sticks, S(100), "R STICK")
	rows = {}
	for i = 1, ROWS do
		local r = UI.text({
			Text = "",
			FontFace = Theme.Fonts.body,
			TextSize = S(15),
			TextColor3 = Theme.Colors.text,
			TextXAlignment = Enum.TextXAlignment.Left,
			RichText = true,
			Position = UDim2.fromOffset(0, S(150) + (i - 1) * S(27)),
			Size = UDim2.new(1, 0, 0, S(25)),
			Parent = panel,
		}) :: TextLabel
		rows[i] = r
	end
end

local function stick(key: Enum.KeyCode): Vector2
	if not UserInputService.GamepadEnabled then
		return Vector2.zero
	end
	for _, s in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
		if s.KeyCode == key then
			return Vector2.new(s.Position.X, s.Position.Y)
		end
	end
	return Vector2.zero
end

local function placeDot(dot: Frame?, v: Vector2)
	if dot then
		dot.Position = UDim2.fromScale(0.5 + v.X * 0.5, 0.5 - v.Y * 0.5)
	end
end

local function paintLog()
	local log = Input.log
	for i = 1, ROWS do
		local e = log[#log - i + 1]
		local r = rows[i]
		if r then
			if e then
				local age = os.clock() - e.t
				r.Text = string.format(
					'<font color="#9BA0A8">%s</font>  →  <font color="#F2C14E"><b>%s</b></font>',
					e.raw,
					e.action
				)
				r.TextTransparency = math.clamp((age - 6) / 10, 0, 0.6)
			else
				r.Text = ""
			end
		end
	end
end

local function lastSprint(): string
	local hist = Sprint.history
	local e = hist[#hist]
	return if e then string.format("%.2fs %s (%s)", e.sec, e.reason, e.device) else "-"
end

local acc = 0
local function paint(dt: number)
	acc += dt
	if acc < 1 / 15 then
		return
	end
	acc = 0
	local l, r = stick(Enum.KeyCode.Thumbstick1), stick(Enum.KeyCode.Thumbstick2)
	placeDot(leftDot, l)
	placeDot(rightDot, r)
	local look = ClientState.padLook
	local h = header
	if h then
		h.Text = string.format(
			"device <b>%s</b>%s\nR (%.2f, %.2f) amt %.2f\nlook yaw %+.0f°/s  pitch %+.0f°/s\nedge %.2fs  ads %s  prompt %s\nfire %s  revive %s  dealer %s\nsprint %s  last %s",
			ClientState.inputDevice,
			if Input.forcedDevice then " (forced)" else "",
			r.X,
			r.Y,
			look.amount,
			math.deg(look.yawRate),
			math.deg(look.pitchRate),
			look.edgeSec,
			if ClientState.ads then "ON" else "-",
			if ClientState.promptVisible then "UP" else "-",
			if ClientState.padFire then "HELD" else "-",
			if ClientState.reviveNearby then "NEAR" else "-",
			if ClientState.dealerActive then (if ClientState.dealerFocus then "PANEL" else "ON") else "-",
			if ClientState.sprinting then "ON" else "-",
			lastSprint()
		)
	end
end

function InputMonitor.setVisible(v: boolean)
	on = v
	if gui then
		gui.Enabled = v
	end
	if v then
		paintLog()
	end
end

function InputMonitor.visible(): boolean
	return on
end

function InputMonitor.init()
	build()
	Input.Logged:Connect(function()
		if on then
			paintLog()
		end
	end)
	RunService.RenderStepped:Connect(function(dt)
		if on then
			paint(dt)
		end
	end)
end

return InputMonitor
