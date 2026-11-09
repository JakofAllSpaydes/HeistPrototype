-- Brief 11 self-test: `lune run tests/input.spec.luau` (the git pre-commit hook runs it too).
-- Feeds synthetic gamepad InputObjects through GamepadMap's router (the same code Input.lua runs) and checks every
-- binding resolves to its action, the X prompt rule, the Create tap / hold, the dealer D-pad, sprint, and the look
-- math (dead zone, curve, acceleration, ADS) as pure functions against expected numbers.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

------------------------------------------------------------------ loader: src/shared modules with a fake `script`
local function vec(...)
	return { ... }
end
local ROBLOX = {
	Vector2 = { new = vec },
	Vector3 = { new = vec },
	CFrame = { new = vec },
	Color3 = { fromHex = vec, fromRGB = vec, new = vec },
}

local cache: { [string]: any } = {}
local function loadShared(name: string): any
	if cache[name] ~= nil then
		return cache[name]
	end
	local path = "src/shared/" .. name .. ".lua"
	local fakeParent = {}
	local fakeScript = { Parent = fakeParent, Name = name }
	function fakeParent:WaitForChild(child: string)
		return { __shared = child }
	end
	fakeParent.FindFirstChild = fakeParent.WaitForChild
	local env: { [string]: any } = {
		script = fakeScript,
		require = function(target: any)
			if type(target) == "table" and target.__shared then
				return loadShared(target.__shared)
			end
			error("unexpected require in " .. name)
		end,
	}
	for k, v in ROBLOX do
		env[k] = v
	end
	local chunk = luau.load(fs.readFile(path), { debugName = name, environment = env })
	local m = chunk()
	cache[name] = m
	return m
end

local Config = loadShared("Config")
local GamepadMap = loadShared("GamepadMap")
local Glyphs = loadShared("Glyphs")
local SprintRule = loadShared("SprintRule")
local NavMath = loadShared("NavMath")

------------------------------------------------------------------ tiny test kit
local passed, failed = 0, 0
local function check(label: string, ok: boolean, detail: string?)
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL  " .. label .. (if detail then "  (" .. detail .. ")" else ""))
	end
end
local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-6)
end

-- A synthetic InputObject: enums by name, like the real thing's EnumItem.Name.
local function inp(key: string, state: string, z: number?): any
	return {
		KeyCode = { Name = key },
		UserInputType = { Name = "Gamepad1" },
		UserInputState = { Name = state },
		Position = { X = 0, Y = 0, Z = z or 0 },
	}
end

local function actions(list: { any }): string
	local parts = {}
	for _, e in list do
		table.insert(parts, e.action .. ":" .. e.phase)
	end
	return table.concat(parts, ",")
end

local RUN = { context = "run" }
local function press(r: any, key: string, ctx: any?, now: number?): string
	local out = r:input(inp(key, "Begin"), ctx or RUN, now or 0)
	return actions(out)
end
local function release(r: any, key: string, ctx: any?, now: number?): string
	local out = r:input(inp(key, "End"), ctx or RUN, now or 0)
	return actions(out)
end

------------------------------------------------------------------ 1. every binding resolves
for context, map in Config.GamepadMap do
	for key, action in map do
		check(
			"resolve " .. context .. "." .. key,
			GamepadMap.resolve(context, key) == action,
			tostring(GamepadMap.resolve(context, key))
		)
		check("buttonFor " .. context .. "." .. action, GamepadMap.buttonFor(context, action) ~= nil)
	end
end
local EXPECT_RUN = {
	ButtonR2 = "fire",
	ButtonL2 = "ads",
	ButtonX = "reload",
	ButtonY = "swap",
	ButtonA = "jump",
	ButtonL1 = "ability1",
	ButtonR1 = "ability2",
	ButtonB = "ability3",
	ButtonR3 = "cameraCycle",
	ButtonL3 = "sprint",
	DPadUp = "upgrade",
	DPadLeft = "pause",
	DPadRight = "voteSkip",
	ButtonSelect = "scoreboard",
}
for key, action in EXPECT_RUN do
	check("brief table run." .. key .. " = " .. action, GamepadMap.resolve("run", key) == action)
end
check("ButtonB unbound in the hub (screens' back)", GamepadMap.resolve("hub", "ButtonB") == nil)
check("teleport glyph rides D-pad up", GamepadMap.buttonFor("run", "dealerTeleport") == "DPadUp")
check("interact glyph rides X", GamepadMap.buttonFor("run", "interact") == "ButtonX")

------------------------------------------------------------------ 2. combat through the router
do
	local r = GamepadMap.newRouter()
	check("RT begin fires", press(r, "ButtonR2") == "fire:begin")
	check("RT repeat Begin ignored", press(r, "ButtonR2") == "")
	check("RT end stops", release(r, "ButtonR2") == "fire:end")
	-- analog: a light squeeze is not a shot, past GamepadTriggerPress is
	local light = r:input(inp("ButtonR2", "Change", Config.GamepadTriggerPress * 0.5), RUN, 0)
	check("RT light squeeze no fire", actions(light) == "")
	local deep = r:input(inp("ButtonR2", "Change", 0.9), RUN, 0)
	check("RT deep squeeze fires", actions(deep) == "fire:begin")
	local back = r:input(inp("ButtonR2", "Change", 0.05), RUN, 0)
	check("RT let off stops", actions(back) == "fire:end")

	check("LT hold ADS begin", press(r, "ButtonL2") == "ads:begin")
	check("LT release ADS end", release(r, "ButtonL2") == "ads:end")
	local toggle = { context = "run", adsToggle = true }
	check("LT toggle on", press(r, "ButtonL2", toggle) == "ads:begin")
	check("LT toggle release nothing", release(r, "ButtonL2", toggle) == "")
	check("LT toggle off", press(r, "ButtonL2", toggle) == "ads:end")
	release(r, "ButtonL2", toggle)

	check("X tap reloads", press(r, "ButtonX") == "reload:tap")
	check("X release after reload nothing", release(r, "ButtonX") == "")
	local prompt = { context = "run", promptVisible = true }
	check("X with a prompt = interact (no reload)", press(r, "ButtonX", prompt) == "interact:begin")
	check("X release ends the prompt hold", release(r, "ButtonX", prompt) == "interact:end")
	local revive = { context = "run", reviveNearby = true }
	check("X near a downed teammate = revive hold", press(r, "ButtonX", revive) == "interact:begin")
	-- the prompt goes away mid-hold: still the prompt's hold until release
	check("X hold keeps its mode when the prompt hides", release(r, "ButtonX", RUN) == "interact:end")

	check("Y swaps", press(r, "ButtonY") == "swap:tap")
	release(r, "ButtonY")
	check("LB ability 1", press(r, "ButtonL1") == "ability1:tap")
	check("RB ability 2", press(r, "ButtonR1") == "ability2:tap")
	check("Circle ability 3", press(r, "ButtonB") == "ability3:tap")
	check("R3 camera view cycle", press(r, "ButtonR3") == "cameraCycle:tap")
	release(r, "ButtonL1")
	release(r, "ButtonR1")
	release(r, "ButtonB")
	release(r, "ButtonR3")
	local _, bSink = r:input(inp("ButtonB", "Begin"), { context = "run", blocked = true }, 0)
	check("Circle passes to the screen when one is open", bSink == false)
	release(r, "ButtonB")

	check("A jumps (no action, Roblox keeps it)", press(r, "ButtonA") == "")
	release(r, "ButtonA")
	local dealer = { context = "run", dealerActive = true, dealerPanel = true }
	check("A at an open dealer panel still jumps", press(r, "ButtonA", dealer) == "")
	release(r, "ButtonA", dealer)
	local out, sink = r:input(inp("ButtonX", "Begin"), dealer, 0)
	check("square at an open dealer panel buys (no reload)", actions(out) == "dealerBuy:tap" and sink == true)
	check("square release after a buy: nothing", release(r, "ButtonX", dealer) == "")
	local both = { context = "run", dealerActive = true, dealerPanel = true, promptVisible = true }
	check("the dealer panel wins over a floor gun prompt", press(r, "ButtonX", both) == "dealerBuy:tap")
	release(r, "ButtonX", both)
	check("dealer buy glyph is square", GamepadMap.buttonFor("run", "dealerBuy") == "ButtonX")

	check("D-pad up teleports at the dealer", press(r, "DPadUp", dealer) == "dealerTeleport:tap")
	check("D-pad right votes skip at the dealer", press(r, "DPadRight", dealer) == "voteSkip:tap")
	check("D-pad left votes pause", press(r, "DPadLeft", dealer) == "pause:tap")
	check("D-pad down is free", press(r, "DPadDown", dealer) == "")
	for _, k in { "DPadUp", "DPadDown", "DPadLeft", "DPadRight" } do
		release(r, k, dealer)
	end
	check("D-pad left votes pause mid-wave", press(r, "DPadLeft") == "pause:tap")
	release(r, "DPadLeft")
	check("D-pad right toggles AUTO SKIP mid-wave", press(r, "DPadRight") == "voteSkip:tap")
	release(r, "DPadRight")
	check("D-pad up buys the upgrade pick outside the dealer", press(r, "DPadUp") == "upgrade:tap")
	release(r, "DPadUp")
	check(
		"D-pad right votes skip in an intermission",
		press(r, "DPadRight", { context = "run", intermission = true }) == "voteSkip:tap"
	)
	release(r, "DPadRight")

	check("L3 sprint begin", press(r, "ButtonL3") == "sprint:begin")
	check("L3 sprint end", release(r, "ButtonL3") == "sprint:end")

	-- Create (ButtonSelect): the scoreboard. A tap opens it and leaves it open, the next tap closes it; a hold peeks.
	local SB_OPEN = { context = "run", scoreboardOpen = true }
	check("Create tap opens the scoreboard", press(r, "ButtonSelect", RUN, 10) == "scoreboard:begin")
	check("Create tap release leaves it open", release(r, "ButtonSelect", RUN, 10.1) == "")
	check("Create tap again closes it", press(r, "ButtonSelect", SB_OPEN, 12) == "scoreboard:end")
	check("Create release after closing: nothing", release(r, "ButtonSelect", RUN, 12.1) == "")
	check("Create hold opens at once", press(r, "ButtonSelect", RUN, 20) == "scoreboard:begin")
	check("Create no timed action", actions(r:tick(RUN, 21)) == "")
	check(
		"Create hold release closes (peek)",
		release(r, "ButtonSelect", SB_OPEN, 20 + Config.GamepadTapMaxSec + 0.05) == "scoreboard:end"
	)
	-- the camera view cycle: normal -> fully out -> first person -> normal
	local z1 = GamepadMap.nextZoom(Config.CameraZoomDefault)
	check("cycle: normal -> fully out", z1 == Config.CameraZoomMax)
	local z2 = GamepadMap.nextZoom(z1)
	check("cycle: out -> first person", z2 == 0)
	check("cycle: first person -> normal", GamepadMap.nextZoom(z2) == Config.CameraZoomDefault)
	check("cycle: a wheel zoom goes out first", GamepadMap.nextZoom(5) == Config.CameraZoomMax)

	-- a screen owns the pad: combat presses do nothing, releases still pass
	local blocked = { context = "run", blocked = true }
	check("blocked: RT press ignored", press(r, "ButtonR2", blocked) == "")
	check("blocked: Y ignored", press(r, "ButtonY", blocked) == "")
	release(r, "ButtonY", blocked)
	release(r, "ButtonR2", blocked)

	-- reset lets go of every hold
	press(r, "ButtonR2")
	press(r, "ButtonL2")
	local let = actions(r:reset())
	check("reset ends fire", string.find(let, "fire:end", 1, true) ~= nil, let)
	check("reset ends ads", string.find(let, "ads:end", 1, true) ~= nil, let)
end

do -- the hub: X is the prompt, Create is Roblox's
	local r = GamepadMap.newRouter()
	local HUB = { context = "hub" }
	check("hub X = interact", press(r, "ButtonX", HUB) == "interact:begin")
	check("hub X release", release(r, "ButtonX", HUB) == "interact:end")
	check("hub RT does nothing", press(r, "ButtonR2", HUB) == "")
	local out, sink = r:input(inp("ButtonSelect", "Begin"), HUB, 0)
	check("hub Create passes to Roblox", actions(out) == "" and sink == false)
end

------------------------------------------------------------------ 3. look math
do
	local dz = Config.GamepadLookDeadZone
	local speed = math.rad(Config.GamepadLookSpeed)
	local y0, p0, a0 = GamepadMap.look(dz * 0.9, 0, 0, false, 5, false)
	check("inside the dead zone: no look", y0 == 0 and p0 == 0 and a0 == 0)
	local y1 = GamepadMap.look(1, 0, 0, false, 5, false)
	check("full right: -speed yaw", near(y1, -speed), tostring(y1))
	local yl = GamepadMap.look(-1, 0, 0, false, 5, false)
	check("full left: +speed yaw", near(yl, speed))
	-- half way past the dead zone: (0.5)^curve of the speed
	local m = dz + (1 - dz) * 0.5
	local yh = GamepadMap.look(m, 0, 0, false, 5, false)
	check("curve at half push", near(yh, -speed * 0.5 ^ Config.GamepadLookCurve), tostring(yh))
	check("curve keeps small pushes fine", math.abs(yh) < speed * 0.5)
	-- acceleration: full ramp after GamepadLookAccelSec at the edge
	local ya = GamepadMap.look(1, 0, Config.GamepadLookAccelSec, false, 5, false)
	check("accel at the full ramp", near(ya, -speed * Config.GamepadLookAccelMult), tostring(ya))
	local yah = GamepadMap.look(1, 0, Config.GamepadLookAccelSec / 2, false, 5, false)
	check("accel half way", near(yah, -speed * (1 + (Config.GamepadLookAccelMult - 1) * 0.5)))
	local yna = GamepadMap.look(m, 0, 99, false, 5, false)
	check("no accel off the edge", near(yna, yh))
	-- the ramp clock
	local t = 0
	for _ = 1, 10 do
		t = GamepadMap.accelStep(t, 1, 0.05)
	end
	check("accel clock counts at the edge", near(t, 0.5, 1e-9))
	check("accel clock resets off the edge", GamepadMap.accelStep(t, 0.5, 0.05) == 0)
	-- ADS, sensitivity, invert
	local yads = GamepadMap.look(1, 0, 0, true, 5, false)
	check("ADS multiplier", near(yads, -speed * Config.GamepadAdsLookMult))
	local ys10 = GamepadMap.look(1, 0, 0, false, 10, false)
	check("sensitivity 10 doubles", near(ys10, -speed * 2))
	local ys1 = GamepadMap.look(1, 0, 0, false, 1, false)
	check("sensitivity 1 is a fifth", near(ys1, -speed * 0.2))
	local _, pu = GamepadMap.look(0, 1, 0, false, 5, false)
	check("stick up looks up", near(pu, speed * Config.GamepadLookPitchShare))
	local _, pi = GamepadMap.look(0, 1, 0, false, 5, true)
	check("invert Y", near(pi, -speed * Config.GamepadLookPitchShare))
	-- diagonal: the direction is normalised, the amount from the radial magnitude
	local yd, pd, ad = GamepadMap.look(0.7071, 0.7071, 0, false, 5, false)
	check("diagonal amount ~1", near(ad, 1, 1e-3))
	check("diagonal splits", near(math.abs(yd), speed * 0.7071, 1e-3) and pd > 0)
	-- live override (the debug slider)
	GamepadMap.live.GamepadLookSpeed = 90
	local ylive = GamepadMap.look(1, 0, 0, false, 5, false)
	check("live slider overrides speed", near(ylive, -math.rad(90)))
	GamepadMap.live.GamepadLookSpeed = nil
end

------------------------------------------------------------------ 4. device detection
do
	check("mouse motion is no device", GamepadMap.deviceOf("MouseMovement", "Unknown", 0) == nil)
	check("wheel is no device", GamepadMap.deviceOf("MouseWheel", "Unknown", 0) == nil)
	check("a click is keyboard", GamepadMap.deviceOf("MouseButton1", "Unknown", 0) == "keyboard")
	check("a key is keyboard", GamepadMap.deviceOf("Keyboard", "E", 0) == "keyboard")
	check("a touch is touch", GamepadMap.deviceOf("Touch", "Unknown", 0) == "touch")
	check("a button is gamepad", GamepadMap.deviceOf("Gamepad1", "ButtonA", 0) == "gamepad")
	check("stick in its dead zone: none", GamepadMap.deviceOf("Gamepad1", "Thumbstick1", 0.05) == nil)
	check("stick past it: gamepad", GamepadMap.deviceOf("Gamepad1", "Thumbstick2", 0.6) == "gamepad")
	local hold = Config.DeviceSwitchHoldSec
	local d = GamepadMap.newDeviceTracker("keyboard")
	check("first switch is instant", d:see("gamepad", 100) == true and d.current == "gamepad")
	check("a stray click inside the hold waits", d:see("keyboard", 100 + hold * 0.5) == false)
	check("...and the pad again cancels it", d:see("gamepad", 100 + hold * 0.6) == false and d.pending == nil)
	check("tick with nothing pending", d:tick(100 + hold * 2) == false and d.current == "gamepad")
	d:see("keyboard", 200)
	check("a real switch after the hold", d.current == "keyboard")
	d:see("gamepad", 200 + hold * 0.2)
	check("pending inside the hold", d.current == "keyboard" and d.pending == "gamepad")
	check("lands when the hold ends (within a second)", d:tick(200 + hold) == true and d.current == "gamepad")
end

------------------------------------------------------------------ 5. glyphs (step 1)
do
	local KEY = Config.InteractKey
	check("keyboard interact is the interact key", Glyphs.label("interact", "keyboard", nil, "run") == KEY)
	check("keyboard abilities follow AbilityKeys", Glyphs.label("ability3", "keyboard") == Config.AbilityKeys[3])
	check("pad interact is square", Glyphs.label("interact", "gamepad", "playstation", "run") == "□")
	check("pad ability 3 is circle", Glyphs.label("ability3", "gamepad", "playstation", "run") == "○")
	check("pad ability 1 is L1", Glyphs.label("ability1", "gamepad", "playstation", "run") == "L1")
	check("xbox ability 1 is LB", Glyphs.label("ability1", "gamepad", "xbox", "run") == "LB")
	check("pad camera view is R3", Glyphs.label("cameraCycle", "gamepad", "playstation", "run") == "R3")
	check("pad upgrade is D-pad up", Glyphs.label("upgrade", "gamepad", "playstation", "run") == "↑")
	check("pad teleport rides D-pad up", Glyphs.label("dealerTeleport", "gamepad", "playstation", "run") == "↑")
	check("pad back is circle", Glyphs.label("back", "gamepad", "playstation") == "○")
	check("pad pause is D-pad left", Glyphs.label("pause", "gamepad", "playstation", "run") == "←")
	check("keyboard has no camera view key", Glyphs.label("cameraCycle", "keyboard") == nil)
	check("touch shows no key", Glyphs.label("interact", "touch") == "")
	-- every action a HUD line names has a glyph on keyboard and pad
	for _, a in { "reload", "swap", "ability1", "ability2", "ability3", "sprint", "upgrade", "voteSkip", "scoreboard" } do
		check("keyboard glyph " .. a, Glyphs.label(a, "keyboard") ~= nil)
		check("pad glyph " .. a, Glyphs.label(a, "gamepad", "playstation", "run") ~= nil)
	end
	check("fmt fills the key", Glyphs.fmt("{key} TO SKIP", "V") == "V TO SKIP")
	check(
		"fmt on touch drops the key",
		Glyphs.fmt("HOLD {key} · CUT", "") == "HOLD CUT" or Glyphs.fmt("HOLD {key} · CUT", "") == "HOLD · CUT",
		Glyphs.fmt("HOLD {key} · CUT", "")
	)
	check("fmt drops a leading key and its dot", Glyphs.fmt("{key} · OPEN", "") == "OPEN")
	check("swapKey HOLD", Glyphs.swapKey("HOLD " .. KEY .. " · CUT", KEY, "□") == "HOLD □ · CUT")
	check("swapKey leading", Glyphs.swapKey(KEY .. " · BREACH", KEY, "□") == "□ · BREACH")
	check("swapKey bare marker", Glyphs.swapKey("HOLD " .. KEY, KEY, "□") == "HOLD □")
	check(
		"swapKey leaves words alone",
		Glyphs.swapKey("ESCAPE THE " .. KEY .. "XIT", KEY, "□") == "ESCAPE THE " .. KEY .. "XIT"
	)
	check("style auto defaults to playstation", Glyphs.style("auto", nil) == "playstation")
	check("style setting wins", Glyphs.style("xbox", "ButtonCross") == "xbox")
end

------------------------------------------------------------------ 6. sprint (step 3): fire always wins
do
	local GO = { moving = true, keep = true, allowed = true }
	local STILL = { moving = false, keep = false, allowed = true }
	-- PC hold
	local r = SprintRule.new("keyboard", true)
	r:press(0)
	local changed = r:tick(0, GO)
	check("Shift held + moving engages", changed and r.on)
	local rec = r:cancel("fire", 0.3)
	check("fire ends it at once", not r.on and rec ~= nil and rec.reason == "fire")
	check("the record says how long", rec ~= nil and math.abs(rec.sec - 0.3) < 1e-6)
	r:tick(0.4, GO)
	check("still holding Shift after a cancel: no re-engage", not r.on)
	r:tick(5, GO)
	check("...not even much later", not r.on)
	r:release(5)
	r:press(5.1)
	r:tick(5.1, GO)
	check("Shift released and pressed again re-arms", r.on)
	r:cancel("fire", 6)
	r:release(6)
	r:press(6.1)
	r:tick(6.1, GO)
	check("re-press inside the fire cooldown waits", not r.on)
	r:tick(6 + Config.SprintReEngageCooldownSec + 0.01, GO)
	check("...and engages when it ends if still held", r.on)
	local relRec = r:release(7)
	check("hold mode: Shift up ends it (key)", not r.on and relRec ~= nil and relRec.reason == "key")
	r:press(8)
	r:tick(8, STILL)
	check("standing still: no sprint", not r.on)
	r:tick(8.5, GO)
	check("held Shift engages once moving", r.on)
	local _, stopRec = r:tick(9, STILL)
	check("stopping ends it", not r.on and stopRec ~= nil and stopRec.reason == "stop")
	r:cancel("ads", 9.1)
	r:tick(9.2, GO)
	check("after an ADS cancel, held Shift does not re-engage", not r.on)
	-- pad toggle
	local p = SprintRule.new("gamepad", false)
	p:press(0)
	p:release(0.05)
	p:tick(0.1, GO)
	check("L3 click toggles on (released)", p.on)
	local _, stickRec = p:tick(1, { moving = true, keep = false, allowed = true })
	check("stick under the keep threshold ends it", not p.on and stickRec ~= nil and stickRec.reason == "stick")
	p:tick(1.1, GO)
	check("pad: no re-engage without a click", not p.on)
	p:press(2)
	p:tick(2, GO)
	local keyRec = p:press(3)
	check("pad: a second click ends it", not p.on and keyRec ~= nil and keyRec.reason == "key")
	p:press(4)
	p:tick(4 + Config.SprintPressGraceSec + 0.1, GO)
	check("a click with the stick idle lapses after the grace", not p.on and not p.pending)
	p:press(5)
	p:tick(5, GO)
	local _, downRec = p:tick(5.5, { moving = true, keep = true, allowed = false, downed = true })
	check("going down ends it (down)", not p.on and downRec ~= nil and downRec.reason == "down")
	check("cancel with no sprint on returns nothing", p:cancel("fire", 6) == nil)
	-- touch geometry
	local ratio, angle, forward = SprintRule.touch(0, -78, 60)
	check("thumb straight up past the ring", math.abs(ratio - 1.3) < 1e-6 and angle < 1e-6 and forward == 1)
	check("that is a push", SprintRule.pushing(ratio, angle))
	local r2, a2 = SprintRule.touch(70, -10, 60)
	check("thumb out to the side is not a push", not SprintRule.pushing(r2, a2))
	local r3, a3 = SprintRule.touch(30, -60, 60)
	check("26 degrees off forward pushes", SprintRule.pushing(r3, a3))
	local r4 = SprintRule.touch(0, -40, 60)
	check("inside the ring re-arms", SprintRule.rearmed(r4))
	check("on the ring does not re-arm", not SprintRule.rearmed(SprintRule.touch(0, -58, 60)))
	local _, _, f5 = SprintRule.touch(0, -30, 60)
	check("half forward is below keep", f5 < Config.SprintKeepThreshold)
end

------------------------------------------------------------------ 7. screens: the D-pad neighbours (GamepadNav.link)
do
	local function R(x, y, w, h)
		return { x = x, y = y, w = w, h = h }
	end
	-- weapon-type chips in a row, a gun grid under them, UPGRADE under the chips on the right
	local chip = R(400, 0, 90, 30)
	local leftChip = R(300, 0, 90, 30)
	local gridTile = R(250, 40, 100, 100) -- nearer but off to the side
	local upgrade = R(380, 200, 160, 50) -- farther but directly below
	check(
		"down goes to what is directly below, not the nearer diagonal",
		NavMath.pick(chip, "down", { gridTile, upgrade }) == 2
	)
	check("left stays in the row", NavMath.pick(chip, "left", { gridTile, leftChip }) == 2)
	check("nothing above: nil", NavMath.pick(chip, "up", { gridTile, upgrade }) == nil)
	check(
		"with no column match the nearest ahead wins",
		NavMath.pick(R(0, 0, 50, 50), "down", { R(100, 300, 50, 50), R(80, 100, 50, 50) }) == 2
	)
end

------------------------------------------------------------------ 8. minigames on a pad (step 5)
do
	-- the Safe dial: a full circle of the right stick is a full turn of the dial, clockwise positive
	local total, prev = 0, NavMath.stickAngle(0, 1)
	for i = 1, 72 do
		local r = math.rad(i * 5)
		local a = NavMath.stickAngle(math.sin(r), math.cos(r))
		total += NavMath.angleDelta(prev, a)
		prev = a
	end
	check("Safe: a stick circle clockwise = one turn right", near(total, 360, 1e-6), tostring(total))
	check("Safe: up to right is +90", near(NavMath.angleDelta(NavMath.stickAngle(0, 1), NavMath.stickAngle(1, 0)), 90))
	check("Safe: across the top seam is short", near(NavMath.angleDelta(170, -170), 20))
	check("Safe: pad mode is stick or dpad", Config.SafeDialPadMode == "stick" or Config.SafeDialPadMode == "dpad")
	-- every game has a pad path and a pad line whose glyph tokens resolve
	for _, name in { "Lockpick", "Hotwire", "Keypad", "Charges", "Safe", "Freq", "Cut" } do
		local src = fs.readFile("src/client/Minigames/" .. name .. ".lua")
		check(name .. " sets host.pad", string.find(src, "host.pad = ", 1, true) ~= nil)
		local line = string.match(src, 'padHint = "([^"]+)"')
		check(name .. " has a pad line", line ~= nil)
		for token in string.gmatch(line or "", "{(%w+)}") do
			check(
				name .. " glyph " .. token,
				Config.GlyphText.playstation[token] ~= nil and Config.GlyphText.xbox[token] ~= nil
			)
		end
	end
end

print(string.format("input.spec: %d passed, %d failed", passed, failed))
if failed > 0 then
	process.exit(1)
end
