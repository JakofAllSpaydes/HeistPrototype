--!strict
-- Brief 6 VIP tab: the hero card with the perks, the VIP mask and the two VIP poses previewed on the mannequin, and
-- SUBSCRIBE (the purchase sheet with a / month price). Subscribed: `VIP · RENEWS IN 27d`, the daily gift, and a
-- CANCEL link (fake: the perks stop, the cosmetics stay). Lapsed: a WELCOME BACK card.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Clock = require(Shared:WaitForChild("Clock"))

local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local ClientState = require(Client:WaitForChild("ClientState"))
local Fx = require(script.Parent:WaitForChild("Fx"))
local ItemArt = require(script.Parent:WaitForChild("ItemArt"))

local VipTab = {}

local VIP_GOLD = Color3.fromHex("F2C14E")
local previewToken = 0

local PERKS = {
	{ "VIP", "A gold VIP tag on your name tag, party card, scoreboard, summary and callouts" },
	{
		"CSH",
		string.format(
			"A permanent +%d%% CASH boost in every run (stacks with CASH)",
			math.round(Config.VipCashPct * 100)
		),
	},
	{ "GFT", string.format("A daily gift of %d Gold on the hub HUD", Config.VipDailyGold) },
	{ "+", string.format("%d revive tokens every month", Config.VipMonthlyTokens) },
	{ "MSK", "The VIP Gold Trim mask and two VIP poses: yours to keep" },
}

local function vipState(p: any): (boolean, boolean, number)
	local v = p and p.vip
	local active = v ~= nil and v.active == true
	local ever = v ~= nil and v.ever == true
	local renewsIn = if active then (tonumber(v.renewsAt) or 0) - ClientState.fakeNow() else 0
	return active, ever, renewsIn
end

-- The mannequin wears the VIP mask and runs through the two VIP poses.
local function preview(ctx: any)
	previewToken += 1
	local t = previewToken
	ctx.preview.mask("vip_gold")
	task.spawn(function()
		local poses = { "vip_stadium", "vip_tilt" }
		local i = 0
		while previewToken == t and ctx.content and ctx.content.Parent do
			i = i % #poses + 1
			ctx.preview.pose(poses[i])
			task.wait(3.6)
		end
	end)
end

function VipTab.render(ctx: any)
	local S = UI.S
	local root = ctx.content :: Frame
	local profile = ctx.profile()
	local active, ever, renewsIn = vipState(profile)
	preview(ctx)
	local card = UI.frame({
		BackgroundColor3 = Color3.fromHex("141216"),
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = true, -- the rays stay inside the card on the scrolling page
		ZIndex = 6,
		Parent = root,
	})
	UI.corner(card, S(14))
	local stroke = UI.stroke(card, VIP_GOLD, S(2), 0.1)
	UI.new("UIGradient", {
		Color = ColorSequence.new(Color3.fromHex("2A2214"), Color3.fromHex("0E0D10")),
		Rotation = 70,
		Parent = card,
	})
	Fx.rays(card, VIP_GOLD, 10, math.floor(math.max(root.AbsoluteSize.X, S(600)) * 1.1), 6, 6).Position =
		UDim2.fromScale(0.82, 0.2)
	Fx.particles(card, VIP_GOLD, 3, 7)
	task.spawn(function()
		local t0 = os.clock()
		while card.Parent do
			stroke.Transparency = 0.05 + 0.35 * (math.sin((os.clock() - t0) * 2.4) + 1) / 2
			task.wait(0.05)
		end
	end)
	UI.pad(card, S(26), S(22), S(26), S(22))
	local title = UI.text({
		Text = if active then "VIP" elseif ever then "WELCOME BACK" else "BECOME A VIP",
		Font = Theme.Fonts.display,
		TextSize = S(42),
		TextColor3 = VIP_GOLD,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(0.62, 0, 0, S(46)),
		ZIndex = 8,
		Parent = card,
	})
	UI.stroke(title, Color3.new(0, 0, 0), S(2), 0.2)
	UI.text({
		Text = if active
			then string.format("VIP · RENEWS IN %s", Clock.span(renewsIn))
			elseif ever then "Your mask and poses are still yours. Pick the perks back up any time."
			else string.format("R$ %s / month · fake subscription in the prototype", UI.fmtInt(Config.VipPrice)),
		Font = Theme.Fonts.display,
		TextSize = S(15),
		TextColor3 = if active then Color3.fromHex("3FD47A") else Theme.Colors.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Position = UDim2.fromOffset(0, S(48)),
		Size = UDim2.new(0.62, 0, 0, S(40)),
		ZIndex = 8,
		Parent = card,
	})
	-- Perk rows.
	local perks = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, S(96)),
		Size = UDim2.new(0.62, 0, 1, -S(180)),
		ZIndex = 8,
		Parent = card,
	})
	UI.list(perks, Enum.FillDirection.Vertical, S(6))
	local rows: { GuiObject } = {}
	for i, perk in PERKS do
		local row = UI.frame({
			BackgroundColor3 = Color3.fromHex("1E1A14"),
			BackgroundTransparency = 0.2,
			Size = UDim2.new(1, 0, 0, S(38)),
			LayoutOrder = i,
			ZIndex = 8,
			Parent = perks,
		})
		UI.corner(row, S(8))
		local badge = UI.frame({
			BackgroundColor3 = if active then VIP_GOLD else Color3.fromHex("3A3324"),
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, S(6), 0.5, 0),
			Size = UDim2.fromOffset(S(44), S(26)),
			ZIndex = 9,
			Parent = row,
		})
		UI.corner(badge, S(6))
		UI.text({
			Text = perk[1],
			Font = Theme.Fonts.display,
			TextSize = S(13),
			TextColor3 = if active then Theme.Colors.bg else VIP_GOLD,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 10,
			Parent = badge,
		})
		UI.text({
			Text = perk[2],
			Font = Theme.Fonts.body,
			TextSize = S(12),
			TextColor3 = Theme.Colors.text,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			Position = UDim2.fromOffset(S(60), 0),
			Size = UDim2.new(1, -S(66), 1, 0),
			ZIndex = 9,
			Parent = row,
		})
		table.insert(rows, row)
	end
	if not ctx.quiet then
		Fx.cascade(rows, 0.04, 12)
	end
	-- The cosmetics, small, on the right.
	local items = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, S(96)),
		Size = UDim2.new(0.34, 0, 0, S(120)),
		ZIndex = 8,
		Parent = card,
	})
	UI.list(items, Enum.FillDirection.Horizontal, S(8), Enum.HorizontalAlignment.Right)
	for i, r in
		{
			{ kind = "mask", id = "vip_gold" },
			{ kind = "emote", id = "vip_stadium" },
			{ kind = "emote", id = "vip_tilt" },
		}
	do
		local cell = UI.button({
			BackgroundColor3 = Color3.fromHex("221C12"),
			Size = UDim2.fromOffset(S(74), S(96)),
			LayoutOrder = i,
			ZIndex = 9,
			Parent = items,
		})
		UI.corner(cell, S(10))
		UI.stroke(cell, VIP_GOLD, S(1.5), 0.3)
		local a = ItemArt.draw(cell, r, S(60), 10)
		a.AnchorPoint = Vector2.new(0.5, 0)
		a.Position = UDim2.new(0.5, 0, 0, S(6))
		Fx.bob(a, S(2), 2.2)
		UI.text({
			Text = if r.kind == "mask" then "MASK" else "POSE",
			Font = Theme.Fonts.display,
			TextSize = S(11),
			TextColor3 = VIP_GOLD,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -S(6)),
			Size = UDim2.new(1, 0, 0, S(14)),
			ZIndex = 10,
			Parent = cell,
		})
		Fx.interactive(cell)
		cell.Activated:Connect(function()
			if r.kind == "emote" then
				ctx.preview.pose(r.id)
			else
				ctx.preview.mask(r.id)
			end
		end)
	end
	-- Actions along the bottom.
	local actions = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, S(56)),
		ZIndex = 8,
		Parent = card,
	})
	UI.list(actions, Enum.FillDirection.Horizontal, S(14), nil, Enum.VerticalAlignment.Center)
	if not active then
		local sub, _h = Fx.button(
			actions,
			string.format("SUBSCRIBE · R$ %s / MONTH", UI.fmtInt(Config.VipPrice)),
			VIP_GOLD,
			Theme.Colors.bg,
			UDim2.fromOffset(S(330), S(54)),
			9
		)
		sub.TextSize = S(20)
		Fx.shine(sub)
		sub.Activated:Connect(function()
			ctx.buy("vip", {
				context = "store VIP",
				onSuccess = function()
					Fx.burst(
						ctx.gui,
						UDim2.fromOffset(sub.AbsolutePosition.X + sub.AbsoluteSize.X / 2, sub.AbsolutePosition.Y),
						VIP_GOLD,
						26,
						80
					)
					Fx.stinger(5)
				end,
			})
		end)
	else
		local gift = profile and Clock.day(ClientState.fakeNow()) > (tonumber(profile.vipGiftDay) or 0)
		local g, gh = Fx.button(
			actions,
			if gift then string.format("CLAIM DAILY GIFT · ◆ %d", Config.VipDailyGold) else "DAILY GIFT CLAIMED",
			VIP_GOLD,
			Theme.Colors.bg,
			UDim2.fromOffset(S(300), S(52)),
			9
		)
		gh.setEnabled(gift == true)
		g.Activated:Connect(function()
			if not gift then
				return
			end
			local res = ctx.shop("vipGift", {})
			if res.ok then
				ctx.goldBurst(g.AbsolutePosition + g.AbsoluteSize / 2)
				ctx.toast(string.format("+%d GOLD · VIP GIFT", Config.VipDailyGold), VIP_GOLD)
			else
				ctx.toast(tostring(res.reason), Theme.Colors.malus)
			end
		end)
		local cancel = UI.button({
			Text = "Cancel subscription (fake)",
			Font = Theme.Fonts.body,
			TextSize = S(12),
			TextColor3 = Theme.Colors.textDim,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(S(220), S(30)),
			ZIndex = 9,
			Parent = actions,
		})
		cancel.MouseEnter:Connect(function()
			cancel.TextColor3 = Theme.Colors.malus
		end)
		cancel.MouseLeave:Connect(function()
			cancel.TextColor3 = Theme.Colors.textDim
		end)
		cancel.Activated:Connect(function()
			local res = ctx.shop("vipCancel", {})
			if res.ok then
				ctx.toast("VIP cancelled · cosmetics kept", Theme.Colors.grey)
			end
		end)
	end
end

function VipTab.leave(ctx: any)
	previewToken += 1
	ctx.preview.reset()
end

function VipTab.badge(profile: any): boolean
	local active, ever = vipState(profile)
	if active then
		return Clock.day(ClientState.fakeNow()) > (tonumber(profile.vipGiftDay) or 0)
	end
	return ever
end

function VipTab.onProfile(ctx: any)
	ctx.refresh()
end

return VipTab
