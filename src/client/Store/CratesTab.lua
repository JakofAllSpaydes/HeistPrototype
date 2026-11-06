--!strict
-- Brief 6 CRATES tab: the ARMS CRATE and the MASK CRATE (Crates.lua). Each card: the crate on a pedestal with an
-- idle bob, its name, a contents strip (every item, dimmed if owned), ODDS (the odds panel: rarity rows with
-- percentages and the exact items, from the same table the server rolls), the pity line `EPIC+ GUARANTEED IN 7`
-- (Config.CratePity and the player's counter) and OPEN 1 / OPEN 3 / OPEN 10 with prices. Buying any amount cuts
-- straight to the opening scene; banked free opens (bundles, the pass) open from their own button.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Crates = require(Shared:WaitForChild("Crates"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Rewards = require(Shared:WaitForChild("Rewards"))

local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local Fx = require(script.Parent:WaitForChild("Fx"))
local Card = require(script.Parent:WaitForChild("Card"))
local ItemArt = require(script.Parent:WaitForChild("ItemArt"))

local CratesTab = {}

local function crateScene(): any
	return require(script.Parent:WaitForChild("CrateScene") :: ModuleScript)
end

local function pityLeft(profile: any, crateId: string): number
	local since = if profile and profile.cratePity then tonumber(profile.cratePity[crateId]) or 0 else 0
	return math.max(1, Config.CratePity - since)
end

local function freeOpens(profile: any, crateId: string): number
	return if profile and profile.crateOpens then tonumber(profile.crateOpens[crateId]) or 0 else 0
end

------------------------------------------------------------------ Odds panel
local function oddsPanel(ctx: any, crate: Crates.Crate)
	local S = UI.S
	local layer = ctx.overlay :: Frame
	for _, c in layer:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local dim = UI.button({
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 31,
		Parent = layer,
	})
	local panel = UI.frame({
		BackgroundColor3 = Color3.fromHex("15151A"),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.fromOffset(S(520), 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Active = true,
		ZIndex = 32,
		Parent = layer,
	})
	UI.corner(panel, S(14))
	UI.stroke(panel, Color3.fromHex(crate.trim), S(2), 0.2)
	UI.pad(panel, S(18), S(16), S(18), S(16))
	UI.list(panel, Enum.FillDirection.Vertical, S(6))
	local sc = UI.new("UIScale", { Scale = 0.9, Parent = panel })
	UI.tween(sc, { Scale = 1 }, 0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	UI.text({
		Text = crate.name .. " · ODDS",
		Font = Theme.Fonts.display,
		TextSize = S(24),
		TextColor3 = Theme.Colors.white,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, S(30)),
		LayoutOrder = 0,
		ZIndex = 33,
		Parent = panel,
	})
	local odds = Crates.odds(crate, 1)
	for r = 5, 1, -1 do
		local items = Crates.itemsAt(crate, r)
		local color = Rarity.color(r)
		local row = UI.frame({
			BackgroundColor3 = Color3.fromHex("1E1E25"),
			Size = UDim2.new(1, 0, 0, S(44)),
			LayoutOrder = 10 - r,
			ZIndex = 33,
			Parent = panel,
		})
		UI.corner(row, S(8))
		UI.frame({
			BackgroundColor3 = color,
			Size = UDim2.new(0, S(5), 1, -S(10)),
			Position = UDim2.fromOffset(S(6), S(5)),
			ZIndex = 34,
			Parent = row,
		})
		UI.text({
			Text = string.upper(Rarity.name(r)),
			Font = Theme.Fonts.display,
			TextSize = S(15),
			TextColor3 = color,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(S(18), 0),
			Size = UDim2.new(0, S(110), 1, 0),
			ZIndex = 34,
			Parent = row,
		})
		local names = {}
		for _, id in items do
			table.insert(names, Crates.itemName(crate, id))
		end
		UI.text({
			Text = if #names > 0 then table.concat(names, " · ") else "—",
			Font = Theme.Fonts.body,
			TextSize = S(11),
			TextColor3 = Theme.Colors.text,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			Position = UDim2.fromOffset(S(130), 0),
			Size = UDim2.new(1, -S(220), 1, 0),
			ZIndex = 34,
			Parent = row,
		})
		UI.text({
			Text = string.format("%.1f%%", odds[r] * 100),
			Font = Theme.Fonts.display,
			TextSize = S(18),
			TextColor3 = Theme.Colors.white,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -S(12), 0, 0),
			Size = UDim2.new(0, S(80), 1, 0),
			ZIndex = 34,
			Parent = row,
		})
	end
	UI.text({
		Text = string.format(
			"Each item is equally likely inside its rarity. Epic or better is guaranteed on the %dth open since your last one; owned items convert to Gold and mastery XP.",
			Config.CratePity
		),
		Font = Theme.Fonts.body,
		TextSize = S(10),
		TextColor3 = Theme.Colors.textDim,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, S(30)),
		LayoutOrder = 20,
		ZIndex = 33,
		Parent = panel,
	})
	UI.text({
		Text = "[Legal copy: TBA]",
		Font = Theme.Fonts.body,
		TextSize = S(10),
		TextColor3 = Theme.Colors.grey,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, S(14)),
		LayoutOrder = 21,
		ZIndex = 33,
		Parent = panel,
	})
	local close, _ =
		Fx.button(panel, "CLOSE", Color3.fromHex("2E3135"), Theme.Colors.white, UDim2.new(1, 0, 0, S(44)), 34)
	close.LayoutOrder = 30
	local function shut()
		for _, c in layer:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
	end
	close.Activated:Connect(shut)
	dim.Activated:Connect(shut)
end

------------------------------------------------------------------ The tab
local function openWith(ctx: any, crate: Crates.Crate, n: number)
	local pid = Crates.productId(crate.id, n)
	ctx.buy(pid, {
		context = "store CRATES " .. pid,
		onSuccess = function(data: any)
			if typeof(data) == "table" and typeof(data.results) == "table" then
				crateScene().play(crate.id, data.results, pid)
			end
		end,
	})
end

local function openFree(ctx: any, crate: Crates.Crate, have: number)
	local res = ctx.shop("openCredits", { crateId = crate.id, count = math.min(have, 10) })
	if res.ok and typeof(res.data) == "table" then
		crateScene().play(crate.id, res.data.results, nil)
	else
		ctx.toast(tostring(res.reason or "Could not open"), Theme.Colors.malus)
	end
end

function CratesTab.render(ctx: any)
	local S = UI.S
	local root = ctx.content :: Frame
	UI.text({
		Text = "CRATES",
		Font = Theme.Fonts.display,
		TextSize = S(26),
		TextColor3 = Theme.Colors.gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, S(30)),
		ZIndex = 6,
		Parent = root,
	})
	UI.text({
		Text = "Every item inside is crate-only. Results land in your Armory and Locker the moment they roll.",
		Font = Theme.Fonts.body,
		TextSize = S(11),
		TextColor3 = Theme.Colors.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(0, S(30)),
		Size = UDim2.new(1, 0, 0, S(16)),
		ZIndex = 6,
		Parent = root,
	})
	local row = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, S(56)),
		Size = UDim2.new(1, 0, 1, -S(56)),
		ZIndex = 6,
		Parent = root,
	})
	UI.list(row, Enum.FillDirection.Horizontal, S(20), Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	local aw, ah = row.AbsoluteSize.X, row.AbsoluteSize.Y
	if aw < 50 then
		aw, ah = S(760), S(560)
	end
	local cardW = math.floor(math.min((aw - S(20)) / 2, S(380)) / UI.scale)
	local cardH = math.floor(math.min(ah - S(10), S(560)) / UI.scale)
	local profile = ctx.profile()
	local cards: { GuiObject } = {}
	local arg = ctx.arg
	for i, crate in Crates.List do
		local focus = typeof(arg) == "table" and arg.crate == crate.id
		local handle = Card.new(row, {
			size = Vector2.new(cardW, cardH),
			art = { kind = "crate", id = crate.id, amount = 1 },
			artScale = 0.8,
			wellShare = 0.4,
			rarity = if crate.id == "arms" then 5 else 4,
			title = crate.name,
			sub = crate.tagline,
			hero = focus,
			layoutOrder = i,
			z = 7,
		})
		local content = handle.content
		UI.list(content, Enum.FillDirection.Vertical, S(6), Enum.HorizontalAlignment.Center)
		-- Contents strip: every item, owned ones dimmed.
		local strip = UI.frame({
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, S(40)),
			LayoutOrder = 1,
			ZIndex = 9,
			Parent = content,
		})
		UI.list(strip, Enum.FillDirection.Horizontal, S(3), Enum.HorizontalAlignment.Center)
		local cell = math.floor((cardW - 40) / #crate.pool)
		for j, id in crate.pool do
			local r = { kind = crate.kind, id = id }
			local rar = Crates.itemRarity(crate, id)
			local owned = Rewards.owned(profile, r)
			local box = UI.frame({
				BackgroundColor3 = Fx.shade(Rarity.color(rar), -0.55),
				Size = UDim2.fromOffset(S(cell), S(cell)),
				LayoutOrder = j,
				ZIndex = 9,
				Parent = strip,
			})
			UI.corner(box, S(5))
			UI.stroke(box, Rarity.color(rar), S(1), if owned then 0.7 else 0.1)
			local a = ItemArt.draw(box, r, S(cell - 4), 10)
			a.AnchorPoint = Vector2.new(0.5, 0.5)
			a.Position = UDim2.fromScale(0.5, 0.5)
			if owned then
				box.BackgroundTransparency = 0.7
				for _, d in a:GetDescendants() do
					if d:IsA("Frame") then
						d.BackgroundTransparency = 0.65
					end
				end
			end
		end
		-- Pity line and ODDS.
		local mid = UI.frame({
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, S(30)),
			LayoutOrder = 2,
			ZIndex = 9,
			Parent = content,
		})
		local left = pityLeft(profile, crate.id)
		UI.text({
			Text = string.format("EPIC+ GUARANTEED IN %d", left),
			Font = Theme.Fonts.display,
			TextSize = S(14),
			TextColor3 = if left <= 2 then Rarity.color(4) else Theme.Colors.text,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -S(80), 1, 0),
			ZIndex = 10,
			Parent = mid,
		})
		local odds, _oh =
			Fx.button(mid, "ODDS", Color3.fromHex("2E3135"), Theme.Colors.white, UDim2.fromOffset(S(72), S(28)), 10)
		odds.AnchorPoint = Vector2.new(1, 0.5)
		odds.Position = UDim2.new(1, 0, 0.5, 0)
		odds.TextSize = S(14)
		odds.Activated:Connect(function()
			oddsPanel(ctx, crate)
		end)
		-- OPEN 1 / OPEN 3 / OPEN 10 (or the banked free opens first).
		local have = freeOpens(profile, crate.id)
		if have > 0 then
			local free, _fh = Fx.button(
				content,
				string.format("OPEN FREE ×%d", math.min(have, 10)),
				Theme.Colors.gold,
				Theme.Colors.bg,
				UDim2.new(1, 0, 0, S(40)),
				10
			)
			free.LayoutOrder = 3
			free.TextSize = S(17)
			UI.text({
				Text = string.format("%d BANKED", have),
				Font = Theme.Fonts.body,
				TextSize = S(9),
				TextColor3 = Theme.Colors.bg,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -S(8), 0.5, 0),
				Size = UDim2.fromOffset(S(70), S(12)),
				ZIndex = 12,
				Parent = free,
			})
			free.Activated:Connect(function()
				openFree(ctx, crate, have)
			end)
		end
		local buttons = UI.frame({
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, S(56)),
			LayoutOrder = 4,
			ZIndex = 9,
			Parent = content,
		})
		UI.list(buttons, Enum.FillDirection.Horizontal, S(6), Enum.HorizontalAlignment.Center)
		for k, n in Crates.Counts do
			local b, _bh = Fx.button(
				buttons,
				"",
				if n == 10
					then Color3.fromHex("A864E8")
					elseif n == 3 then Color3.fromHex("4D9FE8")
					else Color3.fromHex("2FB75A"),
				Theme.Colors.white,
				UDim2.new(1 / #Crates.Counts, -S(4), 1, 0),
				10
			)
			b.LayoutOrder = k
			UI.text({
				Text = "OPEN " .. n,
				Font = Theme.Fonts.display,
				TextSize = S(16),
				TextColor3 = Theme.Colors.white,
				Position = UDim2.fromOffset(0, S(6)),
				Size = UDim2.new(1, 0, 0, S(20)),
				ZIndex = 12,
				Parent = b,
			})
			UI.text({
				Text = "R$ " .. UI.fmtInt(crate.prices[n]),
				Font = Theme.Fonts.body,
				TextSize = S(12),
				TextColor3 = Theme.Colors.white,
				Position = UDim2.fromOffset(0, S(28)),
				Size = UDim2.new(1, 0, 0, S(18)),
				ZIndex = 12,
				Parent = b,
			})
			if n == 10 then
				Fx.shine(b)
			end
			b.Activated:Connect(function()
				openWith(ctx, crate, n)
			end)
		end
		if focus then
			task.delay(0.3, function()
				UI.punch(handle.holder, 1.06, 0.4)
			end)
		end
		table.insert(cards, handle.holder)
	end
	if not ctx.quiet then
		Fx.cascade(cards, 0.05)
	end
end

function CratesTab.badge(profile: any): boolean
	for _, c in Crates.List do
		if freeOpens(profile, c.id) > 0 then
			return true
		end
	end
	return false
end

function CratesTab.onProfile(ctx: any)
	local overlay = ctx.overlay :: Frame?
	if overlay and #overlay:GetChildren() > 0 then
		return
	end
	if not crateScene().isRunning() then
		ctx.refresh()
	end
end

return CratesTab
