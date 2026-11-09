--!strict
-- Brief 10: the login streak modal. Opens on the first hub entry of a fake day (the server's Juice "StreakOpen", or
-- this client's own pull once the profile has synced), before anything else: MARLOW's announce card waits on the
-- server until the day is claimed, and the SKILLS first-time pulse waits on ClientState.streakOpen.
--   DAILY STREAK · DAY 12   the 28-day track as four rows of seven: this week's row expanded (reward art and
--                           amount per day, claimed ticked, today lit and pulsing, future dim, day 7 / 14 / 21 / 28 in
--                           gold frames), the other weeks collapsed to dots ending on their big reward; CLAIM
--   STREAK LOST             the track dimmed at the day you were on, RESTORE · R$ 49 (VIP: RESTORE · FREE (1 left
--                           this month)) and START OVER
-- There is no way out without claiming: the X, Esc and B claim (START OVER on a lost streak). A claim plays the
-- loot ding and a burst on today's tile; a day with a crate opens it in the crate room, then the modal closes.
-- Nothing about the streak stays on the HUD afterwards.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local StreakTrack = require(Shared:WaitForChild("StreakTrack"))

local Client = script.Parent.Parent
local ClientState = require(Client:WaitForChild("ClientState"))
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local Icons = require(Client:WaitForChild("UI"):WaitForChild("Icons"))
local PurchaseSheet = require(Client:WaitForChild("PurchaseSheet"))
local Store = Client:WaitForChild("Store")
local Fx = require(Store:WaitForChild("Fx"))
local ItemArt = require(Store:WaitForChild("ItemArt"))
local CrateScene = require(Store:WaitForChild("CrateScene"))

local StreakModal = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GREEN = Color3.fromHex("2FB75A")
local DARK = Color3.fromHex("2E3135")
local PANEL = Color3.fromHex("121216")
local TILE = Color3.fromHex("1C1C22")

type View = { state: string, day: number, vip: boolean?, vipLeft: number?, price: number? }

local gui: ScreenGui? = nil
local busy = false
local claimFn: (() -> ())? = nil -- what X / Esc / B do

local function close()
	local g = gui
	gui = nil
	claimFn = nil
	busy = false
	ClientState.streakOpen = false
	ClientState.lockMovement("streak", false)
	if g then
		g:Destroy()
	end
	ClientState.Juice:Fire("StreakClosed", {})
end

-- A day's rewards as one tile body (the first reward's art; a second reward adds a small "+").
local function tileArt(parent: Frame, day: number, size: number, z: number): Frame?
	local list = StreakTrack.rewards(day)
	local r = list[1]
	if not r then
		return nil
	end
	local art = ItemArt.draw(parent, { kind = r.kind, id = r.id, amount = r.amount, sec = r.sec }, size, z)
	art.AnchorPoint = Vector2.new(0.5, 0.5)
	art.Position = UDim2.fromScale(0.5, 0.46)
	return art
end

local function shortLine(day: number): string
	local parts = {}
	for _, r in StreakTrack.rewards(day) do
		table.insert(parts, StreakTrack.short(r))
	end
	return table.concat(parts, " + ")
end

local function fullLine(day: number): string
	local parts = {}
	for _, r in StreakTrack.rewards(day) do
		table.insert(parts, StreakTrack.name(r))
	end
	return table.concat(parts, " + ")
end

-- Plays each crate the day opened, one after another, then calls done.
local function playCrates(crates: { any }, done: () -> ())
	local i = 0
	local function step()
		i += 1
		local c = crates[i]
		if not c then
			done()
			return
		end
		if typeof(c.results) == "table" and #c.results > 0 then
			CrateScene.play(tostring(c.crateId), c.results, nil, function()
				task.delay(0.5, step)
			end)
		else
			step()
		end
	end
	step()
end

function StreakModal.isOpen(): boolean
	return gui ~= nil
end

function StreakModal.open(view: View)
	if gui or not Config.StreakEnabled then
		return
	end
	if typeof(view) ~= "table" or (view.state ~= "claim" and view.state ~= "lost") then
		return
	end
	local S = UI.S
	local mobile = ClientState.isMobile
	-- Phones draw at about half the desktop scale: text reads the store's MobileStoreTextScale bigger there.
	local function T(n: number): number
		return if mobile then math.round(S(n) * (Config.MobileStoreTextScale or 1)) else S(n)
	end
	local lost = view.state == "lost"
	local day = math.clamp(math.floor(tonumber(view.day) or 1), 1, StreakTrack.LENGTH)
	ClientState.streakOpen = true
	ClientState.lockMovement("streak", true)

	local g = UI.new("ScreenGui", {
		Name = "StreakModal",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 18, -- over the hub HUD and the scenes, under the crate scene, the debug panel and the sheet
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	}) :: ScreenGui
	gui = g
	local vp = (workspace.CurrentCamera :: Camera).ViewportSize
	local top = Fx.topInset()
	-- The dim takes every tap: nothing behind the modal is reachable until the day is claimed.
	local dim = UI.button({
		Name = "Dim",
		Text = "",
		Selectable = false,
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = g,
	})
	UI.tween(dim, { BackgroundTransparency = 0.3 }, 0.25)

	-- Sizes: the panel fills the space under the top bar on a phone, a fixed card on desktop.
	local pad = S(if mobile then 14 else 20)
	local gap = S(if mobile then 6 else 8)
	local maxW = vp.X - 32
	-- A phone gets the whole width (a 16px gutter each side, capped) and tiles as big as the height allows.
	local w = if mobile then math.min(maxW, 820) else math.min(maxW, S(820))
	local tile = math.floor(math.min(if mobile then S(150) else S(100), (w - pad * 2 - gap * 6) / 7))
	local titleH = T(if mobile then 36 else 42)
	local lineH = T(if mobile then 24 else 26)
	local rowH = T(if mobile then 24 else 26) -- a collapsed week
	local btnH = if mobile then math.max(56, S(60)) else S(58)
	local trackH = tile + T(22) + 3 * (rowH + gap)
	local h = pad + titleH + S(10) + trackH + S(10) + lineH + S(12) + btnH + pad
	local maxH = vp.Y - top - 8
	if h > maxH then
		-- Short phone screens: shrink the expanded tiles until the card fits.
		tile = math.max(S(52), tile - (h - maxH))
		trackH = tile + T(22) + 3 * (rowH + gap)
		h = math.min(maxH, pad + titleH + S(10) + trackH + S(10) + lineH + S(12) + btnH + pad)
	end
	local panel = UI.button({
		Name = "Panel",
		Text = "",
		Selectable = false,
		AutoButtonColor = false,
		BackgroundColor3 = PANEL,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, math.floor(top / 2)),
		Size = UDim2.fromOffset(w, h),
		ZIndex = 2,
		Parent = g,
	})
	UI.corner(panel, S(6))
	UI.stroke(panel, if lost then Theme.Colors.red else Theme.Colors.gold, S(1.5), 0.35)
	local scale = UI.new("UIScale", { Scale = 0.9, Parent = panel }) :: UIScale
	UI.tween(scale, { Scale = 1 }, 0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

	-- Title.
	UI.text({
		Text = if lost then "STREAK LOST" else "DAILY STREAK",
		FontFace = Theme.Fonts.display,
		TextSize = T(if mobile then 28 else 34),
		TextColor3 = if lost then Theme.Colors.red else Theme.Colors.gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(pad, pad),
		Size = UDim2.new(0.5, -pad, 0, titleH),
		ZIndex = 3,
		Parent = panel,
	})
	UI.text({
		Text = if lost then string.format("YOU WERE ON DAY %d", day) else string.format("DAY %d", day),
		FontFace = Theme.Fonts.display,
		TextSize = T(if mobile then 24 else 30),
		TextColor3 = Theme.Colors.white,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -(pad + titleH + S(10)), 0, pad),
		Size = UDim2.new(0.5, -(pad + titleH), 0, titleH),
		ZIndex = 3,
		Parent = panel,
	})
	-- X: claims too (there is no dismiss).
	local xBtn = UI.button({
		Name = "Close",
		Text = "",
		BackgroundColor3 = DARK,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -pad, 0, pad),
		Size = UDim2.fromOffset(titleH, titleH),
		ZIndex = 3,
		Parent = panel,
	})
	UI.corner(xBtn, S(4))
	local xIcon = Icons.fit(xBtn, "close", 0.5, Theme.Colors.white)
	xIcon.ZIndex = 4
	Fx.interactive(xBtn)

	-- The track.
	local trackY = pad + titleH + S(10)
	local track = UI.frame({
		Name = "Track",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(pad, trackY),
		Size = UDim2.new(1, -pad * 2, 0, trackH),
		ZIndex = 3,
		Parent = panel,
	})
	UI.list(track, Enum.FillDirection.Vertical, gap, Enum.HorizontalAlignment.Center)
	local thisWeek = StreakTrack.week(day)
	local todayTile: Frame? = nil
	local todayCheck: Frame? = nil
	local pulse = true
	for week = 1, 4 do
		local first = (week - 1) * 7 + 1
		if week == thisWeek then
			-- Expanded: seven tiles.
			local row = UI.frame({
				Name = "Week" .. week,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, tile + T(22)),
				LayoutOrder = week,
				ZIndex = 3,
				Parent = track,
			})
			UI.list(row, Enum.FillDirection.Horizontal, gap, Enum.HorizontalAlignment.Center)
			for d = first, first + 6 do
				local claimed = d < day
				local isToday = d == day
				local big = StreakTrack.isBig(d)
				local holder = UI.frame({
					BackgroundTransparency = 1,
					Size = UDim2.fromOffset(tile, tile + T(22)),
					LayoutOrder = d,
					ZIndex = 3,
					Parent = row,
				})
				local t = UI.frame({
					Name = "Day" .. d,
					BackgroundColor3 = if big then Color3.fromHex("2A2210") else TILE,
					Size = UDim2.fromOffset(tile, tile),
					ZIndex = 4,
					Parent = holder,
				})
				UI.corner(t, S(4))
				local stroke = UI.stroke(
					t,
					if isToday and not lost
						then Theme.Colors.gold
						elseif isToday and lost then Theme.Colors.red
						elseif big then Color3.fromHex("B88A2E")
						else Color3.fromHex("33333C"),
					S(if isToday then 3 else 1.5),
					0
				)
				UI.text({
					Text = tostring(d),
					FontFace = Theme.Fonts.display,
					TextSize = T(if mobile then 13 else 15),
					TextColor3 = if big then Theme.Colors.gold else Theme.Colors.textDim,
					TextXAlignment = Enum.TextXAlignment.Left,
					Position = UDim2.fromOffset(S(5), S(2)),
					Size = UDim2.fromOffset(S(30), S(16)),
					ZIndex = 6,
					Parent = t,
				})
				local art = tileArt(t, d, math.floor(tile * 0.62), 5)
				if art and (claimed or not isToday or lost) then
					ItemArt.fade(art, if claimed then 0.6 elseif lost then 0.55 else 0.35)
				end
				UI.text({
					Text = shortLine(d),
					FontFace = Theme.Fonts.display,
					TextSize = T(if mobile then 14 else 17),
					TextColor3 = if isToday and not lost
						then Theme.Colors.white
						elseif claimed then Color3.fromHex("6E6E78")
						else Theme.Colors.textDim,
					Position = UDim2.new(0, 0, 1, -T(20)),
					Size = UDim2.new(1, 0, 0, T(20)),
					ZIndex = 4,
					Parent = holder,
				})
				if claimed then
					local check = Icons.fit(t, "check", 0.5, Theme.Colors.health)
					check.ZIndex = 8
				end
				if isToday then
					todayTile = t
					if lost then
						t.BackgroundTransparency = 0.4
					else
						UI.new("UIScale", { Name = "Pulse", Parent = t })
						task.spawn(function()
							while pulse and t.Parent do
								local k = (math.sin(os.clock() * 4) + 1) / 2
								stroke.Thickness = S(2 + k * 2)
								task.wait()
							end
						end)
					end
				end
			end
		else
			-- Collapsed: WEEK N, seven dots, the week's big reward at the end.
			local row = UI.frame({
				Name = "Week" .. week,
				BackgroundColor3 = TILE,
				BackgroundTransparency = 0.2,
				Size = UDim2.new(1, 0, 0, rowH),
				LayoutOrder = week,
				ZIndex = 3,
				Parent = track,
			})
			UI.corner(row, S(3))
			UI.text({
				Text = "WEEK " .. week,
				FontFace = Theme.Fonts.display,
				TextSize = T(if mobile then 14 else 16),
				TextColor3 = Theme.Colors.textDim,
				TextXAlignment = Enum.TextXAlignment.Left,
				Position = UDim2.fromOffset(S(8), 0),
				Size = UDim2.new(0, S(80), 1, 0),
				ZIndex = 4,
				Parent = row,
			})
			local dot = math.floor(rowH * 0.42)
			for d = first, first + 6 do
				local claimed = d < day
				local c = UI.frame({
					BackgroundColor3 = if claimed
						then (if lost then Color3.fromHex("4E6B56") else Theme.Colors.health)
						else Color3.fromHex("3A3A44"),
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0, S(90) + (d - first) * (dot + S(10)), 0.5, 0),
					Size = UDim2.fromOffset(dot, dot),
					ZIndex = 4,
					Parent = row,
				})
				UI.corner(c, dot)
			end
			local bigDay = first + 6
			UI.text({
				Text = string.format("DAY %d · %s", bigDay, fullLine(bigDay)),
				FontFace = Theme.Fonts.display,
				TextSize = T(if mobile then 14 else 16),
				TextColor3 = if bigDay < day then Color3.fromHex("6E6E78") else Theme.Colors.gold,
				TextXAlignment = Enum.TextXAlignment.Right,
				TextTruncate = Enum.TextTruncate.AtEnd,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -S(8) - rowH, 0, 0),
				Size = UDim2.new(1, -(S(100) + 7 * (dot + S(10)) + rowH), 1, 0),
				ZIndex = 4,
				Parent = row,
			})
			local wellBox = UI.frame({
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -S(4), 0.5, 0),
				Size = UDim2.fromOffset(rowH, rowH),
				ZIndex = 4,
				Parent = row,
			})
			local art = tileArt(wellBox, bigDay, rowH, 5)
			if art and bigDay < day then
				ItemArt.fade(art, 0.6)
			end
		end
	end

	-- Today's reward in words.
	local lineY = trackY + trackH + S(10)
	UI.text({
		Text = if lost
			then string.format("RESTORE TO KEEP DAY %d · %s", day, fullLine(day))
			else "TODAY · " .. fullLine(day),
		FontFace = Theme.Fonts.display,
		TextSize = T(if mobile then 18 else 22),
		TextColor3 = if lost then Theme.Colors.textDim else Theme.Colors.white,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(pad, lineY),
		Size = UDim2.new(1, -pad * 2, 0, lineH),
		ZIndex = 3,
		Parent = panel,
	})

	-- Buttons.
	local btnY = lineY + lineH + S(12)
	local row = UI.frame({
		Name = "Buttons",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(pad, btnY),
		Size = UDim2.new(1, -pad * 2, 0, btnH),
		ZIndex = 3,
		Parent = panel,
	})
	UI.list(row, Enum.FillDirection.Horizontal, S(12), Enum.HorizontalAlignment.Center)

	local buttons: { any } = {}
	local function setBusy(on: boolean)
		busy = on
		for _, b in buttons do
			b.setEnabled(not on)
		end
	end

	-- The server answered a claim (or a restore): stamp today's tile, ding, open any crates, close.
	local function landed(res: any)
		if gui ~= g then
			return
		end
		if typeof(res) ~= "table" or not res.ok then
			setBusy(false)
			local reason = if typeof(res) == "table" then tostring(res.reason or "TRY AGAIN") else "TRY AGAIN"
			PurchaseSheet.toast(reason, Theme.Colors.red, true)
			if reason == "ALREADY CLAIMED" then
				close()
			end
			return
		end
		pulse = false
		claimFn = nil
		UI.sound(Fx.Sounds.ding, 1, 0.6)
		Fx.haptic(0.4)
		local t = todayTile
		if t and t.Parent and not lost and (tonumber(res.day) or day) == day then
			if not todayCheck then
				todayCheck = Icons.fit(t, "check", 0.5, Theme.Colors.health);
				(todayCheck :: Frame).ZIndex = 8
			end
			UI.punch(t, 1.15, 0.25)
			local abs = t.AbsolutePosition + t.AbsoluteSize / 2 - panel.AbsolutePosition
			Fx.burst(panel, UDim2.fromOffset(abs.X, abs.Y), Theme.Colors.gold, 14, 9)
		end
		local crates = if typeof(res.crates) == "table" then res.crates else {}
		task.delay(Config.StreakClaimHoldSec, function()
			if gui ~= g then
				return
			end
			if #crates > 0 then
				g.Enabled = false
				playCrates(crates, close)
			else
				UI.tween(dim, { BackgroundTransparency = 1 }, 0.2)
				UI.tween(scale, { Scale = 0.92 }, 0.2)
				task.delay(0.2, close)
			end
		end)
	end

	local function invoke(action: string)
		if busy then
			return
		end
		setBusy(true)
		task.spawn(function()
			local ok, res = pcall(function()
				return Remotes.StreakClaim:InvokeServer(action)
			end)
			landed(if ok then res else nil)
		end)
	end

	local function mkButton(text: string, bg: Color3, frac: number): TextButton
		local b, handle = Fx.button(row, text, bg, Theme.Colors.white, UDim2.new(frac, 0, 1, 0), 4)
		b.TextSize = T(if mobile then 24 else 26)
		b.Selectable = true
		table.insert(buttons, handle)
		return b
	end

	if not lost then
		local claim = mkButton("CLAIM", GREEN, 1)
		Fx.shine(claim)
		claim.Activated:Connect(function()
			invoke("claim")
		end)
		claimFn = function()
			invoke("claim")
		end
		if UserInputService.GamepadEnabled then
			GuiService.SelectedObject = claim
		end
	else
		local vipFree = view.vip == true and (tonumber(view.vipLeft) or 0) > 0
		local price = tonumber(view.price) or Config.StreakRestorePrice
		local restore = mkButton(
			if vipFree
				then string.format("RESTORE · FREE (%d LEFT THIS MONTH)", tonumber(view.vipLeft) or 1)
				else string.format("RESTORE · R$ %s", UI.fmtInt(price)),
			GREEN,
			0.6
		)
		local over = mkButton("START OVER", DARK, 0.4)
		restore.Activated:Connect(function()
			if busy then
				return
			end
			if vipFree then
				invoke("vip")
				return
			end
			setBusy(true)
			PurchaseSheet.open("streak_restore", {
				context = "streak restore day " .. day,
				onSuccess = function(data: any)
					landed(data)
				end,
				onClose = function(bought: boolean)
					if not bought and gui == g then
						setBusy(false)
					end
				end,
			})
		end)
		over.Activated:Connect(function()
			invoke("over")
		end)
		claimFn = function()
			invoke("over")
		end
		if UserInputService.GamepadEnabled then
			GuiService.SelectedObject = restore
		end
	end
	xBtn.Activated:Connect(function()
		local f = claimFn
		if f then
			f()
		end
	end)
	UI.sound(Fx.Sounds.whoosh, 1, 0.35)
end

function StreakModal.init()
	ClientState.streakOpen = false
	ClientState.Juice:Connect(function(name: string, data: any)
		if name == "StreakOpen" then
			StreakModal.open(data)
		end
	end)
	-- Esc / B claim (there is no dismiss).
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if not gui or PurchaseSheet.isOpen() or CrateScene.isRunning() then
			return
		end
		if (input.KeyCode == Enum.KeyCode.Escape and not gameProcessed) or input.KeyCode == Enum.KeyCode.ButtonB then
			local f = claimFn
			if f then
				f()
			end
		end
	end)
	-- The server pushes the modal on join; this client also asks once its profile has synced, in case the push
	-- arrived before this module was listening.
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 20 do
			local sync = ClientState.sync
			if sync and (sync :: any).profile and ClientState.inHub() then
				break
			end
			task.wait(0.5)
		end
		task.wait(Config.StreakOpenDelaySec)
		if gui then
			return
		end
		local ok, view = pcall(function()
			return Remotes.StreakClaim:InvokeServer("view")
		end)
		if ok and view and ClientState.inHub() then
			StreakModal.open(view)
		end
	end)
end

return StreakModal
