--!strict
-- Brief 11: the gamepad's pure logic, shared by Input.lua (client) and tests/input.spec.luau (Lune). No Roblox
-- services in here: inputs are InputObject-shaped tables read by enum *names*, so a real InputObject and a test's
-- synthetic one go through the same code.
--   GamepadMap.resolve(context, keyName)  -> the bound action (Config.GamepadMap) or nil
--   GamepadMap.newRouter()                -> router:input(obj, ctx, now) / router:tick(ctx, now): emitted actions
--   GamepadMap.look(...)                  -> the right stick's yaw / pitch rates (dead zone, curve, accel, ADS)
--   GamepadMap.deviceOf / newDeviceTracker -> which device an input means, with the switch debounce
local Config = require(script.Parent:WaitForChild("Config"))

local GamepadMap = {}

-- Live overrides (the debug panel's sliders): a key set here wins over Config until cleared.
GamepadMap.live = {} :: { [string]: any }

local function cfg(key: string): any
	local v = GamepadMap.live[key]
	if v ~= nil then
		return v
	end
	return (Config :: any)[key]
end
GamepadMap.cfg = cfg

export type Ctx = {
	context: string, -- "run" (a run or the range) | "hub"
	promptVisible: boolean?, -- a ProximityPrompt is showing: X is the prompt
	reviveNearby: boolean?, -- a downed teammate in reach: X holds the revive
	dealerActive: boolean?, -- the dealer break is on
	dealerPanel: boolean?, -- a dealer stand's panel is open and focused: A buys it
	intermission: boolean?, -- between waves: D-pad down votes to skip
	adsToggle: boolean?, -- settings: LT toggles ADS instead of holding
	blocked: boolean?, -- a screen is open (GamepadNav owns the pad): combat actions do nothing
}

export type Emit = { action: string, phase: string } -- phase: "begin" | "end" | "tap"

-- Actions that only make sense with no screen open.
local COMBAT: { [string]: boolean } = {
	fire = true,
	ads = true,
	reload = true,
	swap = true,
	ability1 = true,
	ability2 = true,
	ability3 = true,
	sprint = true,
	dealerTeleport = true,
	voteSkip = true,
	dealerPrev = true,
	dealerNext = true,
	scoreboard = true,
}
GamepadMap.COMBAT = COMBAT

function GamepadMap.resolve(context: string, keyName: string): string?
	local map = (cfg("GamepadMap") :: any)[context]
	return if map then map[keyName] else nil
end

-- The button an action is bound to in a context (glyphs, the settings list), or nil.
function GamepadMap.buttonFor(context: string, action: string): string?
	local map = (cfg("GamepadMap") :: any)[context]
	if not map then
		return nil
	end
	for key, a in map do
		if a == action then
			return key
		end
	end
	return nil
end

local function nameOf(v: any): string
	if typeof(v) == "EnumItem" then
		return v.Name
	elseif type(v) == "table" then
		return tostring(v.Name)
	end
	return tostring(v)
end
GamepadMap.nameOf = nameOf

local TRIGGERS: { [string]: boolean } = { ButtonL2 = true, ButtonR2 = true }

-- One router per client. It turns raw pad inputs into actions: holds (fire, ADS, interact, sprint) begin and end,
-- taps fire once. The X rule: pressed while a prompt (or a downed teammate) is up it is the prompt for the whole
-- hold, never a reload. ButtonSelect in a run is a tap (settings) or a hold (scoreboard), decided by tick().
export type Router = {
	held: { [string]: boolean },
	xMode: string?,
	adsOn: boolean,
	selectAt: number?,
	selectHold: boolean,
	input: (Router, obj: any, ctx: Ctx, now: number) -> ({ Emit }, boolean),
	tick: (Router, ctx: Ctx, now: number) -> { Emit },
	reset: (Router) -> { Emit },
}

local Router = {}
Router.__index = Router

function GamepadMap.newRouter(): Router
	local r = setmetatable({
		held = {},
		xMode = nil,
		adsOn = false,
		selectAt = nil,
		selectHold = false,
	}, Router)
	return (r :: any) :: Router
end

-- Normalise an input to (key, pressed) or nil when it is not a pad button edge. Triggers arrive as Begin / End and as
-- analog Change; both read through GamepadTriggerPress so a light squeeze is not a shot.
local function edge(self: Router, obj: any): (string?, boolean?)
	local key = nameOf(obj.KeyCode)
	local state = nameOf(obj.UserInputState)
	if TRIGGERS[key] then
		local z = 0
		local pos = obj.Position
		if pos ~= nil then
			z = tonumber((pos :: any).Z) or 0
		end
		local pressed: boolean
		if state == "End" or state == "Cancel" then
			pressed = false
		elseif state == "Begin" and z == 0 then
			pressed = true -- a Begin with no depth reported (digital triggers)
		else
			pressed = z >= cfg("GamepadTriggerPress")
		end
		if pressed == (self.held[key] == true) then
			return nil, nil
		end
		return key, pressed
	end
	if state == "Begin" then
		if self.held[key] then
			return nil, nil
		end
		return key, true
	elseif state == "End" or state == "Cancel" then
		if not self.held[key] then
			return nil, nil
		end
		return key, false
	end
	return nil, nil
end

-- Returns the actions to run and whether the input should be sunk (kept from Roblox's own bindings).
function Router.input(self: Router, obj: any, ctx: Ctx, now: number): ({ Emit }, boolean)
	local out: { Emit } = {}
	local key, pressed = edge(self, obj)
	if not key then
		return out, false
	end
	self.held[key] = pressed
	local action = GamepadMap.resolve(ctx.context, key)
	if not action then
		return out, false
	end
	if ctx.blocked and COMBAT[action] and pressed then
		return out, false -- a screen owns the pad; releases still pass so nothing stays held
	end
	local function emit(a: string, phase: string)
		table.insert(out, { action = a, phase = phase })
	end
	local sink = false
	if action == "reload" then
		if pressed then
			if ctx.promptVisible or ctx.reviveNearby then
				self.xMode = "interact"
				emit("interact", "begin")
			else
				self.xMode = "reload"
				emit("reload", "tap")
			end
		else
			if self.xMode == "interact" then
				emit("interact", "end")
			end
			self.xMode = nil
		end
	elseif action == "interact" then
		emit("interact", if pressed then "begin" else "end")
	elseif action == "ads" then
		if ctx.adsToggle then
			if pressed then
				self.adsOn = not self.adsOn
				emit("ads", if self.adsOn then "begin" else "end")
			end
		else
			self.adsOn = pressed :: boolean
			emit("ads", if pressed then "begin" else "end")
		end
		sink = true
	elseif action == "fire" or action == "sprint" then
		emit(action, if pressed then "begin" else "end")
		sink = true
	elseif action == "jump" then
		-- A at an open dealer panel buys it (and does not jump); otherwise Roblox's jump keeps it.
		if pressed and ctx.dealerPanel then
			emit("dealerBuy", "tap")
			sink = true
		end
	elseif action == "dealerTeleport" or action == "dealerPrev" or action == "dealerNext" then
		if pressed and ctx.dealerActive then
			emit(action, "tap")
		end
		sink = true
	elseif action == "voteSkip" then
		if pressed and (ctx.dealerActive or ctx.intermission) then
			emit(action, "tap")
		end
		sink = true
	elseif action == "scoreboard" then
		if pressed then
			self.selectAt = now
			self.selectHold = false
		else
			if self.selectHold then
				emit("scoreboard", "end")
			elseif self.selectAt then
				emit("settings", "tap")
			end
			self.selectAt = nil
			self.selectHold = false
		end
		sink = true
	else
		-- swap, ability1..3, settings: one tap on the press.
		if pressed then
			emit(action, "tap")
		end
		sink = true
	end
	return out, sink
end

-- Holds that turn into something with time (ButtonSelect: past GamepadTapMaxSec it is the scoreboard).
function Router.tick(self: Router, _ctx: Ctx, now: number): { Emit }
	local out: { Emit } = {}
	local at = self.selectAt
	if at and not self.selectHold and now - at >= cfg("GamepadTapMaxSec") then
		self.selectHold = true
		table.insert(out, { action = "scoreboard", phase = "begin" })
	end
	return out
end

-- Everything held lets go (the pad disconnected, the character died, a screen opened mid-hold).
function Router.reset(self: Router): { Emit }
	local out: { Emit } = {}
	local map: { [string]: string } = {
		ButtonR2 = "fire",
		ButtonL3 = "sprint",
	}
	for key, a in map do
		if self.held[key] then
			table.insert(out, { action = a, phase = "end" })
		end
	end
	if self.adsOn then
		table.insert(out, { action = "ads", phase = "end" })
	end
	if self.xMode == "interact" then
		table.insert(out, { action = "interact", phase = "end" })
	end
	if self.selectHold then
		table.insert(out, { action = "scoreboard", phase = "end" })
	end
	self.held = {}
	self.xMode = nil
	self.adsOn = false
	self.selectAt = nil
	self.selectHold = false
	return out
end

------------------------------------------------------------------ look

-- 0..1 how far past the radial dead zone a stick is (0 inside it).
function GamepadMap.stickAmount(x: number, y: number): number
	local mag = math.sqrt(x * x + y * y)
	local dz = cfg("GamepadLookDeadZone")
	if mag <= dz then
		return 0
	end
	return math.clamp((mag - dz) / (1 - dz), 0, 1)
end

-- The acceleration ramp's clock: seconds held at the edge, reset as soon as the stick comes off it.
function GamepadMap.accelStep(edgeSec: number, amount: number, dt: number): number
	if amount >= cfg("GamepadLookAccelEdge") then
		return edgeSec + dt
	end
	return 0
end

-- The right stick's look rates in radians per second (yaw: positive turns left, like the mouse path's yaw;
-- pitch: positive looks up). sens is the settings value 1..10 (5 = Config speed).
function GamepadMap.look(
	x: number,
	y: number,
	edgeSec: number,
	ads: boolean,
	sens: number?,
	invertY: boolean?
): (number, number, number)
	local amount = GamepadMap.stickAmount(x, y)
	if amount <= 0 then
		return 0, 0, 0
	end
	local mag = math.sqrt(x * x + y * y)
	local curved = amount ^ cfg("GamepadLookCurve")
	local ramp = math.clamp(edgeSec / math.max(cfg("GamepadLookAccelSec"), 1e-3), 0, 1)
	local accel = if amount >= cfg("GamepadLookAccelEdge") then 1 + (cfg("GamepadLookAccelMult") - 1) * ramp else 1
	local speed = math.rad(cfg("GamepadLookSpeed")) * ((sens or 5) / 5) * curved * accel
	if ads then
		speed *= cfg("GamepadAdsLookMult")
	end
	local dx, dy = x / mag, y / mag
	local yawRate = -dx * speed
	local pitchRate = dy * speed * cfg("GamepadLookPitchShare") * (if invertY then -1 else 1)
	return yawRate, pitchRate, amount
end

------------------------------------------------------------------ device

-- Which device an input means: "gamepad" | "keyboard" | "touch", or nil when it should not count (mouse motion,
-- the wheel, a stick inside its dead zone, focus events).
function GamepadMap.deviceOf(inputType: string, keyName: string?, magnitude: number?): string?
	if string.sub(inputType, 1, 7) == "Gamepad" then
		if keyName == "Thumbstick1" or keyName == "Thumbstick2" then
			return if (magnitude or 0) > cfg("GamepadMoveDeadZone") then "gamepad" else nil
		end
		if keyName == "ButtonL2" or keyName == "ButtonR2" then
			return if (magnitude or 1) >= cfg("GamepadTriggerPress") then "gamepad" else nil
		end
		return "gamepad"
	elseif inputType == "Keyboard" or inputType == "MouseButton1" or inputType == "MouseButton2" then
		return "keyboard"
	elseif inputType == "Touch" then
		return "touch"
	end
	return nil -- MouseMovement, MouseWheel, Focus, TextInput...
end

export type DeviceTracker = {
	current: string,
	lastSwitch: number,
	pending: string?,
	see: (DeviceTracker, device: string?, now: number) -> boolean,
	tick: (DeviceTracker, now: number) -> boolean,
}

local Tracker = {}
Tracker.__index = Tracker

-- After a switch the device holds DeviceSwitchHoldSec; a different device seen inside that window waits and wins
-- when it ends (if it is still the latest), so jitter never flickers the glyphs and a real switch lands within a
-- second. Returns true when `current` changed.
function GamepadMap.newDeviceTracker(initial: string): DeviceTracker
	local t = setmetatable({ current = initial, lastSwitch = -math.huge, pending = nil }, Tracker)
	return (t :: any) :: DeviceTracker
end

function Tracker.see(self: DeviceTracker, device: string?, now: number): boolean
	if device == nil then
		return false
	end
	if device == self.current then
		self.pending = nil
		return false
	end
	if now - self.lastSwitch >= cfg("DeviceSwitchHoldSec") then
		self.current = device
		self.lastSwitch = now
		self.pending = nil
		return true
	end
	self.pending = device
	return false
end

function Tracker.tick(self: DeviceTracker, now: number): boolean
	local p = self.pending
	if p and now - self.lastSwitch >= cfg("DeviceSwitchHoldSec") then
		self.current = p
		self.lastSwitch = now
		self.pending = nil
		return true
	end
	return false
end

return GamepadMap
