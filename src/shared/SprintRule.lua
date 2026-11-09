--!strict
-- Brief 11 step 3: sprint's rules as pure state, shared by Sprint.lua (client) and tests/input.spec.luau (Lune).
-- One rule above the rest: fire always wins. Any fire / ADS / ability / interact / swap / minigame input ends the
-- sprint in the same frame and the action happens; sprint then needs a fresh engage (Shift pressed again, L3 clicked
-- again, the thumb pumped back inside the ring and out again).
--   rule:press(now)            the engage input was given (Shift down, L3 click, push-through done, the button)
--   rule:release(now)          it was let go (Shift up / L3 up in hold mode)
--   rule:cancel(reason, now)   an action ended it -> the finished sprint's record, or nil when none was on
--   rule:tick(now, cond)       engage / keep / end with the world -> (changed, record?)
local Config = require(script.Parent:WaitForChild("Config"))

local SprintRule = {}

export type Cond = {
	moving: boolean, -- the character is moving
	keep: boolean, -- the stay condition: moving (keyboard) or the stick forward of SprintKeepThreshold (pad / touch)
	allowed: boolean, -- not downed, no screen, gameplay camera
	downed: boolean?,
}

export type Record = { sec: number, reason: string, device: string }

export type Rule = {
	on: boolean,
	pending: boolean, -- an engage given and not yet used
	pendingAt: number,
	held: boolean, -- the engage input is down (hold modes)
	holdMode: boolean, -- Shift held / L3 held: release ends it; toggle: a second press ends it
	since: number,
	blockUntil: number,
	device: string,
	press: (Rule, now: number) -> Record?,
	release: (Rule, now: number) -> Record?,
	cancel: (Rule, reason: string, now: number) -> Record?,
	tick: (Rule, now: number, cond: Cond) -> (boolean, Record?),
}

local function cfg(key: string, default: number): number
	local v = (Config :: any)[key]
	return if typeof(v) == "number" then v else default
end

local Rule = {}
Rule.__index = Rule

function SprintRule.new(device: string?, holdMode: boolean?): Rule
	local r = setmetatable({
		on = false,
		pending = false,
		pendingAt = 0,
		held = false,
		holdMode = holdMode == true,
		since = 0,
		blockUntil = -math.huge,
		device = device or "keyboard",
	}, Rule)
	return (r :: any) :: Rule
end

local function finish(self: Rule, reason: string, now: number): Record?
	if not self.on then
		return nil
	end
	self.on = false
	return { sec = now - self.since, reason = reason, device = self.device }
end

function Rule.press(self: Rule, now: number): Record?
	self.held = true
	if self.on and not self.holdMode then
		self.pending = false
		return finish(self, "key", now) -- toggle: the second press ends it
	end
	self.pending = true
	self.pendingAt = now
	return nil
end

function Rule.release(self: Rule, now: number): Record?
	self.held = false
	if self.holdMode then
		self.pending = false
		return finish(self, "key", now)
	end
	return nil
end

-- An action ends the sprint (or eats a pending engage). A fire cancel also blocks re-engaging for a beat.
function Rule.cancel(self: Rule, reason: string, now: number): Record?
	self.pending = false
	if reason == "fire" then
		self.blockUntil = now + cfg("SprintReEngageCooldownSec", 0.5)
	end
	return finish(self, reason, now)
end

function Rule.tick(self: Rule, now: number, cond: Cond): (boolean, Record?)
	if self.on then
		if not cond.allowed then
			return true, finish(self, if cond.downed then "down" else "blocked", now)
		end
		if not cond.keep then
			return true, finish(self, if self.device == "keyboard" then "stop" else "stick", now)
		end
		return false, nil
	end
	if not self.pending then
		return false, nil
	end
	-- Toggle presses wait a moment for the stick / keys to catch up, then lapse; hold presses wait while held.
	if not self.holdMode and now - self.pendingAt > cfg("SprintPressGraceSec", 0.35) then
		self.pending = false
		return false, nil
	end
	if self.holdMode and not self.held then
		self.pending = false
		return false, nil
	end
	if now < self.blockUntil or not cond.allowed or not cond.moving or not cond.keep then
		return false, nil
	end
	self.pending = false
	self.on = true
	self.since = now
	return true, nil
end

------------------------------------------------------------------ touch push-through geometry

-- A thumb (dx, dy) in px from the thumbstick's centre (screen axes: +y is down) against the ring radius:
-- ratio (1 = on the ring), the angle off straight-forward in degrees, and the forward share (−1..1, ring-clamped).
function SprintRule.touch(dx: number, dy: number, radius: number): (number, number, number)
	local r = math.max(radius, 1)
	local mag = math.sqrt(dx * dx + dy * dy)
	local ratio = mag / r
	local angle = if mag > 0 then math.deg(math.acos(math.clamp(-dy / mag, -1, 1))) else 180
	local forward = math.clamp(-dy / r, -1, 1)
	return ratio, angle, forward
end

-- Is the thumb in the push-through zone (past the ring, within the forward cone)? SprintPushRadius is how far out
-- the stretch zone is drawn; the thumb only has to be past the ring.
function SprintRule.pushing(ratio: number, angle: number): boolean
	return ratio > 1 and angle <= cfg("SprintPushAngle", 35)
end

-- Back inside the re-arm radius: the next push-through is a new engage (the thumb pump).
function SprintRule.rearmed(ratio: number): boolean
	return ratio <= cfg("SprintReArmRadius", 0.88)
end

return SprintRule
