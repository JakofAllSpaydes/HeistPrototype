--!strict
-- Queue zone client: the Create Match card (centered, crew-call frame style: party size 1-4, map with
-- thumbnail, difficulty, info panel, CREATE, X) and the compact party card under PLAY in the hub HUD
-- (map · difficulty, slots, countdown). Driven by Remotes.QueueState; toasts via "QueueToast".
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local HUD = require(script.Parent:WaitForChild("HUD"))

local QueueUI = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local view: any = nil
local createGui: ScreenGui? = nil
local partyCard: Frame? = nil
local partyCountdown: TextLabel? = nil
local partySlots: { Frame } = {}
local partyNames: TextLabel? = nil
local chosen = { partySize = 4, mapIndex = 1, diffIndex = 1 }

local function mapById(id: string?): any
	for _, m in Config.QueueMaps do
		if m.id == id then
			return m
		end
	end
	return Config.QueueMaps[1]
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

------------------------------------------------------------------ Create Match card
local function closeCreate()
	if createGui then
		createGui:Destroy()
		createGui = nil
	end
	ClientState.setBlock("queue", false)
end

local function openCreate(v: any)
	closeCreate()
	local S = UI.S
	local mobile = ClientState.isMobile
	chosen.partySize =
		math.clamp(tonumber(v.settings and v.settings.partySize) or v.maxPartySize or 4, 1, v.maxPartySize or 4)
	chosen.mapIndex = 1
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
	local W, H = S(if mobile then 420 else 520), S(if mobile then 300 else 360)
	local panel = UI.frame({
		Name = "Panel",
		BackgroundColor3 = Theme.Colors.bg,
		BackgroundTransparency = 0.08,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, S(40)),
		Size = UDim2.fromOffset(W, H),
		Active = true,
		Parent = g,
	})
	UI.corner(panel, S(14))
	UI.stroke(panel, Theme.Colors.blue, S(2))
	UI.tween(panel, { Position = UDim2.fromScale(0.5, 0.5) }, 0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	UI.sound(Theme.Sounds.call, 1.1, 0.5)
	if mobile then
		UI.new("UIScale", { Scale = 0.8, Parent = panel })
	end

	UI.text({
		Text = "CREATE MATCH",
		Font = Theme.Fonts.display,
		TextSize = S(26),
		TextColor3 = Theme.Colors.blue,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(S(20), S(12)),
		Size = UDim2.new(1, -S(80), 0, S(32)),
		Parent = panel,
	})
	local closeBtn = UI.button({
		Text = "X",
		Font = Theme.Fonts.display,
		TextSize = S(18),
		TextColor3 = Theme.Colors.grey,
		BackgroundColor3 = Theme.Colors.panel2,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -S(12), 0, S(12)),
		Size = UDim2.fromOffset(S(34), S(34)),
		Parent = panel,
	})
	UI.corner(closeBtn, S(8))
	UI.stroke(closeBtn, Theme.Colors.grey, S(1), 0.5)
	closeBtn.Activated:Connect(function()
		Remotes.QueueAction:FireServer("cancel")
		closeCreate()
	end)

	-- Left column: party size, map, difficulty.
	local leftW = math.floor(W * 0.56)
	local y = S(56)
	local function heading(text: string)
		UI.text({
			Text = text,
			TextSize = S(11),
			TextColor3 = Theme.Colors.grey,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(S(20), y),
			Size = UDim2.fromOffset(leftW, S(14)),
			Parent = panel,
		})
		y += S(18)
	end
	heading("PARTY SIZE")
	local sizeRow = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(S(20), y),
		Size = UDim2.fromOffset(leftW, S(40)),
		Parent = panel,
	})
	UI.list(sizeRow, Enum.FillDirection.Horizontal, S(8))
	local sizeButtons: { TextButton } = {}
	local function paintSizes()
		for n, b in sizeButtons do
			local on = n == chosen.partySize
			b.BackgroundColor3 = if on then Theme.Colors.blue else Theme.Colors.panel2
			b.TextColor3 = if on then Theme.Colors.bg else Theme.Colors.text
		end
	end
	for n = 1, v.maxPartySize or Config.MaxPartySize do
		local b = UI.button({
			Text = tostring(n),
			Font = Theme.Fonts.display,
			TextSize = S(20),
			BackgroundColor3 = Theme.Colors.panel2,
			Size = UDim2.fromOffset(S(44), S(40)),
			LayoutOrder = n,
			Parent = sizeRow,
		})
		UI.corner(b, S(8))
		b.Activated:Connect(function()
			chosen.partySize = n
			paintSizes()
			UI.punch(b, 0.9, 0.15)
			UI.sound(Theme.Sounds.toast, 1.3, 0.3)
		end)
		sizeButtons[n] = b
	end
	paintSizes()
	y += S(50)

	-- Dropdown: a row that cycles through the entries on press (one entry each in the prototype).
	local function dropdown(labelText: string, entries: { any }, key: string, thumb: boolean): TextLabel
		heading(labelText)
		local row = UI.button({
			Text = "",
			BackgroundColor3 = Theme.Colors.panel2,
			Position = UDim2.fromOffset(S(20), y),
			Size = UDim2.fromOffset(leftW, S(if thumb then 52 else 36)),
			Parent = panel,
		})
		UI.corner(row, S(8))
		UI.stroke(row, Theme.Colors.grey, S(1), 0.5)
		local x = S(10)
		if thumb then
			local t = UI.frame({
				BackgroundColor3 = Theme.Colors.panel,
				Position = UDim2.fromOffset(S(8), S(6)),
				Size = UDim2.fromOffset(S(70), S(40)),
				Parent = row,
			})
			UI.corner(t, S(6))
			UI.stroke(t, Theme.Colors.gold, S(1), 0.4)
			UI.text({
				Text = "BANK",
				Font = Theme.Fonts.display,
				TextSize = S(12),
				TextColor3 = Theme.Colors.gold,
				Size = UDim2.fromScale(1, 1),
				Parent = t,
			})
			x = S(88)
		end
		local label = UI.text({
			Text = entries[(chosen :: any)[key]].name,
			Font = Theme.Fonts.display,
			TextSize = S(16),
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(x, 0),
			Size = UDim2.new(1, -x - S(30), 1, 0),
			Parent = row,
		})
		UI.text({
			Text = "▼",
			TextSize = S(12),
			TextColor3 = Theme.Colors.grey,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -S(10), 0, 0),
			Size = UDim2.fromOffset(S(20), S(if thumb then 52 else 36)),
			Parent = row,
		})
		row.Activated:Connect(function()
			local i = (chosen :: any)[key] % #entries + 1;
			(chosen :: any)[key] = i
			label.Text = entries[i].name
			UI.punch(row, 0.96, 0.15)
		end)
		y += S(if thumb then 62 else 46)
		return label
	end
	dropdown("MAP", Config.QueueMaps, "mapIndex", true)
	dropdown("DIFFICULTY", Config.QueueDifficulties, "diffIndex", false)

	-- Right column: info panel.
	local infoX = S(20) + leftW + S(16)
	local info = UI.frame({
		BackgroundColor3 = Theme.Colors.panel,
		Position = UDim2.fromOffset(infoX, S(56)),
		Size = UDim2.new(1, -infoX - S(20), 0, H - S(56) - S(76)),
		Parent = panel,
	})
	UI.corner(info, S(10))
	UI.pad(info, S(12), S(10), S(12), S(10))
	UI.list(info, Enum.FillDirection.Vertical, S(6))
	local function infoLine(k: string, val: string, color: Color3, order: number)
		UI.text({
			Text = k,
			TextSize = S(10),
			TextColor3 = Theme.Colors.grey,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, 0, 0, S(12)),
			LayoutOrder = order * 2,
			Parent = info,
		})
		UI.text({
			Text = val,
			Font = Theme.Fonts.display,
			TextSize = S(18),
			TextColor3 = color,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, 0, 0, S(22)),
			LayoutOrder = order * 2 + 1,
			Parent = info,
		})
	end
	infoLine("PERSONAL TOP WAVE", string.format("WAVE %d", tonumber(v.topWave) or 0), Theme.Colors.gold, 1)
	infoLine("GOLD MULTIPLIER", string.format("x%.1f", tonumber(v.goldMult) or 1), Theme.Colors.gold, 2)
	infoLine("MODIFIERS", tostring(v.modifiers or "NONE"), Theme.Colors.text, 3)

	local create = UI.button({
		Text = "CREATE",
		Font = Theme.Fonts.display,
		TextSize = S(22),
		TextColor3 = Theme.Colors.bg,
		BackgroundColor3 = Theme.Colors.blue,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -S(16)),
		Size = UDim2.new(1, -S(40), 0, S(48)),
		Parent = panel,
	})
	UI.corner(create, S(12))
	UI.stroke(create, Theme.Colors.black, S(2), 0.4)
	create.Activated:Connect(function()
		UI.punch(create, 0.92, 0.2)
		UI.sound(Theme.Sounds.legendary, 1.2, 0.5)
		Remotes.QueueAction:FireServer("create", {
			partySize = chosen.partySize,
			mapId = Config.QueueMaps[chosen.mapIndex].id,
			difficultyId = Config.QueueDifficulties[chosen.diffIndex].id,
		})
		closeCreate()
	end)
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
		BackgroundColor3 = Theme.Colors.panel,
		Size = UDim2.fromOffset(S(340), S(74)),
		Parent = hub.queueSlot,
	})
	UI.corner(card, S(12))
	UI.stroke(card, Theme.Colors.blue, S(2))
	local map = mapById(v.settings and v.settings.mapId)
	local diff = diffById(v.settings and v.settings.difficultyId)
	UI.text({
		Text = string.format("%s · %s", map.name, diff.name),
		Font = Theme.Fonts.display,
		TextSize = S(14),
		TextColor3 = Theme.Colors.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(S(12), S(6)),
		Size = UDim2.new(0.6, 0, 0, S(18)),
		Parent = card,
	})
	partyCountdown = UI.text({
		Text = "",
		Font = Theme.Fonts.display,
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
		s.BackgroundColor3 = if filled then Theme.Colors.gold else Theme.Colors.grey
		s.BackgroundTransparency = if filled then 0 else 0.6
	end
	local names = {}
	for _, m in members do
		local n = string.upper(tostring(m.name))
		if m.userId == v.owner then
			n ..= " ★"
		end
		table.insert(names, n)
	end
	if partyNames then
		partyNames.Text = table.concat(names, " · ")
	end
	if partyCountdown then
		if v.phase == "inProgress" then
			partyCountdown.Text = "STARTING"
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
	-- Countdown tick on the compact card.
	local lastShown = -1
	RunService.Heartbeat:Connect(function()
		local v = view
		local label = partyCountdown
		if not v or not label or v.card ~= "party" or v.phase ~= "open" then
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
