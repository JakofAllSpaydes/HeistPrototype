--!strict
-- Brief 11: one place that formats "{glyph} OPEN" lines, so screens never hand-build key names.
--   Hint.text("{key} TO SKIP", "voteSkip")  -> "V TO SKIP" / "↓ TO SKIP" / "TO SKIP" (touch)
--   Hint.bind(label, fn)                     -> label.Text = fn() now and whenever the device / glyph style changes
--   Hint.swap(text)                          -> a line with the keyboard interact key in it ("HOLD E · CUT", from the
--                                               server) with the current device's key; touch lines stay as they are
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Glyphs = require(Shared:WaitForChild("Glyphs"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local InputGlyphs = require(script.Parent:WaitForChild("InputGlyphs"))

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

return Hint
