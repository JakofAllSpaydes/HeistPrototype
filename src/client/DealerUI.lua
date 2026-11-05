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
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))

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
}

local items: { Item } = {}
local readRadius = 6
local panel: { gui: BillboardGui, att: Attachment, frame: Frame, price: TextLabel, key: any }? = nil
local card: { root: Frame, title: TextLabel, teleport: TextButton, skip: TextButton, pause: TextButton }? = nil
local screen: ScreenGui? = nil
local active = false

-- Phones render UI.S at about half scale: the card, tags and panels are sized up there for thumbs.
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

local function closePanel()
	local p = panel
	panel = nil
	if p then
		p.att:Destroy()
	end
end

------------------------------------------------------------------ World cards on the stands and props
local function standCard(it: Item, statId: string, tier: number)
	local att = Instance.new("Attachment")
	att.WorldPosition = it.position
	att.Parent = Workspace.Terrain
	it.tag = att
	if it.sold then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Adornee = att
	gui.Size = UDim2.fromScale(1.9, 2.5)
	gui.LightInfluence = 0
	gui.MaxDistance = 90
	gui.Parent = att
	local color = Rarity.color(tier)
	local face = UI.frame({
		BackgroundColor3 = Theme.Colors.panel,
		Size = UDim2.fromScale(1, 0.78),
		Parent = gui,
	})
	UI.new("UICorner", { CornerRadius = UDim.new(0.12, 0), Parent = face })
	UI.stroke(face, color, 3)
	local icon = UI.frame({
		BackgroundColor3 = color,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.78, 0.6),
		Parent = face,
	})
	UI.new("UICorner", { CornerRadius = UDim.new(0.18, 0), Parent = icon })
	UI.text({
		Text = Upgrades.shortName(statId),
		Font = Theme.Fonts.display,
		TextScaled = true,
		TextColor3 = Theme.Colors.bg,
		Size = UDim2.fromScale(1, 1),
		Parent = icon,
	})
	local pill = UI.frame({
		BackgroundColor3 = Theme.Colors.cash,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(0.9, 0.2),
		Parent = gui,
	})
	UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = pill })
	UI.text({
		Text = UI.fmtCash(it.price),
		Font = Theme.Fonts.display,
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
		Font = Theme.Fonts.display,
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

local function openPanel(it: Item)
	closePanel()
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
		Font = Theme.Fonts.display,
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
		Font = Theme.Fonts.display,
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
		Text = if ClientState.isMobile then "BUY" else "F  BUY",
		Font = Theme.Fonts.display,
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
	local best: Item? = nil
	local bestD = readRadius
	for _, it in items do
		if it.sold then
			continue
		end
		local d = Vector3.new(it.position.X - root.Position.X, 0, it.position.Z - root.Position.Z).Magnitude
		if d <= bestD then
			bestD = d
			best = it
		end
	end
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
		end
	end
end

------------------------------------------------------------------ The HUD card
local function buildCard()
	if card then
		card.root:Destroy()
		card = nil
	end
	local S = MS
	local s = screen
	if not s or not s.Parent then
		s = UI.new("ScreenGui", {
			Name = "DealerUI",
			IgnoreGuiInset = true,
			ResetOnSpawn = false,
			DisplayOrder = 6,
			Parent = playerGui,
		}) :: ScreenGui
		screen = s
	end
	local mobile = ClientState.isMobile
	local vp = (Workspace.CurrentCamera :: Camera).ViewportSize
	local W = math.min(S(440), math.floor(vp.X * 0.94)) -- never wider than the phone
	local root = UI.frame({
		Name = "DealerCard",
		BackgroundColor3 = Theme.Colors.panel,
		BackgroundTransparency = 0.08,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, S(if mobile then 64 else 92)),
		Size = UDim2.fromOffset(W, S(if mobile then 86 else 90)),
		Parent = s,
	})
	UI.corner(root, S(12))
	UI.stroke(root, Theme.Colors.amber, S(2))
	local title = UI.text({
		Text = "DEALER · 1:30",
		Font = Theme.Fonts.display,
		TextSize = S(22),
		TextColor3 = Theme.Colors.amber,
		Position = UDim2.fromOffset(0, S(6)),
		Size = UDim2.new(1, 0, 0, S(26)),
		Parent = root,
	})
	local row = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -S(8)),
		Size = UDim2.new(1, -S(16), 0, S(if mobile then 42 else 40)),
		Parent = root,
	})
	UI.list(row, Enum.FillDirection.Horizontal, S(6), Enum.HorizontalAlignment.Center)
	local function button(text: string, color: Color3, order: number, fn: () -> ()): TextButton
		local b = UI.button({
			Text = text,
			Font = Theme.Fonts.display,
			TextSize = S(if mobile then 12 else 13),
			TextColor3 = Theme.Colors.bg,
			TextWrapped = true,
			BackgroundColor3 = color,
			Size = UDim2.new(1 / 3, -S(4), 1, 0),
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
	local teleport = button(if hot then "TELEPORT TO DEALER [T]" else "TELEPORT", Theme.Colors.blue, 1, function()
		Remotes.DealerAction:FireServer("teleport")
	end)
	local skip = button(if hot then "SKIP [V]" else "SKIP", Theme.Colors.cash, 2, function()
		Remotes.DealerAction:FireServer("skip")
	end)
	local pause = button(if hot then "VOTE TO PAUSE [P]" else "PAUSE", Theme.Colors.grey, 3, function()
		local pv = ClientState.sync and (ClientState.sync :: any).pause
		Remotes.PauseAction:FireServer(if pv and pv.myVote then "unvote" else "vote")
	end)
	root.Position = UDim2.new(0.5, 0, 0, -S(120))
	UI.tween(
		root,
		{ Position = UDim2.new(0.5, 0, 0, S(if mobile then 64 else 92)) },
		0.4,
		Enum.EasingStyle.Back,
		Enum.EasingDirection.Out
	)
	card = { root = root, title = title, teleport = teleport, skip = skip, pause = pause }
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
			if mobile then "" else " [V]"
		)
		c.skip.BackgroundColor3 = if dv.mySkip then Theme.Colors.gold else Theme.Colors.cash
		c.teleport.AutoButtonColor = false
		c.teleport.BackgroundTransparency = if dv.teleportUsed then 0.6 else 0
		c.teleport.Text = if dv.teleportUsed
			then "TELEPORT USED"
			elseif mobile then "TELEPORT"
			else "TELEPORT TO DEALER [T]"
	end
	local pv = sync.pause
	if pv then
		local can = pv.canVote == true
		c.pause.BackgroundTransparency = if can or pv.myVote then 0 else 0.6
		c.pause.Text = if not can and not pv.myVote
			then string.format("PAUSE IN %d WAVES", tonumber(pv.cooldownWaves) or 0)
			else string.format(
				"%s %d/%d%s",
				if pv.myVote then "PAUSE VOTED" else "VOTE TO PAUSE",
				tonumber(pv.votes) or 0,
				tonumber(pv.needed) or 1,
				if ClientState.isMobile then "" else " [P]"
			)
		c.pause.BackgroundColor3 = if pv.myVote then Theme.Colors.gold else Theme.Colors.grey
	end
end

local function start()
	active = true
	buildCard()
	UI.sound(Theme.Sounds.call, 0.8, 0.6)
end

local function stop()
	active = false
	clearItems()
	closePanel()
	if card then
		local root = card.root
		card = nil
		local out = UI.tween(root, { Position = UDim2.new(0.5, 0, 0, -UI.S(120)) }, 0.3)
		out.Completed:Once(function()
			root:Destroy()
		end)
	end
end

function DealerUI.init()
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
		if key == Enum.KeyCode.F then
			local p = panel
			if p then
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
