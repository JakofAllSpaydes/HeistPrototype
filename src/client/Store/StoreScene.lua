--!strict
-- Brief 6 (Round 17b): the premium store as an overlay window over a dark dim, not a scene. Opens from the hub's
-- SHOP tile, the Gold +, and VIEW CRATE / VIEW BUNDLE / VIEW VIP deep links. Header: SHOP, Gold with + and LEAVE
-- (Round 18: no R$ balance; a tap on the dim outside the window closes it too). The tabs are a rail on the left (FEATURED · CRATES · BOOSTS · VIP · GOLD, a red
-- dot = something claimable or new) and the whole store is one scrolling page: a tab scrolls to the start of its
-- section and the rail follows the scroll, so nothing is ever hidden. Every section is a module under Store/ that
-- renders into its own fixed-height frame. The window keeps clear of the Roblox top bar (Fx.topInset).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Client = script.Parent.Parent
local ClientState = require(Client:WaitForChild("ClientState"))
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local HUD = require(Client:WaitForChild("HUD"))
local PurchaseSheet = require(Client:WaitForChild("PurchaseSheet"))
local Fx = require(script.Parent:WaitForChild("Fx"))
local GamepadNav = require(Client:WaitForChild("GamepadNav"))

local StoreScene = {}

local TABS = { "FEATURED", "CRATES", "BOOSTS", "VIP", "GOLD" }
-- Each section's height at the basis (its module lays out inside it).
local HEIGHTS = { FEATURED = 880, CRATES = 540, BOOSTS = 620, VIP = 440, GOLD = 600 }
local MODULES =
	{ FEATURED = "FeaturedTab", CRATES = "CratesTab", BOOSTS = "BoostsTab", VIP = "VipTab", GOLD = "GoldTab" }
local ACCENT = {
	FEATURED = Color3.fromHex("E8792A"),
	CRATES = Color3.fromHex("A864E8"),
	BOOSTS = Color3.fromHex("E8554D"),
	VIP = Color3.fromHex("F2C14E"),
	GOLD = Color3.fromHex("E8B64C"),
}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = Workspace.CurrentCamera :: Camera

local tabs: { [string]: any } = {}
local open = false
local gui: ScreenGui? = nil
local scroller: ScrollingFrame? = nil
local overlay: Frame? = nil
local sections: { [string]: Frame } = {}
local sectionCtx: { [string]: any } = {}
local railButtons: { [string]: { button: TextButton, dot: Frame, label: TextLabel } } = {}
local railHighlight: Frame? = nil
local goldLabel: TextLabel? = nil
local shownGold = -1
local currentTab = "FEATURED"
local scrollTween: Tween? = nil
local baseCtx: any

------------------------------------------------------------------ Values
local function profile(): any
	local sync = ClientState.sync
	return sync and sync.profile
end

local function paintBalances(animate: boolean)
	local p = profile()
	local gold = if p and typeof(p.gold) == "number" then p.gold else 0
	local gl = goldLabel
	if gl and gold ~= shownGold then
		if animate and shownGold >= 0 then
			Fx.countUp(gl, shownGold, gold, 0.9, nil, gold > shownGold)
			UI.punch(gl, if gold > shownGold then 1.2 else 0.92, 0.35)
		else
			gl.Text = UI.fmtInt(gold)
		end
		shownGold = gold
	end
end

local function paintDots()
	local p = profile()
	for tab, b in railButtons do
		local mod = tabs[tab]
		b.dot.Visible = mod ~= nil and mod.badge ~= nil and p ~= nil and mod.badge(p) == true
	end
end

------------------------------------------------------------------ The rail
local function highlight(tab: string, instant: boolean?)
	currentTab = tab
	local hl = railHighlight
	local b = railButtons[tab]
	if hl and b then
		local y = b.button.Position.Y.Offset
		if instant then
			hl.Position = UDim2.fromOffset(0, y)
		else
			UI.tween(hl, { Position = UDim2.fromOffset(0, y) }, 0.22, Enum.EasingStyle.Back)
		end
		hl.BackgroundColor3 = ACCENT[tab] or Theme.Colors.gold
	end
	for t, rb in railButtons do
		rb.label.TextColor3 = if t == tab then Theme.Colors.white else Theme.Colors.textDim
	end
end

-- Scroll the page to the start of a section.
local function scrollTo(tab: string, instant: boolean?)
	local sc = scroller
	local sec = sections[tab]
	if not sc or not sec then
		return
	end
	local y = sec.AbsolutePosition.Y - sc.AbsolutePosition.Y + sc.CanvasPosition.Y - UI.S(6)
	local maxY = math.max(0, sc.AbsoluteCanvasSize.Y - sc.AbsoluteWindowSize.Y)
	local target = Vector2.new(0, math.clamp(y, 0, maxY))
	if scrollTween then
		scrollTween:Cancel()
	end
	highlight(tab, instant)
	if instant then
		sc.CanvasPosition = target
	else
		local tw = TweenService:Create(
			sc,
			TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ CanvasPosition = target }
		)
		scrollTween = tw
		tw:Play()
	end
end

------------------------------------------------------------------ Sections
local function renderSection(tab: string, quiet: boolean, arg: any?)
	local frame = sections[tab]
	local c = sectionCtx[tab]
	local mod = tabs[tab]
	if not frame or not c or not mod then
		return
	end
	for _, child in frame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	c.quiet = quiet
	c.arg = arg
	mod.render(c)
end

local function clearOverlay()
	local o = overlay
	if o then
		for _, c in o:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
	end
end

------------------------------------------------------------------ Build
local function build(focus: string, arg: any?)
	if gui then
		gui:Destroy()
	end
	local S = UI.S
	local mobile = ClientState.isMobile
	local vp = camera.ViewportSize
	local top = Fx.topInset()
	local g = UI.new("ScreenGui", {
		Name = "StoreScene",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 9,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	}) :: ScreenGui
	gui = g
	-- Round 24d: on mobile every label in the store reads Config.MobileStoreTextScale bigger (FixedTextSize opts out).
	if mobile and (Config.MobileStoreTextScale or 1) ~= 1 then
		local k = Config.MobileStoreTextScale
		g.DescendantAdded:Connect(function(d)
			if (d:IsA("TextLabel") or d:IsA("TextButton")) and not d:GetAttribute("FixedTextSize") then
				local t = d :: TextLabel
				t.TextSize = math.round(t.TextSize * k)
			end
		end)
	end
	railButtons = {}
	sections = {}
	sectionCtx = {}
	shownGold = -1

	-- The dim behind the window: a tap on it (outside the window) closes the store.
	local dim = UI.button({
		Name = "Dim",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = g,
	})
	UI.tween(dim, { BackgroundTransparency = 0.3 }, 0.25)
	local win: Frame? = nil
	-- Round 28e: a tap closes the store only when it lands outside the whole window. On touch the window frame did
	-- not keep a tap on its empty space from reaching the dim, so the tap's own position decides (checked with and
	-- without the top-bar inset, since touch positions may or may not include it).
	local function insideWindow(input: InputObject?): boolean
		local wf = win
		if not wf or not input then
			return false
		end
		local p = Vector2.new(input.Position.X, input.Position.Y)
		local a, s = wf.AbsolutePosition, wf.AbsoluteSize
		for _, q in { p, p + game:GetService("GuiService"):GetGuiInset() } do
			if q.X >= a.X and q.X <= a.X + s.X and q.Y >= a.Y and q.Y <= a.Y + s.Y then
				return true
			end
		end
		return false
	end
	dim.Activated:Connect(function(input: InputObject?)
		if insideWindow(input) then
			return
		end
		if not PurchaseSheet.isOpen() and not (overlay and #overlay:GetChildren() > 0) then
			StoreScene.close()
		end
	end)

	-- The window, clear of the top bar.
	-- Round 21: the window covers Config.PremiumWindowScale of the old footprint each way (text keeps its size,
	-- the page scrolls more), centred in the space under the top bar.
	local k = Config.PremiumWindowScale
	local fullH = vp.Y - top - S(16)
	local winW = math.floor(math.min(vp.X - S(32), S(1240)) * k)
	local winH = math.floor(fullH * k)
	local w = UI.frame({
		Name = "Window",
		BackgroundColor3 = Color3.fromHex("0E0E12"),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, top + math.floor((fullH - winH) / 2)),
		Size = UDim2.fromOffset(winW, winH),
		Active = true,
		ZIndex = 3,
		Parent = g,
	})
	win = w
	UI.corner(w, S(16))
	UI.stroke(w, Color3.fromHex("F2C14E"), S(1.5), 0.55)
	UI.new("UIGradient", {
		Color = ColorSequence.new(Color3.fromHex("1C1A22"), Color3.fromHex("0A0A0D")),
		Rotation = 90,
		Parent = w,
	})
	local winScale = UI.new("UIScale", { Scale = 0.94, Parent = w })
	UI.tween(winScale, { Scale = 1 }, 0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	Fx.slideIn(w, UDim2.fromOffset(0, S(30)), 0.3)

	-- Header: SHOP · Gold · LEAVE.
	local headerH = if mobile then S(56) else S(64)
	local header = UI.frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, headerH), ZIndex = 4, Parent = w })
	local title = UI.text({
		Text = "SHOP",
		FontFace = Theme.Fonts.display,
		TextSize = if mobile then S(26) else S(34),
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(S(22), 0),
		Size = UDim2.new(0, S(140), 1, 0),
		ZIndex = 5,
		Parent = header,
	})
	UI.stroke(title, Color3.new(0, 0, 0), S(1.5), 0.3)
	UI.new("UIGradient", {
		Color = ColorSequence.new(Color3.fromHex("FFE7A3"), Color3.fromHex("E8A33C")),
		Rotation = 90,
		Parent = title,
	})
	UI.frame({
		BackgroundColor3 = Theme.Colors.gold,
		BackgroundTransparency = 0.6,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, S(16), 1, 0),
		Size = UDim2.new(1, -S(32), 0, S(1)),
		ZIndex = 5,
		Parent = header,
	})
	local right = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -S(14), 0.5, 0),
		Size = UDim2.fromOffset(0, headerH - S(16)),
		AutomaticSize = Enum.AutomaticSize.X,
		ZIndex = 5,
		Parent = header,
	})
	UI.list(right, Enum.FillDirection.Horizontal, S(10), Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
	local function balancePill(order: number, glyph: string, color: Color3, onPlus: () -> ()): TextLabel
		local pill = UI.frame({
			BackgroundColor3 = Color3.fromHex("1E1E25"),
			Size = UDim2.fromOffset(if mobile then S(124) else S(160), headerH - S(22)),
			LayoutOrder = order,
			ZIndex = 5,
			Parent = right,
		})
		UI.corner(pill, S(8))
		UI.stroke(pill, color, S(1.5), 0.3)
		UI.text({
			Text = glyph,
			FontFace = Theme.Fonts.display,
			TextSize = S(20),
			TextColor3 = color,
			Position = UDim2.fromOffset(S(6), 0),
			Size = UDim2.new(0, S(24), 1, 0),
			ZIndex = 6,
			Parent = pill,
		})
		local label = UI.text({
			Text = "0",
			FontFace = Theme.Fonts.display,
			TextSize = if mobile then S(16) else S(19),
			TextColor3 = Theme.Colors.white,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(S(36), 0),
			Size = UDim2.new(1, -S(70), 1, 0),
			ZIndex = 6,
			Parent = pill,
		})
		local plus = UI.button({
			Text = "+",
			FontFace = Theme.Fonts.display,
			TextSize = S(18),
			TextColor3 = Theme.Colors.bg,
			BackgroundColor3 = color,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -S(4), 0.5, 0),
			Size = UDim2.fromOffset(S(26), S(26)),
			ZIndex = 6,
			Parent = pill,
		})
		UI.corner(plus, S(6))
		Fx.interactive(plus)
		plus.Activated:Connect(onPlus)
		return label
	end
	goldLabel = balancePill(2, "◆", Theme.Colors.gold, function()
		scrollTo("GOLD")
	end)
	local leave, _ = Fx.button(
		right,
		if mobile then "X" else "LEAVE",
		Theme.Colors.red,
		Theme.Colors.white,
		UDim2.fromOffset(if mobile then S(44) else S(110), headerH - S(22)),
		6
	)
	leave.LayoutOrder = 3
	leave.Activated:Connect(function()
		StoreScene.close()
	end)

	-- The rail of tabs on the left.
	local railW = if mobile then S(158) else S(176) -- Round 24d: wider on mobile for the bigger labels
	local rail = UI.frame({
		Name = "Rail",
		BackgroundColor3 = Color3.fromHex("121217"),
		BackgroundTransparency = 0.2,
		Position = UDim2.fromOffset(S(12), headerH + S(12)),
		Size = UDim2.new(0, railW, 1, -headerH - S(24)),
		ZIndex = 4,
		Parent = w,
	})
	UI.corner(rail, S(12))
	local tabH = if mobile then S(64) else S(58)
	local hl = UI.frame({
		Name = "Highlight",
		BackgroundColor3 = ACCENT.FEATURED,
		BackgroundTransparency = 0.8,
		Size = UDim2.new(1, 0, 0, tabH),
		ZIndex = 5,
		Parent = rail,
	})
	UI.corner(hl, S(10))
	local bar = UI.frame({
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.new(0, S(4), 1, -S(16)),
		Position = UDim2.fromOffset(S(4), S(8)),
		ZIndex = 6,
		Parent = hl,
	})
	UI.corner(bar, S(2))
	railHighlight = hl
	for i, tab in TABS do
		local b = UI.button({
			Name = tab,
			Text = "",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, S(6) + (i - 1) * (tabH + S(4))),
			Size = UDim2.new(1, 0, 0, tabH),
			ZIndex = 7,
			Parent = rail,
		})
		local swatch = UI.frame({
			BackgroundColor3 = ACCENT[tab],
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0, S(21), 0.5, 0),
			Size = UDim2.fromOffset(S(10), S(10)),
			Rotation = 45,
			ZIndex = 8,
			Parent = b,
		})
		UI.corner(swatch, S(2))
		local label = UI.text({
			Text = tab,
			FontFace = Theme.Fonts.display,
			TextSize = if mobile then S(19) else S(18),
			TextColor3 = Theme.Colors.textDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(S(36), 0),
			Size = UDim2.new(1, -S(42), 1, 0),
			ZIndex = 8,
			Parent = b,
		})
		local dot = UI.frame({
			BackgroundColor3 = Theme.Colors.red,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -S(10), 0.5, 0),
			Size = UDim2.fromOffset(S(10), S(10)),
			Visible = false,
			ZIndex = 9,
			Parent = b,
		})
		UI.corner(dot, S(5))
		UI.stroke(dot, Color3.new(1, 1, 1), S(1), 0.3)
		b.MouseEnter:Connect(function()
			if tab ~= currentTab then
				label.TextColor3 = Theme.Colors.text
				UI.sound(Fx.Sounds.hover, 1.8, 0.1)
			end
		end)
		b.MouseLeave:Connect(function()
			if tab ~= currentTab then
				label.TextColor3 = Theme.Colors.textDim
			end
		end)
		b.Activated:Connect(function()
			UI.sound(Fx.Sounds.tab, 1.3, 0.3)
			UI.punch(swatch, 1.6, 0.25)
			scrollTo(tab)
		end)
		railButtons[tab] = { button = b, dot = dot, label = label }
	end

	-- The page: every section, one after another.
	local sc = UI.new("ScrollingFrame", {
		Name = "Page",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(S(12) + railW + S(14), headerH + S(12)),
		Size = UDim2.new(1, -(S(12) + railW + S(28)), 1, -headerH - S(24)),
		CanvasSize = UDim2.fromOffset(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = S(5),
		ScrollBarImageColor3 = Theme.Colors.gold,
		ScrollBarImageTransparency = 0.4,
		ZIndex = 4,
		Parent = w,
	}) :: ScrollingFrame
	scroller = sc
	UI.list(sc, Enum.FillDirection.Vertical, S(22))
	UI.pad(sc, S(4), S(10), S(16), S(40))
	for i, tab in TABS do
		local sec = UI.frame({
			Name = tab,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -S(8), 0, S(HEIGHTS[tab])),
			LayoutOrder = i * 2,
			ZIndex = 5,
			Parent = sc,
		})
		sections[tab] = sec
		if i < #TABS then
			-- A fading rule between sections.
			local div = UI.frame({
				BackgroundColor3 = ACCENT[TABS[i + 1]],
				BackgroundTransparency = 0.5,
				Size = UDim2.new(1, -S(8), 0, S(2)),
				LayoutOrder = i * 2 + 1,
				ZIndex = 5,
				Parent = sc,
			})
			UI.new("UIGradient", {
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0),
					NumberSequenceKeypoint.new(1, 1),
				}),
				Parent = div,
			})
		end
		local c = setmetatable({ content = sec, quiet = false, arg = nil }, { __index = baseCtx }) :: any
		c.refresh = function(loud: boolean?)
			renderSection(tab, loud ~= true, nil)
		end
		sectionCtx[tab] = c
	end
	-- The rail follows the scroll.
	sc:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		local best = TABS[1]
		for _, tab in TABS do
			local sec = sections[tab]
			if sec and sec.AbsolutePosition.Y - sc.AbsolutePosition.Y <= S(120) then
				best = tab
			end
		end
		if best ~= currentTab then
			highlight(best)
		end
	end)

	overlay = UI.frame({
		Name = "Overlay",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 30,
		Parent = g,
	})
	paintBalances(false)

	-- Every section renders; the one asked for gets the deep-link argument.
	for _, tab in TABS do
		renderSection(tab, false, if tab == focus then arg else nil)
	end
	highlight(focus, true)
	task.defer(function()
		scrollTo(focus, true)
	end)
	paintDots()
end

------------------------------------------------------------------ Open / close
function StoreScene.isOpen(): boolean
	return open
end

function StoreScene.select(tab: string, arg: any?)
	if not open then
		StoreScene.open(tab, arg)
		return
	end
	if arg ~= nil then
		renderSection(tab, true, arg)
	end
	scrollTo(tab)
end

function StoreScene.open(tab: string?, arg: any?)
	if not ClientState.inHub() or ClientState.downed or ClientState.spectating then
		return
	end
	local t = if tab and tabs[tab] then tab else "FEATURED"
	if open then
		StoreScene.select(t, arg)
		return
	end
	-- One premium screen at a time.
	ClientState.Juice:Fire("CloseMeta", {})
	ClientState.Juice:Fire("ClosePass", {})
	ClientState.Juice:Fire("CloseJobs", {})
	open = true
	ClientState.setAds(false)
	ClientState.setBlock("store", true)
	ClientState.lockMovement("store", true)
	HUD.setMode("meta")
	UI.sound(Fx.Sounds.whoosh, 1.1, 0.4)
	build(t, arg)
end

function StoreScene.close()
	if not open then
		return
	end
	for _, tab in TABS do
		local mod = tabs[tab]
		if mod and mod.leave and sectionCtx[tab] then
			mod.leave(sectionCtx[tab])
		end
	end
	open = false
	if PurchaseSheet.isOpen() then
		PurchaseSheet.close()
	end
	if gui then
		gui:Destroy()
		gui = nil
	end
	scroller, overlay, railHighlight = nil, nil, nil
	goldLabel = nil
	sections, sectionCtx, railButtons = {}, {}, {}
	ClientState.setBlock("store", false)
	ClientState.lockMovement("store", false)
	HUD.setMode(HUD.baseMode())
	UI.sound(Fx.Sounds.whoosh, 0.7, 0.35)
end

-- The crate scene takes the whole screen: the window steps aside and comes back.
function StoreScene.setHidden(hidden: boolean)
	local g = gui
	if g then
		g.Enabled = not hidden
	end
end

function StoreScene.refreshTab(tab: string)
	if open then
		renderSection(tab, true, nil)
		paintDots()
	end
end

StoreScene.scrollTo = scrollTo

------------------------------------------------------------------ Init
local lastStamp = ""
local function profileStamp(p: any): string
	if not p then
		return ""
	end
	local reroll = p.dailyReroll or {}
	local parts = {
		tostring(p.fakeRobux),
		tostring(p.gold),
		tostring(p.reviveTokens),
		tostring(reroll.day) .. ":" .. tostring(reroll.count),
	}
	for _, key in { "weapons", "boosts", "crateOpens", "cratePity" } do
		local n = 0
		for id, v in (p[key] or {}) do
			n += #id * 7 + (if typeof(v) == "number"
				then v
				else (if typeof(v) == "table" then (tonumber(v.expiresAt) or 1) % 997 else 1))
		end
		table.insert(parts, tostring(n))
	end
	for _, key in { "masks", "emotes", "wraps", "classes" } do
		local n = 0
		local t = p[key]
		for id in (if t and t.owned then t.owned else {}) do
			n += #id * 13 + string.byte(id, 1)
		end
		table.insert(parts, tostring(n) .. ":" .. tostring(t and t.equipped))
	end
	local vip = p.vip or {}
	table.insert(parts, tostring(vip.active) .. tostring(vip.renewsAt) .. tostring(p.vipGiftDay))
	return table.concat(parts, "|")
end

function StoreScene.init()
	for tab, name in MODULES do
		local m = script.Parent:FindFirstChild(name)
		if m then
			tabs[tab] = require(m :: ModuleScript)
		end
	end
	local noop = function(...: any) end
	baseCtx = {
		mobile = ClientState.isMobile,
		profile = profile,
		sync = function()
			return ClientState.sync
		end,
		toast = function(text: string, color: Color3?)
			PurchaseSheet.toast(text, color)
		end,
		buy = function(productId: string, opts: any?)
			local o = opts or {}
			o.context = o.context or "store"
			PurchaseSheet.open(productId, o)
		end,
		shop = function(action: string, args: any?): any
			local ok, res = pcall(function()
				return Remotes.Shop:InvokeServer(action, args)
			end)
			if not ok or typeof(res) ~= "table" then
				return { ok = false, reason = "Server error" }
			end
			return res
		end,
		select = function(tab: string, arg: any?)
			StoreScene.select(tab, arg)
		end,
		-- The overlay store has no mannequin: previews are no-ops (the customization scene previews on you).
		preview = { mask = noop, pose = noop, wrap = noop, idle = noop, reset = noop },
		goldBurst = function(from: Vector2?)
			local g, gl = gui, goldLabel
			if not g or not gl then
				return
			end
			local S = UI.S
			local target = gl.AbsolutePosition + gl.AbsoluteSize / 2
			local start = from or (camera.ViewportSize / 2)
			for i = 1, 18 do
				local coin = UI.frame({
					BackgroundColor3 = Theme.Colors.gold,
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(start.X + math.random(-50, 50), start.Y + math.random(-40, 40)),
					Size = UDim2.fromOffset(S(12), S(12)),
					Rotation = 45,
					ZIndex = 90,
					Parent = g,
				})
				UI.stroke(coin, Color3.fromHex("8A5A12"), S(1), 0)
				task.delay(i * 0.03, function()
					UI.tween(
						coin,
						{ Position = UDim2.fromOffset(target.X, target.Y), Size = UDim2.fromOffset(S(6), S(6)) },
						0.45,
						Enum.EasingStyle.Quad,
						Enum.EasingDirection.In
					)
					task.delay(0.46, function()
						coin:Destroy()
						UI.sound(Fx.Sounds.tick, 1.6 + i * 0.03, 0.15)
					end)
				end)
			end
			task.delay(0.6, function()
				local gl2 = goldLabel
				if gl2 then
					UI.punch(gl2, 1.35, 0.35)
				end
			end)
		end,
		hideChrome = function(hidden: boolean)
			StoreScene.setHidden(hidden)
		end,
	}
	setmetatable(baseCtx, {
		__index = function(_, k)
			if k == "gui" then
				return gui
			elseif k == "overlay" then
				return overlay
			end
			return nil
		end,
	})

	local function bindHub()
		local hub = HUD.get("hub")
		if hub then
			hub.onShop = function()
				StoreScene.open("FEATURED")
			end
			hub.onGoldPlus = function()
				StoreScene.open("GOLD")
			end
			hub.onStoreTab = function(tab: string)
				StoreScene.open(tab)
			end
			-- The VIP daily gift chip on the hub HUD.
			hub.onVipGift = function()
				local ok, res = pcall(function()
					return Remotes.Shop:InvokeServer("vipGift", {})
				end)
				if ok and typeof(res) == "table" and res.ok then
					PurchaseSheet.toast(
						string.format("+%d GOLD · VIP DAILY GIFT", Config.VipDailyGold),
						Color3.fromHex("F2C14E")
					)
				elseif ok and typeof(res) == "table" then
					PurchaseSheet.toast(tostring(res.reason), Theme.Colors.malus, false)
				end
			end
		end
	end
	bindHub()
	HUD.Rebuilt:Connect(function()
		bindHub()
		if open then
			local tab = currentTab
			StoreScene.close()
			StoreScene.open(tab)
		end
	end)
	ClientState.Juice:Connect(function(name: string, data: any)
		if name == "OpenStore" then
			StoreScene.open(data and data.tab, data and data.arg)
		elseif name == "RunStartBegin" or name == "Downed" or name == "BledOut" or name == "CloseStore" then
			StoreScene.close()
		end
	end)
	ClientState.Changed:Connect(function(sync: any)
		if not open then
			return
		end
		paintBalances(true)
		local stamp = profileStamp(sync.profile)
		if stamp ~= lastStamp then
			lastStamp = stamp
			paintDots()
			for _, tab in TABS do
				local mod = tabs[tab]
				if mod and mod.onProfile and sectionCtx[tab] then
					mod.onProfile(sectionCtx[tab])
				end
			end
		end
	end)
	-- Brief 11: LB / RB walk the tabs on a pad.
	GamepadNav.register("store", {
		tabs = function(dir: number)
			local i = table.find(TABS, currentTab) or 1
			scrollTo(TABS[(i - 1 + dir) % #TABS + 1])
		end,
	})
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		local back = (input.KeyCode == Enum.KeyCode.Escape and not gameProcessed)
			or input.KeyCode == Enum.KeyCode.ButtonB
		if open and back and not PurchaseSheet.isOpen() then
			if overlay and #overlay:GetChildren() > 0 then
				clearOverlay()
			else
				StoreScene.close()
			end
		end
	end)
end

return StoreScene
