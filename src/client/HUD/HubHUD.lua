--!strict
-- The hub HUD: PLAY top-center (teleports you onto the queue pad; the card opens there), SHOP tile
-- left-center, Gold pill with + and INVITE FRIENDS bottom-left, the WEAPONS · CLASSES · AVATAR dock
-- bottom-center as icon tiles with labels (reference style), BOOSTS bottom-right as icon chips with a
-- countdown, and a slot under PLAY for the compact queue card. Shown by HUD.setMode("hub").
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local LevelRewards = require(Shared:WaitForChild("LevelRewards"))

local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local ClientState = require(Client:WaitForChild("ClientState"))
local LevelCard = require(script.Parent.LevelCard)
local BoostChips = require(script.Parent.BoostChips)
local PassSeason = require(Shared:WaitForChild("PassSeason"))
local Clock = require(Shared:WaitForChild("Clock"))

local HubHUD = {}

local GREEN = Color3.fromHex("2FD46A")

-- Icon tile with a label under it. Returns the button.
local function iconTile(
	parent: Instance,
	order: number,
	label: string,
	glyph: string,
	bg: Color3,
	fg: Color3,
	size: number
): TextButton
	local S = UI.S
	local holder = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size + S(16)),
		LayoutOrder = order,
		Parent = parent,
	})
	local b = UI.button({
		Name = label,
		Text = "",
		BackgroundColor3 = bg,
		Size = UDim2.fromOffset(size, size),
		Parent = holder,
	})
	UI.corner(b, S(10))
	UI.stroke(b, Theme.Colors.black, S(1.5), 0.3)
	if glyph == "gun" then
		local icon = UI.gunIcon(b, fg, math.floor(size * 0.8))
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
	else
		UI.text({
			Text = glyph,
			Font = Theme.Fonts.display,
			TextSize = math.floor(size * (if #glyph > 1 then 0.34 else 0.6)),
			TextColor3 = fg,
			Size = UDim2.fromScale(1, 1),
			Parent = b,
		})
	end
	local l = UI.text({
		Text = label,
		Font = Theme.Fonts.display,
		TextSize = S(11),
		TextColor3 = Theme.Colors.text,
		Position = UDim2.fromOffset(0, size + S(1)),
		Size = UDim2.new(1, 0, 0, S(14)),
		Parent = holder,
	})
	UI.stroke(l, Theme.Colors.black, S(1.5), 0.3)
	b.MouseEnter:Connect(function()
		if not ClientState.isMobile then
			UI.punch(b, 1.06, 0.15)
		end
	end)
	return b
end

function HubHUD.build(gui: ScreenGui, track: (RBXScriptConnection) -> ())
	local S = UI.S
	local mobile = ClientState.isMobile
	local component: { [string]: any } = {}
	local root = UI.frame({
		Name = "HubHUD",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = gui,
	})

	-- PLAY, top-center.
	local playH = if mobile then S(44) else S(64)
	local play = UI.button({
		Name = "Play",
		Text = "PLAY",
		Font = Theme.Fonts.display,
		TextSize = if mobile then S(22) else S(32),
		TextColor3 = Theme.Colors.bg,
		BackgroundColor3 = GREEN,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, S(if mobile then 12 else 22)),
		Size = UDim2.fromOffset(if mobile then S(200) else S(280), playH),
		Parent = root,
	})
	UI.corner(play, S(10))
	UI.stroke(play, Theme.Colors.black, S(2), 0.4)
	play.Activated:Connect(function()
		UI.punch(play, 0.92, 0.2)
		UI.sound(Theme.Sounds.toast, 1.3, 0.5)
		Remotes.QueueAction:FireServer("play")
	end)
	play.MouseEnter:Connect(function()
		if not mobile then
			UI.punch(play, 1.04, 0.15)
		end
	end)

	-- Slot for the compact queue card, under PLAY.
	local queueSlot = UI.frame({
		Name = "QueueSlot",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, S(if mobile then 12 else 22) + playH + S(10)),
		Size = UDim2.fromOffset(S(360), 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = root,
	})
	UI.list(queueSlot, Enum.FillDirection.Vertical, S(6), Enum.HorizontalAlignment.Center)
	if mobile then
		UI.new("UIScale", { Scale = 0.8, Parent = queueSlot })
	end

	-- Placeholder panel (SHOP / GOLD / CRATE · PHASE 4).
	local placeholder = UI.frame({
		Name = "Placeholder",
		BackgroundColor3 = Theme.Colors.bg,
		BackgroundTransparency = 0.04,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(S(360), S(170)),
		Visible = false,
		ZIndex = 20,
		Parent = root,
	})
	UI.corner(placeholder, S(10))
	UI.stroke(placeholder, Theme.Colors.black, S(2), 0.3)
	local phHeader = UI.frame({
		BackgroundColor3 = Theme.Colors.blue,
		Size = UDim2.new(1, 0, 0, S(44)),
		ZIndex = 21,
		Parent = placeholder,
	})
	UI.corner(phHeader, S(10))
	local placeholderTitle = UI.text({
		Text = "Shop",
		Font = Theme.Fonts.body,
		TextSize = S(22),
		TextColor3 = Theme.Colors.white,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(S(16), 0),
		Size = UDim2.new(1, -S(32), 1, 0),
		ZIndex = 22,
		Parent = phHeader,
	})
	UI.text({
		Text = "PHASE 4 · ROBUX AND CRATES ARE OUT OF SCOPE FOR THIS BRIEF",
		TextSize = S(11),
		TextColor3 = Theme.Colors.grey,
		Position = UDim2.fromOffset(0, S(64)),
		Size = UDim2.new(1, 0, 0, S(16)),
		ZIndex = 21,
		Parent = placeholder,
	})
	local okBtn = UI.button({
		Text = "OK",
		Font = Theme.Fonts.body,
		TextSize = S(18),
		TextColor3 = Theme.Colors.bg,
		BackgroundColor3 = GREEN,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -S(14)),
		Size = UDim2.new(1, -S(28), 0, S(44)),
		ZIndex = 21,
		Parent = placeholder,
	})
	UI.corner(okBtn, S(6))
	okBtn.Activated:Connect(function()
		placeholder.Visible = false
	end)
	function component.showPlaceholder(title: string)
		placeholderTitle.Text = title
		placeholder.Visible = true
		UI.punch(placeholder, 1.08, 0.25)
		UI.sound(Theme.Sounds.toast, 1.1, 0.4)
	end

	-- SHOP tile, left-center.
	local shopSize = if mobile then S(52) else S(64)
	local shopHolder = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, S(20), 0.5, 0),
		Size = UDim2.fromOffset(shopSize, shopSize + S(16)),
		Parent = root,
	})
	local shop = iconTile(shopHolder, 1, "Shop", "$", Theme.Colors.amber, Theme.Colors.bg, shopSize)
	shop.Activated:Connect(function()
		UI.punch(shop, 0.92, 0.15)
		if component.onShop then
			component.onShop() -- brief 6: the store scene
		else
			component.showPlaceholder("Shop")
		end
	end)

	-- Gold pill with + and INVITE FRIENDS, bottom-left; the level card sits above them.
	local goldW = if mobile then S(170) else S(230)
	local levelCard = LevelCard.build(root, goldW, true) -- the same width as the Gold pill and INVITE under it
	levelCard.frame.AnchorPoint = Vector2.new(0, 1)
	levelCard.frame.Position = UDim2.new(0, S(20), 1, -S(62) - S(38) - S(12))
	local gold = UI.frame({
		Name = "Gold",
		BackgroundColor3 = Theme.Colors.panel,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, S(20), 1, -S(62)),
		Size = UDim2.fromOffset(goldW, S(38)),
		Parent = root,
	})
	UI.corner(gold, S(8))
	UI.stroke(gold, Theme.Colors.black, S(1.5), 0.3)
	local bar = UI.frame({
		BackgroundColor3 = Theme.Colors.gold,
		Size = UDim2.fromOffset(S(26), S(13)),
		Position = UDim2.fromOffset(S(10), S(13)),
		Rotation = -8,
		Parent = gold,
	})
	UI.corner(bar, S(3))
	local goldLabel = UI.text({
		Name = "Gold",
		Text = "0",
		Font = Theme.Fonts.display,
		TextSize = S(22),
		TextColor3 = Theme.Colors.white,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(S(44), 0),
		Size = UDim2.new(1, -S(88), 1, 0),
		Parent = gold,
	})
	local plus = UI.button({
		Text = "+",
		Font = Theme.Fonts.display,
		TextSize = S(20),
		TextColor3 = Theme.Colors.bg,
		BackgroundColor3 = GREEN,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -S(6), 0.5, 0),
		Size = UDim2.fromOffset(S(28), S(28)),
		Parent = gold,
	})
	UI.corner(plus, S(6))
	plus.Activated:Connect(function()
		UI.punch(plus, 0.9, 0.15)
		if component.onGoldPlus then
			component.onGoldPlus() -- brief 6: the store's GOLD tab
		else
			component.showPlaceholder("Gold")
		end
	end)
	-- Brief 6: revive tokens beside the Gold pill; tap for the token packs.
	local tokenChip = UI.button({
		Name = "Tokens",
		Text = "",
		BackgroundColor3 = Theme.Colors.panel,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, S(20) + goldW + S(8), 1, -S(62)),
		Size = UDim2.fromOffset(S(70), S(38)),
		Parent = root,
	})
	UI.corner(tokenChip, S(8))
	UI.stroke(tokenChip, Color3.fromHex("3FD47A"), S(1.5), 0.2)
	local tokenDot = UI.frame({
		BackgroundColor3 = Color3.fromHex("3FD47A"),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, S(7), 0.5, 0),
		Size = UDim2.fromOffset(S(22), S(22)),
		Parent = tokenChip,
	})
	UI.corner(tokenDot, S(11))
	UI.text({
		Text = "+",
		Font = Theme.Fonts.display,
		TextSize = S(18),
		TextColor3 = Theme.Colors.white,
		Size = UDim2.fromScale(1, 1),
		Parent = tokenDot,
	})
	local tokenLabel = UI.text({
		Text = "0",
		Font = Theme.Fonts.display,
		TextSize = S(20),
		TextColor3 = Theme.Colors.white,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(S(34), 0),
		Size = UDim2.new(1, -S(36), 1, 0),
		Parent = tokenChip,
	})
	tokenChip.Activated:Connect(function()
		UI.punch(tokenChip, 0.9, 0.15)
		local sheet = require(Client:WaitForChild("PurchaseSheet") :: ModuleScript) :: any
		sheet.choose("Revive tokens", { "tokens_5", "tokens_25", "tokens_100" }, { context = "hub token chip" })
	end)

	local invite = UI.button({
		Name = "Invite",
		Text = if mobile then "+👥" else "INVITE FRIENDS",
		Font = Theme.Fonts.body,
		TextSize = S(13),
		TextColor3 = Theme.Colors.white,
		BackgroundColor3 = Theme.Colors.panel,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, S(20), 1, -S(20)),
		Size = UDim2.fromOffset(if mobile then S(44) else goldW, S(34)),
		Parent = root,
	})
	UI.corner(invite, S(6))
	UI.stroke(invite, Theme.Colors.black, S(1.5), 0.3)
	invite.Activated:Connect(function()
		UI.punch(invite, 0.92, 0.15) -- present, does nothing (brief)
	end)

	-- Dock, bottom-center: WEAPONS · CLASSES · AVATAR icon tiles with labels.
	local tile = if mobile then S(64) else S(92)
	local dock = UI.frame({
		Name = "Dock",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -S(16)),
		Size = UDim2.fromOffset(tile * 3 + S(24), tile + S(16)),
		Parent = root,
	})
	UI.list(dock, Enum.FillDirection.Horizontal, S(12), Enum.HorizontalAlignment.Center)
	local tiles: { [string]: TextButton } = {}
	local glyphs = { WEAPONS = "gun", CLASSES = "CLS", AVATAR = "MSK" }
	local colors = { WEAPONS = Theme.Colors.blue, CLASSES = Theme.Colors.grey, AVATAR = Theme.Colors.gold }
	local labels = { WEAPONS = "Weapons", CLASSES = "Classes", AVATAR = "Avatar" }
	for i, tab in { "WEAPONS", "CLASSES", "AVATAR" } do
		local b = iconTile(dock, i, labels[tab], glyphs[tab], Theme.Colors.panel, colors[tab], tile)
		local stroke = b:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = Theme.Colors.gold
			stroke.Transparency = 0
		end
		b.Activated:Connect(function()
			UI.punch(b, 0.92, 0.18)
			UI.sound(Theme.Sounds.toast, 1.4, 0.35)
			if component.onDock then
				component.onDock(tab)
			end
		end)
		tiles[tab] = b
	end

	-- BOOSTS, bottom-right (brief 6): the live boost chips, VIP's CASH chip and daily gift, and a + into the store.
	local chipSize = if mobile then S(44) else S(56)
	local boosts = UI.frame({
		Name = "Boosts",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -S(20), 1, -S(16)),
		Size = UDim2.fromOffset(chipSize * 5 + S(40), chipSize + S(34)),
		Parent = root,
	})
	UI.text({
		Text = "BOOSTS",
		Font = Theme.Fonts.display,
		TextSize = S(12),
		TextColor3 = Theme.Colors.grey,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.new(1, 0, 0, S(14)),
		Parent = boosts,
	})
	local chipHolder = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, S(18)),
		Size = UDim2.new(1, 0, 0, chipSize + S(16)),
		Parent = boosts,
	})
	local chipRow = BoostChips.new(chipHolder, {
		size = chipSize,
		align = Enum.HorizontalAlignment.Right,
		hub = true,
		onPlus = function()
			if component.onStoreTab then
				component.onStoreTab("BOOSTS")
			end
		end,
		onGift = function()
			if component.onVipGift then
				component.onVipGift()
			end
		end,
	}, track)
	chipRow.frame.AnchorPoint = Vector2.new(1, 0)
	chipRow.frame.Position = UDim2.fromScale(1, 0)

	-- Brief 6: PASS and JOBS, top-right (top-left stays free for chat). PASS: the season emblem with the level, a
	-- ring of dots for the progress to the next level, a red dot when a cell is claimable. JOBS: the clipboard,
	-- the dailies done count, a red dot when a Job is ready to claim.
	local topSize = if mobile then S(54) else S(68)
	local topRight = UI.frame({
		Name = "TopButtons",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -S(20), 0, S(16)),
		Size = UDim2.fromOffset(topSize * 2 + S(14), topSize + S(18)),
		Parent = root,
	})
	UI.list(topRight, Enum.FillDirection.Horizontal, S(14), Enum.HorizontalAlignment.Right)
	local function topTile(order: number, label: string, color: Color3): (TextButton, Frame, TextLabel)
		local holder = UI.frame({
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(topSize, topSize + S(18)),
			LayoutOrder = order,
			Parent = topRight,
		})
		local b = UI.button({
			Text = "",
			BackgroundColor3 = Theme.Colors.panel,
			Size = UDim2.fromOffset(topSize, topSize),
			Parent = holder,
		})
		UI.corner(b, S(12))
		UI.stroke(b, color, S(2), 0)
		local dot = UI.frame({
			BackgroundColor3 = Theme.Colors.red,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -S(4), 0, S(4)),
			Size = UDim2.fromOffset(S(14), S(14)),
			Visible = false,
			ZIndex = 5,
			Parent = holder,
		})
		UI.corner(dot, S(7))
		UI.stroke(dot, Theme.Colors.white, S(1.5), 0)
		local sub = UI.text({
			Text = label,
			Font = Theme.Fonts.display,
			TextSize = S(12),
			TextColor3 = Theme.Colors.text,
			Position = UDim2.fromOffset(0, topSize + S(2)),
			Size = UDim2.new(1, 0, 0, S(14)),
			Parent = holder,
		})
		UI.stroke(sub, Theme.Colors.black, S(1.5), 0.3)
		b.MouseEnter:Connect(function()
			if not mobile then
				UI.punch(b, 1.06, 0.15)
			end
		end)
		return b, dot, sub
	end
	local ORANGE = Color3.fromHex("E8792A")
	local passBtn, passDot, passSub = topTile(1, "PASS", ORANGE)
	-- The progress ring: dots round the emblem, lit up to the XP share of the level.
	local RING = 16
	local ringDots: { Frame } = {}
	for i = 1, RING do
		local a = (i - 1) / RING * math.pi * 2 - math.pi / 2
		local dd = UI.frame({
			BackgroundColor3 = Color3.fromHex("3A3A44"),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, math.cos(a) * topSize * 0.38, 0.5, math.sin(a) * topSize * 0.38),
			Size = UDim2.fromOffset(S(5), S(5)),
			ZIndex = 3,
			Parent = passBtn,
		})
		UI.corner(dd, S(3))
		ringDots[i] = dd
	end
	local emblem = UI.frame({
		BackgroundColor3 = ORANGE,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(math.floor(topSize * 0.42), math.floor(topSize * 0.42)),
		Rotation = 45,
		ZIndex = 3,
		Parent = passBtn,
	})
	UI.corner(emblem, S(4))
	local passLv = UI.text({
		Text = "1",
		Font = Theme.Fonts.display,
		TextSize = math.floor(topSize * 0.3),
		TextColor3 = Theme.Colors.white,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
		Parent = passBtn,
	})
	UI.stroke(passLv, Theme.Colors.black, S(1.5), 0.2)
	passBtn.Activated:Connect(function()
		UI.punch(passBtn, 0.9, 0.15)
		UI.sound(Theme.Sounds.toast, 1.3, 0.4)
		ClientState.Juice:Fire("OpenPass", {})
	end)
	local jobsBtn, jobsDot, jobsSub = topTile(2, "JOBS", Theme.Colors.gold)
	-- The clipboard: a board, a clip, three lines.
	local board = UI.frame({
		BackgroundColor3 = Color3.fromHex("C9A46A"),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.5, 0.62),
		ZIndex = 3,
		Parent = jobsBtn,
	})
	UI.corner(board, S(4))
	local paper = UI.frame({
		BackgroundColor3 = Color3.fromHex("F2E6C8"),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.fromScale(0.78, 0.74),
		ZIndex = 4,
		Parent = board,
	})
	for i = 1, 3 do
		UI.frame({
			BackgroundColor3 = Color3.fromHex("8A7A5A"),
			Position = UDim2.fromScale(0.15, 0.18 + (i - 1) * 0.26),
			Size = UDim2.fromScale(0.7, 0.08),
			ZIndex = 5,
			Parent = paper,
		})
	end
	UI.frame({
		BackgroundColor3 = Color3.fromHex("6A6A72"),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.04),
		Size = UDim2.fromScale(0.5, 0.14),
		ZIndex = 5,
		Parent = board,
	})
	jobsBtn.Activated:Connect(function()
		UI.punch(jobsBtn, 0.9, 0.15)
		UI.sound(Theme.Sounds.toast, 1.3, 0.4)
		ClientState.Juice:Fire("OpenJobs", {})
	end)
	local function paintTop(profile: any)
		local pass = profile and profile.pass
		local level = if pass then tonumber(pass.level) or 1 else 1
		local xp = if pass then tonumber(pass.xp) or 0 else 0
		passLv.Text = tostring(level)
		passSub.Text = "LV " .. level
		local lit = math.floor(math.clamp(xp / Config.PassXpPerLevel, 0, 1) * RING + 0.5)
		for i, dd in ringDots do
			dd.BackgroundColor3 = if i <= lit then ORANGE else Color3.fromHex("3A3A44")
		end
		passDot.Visible = PassSeason.claimableCount(pass) > 0
		local jobs = profile and profile.jobs
		local done, ready = 0, false
		local today = Clock.day(ClientState.fakeNow())
		local fresh = jobs ~= nil and tonumber(jobs.dailyResetDay) == today
		if fresh then
			local JobPool = require(Shared:WaitForChild("JobPool")) :: any
			for _, e in jobs.daily do
				local def = JobPool.ById[e.id]
				if def and (tonumber(e.progress) or 0) >= def.target then
					done += 1
					if not e.claimed then
						ready = true
					end
				end
			end
			for _, e in jobs.bounty do
				local def = JobPool.ById[e.id]
				if def and (tonumber(e.progress) or 0) >= def.target and not e.claimed then
					ready = true
				end
			end
		end
		jobsSub.Text = string.format("%d / %d", done, if fresh then #jobs.daily else 3)
		jobsDot.Visible = ready or not fresh
	end
	component.paintTop = paintTop

	component.frame = root
	component.queueSlot = queueSlot
	component.goldLabel = goldLabel
	component.tiles = tiles
	component.play = play
	component.onDock = nil :: ((string) -> ())?

	local shown = -1
	local shownTokens = -1
	local shownLevel, shownXp = -1, -1
	function component.update(sync: any)
		chipRow.update(sync)
		paintTop(sync.profile)
		local profile = sync.profile
		local tokens = if profile and typeof(profile.reviveTokens) == "number" then profile.reviveTokens else 0
		if tokens ~= shownTokens then
			if shownTokens >= 0 then
				UI.punch(tokenChip, if tokens > shownTokens then 1.2 else 0.95, 0.3)
			end
			shownTokens = tokens
			tokenLabel.Text = tostring(tokens)
		end
		local gold = if profile and typeof(profile.gold) == "number" then profile.gold else 0
		if gold ~= shown then
			if shown >= 0 then
				UI.punch(goldLabel, if gold > shown then 1.15 else 0.95, 0.3)
			end
			shown = gold
			goldLabel.Text = UI.fmtNum(gold)
		end
		-- The level card reads the profile; a change (a run, a debug +XP) pops it.
		local level = if profile and typeof(profile.level) == "number" then profile.level else 1
		local xp = if profile and typeof(profile.xp) == "number" then profile.xp else 0
		if level ~= shownLevel or xp ~= shownXp then
			local leveled = shownLevel >= 0 and level > shownLevel
			shownLevel, shownXp = level, xp
			levelCard.set(level, xp, LevelRewards.xpToLevel(level), nil, nil)
			if leveled then
				levelCard.flash()
				levelCard.punch()
			end
		end
	end

	-- PLAY breathes.
	local t = 0
	track(RunService.Heartbeat:Connect(function(dt)
		if not root.Visible then
			return
		end
		t += dt
		local stroke = play:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = 0.3 + 0.2 * math.sin(t * 2)
		end
	end))

	return component
end

return HubHUD
