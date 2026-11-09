--!strict
-- Brief 11 step 4: every custom screen walkable on a pad. A stack of contexts, one per open screen:
--   * screens that hold a ClientState block or movement lock (meta, store, pass, jobs, skills, daily, streak,
--     queue, overlay, purchase, debug, cinematic, ...) push and pop by themselves; SCREENS names each one's gui
--   * GamepadNav.push / pop for the rest (the scoreboard, MARLOW's cards, the hub HUD toggle)
-- The top context's selectables are its gui's visible buttons (attribute NavSkip excludes one, NavSelectable adds a
-- non-button, NavDefault marks the default). D-pad / left stick move by screen geometry (NavMath), A is Roblox's own
-- activation of GuiService.SelectedObject (so buttons need no new code), B is each screen's own back handler (they
-- listen for ButtonB), LB / RB call the screen's tabs hook, LT / RT its page hook (or scroll its list). Mouse and
-- touch keep working everywhere; the ring (SelectionRing) only shows on a pad.
-- Logs: [GHS Nav] push <screen> / pop <screen> / WARN no selectables <screen>.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local NavMath = require(Shared:WaitForChild("NavMath"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local SelectionRing = require(script.Parent:WaitForChild("SelectionRing"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local GamepadNav = {}

export type Spec = {
	gui: { string }?, -- ScreenGui names in PlayerGui (the topmost one with selectables wins); "Minigame_*" = prefix
	root: (() -> GuiObject?)?, -- or a root object
	default: (() -> GuiObject?)?, -- the first selection (else NavDefault, else the biggest button)
	tabs: ((dir: number) -> ())?, -- LB / RB
	page: ((dir: number) -> ())?, -- LT / RT (default: scroll the selection's list a page)
	back: (() -> ())?, -- B, for contexts whose screen has no ButtonB handler of its own
	filter: ((g: GuiObject) -> boolean)?, -- extra test for a selectable
	quiet: boolean?, -- no WARN when it has nothing to select (cutscenes, spectate)
	passive: boolean?, -- the stick and D-pad are not taken while nothing is selectable
	offscreen: boolean?, -- selectables may sit off screen (a panned canvas: onSelect brings them in)
	onSelect: ((g: GuiObject) -> ())?, -- the selection moved to g
}

type Context = {
	name: string,
	spec: Spec,
	auto: boolean,
	current: GuiObject?,
	warned: boolean,
}

-- The screens that push themselves (their block / lock reason -> gui). Tabs / page hooks are added by the screens
-- with GamepadNav.register.
local SCREENS: { [string]: Spec } = {
	queue = { gui = { "CreateMatch" } },
	meta = { gui = { "MetaScene" } },
	overlay = { gui = { "UpgradeOverlay" } },
	cinematic = { gui = { "SummaryCrateCard", "RunEnd", "BossCutscene" }, quiet = true },
	store = { gui = { "CrateReel", "CrateScene", "StoreScene" } },
	purchase = { gui = { "PurchaseSheet" } },
	pass = { gui = { "PassScene" } },
	jobs = { gui = { "JobBoard" } },
	skills = { gui = { "SkillScene" } },
	streak = { gui = { "StreakModal" } },
	daily = { gui = { "DailySheet" } },
	debug = { gui = { "DebugPanel" } },
	pause = { gui = { "PauseOverlay" }, quiet = true },
	spectate = { gui = { "Spectate" }, quiet = true },
	-- the pad plays each game its own way (Minigames/Frame); only games that ask (NavWalk) have their buttons walked
	minigame = {
		gui = { "Minigame_*" },
		quiet = true,
		filter = function(g: GuiObject): boolean
			local sg = g:FindFirstAncestorWhichIsA("ScreenGui")
			return sg ~= nil and sg:GetAttribute("NavWalk") == true
		end,
	},
	jobsAnnounce = { gui = { "JobsAnnounce" }, quiet = true },
}

GamepadNav.showNav = false -- debug: outline every selectable and list the stack

local player = Players.LocalPlayer
local stack: { Context } = {}
local selectedByUs: GuiObject? = nil

function GamepadNav.register(name: string, spec: Spec)
	local s = SCREENS[name] or {}
	for k, v in spec :: any do
		(s :: any)[k] = v
	end
	SCREENS[name] = s
end

local function find(name: string): (number?, Context?)
	for i, c in stack do
		if c.name == name then
			return i, c
		end
	end
	return nil, nil
end

local function pushCtx(name: string, spec: Spec, auto: boolean)
	if find(name) then
		return
	end
	table.insert(stack, { name = name, spec = spec, auto = auto, current = nil, warned = false })
	print("[GHS Nav] push " .. name)
end

local function popCtx(name: string)
	local i = find(name)
	if i then
		table.remove(stack, i)
		print("[GHS Nav] pop " .. name)
	end
end

-- Explicit contexts (screens without a block reason).
function GamepadNav.push(name: string, spec: Spec?)
	pushCtx(name, spec or SCREENS[name] or {}, false)
end

function GamepadNav.pop(name: string)
	popCtx(name)
end

function GamepadNav.top(): string?
	local c = stack[#stack]
	return if c then c.name else nil
end

function GamepadNav.isOpen(name: string): boolean
	return find(name) ~= nil
end

------------------------------------------------------------------ selectables

local function shown(g: GuiObject): boolean
	local node: Instance? = g
	while node and not node:IsA("LayerCollector") do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end
		node = node.Parent
	end
	if node and node:IsA("ScreenGui") and not node.Enabled then
		return false
	end
	return node ~= nil
end

local function viewport(): Vector2
	local cam = workspace.CurrentCamera
	return if cam then cam.ViewportSize else Vector2.new(1920, 1080)
end

local function selectable(g: GuiObject, spec: Spec): boolean
	if g:GetAttribute("NavSkip") then
		return false
	end
	if not (g:IsA("GuiButton") or g:GetAttribute("NavSelectable")) then
		return false
	end
	if g:IsA("GuiButton") and not (g.Active and g.Selectable) and not g:GetAttribute("NavSelectable") then
		return false -- Selectable = false marks a tap catcher (a sheet's body, a backdrop)
	end
	local size = g.AbsoluteSize
	if size.X < 4 or size.Y < 4 then
		return false
	end
	local vp = viewport()
	-- full-screen catchers (a dim backdrop that closes on click) are not choices
	if size.X >= vp.X * 0.8 and size.Y >= vp.Y * 0.8 then
		return false
	end
	if not shown(g) then
		return false
	end
	-- off screen (slid away) unless a scrolling list clips it: the list scrolls to it
	if not spec.offscreen and not g:FindFirstAncestorWhichIsA("ScrollingFrame") then
		local pos = SelectionRing.rectOf(g)
		if pos.X + size.X < 0 or pos.Y + size.Y < 0 or pos.X > vp.X or pos.Y > vp.Y then
			return false
		end
	end
	if spec.filter and not spec.filter(g) then
		return false
	end
	return true
end

local function guisFor(spec: Spec): { Instance }
	local out: { Instance } = {}
	if spec.root then
		local r = spec.root()
		if r then
			table.insert(out, r)
		end
		return out
	end
	local pg = player:FindFirstChild("PlayerGui")
	if not pg then
		return out
	end
	for _, name in spec.gui or {} do
		if string.sub(name, -1) == "*" then
			local prefix = string.sub(name, 1, -2)
			for _, c in pg:GetChildren() do
				if c:IsA("ScreenGui") and c.Enabled and string.sub(c.Name, 1, #prefix) == prefix then
					table.insert(out, c)
				end
			end
		else
			local g = pg:FindFirstChild(name)
			if g and (not g:IsA("ScreenGui") or (g :: ScreenGui).Enabled) then
				table.insert(out, g)
			end
		end
	end
	-- the topmost first
	table.sort(out, function(a, b)
		local da = if a:IsA("ScreenGui") then a.DisplayOrder else 0
		local db = if b:IsA("ScreenGui") then b.DisplayOrder else 0
		return da > db
	end)
	return out
end

local function collect(root: Instance, spec: Spec): { GuiObject }
	local out: { GuiObject } = {}
	for _, d in root:GetDescendants() do
		if d:IsA("GuiObject") and selectable(d, spec) then
			table.insert(out, d)
		end
	end
	return out
end

-- Best effort for a context with no gui named: the topmost enabled ScreenGui (not the HUD) that has buttons.
local SYSTEM: { [string]: boolean } = {
	HUD = true,
	SelectionRing = true,
	InputMonitor = true,
	SprintArc = true,
	DebugToggle = true,
	TouchGui = true,
}
local function bestEffort(spec: Spec): { GuiObject }
	local pg = player:FindFirstChild("PlayerGui")
	if not pg then
		return {}
	end
	local guis = {}
	for _, c in pg:GetChildren() do
		if c:IsA("ScreenGui") and c.Enabled and not SYSTEM[c.Name] then
			table.insert(guis, c)
		end
	end
	table.sort(guis, function(a, b)
		return a.DisplayOrder > b.DisplayOrder
	end)
	for _, g in guis do
		local list = collect(g, spec)
		if #list > 0 then
			return list
		end
	end
	return {}
end

local function selectablesOf(ctx: Context): { GuiObject }
	local spec = ctx.spec
	if not spec.gui and not spec.root then
		return bestEffort(spec)
	end
	for _, g in guisFor(spec) do
		local list = collect(g, spec)
		if #list > 0 then
			return list
		end
	end
	return {}
end

local function rect(g: GuiObject): NavMath.Rect
	local pos, size = SelectionRing.rectOf(g)
	return { x = pos.X, y = pos.Y, w = size.X, h = size.Y }
end

local function defaultOf(ctx: Context, list: { GuiObject }): GuiObject?
	local d = ctx.spec.default and ctx.spec.default()
	if d and table.find(list, d) then
		return d
	end
	for _, g in list do
		if g:GetAttribute("NavDefault") then
			return g
		end
	end
	-- the biggest button, ties to the top-left
	local best, bestArea = nil, -1
	for _, g in list do
		local a = g.AbsoluteSize.X * g.AbsoluteSize.Y
		if a > bestArea + 1 then
			best, bestArea = g, a
		end
	end
	return best
end

------------------------------------------------------------------ selection

local function scrollIntoView(g: GuiObject)
	local sf = g:FindFirstAncestorWhichIsA("ScrollingFrame")
	if not sf then
		return
	end
	local top = g.AbsolutePosition.Y - sf.AbsolutePosition.Y + sf.CanvasPosition.Y
	local bottom = top + g.AbsoluteSize.Y
	local y = NavMath.scrollInto(sf.CanvasPosition.Y, sf.AbsoluteWindowSize.Y, top, bottom, UI.S(12))
	local left = g.AbsolutePosition.X - sf.AbsolutePosition.X + sf.CanvasPosition.X
	local right = left + g.AbsoluteSize.X
	local x = NavMath.scrollInto(sf.CanvasPosition.X, sf.AbsoluteWindowSize.X, left, right, UI.S(12))
	if y ~= sf.CanvasPosition.Y or x ~= sf.CanvasPosition.X then
		sf.CanvasPosition = Vector2.new(x, y)
	end
end

local function choose(ctx: Context, g: GuiObject?)
	if ctx.current ~= g and g then
		UI.sound(Theme.Sounds.toast, 1.6, 0.12)
		local haptics = script.Parent:FindFirstChild("Haptics")
		if haptics then
			(require(haptics) :: any).pulse((Config :: any).HapticNav)
		end
	end
	local moved = ctx.current ~= g
	ctx.current = g
	if g then
		scrollIntoView(g)
		if moved and ctx.spec.onSelect then
			ctx.spec.onSelect(g)
		end
	end
end

-- Move the top context's selection to g (a screen that knows where the pad should land next, e.g. BUY).
function GamepadNav.focus(g: GuiObject)
	local ctx = stack[#stack]
	if ctx and ClientState.inputDevice == "gamepad" then
		choose(ctx, g)
	end
end

local function active(): boolean
	return ClientState.inputDevice == "gamepad" and #stack > 0
end

local cache: { GuiObject } = {}

function GamepadNav.move(dir: string): boolean
	local ctx = stack[#stack]
	if not ctx or ClientState.inputDevice ~= "gamepad" then
		return false
	end
	local list = selectablesOf(ctx)
	local cur = ctx.current
	if not cur or not table.find(list, cur) then
		choose(ctx, defaultOf(ctx, list))
		return true
	end
	local rects = {}
	local others = {}
	for _, g in list do
		if g ~= cur then
			table.insert(rects, rect(g))
			table.insert(others, g)
		end
	end
	local i = NavMath.pick(rect(cur), dir, rects)
	if i then
		choose(ctx, others[i])
	end
	return true
end

-- Page a long list: the screen's hook, else scroll the selection's ScrollingFrame by a window.
local function page(dir: number)
	local ctx = stack[#stack]
	if not ctx then
		return
	end
	if ctx.spec.page then
		ctx.spec.page(dir)
		return
	end
	local cur = ctx.current
	local sf = cur and cur:FindFirstAncestorWhichIsA("ScrollingFrame")
	if not sf then
		return
	end
	local h = sf.AbsoluteWindowSize.Y * 0.9
	sf.CanvasPosition = Vector2.new(sf.CanvasPosition.X, math.max(0, sf.CanvasPosition.Y + dir * h))
	-- land on the first selectable now in view
	task.defer(function()
		local list = selectablesOf(ctx)
		local best, bestD = nil, math.huge
		for _, g in list do
			if g:FindFirstAncestorWhichIsA("ScrollingFrame") == sf then
				local y = g.AbsolutePosition.Y - sf.AbsolutePosition.Y
				if y >= 0 and y < sf.AbsoluteWindowSize.Y then
					local d = math.abs(y - (if dir > 0 then 0 else sf.AbsoluteWindowSize.Y))
					if d < bestD then
						best, bestD = g, d
					end
				end
			end
		end
		if best then
			choose(ctx, best)
		end
	end)
end

------------------------------------------------------------------ the hub HUD toggle

local function hubHud(): GuiObject?
	local pg = player:FindFirstChild("PlayerGui")
	local hud = pg and pg:FindFirstChild("HUD")
	local root = hud and hud:FindFirstChild("HubHUD", true)
	return if root and root:IsA("GuiObject") then root else nil
end

GamepadNav.register("hud", {
	root = hubHud,
	default = function()
		local root = hubHud()
		local play = root and root:FindFirstChild("Play", true)
		return if play and play:IsA("GuiObject") then play else nil
	end,
	back = function()
		GamepadNav.pop("hud")
	end,
})

local function toggleHud()
	if GamepadNav.isOpen("hud") then
		GamepadNav.pop("hud")
	elseif ClientState.inHub() and not ClientState.blocked() then
		GamepadNav.push("hud")
	end
end

------------------------------------------------------------------ input

local dpadHeld: { [string]: number } = {}
local dpadLast: { [string]: number } = {}
local stickHeld: string? = nil
local stickSince = 0
local stickLast: number? = nil

local DPAD: { [string]: string } = { DPadUp = "up", DPadDown = "down", DPadLeft = "left", DPadRight = "right" }

local function isToggle(key: string): boolean
	for _, k in (Config :: any).NavToggleButtons or {} do
		if k == key then
			return true
		end
	end
	return false
end

local function hasSelectables(): boolean
	local ctx = stack[#stack]
	return ctx ~= nil and ctx.current ~= nil
end

local function onNav(_name: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if string.sub(input.UserInputType.Name, 1, 7) ~= "Gamepad" then
		return Enum.ContextActionResult.Pass
	end
	local key = input.KeyCode.Name
	local began = state == Enum.UserInputState.Begin
	-- the hub HUD toggle (in a run Create is the scoreboard)
	if isToggle(key) and ClientState.inHub() then
		if began then
			toggleHud()
		end
		return Enum.ContextActionResult.Sink
	end
	if not active() then
		return Enum.ContextActionResult.Pass
	end
	local ctx = stack[#stack]
	if ctx.spec.passive and not hasSelectables() then
		return Enum.ContextActionResult.Pass
	end
	local dir = DPAD[key]
	if dir then
		if began then
			dpadHeld[key] = os.clock()
			dpadLast[key] = os.clock()
			GamepadNav.move(dir)
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			dpadHeld[key] = nil
			dpadLast[key] = nil
		end
		return Enum.ContextActionResult.Sink
	end
	if key == "ButtonL1" or key == "ButtonR1" then
		if began and ctx.spec.tabs then
			ctx.spec.tabs(if key == "ButtonL1" then -1 else 1)
			UI.sound(Theme.Sounds.toast, 1.2, 0.25)
		end
		return Enum.ContextActionResult.Sink
	end
	if key == "ButtonL2" or key == "ButtonR2" then
		if began then
			page(if key == "ButtonL2" then -1 else 1)
		end
		return Enum.ContextActionResult.Sink
	end
	if key == "ButtonB" then
		if began and ctx.spec.back then
			ctx.spec.back()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass -- the screen's own ButtonB handler
	end
	if key == "Thumbstick1" then
		return Enum.ContextActionResult.Sink -- RenderStepped reads it for the repeat
	end
	return Enum.ContextActionResult.Pass
end

------------------------------------------------------------------ the frame

local navGui: ScreenGui? = nil
local function paintDebug(list: { GuiObject })
	if not GamepadNav.showNav then
		if navGui then
			navGui:Destroy()
			navGui = nil
		end
		return
	end
	local g = navGui
	if not g then
		g = UI.new("ScreenGui", {
			Name = "NavDebug",
			IgnoreGuiInset = true,
			ResetOnSpawn = false,
			DisplayOrder = 61,
			Parent = player:WaitForChild("PlayerGui"),
		}) :: ScreenGui
		navGui = g
	end
	local gg = g :: ScreenGui
	gg:ClearAllChildren()
	for _, s in list do
		local r = rect(s)
		local box = UI.frame({
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(r.x, r.y),
			Size = UDim2.fromOffset(r.w, r.h),
			Parent = gg,
		})
		UI.new("UIStroke", { Color = Theme.Colors.blue, Thickness = 1, Parent = box })
	end
	local names = {}
	for _, c in stack do
		table.insert(names, c.name)
	end
	UI.text({
		Text = "NAV  "
			.. (if #names > 0 then table.concat(names, " > ") else "(none)")
			.. "  ·  "
			.. #list
			.. " selectable",
		TextSize = UI.S(14),
		TextColor3 = Theme.Colors.blue,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(UI.S(16), UI.S(60)),
		Size = UDim2.fromOffset(UI.S(600), UI.S(20)),
		Parent = gg,
	})
end

local SKIP_AUTO: { [string]: boolean } = {} -- reasons that are never screens

local function syncAuto()
	local want: { [string]: boolean } = {}
	for reason in ClientState.blocks do
		if not SKIP_AUTO[reason] then
			want[reason] = true
		end
	end
	for reason in ClientState.movementLocks() do
		if not SKIP_AUTO[reason] then
			want[reason] = true
		end
	end
	-- pop what closed (auto contexts only), push what opened
	for i = #stack, 1, -1 do
		local c = stack[i]
		if c.auto and not want[c.name] then
			popCtx(c.name)
		end
	end
	for reason in want do
		if not find(reason) then
			local spec = SCREENS[reason]
			if not spec then
				warn("[GHS Nav] WARN no context registered for " .. reason .. " (best-effort walk)")
				spec = {}
				SCREENS[reason] = spec
			end
			pushCtx(reason, spec, true)
		end
	end
	-- a screen opening over the hub HUD selection ends it
	if GamepadNav.isOpen("hud") and (ClientState.blocked() or not ClientState.inHub()) then
		popCtx("hud")
	end
end

local lastScan = 0
local lastTop: Context? = nil
local function frame()
	syncAuto()
	local ctx = stack[#stack]
	local list: { GuiObject } = cache
	-- The scan walks a screen's whole tree: only on a pad (or the debug view), at most every 0.1 s.
	local now0 = os.clock()
	if not ctx then
		list = {}
	elseif (active() or GamepadNav.showNav) and (ctx ~= lastTop or now0 - lastScan >= 0.1) then
		list = selectablesOf(ctx)
		lastScan = now0
	end
	if ctx and ctx.current and not (ctx.current :: GuiObject):IsDescendantOf(game) then
		list = selectablesOf(ctx) -- the selection was destroyed (a rebuilt list): look again now
	end
	lastTop = ctx
	cache = list
	paintDebug(list)
	if not active() or not ctx then
		if selectedByUs and GuiService.SelectedObject == selectedByUs then
			GuiService.SelectedObject = nil
		end
		selectedByUs = nil
		SelectionRing.set(nil)
		return
	end
	if #list == 0 then
		if not ctx.warned and not ctx.spec.quiet then
			ctx.warned = true
			warn("[GHS Nav] WARN no selectables " .. ctx.name)
		end
		ctx.current = nil
		if selectedByUs and GuiService.SelectedObject == selectedByUs then
			GuiService.SelectedObject = nil
		end
		selectedByUs = nil
		SelectionRing.set(nil)
		return
	end
	if not ctx.current or not table.find(list, ctx.current) then
		ctx.current = defaultOf(ctx, list)
		if ctx.current then
			scrollIntoView(ctx.current)
		end
	end
	local cur = ctx.current :: GuiObject
	-- held directions repeat
	local now = os.clock()
	local delay, every = Config.NavRepeatDelaySec, Config.NavRepeatSec
	for key, since in dpadHeld do
		local last = dpadLast[key]
		if last and now - since >= delay and NavMath.repeatStep(since, last, now, delay, every) then
			dpadLast[key] = now
			GamepadNav.move(DPAD[key])
		end
	end
	local sx, sy = 0, 0
	if UserInputService.GamepadEnabled then
		for _, s in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
			if s.KeyCode == Enum.KeyCode.Thumbstick1 then
				sx, sy = s.Position.X, s.Position.Y
			end
		end
	end
	local sdir = NavMath.stickDir(sx, sy, Config.NavStickPress)
	if sdir ~= stickHeld then
		stickHeld = sdir
		stickSince = now
		stickLast = nil
	end
	if sdir and NavMath.repeatStep(stickSince, stickLast, now, delay, every) then
		stickLast = now
		GamepadNav.move(sdir)
	end
	cur = ctx.current :: GuiObject
	-- Roblox's own navigation stays put (we move it); A activates what is selected.
	cur.Selectable = true
	cur.NextSelectionUp = cur
	cur.NextSelectionDown = cur
	cur.NextSelectionLeft = cur
	cur.NextSelectionRight = cur
	if GuiService.SelectedObject ~= cur then
		GuiService.SelectedObject = cur
	end
	selectedByUs = cur
	SelectionRing.set(cur)
end

function GamepadNav.selectables(): { GuiObject }
	return cache
end

function GamepadNav.init()
	pcall(function()
		GuiService.AutoSelectGuiEnabled = false
	end)
	local keys: { Enum.KeyCode } = {
		Enum.KeyCode.DPadUp,
		Enum.KeyCode.DPadDown,
		Enum.KeyCode.DPadLeft,
		Enum.KeyCode.DPadRight,
		Enum.KeyCode.ButtonL1,
		Enum.KeyCode.ButtonR1,
		Enum.KeyCode.ButtonL2,
		Enum.KeyCode.ButtonR2,
		Enum.KeyCode.ButtonB,
		Enum.KeyCode.Thumbstick1,
	}
	for _, k in (Config :: any).NavToggleButtons or {} do
		local ok, code = pcall(function()
			return (Enum.KeyCode :: any)[k]
		end)
		if ok and code and not table.find(keys, code) then
			table.insert(keys, code)
		end
	end
	ContextActionService:BindActionAtPriority(
		"GHSNav",
		onNav,
		false,
		Enum.ContextActionPriority.High.Value + 30,
		table.unpack(keys)
	)
	RunService.RenderStepped:Connect(frame)
	ClientState.DeviceChanged:Connect(function(d: string)
		if d ~= "gamepad" and GamepadNav.isOpen("hud") then
			popCtx("hud")
		end
	end)
end

return GamepadNav
