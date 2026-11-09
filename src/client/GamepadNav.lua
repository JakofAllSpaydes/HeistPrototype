--!strict
-- Brief 11: screens on a pad, on top of Roblox's own gamepad selection (its highlight, its D-pad / stick movement,
-- A to press). This module only does what Roblox does not:
--   * when a screen opens on a pad, select a sensible first button in it (NavDefault, the screen's default, else
--     the biggest), and keep the selection inside the open screen (if Roblox moves it to the HUD behind, it comes
--     back); when the screen closes, clear it
--   * in the hub, Roblox's Select toggle lands on PLAY instead of whatever Roblox picks
--   * L1 / R1 call the screen's tabs hook, L2 / R2 its page hook (or scroll its list), B the screen's back hook when
--     it has one (most screens handle ButtonB themselves)
-- Screens push themselves through their ClientState block / movement-lock reason (SCREENS names each one's gui);
-- the rest use GamepadNav.push / pop (the scoreboard). Logs: [GHS Nav] push / pop / WARN no selectables.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ClientState = require(script.Parent:WaitForChild("ClientState"))
local NavMath = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("NavMath"))

local GamepadNav = {}

export type Spec = {
	gui: { string }?, -- ScreenGui names in PlayerGui (the topmost one with selectables wins); "Minigame_*" = prefix
	root: (() -> GuiObject?)?, -- or a root object
	default: (() -> GuiObject?)?, -- the first selection (else NavDefault, else the biggest button)
	tabs: ((dir: number) -> ())?, -- L1 / R1: the small categories (or a screen's only tab strip)
	pages: ((dir: number) -> ())?, -- L2 / R2: the big categories of a two-level screen (else page)
	page: ((dir: number) -> ())?, -- L2 / R2 on a one-level screen (default: scroll the selection's list a page)
	merge: boolean?, -- the selectables of all its guis together (else the topmost gui that has any)
	back: (() -> ())?, -- B, for screens with no ButtonB handler of their own
	filter: ((g: GuiObject) -> boolean)?, -- extra test for a selectable
	quiet: boolean?, -- no WARN when it has nothing to select (cutscenes, spectate)
	onSelect: ((g: GuiObject) -> ())?, -- the selection moved to g (the Skill Web pans to it)
}

type Context = {
	name: string,
	spec: Spec,
	auto: boolean,
	current: GuiObject?,
	warned: boolean,
	lastAt: Vector2?, -- the selection's centre, so a rebuilt screen keeps your place
	lastText: string?,
}

local SCREENS: { [string]: Spec } = {
	queue = { gui = { "CreateMatch" } },
	meta = { gui = { "MetaScene" } },
	overlay = { gui = { "UpgradeOverlay" } },
	cinematic = { gui = { "RunEnd", "SummaryCrateCard", "BossCutscene" }, quiet = true, merge = true },
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
	-- each game plays the pad its own way (Minigames/Frame): no selection, so the left stick still walks
	minigame = {
		gui = { "Minigame_*" },
		quiet = true,
		filter = function(): boolean
			return false
		end,
	},
}

local player = Players.LocalPlayer
local stack: { Context } = {}
local selectedByUs = false

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

function GamepadNav.push(name: string, spec: Spec?)
	pushCtx(name, spec or SCREENS[name] or {}, false)
end

function GamepadNav.pop(name: string)
	popCtx(name)
end

function GamepadNav.isOpen(name: string): boolean
	return find(name) ~= nil
end

------------------------------------------------------------------ what a screen can select

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

local function selectable(g: GuiObject, spec: Spec): boolean
	if not g:IsA("GuiButton") or g:GetAttribute("NavSkip") or not g.Selectable or not g.Active then
		return false
	end
	local size = g.AbsoluteSize
	if size.X < 4 or size.Y < 4 then
		return false
	end
	local cam = workspace.CurrentCamera
	local vp = if cam then cam.ViewportSize else Vector2.new(1920, 1080)
	if size.X >= vp.X * 0.8 and size.Y >= vp.Y * 0.8 then
		return false -- a full-screen tap catcher
	end
	if not shown(g) then
		return false
	end
	return spec.filter == nil or spec.filter(g)
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
	table.sort(out, function(a, b)
		local da = if a:IsA("ScreenGui") then a.DisplayOrder else 0
		local db = if b:IsA("ScreenGui") then b.DisplayOrder else 0
		return da > db
	end)
	return out
end

-- The screen's gui that holds its selectables now (the topmost with any), and the list.
local function selectablesOf(ctx: Context): { GuiObject }
	local all: { GuiObject } = {}
	for _, root in guisFor(ctx.spec) do
		local list = {}
		for _, d in root:GetDescendants() do
			if d:IsA("GuiObject") and selectable(d, ctx.spec) then
				table.insert(list, d)
			end
		end
		if ctx.spec.merge then
			for _, g in list do
				table.insert(all, g)
			end
		elseif #list > 0 then
			return list
		end
	end
	return all
end

local function centre(g: GuiObject): Vector2
	return g.AbsolutePosition + g.AbsoluteSize / 2
end

local function rect(g: GuiObject): NavMath.Rect
	local p, s = g.AbsolutePosition, g.AbsoluteSize
	return { x = p.X, y = p.Y, w = s.X, h = s.Y }
end

-- Roblox moves the selection along NextSelection*: point those at the geometric neighbours inside the screen, so
-- down goes to what is directly below.
local function link(sel: GuiObject, list: { GuiObject })
	local others, rects = {}, {}
	for _, g in list do
		if g ~= sel then
			table.insert(others, g)
			table.insert(rects, rect(g))
		end
	end
	local from = rect(sel)
	local function to(dir: string): GuiObject?
		local i = NavMath.pick(from, dir, rects)
		return if i then others[i] else sel -- nothing that way: stay put (never leave the screen)
	end
	sel.NextSelectionUp = to("up")
	sel.NextSelectionDown = to("down")
	sel.NextSelectionLeft = to("left")
	sel.NextSelectionRight = to("right")
end

-- After a press rebuilds the screen (UPGRADE, a tab), the button nearest where the selection was (the same words
-- first), so the pad keeps its place instead of jumping to the default.
local function nearestTo(ctx: Context, list: { GuiObject }): GuiObject?
	local at = ctx.lastAt
	if not at then
		return nil
	end
	local best, bestD = nil, math.huge
	for _, g in list do
		local d = (centre(g) - at).Magnitude
		if ctx.lastText and (g :: any).Text == ctx.lastText then
			d *= 0.5
		end
		if d < bestD then
			best, bestD = g, d
		end
	end
	return best
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
	local best, bestArea = nil, -1
	for _, g in list do
		local a = g.AbsoluteSize.X * g.AbsoluteSize.Y
		if a > bestArea + 1 then
			best, bestArea = g, a
		end
	end
	return best
end

local function select(g: GuiObject?)
	if GuiService.SelectedObject ~= g then
		GuiService.SelectedObject = g
	end
	selectedByUs = g ~= nil
end

-- Point the selection at g (a screen that knows where the pad goes next, e.g. the Skill Web's BUY).
function GamepadNav.focus(g: GuiObject)
	local ctx = stack[#stack]
	if ctx and ClientState.inputDevice == "gamepad" then
		ctx.current = g
		select(g)
	end
end

------------------------------------------------------------------ the frame

local function syncAuto()
	local want: { [string]: boolean } = {}
	for reason in ClientState.blocks do
		want[reason] = true
	end
	for reason in ClientState.movementLocks() do
		want[reason] = true
	end
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
				warn("[GHS Nav] WARN no context registered for " .. reason)
				spec = {}
				SCREENS[reason] = spec
			end
			pushCtx(reason, spec, true)
		end
	end
end

local lastCheck = 0
local function frame()
	syncAuto()
	local ctx = stack[#stack]
	if ClientState.inputDevice ~= "gamepad" or not ctx then
		if selectedByUs then
			select(nil)
		end
		return
	end
	-- Roblox moves the selection; keep it inside the open screen. The tree walk runs a few times a second.
	local now = os.clock()
	local sel = GuiService.SelectedObject
	if ctx.current and sel == ctx.current and now - lastCheck < 0.25 then
		return
	end
	lastCheck = now
	local list = selectablesOf(ctx)
	if #list == 0 then
		if not ctx.warned and not ctx.spec.quiet then
			ctx.warned = true
			warn("[GHS Nav] WARN no selectables " .. ctx.name)
		end
		if selectedByUs then
			select(nil)
		end
		ctx.current = nil
		return
	end
	if sel and table.find(list, sel) then
		if ctx.current ~= sel and ctx.spec.onSelect then
			ctx.spec.onSelect(sel)
		end
		ctx.current = sel
		ctx.lastAt = centre(sel)
		ctx.lastText = (sel :: any).Text
		link(sel, list)
		return
	end
	local back = ctx.current
	if not (back and table.find(list, back)) then
		-- a screen's marked next step (CONFIRM after a crate, PLAY AGAIN) wins; else keep the place; else the default
		local marked = nil
		for _, g in list do
			if g:GetAttribute("NavDefault") then
				marked = g
			end
		end
		back = marked or nearestTo(ctx, list) or defaultOf(ctx, list)
	end
	ctx.current = back
	if back then
		link(back, list)
	end
	select(back)
end

------------------------------------------------------------------ L1 / R1 / L2 / R2 / B in a screen

local function page(ctx: Context, dir: number)
	if ctx.spec.page then
		ctx.spec.page(dir)
		return
	end
	local cur = GuiService.SelectedObject
	local sf = cur and cur:FindFirstAncestorWhichIsA("ScrollingFrame")
	if sf then
		local h = sf.AbsoluteWindowSize.Y * 0.9
		sf.CanvasPosition = Vector2.new(sf.CanvasPosition.X, math.max(0, sf.CanvasPosition.Y + dir * h))
	end
end

local function onPad(_name: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	local ctx = stack[#stack]
	if not ctx or ClientState.inputDevice ~= "gamepad" or string.sub(input.UserInputType.Name, 1, 7) ~= "Gamepad" then
		return Enum.ContextActionResult.Pass
	end
	local key = input.KeyCode.Name
	local began = state == Enum.UserInputState.Begin
	if key == "ButtonL1" or key == "ButtonR1" then
		if began and ctx.spec.tabs then
			ctx.spec.tabs(if key == "ButtonL1" then -1 else 1)
		end
		return Enum.ContextActionResult.Sink
	elseif key == "ButtonL2" or key == "ButtonR2" then
		if began then
			local dir = if key == "ButtonL2" then -1 else 1
			if ctx.spec.pages then
				ctx.spec.pages(dir)
			else
				page(ctx, dir)
			end
		end
		return Enum.ContextActionResult.Sink
	elseif key == "ButtonB" and ctx.spec.back then
		if began then
			ctx.spec.back()
		end
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

------------------------------------------------------------------ the hub: Roblox's Select toggle lands on PLAY

local function hubPlay(): GuiObject?
	local pg = player:FindFirstChild("PlayerGui")
	local hud = pg and pg:FindFirstChild("HUD")
	local play = hud and hud:FindFirstChild("Play", true)
	return if play and play:IsA("GuiObject") and play.Visible then play else nil
end

function GamepadNav.init()
	ContextActionService:BindActionAtPriority(
		"GHSNav",
		onPad,
		false,
		Enum.ContextActionPriority.High.Value + 30,
		Enum.KeyCode.ButtonL1,
		Enum.KeyCode.ButtonR1,
		Enum.KeyCode.ButtonL2,
		Enum.KeyCode.ButtonR2,
		Enum.KeyCode.ButtonB
	)
	RunService.RenderStepped:Connect(frame)
	local prev: GuiObject? = nil
	GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
		local sel = GuiService.SelectedObject
		if sel and not prev and #stack == 0 and ClientState.inHub() then
			-- the player just turned Roblox's selection on in the hub: start on PLAY
			local play = hubPlay()
			if play and sel ~= play then
				prev = play
				GuiService.SelectedObject = play
				return
			end
		end
		prev = sel
	end)
end

return GamepadNav
