--!strict
-- Brief 6 BOOSTS tab: POWER, CASH and LUCKY (BoostDefs.lua), each a card with its durations as a segmented control
-- and one BUY button (EXTEND while it runs, with the time left on the card), and the revive token packs along the
-- bottom row (ReviveTokenPacks.lua). Boosts run on a real-time clock from purchase and touch runs only.
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local BoostDefs = require(Shared:WaitForChild("BoostDefs"))
local ReviveTokenPacks = require(Shared:WaitForChild("ReviveTokenPacks"))
local Clock = require(Shared:WaitForChild("Clock"))

local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local ClientState = require(Client:WaitForChild("ClientState"))
local Fx = require(script.Parent:WaitForChild("Fx"))
local Card = require(script.Parent:WaitForChild("Card"))

local BoostsTab = {}

local chosen: { [string]: number } = {} -- boost id -> selected duration index
local timerConn: RBXScriptConnection? = nil

local function remaining(profile: any, id: string): number
	local b = profile and profile.boosts and profile.boosts[id]
	return if b then (tonumber(b.expiresAt) or 0) - ClientState.osNow() else 0
end

function BoostsTab.render(ctx: any)
	local S = UI.S
	local root = ctx.content :: Frame
	UI.text({
		Text = "BOOSTS",
		FontFace = Theme.Fonts.display,
		TextSize = S(26),
		TextColor3 = Theme.Colors.gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, S(30)),
		ZIndex = 6,
		Parent = root,
	})
	local blurb = UI.text({
		Text = "Real-time from purchase · in-run only · Gold, XP, pass XP and paid crates are never boosted",
		FontFace = Theme.Fonts.body,
		TextSize = S(13),
		TextColor3 = Theme.Colors.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(0, S(30)),
		Size = UDim2.new(1, 0, 0, if ctx.mobile then S(22) else S(16)),
		ZIndex = 6,
		Parent = root,
	})
	if ctx.mobile then
		Card.fitText(blurb) -- phone pass: one line that fits the width instead of running off the page
	end
	local profile = ctx.profile()
	local area = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, S(54)),
		Size = UDim2.new(1, 0, 1, -S(54)),
		ZIndex = 6,
		Parent = root,
	})
	local aw, ah = area.AbsoluteSize.X, area.AbsoluteSize.Y
	if aw < 50 then
		aw, ah = S(760), S(560)
	end
	local topH = math.floor((ah - S(20)) * 0.64)
	local top = UI.frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, topH), ZIndex = 6, Parent = area })
	UI.list(top, Enum.FillDirection.Horizontal, S(18), Enum.HorizontalAlignment.Center)
	local cardW = math.floor(math.min((aw - S(36)) / 3, S(240)) / UI.scale)
	local cards: { GuiObject } = {}
	local timers: { [string]: TextLabel } = {}
	for i, def in BoostDefs.List do
		local color = Color3.fromHex(def.color)
		local left = remaining(profile, def.id)
		local active = left > 0
		local idx = chosen[def.id] or 1
		local handle = Card.new(top, {
			size = Vector2.new(cardW, math.floor(topH / UI.scale)),
			art = { kind = "boost", id = def.id, sec = def.durations[idx].sec },
			artScale = 0.62,
			wellShare = if ctx.mobile then 0.3 else 0.38,
			rarity = if def.id == "lucky" then 4 elseif def.id == "power" then 3 else 2,
			title = def.name,
			sub = def.desc,
			ribbons = if active then { "ACTIVE" } else {},
			hero = active,
			layoutOrder = i,
			z = 7,
		})
		local content = handle.content
		UI.list(content, Enum.FillDirection.Vertical, S(6), Enum.HorizontalAlignment.Center)
		local status = UI.text({
			Text = "",
			FontFace = Theme.Fonts.display,
			TextSize = S(14),
			TextColor3 = if active then Color3.fromHex("3FD47A") else Theme.Colors.grey,
			Size = UDim2.new(1, 0, 0, S(18)),
			LayoutOrder = 1,
			ZIndex = 9,
			Parent = content,
		})
		status.Text = if active then "ACTIVE · " .. Clock.timer(left) else "NOT ACTIVE"
		if active then
			timers[def.id] = status
		end
		-- Segmented control: one segment per duration.
		local seg = UI.frame({
			BackgroundColor3 = Color3.fromHex("0E0E12"),
			Size = UDim2.new(1, 0, 0, S(34)),
			LayoutOrder = 2,
			ZIndex = 9,
			Parent = content,
		})
		UI.corner(seg, S(8))
		UI.stroke(seg, color, S(1), 0.5)
		UI.list(seg, Enum.FillDirection.Horizontal, 0)
		for k, d in def.durations do
			local on = k == idx
			local b = UI.button({
				Text = d.label,
				FontFace = Theme.Fonts.display,
				TextSize = S(13),
				TextColor3 = if on then Theme.Colors.bg else Theme.Colors.textDim,
				BackgroundColor3 = color,
				BackgroundTransparency = if on then 0 else 1,
				Size = UDim2.new(1 / #def.durations, 0, 1, 0),
				LayoutOrder = k,
				ZIndex = 10,
				Parent = seg,
			})
			UI.corner(b, S(8))
			b.Activated:Connect(function()
				if chosen[def.id] ~= k then
					chosen[def.id] = k
					UI.sound(Fx.Sounds.tab, 1.5, 0.25)
					ctx.refresh()
				end
			end)
		end
		local d = def.durations[idx]
		local buy, _h = Fx.button(
			content,
			string.format("%s · R$ %s", if active then "EXTEND" else "BUY", UI.fmtInt(d.price)),
			if active then Color3.fromHex("4D9FE8") else Color3.fromHex("2FB75A"),
			Theme.Colors.white,
			UDim2.new(1, 0, 0, S(42)),
			10
		)
		buy.LayoutOrder = 3
		if ctx.mobile then
			Card.fitText(buy) -- EXTEND · R$ 1,234 ran past the card's edges on a phone
		end
		buy.Activated:Connect(function()
			ctx.buy(BoostDefs.productId(def.id, d.id), {
				context = "store BOOSTS",
				onSuccess = function()
					Fx.burst(
						ctx.gui,
						UDim2.fromOffset(buy.AbsolutePosition.X + buy.AbsoluteSize.X / 2, buy.AbsolutePosition.Y),
						color,
						16,
						80
					)
				end,
			})
		end)
		table.insert(cards, handle.holder)
	end

	-- Bottom row: revive token packs.
	local bottomY = topH + S(16)
	local have = if profile and typeof(profile.reviveTokens) == "number" then profile.reviveTokens else 0
	local tokenTitle = UI.text({
		Text = string.format("REVIVE TOKENS · OWNED: %d", have),
		FontFace = Theme.Fonts.display,
		TextSize = S(24),
		TextColor3 = Color3.fromHex("3FD47A"),
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(0, bottomY),
		Size = UDim2.new(1, 0, 0, S(28)),
		ZIndex = 7,
		Parent = area,
	})
	UI.stroke(tokenTitle, Color3.new(0, 0, 0), S(1.5), 0.3)
	local bottom = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, bottomY + S(36)),
		Size = UDim2.new(1, 0, 1, -(bottomY + S(36))),
		ZIndex = 6,
		Parent = area,
	})
	UI.list(bottom, Enum.FillDirection.Horizontal, S(14), Enum.HorizontalAlignment.Center)
	local packW = math.floor(math.min((aw - S(28)) / 3, S(240)) / UI.scale)
	local packH = math.floor(math.max(S(120), ah - bottomY - S(40)) / UI.scale)
	for i, pack in ReviveTokenPacks.List do
		local h = Card.new(bottom, {
			size = Vector2.new(packW, math.min(packH, 190)),
			art = { kind = "tokens", amount = pack.tokens },
			artScale = 0.9,
			wellShare = 0.44,
			title = string.format("%d TOKENS", pack.tokens),
			price = pack.price,
			ribbons = if pack.tag then { pack.tag } else {},
			layoutOrder = i,
			z = 7,
			onClick = function()
				ctx.buy(pack.id, { context = "store BOOSTS tokens" })
			end,
		})
		table.insert(cards, h.holder)
	end
	if not ctx.quiet then
		Fx.cascade(cards, 0.04)
	end
	-- Live timers on the active cards.
	if timerConn then
		timerConn:Disconnect()
	end
	local lastSec = -1
	timerConn = RunService.Heartbeat:Connect(function()
		if not root.Parent then
			return
		end
		local sec = math.floor(os.clock())
		if sec == lastSec then
			return
		end
		lastSec = sec
		local p = ctx.profile()
		for id, label in timers do
			local l = remaining(p, id)
			if l <= 0 then
				ctx.refresh()
				return
			end
			label.Text = "ACTIVE · " .. Clock.timer(l)
		end
	end)
end

function BoostsTab.leave(_ctx: any)
	if timerConn then
		timerConn:Disconnect()
		timerConn = nil
	end
end

function BoostsTab.onProfile(ctx: any)
	ctx.refresh()
end

return BoostsTab
