--!strict
-- Brief 11: "what do I press" as data, shared by InputGlyphs / Hint (client) and tests/input.spec.luau (Lune).
--   Glyphs.button(action, context)        -> the pad button (Enum.KeyCode name) for an action, or nil
--   Glyphs.keyboard(action)               -> the keyboard key cap text ("E", "SHIFT"), or nil
--   Glyphs.label(action, device, style, context) -> the text for a line of text: "E" / "□" / "" (touch)
-- Pad bindings come from GamepadMap (Config.GamepadMap); the screen buttons GamepadNav uses (select, back, tabs,
-- pages) are fixed here. Keyboard keys come from Config where Config owns them (InteractKey, AbilityKeys).
local Config = require(script.Parent:WaitForChild("Config"))
local GamepadMap = require(script.Parent:WaitForChild("GamepadMap"))

local Glyphs = {}

-- Pad buttons for the screen actions (GamepadNav), the same in every context.
Glyphs.NAV = {
	select = "ButtonA",
	back = "ButtonB",
	tabPrev = "ButtonL1",
	tabNext = "ButtonR1",
	pagePrev = "ButtonL2",
	pageNext = "ButtonR2",
} :: { [string]: string }

-- Keyboard key caps per action (nil = the action has no key: the camera view cycle is the wheel).
local function keyboardTable(): { [string]: string }
	local cfg = Config :: any
	local keys = cfg.AbilityKeys or { "Q", "F", "Z" }
	return {
		interact = cfg.InteractKey or "E",
		reload = "R",
		swap = "1",
		upgrade = "2",
		ability1 = keys[1],
		ability2 = keys[2],
		ability3 = keys[3],
		sprint = "SHIFT",
		dealerTeleport = "T",
		dealerBuy = cfg.InteractKey or "E",
		voteSkip = "V",
		pause = "P",
		scoreboard = "TAB",
		fire = "LMB",
		ads = "RMB",
		jump = "SPACE",
		debug = "`",
		back = "ESC",
		cameraFree = "CTRL",
	}
end

function Glyphs.keyboard(action: string): string?
	return keyboardTable()[action]
end

function Glyphs.button(action: string, context: string?): string?
	local nav = Glyphs.NAV[action]
	if nav then
		return nav
	end
	return GamepadMap.buttonFor(context or "run", action)
		or (if context == nil then GamepadMap.buttonFor("hub", action) else nil)
end

-- The text one pad button reads as in a line ("□", "L1", "↑").
function Glyphs.padText(button: string, style: string?): string
	local all = (Config :: any).GlyphText or {}
	local set = all[style or "playstation"] or all.playstation or {}
	return set[button] or button
end

-- The label for an action on a device: keyboard key cap, pad glyph text, or "" on touch (no key names on touch).
-- nil when the action has no input on that device.
function Glyphs.label(action: string, device: string, style: string?, context: string?): string?
	if device == "touch" then
		return ""
	elseif device == "gamepad" then
		local b = Glyphs.button(action, context)
		return if b then Glyphs.padText(b, style) else nil
	end
	return Glyphs.keyboard(action)
end

-- Fill a template's {key} with a label. An empty label (touch) drops the token and the separator after it, so
-- "{key} · OPEN" reads "OPEN" and "HOLD {key} · CUT" reads "HOLD · CUT".
function Glyphs.fmt(template: string, label: string?): string
	if label and label ~= "" then
		return (string.gsub(template, "{key}", (string.gsub(label, "%%", "%%%%"))))
	end
	local s = string.gsub(template, "{key}%s*·%s*", "")
	s = string.gsub(s, "%s*{key}", "")
	s = string.gsub(s, "{key}%s*", "")
	return s
end

-- A line built elsewhere with the keyboard's interact key in it (the server's door / beacon hints: "HOLD E · CUT",
-- "E · BREACH") rewritten with another label for the same key. Only whole-word keys change.
function Glyphs.swapKey(text: string, key: string, label: string): string
	if label == key or key == "" then
		return text
	end
	local safe = string.gsub(label, "%%", "%%%%")
	local s = string.gsub(text, "^" .. key .. "(%s)", safe .. "%1")
	s = string.gsub(s, "HOLD " .. key .. "%f[%W]", "HOLD " .. safe)
	s = string.gsub(s, "%[" .. key .. "%]", "[" .. safe .. "]")
	return s
end

-- "auto" -> playstation unless the pad's own name for ButtonA says Xbox ("ButtonA" on an Xbox pad, "ButtonCross" on
-- a PlayStation pad when Roblox reports it). `padName` is UserInputService:GetStringForKeyCode(ButtonA) or nil.
function Glyphs.style(setting: string?, padName: string?): string
	if setting == "playstation" or setting == "xbox" then
		return setting
	end
	if padName and string.find(string.lower(padName), "cross") then
		return "playstation"
	end
	return "playstation" -- the brief's default: Roblox does not name the pad reliably
end

return Glyphs
