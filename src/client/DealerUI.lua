--!strict
-- The dealer break on the client (brief 5). The HUD card under the wave bar: `DEALER · 1:30` with TELEPORT TO
-- DEALER (T, once per break), SKIP (V, everyone has to) and VOTE TO PAUSE (P). The shop is in the world: the
-- server sends this player's own stock (DealerStock) and this module hangs an upright card on each of the eight
-- stands (stat icon in the tier color, price pill) and a price tag over the three props. Walking within
-- ShopReadRadius of one opens a floating panel over the nearest (name, tier, effect lines current → new, price,
-- F BUY; a BUY button on touch). Not enough cash: the panel shakes and the price flashes red.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Upgrades = require(Shared:WaitForChild("Upgrades"))

local ClientState = require(script.Parent:WaitForChild("ClientState"))
local Hint = require(script.Parent:WaitForChild("Hint"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local Icons = require(script.Parent:WaitForChild("UI"):WaitForChild("Icons"))
local HUD = require(script.Parent:WaitForChild("HUD"))
local CardFace = require(script.Parent:WaitForChild("UI"):WaitForChild("CardFace"))

local DealerUI = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

type Item = {
	key: any, -- stand index or prop id
	position: Vector3,
	title: string,
	sub: string,
	lines: { string },
	price: number,
	color: Color3,
	sold: boolean,
	tag: Attachment?, -- the world card / price tag
	card: any?, -- a stand's Types.Card (Round 16: its panel is drawn as a pick-3 card with a price bar)
}

local items: { Item } = {}
local readRadius = 6
local panel: {
	gui: Instance, -- a BillboardGui (props) or the stand card's ScreenGui
	att: Attachment,
	frame: Frame,
	price: TextLabel,
	key: any,
	hidden: BillboardGui?, -- the stand's small card, hidden while its big card stands in for it
}? =
	nil
local card: { root: Frame, inner: Frame, title: TextLabel, teleport: TextButton, skip: TextButton }? = nil
local active = false

-- Phones render UI.S at about half scale: the card, tags and panels are sized up there for thumbs.
-- The small card on a stand, in studs (the big card anchors to its bottom edge).
local STAND_CARD_STUDS = Vector2.new(2.4, 3.5)

local function MS(n: number): number
	return UI.S(n * (if ClientState.isMobile then 1.4 else 1))
end

local function fmt(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

local function clearItems()
	for _, it in items do
		if it.tag then
			it.tag:Destroy()
		end
	end
	items = {}
end

-- The panel's BillboardGui lives in PlayerGui (so its BUY button takes taps), not under its attachment: both go,
-- or an orphaned panel stays on screen at the world origin.
local function closePanel()
	local p = panel
	panel = nil
	if p then
		p.gui:Destroy()
		p.att:Destroy()
		if p.hidden and p.hidden.Parent then
			p.hidden.Enabled = true
		end
	end
end

------------------------------------------------------------------ World cards on the stands and props
-- The card on a stand, a small pick-3 card: tier border, stat icon, the big number, and the price pill under it.
local function standCard(it: Item, statId: string, tier: number)
	local att = Instance.new("Attachment")
	att.WorldPosition = it.position
	att.Parent = Workspace.Terrain
	it.tag = att
	if it.sold then
		return
	end
	-- Pure UI over the table: always drawn on top, so no part ever hides it.
	local gui = Instance.new("BillboardGui")
	gui.Adornee = att
	gui.Size = UDim2.fromScale(STAND_CARD_STUDS.X, STAND_CARD_STUDS.Y)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 90
	gui.Parent = att
	local color = Rarity.color(tier)
	local face = UI.frame({
		BackgroundColor3 = Theme.Colors.panel,
		Size = UDim2.fromScale(1, 0.8),
		Parent = gui,
	})
	UI.new("UICorner", { CornerRadius = UDim.new(0.04, 0), Parent = face })
	UI.stroke(face, color, 3)
	-- A conditional (synergy) card: a small SYNERGY strip on the top edge (the opened card says why).
	if Upgrades.isConditional(statId) then
		local strip = UI.frame({
			Name = "Synergy",
			BackgroundColor3 = Color3.fromHex(Config.SynergyColor),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.fromScale(0.7, 0.11),
			ZIndex = 3,
			Parent = face,
		})
		UI.new("UICorner", { CornerRadius = UDim.new(0.12, 0), Parent = strip })
		UI.text({
			Text = "SYNERGY",
			FontFace = Theme.Fonts.display,
			TextScaled = true,
			TextColor3 = Theme.Colors.bg,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.86, 0.8),
			ZIndex = 3,
			Parent = strip,
		})
	end
	local icon = UI.frame({
		BackgroundColor3 = color,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.07),
		Size = UDim2.fromScale(0.72, 0.5),
		Parent = face,
	})
	local card = it.card
	if card then
		local bigText = Upgrades.cardTexts(card.stat, card.pct)
		UI.text({
			Text = bigText,
			FontFace = Theme.Fonts.display,
			TextScaled = true,
			TextColor3 = Theme.Colors.cash,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.62),
			Size = UDim2.fromScale(0.86, 0.3),
			Parent = face,
		})
	end
	UI.new("UICorner", { CornerRadius = UDim.new(0.06, 0), Parent = icon })
	-- The stat's pictogram (Icons.lua; the short name is the text fallback), sized to the tile so it scales with
	-- the billboard.
	Icons.fit(icon, statId, 0.86, Theme.Colors.bg, color, Upgrades.shortName(statId))
	local pill = UI.frame({
		BackgroundColor3 = Theme.Colors.cash,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(0.96, 0.17),
		Parent = gui,
	})
	UI.new("UICorner", { CornerRadius = UDim.new(0.12, 0), Parent = pill })
	UI.text({
		Text = UI.fmtCash(it.price),
		FontFace = Theme.Fonts.display,
		TextScaled = true,
		TextColor3 = Theme.Colors.bg,
		Size = UDim2.fromScale(1, 1),
		Parent = pill,
	})
end

local function propTag(it: Item)
	local att = Instance.new("Attachment")
	att.WorldPosition = it.position + Vector3.new(0, 2.2, 0)
	att.Parent = Workspace.Terrain
	it.tag = att
	local S = MS
	local gui = Instance.new("BillboardGui")
	gui.Adornee = att
	gui.Size = UDim2.fromOffset(S(120), S(40))
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 90
	gui.Parent = att
	UI.text({
		Text = it.title,
		FontFace = Theme.Fonts.display,
		TextSize = S(14),
		TextColor3 = Theme.Colors.amber,
		Size = UDim2.new(1, 0, 0, S(18)),
		Parent = gui,
	})
	local pill = UI.pill(gui, UI.fmtCash(it.price), Theme.Colors.cash, Theme.Colors.bg, S(18), S(12))
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.Position = UDim2.new(0.5, 0, 0, S(20))
end

local function onStock(data: any)
	clearItems()
	closePanel()
	readRadius = tonumber(data.readRadius) or Config.ShopReadRadius
	for _, s in data.slots or {} do
		local c = s.card
		local it: Item = {
			key = s.index,
			position = s.position,
			title = tostring(s.title or ""),
			sub = string.format("%s · %s", tostring(s.tierName or ""), string.upper(Upgrades.statName(c.stat))),
			lines = s.lines or {},
			price = tonumber(s.price) or 0,
			color = Rarity.color(tonumber(c.tier) or 1),
			sold = s.sold == true,
			tag = nil,
			card = c,
		}
		standCard(it, c.stat, tonumber(c.tier) or 1)
		table.insert(items, it)
	end
	for _, p in data.props or {} do
		local it: Item = {
			key = p.id,
			position = p.position,
			title = tostring(p.title or ""),
			sub = "FOR THE CREW",
			lines = p.lines or {},
			price = tonumber(p.price) or 0,
			color = Theme.Colors.amber,
			sold = false,
			tag = nil,
		}
		if p.id == "reroll" then
			it.sub = "FOR YOU"
		end
		propTag(it)
		table.insert(items, it)
	end
end

------------------------------------------------------------------ The floating panel over the nearest stand
local function buy(key: any)
	Remotes.DealerAction:FireServer("buy", key) -- the server checks reach, cash and stock
end

-- A stand's panel: the pick-3 card (icon well, NAME, big number, stat line, malus strip) with the stat's
-- current → new line under it and a price bar across the bottom (cash price, F BUY).
local function openCardPanel(it: Item, card: any)
	local S = MS
	local color = CardFace.tierColor(tonumber(card.tier) or 1)
	local w = S(Config.DealerCardWidth)
	-- Round 16: the big card takes the small card's place on the stand instead of floating above it: the small
	-- one hides, and the big one stands on the same spot, its bottom edge where the small card's bottom was.
	local small = it.tag and it.tag:FindFirstChildOfClass("BillboardGui")
	if small then
		small.Enabled = false
	end
	local att = Instance.new("Attachment")
	att.WorldPosition = it.position - Vector3.new(0, STAND_CARD_STUDS.Y / 2, 0)
	att.Parent = Workspace.Terrain
	-- A ScreenGui that follows the stand on screen (not a BillboardGui), so it always draws in front of the other
	-- stands' cards: AlwaysOnTop billboards sort among themselves by distance, and a nearer small card covered it.
	local gui = UI.new("ScreenGui", {
		Name = "DealerCard",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 2,
		Parent = playerGui,
	}) :: ScreenGui
	local holder = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1), -- grows up from the anchor
		Parent = gui,
	})
	local camera = Workspace.CurrentCamera :: Camera
	local follow: RBXScriptConnection
	local function place()
		if not holder.Parent then
			follow:Disconnect()
			return
		end
		local p, onScreen = camera:WorldToViewportPoint(att.WorldPosition)
		holder.Visible = onScreen and p.Z <= 40
		holder.Position = UDim2.fromOffset(p.X, p.Y)
	end
	follow = RunService.RenderStepped:Connect(place)
	local frame = UI.frame({
		BackgroundColor3 = Theme.Colors.panel,
		BackgroundTransparency = 0.02,
		Size = UDim2.fromScale(1, 1),
		Parent = holder,
	})
	UI.corner(frame, S(14))
	UI.stroke(frame, color, S(3))
	CardFace.synergyPill(frame, card.stat, S(18)) -- a conditional card: "TORCH SYNERGY" on the top edge
	-- Icon well at the top, like the pick-3 reel's landing cell.
	local wellSize = S(84)
	local well = UI.frame({
		BackgroundColor3 = Theme.Colors.bg,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, S(12)),
		Size = UDim2.fromOffset(wellSize, wellSize),
		Parent = frame,
	})
	UI.corner(well, S(14))
	UI.stroke(well, color, S(2))
	CardFace.statIcon(well, card.stat, color, S(64), false)
	local y = CardFace.body(frame, card, S, S(12) + wellSize + S(8), 0.9)
	-- What it does to your total: "DAMAGE +30% → +52%".
	for _, line in it.lines do
		UI.text({
			Text = line,
			TextSize = S(11),
			TextColor3 = Theme.Colors.textDim,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(S(8), y),
			Size = UDim2.new(1, -S(16), 0, S(14)),
			Parent = frame,
		})
		y += S(15)
	end
	y += S(6)
	-- Price bar: the cost is the loudest thing after the number.
	local barH = S(40)
	local bar = UI.frame({
		BackgroundColor3 = Theme.Colors.bg,
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.new(1, 0, 0, barH),
		Parent = frame,
	})
	UI.corner(bar, S(14))
	UI.pad(bar, S(10), 0, S(8), 0)
	local affordable = (ClientState.sync and ClientState.sync.cash or 0) >= it.price
	local price = UI.text({
		Text = UI.fmtCash(it.price),
		FontFace = Theme.Fonts.display,
		TextSize = S(24),
		TextColor3 = if affordable then Theme.Colors.cash else Theme.Colors.malus,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -S(90), 1, 0),
		Parent = bar,
	})
	local buyBtn = UI.button({
		Text = if ClientState.isMobile then "BUY" else Hint.text("{key}  BUY", "dealerBuy", "run"),
		FontFace = Theme.Fonts.display,
		TextSize = S(14),
		TextColor3 = Theme.Colors.bg,
		BackgroundColor3 = if affordable then Theme.Colors.cash else Theme.Colors.grey,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(S(80), S(28)),
		Parent = bar,
	})
	UI.corner(buyBtn, S(8))
	holder.Size = UDim2.fromOffset(w, y + barH)
	place()
	local key = it.key
	buyBtn.Activated:Connect(function()
		buy(key)
	end)
	UI.punch(frame, 1.12, 0.25)
	UI.sound(Theme.Sounds.cardFlip, 1.1, 0.3)
	panel = { gui = gui, att = att, frame = frame, price = price, key = it.key, hidden = small }
end

local function openPanel(it: Item)
	closePanel()
	if it.card then
		openCardPanel(it, it.card)
		return
	end
	local S = MS
	local att = Instance.new("Attachment")
	att.WorldPosition = it.position + Vector3.new(0, 3.2, 0)
	att.Parent = Workspace.Terrain
	local gui = Instance.new("BillboardGui")
	gui.Adornee = att
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(S(250), S(54 + 16 * #it.lines + 34))
	gui.LightInfluence = 0
	gui.MaxDistance = 40
	gui.Active = true
	gui.Parent = playerGui
	local frame = UI.frame({
		BackgroundColor3 = Theme.Colors.panel,
		BackgroundTransparency = 0.05,
		Size = UDim2.fromScale(1, 1),
		Parent = gui,
	})
	UI.corner(frame, S(10))
	UI.stroke(frame, it.color, S(2))
	UI.pad(frame, S(10), S(6), S(10), S(6))
	UI.text({
		Text = it.title,
		FontFace = Theme.Fonts.display,
		TextSize = S(17),
		TextColor3 = it.color,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, S(20)),
		Parent = frame,
	})
	UI.text({
		Text = it.sub,
		TextSize = S(10),
		TextColor3 = Theme.Colors.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(0, S(20)),
		Size = UDim2.new(1, 0, 0, S(14)),
		Parent = frame,
	})
	for i, line in it.lines do
		UI.text({
			Text = line,
			TextSize = S(12),
			TextColor3 = Theme.Colors.text,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(0, S(36 + (i - 1) * 16)),
			Size = UDim2.new(1, 0, 0, S(16)),
			Parent = frame,
		})
	end
	local price = UI.text({
		Text = UI.fmtCash(it.price),
		FontFace = Theme.Fonts.display,
		TextSize = S(18),
		TextColor3 = if (ClientState.sync and ClientState.sync.cash or 0) >= it.price
			then Theme.Colors.cash
			else Theme.Colors.malus,
		TextXAlignment = Enum.TextXAlignment.Left,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.fromOffset(S(110), S(26)),
		Parent = frame,
	})
	local buyBtn = UI.button({
		Text = if ClientState.isMobile then "BUY" else Hint.text("{key}  BUY", "dealerBuy", "run"),
		FontFace = Theme.Fonts.display,
		TextSize = S(14),
		TextColor3 = Theme.Colors.bg,
		BackgroundColor3 = Theme.Colors.cash,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 1, 0),
		Size = UDim2.fromOffset(S(90), S(26)),
		Parent = frame,
	})
	UI.corner(buyBtn, S(6))
	local key = it.key
	buyBtn.Activated:Connect(function()
		buy(key)
	end)
	UI.punch(frame, 1.15, 0.25)
	panel = { gui = gui, att = att, frame = frame, price = price, key = it.key }
end

local function nearest(): Item?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	-- Round 25: among the stands in reach, the one you're looking at (ClientState.aimScore), not just the nearest;
	-- and a floor gun in reach that you're looking at more squarely takes the interact key instead (the panel
	-- closes and its prompt comes back). ClientState.dealerFocus tells GroundLoot which one owns the key.
	local best: Item? = nil
	local bestScore = math.huge
	for _, it in items do
		if it.sold then
			continue
		end
		local d = Vector3.new(it.position.X - root.Position.X, 0, it.position.Z - root.Position.Z).Magnitude
		if d <= readRadius then
			local s = ClientState.aimScore(it.position + Vector3.new(0, 2, 0))
			if s < bestScore then
				bestScore = s
				best = it
			end
		end
	end
	if best then
		local loot = workspace:FindFirstChild("GroundLoot")
		for _, gun in if loot then loot:GetChildren() else {} do
			if gun:IsA("BasePart") and gun:GetAttribute("Landing") ~= true then
				local d = (gun.Position - root.Position).Magnitude
				if d <= Config.InteractRadius and ClientState.aimScore(gun.Position) < bestScore then
					best = nil
					break
				end
			end
		end
	end
	ClientState.dealerFocus = best ~= nil
	return best
end

local function onResult(data: any)
	local p = panel
	if data.ok then
		UI.sound(Theme.Sounds.take, 1.2, 0.6)
		ClientState.Juice:Fire("RarityFlash", { color = Theme.Colors.cash, alpha = 0.12 })
		-- The stand pops: the new stock (with this slot empty) follows from the server.
		for _, it in items do
			if it.key == data.slot and typeof(data.slot) == "number" and it.tag then
				for _, g in it.tag:GetChildren() do
					if g:IsA("BillboardGui") then
						for _, f in g:GetChildren() do
							if f:IsA("GuiObject") then
								UI.punch(f, 1.4, 0.2)
							end
						end
					end
				end
			end
		end
	elseif p and p.key == data.slot then
		UI.shake(p.frame, UI.S(5), 0.3)
		UI.sound(Theme.Sounds.deny, 1, 0.5)
		p.price.TextColor3 = Theme.Colors.red
		UI.punch(p.price, 1.3, 0.25)
		if data.reason == "cash" then
			ClientState.Juice:Fire("Toast", { text = "NOT ENOUGH CASH" })
			-- Brief 6: short of match cash funnels to the purchase sheet (RESTOCK for Robux, or a cash pack).
			local sheet = require(script.Parent:WaitForChild("PurchaseSheet") :: ModuleScript) :: any
			if not sheet.isOpen() then
				if data.slot == "reroll" then
					sheet.open("dealer_restock", { context = "dealer RESTOCK short of cash" })
				else
					sheet.choose(
						"Match cash",
						{ "cash_5k", "cash_20k", "cash_100k" },
						{ context = "dealer short of cash" }
					)
				end
			end
		end
	end
end

------------------------------------------------------------------ The HUD card (top-right stack, like a crew call)
-- The DEALER's call card comes in first (the CrewLine the server sends on DealerStart, CrewCallUI), then this
-- compact card slides into the same top-right stack: `DEALER · 1:30` with TELEPORT [T] and SKIP n/m [V].
local SLIDE = 420
local cardToken = 0

local function buildCard()
	if card then
		card.root:Destroy()
		card = nil
	end
	local home = HUD.get("topRight")
	if not home then
		return
	end
	local S = UI.S
	local mobile = ClientState.isMobile
	local H = S(if mobile then 92 else 84)
	local box = UI.frame({
		Name = "DealerBox",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(home.width, H),
		ClipsDescendants = true,
	})
	local inner = UI.frame({
		Name = "Inner",
		BackgroundColor3 = Theme.Colors.panel,
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(S(SLIDE), 0),
		Parent = box,
	})
	UI.corner(inner, S(12))
	UI.stroke(inner, Theme.Colors.amber, S(2))
	home.add(box, 3)
	local title = UI.text({
		Text = "DEALER · 1:30",
		FontFace = Theme.Fonts.display,
		TextSize = S(18),
		TextColor3 = Theme.Colors.amber,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(S(12), S(6)),
		Size = UDim2.new(1, -S(24), 0, S(24)),
		Parent = inner,
	})
	local row = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -S(8)),
		Size = UDim2.new(1, -S(16), 0, S(if mobile then 46 else 38)),
		Parent = inner,
	})
	UI.list(row, Enum.FillDirection.Horizontal, S(6), Enum.HorizontalAlignment.Center)
	local function button(text: string, color: Color3, order: number, fn: () -> ()): TextButton
		local b = UI.button({
			Text = text,
			FontFace = Theme.Fonts.display,
			TextSize = S(if mobile then 13 else 12),
			TextColor3 = Theme.Colors.bg,
			TextWrapped = true,
			BackgroundColor3 = color,
			Size = UDim2.new(1 / 2, -S(4), 1, 0),
			LayoutOrder = order,
			Parent = row,
		})
		UI.corner(b, S(8))
		b.Activated:Connect(function()
			UI.punch(b, 0.92, 0.15)
			fn()
		end)
		return b
	end
	local hot = not mobile
	local teleport = button("TELEPORT", Theme.Colors.blue, 1, function()
		Remotes.DealerAction:FireServer("teleport")
	end)
	if hot then
		Hint.bind(teleport, function()
			return Hint.text("TELEPORT [{key}]", "dealerTeleport", "run")
		end)
	end
	local skip = button(if hot then "SKIP [V]" else "SKIP", Theme.Colors.cash, 2, function()
		Remotes.DealerAction:FireServer("skip")
	end)
	UI.tween(inner, { Position = UDim2.fromOffset(0, 0) }, 0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	UI.sound(Theme.Sounds.call, 1, 0.5)
	card = { root = box, inner = inner, title = title, teleport = teleport, skip = skip }
end

local function paintCard()
	local c = card
	local sync: any = ClientState.sync
	if not c or not sync then
		return
	end
	local dv = sync.dealer
	if dv then
		c.title.Text = string.format("DEALER · %s", fmt((tonumber(dv.endsAt) or 0) - ClientState.serverNow()))
		local mobile = ClientState.isMobile
		c.skip.Text = string.format(
			"%s %d/%d%s",
			if dv.mySkip then "SKIPPING" else "SKIP",
			tonumber(dv.skips) or 0,
			tonumber(dv.needed) or 1,
			if mobile then "" else Hint.text(" [{key}]", "voteSkip", "run")
		)
		c.skip.BackgroundColor3 = if dv.mySkip then Theme.Colors.gold else Theme.Colors.cash
	end
end

-- The break starts: the DEALER's call card holds first (CrewCallUI), then the card slides into the stack.
local function start()
	if active then
		return
	end
	active = true
	ClientState.dealerActive = true
	cardToken += 1
	local token = cardToken
	task.delay(Config.CallHoldSec + 0.45, function()
		if active and token == cardToken and not card then
			buildCard()
		end
	end)
end

local function stop()
	active = false
	ClientState.dealerActive = false
	ClientState.dealerFocus = false
	cardToken += 1
	clearItems()
	closePanel()
	local c = card
	card = nil
	if c then
		local out = UI.tween(
			c.inner,
			{ Position = UDim2.fromOffset(UI.S(SLIDE), 0) },
			0.3,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		)
		out.Completed:Once(function()
			c.root:Destroy()
		end)
	end
end

function DealerUI.init()
	-- A HUD rebuild clears the top-right stack: put the card back while the break runs.
	HUD.Rebuilt:Connect(function()
		if active then
			card = nil
			buildCard()
		end
	end)
	ClientState.Juice:Connect(function(name: string, data: any)
		if name == "DealerStart" then
			start()
		elseif name == "DealerStock" and typeof(data) == "table" then
			if not active then
				start()
			end
			onStock(data)
		elseif name == "DealerResult" and typeof(data) == "table" then
			onResult(data)
		elseif name == "DealerEnd" or name == "HubEnter" then
			stop()
		elseif name == "DealerHealAll" then
			UI.sound(Theme.Sounds.legendary, 1.4, 0.5)
			ClientState.Juice:Fire("RarityFlash", { color = Theme.Colors.health, alpha = 0.2 })
			ClientState.Juice:Fire("Toast", { text = string.upper(tostring(data.name or "")) .. " HEALED THE CREW" })
		elseif name == "DealerWarn" and typeof(data) == "table" then
			-- Round 21: the stall packs up soon (Config.DealerWarnSec).
			local sec = tonumber(data.sec) or 0
			ClientState.Juice:Fire("Toast", {
				text = string.format("DEALER LEAVES IN %dS", sec),
				color = Theme.Colors.red,
				duration = 2,
			})
			UI.sound(Theme.Sounds.call, if sec <= 5 then 1.25 else 1, 0.45)
			local c = card
			if c then
				UI.punch(c.inner, 1.08, 0.3)
				c.title.TextColor3 = Theme.Colors.red
				UI.tween(c.title, { TextColor3 = Theme.Colors.amber }, 1.2)
			end
		elseif name == "PadDealer" and active and typeof(data) == "table" then
			-- Brief 11: the pad (Input.lua). D-pad up teleports, right votes skip, square buys the open panel.
			local a = data.action
			if a == "dealerTeleport" then
				Remotes.DealerAction:FireServer("teleport")
			elseif a == "voteSkip" then
				Remotes.DealerAction:FireServer("skip")
			elseif a == "dealerBuy" then
				local p = panel
				if p and ClientState.dealerFocus then
					buy(p.key)
				end
			end
		elseif name == "DealerTeleported" then
			UI.sound(Theme.Sounds.swap, 0.7, 0.6)
			ClientState.Juice:Fire("Shake", { amp = 0.2, dur = 0.2 })
		end
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or ClientState.inHub() then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.P then
			-- Vote to pause works in waves and intermissions too, not only at the dealer.
			local pv = ClientState.sync and (ClientState.sync :: any).pause
			if pv and not pv.active then
				Remotes.PauseAction:FireServer(if pv.myVote then "unvote" else "vote")
			end
			return
		end
		if not active then
			return
		end
		if key == Enum.KeyCode[Config.InteractKey] then
			local p = panel
			if p and ClientState.dealerFocus then
				buy(p.key)
			end
		elseif key == Enum.KeyCode.T then
			Remotes.DealerAction:FireServer("teleport")
		elseif key == Enum.KeyCode.V then
			Remotes.DealerAction:FireServer("skip")
		end
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		if not active then
			return
		end
		acc += dt
		if acc < 0.1 then
			return
		end
		acc = 0
		paintCard()
		local it = nearest()
		local p = panel
		if not it then
			if p then
				closePanel()
			end
		elseif not p or p.key ~= it.key then
			openPanel(it)
		end
	end)
end

return DealerUI
