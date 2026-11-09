--!strict
-- Brief 9: the Skill Web scene, in the pass / store family. A full-screen overlay over the blurred hub (the hub HUD
-- hidden, the local nameplate hidden, movement locked); Esc / BACK / B closes it.
--   top-left      SKILL WEB in the stencil face, the branch legend under it (the hovered / selected branch lit)
--   top-right     the Gold pill (the store's balance style; + goes to the store's GOLD section)
--   bottom-left   BACK, the red X tile
--   the canvas    91 flat-top hexes on a regular hex grid (Skills / SkillLayout): drag pans (mouse, touch, right
--                 stick), scroll / pinch / triggers zoom between SkillZoomMin (never smaller than the whole web on
--                 screen) and SkillZoomMax; double-tap the backdrop to recentre on START
--   the sheet     tap a hex -> docks to the right edge: branch tag, pictogram, name, effect line, RING N, the price,
--                 BUY (never a single tap on a hex). It stays up after a buy so the player reads what they got.
-- Hex states: owned (the branch tint, edges lit to owned neighbours), affordable (panel colour, gold price, a slow
-- white edge pulse, a red ! badge), revealed but short (red price, grey name, no pulse), outlined (two steps out:
-- dim with ?), faint (stroke).
-- Built from plain frames with one selectable button per hex and a selectable BUY, so GamepadNav can walk it later.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Skills = require(Shared:WaitForChild("Skills"))
local SkillLayout = require(Shared:WaitForChild("SkillLayout"))

local Client = script.Parent.Parent
local ClientState = require(Client:WaitForChild("ClientState"))
local GamepadNav = require(Client:WaitForChild("GamepadNav"))
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local Icons = require(Client:WaitForChild("UI"):WaitForChild("Icons"))
local HUD = require(Client:WaitForChild("HUD"))
local Nameplates = require(Client:WaitForChild("Nameplates"))
local Fx = require(Client:WaitForChild("Store"):WaitForChild("Fx"))

local SkillScene = {}
-- Set by bindInput: whether the press that just ended was a drag (a hex tap after a pan is ignored), and the
-- backdrop's tap (close the sheet; a double-tap recentres on START).
SkillScene.dragged = nil :: (() -> boolean)?
SkillScene.backdropTap = nil :: (() -> ())?

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = Workspace.CurrentCamera :: Camera

local SQ3 = math.sqrt(3)
local GREEN = Color3.fromHex("2FB75A")
local BG = Color3.fromHex("0C0C10")
local PANEL = Color3.fromHex("1F1F26")
local GAP = 1.1 -- grid radius / drawn hex radius: the dark seam between hexes
local START = Skills.START

type HexView = {
	id: string,
	holder: Frame,
	scale: UIScale,
	outer: { Frame },
	inner: { Frame },
	button: TextButton,
	icon: Frame?,
	iconId: string,
	name: TextLabel,
	price: TextLabel,
	unknown: TextLabel,
	badge: Frame, -- Round 28e: the red ! breadcrumb on a hex you can buy right now
	x: number,
	y: number,
	state: string,
	edge: Color3, -- the edge colour at rest (the affordable pulse breathes from it to white)
	pulse: number, -- os.clock until the pulse-once glow ends (0 = none)
}

local open = false
local gui: ScreenGui? = nil
local blur: BlurEffect? = nil
local canvas: Frame? = nil
local zoomScale: UIScale? = nil
local hexes: { [string]: HexView } = {}
local seams: { [string]: Frame } = {}
local seamLayer: Frame? = nil
local selected: string? = nil
local hovered: string? = nil
local zoom = 1
local zoomMin, zoomMax = 0.55, 1.6
local pan = Vector2.zero
local panTarget: Vector2? = nil
local side = 32 -- drawn hex radius (px at zoom 1)
local grid = 35 -- grid radius (px at zoom 1)
local webRadius = 400
local goldLabel: TextLabel? = nil
local goldPill: Frame? = nil
local shownGold = -1
local ownedOverride: { [string]: boolean }? = nil -- the last buy's reply, until the sync catches up
local legendRows: { [string]: { label: TextLabel?, icon: Frame, bg: Frame } } = {}
local chrome: { GuiObject } = {}
local sheet: GuiObject? = nil
local buying = false
local revealing = false -- Round 26c: the unlock sequence is playing (sync repaints wait for it)
local renderConn: RBXScriptConnection? = nil
local inputConns: { RBXScriptConnection } = {}

------------------------------------------------------------------ Profile
local function profile(): any
	local sync = ClientState.sync
	return sync and sync.profile
end

local function goldNow(): number
	local p = profile()
	return if p and typeof(p.gold) == "number" then p.gold else 0
end

local function ownedSet(): { [string]: boolean }
	local o = ownedOverride
	if o then
		return o
	end
	local p = profile()
	local s = p and p.skills
	return if s and typeof(s.owned) == "table" then s.owned else {}
end

local function seenSet(): { [string]: boolean }
	local p = profile()
	local s = p and p.skills
	return if s and typeof(s.seen) == "table" then s.seen else {}
end

-- 500 -> "500", 1500 -> "1.5K", 25000 -> "25K".
local function fmtK(n: number): string
	if n >= 1000 then
		local k = n / 1000
		return (if k == math.floor(k) then string.format("%d", k) else string.format("%.1f", k)) .. "K"
	end
	return string.format("%d", n)
end

local function branchColor(id: string): Color3
	local n = Skills.ById[id]
	local b = n and Skills.BranchById[n.branch]
	return if b then Color3.fromHex(b.color) else Theme.Colors.gold
end

-- The hex's state now: owned | affordable | short | outlined | faint.
local function stateOf(id: string, dist: { [string]: number }, gold: number): string
	local d = dist[id] or 99
	if d == 0 then
		return "owned"
	elseif d == 1 then
		return if gold >= Skills.cost(id) then "affordable" else "short"
	elseif d == 2 then
		return "outlined"
	end
	return "faint"
end

------------------------------------------------------------------ Hex drawing
-- A flat-top hex of radius r (corner to centre): three r x r*sqrt(3) rectangles turned 0 / 60 / 120 degrees.
local function hexParts(parent: GuiObject, r: number, color: Color3, z: number): { Frame }
	local parts = {}
	for i = 0, 2 do
		parts[i + 1] = UI.frame({
			Name = "Hex",
			BackgroundColor3 = color,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(r, r * SQ3),
			Rotation = i * 60,
			ZIndex = z,
			Parent = parent,
		})
	end
	return parts
end

local function paintParts(parts: { Frame }, color: Color3)
	for _, f in parts do
		f.BackgroundColor3 = color
	end
end

local function toCanvas(q: number, r: number): (number, number)
	local x, y = SkillLayout.toXY(q, r)
	return x * grid, y * grid
end

local function buildHex(parent: Frame, id: string, q: number, r: number): HexView
	local isStart = id == START
	local rr = if isStart then side * 1.18 else side
	local x, y = toCanvas(q, r)
	local holder = UI.frame({
		Name = id,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(rr * 2, rr * SQ3),
		ZIndex = 3,
		Parent = parent,
	})
	local scale = UI.new("UIScale", { Name = "HexScale", Parent = holder })
	local border = math.max(2, math.floor(rr * 0.07))
	local outer = hexParts(holder, rr, Color3.fromHex("26262E"), 3)
	local inner = hexParts(holder, rr - border * 1.16, BG, 4)
	-- The tap target: the hex's middle band (1.5 r wide), so neighbouring targets never overlap.
	local button = UI.button({
		Name = "Tap",
		Text = "",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(rr * 1.5, rr * SQ3),
		Selectable = true,
		ZIndex = 6,
		Parent = holder,
	})
	local node = Skills.ById[id]
	local iconId = if isStart then "star" else (if node then node.icon else "plus")
	local h = rr * SQ3
	local name = UI.text({
		Name = "Name",
		Text = if isStart then "START" elseif node then node.name else "",
		FontFace = Theme.Fonts.display,
		TextScaled = true,
		TextWrapped = true,
		TextColor3 = Theme.Colors.white,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, h * 0.64),
		Size = UDim2.fromOffset(rr * 1.62, h * 0.22),
		ZIndex = 7,
		Parent = holder,
	})
	name:SetAttribute("FixedTextSize", true)
	UI.new("UITextSizeConstraint", { MaxTextSize = math.max(8, math.floor(rr * 0.36)), Parent = name })
	UI.stroke(name, Theme.Colors.black, 1, 0.35)
	local price = UI.text({
		Name = "Price",
		Text = "",
		RichText = true,
		FontFace = Theme.Fonts.display,
		TextScaled = true,
		TextColor3 = Theme.Colors.white,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, h * 0.84),
		Size = UDim2.fromOffset(rr * 1.1, h * 0.17),
		ZIndex = 7,
		Parent = holder,
	})
	price:SetAttribute("FixedTextSize", true)
	UI.new("UITextSizeConstraint", { MaxTextSize = math.max(8, math.floor(rr * 0.34)), Parent = price })
	UI.stroke(price, Theme.Colors.black, 1, 0.35)
	local unknown = UI.text({
		Name = "Unknown",
		Text = "?",
		FontFace = Theme.Fonts.display,
		TextSize = math.floor(rr * 0.9),
		TextColor3 = Color3.fromHex("6A6A76"),
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 7,
		Parent = holder,
	})
	unknown:SetAttribute("FixedTextSize", true)
	-- Round 28e: affordable hexes wear the hub SKILLS tile's breadcrumb (a red dot with a white ring) with a ! in it,
	-- on the hex's top-right corner, so what you can buy reads at a glance without comparing prices.
	local badgePx = math.max(12, math.floor(rr * 0.5))
	local badge = UI.frame({
		Name = "Badge",
		BackgroundColor3 = Theme.Colors.red,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.8, 0.12),
		Size = UDim2.fromOffset(badgePx, badgePx),
		Visible = false,
		ZIndex = 9,
		Parent = holder,
	})
	UI.corner(badge, badgePx / 2)
	UI.stroke(badge, Theme.Colors.white, math.max(1, math.floor(badgePx * 0.09)), 0)
	local bang = UI.text({
		Text = "!",
		FontFace = Theme.Fonts.display,
		TextSize = math.floor(badgePx * 0.8),
		TextColor3 = Theme.Colors.white,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 10,
		Parent = badge,
	})
	bang:SetAttribute("FixedTextSize", true)
	local v: HexView = {
		id = id,
		holder = holder,
		scale = scale,
		outer = outer,
		inner = inner,
		button = button,
		icon = nil,
		iconId = iconId,
		name = name,
		price = price,
		unknown = unknown,
		badge = badge,
		x = x,
		y = y,
		state = "",
		edge = Color3.fromHex("26262E"),
		pulse = 0,
	}
	return v
end

-- (Re)draw the hex's pictogram in `color` (Icons draw their colour in; a state change redraws).
local function setIcon(v: HexView, color: Color3?, detail: Color3?)
	if v.icon then
		v.icon:Destroy()
		v.icon = nil
	end
	if not color then
		return
	end
	local isStart = v.id == START
	local rr = if isStart then side * 1.18 else side
	local px = math.floor(rr * (if isStart then 0.8 else 0.62))
	local icon = Icons.draw(v.holder, v.iconId, px, color, detail)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = if isStart then UDim2.fromScale(0.5, 0.36) else UDim2.new(0.5, 0, 0, rr * SQ3 * 0.32)
	icon.ZIndex = 7
	for _, d in icon:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex += 3
		end
	end
	v.icon = icon
end

local function seamKey(a: string, b: string): string
	return if a < b then a .. "|" .. b else b .. "|" .. a
end

-- A lit edge between two owned neighbours: a white bar across the gap, along their shared side.
local function addSeam(a: string, b: string, animate: boolean)
	local key = seamKey(a, b)
	local layer = seamLayer
	local va, vb = hexes[a], hexes[b]
	if seams[key] or not layer or not va or not vb then
		return
	end
	local mx, my = (va.x + vb.x) / 2, (va.y + vb.y) / 2
	local ang = math.deg(math.atan2(vb.y - va.y, vb.x - va.x)) + 90
	local bar = UI.frame({
		Name = "Seam",
		BackgroundColor3 = Theme.Colors.white,
		BackgroundTransparency = if animate then 1 else 0.1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(mx, my),
		Size = UDim2.fromOffset(side * 0.95, math.max(2, math.floor(side * 0.09))),
		Rotation = ang,
		ZIndex = 2,
		Parent = layer,
	})
	seams[key] = bar
	if animate then
		UI.tween(bar, { BackgroundTransparency = 0.1 }, 0.25)
	end
end

------------------------------------------------------------------ Painting
local paintSheet: (() -> ())? = nil

local function paintHex(v: HexView, st: string, animate: boolean)
	local isStart = v.id == START
	local tint = if isStart then Theme.Colors.gold else branchColor(v.id)
	local prev = v.state
	v.state = st
	local selectedHere = selected == v.id
	v.unknown.Visible = st == "outlined"
	v.name.Visible = st == "owned" or st == "affordable" or st == "short"
	v.price.Visible = st == "affordable" or st == "short"
	v.badge.Visible = st == "affordable"
	v.button.Visible = st ~= "faint"
	-- Round 26b: hexes past the ? ring are hidden, so the web grows as you buy.
	v.holder.Visible = st ~= "faint"
	-- Round 26b: a revealed hex wears a dark shade of its branch colour (the type reads without the text); owned goes
	-- to the bright, saturated colour.
	local dark = tint:Lerp(BG, 0.62)
	if st == "owned" then
		v.edge = tint:Lerp(Color3.new(1, 1, 1), 0.35)
		paintParts(v.outer, if selectedHere then Theme.Colors.gold else v.edge)
		paintParts(v.inner, tint)
		v.name.TextColor3 = Theme.Colors.white
		if prev ~= "owned" then
			setIcon(v, Theme.Colors.white, tint)
		end
	elseif st == "affordable" or st == "short" then
		v.edge = tint:Lerp(BG, 0.35)
		paintParts(v.outer, if selectedHere then Theme.Colors.gold else v.edge)
		paintParts(v.inner, dark)
		-- Round 28e: one you can't afford yet reads dimmer (grey name) beside the bright, badged affordable ones.
		v.name.TextColor3 = if st == "short" then Theme.Colors.textDim else Theme.Colors.white
		local cost = Skills.cost(v.id)
		v.price.Text = string.format(
			'<font color="#E8B64C">◆</font> <font color="%s">%s</font>',
			if st == "short" then "#FF6B5E" else "#FFFFFF",
			fmtK(cost)
		)
		if prev ~= "affordable" and prev ~= "short" then
			setIcon(v, Color3.fromHex("E6E6EA"), dark)
		end
	elseif st == "outlined" then
		paintParts(v.outer, if selectedHere then Theme.Colors.gold else Color3.fromHex("3A3A44"))
		paintParts(v.inner, Color3.fromHex("16161B"))
		setIcon(v, nil)
	else
		paintParts(v.outer, Color3.fromHex("23232A"))
		paintParts(v.inner, BG)
		setIcon(v, nil)
	end
	-- Newly revealed (from ? or faint): fade in with a small pop.
	if animate and prev ~= "" and prev ~= st and (prev == "outlined" or prev == "faint") then
		v.scale.Scale = 0.7
		UI.tween(v.scale, { Scale = 1 }, 0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end
	if selectedHere then
		v.holder.ZIndex = 5
	else
		v.holder.ZIndex = 3
	end
end

local function paintLegend()
	local focus = hovered or selected
	-- A ? hex never lights its branch (that would give away what it is).
	local fv = focus and hexes[focus]
	if fv and (fv.state == "outlined" or fv.state == "faint") then
		focus = nil
	end
	local n = focus and Skills.ById[focus]
	local lit = n and n.branch
	for id, row in legendRows do
		local b = Skills.BranchById[id]
		local on = lit == id
		local color = Color3.fromHex(b.color)
		row.bg.BackgroundColor3 = if on then color:Lerp(PANEL, 0.55) else PANEL
		row.bg.BackgroundTransparency = if on then 0 else 0.35
		if row.label then
			row.label.TextColor3 = if on then Theme.Colors.white else Theme.Colors.textDim
		end
	end
end

local function paintAll(animate: boolean)
	local owned = ownedSet()
	local dist = Skills.distances(owned)
	local gold = goldNow()
	for id, v in hexes do
		paintHex(v, stateOf(id, dist, gold), animate)
	end
	-- Seams between every pair of owned neighbours.
	for id, v in hexes do
		if v.state == "owned" then
			for _, nb in Skills.neighbours(id) do
				if Skills.owns(owned, nb) then
					addSeam(id, nb, false)
				end
			end
		end
	end
	paintLegend()
	local ps = paintSheet
	if ps then
		ps()
	end
end

local function paintGold(animate: boolean)
	local gold = goldNow()
	local gl = goldLabel
	if gl and gold ~= shownGold then
		if animate and shownGold >= 0 then
			Fx.countUp(gl, shownGold, gold, 0.6, nil, false)
		else
			gl.Text = UI.fmtInt(gold)
		end
		shownGold = gold
	end
end

------------------------------------------------------------------ Pan and zoom
local function applyView()
	local c, zs = canvas, zoomScale
	if c and zs then
		c.Position = UDim2.new(0.5, math.round(pan.X), 0.5, math.round(pan.Y))
		zs.Scale = zoom
	end
end

local function clampPan(p: Vector2): Vector2
	-- (plus room to centre an edge hex in the space beside the sheet)
	local lim = webRadius * zoom + UI.S(220)
	return Vector2.new(math.clamp(p.X, -lim, lim), math.clamp(p.Y, -lim, lim))
end

local function viewCentre(): Vector2
	local g = gui
	if g then
		return g.AbsoluteSize / 2
	end
	return camera.ViewportSize / 2
end

-- Zoom to `z` keeping the web point under the screen point `at` where it is.
local function zoomAt(z: number, at: Vector2?)
	local nz = math.clamp(z, zoomMin, zoomMax)
	if nz == zoom then
		return
	end
	local p = at or viewCentre()
	local u = (p - viewCentre() - pan) / zoom
	zoom = nz
	pan = clampPan(p - viewCentre() - u * zoom)
	panTarget = nil
	applyView()
end

local function centreOn(id: string, instant: boolean)
	local v = hexes[id]
	if not v then
		return
	end
	local target = clampPan(Vector2.new(-v.x * zoom, -v.y * zoom))
	if instant then
		pan = target
		panTarget = nil
		applyView()
	else
		panTarget = target
	end
end

------------------------------------------------------------------ The sheet
local function closeSheet()
	local prev = selected
	selected = nil
	local s = sheet
	if s then
		s.Visible = false
	end
	if prev and hexes[prev] then
		paintHex(hexes[prev], hexes[prev].state, false)
	end
	paintLegend()
end

local buy: (string) -> () = function() end

-- Round 26b: centre a hex in the space the sheet leaves free (the whole view when no sheet is up).
local function centreInFree(id: string, instant: boolean)
	local v = hexes[id]
	if not v then
		return
	end
	local free = viewCentre().X * 2
	local s = sheet
	if s and s.Visible then
		free -= s.AbsoluteSize.X + UI.S(14)
	end
	local target = clampPan(Vector2.new(free / 2 - viewCentre().X - v.x * zoom, -v.y * zoom))
	if instant then
		pan = target
		panTarget = nil
		applyView()
	else
		panTarget = target
	end
end

local function select(id: string)
	if buying then
		return
	end
	local prev = selected
	selected = id
	if prev and prev ~= id and hexes[prev] then
		paintHex(hexes[prev], hexes[prev].state, false)
	end
	local v = hexes[id]
	if v then
		paintHex(v, v.state, false)
		UI.punch(v.button, 0.9, 0.2)
	end
	local s = sheet
	if s then
		local was = s.Visible
		s.Visible = true
		if not was then
			Fx.slideIn(s, UDim2.fromOffset(UI.S(40), 0), 0.25)
		end
	end
	local ps = paintSheet
	if ps then
		ps()
	end
	-- The tapped hex glides to the centre of the free space.
	centreInFree(id, false)
	paintLegend()
	UI.sound(Fx.Sounds.tab, 1.4, 0.25)
end

-- Round 26b: a compact card (was a full-height column, mostly empty): the branch tag and ring, the pictogram well
-- beside the name and effect line, then BUY with the price on it (or OWNED) and a status line. Docked right,
-- vertically centred (bottom-right on a phone, BUY under the thumb).
local function buildSheet(g: ScreenGui, vp: Vector2, _top: number, mobile: boolean)
	local S = UI.S
	local w = if mobile then math.floor(vp.X * 0.4) else S(390)
	local margin = S(14)
	local pad = S(14)
	local headH = S(22)
	local wellSize = if mobile then S(70) else S(92)
	local buyH = if mobile then math.max(44, S(56)) else S(52) -- a thumb-sized target on a phone
	local statusH = S(18)
	local h = pad + headH + S(10) + wellSize + S(12) + buyH + S(4) + statusH + pad - S(6)
	-- A button, so a tap on the sheet never falls through to the backdrop (which closes it).
	local s = UI.button({
		Name = "Sheet",
		Text = "",
		Selectable = false,
		BackgroundColor3 = Color3.fromHex("121216"),
		AnchorPoint = if mobile then Vector2.new(1, 1) else Vector2.new(1, 0.5),
		Position = if mobile then UDim2.new(1, -margin, 1, -margin) else UDim2.new(1, -margin, 0.5, 0),
		Size = UDim2.fromOffset(w, h),
		Visible = false,
		Active = true,
		ZIndex = 20,
		Parent = g,
	})
	s:SetAttribute("NavSkip", true) -- brief 11: the card itself is not a choice (BUY is)

	UI.corner(s, S(6))
	local edge = UI.stroke(s, Theme.Colors.gold, S(1.5), 0.4)
	table.insert(chrome, s)
	local tag = UI.text({
		Name = "Branch",
		Text = "",
		FontFace = Theme.Fonts.display,
		TextSize = S(14),
		TextColor3 = Theme.Colors.bg,
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Colors.gold,
		Position = UDim2.fromOffset(pad, pad),
		Size = UDim2.fromOffset(0, headH),
		AutomaticSize = Enum.AutomaticSize.X,
		ZIndex = 21,
		Parent = s,
	})
	UI.pad(tag, S(8), 0, S(8), 0)
	UI.corner(tag, S(3))
	local ringLabel = UI.text({
		Name = "Ring",
		Text = "",
		FontFace = Theme.Fonts.display,
		TextSize = S(14),
		TextColor3 = Theme.Colors.textDim,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -pad, 0, pad),
		Size = UDim2.fromOffset(S(90), headH),
		ZIndex = 21,
		Parent = s,
	})
	local bodyY = pad + headH + S(10)
	local well = UI.frame({
		Name = "Well",
		BackgroundColor3 = PANEL,
		Position = UDim2.fromOffset(pad, bodyY),
		Size = UDim2.fromOffset(wellSize, wellSize),
		ZIndex = 21,
		Parent = s,
	})
	UI.corner(well, S(4))
	local textX = pad + wellSize + S(12)
	local name = UI.text({
		Name = "Name",
		Text = "",
		FontFace = Theme.Fonts.display,
		TextSize = if mobile then S(20) else S(26),
		TextColor3 = Theme.Colors.white,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(textX, bodyY - S(2)),
		Size = UDim2.new(1, -textX - pad, 0, if mobile then S(24) else S(32)),
		ZIndex = 21,
		Parent = s,
	})
	local line = UI.text({
		Name = "Effect",
		Text = "",
		FontFace = Theme.Fonts.body,
		TextScaled = true, -- full size; shrinks only when a long line would overflow its three lines
		TextColor3 = Theme.Colors.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Position = UDim2.fromOffset(textX, bodyY + (if mobile then S(26) else S(34))),
		Size = UDim2.new(1, -textX - pad, 0, wellSize - (if mobile then S(26) else S(34))),
		ZIndex = 21,
		Parent = s,
	})
	line:SetAttribute("FixedTextSize", true)
	UI.new("UITextSizeConstraint", {
		MaxTextSize = math.round(
			(if mobile then S(14) * (Config.MobileStoreTextScale or 1) else S(16)) * Theme.TextScale.body
		),
		MinTextSize = 8,
		Parent = line,
	})
	local actionY = bodyY + wellSize + S(12)
	local buyBtn, buyHandle = Fx.button(s, "BUY", GREEN, Theme.Colors.white, UDim2.new(1, -pad * 2, 0, buyH), 22)
	buyBtn.Name = "Buy"
	buyBtn.RichText = true
	buyBtn.Position = UDim2.fromOffset(pad, actionY)
	buyBtn.TextSize = if mobile then S(22) else S(22)
	buyBtn.Selectable = true
	local ownedStamp = UI.text({
		Name = "Owned",
		Text = "OWNED",
		FontFace = Theme.Fonts.display,
		TextSize = S(24),
		TextColor3 = Theme.Colors.health,
		Position = UDim2.fromOffset(pad, actionY),
		Size = UDim2.new(1, -pad * 2, 0, buyH),
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.fromHex("16241B"),
		Visible = false,
		ZIndex = 22,
		Parent = s,
	})
	UI.corner(ownedStamp, S(4))
	UI.stroke(ownedStamp, Theme.Colors.health, S(1.5), 0.2)
	local status = UI.text({
		Name = "Status",
		Text = "",
		FontFace = Theme.Fonts.display,
		TextSize = S(13),
		TextColor3 = Theme.Colors.red,
		Position = UDim2.fromOffset(pad, actionY + buyH + S(4)),
		Size = UDim2.new(1, -pad * 2, 0, statusH),
		ZIndex = 21,
		Parent = s,
	})
	local buyEnabled = false
	buyBtn.Activated:Connect(function()
		local id = selected
		-- A disabled BUY already plays the refusal tick (Fx.interactive); only an enabled one buys.
		if id and buyEnabled and not buying then
			buy(id)
		end
	end)

	local wellIcon: Instance? = nil
	paintSheet = function()
		local id = selected
		if not id or not s.Visible then
			return
		end
		local owned = ownedSet()
		local node = Skills.ById[id]
		local v = hexes[id]
		local st = if v then v.state else "faint"
		local unknown = st == "outlined" or st == "faint"
		local isOwned = Skills.owns(owned, id)
		local color = if id == START then Theme.Colors.gold elseif unknown then Theme.Colors.grey else branchColor(id)
		edge.Color = color
		tag.BackgroundColor3 = color
		tag.Text = if id == START then "THE WEB" elseif unknown then "UNKNOWN" elseif node then node.branch else ""
		ringLabel.Text = if node then "RING " .. node.ring else ""
		name.Text = if id == START then "START" elseif unknown then "???" elseif node then node.name else ""
		line.Text = if id == START and not isOwned
			then "UNLOCK SKILLS"
			elseif id == START then "Every branch starts here. Buy a hex next to one you own."
			elseif unknown then "Unlock a neighbour to reveal it."
			elseif node then node.line
			else ""
		-- The well wears the hex's own colour: dark while locked, bright once owned.
		well.BackgroundColor3 = if unknown then PANEL elseif isOwned then color else color:Lerp(BG, 0.62)
		if wellIcon then
			wellIcon:Destroy()
			wellIcon = nil
		end
		local iconId = if id == START then "star" elseif unknown then "" elseif node then node.icon else ""
		if iconId ~= "" then
			local ic = Icons.fit(well, iconId, 0.74, Theme.Colors.white, well.BackgroundColor3)
			ic.ZIndex = 22
			for _, d in ic:GetDescendants() do
				if d:IsA("GuiObject") then
					d.ZIndex += 22
				end
			end
			wellIcon = ic
		else
			wellIcon = UI.text({
				Text = "?",
				FontFace = Theme.Fonts.display,
				TextSize = S(40),
				TextColor3 = Color3.fromHex("6A6A76"),
				Size = UDim2.fromScale(1, 1),
				ZIndex = 22,
				Parent = well,
			})
		end
		-- The action row by state.
		local cost = if node then Skills.cost(id) else 0
		local gold = goldNow()
		local adjacent = (node ~= nil or id == START) and Skills.adjacent(owned, id)
		ownedStamp.Visible = isOwned
		buyBtn.Visible = not isOwned and (node ~= nil or id == START)
		buyBtn.Text = if unknown
			then "BUY"
			else string.format(
				'BUY   <font color="#FFE7A3">◆</font> <font color="%s">%s</font>',
				if gold >= cost then "#FFFFFF" else "#FFB0A8",
				UI.fmtInt(cost)
			)
		if isOwned then
			buyEnabled = false
			status.Text = ""
		elseif not adjacent then
			buyEnabled = false
			buyHandle.setEnabled(false)
			status.Text = "LOCKED · UNLOCK A NEIGHBOUR"
			status.TextColor3 = Theme.Colors.textDim
		elseif gold < cost then
			buyEnabled = false
			buyHandle.setEnabled(false)
			status.Text = string.format("NOT ENOUGH GOLD · NEED %s MORE", UI.fmtInt(cost - gold))
			status.TextColor3 = Theme.Colors.red
		else
			buyEnabled = not buying
			buyHandle.setEnabled(buyEnabled)
			status.Text = ""
		end
	end
	sheet = s
	return s
end

------------------------------------------------------------------ Buying
-- Round 26c: START bought -> the system switches on. START ignites (flash, two shockwave rings), SKILL WEB UNLOCKED
-- drops in, the six ring-1 hexes turn over clockwise one by one (each with its branch colour, a lit edge, a burst and
-- a rising ding while its legend row appears), then the ? ring beyond them fades in.
local function unlockSequence(set: { [string]: boolean }, gold: number?)
	local g, c, sv = gui, canvas, hexes[START]
	if not g or not c or not sv then
		paintAll(true)
		return
	end
	local S = UI.S
	revealing = true
	closeSheet()
	centreOn(START, false)
	local g0 = gold or goldNow()
	local gl = goldLabel
	if gold and gl then
		Fx.countUp(gl, if shownGold >= 0 then shownGold else gold, gold, 0.6, nil, false)
		shownGold = gold
	end
	local GOLD = Theme.Colors.gold
	-- 1. START ignites.
	paintHex(sv, "owned", false)
	paintParts(sv.inner, Color3.new(1, 1, 1))
	for _, f in sv.inner do
		UI.tween(f, { BackgroundColor3 = GOLD }, 0.5)
	end
	sv.scale.Scale = 1.4
	UI.tween(sv.scale, { Scale = 1 }, 0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	Fx.stinger(4)
	Fx.haptic(0.7)
	local flash = UI.frame({
		BackgroundColor3 = Color3.fromHex("FFE7A3"),
		BackgroundTransparency = 0.55,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 40,
		Parent = g,
	})
	UI.tween(flash, { BackgroundTransparency = 1 }, 0.6)
	task.delay(0.65, function()
		flash:Destroy()
	end)
	for k = 0, 1 do
		task.delay(k * 0.18, function()
			if not open then
				return
			end
			local ring = UI.frame({
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(0, 0),
				Size = UDim2.fromOffset(side * 2, side * 2),
				ZIndex = 2,
				Parent = c,
			})
			UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = ring })
			local st = UI.new("UIStroke", { Color = GOLD, Thickness = S(4), Transparency = 0, Parent = ring })
			local reach = grid * 1.5 * 3 * 2
			UI.tween(ring, { Size = UDim2.fromOffset(reach, reach) }, 0.8, Enum.EasingStyle.Quad)
			UI.tween(st, { Transparency = 1, Thickness = 1 }, 0.8, Enum.EasingStyle.Quad)
			task.delay(0.85, function()
				ring:Destroy()
			end)
		end)
	end
	-- 2. The banner.
	local banner = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, Fx.topInset() + S(4)),
		Size = UDim2.fromOffset(S(560), S(70)),
		ZIndex = 41,
		Parent = g,
	})
	local bScale = UI.new("UIScale", { Scale = 0.6, Parent = banner })
	UI.tween(bScale, { Scale = 1 }, 0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local title = UI.text({
		Text = "SKILL WEB UNLOCKED",
		FontFace = Theme.Fonts.display,
		TextSize = S(40),
		TextColor3 = Color3.new(1, 1, 1),
		Size = UDim2.new(1, 0, 0, S(46)),
		ZIndex = 42,
		Parent = banner,
	})
	local tStroke = UI.stroke(title, Color3.new(0, 0, 0), S(1.5), 0.3)
	UI.new("UIGradient", {
		Color = ColorSequence.new(Color3.fromHex("FFE7A3"), Color3.fromHex("E8A33C")),
		Rotation = 90,
		Parent = title,
	})
	local sub = UI.text({
		Text = "Six branches are open. Buy a hex next to one you own.",
		FontFace = Theme.Fonts.body,
		TextSize = S(16),
		TextColor3 = Theme.Colors.text,
		Position = UDim2.fromOffset(0, S(46)),
		Size = UDim2.new(1, 0, 0, S(22)),
		ZIndex = 42,
		Parent = banner,
	})
	local sStroke = UI.stroke(sub, Color3.new(0, 0, 0), S(1.5), 0.4)
	task.delay(2.6, function()
		if banner.Parent then
			UI.tween(title, { TextTransparency = 1 }, 0.4)
			UI.tween(sub, { TextTransparency = 1 }, 0.4)
			UI.tween(tStroke, { Transparency = 1 }, 0.4)
			UI.tween(sStroke, { Transparency = 1 }, 0.4)
			task.delay(0.45, function()
				banner:Destroy()
			end)
		end
	end)
	-- 3. Ring 1 turns over, clockwise from DAMAGE, with the legend row for each branch.
	local dist = Skills.distances(set)
	local t0, step = 0.5, 0.16
	for i, b in Skills.Branches do
		local nodeId: string? = nil
		for _, n in Skills.List do
			if n.branch == b.id and n.ring == 1 then
				nodeId = n.id
			end
		end
		local id = nodeId
		if not id then
			continue
		end
		task.delay(t0 + (i - 1) * step, function()
			local v = hexes[id]
			if not open or not v then
				return
			end
			paintHex(v, stateOf(id, dist, g0), false)
			v.scale.Scale = 0.2
			UI.tween(v.scale, { Scale = 1 }, 0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			local abs = v.holder.AbsolutePosition + v.holder.AbsoluteSize / 2
			Fx.burst(g, UDim2.fromOffset(abs.X, abs.Y), branchColor(id), 8, 30)
			UI.sound(Fx.Sounds.ding, 1 + i * 0.09, 0.22)
			local row = legendRows[b.id]
			if row then
				row.bg.Visible = true
				UI.punch(row.bg, 1.2, 0.3)
			end
		end)
	end
	-- 4. The ? ring beyond fades in, then everything settles into its normal paint.
	local t1 = t0 + #Skills.Branches * step + 0.15
	task.delay(t1, function()
		if not open then
			return
		end
		for id, v in hexes do
			if v.state == "faint" and stateOf(id, dist, g0) == "outlined" then
				task.delay(math.random() * 0.25, function()
					if open then
						paintHex(v, "outlined", false)
						v.scale.Scale = 0.5
						UI.tween(v.scale, { Scale = 1 }, 0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
					end
				end)
			end
		end
		UI.sound(Fx.Sounds.shimmer, 1.1, 0.2)
	end)
	task.delay(t1 + 0.6, function()
		revealing = false
		if open then
			paintAll(false)
			-- The six new hexes are affordable and now seen: no pulse-once for them on the next open.
			Remotes.SkillSeen:FireServer(Skills.affordableIds(ownedSet(), goldNow()))
		end
	end)
end

buy = function(id: string)
	local node = Skills.ById[id]
	if (not node and id ~= START) or buying or revealing then
		return
	end
	local owned = ownedSet()
	if Skills.owns(owned, id) then
		return
	end
	if not Skills.adjacent(owned, id) or goldNow() < Skills.cost(id) then
		UI.sound(Fx.Sounds.deny, 1, 0.25) -- the store's refusal tick
		local gp = goldPill
		if gp then
			UI.shake(gp, UI.S(4), 0.25)
		end
		return
	end
	buying = true
	local ps = paintSheet
	if ps then
		ps()
	end
	task.spawn(function()
		local ok, res = pcall(function()
			return Remotes.SkillBuy:InvokeServer(id)
		end)
		buying = false
		if not open then
			return
		end
		if not ok or typeof(res) ~= "table" or not res.ok then
			UI.sound(Fx.Sounds.deny, 1, 0.25)
			local gp = goldPill
			if gp then
				UI.shake(gp, UI.S(5), 0.3)
			end
			if paintSheet then
				(paintSheet :: any)()
			end
			return
		end
		-- The reply's owned set is the truth until the next sync says the same.
		local set: { [string]: boolean } = {}
		if typeof(res.owned) == "table" then
			for _, oid in res.owned do
				set[oid] = true
			end
		end
		ownedOverride = set
		if id == START then
			unlockSequence(set, tonumber(res.gold))
			return
		end
		local v = hexes[id]
		-- The hex fills with a quick wipe: a white flash that settles into the branch tint.
		if v then
			paintHex(v, "owned", false)
			local tint = branchColor(id) -- the bright, saturated owned colour
			paintParts(v.inner, Color3.new(1, 1, 1))
			for _, f in v.inner do
				UI.tween(f, { BackgroundColor3 = tint }, 0.35)
			end
			v.scale.Scale = 1.18
			UI.tween(v.scale, { Scale = 1 }, 0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			local g = gui
			local c = canvas
			if g and c then
				local abs = v.holder.AbsolutePosition + v.holder.AbsoluteSize / 2
				Fx.burst(g, UDim2.fromOffset(abs.X, abs.Y), branchColor(id), 10, 30)
			end
		end
		UI.sound(Fx.Sounds.ding, 1.2, 0.35)
		UI.sound(Theme.Sounds.upgrade, 1, 0.25)
		Fx.haptic(0.4)
		-- Edges to owned neighbours light one by one.
		local i = 0
		for _, nb in Skills.neighbours(id) do
			if Skills.owns(set, nb) then
				i += 1
				task.delay(i * 0.08, function()
					if open then
						addSeam(id, nb, true)
					end
				end)
			end
		end
		-- The rest repaints: newly revealed neighbours fade in, prices re-colour against the new balance.
		local gold = tonumber(res.gold)
		local gl = goldLabel
		if gold and gl then
			Fx.countUp(gl, if shownGold >= 0 then shownGold else gold, gold, 0.6, nil, false)
			shownGold = gold
		end
		task.delay(0.12, function()
			if open then
				paintAll(true)
			end
		end)
	end)
end

------------------------------------------------------------------ Build
local function clearInput()
	for _, c in inputConns do
		c:Disconnect()
	end
	inputConns = {}
	local rc = renderConn
	if rc then
		rc:Disconnect()
		renderConn = nil
	end
end

local function overChrome(pos: Vector2): boolean
	for _, f in chrome do
		if f.Parent and f.Visible then
			local p, s = f.AbsolutePosition, f.AbsoluteSize
			if pos.X >= p.X and pos.X <= p.X + s.X and pos.Y >= p.Y and pos.Y <= p.Y + s.Y then
				return true
			end
		end
	end
	return false
end

-- Input positions are below the top bar inset; the scene's ScreenGui ignores the inset.
local function screenPos(input: InputObject): Vector2
	local inset = GuiService:GetGuiInset()
	return Vector2.new(input.Position.X, input.Position.Y) + inset
end

local build: () -> () = function() end

local function bindInput()
	clearInput()
	local mouseDown: { start: Vector2, startPan: Vector2 }? = nil
	local touches: { [InputObject]: boolean } = {}
	local lastTouch: { [InputObject]: Vector2 } = {}
	local dragged = false
	local dragFrom: Vector2? = nil
	local DRAG = UI.S(8)
	local lastBackdropTap = 0
	SkillScene.dragged = function(): boolean
		return dragged
	end
	table.insert(
		inputConns,
		UserInputService.InputBegan:Connect(function(input: InputObject)
			if not open then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				local p = screenPos(input)
				dragged = false
				if not overChrome(p) then
					mouseDown = { start = p, startPan = pan }
				end
			elseif input.UserInputType == Enum.UserInputType.Touch then
				local p = screenPos(input)
				if next(touches) == nil then
					dragged = false
					dragFrom = p
				end
				if not overChrome(p) then
					touches[input] = true
					lastTouch[input] = p
				end
			end
		end)
	)
	table.insert(
		inputConns,
		UserInputService.InputChanged:Connect(function(input: InputObject)
			if not open then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				local md = mouseDown
				if md then
					local p = screenPos(input)
					if dragged or (p - md.start).Magnitude > DRAG then
						dragged = true
						panTarget = nil
						pan = clampPan(md.startPan + (p - md.start))
						applyView()
					end
				end
			elseif input.UserInputType == Enum.UserInputType.MouseWheel then
				local p = UserInputService:GetMouseLocation()
				if not overChrome(p) then
					zoomAt(zoom * (1.12 ^ input.Position.Z), p)
				end
			end
		end)
	)
	table.insert(
		inputConns,
		UserInputService.InputEnded:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				mouseDown = nil
			elseif input.UserInputType == Enum.UserInputType.Touch then
				touches[input] = nil
				lastTouch[input] = nil
			end
		end)
	)
	SkillScene.backdropTap = function()
		if dragged then
			return
		end
		local now = os.clock()
		if now - lastBackdropTap < 0.35 then
			centreOn(START, false)
			lastBackdropTap = 0
		else
			lastBackdropTap = now
		end
		if selected then
			closeSheet()
		end
	end
	-- Per frame: touch pan / pinch (polled: the InputChanged stream drops fingers), gamepad, easing, pulses.
	renderConn = RunService.RenderStepped:Connect(function(dt)
		if not open then
			return
		end
		local list = {}
		for input in touches do
			if
				input.UserInputState == Enum.UserInputState.End
				or input.UserInputState == Enum.UserInputState.Cancel
			then
				touches[input] = nil
				lastTouch[input] = nil
			else
				table.insert(list, input)
			end
		end
		if #list == 1 then
			local input = list[1]
			local p = screenPos(input)
			local last = lastTouch[input] or p
			if dragged or (dragFrom and (p - dragFrom).Magnitude > DRAG) then
				dragged = true
				panTarget = nil
				pan = clampPan(pan + (p - last))
				applyView()
			end
			lastTouch[input] = p
		elseif #list >= 2 then
			local a, b = list[1], list[2]
			local pa, pb = screenPos(a), screenPos(b)
			local la, lb = lastTouch[a] or pa, lastTouch[b] or pb
			local d0 = (la - lb).Magnitude
			local d1 = (pa - pb).Magnitude
			local mid0, mid1 = (la + lb) / 2, (pa + pb) / 2
			dragged = true
			panTarget = nil
			pan = clampPan(pan + (mid1 - mid0))
			if d0 > 4 and d1 > 4 then
				zoomAt(zoom * (d1 / d0), mid1)
			end
			applyView()
			lastTouch[a], lastTouch[b] = pa, pb
		end
		-- Gamepad: the right stick pans, the triggers zoom.
		for _, state in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
			if state.KeyCode == Enum.KeyCode.Thumbstick2 then
				local v = Vector2.new(state.Position.X, -state.Position.Y)
				if v.Magnitude > 0.2 then
					panTarget = nil
					pan = clampPan(pan - v * UI.S(600) * dt)
					applyView()
				end
			elseif state.KeyCode == Enum.KeyCode.ButtonR2 and state.Position.Z > 0.1 then
				zoomAt(zoom * (1 + 1.5 * dt * state.Position.Z))
			elseif state.KeyCode == Enum.KeyCode.ButtonL2 and state.Position.Z > 0.1 then
				zoomAt(zoom / (1 + 1.5 * dt * state.Position.Z))
			end
		end
		local target = panTarget
		if target then
			local k = 1 - math.exp(-dt * 12)
			pan = pan:Lerp(target, k)
			if (pan - target).Magnitude < 0.5 then
				pan = target
				panTarget = nil
			end
			applyView()
		end
		-- Affordable hexes breathe a slow white edge; a newly affordable one pulses brighter once.
		local t = os.clock()
		local k = (math.sin(t * 2.2) + 1) / 2
		for id, v in hexes do
			if selected == id then
				continue
			end
			if v.pulse > t then
				local f = (v.pulse - t) / Config.SkillNewPulseSec
				local glow = (math.sin(f * math.pi * 3) + 1) / 2
				paintParts(v.outer, Theme.Colors.gold:Lerp(Color3.new(1, 1, 1), glow))
				v.scale.Scale = 1 + 0.12 * glow * f
			elseif v.pulse ~= 0 then
				v.pulse = 0
				v.scale.Scale = 1
				paintHex(v, v.state, false)
			elseif v.state == "affordable" then
				paintParts(v.outer, v.edge:Lerp(Color3.new(1, 1, 1), k))
			end
		end
	end)
end

build = function()
	local old = gui
	if old then
		old:Destroy()
	end
	hexes, seams, legendRows, chrome = {}, {}, {}, {}
	sheet, paintSheet = nil, nil
	local S = UI.S
	local mobile = ClientState.isMobile
	local vp = camera.ViewportSize
	local top = Fx.topInset()
	local g = UI.new("ScreenGui", {
		Name = "SkillScene",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 9,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	}) :: ScreenGui
	gui = g
	-- Phone: every label reads MobileStoreTextScale bigger, as in the store (FixedTextSize opts out: the hexes).
	if mobile and (Config.MobileStoreTextScale or 1) ~= 1 then
		local k = Config.MobileStoreTextScale
		g.DescendantAdded:Connect(function(d)
			if (d:IsA("TextLabel") or d:IsA("TextButton")) and not d:GetAttribute("FixedTextSize") then
				-- At once, as the store does: UI.caps' deferred font factor then builds on this size.
				local t = d :: TextLabel
				t.TextSize = math.round(t.TextSize * k)
			end
		end)
	end

	-- Sizes: a hex is SkillHexPx wide at zoom 1 (never under 56 px on a phone).
	local hexW = math.max(S(Config.SkillHexPx), if mobile then 56 else 0)
	side = hexW / 2
	grid = side * GAP
	webRadius = grid * 1.5 * SkillLayout.Rings + side
	-- The web's extent at zoom 1 and the room it has (under the title strip, beside nothing: the sheet floats).
	local webW = grid * 1.5 * SkillLayout.Rings * 2 + side * 2
	local webH = grid * SQ3 * (SkillLayout.Rings * 2 + 1)
	local roomW = vp.X - S(40)
	local roomH = vp.Y - top - S(70)
	local fit = math.min(roomW / webW, roomH / webH)
	zoomMin = math.min(Config.SkillZoomMin, fit)
	zoomMax = math.max(zoomMin, Config.SkillZoomMax)

	-- The backdrop: dark over the blurred hub. A tap on it closes the sheet; a double-tap recentres on START.
	local dim = UI.button({
		Name = "Backdrop",
		Text = "",
		BackgroundColor3 = Color3.fromHex("07070A"),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Selectable = false,
		ZIndex = 1,
		Parent = g,
	})
	UI.tween(dim, { BackgroundTransparency = 0.12 }, 0.25)
	dim.Activated:Connect(function()
		local f = SkillScene.backdropTap
		if f then
			f()
		end
	end)

	-- The canvas: a 0x0 frame at the view centre + pan; hex positions are web px from START; UIScale zooms.
	local c = UI.frame({
		Name = "Canvas",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(0, 0),
		ZIndex = 2,
		Parent = g,
	})
	canvas = c
	zoomScale = UI.new("UIScale", { Name = "Zoom", Scale = 1, Parent = c })
	seamLayer = UI.frame({
		Name = "Seams",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 0),
		ZIndex = 2,
		Parent = c,
	})
	hexes[START] = buildHex(c, START, 0, 0)
	for _, n in Skills.List do
		hexes[n.id] = buildHex(c, n.id, n.q, n.r)
	end
	for id, v in hexes do
		v.button.Activated:Connect(function(input: InputObject?)
			local dragged = SkillScene.dragged
			if dragged and dragged() then
				return
			end
			if v.state == "faint" then
				return
			end
			-- Brief 11: on a pad the hex is already open (the selection opens it), so A buys it.
			if input and string.sub(input.UserInputType.Name, 1, 7) == "Gamepad" and selected == id then
				buy(id)
				return
			end
			select(id)
		end)
		v.button.MouseEnter:Connect(function()
			hovered = id
			paintLegend()
			if not mobile and v.state ~= "faint" then
				UI.tween(v.scale, { Scale = 1.06 }, 0.1)
			end
		end)
		v.button.MouseLeave:Connect(function()
			if hovered == id then
				hovered = nil
				paintLegend()
			end
			if v.pulse == 0 then
				UI.tween(v.scale, { Scale = 1 }, 0.1)
			end
		end)
		v.button.SelectionGained:Connect(function()
			hovered = id
			paintLegend()
		end)
	end

	-- Title and legend, top-left.
	local narrow = vp.X < 720
	local titleH = if mobile then S(34) else S(44)
	local title = UI.text({
		Name = "Title",
		Text = "SKILL WEB",
		FontFace = Theme.Fonts.display,
		TextSize = if mobile then S(26) else S(36),
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(S(22), top),
		Size = UDim2.fromOffset(S(260), titleH),
		ZIndex = 10,
		Parent = g,
	})
	UI.stroke(title, Color3.new(0, 0, 0), S(1.5), 0.3)
	UI.new("UIGradient", {
		Color = ColorSequence.new(Color3.fromHex("FFE7A3"), Color3.fromHex("E8A33C")),
		Rotation = 90,
		Parent = title,
	})
	local rowH = if mobile then S(26) else S(28)
	local legend = UI.frame({
		Name = "Legend",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(S(22), top + titleH + S(6)),
		Size = UDim2.fromOffset(if narrow then rowH else S(150), rowH * 6 + S(4) * 5),
		ZIndex = 10,
		Parent = g,
	})
	UI.list(legend, Enum.FillDirection.Vertical, S(4))
	table.insert(chrome, legend)
	UI.mobileGrow(legend, mobile) -- the hub HUD's mobile size (MobileButtonScale)
	for i, b in Skills.Branches do
		local color = Color3.fromHex(b.color)
		local row = UI.frame({
			Name = b.id,
			BackgroundColor3 = PANEL,
			BackgroundTransparency = 0.35,
			Size = UDim2.new(1, 0, 0, rowH),
			LayoutOrder = i,
			ZIndex = 10,
			Parent = legend,
		})
		UI.corner(row, S(3))
		local chip = UI.frame({
			BackgroundColor3 = color,
			Size = UDim2.fromOffset(rowH, rowH),
			ZIndex = 11,
			Parent = row,
		})
		UI.corner(chip, S(3))
		local icon = Icons.draw(chip, b.icon, math.floor(rowH * 0.74), Theme.Colors.white, color)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		local label: TextLabel? = nil
		if not narrow then
			label = UI.text({
				Text = b.name,
				FontFace = Theme.Fonts.display,
				TextSize = S(15),
				TextColor3 = Theme.Colors.textDim,
				TextXAlignment = Enum.TextXAlignment.Left,
				Position = UDim2.fromOffset(rowH + S(8), 0),
				Size = UDim2.new(1, -rowH - S(10), 1, 0),
				ZIndex = 11,
				Parent = row,
			})
		end
		legendRows[b.id] = { label = label, icon = icon, bg = row }
		-- Round 26c: the branches are a secret until START is bought (the unlock reveals them row by row).
		row.Visible = Skills.unlocked(ownedSet())
	end

	-- The Gold pill, top-right (the store's balance style).
	local pillH = if mobile then S(36) else S(42)
	local pill = UI.frame({
		Name = "Gold",
		BackgroundColor3 = Color3.fromHex("1E1E25"),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -S(14), 0, top),
		Size = UDim2.fromOffset(if mobile then S(150) else S(190), pillH),
		ZIndex = 10,
		Parent = g,
	})
	UI.corner(pill, S(6))
	UI.stroke(pill, Theme.Colors.gold, S(1.5), 0.3)
	goldPill = pill
	UI.mobileGrow(pill, mobile)
	table.insert(chrome, pill)
	UI.text({
		Text = "◆",
		FontFace = Theme.Fonts.display,
		TextSize = S(20),
		TextColor3 = Theme.Colors.gold,
		Position = UDim2.fromOffset(S(6), 0),
		Size = UDim2.new(0, S(24), 1, 0),
		ZIndex = 11,
		Parent = pill,
	})
	goldLabel = UI.text({
		Text = "0",
		FontFace = Theme.Fonts.display,
		TextSize = if mobile then S(18) else S(21),
		TextColor3 = Theme.Colors.white,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(S(34), 0),
		Size = UDim2.new(1, -S(70), 1, 0),
		ZIndex = 11,
		Parent = pill,
	})
	local plus = UI.button({
		Text = "+",
		FontFace = Theme.Fonts.display,
		TextSize = S(18),
		TextColor3 = Theme.Colors.bg,
		BackgroundColor3 = Theme.Colors.gold,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -S(5), 0.5, 0),
		Size = UDim2.fromOffset(S(28), S(28)),
		ZIndex = 11,
		Parent = pill,
	})
	UI.corner(plus, S(4))
	Fx.interactive(plus)
	plus.Activated:Connect(function()
		SkillScene.close()
		ClientState.Juice:Fire("OpenStore", { tab = "GOLD" })
	end)
	shownGold = -1
	paintGold(false)

	-- BACK, bottom-left: the red X tile.
	local backSize = if mobile then S(56) else S(60)
	local backHolder = UI.frame({
		Name = "Back",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, S(20), 1, -S(14)),
		Size = UDim2.fromOffset(backSize, backSize + S(16)),
		ZIndex = 10,
		Parent = g,
	})
	table.insert(chrome, backHolder)
	UI.mobileGrow(backHolder, mobile)
	local back = UI.button({
		Name = "BackButton",
		Text = "",
		BackgroundColor3 = Theme.Colors.red,
		Size = UDim2.fromOffset(backSize, backSize),
		Selectable = true,
		ZIndex = 11,
		Parent = backHolder,
	})
	UI.corner(back, S(4))
	UI.stroke(back, Theme.Colors.black, S(1.5), 0.3)
	local x = Icons.draw(back, "close", math.floor(backSize * 0.6), Theme.Colors.white, Theme.Colors.red)
	x.AnchorPoint = Vector2.new(0.5, 0.5)
	x.Position = UDim2.fromScale(0.5, 0.5)
	local backLabel = UI.text({
		Text = "BACK",
		FontFace = Theme.Fonts.display,
		TextSize = S(12),
		TextColor3 = Theme.Colors.text,
		Position = UDim2.fromOffset(0, backSize + S(1)),
		Size = UDim2.new(1, 0, 0, S(14)),
		ZIndex = 11,
		Parent = backHolder,
	})
	UI.stroke(backLabel, Theme.Colors.black, S(1.5), 0.3)
	Fx.interactive(back)
	back.Activated:Connect(function()
		SkillScene.close()
	end)

	buildSheet(g, vp, top, mobile)
	bindInput()
	paintAll(false)
	applyView()
end

------------------------------------------------------------------ Open / close
function SkillScene.isOpen(): boolean
	return open
end

function SkillScene.open()
	if open or not Config.SkillsEnabled then
		return
	end
	if not ClientState.inHub() or ClientState.downed or ClientState.spectating then
		return
	end
	-- One premium screen at a time.
	ClientState.Juice:Fire("CloseStore", {})
	ClientState.Juice:Fire("CloseMeta", {})
	ClientState.Juice:Fire("ClosePass", {})
	ClientState.Juice:Fire("CloseJobs", {})
	open = true
	ownedOverride = nil
	selected = nil
	hovered = nil
	ClientState.setAds(false)
	ClientState.setBlock("skills", true)
	ClientState.lockMovement("skills", true)
	HUD.setMode("meta")
	Nameplates.setLocalHidden(true)
	local b = UI.new("BlurEffect", { Name = "SkillBlur", Size = 0, Parent = camera }) :: BlurEffect
	blur = b
	UI.tween(b, { Size = 14 }, 0.3)
	UI.sound(Fx.Sounds.whoosh, 1, 0.4) -- the pass scene's open
	zoom = 1
	build()
	-- Round 26b: opens centred on START, zoomed all the way in (SkillOpenZoom).
	zoom = math.clamp(Config.SkillOpenZoom, zoomMin, zoomMax)
	centreOn(START, true)
	-- Pulse once: affordable now and not seen on an earlier visit. Then the server records them as seen.
	local owned = ownedSet()
	local seen = seenSet()
	local affordable = Skills.affordableIds(owned, goldNow())
	local fresh = {}
	for i, id in affordable do
		local v = hexes[id]
		if v and not seen[id] then
			v.pulse = os.clock() + Config.SkillNewPulseSec + i * 0.02
			table.insert(fresh, id)
		end
	end
	if #fresh > 0 then
		Remotes.SkillSeen:FireServer(fresh)
		UI.sound(Fx.Sounds.shimmer, 1.2, 0.18)
	end
	local g = gui
	if g then
		local c = canvas
		if c then
			local zs = zoomScale
			if zs then
				zs.Scale = zoom * 0.92
				UI.tween(zs, { Scale = zoom }, 0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			end
		end
	end
end

function SkillScene.close()
	if not open then
		return
	end
	open = false
	buying = false
	revealing = false
	clearInput()
	if gui then
		gui:Destroy()
		gui = nil
	end
	local b = blur
	blur = nil
	if b then
		UI.tween(b, { Size = 0 }, 0.2)
		task.delay(0.25, function()
			b:Destroy()
		end)
	end
	hexes, seams, legendRows, chrome = {}, {}, {}, {}
	canvas, zoomScale, seamLayer, sheet, paintSheet = nil, nil, nil, nil, nil
	goldLabel, goldPill = nil, nil
	ownedOverride = nil
	Nameplates.setLocalHidden(false)
	ClientState.setBlock("skills", false)
	ClientState.lockMovement("skills", false)
	HUD.setMode(HUD.baseMode())
	UI.sound(Fx.Sounds.whoosh, 0.7, 0.35) -- the pass scene's close
end

------------------------------------------------------------------ Init
local lastStamp = ""
local function stamp(p: any): string
	if not p then
		return ""
	end
	local n = 0
	local s = p.skills
	for id in (if s and s.owned then s.owned else {}) do
		n += #id * 7 + string.byte(id, 1)
	end
	return tostring(p.gold) .. "|" .. tostring(n)
end

function SkillScene.init()
	-- Brief 11: on a pad the selection hops hex to hex (Roblox's selection along GamepadNav's neighbours), each hex
	-- it lands on opens its sheet and the view glides to it; A buys; B closes the sheet (the selection stays on the
	-- hex), B again leaves. The right stick pans and the triggers zoom (below).
	local lastHex = START
	local function hexOf(g: GuiObject): string?
		for id, v in hexes do
			if v.button == g then
				return id
			end
		end
		return nil
	end
	GamepadNav.register("skills", {
		default = function()
			local v = hexes[selected or lastHex] or hexes[START]
			return if v then v.button else nil
		end,
		onSelect = function(g: GuiObject)
			local id = hexOf(g)
			if id then
				lastHex = id
				local v = hexes[id]
				if v and v.state ~= "faint" and selected ~= id then
					select(id) -- moving onto a hex opens its sheet: A buys it, B closes the sheet and stays here
				else
					centreInFree(id, false)
				end
			end
		end,
		-- the hexes only: the sheet's BUY is the hex's own A on a pad
		filter = function(g: GuiObject): boolean
			local s = sheet
			return not (s and g:IsDescendantOf(s))
		end,
		page = function() end, -- the triggers zoom here (polled below)
	})
	ClientState.Juice:Connect(function(name: string, _data: any)
		if name == "OpenSkills" then
			SkillScene.open()
		elseif name == "CloseSkills" or name == "RunStartBegin" or name == "Downed" or name == "BledOut" then
			SkillScene.close()
		end
	end)
	ClientState.Changed:Connect(function(sync: any)
		if not open then
			return
		end
		if not ClientState.inHub() then
			SkillScene.close()
			return
		end
		paintGold(true)
		local st = stamp(sync.profile)
		if st ~= lastStamp then
			lastStamp = st
			-- The sync caught up with the last buy: drop the reply's copy.
			local p = sync.profile
			local o = ownedOverride
			if o and p and p.skills and p.skills.owned then
				local same = true
				for id in o do
					if not p.skills.owned[id] then
						same = false
					end
				end
				if same then
					ownedOverride = nil
				end
			end
			if not buying and not revealing then
				paintAll(true)
			end
		end
	end)
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		if open then
			local keepSel = selected
			build()
			zoom = math.clamp(zoom, zoomMin, zoomMax)
			centreOn(START, true)
			if keepSel then
				select(keepSel)
			end
		end
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if not open then
			return
		end
		local back = input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB
		if back and (not gameProcessed or input.KeyCode == Enum.KeyCode.ButtonB) then
			if selected then
				closeSheet()
			else
				SkillScene.close()
			end
		end
	end)
end

return SkillScene
