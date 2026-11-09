--!strict
-- Brief 11: one place that formats "{glyph} OPEN" lines, so screens never hand-build key names.
--   Hint.text("{key} TO SKIP", "voteSkip")  -> "V TO SKIP" / "↓ TO SKIP" / "TO SKIP" (touch)
--   Hint.bind(label, fn)                     -> label.Text = fn() now and whenever the device / glyph style changes
--   Hint.swap(text)                          -> a line with the keyboard interact key in it ("HOLD E · CUT", from the
--                                               server) with the current device's key; touch lines stay as they are
--   Hint.row(action, words, h, props)        -> a drawn glyph chip + caps text, for hints that sit on their own
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Glyphs = require(Shared:WaitForChild("Glyphs"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local InputGlyphs = require(script.Parent:WaitForChild("InputGlyphs"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local Hint = {}

Hint.Changed = InputGlyphs.Changed

function Hint.key(action: string, ctx: string?): string?
	return InputGlyphs.label(action, ctx)
end

function Hint.text(template: string, action: string, ctx: string?): string
	return Glyphs.fmt(template, InputGlyphs.label(action, ctx))
end

function Hint.swap(text: string): string
	local device = ClientState.inputDevice
	if device ~= "gamepad" then
		return text
	end
	local label = InputGlyphs.label("interact")
	if not label then
		return text
	end
	return Glyphs.swapKey(text, (Config :: any).InteractKey or "E", label)
end

function Hint.gamepad(): boolean
	return ClientState.inputDevice == "gamepad"
end

-- Keep a label's text current: fn runs now and on every device / style change until the label is destroyed.
function Hint.bind(label: TextLabel | TextButton, fn: () -> string)
	label.Text = fn()
	local conn = InputGlyphs.Changed:Connect(function()
		if label.Parent then
			label.Text = fn()
		end
	end)
	label.Destroying:Connect(function()
		conn:Disconnect()
	end)
end

-- Run fn now and on every device / style change for as long as `owner` lives (layout swaps, not just text).
function Hint.watch(owner: Instance, fn: () -> ())
	fn()
	local conn = InputGlyphs.Changed:Connect(fn)
	owner.Destroying:Connect(function()
		conn:Disconnect()
	end)
end

-- A row: [glyph] WORDS, h px tall, auto-width. Hidden whole on touch (and on keyboard when opts.padOnly).
function Hint.row(
	action: string,
	words: string,
	h: number,
	props: { [string]: any }?,
	opts: InputGlyphs.ChipOpts?
): (Frame, TextLabel)
	local p: { [string]: any } = {
		Name = "Hint",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, h),
	}
	for k, v in props or {} do
		p[k] = v
	end
	local row = UI.frame(p)
	UI.list(row, Enum.FillDirection.Horizontal, math.floor(h * 0.3), nil, Enum.VerticalAlignment.Center)
	local chip = InputGlyphs.chip(action, h, { LayoutOrder = 1, ZIndex = p.ZIndex or 1, Parent = row }, opts)
	local label = UI.text({
		Text = words,
		FontFace = Theme.Fonts.display,
		TextSize = math.floor(h * 0.72),
		TextColor3 = Theme.Colors.text,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, h),
		LayoutOrder = 2,
		ZIndex = p.ZIndex or 1,
		Parent = row,
	}) :: TextLabel
	local function vis()
		row.Visible = chip.Visible
	end
	Hint.watch(row, vis)
	return row, label
end

return Hint
