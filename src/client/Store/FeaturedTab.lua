--!strict
-- Brief 6 FEATURED tab: three hero bundle cards in a row (Bundles.lua) under a `ROTATES IN 2d 14h` timer (the fake
-- clock, Config.FeaturedRotationSec), each with a LIMITED ribbon and the -X% from list vs bundle price. Tapping a
-- card opens the detail sheet: every item with its art and rarity, owned ones struck through and their list share
-- taken off the price (Config.BundleOwnedDiscount). Buying grants everything in one write and plays the stacked
-- reveal before returning to the tab. Hovering / selecting a bundle previews its cosmetics on the mannequin.
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Bundles = require(Shared:WaitForChild("Bundles"))
local Rewards = require(Shared:WaitForChild("Rewards"))
local Clock = require(Shared:WaitForChild("Clock"))

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

-- The rotation: the three bundles in an order that turns with each slot.
local function rotation(): { Bundles.Bundle }
	local slot = Clock.featuredSlot(ClientState.fakeNow())
	local list = Bundles.List
	local out = {}
	for i = 1, #list do
		out[i] = list[((i - 1 + slot) % #list) + 1]
	end
	return out
end

-- Show the bundle's cosmetics on the mannequin: a mask, a pose, the class idle.
local function preview(ctx: any, b: Bundles.Bundle)
	ctx.preview.reset()
	for _, c in b.contents do
		if c.kind == "mask" and c.id then
			ctx.preview.mask(c.id)
		elseif c.kind == "class" and c.id then
			ctx.preview.idle(c.id)
		elseif c.kind == "wrap" and c.id then
			ctx.preview.wrap(c.id)
		end
	end
	for _, c in b.contents do
		if c.kind == "emote" and c.id then
			ctx.preview.pose(c.id)
			break
		end
	end
end

local function ownedCount(b: Bundles.Bundle, profile: any): number
	local _, owned = Bundles.priceFor(b, profile)
	local n = 0
	for _, o in owned do
		if o then
			n += 1
		end
	end
	return n
end

------------------------------------------------------------------ Detail sheet
local function detail(ctx: any, b: Bundles.Bundle)
	local S = UI.S
	local layer = ctx.overlay :: Frame
	for _, c in layer:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	preview(ctx, b)
	local dim = UI.button({
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 31,
		Parent = layer,
	})
	UI.tween(dim, { BackgroundTransparency = 0.45 }, 0.15)
	local profile = ctx.profile()
	local price, owned = Bundles.priceFor(b, profile)
	local list = Bundles.listPrice(b)
	local color = Color3.fromHex(b.color)
	local w = math.min(S(560), math.floor(ctx.gui.AbsoluteSize.X * 0.62))
	local sheet = UI.frame({
		BackgroundColor3 = Color3.fromHex("15151A"),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.54),
		Size = UDim2.fromOffset(w, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Active = true,
		ZIndex = 32,
		Parent = layer,
	})
	UI.corner(sheet, S(14))
	UI.stroke(sheet, color, S(2), 0.2)
	UI.pad(sheet, S(18), S(16), S(18), S(18))
	UI.list(sheet, Enum.FillDirection.Vertical, S(8))
	Fx.slideIn(sheet, UDim2.fromOffset(0, S(40)), 0.25)
	local head = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, S(56)),
		LayoutOrder = 0,
		ZIndex = 33,
		Parent = sheet,
	})
	UI.text({
		Text = b.name,
		Font = Theme.Fonts.display,
		TextSize = S(28),
		TextColor3 = Theme.Colors.white,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -S(50), 0, S(32)),
		ZIndex = 34,
		Parent = head,
	})
	UI.text({
		Text = b.tagline,
		Font = Theme.Fonts.body,
		TextSize = S(11),
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(0, S(34)),
		Size = UDim2.new(1, -S(50), 0, S(16)),
		ZIndex = 34,
		Parent = head,
	})
	local x = UI.button({
		Text = "X",
		Font = Theme.Fonts.display,
		TextSize = S(16),
		TextColor3 = Theme.Colors.white,
		BackgroundColor3 = Color3.fromHex("2E3135"),
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(S(34), S(34)),
		Position = UDim2.new(1, 0, 0, 0),
		ZIndex = 34,
		Parent = head,
	})
	UI.corner(x, S(17))
	Fx.interactive(x)
	local function close()
		ctx.preview.reset()
		for _, c in layer:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
	end
	x.Activated:Connect(close)
	dim.Activated:Connect(close)

	local rows: { GuiObject } = {}
	for i, c in b.contents do
		local isOwned = owned[i] == true
		local r = c :: any
		local rarity = Rewards.rarity(r)
		local rc = Fx.rarityColor(rarity)
		local row = UI.frame({
			BackgroundColor3 = Color3.fromHex("1E1E25"),
			Size = UDim2.new(1, 0, 0, S(54)),
			LayoutOrder = i,
			ZIndex = 33,
			Parent = sheet,
		})
		UI.corner(row, S(8))
		UI.frame({
			BackgroundColor3 = rc,
			Size = UDim2.new(0, S(4), 1, -S(12)),
			Position = UDim2.fromOffset(S(5), S(6)),
			ZIndex = 34,
			Parent = row,
		})
		local art = ItemArt.draw(row, r, S(44), 35)
		art.AnchorPoint = Vector2.new(0, 0.5)
		art.Position = UDim2.new(0, S(16), 0.5, 0)
		local name = UI.text({
			Text = Rewards.name(r),
			Font = Theme.Fonts.display,
			TextSize = S(16),
			TextColor3 = if isOwned then Theme.Colors.grey else Theme.Colors.white,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(S(70), S(6)),
			Size = UDim2.new(1, -S(170), 0, S(22)),
			ZIndex = 35,
			Parent = row,
		})
		UI.text({
			Text = Rewards.kindLabel(r) .. " · " .. string.upper(require(Shared:WaitForChild("Rarity")).name(rarity)),
			Font = Theme.Fonts.body,
			TextSize = S(10),
			TextColor3 = if isOwned then Theme.Colors.grey else rc,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(S(70), S(29)),
			Size = UDim2.new(1, -S(170), 0, S(16)),
			ZIndex = 35,
			Parent = row,
		})
		UI.text({
			Text = if isOwned then "OWNED" else "R$ " .. UI.fmtInt(c.value),
			Font = Theme.Fonts.display,
			TextSize = S(13),
			TextColor3 = if isOwned then Theme.Colors.grey else Theme.Colors.textDim,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -S(12), 0.5, 0),
			Size = UDim2.fromOffset(S(90), S(20)),
			ZIndex = 35,
			Parent = row,
		})
		if isOwned then
			-- Struck through.
			local strike = UI.frame({
				BackgroundColor3 = Theme.Colors.grey,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, S(66), 0.5, 0),
				Size = UDim2.new(1, -S(80), 0, S(2)),
				ZIndex = 36,
				Parent = row,
			})
			local _ = strike
			row.BackgroundTransparency = 0.5
			local _2 = name
		end
		table.insert(rows, row)
	end
	Fx.cascade(rows, 0.03, 12)

	-- Price line and BUY.
	local priceRow = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, S(34)),
		LayoutOrder = 50,
		ZIndex = 33,
		Parent = sheet,
	})
	UI.text({
		Text = "R$ " .. UI.fmtInt(list),
		Font = Theme.Fonts.display,
		TextSize = S(16),
		TextColor3 = Theme.Colors.grey,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.fromOffset(S(110), S(34)),
		ZIndex = 34,
		Parent = priceRow,
	})
	UI.frame({
		BackgroundColor3 = Theme.Colors.grey,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(S(80), S(2)),
		ZIndex = 35,
		Parent = priceRow,
	})
	local nOwned = ownedCount(b, profile)
	UI.text({
		Text = if nOwned > 0
			then string.format("%d OWNED · PRICE REDUCED · -%d%%", nOwned, math.floor((1 - price / list) * 100 + 0.5))
			else string.format("-%d%% VS BUYING SEPARATELY", Bundles.discountPct(b)),
		Font = Theme.Fonts.display,
		TextSize = S(13),
		TextColor3 = Color3.fromHex("FF8A5C"),
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(1, -S(110), 1, 0),
		ZIndex = 34,
		Parent = priceRow,
	})
	local allOwned = nOwned >= #b.contents
	local buy, handle = Fx.button(
		sheet,
		if allOwned then "ALL OWNED" else "BUY · R$ " .. UI.fmtInt(price),
		Color3.fromHex("2FB75A"),
		Theme.Colors.white,
		UDim2.new(1, 0, 0, S(52)),
		34
	)
	buy.TextSize = S(22)
	buy.LayoutOrder = 51
	handle.setEnabled(not allOwned)
	buy.Activated:Connect(function()
		if allOwned then
			return
		end
		ctx.buy(b.id, {
			context = "store FEATURED " .. b.id,
			onSuccess = function(data: any)
				close()
				local results = if typeof(data) == "table" and typeof(data.results) == "table" then data.results else {}
				Reveal.stack(ctx.overlay, results, b.name .. " UNLOCKED", {
					onDone = function()
						ctx.refresh()
					end,
				})
				local gotGold = false
				for _, res in results do
					if res.kind == "gold" and not res.skipped then
						gotGold = true
					end
				end
				if gotGold then
					task.delay(0.6, function()
						ctx.goldBurst(nil)
					end)
				end
			end,
		})
	end)
end

------------------------------------------------------------------ The tab
function FeaturedTab.render(ctx: any)
	local S = UI.S
	local root = ctx.content :: Frame
	local top = UI.frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, S(40)), ZIndex = 6, Parent = root })
	UI.text({
		Text = "FEATURED",
		Font = Theme.Fonts.display,
		TextSize = S(26),
		TextColor3 = Theme.Colors.gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(0.5, 0, 1, 0),
		ZIndex = 7,
		Parent = top,
	})
	local timerPill = UI.frame({
		BackgroundColor3 = Color3.fromHex("2A1A1A"),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(S(200), S(30)),
		ZIndex = 7,
		Parent = top,
	})
	UI.corner(timerPill, S(15))
	UI.stroke(timerPill, Theme.Colors.red, S(1.5), 0.2)
	local timer = UI.text({
		Text = "",
		Font = Theme.Fonts.display,
		TextSize = S(14),
		TextColor3 = Color3.fromHex("FF9A8C"),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 8,
		Parent = timerPill,
	})
	if timerConn then
		timerConn:Disconnect()
	end
	local lastSlot = Clock.featuredSlot(ClientState.fakeNow())
	local lastShown = ""
	timerConn = RunService.Heartbeat:Connect(function()
		if not timer.Parent then
			if timerConn then
				timerConn:Disconnect()
				timerConn = nil
			end
			return
		end
		local now = ClientState.fakeNow()
		local text = "ROTATES IN " .. Clock.span(Clock.featuredEndsAt(now) - now)
		if text ~= lastShown then
			lastShown = text
			timer.Text = text
		end
		if Clock.featuredSlot(now) ~= lastSlot then
			lastSlot = Clock.featuredSlot(now)
			ctx.refresh()
		end
	end)

	local row = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, S(52)),
		Size = UDim2.new(1, 0, 1, -S(52)),
		ZIndex = 6,
		Parent = root,
	})
	UI.list(row, Enum.FillDirection.Horizontal, S(18), Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	local aw, ah = row.AbsoluteSize.X, row.AbsoluteSize.Y
	if aw < 50 then
		aw, ah = S(760), S(560)
	end
	local cardW = math.floor(math.min((aw - S(36)) / 3, S(250)) / UI.scale)
	local cardH = math.floor(math.min(ah - S(16), S(440)) / UI.scale)
	local profile = ctx.profile()
	local cards: { GuiObject } = {}
	for i, b in rotation() do
		local price = Bundles.priceFor(b, profile)
		local nOwned = ownedCount(b, profile)
		local ribbons = { "LIMITED", "-" .. Bundles.discountPct(b) .. "%" }
		local handle = Card.new(row, {
			size = Vector2.new(cardW, cardH),
			art = b.hero :: any,
			artScale = 0.7,
			rarity = math.max(4, Rewards.rarity(b.hero :: any)),
			title = b.name,
			sub = b.tagline,
			price = price,
			ribbons = ribbons,
			owned = nOwned >= #b.contents,
			hero = true,
			layoutOrder = i,
			z = 7,
			onClick = function()
				detail(ctx, b)
			end,
		})
		-- The contents strip inside the card: every item small, owned ones dimmed; the list price struck.
		local strip = UI.frame({
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, S(34)),
			ZIndex = 9,
			Parent = handle.content,
		})
		UI.list(strip, Enum.FillDirection.Horizontal, S(3), Enum.HorizontalAlignment.Center)
		local _, ownedList = Bundles.priceFor(b, profile)
		for j, c in b.contents do
			local cell = UI.frame({
				BackgroundColor3 = Fx.shade(Fx.rarityColor(Rewards.rarity(c :: any)), -0.6),
				Size = UDim2.fromOffset(S(30), S(30)),
				LayoutOrder = j,
				ZIndex = 9,
				Parent = strip,
			})
			UI.corner(cell, S(5))
			local a = ItemArt.draw(cell, c :: any, S(26), 10)
			a.AnchorPoint = Vector2.new(0.5, 0.5)
			a.Position = UDim2.fromScale(0.5, 0.5)
			if ownedList[j] then
				cell.BackgroundTransparency = 0.7
				for _, d in a:GetDescendants() do
					if d:IsA("Frame") then
						d.BackgroundTransparency = 0.6
					end
				end
			end
		end
		UI.text({
			Text = string.format(
				"%d ITEMS · WORTH R$ %s%s",
				#b.contents,
				UI.fmtInt(Bundles.listPrice(b)),
				if nOwned > 0 then string.format(" · %d OWNED", nOwned) else ""
			),
			Font = Theme.Fonts.body,
			TextSize = S(10),
			TextColor3 = if nOwned > 0 then Color3.fromHex("FF8A5C") else Theme.Colors.textDim,
			Position = UDim2.fromOffset(0, S(38)),
			Size = UDim2.new(1, 0, 0, S(14)),
			ZIndex = 9,
			Parent = handle.content,
		})
		handle.body.MouseEnter:Connect(function()
			preview(ctx, b)
		end)
		table.insert(cards, handle.holder)
	end
	if not ctx.quiet then
		Fx.cascade(cards, 0.04)
	end
	-- Deep link (VIEW BUNDLE): open that bundle's sheet.
	local arg = ctx.arg
	if typeof(arg) == "table" and arg.bundle and Bundles.ById[arg.bundle] and not ctx.quiet then
		task.delay(0.3, function()
			detail(ctx, Bundles.ById[arg.bundle])
		end)
	end
end

function FeaturedTab.leave(_ctx: any)
	if timerConn then
		timerConn:Disconnect()
		timerConn = nil
	end
end

function FeaturedTab.onProfile(ctx: any)
	-- Prices and owned marks follow the profile; an open detail sheet stays as it is.
	local overlay = ctx.overlay :: Frame?
	if overlay and #overlay:GetChildren() > 0 then
		return
	end
	ctx.refresh()
end

return FeaturedTab
