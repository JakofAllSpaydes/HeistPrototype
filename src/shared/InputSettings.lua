--!strict
-- Brief 11: the INPUT settings page's values, stored on the profile under settings.input. One schema shared by the
-- server (sanitise on load, validate Remotes.SetInputSetting) and the client (defaults until the sync arrives).
local Config = require(script.Parent:WaitForChild("Config"))

local InputSettings = {}

export type Values = {
	sprintTouch: string, -- "push" (push-through) | "button" (a tap button under the stick) | "off"
	sprintPc: string, -- "hold" | "toggle" (Shift)
	sprintPad: string, -- "toggle" | "hold" (L3)
	lookSens: number, -- 1..10, 5 = GamepadLookSpeed
	invertY: boolean,
	adsToggle: boolean, -- LT / RMB / the ADS button toggles instead of holding
	aimAssist: boolean, -- gamepad and touch only (the mouse's faint assist stays)
	haptics: boolean,
	glyphs: string, -- "auto" | "playstation" | "xbox"
}

-- key -> { kind, default, choices | min / max }
InputSettings.SCHEMA = {
	sprintTouch = { kind = "choice", default = "push", choices = { "push", "button", "off" } },
	sprintPc = { kind = "choice", default = "hold", choices = { "hold", "toggle" } },
	sprintPad = { kind = "choice", default = "toggle", choices = { "toggle", "hold" } },
	lookSens = { kind = "number", default = 5, min = 1, max = 10, step = 1 },
	invertY = { kind = "boolean", default = false },
	adsToggle = { kind = "boolean", default = false },
	aimAssist = { kind = "boolean", default = true },
	haptics = { kind = "boolean", default = Config.HapticsEnabled },
	glyphs = { kind = "choice", default = "auto", choices = { "auto", "playstation", "xbox" } },
} :: { [string]: any }

-- The page's order.
InputSettings.ORDER =
	{ "sprintTouch", "sprintPc", "sprintPad", "lookSens", "invertY", "adsToggle", "aimAssist", "haptics", "glyphs" }

-- A valid value for key, or nil when the value is not allowed.
function InputSettings.sanitize(key: string, value: any): any
	local s = InputSettings.SCHEMA[key]
	if not s then
		return nil
	end
	if s.kind == "boolean" then
		return if typeof(value) == "boolean" then value else nil
	elseif s.kind == "number" then
		local n = tonumber(value)
		if not n or n ~= n then
			return nil
		end
		n = math.clamp(n, s.min, s.max)
		return math.floor(n / s.step + 0.5) * s.step
	elseif s.kind == "choice" then
		if typeof(value) ~= "string" then
			return nil
		end
		for _, c in s.choices do
			if c == value then
				return value
			end
		end
	end
	return nil
end

function InputSettings.defaults(): Values
	local out = {}
	for k, s in InputSettings.SCHEMA do
		out[k] = s.default
	end
	return (out :: any) :: Values
end

-- Defaults overlaid with whatever valid values raw holds (a saved profile, a sync).
function InputSettings.merge(raw: any): Values
	local out = InputSettings.defaults() :: any
	if typeof(raw) == "table" then
		for k in InputSettings.SCHEMA do
			local v = InputSettings.sanitize(k, raw[k])
			if v ~= nil then
				out[k] = v
			end
		end
	end
	return out :: Values
end

return InputSettings
