--!strict
-- Brief 6 FEATURED section (Round 17c). One wide featured bundle (Bundles.lua, rotating every
-- Config.FeaturedRotationSec on the fake clock) with every item it holds laid out on the bar, CLASS + WEAPON + ... ,
-- the -X% against buying them apart and BUY right there: no detail sheet, no owned discount (owned items are marked
-- and skipped). Under it the DAILY ITEMS: Config.DailyShopItems single items from crates and past events
-- (DailyShop.lua), redrawn every fake UTC day and sold one by one. Both carry a LEAVING IN hh:mm:ss countdown.
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Bundles = require(Shared:WaitForChild("Bundles"))
local Rewards = require(Shared:WaitForChild("Rewards"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Clock = require(Shared:WaitForChild("Clock"))
local DailyShop = require(Shared:WaitForChild("DailyShop"))
local Config = require(Shared:WaitForChild("Config"))

local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local ClientState = require(Client:WaitForChild("ClientState"))
local Fx = require(script.Parent:WaitForChild("Fx"))
local Card = require(script.Parent:WaitForChild("Card"))
local ItemArt = require(script.Parent:WaitForChild("ItemArt"))
local Reveal = require(script.Parent:WaitForChild("Reveal"))

local FeaturedTab = {}

local timerConn: RBXScriptConnection? = nil

-- The rotation's bundle, or the one a VIEW BUNDLE deep link asked for.
local function featuredBundle(arg: any?): Bundles.Bundle
	if typeof(arg) == "table" and arg.bundle and Bundles.ById[arg.bundle] then
		return Bundles.ById[arg.bundle]
	end
	local slot = Clock.featuredSlot(ClientState.fakeNow())
	return Bundles.List[(slot % #Bundles.List) + 1]
end

-- Phone pass (touch): the bundle bar stacks in two rows (name · tagline · -X% left and worth · price · BUY right
-- over the full-width item strip, no + signs), so a 7-item bundle's tiles stay wide enough for their art and names;
-- the daily cards get a fixed height and the section grows to hold both (StoreScene keeps the size a tab sets).
local MOBILE_BAR_H = 330 -- the bundle bar's height (UI px at the basis)
local MOBILE_TOP_H = 130 -- its top row (name / price / BUY); the item strip fills the rest
local MOBILE_DAILY_H = 280 -- one daily card's height

-- A framed countdown pill: `LEAVING IN 62:14:05`.
local function timerPill(parent: Instance, position: UDim2, anchor: Vector2, color: Color3): TextLabel
	local S = UI.S
	local pill = UI.frame({
		BackgroundColor3 = Fx.shade(color, -0.75),
		AnchorPoint = anchor,
		Position = position,
		Size = UDim2.fromOffset(S(230), S(34)),
		ZIndex = 8,
		Parent = parent,
	})
	UI.corner(pill, S(17))
	UI.stroke(pill, color, S(1.5), 0.1)
	local l = UI.text({
		Text = "",
		FontFace = Theme.Fonts.display,
		TextSize = S(16),
		TextColor3 = Fx.shade(color, 0.4),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 9,
		Parent = pill,
	})
	if ClientState.isMobile then
		Card.fitText(l)
	end
	return l
end

local function sectionTitle(parent: Instance, text: string, y: number, color: Color3)
	local S = UI.S
	UI.text({
		Text = text,
		FontFace = Theme.Fonts.display,
		TextSize = S(28),
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.new(0.5, 0, 0, S(34)),
		ZIndex = 7,
		Parent = parent,
	})
end

------------------------------------------------------------------ The bundle bar
local function bundleBar(ctx: any, parent: Frame, y: number, h: number)
	local S = UI.S
	local b = featuredBundle(ctx.arg)
	local profile = ctx.profile()
	local price, owned = Bundles.priceFor(b, profile)
	local color = Color3.fromHex(b.color)
	local allOwned = true
	for i in b.contents do
		if not owned[i] then
			allOwned = false
		end
	end
	local holder = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.new(1, 0, 0, h),
		ZIndex = 6,
		Parent = parent,
	})
	local _g, setGlow = Fx.glow(holder, color, S(14), 6)
	setGlow(1.3)
	Fx.pulse(setGlow, function()
		return holder.Parent ~= nil
	end, 2.4, 1.0, 1.6)
	local bar = UI.frame({
		BackgroundColor3 = Color3.fromHex("141218"),
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = true,
		ZIndex = 7,
		Parent = holder,
	})
	UI.corner(bar, S(14))
	UI.stroke(bar, color, S(2), 0.1)
	UI.new("UIGradient", {
		Color = ColorSequence.new(Fx.shade(color, -0.5), Color3.fromHex("0E0E12")),
		Rotation = 0,
		Parent = bar,
	})
	Fx.rays(bar, color, 10, math.floor(h * 2.4), 7, 6).Position = UDim2.fromScale(0.12, 0.5)
	Fx.particles(bar, color, 4, 8)
	local mobile = ClientState.isMobile
	local topH = S(MOBILE_TOP_H)
	-- Left: the name, the tagline, the discount (phone: one line each across the top row).
	local left = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(S(22), if mobile then S(14) else S(18)),
		Size = if mobile then UDim2.new(0.58, 0, 0, topH) else UDim2.new(0.24, 0, 1, -S(36)),
		ZIndex = 8,
		Parent = bar,
	})
	local name = UI.text({
		Text = b.name,
		FontFace = Theme.Fonts.display,
		TextSize = S(32),
		TextColor3 = Theme.Colors.white,
		TextWrapped = not mobile,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, 0, 0, if mobile then S(46) else S(80)),
		ZIndex = 9,
		Parent = left,
	})
	UI.stroke(name, Color3.new(0, 0, 0), S(2), 0.2)
	local tagline = UI.text({
		Text = b.tagline,
		FontFace = Theme.Fonts.body,
		TextSize = S(13),
		TextColor3 = Fx.shade(color, 0.45),
		TextWrapped = not mobile,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(0, if mobile then S(50) else S(84)),
		Size = UDim2.new(1, 0, 0, if mobile then S(26) else S(36)),
		ZIndex = 9,
		Parent = left,
	})
	if mobile then
		Card.fitText(name)
		Card.fitText(tagline)
	end
	local off = UI.frame({
		BackgroundColor3 = Color3.fromHex("FF6A3D"),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.fromOffset(S(96), S(34)),
		Rotation = -4,
		ZIndex = 9,
		Parent = left,
	})
	UI.corner(off, S(6))
	UI.text({
		Text = "-" .. Bundles.discountPct(b) .. "%",
		FontFace = Theme.Fonts.display,
		TextSize = S(22),
		TextColor3 = Theme.Colors.white,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 10,
		Parent = off,
	})
	-- Middle: every item, joined by + (phone: the full-width strip under the top row, spaced by a gap).
	local stripTop = S(14) + topH + S(10)
	local contents = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = if mobile then Vector2.zero else Vector2.new(0, 0.5),
		Position = if mobile then UDim2.fromOffset(S(16), stripTop) else UDim2.new(0.26, 0, 0.5, 0),
		Size = if mobile then UDim2.new(1, -S(32), 0, h - stripTop - S(12)) else UDim2.new(0.52, 0, 1, -S(28)),
		ZIndex = 8,
		Parent = bar,
	})
	local gapW = if mobile then S(8) else S(4)
	UI.list(
		contents,
		Enum.FillDirection.Horizontal,
		gapW,
		Enum.HorizontalAlignment.Center,
		Enum.VerticalAlignment.Center
	)
	local cw = contents.AbsoluteSize.X
	if cw < 50 then
		cw = if mobile and parent.AbsoluteSize.X > 50
			then parent.AbsoluteSize.X - S(32)
			elseif mobile then S(860)
			else S(520)
	end
	local n = #b.contents
	local plusW = S(18)
	local tileW = if mobile
		then math.floor(math.min((cw - gapW * (n - 1)) / n, S(150)))
		else math.floor(math.min((cw - plusW * (n - 1) - S(4) * (2 * n)) / n, S(150)))
	local tileH = if mobile then h - stripTop - S(12) else math.min(h - S(40), math.floor(tileW * 1.35))
	local tiles: { GuiObject } = {}
	for i, c in b.contents do
		local r = c :: any
		local rarity = Rewards.rarity(r)
		local rc = Rarity.color(rarity)
		local tile = UI.frame({
			BackgroundColor3 = Fx.shade(rc, -0.7),
			Size = UDim2.fromOffset(tileW, tileH),
			LayoutOrder = i * 2,
			ZIndex = 9,
			Parent = contents,
		})
		UI.corner(tile, S(10))
		UI.stroke(tile, rc, S(1.5), if owned[i] then 0.7 else 0.05)
		UI.new(
			"UIGradient",
			{ Color = ColorSequence.new(Fx.shade(rc, -0.35), Fx.shade(rc, -0.85)), Rotation = 90, Parent = tile }
		)
		-- Phone: the art is a square in the space over the two text rows (top-anchored, inside the tile); the name gets
		-- two wrapped lines and the kind line a readable size, both fitted to their boxes.
		local artSize = if mobile
			then math.max(S(24), math.floor(math.min(tileW - S(10), tileH - S(78))))
			else math.floor(math.min(tileW, tileH * 0.62) * 0.92)
		local art = ItemArt.draw(tile, r, artSize, 10)
		art.AnchorPoint = if mobile then Vector2.new(0.5, 0) else Vector2.new(0.5, 0.5)
		art.Position = if mobile then UDim2.new(0.5, 0, 0, S(6)) else UDim2.fromScale(0.5, 0.38)
		Fx.bob(art, S(2), 2.2 + i * 0.2)
		local itemName = UI.text({
			Text = Rewards.name(r),
			FontFace = Theme.Fonts.display,
			TextSize = S(13),
			TextColor3 = Theme.Colors.white,
			TextWrapped = true,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, if mobile then -S(28) else -S(20)),
			Size = UDim2.new(1, -S(8), 0, if mobile then S(42) else S(30)),
			ZIndex = 10,
			Parent = tile,
		})
		-- (Phone: no kind line where the name already says it, 10 REVIVE TOKENS / 2,000 GOLD / ARMS CRATE ×1.)
		local named = mobile and (r.kind == "gold" or r.kind == "tokens" or r.kind == "crate" or r.kind == "boost")
		local kind = UI.text({
			Text = if owned[i] then "OWNED" elseif named then "" else Rewards.kindLabel(r),
			FontFace = Theme.Fonts.body,
			TextSize = if mobile then S(13) else S(10),
			TextColor3 = if owned[i] then Theme.Colors.grey else rc,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -S(5)),
			Size = UDim2.new(1, if mobile then -S(6) else 0, 0, if mobile then S(20) else S(13)),
			ZIndex = 10,
			Parent = tile,
		})
		if mobile then
			Card.fitText(itemName)
			Card.fitText(kind)
		end
		if owned[i] then
			tile.BackgroundTransparency = 0.5
		end
		table.insert(tiles, tile)
		if i < n and not mobile then
			UI.text({
				Text = "+",
				FontFace = Theme.Fonts.display,
				TextSize = S(26),
				TextColor3 = Fx.shade(color, 0.4),
				Size = UDim2.fromOffset(plusW, S(30)),
				LayoutOrder = i * 2 + 1,
				ZIndex = 9,
				Parent = contents,
			})
		end
	end
	if not ctx.quiet then
		for i, t in tiles do
			t.Visible = false
			task.delay(0.1 + i * 0.06, function()
				if t.Parent then
					t.Visible = true
					local sc = UI.new("UIScale", { Scale = 0.5, Parent = t })
					UI.tween(sc, { Scale = 1 }, 0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
				end
			end)
		end
	end
	-- Right: worth, price, BUY (phone: the top row's right side).
	local right = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = if mobile then Vector2.new(1, 0) else Vector2.new(1, 0.5),
		Position = if mobile then UDim2.new(1, -S(20), 0, S(14)) else UDim2.new(1, -S(20), 0.5, 0),
		Size = if mobile then UDim2.new(0.3, 0, 0, topH) else UDim2.new(0.19, 0, 1, -S(36)),
		ZIndex = 8,
		Parent = bar,
	})
	local worth = UI.text({
		Text = "WORTH R$ " .. UI.fmtInt(Bundles.listPrice(b)),
		FontFace = Theme.Fonts.display,
		TextSize = S(15),
		TextColor3 = Theme.Colors.grey,
		Size = UDim2.new(1, 0, 0, S(20)),
		ZIndex = 9,
		Parent = right,
	})
	if mobile then
		Card.fitText(worth)
	end
	UI.frame({
		BackgroundColor3 = Theme.Colors.grey,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.8, 0, 0, S(2)),
		ZIndex = 10,
		Parent = worth,
	})
	local priceRow = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, S(26)),
		Size = UDim2.new(1, 0, 0, S(44)),
		ZIndex = 9,
		Parent = right,
	})
	UI.list(
		priceRow,
		Enum.FillDirection.Horizontal,
		S(8),
		Enum.HorizontalAlignment.Center,
		Enum.VerticalAlignment.Center
	)
	Fx.robux(priceRow, S(28), 10)
	UI.text({
		Text = UI.fmtInt(price),
		FontFace = Theme.Fonts.display,
		TextSize = S(38),
		TextColor3 = Theme.Colors.white,
		Size = UDim2.fromOffset(0, S(44)),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 2,
		ZIndex = 10,
		Parent = priceRow,
	})
	local buy, handle = Fx.button(
		right,
		if allOwned then "OWNED" else "BUY",
		Color3.fromHex("2FB75A"),
		Theme.Colors.white,
		UDim2.new(1, 0, 0, S(56)),
		10
	)
	buy.AnchorPoint = Vector2.new(0, 1)
	buy.Position = UDim2.fromScale(0, 1)
	buy.TextSize = S(26)
	handle.setEnabled(not allOwned)
	if not allOwned then
		Fx.shine(buy, 2)
	end
	buy.Activated:Connect(function()
		if allOwned then
			return
		end
		ctx.buy(b.id, {
			context = "store FEATURED " .. b.id,
			onSuccess = function(data: any)
				local results = if typeof(data) == "table" and typeof(data.results) == "table" then data.results else {}
				Reveal.stack(ctx.overlay, results, b.name .. " UNLOCKED", {
					onDone = function()
						ctx.refresh()
					end,
				})
				for _, res in results do
					if res.kind == "gold" and not res.skipped then
						task.delay(0.6, function()
							ctx.goldBurst(nil)
						end)
						break
					end
				end
			end,
		})
	end)
	-- The leaving countdown sits on the section's title row (Round 18: on the bar it covered the price).
	return timerPill(parent, UDim2.new(1, 0, 0, y - S(42)), Vector2.new(1, 0), Color3.fromHex("FF6A3D"))
end

------------------------------------------------------------------ The daily items
local function dailyItems(ctx: any, parent: Frame, y: number): TextLabel
	local S = UI.S
	local profile = ctx.profile()
	local day = Clock.day(ClientState.fakeNow())
	local rerolls = DailyShop.rerollsOn(profile, day)
	sectionTitle(parent, "DAILY ITEMS", y, Theme.Colors.text)
	local pill = timerPill(parent, UDim2.new(1, 0, 0, y), Vector2.new(1, 0), Color3.fromHex("4D9FE8"))
	-- Round 18: REROLL draws a fresh set of daily items for fake Robux, left of the timer.
	local reroll, _rh =
		Fx.button(parent, "", Color3.fromHex("2A2A33"), Theme.Colors.white, UDim2.fromOffset(S(150), S(34)), 8)
	reroll.AnchorPoint = Vector2.new(1, 0)
	reroll.Position = UDim2.new(1, -S(242), 0, y)
	local rr = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 9,
		Parent = reroll,
	})
	UI.list(rr, Enum.FillDirection.Horizontal, S(6), Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	UI.text({
		Text = "REROLL",
		FontFace = Theme.Fonts.display,
		TextSize = S(15),
		TextColor3 = Theme.Colors.white,
		Size = UDim2.fromOffset(0, S(20)),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 1,
		ZIndex = 10,
		Parent = rr,
	})
	local plate = Fx.robux(rr, S(16), 10)
	plate.LayoutOrder = 2
	UI.text({
		Text = UI.fmtInt(Config.DailyShopRerollPrice),
		FontFace = Theme.Fonts.display,
		TextSize = S(15),
		TextColor3 = Color3.fromHex("8FE3A1"),
		Size = UDim2.fromOffset(0, S(20)),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 3,
		ZIndex = 10,
		Parent = rr,
	})
	reroll.Activated:Connect(function()
		ctx.buy("daily_reroll", {
			context = "store DAILY reroll",
			onSuccess = function()
				UI.sound(Fx.Sounds.whoosh, 1.3, 0.3)
				ctx.refresh(true) -- loud: the new cards cascade in
			end,
		})
	end)
	local area = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, y + S(46)),
		Size = UDim2.new(1, 0, 1, -(y + S(46))),
		ZIndex = 6,
		Parent = parent,
	})
	local aw, ah = area.AbsoluteSize.X, area.AbsoluteSize.Y
	if aw < 50 then
		aw, ah = S(1000), S(500)
		if ClientState.isMobile and parent.AbsoluteSize.X > 50 then
			aw = parent.AbsoluteSize.X
		end
	end
	local cols = 3
	local gap = S(20)
	local cardW = math.floor(math.min((aw - gap * (cols - 1)) / cols, S(300)) / UI.scale)
	-- Phone: a fixed height (the section grows to fit, FeaturedTab.render), tall enough for the bigger text.
	local cardH = if ClientState.isMobile
		then MOBILE_DAILY_H
		else math.floor(math.min((ah - gap) / 2, S(250)) / UI.scale)
	local grid = UI.frame({ BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 6, Parent = area })
	UI.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(S(cardW), S(cardH)),
		CellPadding = UDim2.fromOffset(gap, gap),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	local cards: { GuiObject } = {}
	for i, e in DailyShop.forDay(day, rerolls) do
		local r = e :: any
		local own = Rewards.owned(profile, r)
		local rarity = Rewards.rarity(r)
		local pid = DailyShop.productId(e)
		local h = Card.new(grid, {
			size = Vector2.new(cardW, cardH),
			art = r,
			artScale = 0.86,
			wellShare = 0.56,
			title = Rewards.name(r),
			sub = string.upper(Rarity.name(rarity)) .. " " .. Rewards.kindLabel(r),
			price = DailyShop.price(e),
			owned = own,
			ribbons = if rarity >= 5 then { "LIMITED" } else {},
			-- Round 21: highest rarity first (draw order breaks ties); owned ones still go to the back.
			layoutOrder = (if own then 1000 else 0) + (10 - rarity) * 20 + i,
			z = 8,
			onClick = function()
				if own then
					return
				end
				ctx.buy(pid, {
					context = "store DAILY " .. pid,
					onSuccess = function(data: any)
						local results = if typeof(data) == "table" and typeof(data.results) == "table"
							then data.results
							else {}
						Reveal.stack(ctx.overlay, results, "NEW ITEM", { mini = true })
					end,
				})
			end,
		})
		table.insert(cards, h.holder)
	end
	if not ctx.quiet then
		Fx.cascade(cards, 0.04)
	end
	return pill
end

------------------------------------------------------------------ The section
function FeaturedTab.render(ctx: any)
	local S = UI.S
	local root = ctx.content :: Frame
	sectionTitle(root, "FEATURED", 0, Theme.Colors.gold)
	local mobile = ClientState.isMobile
	local barH = if mobile then S(MOBILE_BAR_H) else S(230)
	local dailyY = S(44) + barH + S(28)
	if mobile then
		-- The section holds the taller bar and two rows of fixed-height daily cards (StoreScene sized it for PC).
		local rows = math.ceil(Config.DailyShopItems / 3)
		local need = dailyY + S(46) + rows * S(MOBILE_DAILY_H) + (rows - 1) * S(20) + S(12)
		root.Size = UDim2.new(root.Size.X.Scale, root.Size.X.Offset, 0, math.max(root.Size.Y.Offset, need))
	end
	local bundleTimer = bundleBar(ctx, root, S(44), barH)
	local dailyTimer = dailyItems(ctx, root, dailyY)
	if timerConn then
		timerConn:Disconnect()
	end
	local lastSlot = Clock.featuredSlot(ClientState.fakeNow())
	local lastDay = Clock.day(ClientState.fakeNow())
	local lastSec = -1
	timerConn = RunService.Heartbeat:Connect(function()
		if not root.Parent then
			if timerConn then
				timerConn:Disconnect()
				timerConn = nil
			end
			return
		end
		local now = ClientState.fakeNow()
		local sec = math.floor(now)
		if sec == lastSec then
			return
		end
		lastSec = sec
		bundleTimer.Text = "LEAVING IN " .. Clock.hms(Clock.featuredEndsAt(now) - now)
		dailyTimer.Text = "LEAVING IN " .. Clock.hms(Clock.nextDay(now) - now)
		if Clock.featuredSlot(now) ~= lastSlot or Clock.day(now) ~= lastDay then
			lastSlot, lastDay = Clock.featuredSlot(now), Clock.day(now)
			ctx.refresh()
		end
	end)
end

function FeaturedTab.leave(_ctx: any)
	if timerConn then
		timerConn:Disconnect()
		timerConn = nil
	end
end

function FeaturedTab.onProfile(ctx: any)
	local overlay = ctx.overlay :: Frame?
	if overlay and #overlay:GetChildren() > 0 then
		return
	end
	ctx.refresh()
end

return FeaturedTab
