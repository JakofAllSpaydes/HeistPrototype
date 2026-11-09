--!strict
-- Brief 11: the glyph for an action on the current device, as text (InputGlyphs.label) or as a drawn chip
-- (InputGlyphs.chip) that redraws itself when the device or the glyph setting changes. Chips are drawn frames in the
-- theme, not images: the PlayStation face buttons are shapes (□ ○ ✕ △ in their colours), Xbox ones letters, the
-- shoulders / triggers / sticks are labelled caps, the D-pad is a cross with the pressed arm lit, a keyboard key is
-- a key cap. On touch every chip hides (no key names on touch). The data lives in shared/Glyphs.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Signal = require(Shared:WaitForChild("Signal"))
local Glyphs = require(Shared:WaitForChild("Glyphs"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local InputGlyphs = {}

-- Fires when what a glyph shows may have changed (the device, the glyph style).
InputGlyphs.Changed = Signal.new()

local function padName(): string?
	local ok, s = pcall(function()
		return UserInputService:GetStringForKeyCode(Enum.KeyCode.ButtonA)
	end)
	return if ok and typeof(s) == "string" then s else nil
end

local currentStyle = Glyphs.style(ClientState.inputSettings().glyphs, padName())

function InputGlyphs.style(): string
	return currentStyle
end

function InputGlyphs.device(): string
	return ClientState.inputDevice
end

-- The context an action resolves in right now ("hub" outside a run).
local function context(): string
	return if ClientState.combatOff() then "hub" else "run"
end

-- Text for a line: "E" on keyboard, "□" on a pad, "" on touch; nil when the action has no input here.
function InputGlyphs.label(action: string, ctx: string?): string?
	return Glyphs.label(action, ClientState.inputDevice, currentStyle, ctx or context())
end

function InputGlyphs.button(action: string, ctx: string?): string?
	return Glyphs.button(action, ctx or context())
end

ClientState.DeviceChanged:Connect(function()
	InputGlyphs.Changed:Fire()
end)
ClientState.Changed:Connect(function()
	local s = Glyphs.style(ClientState.inputSettings().glyphs, padName())
	if s ~= currentStyle then
		currentStyle = s
		InputGlyphs.Changed:Fire()
	end
end)

------------------------------------------------------------------ drawing

local FACE = { ButtonA = true, ButtonB = true, ButtonX = true, ButtonY = true }
local DPAD = { DPadUp = true, DPadDown = true, DPadLeft = true, DPadRight = true }

local function bar(parent: Instance, w: number, h: number, x: number, y: number, rot: number, color: Color3)
	UI.frame({
		Name = "G",
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, x, 0.5, y),
		Size = UDim2.fromOffset(w, h),
		Rotation = rot,
		ZIndex = (parent :: any).ZIndex + 1,
		Parent = parent,
	})
end

-- A PlayStation face shape inside a chip of height h.
local function drawShape(chip: Frame, button: string, h: number, color: Color3)
	local t = math.max(2, math.floor(h * 0.1 + 0.5)) -- stroke weight
	local s = h * 0.46 -- shape size
	local z = chip.ZIndex + 1
	if button == "ButtonX" then -- square
		local sq = UI.frame({
			Name = "G",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(s * 0.86, s * 0.86),
			ZIndex = z,
			Parent = chip,
		})
		UI.new("UIStroke", { Color = color, Thickness = t, Parent = sq })
	elseif button == "ButtonB" then -- circle
		local d = math.floor(s + 0.5)
		local ring = UI.frame({
			Name = "G",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(d, d),
			ZIndex = z,
			Parent = chip,
		})
		UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = ring })
		UI.new("UIStroke", { Color = color, Thickness = t, Parent = ring })
	elseif button == "ButtonA" then -- cross
		bar(chip, s * 1.15, t, 0, 0, 45, color)
		bar(chip, s * 1.15, t, 0, 0, -45, color)
	else -- ButtonY: triangle, three bars round the centroid
		local side = s * 1.05
		local th = side * math.sqrt(3) / 2
		bar(chip, side, t, 0, th / 3, 0, color)
		bar(chip, side, t, -side / 4, -th / 6, -60, color)
		bar(chip, side, t, side / 4, -th / 6, 60, color)
	end
end

-- A D-pad cross with one arm lit.
local function drawDpad(chip: Frame, button: string, h: number)
	local arm = h * 0.62
	local t = math.max(3, math.floor(h * 0.2 + 0.5))
	bar(chip, arm, t, 0, 0, 0, Theme.Colors.grey)
	bar(chip, t, arm, 0, 0, 0, Theme.Colors.grey)
	local half = arm / 2
	local seg = half - t / 2
	local lit = Theme.Colors.gold
	if button == "DPadUp" then
		bar(chip, t, seg, 0, -(t / 2 + seg / 2), 0, lit)
	elseif button == "DPadDown" then
		bar(chip, t, seg, 0, t / 2 + seg / 2, 0, lit)
	elseif button == "DPadLeft" then
		bar(chip, seg, t, -(t / 2 + seg / 2), 0, 0, lit)
	else
		bar(chip, seg, t, t / 2 + seg / 2, 0, 0, lit)
	end
end

local function chipText(chip: Frame, text: string, h: number, color: Color3)
	UI.text({
		Name = "G",
		Text = text,
		FontFace = Theme.Fonts.display,
		TextSize = math.floor(h * (if #text <= 2 then 0.6 else 0.5)),
		TextColor3 = color,
		Size = UDim2.fromScale(1, 1),
		ZIndex = chip.ZIndex + 1,
		Parent = chip,
	})
end

export type ChipOpts = {
	context: string?, -- resolve the pad button in this context (default: the current one)
	padOnly: boolean?, -- hidden on keyboard too (a pad-only hint)
	keyboardText: string?, -- override the key cap text on keyboard
	button: string?, -- draw this pad button instead of resolving an action
	device: string?, -- draw for this device whatever is in use (the CONTROLS list shows both)
}

local function widthFor(text: string, h: number): number
	if #text <= 2 then
		return h
	end
	return math.floor(h * 0.36 * utf8.len(text) :: number + h * 0.6)
end

-- Redraw `chip` (height h) for the current device. Returns whether it is visible.
local function redraw(chip: Frame, action: string, h: number, opts: ChipOpts): boolean
	for _, c in chip:GetChildren() do
		if c.Name == "G" then
			c:Destroy()
		end
	end
	local stroke = chip:FindFirstChild("Edge") :: UIStroke?
	local device = opts.device or ClientState.inputDevice
	if device == "touch" then
		chip.Visible = false
		return false
	end
	if device == "gamepad" then
		local b = opts.button or InputGlyphs.button(action, opts.context)
		if not b then
			chip.Visible = false
			return false
		end
		chip.Visible = true
		chip.BackgroundColor3 = Theme.Colors.bg
		if stroke then
			stroke.Color = Theme.Colors.grey
		end
		if FACE[b] then
			chip.Size = UDim2.fromOffset(h, h)
			local corner = chip:FindFirstChildOfClass("UICorner")
			if corner then
				corner.CornerRadius = UDim.new(0.5, 0)
			end
			local hex = ((Config :: any).GlyphColors[currentStyle] or {})[b] or "F2E6C8"
			local color = Color3.fromHex(hex)
			if currentStyle == "xbox" then
				chipText(chip, Glyphs.padText(b, "xbox"), h, color)
			else
				drawShape(chip, b, h, color)
			end
			return true
		end
		local corner = chip:FindFirstChildOfClass("UICorner")
		if corner then
			corner.CornerRadius = UDim.new(0, UI.S(Theme.Corner))
		end
		if DPAD[b] then
			chip.Size = UDim2.fromOffset(h, h)
			drawDpad(chip, b, h)
			return true
		end
		local text = Glyphs.padText(b, currentStyle)
		chip.Size = UDim2.fromOffset(widthFor(text, h), h)
		chipText(chip, text, h, Theme.Colors.text)
		return true
	end
	-- keyboard
	local key = opts.keyboardText or Glyphs.keyboard(action)
	if opts.padOnly or not key then
		chip.Visible = false
		return false
	end
	chip.Visible = true
	chip.BackgroundColor3 = Theme.Colors.panel2
	local corner = chip:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(0, UI.S(Theme.Corner))
	end
	if stroke then
		stroke.Color = Theme.Colors.grey
	end
	chip.Size = UDim2.fromOffset(widthFor(key, h), h)
	chipText(chip, key, h, Theme.Colors.text)
	return true
end

-- A self-updating glyph chip `h` px tall (already scaled). Width follows the glyph (square for one symbol). Extra
-- props (Position, AnchorPoint, LayoutOrder, ZIndex, Parent...) go straight onto the frame. Lives until destroyed.
function InputGlyphs.chip(action: string, h: number, props: { [string]: any }?, opts: ChipOpts?): Frame
	local o: ChipOpts = opts or {}
	local p: { [string]: any } =
		{ Name = "Glyph", BackgroundColor3 = Theme.Colors.panel2, Size = UDim2.fromOffset(h, h) }
	for k, v in props or {} do
		p[k] = v
	end
	local chip = UI.frame(p)
	UI.new("UICorner", { CornerRadius = UDim.new(0, UI.S(Theme.Corner)), Parent = chip })
	local edge = UI.new("UIStroke", {
		Name = "Edge",
		Color = Theme.Colors.grey,
		Thickness = math.max(1, UI.S(1)),
		Transparency = 0.4,
		Parent = chip,
	})
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	chip:SetAttribute("GlyphAction", action)
	redraw(chip, action, h, o)
	local conn = InputGlyphs.Changed:Connect(function()
		redraw(chip, chip:GetAttribute("GlyphAction") :: string, h, o)
	end)
	chip.Destroying:Connect(function()
		conn:Disconnect()
	end)
	return chip
end

-- Redraw an existing chip for another action (an ability tile when the class changes).
function InputGlyphs.rebind(chip: Frame, action: string, h: number, opts: ChipOpts?)
	chip:SetAttribute("GlyphAction", action)
	redraw(chip, action, h, opts or {})
end

return InputGlyphs
