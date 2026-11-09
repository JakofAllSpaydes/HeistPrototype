--!strict
-- Queue zone client: the Create Party card (reference layout: header bar with X, Select Map thumbnails,
-- Difficulty segment with the bonus row, Party size segment, the boosts row (live: boosts and revive tokens), CREATE
-- PARTY) and the compact party card under PLAY in the hub HUD (map · difficulty, slots, countdown).
-- Driven by Remotes.QueueState; toasts via "QueueToast". Movement is locked while the card is open.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local Icons = require(script.Parent:WaitForChild("UI"):WaitForChild("Icons"))
local HUD = require(script.Parent:WaitForChild("HUD"))
local PurchaseSheet = require(script.Parent:WaitForChild("PurchaseSheet"))
local BoostDefs = require(Shared:WaitForChild("BoostDefs"))
local ReviveTokenPacks = require(Shared:WaitForChild("ReviveTokenPacks"))
local Clock = require(Shared:WaitForChild("Clock"))
local Maps = require(Shared:WaitForChild("Maps"))
local MatchCardLine = require(script.Parent:WaitForChild("Retention"):WaitForChild("MatchCardLine")) -- brief 10
local RelicRail = require(script.Parent:WaitForChild("RelicRail")) -- brief 13

local QueueUI = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GREEN = Color3.fromHex("2FD46A")

local view: any = nil
local createGui: ScreenGui? = nil
local partyCard: Frame? = nil
local partyCountdown: TextLabel? = nil
local partySlots: { Frame } = {}
local partyNames: TextLabel? = nil
local chosen = { partySize = 4, mapIndex = 1, diffIndex = 1 }

local function mapById(id: string?): any
	return Maps.get(id)
end

local function diffById(id: string?): any
	for _, d in Config.QueueDifficulties do
		if d.id == id then
			return d
		end
	end
	return Config.QueueDifficulties[1]
end

local function fmtCountdown(startsAt: number): string
	return string.format("STARTING IN %d", math.max(0, math.ceil(startsAt - ClientState.serverNow())))
end

------------------------------------------------------------------ Create Party card
local function closeCreate()
	if createGui then
		createGui:Destroy()
		createGui = nil
	end
	ClientState.setBlock("queue", false)
end

local function section(parent: Instance, order: number, text: string)
	local S = UI.S
	local bar = UI.frame({
		BackgroundColor3 = Theme.Colors.panel,
		Size = UDim2.new(1, 0, 0, S(24)),
		LayoutOrder = order,
		Parent = parent,
	})
	UI.corner(bar, S(4))
	UI.text({
		Text = text,
		FontFace = Theme.Fonts.body,
		TextSize = S(13),
		TextColor3 = Theme.Colors.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(S(10), 0),
		Size = UDim2.new(1, -S(10), 1, 0),
		Parent = bar,
	})
end

-- Segmented control: equal-width buttons, the selected one blue, disabled ones dim.
local function segment(
	parent: Instance,
	order: number,
	entries: { { name: string, disabled: boolean? } },
	selectedIndex: number,
	height: number,
	onPick: (number) -> ()
): { TextButton }
	local S = UI.S
	local row = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, height),
		LayoutOrder = order,
		Parent = parent,
	})
	UI.list(row, Enum.FillDirection.Horizontal, S(8))
	local buttons: { TextButton } = {}
	local n = #entries
	for i, e in entries do
		local on = i == selectedIndex
		local b = UI.button({
			Text = e.name,
			FontFace = Theme.Fonts.body,
			TextSize = S(16),
			TextColor3 = if e.disabled then Theme.Colors.grey else Theme.Colors.white,
			BackgroundColor3 = if on then Theme.Colors.blue else Theme.Colors.panel,
			Size = UDim2.new(1 / n, -S(8) * (n - 1) / n, 1, 0),
			LayoutOrder = i,
			Parent = row,
		})
		UI.corner(b, S(4))
		if not e.disabled then
			b.Activated:Connect(function()
				UI.punch(b, 0.95, 0.15)
				UI.sound(Theme.Sounds.toast, 1.3, 0.3)
				-- The highlight moves to the pick (Round 16: the difficulty row kept its first highlight).
				for k, other in buttons do
					other.BackgroundColor3 = if k == i then Theme.Colors.blue else Theme.Colors.panel
				end
				onPick(i)
			end)
		end
		buttons[i] = b
	end
	return buttons
end

local function openCreate(v: any)
	closeCreate()
	local S = UI.S
	local mobile = ClientState.isMobile
	chosen.partySize =
		math.clamp(tonumber(v.settings and v.settings.partySize) or v.maxPartySize or 4, 1, v.maxPartySize or 4)
	chosen.mapIndex = 1
	for i, m in Maps.live() do
		if m.id == Maps.pickable(v.settings and v.settings.mapId) then
			chosen.mapIndex = i -- PLAY AGAIN keeps the map
		end
	end
	chosen.diffIndex = 1
	ClientState.setBlock("queue", true)
	local g = UI.new("ScreenGui", {
		Name = "CreateMatch",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 9,
		Parent = playerGui,
	}) :: ScreenGui
	createGui = g
	local W = S(460)
	local panel = UI.frame({
		Name = "Panel",
		BackgroundColor3 = Theme.Colors.bg,
		BackgroundTransparency = 0.04,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, S(40)),
		Size = UDim2.fromOffset(W, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Active = true,
		Parent = g,
	})
	UI.corner(panel, S(10))
	UI.stroke(panel, Theme.Colors.black, S(2), 0.3)
	UI.tween(panel, { Position = UDim2.fromScale(0.5, 0.5) }, 0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	UI.sound(Theme.Sounds.call, 1.1, 0.5)
	if mobile then
		UI.new("UIScale", { Scale = 0.8, Parent = panel })
	end

	-- Header bar.
	local header = UI.frame({
		BackgroundColor3 = Theme.Colors.blue,
		Size = UDim2.new(1, 0, 0, S(54)),
		Parent = panel,
	})
	UI.corner(header, S(10))
	UI.new("UIGradient", {
		Color = ColorSequence.new(Color3.fromHex("2B6FB8"), Color3.fromHex("153A66")),
		Parent = header,
	})
	UI.text({
		Text = "Create Party",
		FontFace = Theme.Fonts.body,
		TextSize = S(26),
		TextColor3 = Theme.Colors.white,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(S(18), 0),
		Size = UDim2.new(1, -S(80), 1, 0),
		Parent = header,
	})
	local closeBtn = UI.button({
		Text = "X",
		FontFace = Theme.Fonts.display,
		TextSize = S(18),
		TextColor3 = Theme.Colors.white,
		BackgroundColor3 = Theme.Colors.red,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -S(12), 0.5, 0),
		Size = UDim2.fromOffset(S(36), S(36)),
		Parent = header,
	})
	UI.corner(closeBtn, S(6))
	UI.stroke(closeBtn, Theme.Colors.white, S(1.5), 0.3)
	closeBtn.Activated:Connect(function()
		Remotes.QueueAction:FireServer("cancel")
		closeCreate()
	end)

	local body = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, S(54)),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = panel,
	})
	UI.pad(body, S(14), S(12), S(14), S(14))
	UI.list(body, Enum.FillDirection.Vertical, S(8))

	-- Select Map: three thumbnail cards (the configured maps, then COMING SOON fillers).
	section(body, 1, "Select Map")
	local mapsRow = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, S(110)),
		LayoutOrder = 2,
		Parent = body,
	})
	-- Brief 7: the live maps in Maps.lua order, then one COMING SOON filler. Desktop: three tiles share the row;
	-- mobile (or more than three tiles): fixed tiles (88 x 64 thumbnails on a phone, name under) that swipe.
	local liveMaps = Maps.live()
	local tileCount = #liveMaps + 1
	local scroll = mobile or tileCount > 3
	local tileRow: GuiObject = mapsRow
	if scroll then
		local sf = UI.new("ScrollingFrame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.X,
			ScrollingDirection = Enum.ScrollingDirection.X,
			ScrollBarThickness = S(3),
			ElasticBehavior = Enum.ElasticBehavior.Always,
			Parent = mapsRow,
		})
		tileRow = sf
	end
	UI.list(tileRow, Enum.FillDirection.Horizontal, S(8))
	local mapCards: { TextButton } = {}
	local repaintBonus: () -> () = function() end
	local function paintMaps()
		for i, c in mapCards do
			local stroke = c:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = if i == chosen.mapIndex then Color3.fromHex("4DE8E8") else Theme.Colors.black
				stroke.Thickness = S(if i == chosen.mapIndex then 3 else 1)
			end
		end
	end
	for i = 1, tileCount do
		local m = liveMaps[i]
		local c = UI.button({
			Text = "",
			BackgroundColor3 = if m then Theme.Colors.panel2 else Theme.Colors.panel,
			Size = if scroll
				then UDim2.new(0, if mobile then 96 else S(150), 1, -S(6))
				else UDim2.new(1 / 3, -S(6), 1, 0),
			LayoutOrder = i,
			Parent = tileRow,
		})
		UI.corner(c, S(6))
		UI.stroke(c, Theme.Colors.black, S(1), 0.3)
		-- Thumbnail: the map's image when it has one, else its colour block with a lighter "building" shape.
		local thumb = UI.frame({
			BackgroundColor3 = if m then Color3.fromHex(m.color) else Theme.Colors.panel2,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, if mobile then 4 else 0),
			Size = if mobile then UDim2.fromOffset(88, 64) else UDim2.fromScale(0.84, 0.58),
			Parent = c,
		})
		if not mobile then
			thumb.Position = UDim2.fromScale(0.5, 0.1)
		end
		UI.corner(thumb, S(4))
		if m and m.thumb ~= "" then
			UI.new("ImageLabel", {
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Image = m.thumb,
				ScaleType = Enum.ScaleType.Crop,
				Parent = thumb,
			})
		elseif m then
			UI.frame({
				BackgroundColor3 = Theme.Colors.gold,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -S(4)),
				Size = UDim2.fromScale(0.5, 0.45),
				Parent = thumb,
			})
		end
		UI.text({
			Text = if m then m.name else "COMING SOON",
			FontFace = Theme.Fonts.body,
			TextSize = S(12),
			TextColor3 = if m then Theme.Colors.white else Theme.Colors.grey,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, S(22)),
			Parent = c,
		})
		if m then
			c.Activated:Connect(function()
				chosen.mapIndex = i
				paintMaps()
				repaintBonus()
				RelicRail.select(m.id) -- brief 13: the rail follows the highlighted map
				UI.punch(c, 0.96, 0.15)
			end)
		end
		mapCards[i] = c
	end
	paintMaps()

	-- Difficulty: every Config.QueueDifficulties row is live (Round 16); the bonus row follows the segment.
	section(body, 3, "Difficulty")
	local diffEntries = {}
	for _, d in Config.QueueDifficulties do
		table.insert(diffEntries, { name = d.name })
	end
	for _, name in { "HARD", "NIGHTMARE" } do
		if #diffEntries >= 3 then
			break
		end
		table.insert(diffEntries, { name = name, disabled = true })
	end
	local bonus: TextLabel? = nil
	local function paintBonus()
		if bonus then
			local d = Config.QueueDifficulties[chosen.diffIndex] or Config.QueueDifficulties[1]
			local m = Maps.live()[chosen.mapIndex] or Maps.live()[1]
			local top = if v.topWaves then v.topWaves[m.id .. ":" .. d.id] else v.topWave
			bonus.Text = string.format(
				"◆ x%s Gold   |   ENEMY HP x%s · DMG x%s   |   ★ Top wave %d",
				tostring(d.goldMult or 1),
				tostring(d.hpMult or 1),
				tostring(d.dmgMult or 1),
				tonumber(top) or 0
			)
		end
	end
	repaintBonus = paintBonus
	segment(body, 4, diffEntries, chosen.diffIndex, S(40), function(i)
		chosen.diffIndex = i
		paintBonus()
	end)
	local bonusRow = UI.frame({
		BackgroundColor3 = Theme.Colors.panel,
		Size = UDim2.new(1, 0, 0, S(32)),
		LayoutOrder = 5,
		Parent = body,
	})
	UI.corner(bonusRow, S(4))
	bonus = UI.text({
		Text = "",
		FontFace = Theme.Fonts.body,
		TextSize = S(13),
		TextColor3 = Theme.Colors.gold,
		Size = UDim2.fromScale(1, 1),
		Parent = bonusRow,
	})
	paintBonus()

	-- Party size.
	section(body, 6, "Party size")
	local sizeEntries = {}
	for n = 1, v.maxPartySize or Config.MaxPartySize do
		table.insert(sizeEntries, { name = tostring(n) })
	end
	local sizeButtons: { TextButton } = {}
	sizeButtons = segment(body, 7, sizeEntries, chosen.partySize, S(40), function(i)
		chosen.partySize = i
		for k, b in sizeButtons do
			b.BackgroundColor3 = if k == i then Theme.Colors.blue else Theme.Colors.panel
		end
	end)

	-- Round 18: the boosts row is live. POWER / CASH / LUCKY (BoostDefs) and REVIVE TOKENS, drawn like the hub's
	-- chips: the pictogram, then either the live timer (active, in the boost's color) or the cheapest price; tokens show
	-- the count you hold. A tap opens the purchase sheet on that boost's durations (or the token packs); the card
	-- stays open behind it.
	local boosts = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, S(52)),
		LayoutOrder = 8,
		Parent = body,
	})
	UI.list(boosts, Enum.FillDirection.Horizontal, S(8))
	local timers: { [string]: TextLabel } = {}
	local function boostChip(order: number, id: string, glyph: string, color: Color3, onTap: () -> ()): TextLabel
		local b = UI.button({
			Text = "",
			BackgroundColor3 = Theme.Colors.panel,
			Size = UDim2.new(0.25, -S(6), 1, 0),
			LayoutOrder = order,
			Parent = boosts,
		})
		b.Name = id
		UI.corner(b, S(6))
		UI.stroke(b, color, S(1.5), 0)
		-- The boost's pictogram (UI/Icons.lua, keyed by the BoostDefs id; tokens -> revive); `glyph` is the fallback.
		local icon = Icons.draw(b, if id == "tokens" then "revive" else id, S(22), color, Theme.Colors.panel, glyph)
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.new(0.5, 0, 0, S(4))
		local sub = UI.text({
			Text = "",
			FontFace = Theme.Fonts.display,
			TextSize = S(13),
			TextColor3 = Theme.Colors.text,
			Position = UDim2.fromOffset(0, S(27)),
			Size = UDim2.new(1, 0, 0, S(18)),
			Parent = b,
		})
		b.MouseEnter:Connect(function()
			UI.punch(b, 1.04, 0.12)
		end)
		b.Activated:Connect(function()
			UI.punch(b, 0.95, 0.15)
			onTap()
		end)
		return sub
	end
	for i, def in BoostDefs.List do
		timers[def.id] = boostChip(i, def.id, def.glyph, Color3.fromHex(def.color), function()
			local ids = {}
			for _, d in def.durations do
				table.insert(ids, BoostDefs.productId(def.id, d.id))
			end
			PurchaseSheet.choose(def.name .. " BOOST", ids, { context = "create party " .. def.id, note = def.desc })
		end)
	end
	local tokenLabel = boostChip(#BoostDefs.List + 1, "tokens", "+", Color3.fromHex("3FD47A"), function()
		local ids = {}
		for _, pack in ReviveTokenPacks.List do
			table.insert(ids, pack.id)
		end
		PurchaseSheet.choose("REVIVE TOKENS", ids, { context = "create party tokens" })
	end)
	local function paintBoosts()
		local p = ClientState.sync and ClientState.sync.profile
		local now = ClientState.osNow()
		for _, def in BoostDefs.List do
			local label = timers[def.id]
			local st = p and p.boosts and p.boosts[def.id]
			local left = if st then (tonumber(st.expiresAt) or 0) - now else 0
			if left > 0 then
				label.Text = Clock.timer(left)
				label.TextColor3 = Color3.fromHex(def.color)
			else
				label.Text = "R$ " .. UI.fmtInt(def.durations[1].price)
				label.TextColor3 = Theme.Colors.cash
			end
		end
		local n = if p and typeof(p.reviveTokens) == "number" then p.reviveTokens else 0
		tokenLabel.Text = "×" .. tostring(n)
		tokenLabel.TextColor3 = if n > 0 then Theme.Colors.cash else Theme.Colors.red
	end
	paintBoosts()
	local lastPaint = 0
	local paintConn: RBXScriptConnection
	paintConn = RunService.Heartbeat:Connect(function()
		if not boosts.Parent then
			paintConn:Disconnect()
			return
		end
		if os.clock() - lastPaint >= 0.5 then
			lastPaint = os.clock()
			paintBoosts()
		end
	end)

	local create = UI.button({
		Name = "CreateParty",
		Text = "CREATE PARTY",
		FontFace = Theme.Fonts.body,
		TextSize = S(24),
		TextColor3 = Theme.Colors.bg,
		BackgroundColor3 = GREEN,
		Size = UDim2.new(1, 0, 0, S(54)),
		LayoutOrder = 9,
		Parent = body,
	})
	UI.corner(create, S(6))
	create.Activated:Connect(function()
		UI.punch(create, 0.95, 0.2)
		UI.sound(Theme.Sounds.legendary, 1.2, 0.5)
		Remotes.QueueAction:FireServer("create", {
			partySize = chosen.partySize,
			mapId = (Maps.live()[chosen.mapIndex] or Maps.live()[1]).id,
			difficultyId = Config.QueueDifficulties[chosen.diffIndex].id,
		})
		closeCreate()
	end)
	-- Brief 10: PLAY A MATCH · DAILY CRATE · ×2 XP under the map row while today's first run is still to come.
	MatchCardLine.add(body, 3)
	-- Brief 13: the relic rail beside the card (a chip on the tile on phones).
	RelicRail.attach(g, panel, mapCards, liveMaps, (liveMaps[chosen.mapIndex] or liveMaps[1]).id)
end

------------------------------------------------------------------ Compact party card (hub HUD, under PLAY)
local function destroyParty()
	if partyCard then
		partyCard:Destroy()
		partyCard = nil
	end
	partyCountdown = nil
	partyNames = nil
	partySlots = {}
end

local function buildParty(v: any)
	destroyParty()
	local hub = HUD.get("hub")
	if not hub or not hub.queueSlot then
		return
	end
	local S = UI.S
	local card = UI.frame({
		Name = "PartyCard",
		BackgroundColor3 = Theme.Colors.bg,
		BackgroundTransparency = 0.1,
		Size = UDim2.fromOffset(S(340), S(74)),
		Parent = hub.queueSlot,
	})
	UI.corner(card, S(8))
	UI.stroke(card, Theme.Colors.blue, S(2))
	local map = mapById(v.settings and v.settings.mapId)
	local diff = diffById(v.settings and v.settings.difficultyId)
	UI.text({
		Text = string.format("PAD %d · %s · %s", tonumber(v.zone) or 1, map.name, diff.name),
		FontFace = Theme.Fonts.body,
		TextSize = S(14),
		TextColor3 = Theme.Colors.white,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(S(12), S(6)),
		Size = UDim2.new(0.6, 0, 0, S(18)),
		Parent = card,
	})
	partyCountdown = UI.text({
		Text = "",
		FontFace = Theme.Fonts.display,
		TextSize = S(14),
		TextColor3 = Theme.Colors.gold,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -S(12), 0, S(6)),
		Size = UDim2.new(0.4, 0, 0, S(18)),
		Parent = card,
	})
	local slotRow = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(S(12), S(28)),
		Size = UDim2.fromOffset(S(120), S(18)),
		Parent = card,
	})
	UI.list(slotRow, Enum.FillDirection.Horizontal, S(6))
	local size = tonumber(v.settings and v.settings.partySize) or 1
	for i = 1, size do
		local s = UI.frame({
			BackgroundColor3 = Theme.Colors.grey,
			BackgroundTransparency = 0.6,
			Size = UDim2.fromOffset(S(18), S(18)),
			LayoutOrder = i,
			Parent = slotRow,
		})
		UI.corner(s, S(9))
		partySlots[i] = s
	end
	partyNames = UI.text({
		Text = "",
		TextSize = S(10),
		TextColor3 = Theme.Colors.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(S(12), S(50)),
		Size = UDim2.new(1, -S(24), 0, S(16)),
		Parent = card,
	})
	partyCard = card
	UI.punch(card, 1.1, 0.3)
end

local function paintParty(v: any)
	if not partyCard then
		return
	end
	local members: { any } = v.members or {}
	for i, s in partySlots do
		local filled = i <= #members
		s.BackgroundColor3 = if filled then GREEN else Theme.Colors.grey
		s.BackgroundTransparency = if filled then 0 else 0.6
	end
	local names = {}
	for _, m in members do
		local n = UI.vipName(string.format("LV %d %s", tonumber(m.level) or 1, string.upper(tostring(m.name))), m.vip)
		if m.userId == v.owner then
			n ..= " ★"
		end
		table.insert(names, n)
	end
	if partyNames then
		partyNames.RichText = true
		partyNames.Text = table.concat(names, " · ")
	end
	if partyCountdown then
		if v.phase == "inProgress" then
			partyCountdown.Text = "STARTING"
		elseif v.waiting then
			partyCountdown.Text = "MAP BUSY" -- brief 8: the map is in use; the pad starts when it frees
		else
			partyCountdown.Text = string.format("%d / %d", #members, tonumber(v.settings and v.settings.partySize) or 1)
		end
	end
end

local function apply(v: any)
	local prev = view
	view = v
	if v.card == "create" then
		destroyParty()
		if not createGui then
			openCreate(v)
		end
		return
	end
	closeCreate()
	if v.card == "party" then
		local sameParty = prev and prev.card == "party" and partyCard ~= nil and partyCard.Parent ~= nil
		if not sameParty then
			buildParty(v)
		end
		paintParty(v)
	else
		destroyParty()
	end
end

function QueueUI.init()
	-- Brief 11: B on the Create Match card is its X (cancel and close).
	local GamepadNav = require(script.Parent:WaitForChild("GamepadNav"))
	GamepadNav.register("queue", {
		back = function()
			Remotes.QueueAction:FireServer("cancel")
			closeCreate()
		end,
	})
	Remotes.QueueState.OnClientEvent:Connect(apply)
	ClientState.Juice:Connect(function(name: string, data: any)
		if name == "QueueToast" then
			HUD.get("toast").show(tostring(data.text), Theme.Colors.blue, 1.6)
			UI.sound(Theme.Sounds.toast, 1.2, 0.4)
		elseif name == "HubEnter" or name == "RunStartBegin" then
			closeCreate()
		end
	end)
	HUD.Rebuilt:Connect(function()
		destroyParty()
		Remotes.QueueAction:FireServer("refresh")
	end)
	local lastShown = -1
	RunService.Heartbeat:Connect(function()
		local v = view
		local label = partyCountdown
		if not v or not label or v.card ~= "party" or v.phase ~= "open" or v.waiting then
			return
		end
		local startsAt = tonumber(v.startsAt) or 0
		if startsAt <= 0 then
			return
		end
		local left = math.max(0, math.ceil(startsAt - ClientState.serverNow()))
		if left ~= lastShown then
			lastShown = left
			label.Text = fmtCountdown(startsAt)
			if left <= 3 and left > 0 then
				UI.punch(label, 1.2, 0.2)
				UI.sound(Theme.Sounds.reelTick, 1 + (3 - left) * 0.2, 0.3)
			end
		end
	end)
end

return QueueUI
