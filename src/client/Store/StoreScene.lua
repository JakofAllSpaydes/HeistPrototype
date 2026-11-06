--!strict
-- Brief 6: the premium store scene. Opens from the hub's SHOP tile, the Gold +, and VIEW CRATE / VIEW BUNDLE deep
-- links in the customization tabs. A quick dip to black and the camera eases onto the SHOWROOM set (Sets.lua):
-- the mannequin (a local clone of you) on the left for anything previewable, the store panel on the right two
-- thirds. Header: SHOP, the tab strip FEATURED · CRATES · BOOSTS · VIP · GOLD (red dot = something claimable or
-- new; it scrolls on mobile), the R$ balance with + (GET ROBUX), Gold with + (the GOLD tab) and LEAVE. Tabs
-- crossfade and their cards cascade in; the panel slides in and settles. One module per tab under Store/.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Classes = require(Shared:WaitForChild("Classes"))

local Client = script.Parent.Parent
local ClientState = require(Client:WaitForChild("ClientState"))
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local HUD = require(Client:WaitForChild("HUD"))
local PurchaseSheet = require(Client:WaitForChild("PurchaseSheet"))
local Fx = require(script.Parent:WaitForChild("Fx"))
local Sets = require(script.Parent:WaitForChild("Sets"))

local StoreScene = {}

export type Ctx = {
	gui: ScreenGui,
	overlay: Frame, -- full-screen layer above the panel (detail sheets, odds panels)
	content: Frame, -- the current tab's area (cleared on every render)
	arg: any, -- the deep-link argument the tab was opened with
	quiet: boolean, -- a re-render after a profile change: no cascade
	mobile: boolean,
	profile: () -> any,
	sync: () -> any,
	toast: (string, Color3?) -> (),
	buy: (string, any?) -> (), -- product id, PurchaseSheet opts
	shop: (string, any?) -> any, -- Remotes.Shop round trip
	refresh: () -> (),
	select: (string, any?) -> (),
	preview: {
		mask: (string?) -> (),
		pose: (string) -> (),
		wrap: (string?) -> (),
		idle: (string?) -> (),
		reset: () -> (),
	},
	goldBurst: (Vector2?) -> (), -- sparks fly into the header Gold and it counts up
	hideChrome: (boolean) -> (), -- the crate scene takes the whole screen
}

local TABS = { "FEATURED", "CRATES", "BOOSTS", "VIP", "GOLD" }

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = Workspace.CurrentCamera :: Camera

local tabs: { [string]: any } = {}
local open = false
local currentTab: string? = nil
local currentArg: any = nil
local gui: ScreenGui? = nil
local panel: Frame? = nil
local header: Frame? = nil
local contentArea: Frame? = nil
local overlay: Frame? = nil
local fade: Frame? = nil
local tabButtons: { [string]: { button: TextButton, dot: Frame, underline: Frame } } = {}
local robuxLabel: TextLabel? = nil
local goldLabel: TextLabel? = nil
local shownRobux, shownGold = -1, -1
local mannequin: Sets.Mannequin? = nil
local set: Sets.Set? = nil
local camFrom: CFrame? = nil
local camTo: CFrame? = nil
local camT0 = 0
local camSec = 0.5
local currentFrame: Frame? = nil
local ctx: Ctx

------------------------------------------------------------------ Camera
local function stepCamera()
	local to = camTo
	if not to then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	local s = math.clamp((os.clock() - camT0) / camSec, 0, 1)
	local k = 1 - (1 - s) ^ 3
	local cf = (camFrom or to):Lerp(to, k)
	camera.CFrame = cf
	camera.Focus = cf
end

local function easeTo(cf: CFrame, from: CFrame?, sec: number)
	camFrom = from or camera.CFrame
	camTo = cf
	camT0 = os.clock()
	camSec = math.max(sec, 0.01)
end

-- Dip to black, run `mid` (the cut), then fade back up.
local function dip(mid: () -> ())
	local f = fade
	if not f then
		mid()
		return
	end
	f.Visible = true
	f.BackgroundTransparency = 1
	UI.tween(f, { BackgroundTransparency = 0 }, 0.12)
	task.wait(0.13)
	mid()
	UI.tween(f, { BackgroundTransparency = 1 }, 0.35)
	task.delay(0.36, function()
		if f.Parent then
			f.Visible = false
		end
	end)
end

------------------------------------------------------------------ Header values
local function profile(): any
	local sync = ClientState.sync
	return sync and sync.profile
end

local function paintBalances(animate: boolean)
	local p = profile()
	local robux = if p and typeof(p.fakeRobux) == "number" then p.fakeRobux else 0
	local gold = if p and typeof(p.gold) == "number" then p.gold else 0
	local rl, gl = robuxLabel, goldLabel
	if rl and robux ~= shownRobux then
		if animate and shownRobux >= 0 then
			Fx.countUp(rl, shownRobux, robux, 0.6, nil, robux > shownRobux)
			UI.punch(rl, if robux > shownRobux then 1.15 else 0.92, 0.3)
		else
			rl.Text = UI.fmtInt(robux)
		end
		shownRobux = robux
	end
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
	for tab, b in tabButtons do
		local mod = tabs[tab]
		b.dot.Visible = mod ~= nil and mod.badge ~= nil and p ~= nil and mod.badge(p) == true
	end
end

------------------------------------------------------------------ Tabs
local function paintTabs()
	for tab, b in tabButtons do
		local on = tab == currentTab
		b.button.TextColor3 = if on then Theme.Colors.white else Theme.Colors.textDim
		UI.tween(b.underline, { Size = UDim2.new(if on then 1 else 0, 0, 0, UI.S(3)) }, 0.18)
	end
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

-- Builds the tab into a fresh frame; a switch crossfades the old one out and the new one in.
local function render(quiet: boolean)
	local area = contentArea
	local tab = currentTab
	if not area or not tab then
		return
	end
	local frame = UI.frame({
		Name = "Tab_" .. tab,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
	})
	ctx.content = frame
	ctx.arg = currentArg
	ctx.quiet = quiet
	local old = currentFrame
	currentFrame = frame
	if quiet then
		if old then
			old:Destroy()
		end
		frame.Parent = area
		local mod = tabs[tab]
		if mod then
			mod.render(ctx)
		end
		return
	end
	-- Crossfade through CanvasGroups only for the length of the fade, then back to plain frames.
	if old then
		local g = UI.new("CanvasGroup", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 5,
			Parent = area,
		}) :: CanvasGroup
		old.Parent = g
		UI.tween(g, { GroupTransparency = 1 }, 0.16)
		task.delay(0.17, function()
			g:Destroy()
		end)
	end
	local g2 = UI.new("CanvasGroup", {
		BackgroundTransparency = 1,
		GroupTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 6,
		Parent = area,
	}) :: CanvasGroup
	frame.Parent = g2
	local mod = tabs[tab]
	if mod then
		mod.render(ctx)
	else
		StoreScene.placeholder(ctx, tab)
	end
	UI.tween(g2, { GroupTransparency = 0 }, 0.2)
	task.delay(0.21, function()
		if frame.Parent == g2 then
			frame.Parent = area
		end
		g2:Destroy()
	end)
end

function StoreScene.select(tab: string, arg: any?)
	if not tabs[tab] then
		tab = "FEATURED"
	end
	if currentTab ~= tab then
		local old = currentTab and tabs[currentTab]
		if old and old.leave then
			old.leave(ctx)
		end
		UI.sound(Fx.Sounds.tab, 1.3, 0.3)
	end
	currentTab = tab
	currentArg = arg
	clearOverlay()
	ctx.preview.reset()
	paintTabs()
	render(false)
	paintDots()
end

-- A tab without its module yet: the card component in every state (normal, owned, disabled, Legendary hero).
function StoreScene.placeholder(c: Ctx, tab: string)
	local Card = require(script.Parent:WaitForChild("Card")) :: any
	local row = UI.frame({ BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = c.content })
	UI.list(
		row,
		Enum.FillDirection.Horizontal,
		UI.S(18),
		Enum.HorizontalAlignment.Center,
		Enum.VerticalAlignment.Center
	)
	local cards = {}
	for i, spec in
		{
			{ title = tab, sub = "Arrives in a later build step", art = { kind = "gold", amount = 1000 }, price = 99 },
			{
				title = "OWNED",
				sub = "Check across the price",
				art = { kind = "mask", id = "c_neon" },
				price = 99,
				owned = true,
			},
			{
				title = "DISABLED",
				sub = "Dimmed to 40%",
				art = { kind = "weapon", id = "AUG" },
				price = 129,
				enabled = false,
			},
			{
				title = "HERO",
				sub = "Rays, sparks, a breathing glow",
				art = { kind = "mask", id = "c_king" },
				price = 999,
				hero = true,
				ribbons = { "LIMITED", "-30%" },
			},
		}
	do
		local s = spec :: any
		s.size = Vector2.new(180, 260)
		s.layoutOrder = i
		table.insert(cards, Card.new(row, s).holder)
	end
	if not c.quiet then
		Fx.cascade(cards, 0.04)
	end
end

------------------------------------------------------------------ Build
local function build()
	if gui then
		gui:Destroy()
	end
	local S = UI.S
	local mobile = ClientState.isMobile
	local g = UI.new("ScreenGui", {
		Name = "StoreScene",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 9,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	}) :: ScreenGui
	gui = g
	tabButtons = {}
	shownRobux, shownGold = -1, -1

	-- Header across the top.
	local headerH = if mobile then S(54) else S(66)
	local h = UI.frame({
		Name = "Header",
		BackgroundColor3 = Color3.fromHex("0C0C10"),
		BackgroundTransparency = 0.1,
		Size = UDim2.new(1, 0, 0, headerH),
		ZIndex = 10,
		Parent = g,
	})
	header = h
	UI.new("UIGradient", {
		Color = ColorSequence.new(Color3.fromHex("1C1A20"), Color3.fromHex("0A0A0D")),
		Rotation = 90,
		Parent = h,
	})
	local edge = UI.frame({
		BackgroundColor3 = Theme.Colors.gold,
		BackgroundTransparency = 0.4,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, S(1)),
		ZIndex = 11,
		Parent = h,
	})
	local _ = edge
	local title = UI.text({
		Text = "SHOP",
		Font = Theme.Fonts.display,
		TextSize = if mobile then S(24) else S(32),
		TextColor3 = Theme.Colors.gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(S(20), 0),
		Size = UDim2.new(0, S(96), 1, 0),
		ZIndex = 12,
		Parent = h,
	})
	UI.stroke(title, Color3.new(0, 0, 0), S(1.5), 0.3)

	-- Right side: R$ · Gold · LEAVE.
	local right = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -S(14), 0.5, 0),
		Size = UDim2.fromOffset(0, headerH - S(14)),
		AutomaticSize = Enum.AutomaticSize.X,
		ZIndex = 12,
		Parent = h,
	})
	UI.list(right, Enum.FillDirection.Horizontal, S(10), Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
	local function balancePill(order: number, glyph: string, color: Color3, onPlus: () -> ()): TextLabel
		local pill = UI.frame({
			BackgroundColor3 = Color3.fromHex("1E1E25"),
			Size = UDim2.fromOffset(if mobile then S(118) else S(150), headerH - S(22)),
			LayoutOrder = order,
			ZIndex = 12,
			Parent = right,
		})
		UI.corner(pill, S(8))
		UI.stroke(pill, color, S(1.5), 0.3)
		if glyph == "R$" then
			local b = Fx.robux(pill, S(18), 13)
			b.AnchorPoint = Vector2.new(0, 0.5)
			b.Position = UDim2.new(0, S(8), 0.5, 0)
		else
			UI.text({
				Text = glyph,
				Font = Theme.Fonts.display,
				TextSize = S(20),
				TextColor3 = color,
				Position = UDim2.fromOffset(S(6), 0),
				Size = UDim2.new(0, S(24), 1, 0),
				ZIndex = 13,
				Parent = pill,
			})
		end
		local label = UI.text({
			Text = "0",
			Font = Theme.Fonts.display,
			TextSize = if mobile then S(16) else S(19),
			TextColor3 = Theme.Colors.white,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(S(36), 0),
			Size = UDim2.new(1, -S(70), 1, 0),
			ZIndex = 13,
			Parent = pill,
		})
		local plus = UI.button({
			Text = "+",
			Font = Theme.Fonts.display,
			TextSize = S(18),
			TextColor3 = Theme.Colors.bg,
			BackgroundColor3 = color,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -S(4), 0.5, 0),
			Size = UDim2.fromOffset(S(26), S(26)),
			ZIndex = 13,
			Parent = pill,
		})
		UI.corner(plus, S(6))
		Fx.interactive(plus)
		plus.Activated:Connect(onPlus)
		return label
	end
	robuxLabel = balancePill(1, "R$", Color3.fromHex("2FD46A"), function()
		PurchaseSheet.getRobux({ context = "store R$ +" })
	end)
	goldLabel = balancePill(2, "◆", Theme.Colors.gold, function()
		StoreScene.select("GOLD")
	end)
	local leave = UI.button({
		Text = if mobile then "X" else "LEAVE",
		Font = Theme.Fonts.display,
		TextSize = S(18),
		TextColor3 = Theme.Colors.white,
		BackgroundColor3 = Theme.Colors.red,
		Size = UDim2.fromOffset(if mobile then S(44) else S(104), headerH - S(22)),
		LayoutOrder = 3,
		ZIndex = 12,
		Parent = right,
	})
	UI.corner(leave, S(8))
	UI.stroke(leave, Color3.new(1, 1, 1), S(1), 0.6)
	Fx.interactive(leave)
	leave.Activated:Connect(function()
		StoreScene.close()
	end)

	-- Tab strip between the title and the balances; scrolls when it does not fit.
	local strip = UI.new("ScrollingFrame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(S(20) + S(96), 0),
		Size = UDim2.new(1, -(S(20) + S(96)) - (if mobile then S(340) else S(450)), 1, 0),
		CanvasSize = UDim2.fromOffset(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 0,
		ZIndex = 12,
		Parent = h,
	})
	UI.list(strip, Enum.FillDirection.Horizontal, S(4), nil, Enum.VerticalAlignment.Center)
	for i, tab in TABS do
		local b = UI.button({
			Name = tab,
			Text = tab,
			Font = Theme.Fonts.display,
			TextSize = if mobile then S(15) else S(18),
			TextColor3 = Theme.Colors.textDim,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(if mobile then S(96) else S(110), math.max(S(44), headerH - S(10))),
			LayoutOrder = i,
			ZIndex = 13,
			Parent = strip,
		})
		local underline = UI.frame({
			BackgroundColor3 = Theme.Colors.gold,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -S(4)),
			Size = UDim2.new(0, 0, 0, S(3)),
			ZIndex = 14,
			Parent = b,
		})
		UI.corner(underline, S(2))
		local dot = UI.frame({
			BackgroundColor3 = Theme.Colors.red,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -S(6), 0, S(10)),
			Size = UDim2.fromOffset(S(10), S(10)),
			Visible = false,
			ZIndex = 15,
			Parent = b,
		})
		UI.corner(dot, S(5))
		UI.stroke(dot, Color3.new(1, 1, 1), S(1), 0.3)
		b.MouseEnter:Connect(function()
			if tab ~= currentTab then
				b.TextColor3 = Theme.Colors.text
				UI.sound(Fx.Sounds.hover, 1.8, 0.1)
			end
		end)
		b.MouseLeave:Connect(function()
			if tab ~= currentTab then
				b.TextColor3 = Theme.Colors.textDim
			end
		end)
		b.Activated:Connect(function()
			if tab ~= currentTab then
				UI.punch(b, 0.94, 0.15)
				StoreScene.select(tab)
			end
		end)
		tabButtons[tab] = { button = b, dot = dot, underline = underline }
	end

	-- The store panel: the right two thirds under the header.
	local panelW = if mobile then 0.68 else 0.64
	local p = UI.frame({
		Name = "Panel",
		BackgroundColor3 = Color3.fromHex("0E0E12"),
		BackgroundTransparency = 0.12,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -S(14), 0, headerH + S(12)),
		Size = UDim2.new(panelW, 0, 1, -headerH - S(26)),
		Active = true,
		ZIndex = 4,
		Parent = g,
	})
	panel = p
	UI.corner(p, S(14))
	UI.stroke(p, Color3.new(1, 1, 1), S(1), 0.86)
	UI.new("UIGradient", {
		Color = ColorSequence.new(Color3.fromHex("1A1A21"), Color3.fromHex("0B0B0E")),
		Rotation = 90,
		Parent = p,
	})
	contentArea = UI.frame({
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(S(16), S(14)),
		Size = UDim2.new(1, -S(32), 1, -S(28)),
		ZIndex = 5,
		Parent = p,
	})
	overlay = UI.frame({
		Name = "Overlay",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 30,
		Parent = g,
	})
	fade = UI.frame({
		Name = "Fade",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 100,
		Parent = g,
	})
	-- Entrance: the header drops, the panel slides in from the right and settles with an overshoot.
	Fx.slideIn(h, UDim2.fromOffset(0, -headerH), 0.3)
	Fx.slideIn(p, UDim2.fromOffset(S(160), 0), 0.25)
	paintBalances(false)
end

------------------------------------------------------------------ Open / close
function StoreScene.isOpen(): boolean
	return open
end

local dragging = false
local dragX = 0

function StoreScene.open(tab: string?, arg: any?)
	if not ClientState.inHub() or ClientState.downed or ClientState.spectating then
		return
	end
	local t = if tab and tabs[tab] then tab else "FEATURED"
	if open then
		StoreScene.select(t, arg)
		return
	end
	-- One premium scene at a time: the customization scene closes first.
	ClientState.Juice:Fire("CloseMeta", {})
	open = true
	build()
	ClientState.setAds(false)
	ClientState.setBlock("store", true)
	ClientState.lockMovement("store", true)
	ClientState.cameraMode = "store"
	HUD.setMode("meta")
	ClientState.Juice:Fire("CameraZoomReset", {})
	RunService:BindToRenderStep("GHSStoreCamera", Enum.RenderPriority.Camera.Value + 2, function()
		if open then
			stepCamera()
		end
	end)
	UI.sound(Fx.Sounds.whoosh, 0.9, 0.4)
	task.spawn(function()
		dip(function()
			Sets.dimWorld(true)
			local s = Sets.get("Showroom")
			set = s
			local m = Sets.mannequin(s.pedestal, s.shot.Position - s.pedestal.Position)
			mannequin = m
			if m then
				local sync = ClientState.sync
				m.idle(if sync then sync.classId else Classes.Default)
			end
			camera.CameraType = Enum.CameraType.Scriptable
			camera.CFrame = s.pullback
			easeTo(s.shot, s.pullback, Config.MetaCameraTweenSec + 0.35)
		end)
	end)
	StoreScene.select(t, arg)
end

function StoreScene.close()
	if not open then
		return
	end
	local old = currentTab and tabs[currentTab]
	if old and old.leave then
		old.leave(ctx)
	end
	open = false
	currentTab = nil
	currentFrame = nil
	dragging = false
	if PurchaseSheet.isOpen() then
		PurchaseSheet.close()
	end
	local m = mannequin
	mannequin = nil
	if m then
		m.destroy()
	end
	Sets.dimWorld(false)
	if gui then
		gui:Destroy()
		gui = nil
	end
	panel, header, contentArea, overlay, fade = nil, nil, nil, nil, nil
	robuxLabel, goldLabel = nil, nil
	pcall(function()
		RunService:UnbindFromRenderStep("GHSStoreCamera")
	end)
	camFrom, camTo = nil, nil
	ClientState.cameraMode = "gameplay"
	ClientState.requestCameraYaw = 0
	ClientState.setBlock("store", false)
	ClientState.lockMovement("store", false)
	HUD.setMode(HUD.baseMode())
	UI.sound(Fx.Sounds.whoosh, 0.7, 0.35)
end

------------------------------------------------------------------ Init
local lastStamp = ""
local function profileStamp(p: any): string
	if not p then
		return ""
	end
	local parts = { tostring(p.fakeRobux), tostring(p.gold), tostring(p.reviveTokens) }
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
	local pass = p.pass or {}
	table.insert(parts, tostring(pass.tier) .. ":" .. tostring(pass.level))
	return table.concat(parts, "|")
end

function StoreScene.init()
	local folder = script.Parent
	local function tryTab(name: string, moduleName: string)
		local m = folder:FindFirstChild(moduleName)
		if m then
			tabs[name] = require(m :: ModuleScript)
		end
	end
	tryTab("FEATURED", "FeaturedTab")
	tryTab("CRATES", "CratesTab")
	tryTab("BOOSTS", "BoostsTab")
	tryTab("VIP", "VipTab")
	tryTab("GOLD", "GoldTab")

	ctx = {
		gui = nil :: any,
		overlay = nil :: any,
		content = nil :: any,
		arg = nil,
		quiet = false,
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
			o.context = o.context or ("store " .. tostring(currentTab))
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
		refresh = function()
			render(true)
		end,
		select = function(tab: string, arg: any?)
			StoreScene.select(tab, arg)
		end,
		preview = {
			mask = function(id: string?)
				local m = mannequin
				if m then
					m.mask(id)
				end
			end,
			pose = function(id: string)
				local m = mannequin
				if m then
					m.pose(id)
				end
			end,
			wrap = function(id: string?)
				local m = mannequin
				if m then
					m.wrap(id)
				end
			end,
			idle = function(classId: string?)
				local m = mannequin
				if m then
					m.idle(classId)
				end
			end,
			reset = function()
				local m = mannequin
				if m then
					m.mask(nil)
					m.wrap(nil)
				end
			end,
		},
		goldBurst = function(from: Vector2?)
			local g, gl = gui, goldLabel
			if not g or not gl then
				return
			end
			local S = UI.S
			local target = gl.AbsolutePosition + gl.AbsoluteSize / 2
			local start = from or (camera.ViewportSize / 2)
			for i = 1, 16 do
				local coin = UI.frame({
					BackgroundColor3 = Theme.Colors.gold,
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(start.X + math.random(-40, 40), start.Y + math.random(-30, 30)),
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
			if panel then
				panel.Visible = not hidden
			end
			if header then
				header.Visible = not hidden
			end
		end,
	}
	setmetatable(ctx :: any, {
		__index = function(_, k)
			if k == "gui" then
				return gui
			elseif k == "overlay" then
				return overlay
			end
			return nil
		end,
	})
	-- ctx.gui / ctx.overlay resolve live through the metatable.
	rawset(ctx :: any, "gui", nil)
	rawset(ctx :: any, "overlay", nil)

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
			local mod = currentTab and tabs[currentTab]
			if mod and mod.onProfile then
				mod.onProfile(ctx)
			end
		end
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if not open then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape and not gameProcessed and not PurchaseSheet.isOpen() then
			StoreScene.close()
			return
		end
		-- Drag on the mannequin side (left of the panel) turns it round.
		local press = input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		local p = panel
		if press and not gameProcessed and p and p.Visible and input.Position.X < p.AbsolutePosition.X then
			dragging = true
			dragX = input.Position.X
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if not open or not dragging then
			return
		end
		if
			input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch
		then
			local dx = input.Position.X - dragX
			dragX = input.Position.X
			local m = mannequin
			if m then
				m.turn(dx * Config.MetaDragSensitivity)
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = false
		end
	end)
	local _ = set
end

-- For the crate scene and other modules that run on the store's sets and camera.
StoreScene.ctx = function(): Ctx
	return ctx
end
StoreScene.easeCamera = function(cf: CFrame, from: CFrame?, sec: number)
	easeTo(cf, from, sec)
end
StoreScene.dip = dip
StoreScene.backToShowroom = function()
	local s = set
	if s then
		easeTo(s.shot, s.pullback, 0.5)
	end
end

return StoreScene
