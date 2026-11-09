--!strict
-- Brief 10 / Rounds 27b-27d: the login streak modal. Opens on the first hub entry of a fake day (the server's Juice
-- "StreakOpen") and once at the start of every session even with nothing to claim (StreakOpenEverySession), before
-- anything else: MARLOW's announce card waits on the server until the day is claimed, the SKILLS first-time pulse
-- waits on ClientState.streakOpen.
-- The house's premium window (dark graded panel, sharp corners, condensed caps, a gold edge and a warm glow under the
-- header), the reference's format: DAILY STREAK with a gift mark and the IN A ROW counter, then one wide row of
-- reward cards, each tinted by what it holds (Gold amber, Arms crates blue, Mask crates purple, a RARE+ / EPIC+ crate
-- in its rarity, the CASH boost green, pass XP orange) with a halo behind the art and the amount in that colour:
--   claimed days       dimmed under a green tick
--   today              lifted, a gold TODAY band across the top, a soft breathing glow; CLAIM under the row
--   tomorrow           (today claimed) lifted, a green band with its countdown; GET DAY N NOW · R$ 29 beside the
--                      FREE IN countdown (the paid skip, StreakSkipsPerDay 0 = always offered)
--   the big days       gold edge and rays (7 / 14 / 21 / 28)
-- The row runs from the start of this week to its end plus StreakPeekDays (fogged), then a MORE card. The current day
-- sits in the centre when the row allows (it never scrolls past either end, so early in a week there is no gap on the
-- left). Drag it sideways (mouse or finger; the wheel does nothing); after a claim or a skip it glides to the new day.
-- A lost streak: STREAK LOST, today's card red with a RESTORE band, RESTORE · R$ 49 (VIP: FREE) and START OVER. An
-- unclaimed day cannot be dismissed (the X, Esc and B claim; START OVER when lost); with nothing to claim they close.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Clock = require(Shared:WaitForChild("Clock"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Crates = require(Shared:WaitForChild("Crates"))
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
local TILE = Color3.fromHex("17171D")
local EDGE = Color3.fromHex("33333C")
local GOLD = Color3.fromHex("E8B64C")
local BIG_EDGE = Color3.fromHex("F2C14E")
local INK = Color3.fromHex("0B0B0F")

type View = {
	state: string,
	day: number,
	count: number?,
	nextDay: number?,
	vip: boolean?,
	vipLeft: number?,
	price: number?,
	skipPrice: number?,
	canSkip: boolean?,
}

type Ui = {
	gui: ScreenGui,
	panel: GuiObject,
	edge: UIStroke,
	title: TextLabel,
	count: TextLabel,
	countBox: Frame,
	timerBox: Frame,
	timer: TextLabel,
	clip: Frame,
	strip: Frame,
	buttons: Frame,
	cardW: number,
	cardH: number,
	gap: number,
	btnH: number,
	T: (number) -> number,
	mobile: boolean,
}

type Timer = { label: TextLabel, prefix: string }

local ui: Ui? = nil
local sessionShown = false -- the session's open happened (the client's own pull never reopens it)
local busy = false
local claimFn: (() -> ())? = nil -- what X / Esc / B do
local renderToken = 0
local timers: { Timer } = {} -- countdown labels, refreshed every second

-- The row's scroll: the strip's x offset, eased toward a target; dragging writes it directly.
local scrollX = 0
local scrollTarget = 0
local scrollMin, scrollMax = 0, 0
local centeredN: number? = nil -- the day number in focus (a re-render glides from it to the new current day)
local dragging: InputObject? = nil
local dragStartX, dragStartScroll = 0, 0
local velocity = 0

local function untilTomorrow(): string
	local now = ClientState.fakeNow()
	local sec = math.max(0, Clock.nextDay(now) - now)
	return string.format("%dH %02dM %02dS", sec // 3600, (sec % 3600) // 60, sec % 60)
end

local function close()
	local u = ui
	ui = nil
	claimFn = nil
	busy = false
	timers = {}
	dragging = nil
	centeredN = nil
	renderToken += 1
	ClientState.streakOpen = false
	ClientState.lockMovement("streak", false)
	if u then
		u.gui:Destroy()
	end
	ClientState.Juice:Fire("StreakClosed", {})
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
				task.delay(Config.CrateExitHoldSec + 0.5, step)
			end)
		else
			step()
		end
	end
	step()
end

-- A card's colour: what it holds.
local function tintFor(r: StreakTrack.Entry?, day: number): Color3
	if not r then
		return EDGE
	elseif r.kind == "crate" then
		if (r.floor or 1) > 1 then
			return Rarity.color(r.floor or 3)
		end
		if r.id == "daily" then
			-- Round 27d: the daily crate in this week's tier colour (quality rises by week).
			local def = (Config.DailyCrateTierOdds :: any)[StreakTrack.crateTier(day)]
			return if def then Color3.fromHex(def.trim) else GOLD
		end
		return if r.id == "mask" then Color3.fromHex("A864E8") else Color3.fromHex("4D9FE8")
	elseif r.kind == "boost" then
		return Color3.fromHex("2FD46A")
	elseif r.kind == "passxp" then
		return Color3.fromHex("E8792A")
	end
	return GOLD
end

------------------------------------------------------------------ The card row
type Card = { day: number, n: number, kind: string } -- kind: past | today | done | next | future | peek

-- The days the row shows: this week's start .. its end plus StreakPeekDays, numbered by days in a row. Returns the
-- cards and the index of the one in focus (today, or tomorrow once today is claimed).
local function sequence(v: View): ({ Card }, number)
	local out: { Card } = {}
	local a = math.clamp(v.day, 1, StreakTrack.LENGTH)
	local n = math.max(1, tonumber(v.count) or 1)
	if v.state == "lost" then
		n = math.max(1, (tonumber(v.count) or 0) + 1)
	end
	local pos = (a - 1) % 7
	for i = pos, 1, -1 do
		if n - i >= 1 then
			table.insert(out, { day = a - i, n = n - i, kind = "past" })
		end
	end
	table.insert(out, { day = a, n = n, kind = if v.state == "claimed" then "done" else "today" })
	local anchor = #out
	local d = a
	local steps = (6 - pos) + math.max(0, Config.StreakPeekDays)
	for k = 1, steps do
		d = StreakTrack.nextDay(d)
		table.insert(out, {
			day = d,
			n = n + k,
			kind = if k == 1 and v.state == "claimed" then "next" elseif k > 6 - pos then "peek" else "future",
		})
	end
	if v.state == "claimed" and out[anchor + 1] then
		anchor += 1
	end
	return out, anchor
end

local function buildCard(u: Ui, c: Card, index: number, peekIndex: number, lost: boolean): Frame
	local S, T = UI.S, u.T
	local big = StreakTrack.isBig(c.day)
	local rewards = StreakTrack.rewards(c.day)
	local r = rewards[1]
	local tint = tintFor(r, c.day)
	local claimed = c.kind == "past" or c.kind == "done"
	local lifted = c.kind == "today" or c.kind == "next"
	local holder = UI.frame({
		Name = "Day" .. c.n,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset((index - 1) * (u.cardW + u.gap), 0),
		Size = UDim2.fromOffset(u.cardW, u.cardH),
		ZIndex = 4,
		Parent = u.strip,
	})
	local card = UI.frame({
		Name = "Card",
		BackgroundColor3 = Color3.new(1, 1, 1),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = true,
		ZIndex = 5,
		Parent = holder,
	})
	UI.corner(card, S(4))
	-- Graded fill: the content's colour up top, sinking to the tile colour.
	local top = if lost and c.kind == "today" then Theme.Colors.red else tint
	UI.new("UIGradient", {
		Color = ColorSequence.new(top:Lerp(TILE, if claimed then 0.82 else 0.62), TILE),
		Rotation = 90,
		Parent = card,
	})
	local edgeColor = if c.kind == "today" and lost
		then Theme.Colors.red
		elseif c.kind == "today" then GOLD
		elseif c.kind == "next" then GREEN
		elseif big then BIG_EDGE
		elseif claimed then EDGE
		else tint:Lerp(EDGE, 0.55)
	local stroke = UI.stroke(card, edgeColor, S(if lifted then 2.5 else 1.5), 0)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	if lifted then
		UI.new("UIScale", { Scale = 1.06, Parent = card })
		local glow, setGlow = Fx.glow(holder, edgeColor, S(4), 3)
		glow.ZIndex = 3
		local token = renderToken
		Fx.pulse(setGlow, function()
			return renderToken == token and holder.Parent ~= nil
		end, 1.6, 0.5, 1.2)
	end
	-- The band across the top: TODAY (RESTORE when lost), tomorrow's countdown, or DAY N.
	local bandH = T(24)
	local band = UI.frame({
		Name = "Band",
		BackgroundColor3 = if c.kind == "today" then edgeColor elseif c.kind == "next" then GREEN else INK,
		BackgroundTransparency = if lifted then 0 else 0.55,
		Size = UDim2.new(1, 0, 0, bandH),
		ZIndex = 9,
		Parent = card,
	})
	local bandText = UI.text({
		Text = if c.kind == "today"
			then (if lost then "RESTORE" else "TODAY")
			elseif c.kind == "next" then untilTomorrow()
			else "DAY " .. c.n,
		FontFace = Theme.Fonts.display,
		TextSize = T(if lifted then 16 else 15),
		TextColor3 = if c.kind == "today" and not lost
			then INK
			elseif lifted then Theme.Colors.white
			elseif big then BIG_EDGE
			else Theme.Colors.textDim,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 10,
		Parent = band,
	})
	if c.kind == "next" then
		table.insert(timers, { label = bandText, prefix = "" })
	end
	-- The reward, big, on a halo of its colour (rays on the big days).
	local artSize = math.floor(math.min(u.cardW * 0.74, (u.cardH - bandH) * 0.52))
	local artY = bandH + (u.cardH - bandH - T(30)) / 2
	local halo = UI.frame({
		BackgroundColor3 = tint,
		BackgroundTransparency = if claimed then 0.92 else 0.78,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, artY),
		Size = UDim2.fromOffset(math.floor(artSize * 1.2), math.floor(artSize * 1.2)),
		ZIndex = 5,
		Parent = card,
	})
	UI.corner(halo, artSize)
	if big and not claimed then
		local rays = Fx.rays(card, BIG_EDGE, 10, math.floor(artSize * 1.6), 5, 0.2)
		rays.Position = UDim2.new(0.5, 0, 0, artY)
	end
	if r then
		local artId = if r.kind == "crate" and r.id == "daily"
			then Crates.dailyId(StreakTrack.crateTier(c.day))
			else r.id
		local art = ItemArt.draw(card, { kind = r.kind, id = artId, amount = r.amount, sec = r.sec }, artSize, 6)
		art.AnchorPoint = Vector2.new(0.5, 0.5)
		art.Position = UDim2.new(0.5, 0, 0, artY)
		if claimed then
			ItemArt.fade(art, 0.6)
		end
	end
	UI.text({
		Text = if r then StreakTrack.short(r) else "",
		FontFace = Theme.Fonts.display,
		TextSize = T(22),
		TextColor3 = if claimed then Theme.Colors.textDim else tint:Lerp(Color3.new(1, 1, 1), 0.35),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -S(6)),
		Size = UDim2.new(1, 0, 0, T(26)),
		ZIndex = 8,
		Parent = card,
	})
	-- A second reward rides as a chip under the band (day 14's / 28's Gold).
	local extra = rewards[2]
	if extra then
		local chip = UI.text({
			Text = "+" .. StreakTrack.short(extra),
			FontFace = Theme.Fonts.display,
			TextSize = T(13),
			TextColor3 = INK,
			BackgroundTransparency = 0,
			BackgroundColor3 = tintFor(extra, c.day),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -S(6), 0, bandH + S(6)),
			Size = UDim2.fromOffset(0, T(18)),
			AutomaticSize = Enum.AutomaticSize.X,
			ZIndex = 9,
			Parent = card,
		})
		UI.pad(chip, S(4), 0, S(4), 0)
		UI.corner(chip, S(3))
	end
	-- Claimed: a green tick over the dimmed art.
	if claimed then
		local d = math.floor(artSize * 0.5)
		local badge = UI.frame({
			BackgroundColor3 = GREEN,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, artY),
			Size = UDim2.fromOffset(d, d),
			ZIndex = 11,
			Parent = card,
		})
		UI.corner(badge, d)
		UI.stroke(badge, INK, S(2), 0)
		Icons.fit(badge, "check", 0.66, Theme.Colors.white).ZIndex = 12
	end
	if c.kind == "today" and not lost then
		Fx.shine(card, 2.4)
	end
	-- Past this week: fogged, deeper toward the MORE card.
	if c.kind == "peek" then
		local fog = UI.frame({
			BackgroundColor3 = INK,
			BackgroundTransparency = math.clamp(0.5 - peekIndex * 0.12, 0.15, 0.5),
			Size = UDim2.fromScale(1, 1),
			ZIndex = 14,
			Parent = card,
		})
		local _ = fog
	end
	return card
end

local function buildMore(u: Ui, index: number)
	local S, T = UI.S, u.T
	local card = UI.frame({
		Name = "More",
		BackgroundColor3 = TILE,
		BackgroundTransparency = 0.3,
		Position = UDim2.fromOffset((index - 1) * (u.cardW + u.gap), 0),
		Size = UDim2.fromOffset(u.cardW, u.cardH),
		ZIndex = 5,
		Parent = u.strip,
	})
	UI.corner(card, S(4))
	UI.stroke(card, EDGE, S(1.5), 0.3)
	UI.text({
		Text = "?",
		FontFace = Theme.Fonts.display,
		TextSize = T(52),
		TextColor3 = Color3.fromHex("4A4A56"),
		Size = UDim2.fromScale(1, 0.8),
		ZIndex = 6,
		Parent = card,
	})
	UI.text({
		Text = "MORE",
		FontFace = Theme.Fonts.display,
		TextSize = T(18),
		TextColor3 = Theme.Colors.textDim,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -S(8)),
		Size = UDim2.new(1, 0, 0, T(22)),
		ZIndex = 6,
		Parent = card,
	})
end

-- The strip offset that puts card `index` (1-based) in the centre of the row, kept inside the row's ends.
local function centerOn(u: Ui, index: number): number
	local center = (index - 1) * (u.cardW + u.gap) + u.cardW / 2
	return math.clamp(u.clip.AbsoluteSize.X / 2 - center, scrollMin, scrollMax)
end

------------------------------------------------------------------ Rendering a view
local refreshView: () -> ()

local function render(v: View)
	local u = ui
	if not u then
		return
	end
	local rerender = centeredN ~= nil -- the window was already showing a row (glide from where it is)
	renderToken += 1
	timers = {}
	claimFn = nil
	busy = false
	local S, T = UI.S, u.T
	local lost = v.state == "lost"
	u.title.Text = if lost then "STREAK LOST" else "DAILY STREAK"
	u.title.TextColor3 = if lost then Theme.Colors.red else GOLD
	u.edge.Color = if lost then Theme.Colors.red else GOLD
	-- Round 27e: the next free day's countdown in the header, beside the counter (only with today claimed).
	u.timerBox.Visible = v.state == "claimed"
	if v.state == "claimed" then
		local prefix = '<font color="#9BA0A8">FREE IN</font>  '
		u.timer.Text = prefix .. untilTomorrow()
		table.insert(timers, { label = u.timer, prefix = prefix })
	end
	-- The counter shows the days in a row as they stand (a claim adds one when it lands).
	local shown = if v.state == "claim"
		then math.max(0, (tonumber(v.count) or 1) - 1)
		else math.max(1, tonumber(v.count) or 1)
	if u.count.Text ~= tostring(shown) then
		if u.count.Text ~= "" then
			UI.punch(u.countBox, 1.2, 0.3)
		end
		u.count.Text = tostring(shown)
	end
	u.count.TextColor3 = if lost then Theme.Colors.red else GOLD
	-- Cards.
	for _, ch in u.strip:GetChildren() do
		if ch:IsA("GuiObject") then
			ch:Destroy()
		end
	end
	local cards, anchor = sequence(v)
	local focusCard: Frame? = nil
	local peek = 0
	local fromIndex: number? = nil
	for i, c in cards do
		if c.kind == "peek" then
			peek += 1
		end
		local card = buildCard(u, c, i, peek, lost)
		if i == anchor then
			focusCard = card
		end
		if centeredN and c.n == centeredN then
			fromIndex = i
		end
	end
	buildMore(u, #cards + 1)
	-- Scroll: never past either end (no gap on the left early in a week); the focus card centred when it can be.
	local contentW = (#cards + 1) * (u.cardW + u.gap) - u.gap
	u.strip.Size = UDim2.fromOffset(contentW, u.cardH)
	local clipW = u.clip.AbsoluteSize.X
	local endPad = S(8)
	if contentW + endPad * 2 <= clipW then
		scrollMin = (clipW - contentW) / 2
		scrollMax = scrollMin
	else
		scrollMin = clipW - contentW - endPad
		scrollMax = endPad
	end
	scrollTarget = centerOn(u, anchor)
	-- A re-render with the old focus gone (START OVER) keeps the row where it was, so it visibly rolls back.
	if fromIndex then
		scrollX = centerOn(u, fromIndex)
	elseif not rerender then
		scrollX = scrollTarget
	end
	velocity = 0
	centeredN = cards[anchor].n
	local focusN = cards[anchor].n
	-- Buttons.
	for _, ch in u.buttons:GetChildren() do
		if ch:IsA("GuiObject") then
			ch:Destroy()
		end
	end
	local handles: { any } = {}
	local function setBusy(on: boolean)
		busy = on
		for _, h in handles do
			h.setEnabled(not on)
		end
	end
	local function mk(text: string, bg: Color3, w: number, order: number): TextButton
		local b, h = Fx.button(u.buttons, text, bg, Theme.Colors.white, UDim2.fromOffset(w, u.btnH), 6)
		b.TextSize = T(if u.mobile then 20 else 22)
		b.Selectable = true
		b.LayoutOrder = order
		table.insert(handles, h)
		return b
	end

	-- The server answered (a claim, a restore, a skip): punch the card, ding, play crates, show the claimed view.
	local function landed(res: any)
		if ui ~= u then
			return
		end
		if typeof(res) ~= "table" or not res.ok then
			setBusy(false)
			local reason = if typeof(res) == "table" then tostring(res.reason or "TRY AGAIN") else "TRY AGAIN"
			PurchaseSheet.toast(reason, Theme.Colors.red, true)
			if reason == "ALREADY CLAIMED" then
				refreshView()
			end
			return
		end
		-- START OVER: nothing was paid; the row rolls back to day 1, waiting for CLAIM.
		if res.reset then
			UI.sound(Fx.Sounds.whoosh, 0.8, 0.4)
			refreshView()
			return
		end
		UI.sound(Fx.Sounds.ding, 1, 0.6)
		Fx.haptic(0.4)
		local t = focusCard
		if t and t.Parent then
			UI.punch(t, 1.08, 0.25)
			local abs = t.AbsolutePosition + t.AbsoluteSize / 2 - u.panel.AbsolutePosition
			Fx.burst(u.panel, UDim2.fromOffset(abs.X, abs.Y), GOLD, 18, 30)
		end
		local crates = if typeof(res.crates) == "table" then res.crates else {}
		task.delay(Config.StreakClaimHoldSec, function()
			if ui ~= u then
				return
			end
			if #crates > 0 then
				u.gui.Enabled = false
				playCrates(crates, function()
					if ui == u then
						u.gui.Enabled = true
						refreshView()
					end
				end)
			else
				refreshView()
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
	local function buy(productId: string, context: string)
		if busy then
			return
		end
		setBusy(true)
		PurchaseSheet.open(productId, {
			context = context,
			onSuccess = function(data: any)
				landed(data)
			end,
			onClose = function(bought: boolean)
				if not bought and ui == u then
					setBusy(false)
				end
			end,
		})
	end

	local main: TextButton? = nil
	local wide = if u.mobile then S(330) else S(300)
	if v.state == "claim" then
		local claim = mk("CLAIM", GREEN, wide, 2)
		claim:SetAttribute("NavDefault", true) -- brief 11: CLAIM is the pad's only stop
		Fx.shine(claim)
		claim.Activated:Connect(function()
			invoke("claim")
		end)
		claimFn = function()
			invoke("claim")
		end
		main = claim
	elseif lost then
		local vipFree = v.vip == true and (tonumber(v.vipLeft) or 0) > 0
		local over = mk("START OVER", DARK, if u.mobile then S(200) else S(170), 1)
		local restore = mk(
			if vipFree then "RESTORE · FREE" else string.format("RESTORE · R$ %s", UI.fmtInt(tonumber(v.price) or 0)),
			GREEN,
			wide,
			2
		)
		Fx.shine(restore)
		restore.Activated:Connect(function()
			if vipFree then
				invoke("vip")
			else
				buy("streak_restore", "streak restore day " .. v.day)
			end
		end)
		over.Activated:Connect(function()
			invoke("over")
		end)
		claimFn = function()
			invoke("over")
		end
		main = restore
	else
		-- Nothing to claim: one action, the upsell (tomorrow's reward now for fake R$); the free countdown sits in the
		-- header beside IN A ROW (Round 27e).
		if v.canSkip then
			local skip = mk(
				string.format("GET DAY %d NOW · R$ %s", focusN, UI.fmtInt(tonumber(v.skipPrice) or 0)),
				GREEN,
				wide,
				2
			)
			Fx.shine(skip)
			skip.Activated:Connect(function()
				buy("streak_skip", "streak skip day " .. tostring(v.nextDay))
			end)
			main = skip
		end
		claimFn = close
	end
	if main and UserInputService.GamepadEnabled then
		GuiService.SelectedObject = main
	end
end

refreshView = function()
	task.spawn(function()
		local ok, v = pcall(function()
			return Remotes.StreakClaim:InvokeServer("view")
		end)
		if not ui then
			return
		end
		if ok and typeof(v) == "table" then
			render(v :: any)
		else
			close()
		end
	end)
end

------------------------------------------------------------------ The window
local function build(): Ui
	local S = UI.S
	local mobile = ClientState.isMobile
	-- Phones draw at about half the desktop scale: text reads the store's MobileStoreTextScale bigger there.
	local function T(n: number): number
		return if mobile then math.round(S(n) * (Config.MobileStoreTextScale or 1)) else S(n)
	end
	local g = UI.new("ScreenGui", {
		Name = "StreakModal",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 18, -- over the hub HUD and the scenes, under the crate scene, the debug panel and the sheet
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	}) :: ScreenGui
	local vp = (workspace.CurrentCamera :: Camera).ViewportSize
	local top = Fx.topInset()
	-- The dim takes every tap: nothing behind the modal is reachable while it is up.
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
	UI.tween(dim, { BackgroundTransparency = 0.45 }, 0.25)

	local pad = S(if mobile then 10 else 18)
	local headH = T(if mobile then 34 else 40)
	local btnH = if mobile then math.max(48, S(56)) else S(52)
	local vpad = S(10) -- room above and below the cards for the lifted ones and their glow
	local maxW = vp.X - 32
	local maxH = vp.Y - top - 16
	local w = if mobile then maxW else math.min(maxW, S(1040))
	local fixed = pad * 2 + headH + S(8) + vpad * 2 + S(10) + btnH
	local cardH = math.floor(if mobile then math.min(maxH - fixed, S(270)) else math.min(S(200), maxH - fixed))
	local cardW = math.floor(cardH * 0.72)
	local h = fixed + cardH
	local panel = UI.button({
		Name = "Panel",
		Text = "",
		Selectable = false,
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(1, 1, 1),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, math.floor(top / 2)),
		Size = UDim2.fromOffset(w, h),
		ClipsDescendants = true,
		ZIndex = 2,
		Parent = g,
	})
	UI.corner(panel, S(6))
	UI.new("UIGradient", {
		Color = ColorSequence.new(Color3.fromHex("23232D"), Color3.fromHex("0E0E13")),
		Rotation = 90,
		Parent = panel,
	})
	local edge = UI.stroke(panel, GOLD, S(1.5), 0.25)
	-- A warm glow under the header, fading down.
	local warm = UI.frame({
		BackgroundColor3 = GOLD,
		Size = UDim2.new(1, 0, 0, pad * 2 + headH + S(30)),
		ZIndex = 2,
		Parent = panel,
	})
	UI.new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.8),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = warm,
	})
	local scale = UI.new("UIScale", { Scale = 0.94, Parent = panel }) :: UIScale
	UI.tween(scale, { Scale = 1 }, 0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

	-- Header: the gift mark, DAILY STREAK, the IN A ROW counter, X.
	local mark = UI.frame({
		BackgroundColor3 = GOLD,
		Position = UDim2.fromOffset(pad, pad),
		Size = UDim2.fromOffset(headH, headH),
		ZIndex = 6,
		Parent = panel,
	})
	UI.corner(mark, S(4))
	Icons.fit(mark, "gift", 0.7, INK, Color3.fromHex("8A5A12")).ZIndex = 7
	local title = UI.text({
		Text = "DAILY STREAK",
		FontFace = Theme.Fonts.display,
		TextSize = T(if mobile then 28 else 34),
		TextColor3 = GOLD,
		TextXAlignment = Enum.TextXAlignment.Left,
		AutomaticSize = Enum.AutomaticSize.X,
		Position = UDim2.fromOffset(pad + headH + S(12), pad),
		Size = UDim2.fromOffset(0, headH),
		ZIndex = 6,
		Parent = panel,
	})
	-- Round 27e: the header's right side: the free countdown (only with today claimed), the counter, then X.
	local right = UI.frame({
		Name = "Right",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -(pad + headH + S(10)), 0, pad),
		Size = UDim2.fromOffset(0, headH),
		AutomaticSize = Enum.AutomaticSize.X,
		ZIndex = 6,
		Parent = panel,
	})
	UI.list(right, Enum.FillDirection.Horizontal, S(10), Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
	local timerBox = UI.frame({
		Name = "Timer",
		BackgroundColor3 = TILE,
		Size = UDim2.fromOffset(0, headH),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 1,
		Visible = false,
		ZIndex = 6,
		Parent = right,
	})
	UI.corner(timerBox, S(4))
	UI.stroke(timerBox, EDGE, S(1.5), 0)
	UI.pad(timerBox, S(12), 0, S(12), 0)
	local timer = UI.text({
		Text = "",
		RichText = true,
		FontFace = Theme.Fonts.display,
		TextSize = T(20),
		TextColor3 = Theme.Colors.white,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, headH),
		ZIndex = 7,
		Parent = timerBox,
	})
	local countBox = UI.frame({
		Name = "Count",
		BackgroundColor3 = Color3.fromHex("2A2210"),
		Size = UDim2.fromOffset(0, headH),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 2,
		ZIndex = 6,
		Parent = right,
	})
	UI.corner(countBox, S(4))
	UI.stroke(countBox, Color3.fromHex("B88A2E"), S(1.5), 0)
	UI.pad(countBox, S(12), 0, S(12), 0)
	UI.list(countBox, Enum.FillDirection.Horizontal, S(8), Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	local count = UI.text({
		Text = "",
		FontFace = Theme.Fonts.display,
		TextSize = T(28),
		TextColor3 = GOLD,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, headH),
		LayoutOrder = 1,
		ZIndex = 7,
		Parent = countBox,
	})
	UI.text({
		Text = "IN A ROW",
		FontFace = Theme.Fonts.display,
		TextSize = T(16),
		TextColor3 = Theme.Colors.text,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, headH),
		LayoutOrder = 2,
		ZIndex = 7,
		Parent = countBox,
	})
	local xBtn = UI.button({
		Name = "Close",
		Text = "",
		BackgroundColor3 = DARK,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -pad, 0, pad),
		Size = UDim2.fromOffset(headH, headH),
		ZIndex = 6,
		Parent = panel,
	})
	UI.corner(xBtn, S(4))
	Icons.fit(xBtn, "close", 0.5, Theme.Colors.white).ZIndex = 7
	Fx.interactive(xBtn)
	xBtn.Activated:Connect(function()
		local f = claimFn
		if f and not busy then
			f()
		end
	end)

	-- The row: a clipped window over a strip of cards we move ourselves (drag to scroll; no wheel).
	local rowY = pad + headH + S(8)
	local clip = UI.frame({
		Name = "Row",
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Active = true,
		Position = UDim2.fromOffset(0, rowY),
		Size = UDim2.new(1, 0, 0, cardH + vpad * 2),
		ZIndex = 4,
		Parent = panel,
	})
	local strip = UI.frame({
		Name = "Strip",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, vpad),
		Size = UDim2.fromOffset(0, cardH),
		ZIndex = 4,
		Parent = clip,
	})
	clip.InputBegan:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = input
			dragStartX = input.Position.X
			dragStartScroll = scrollX
			velocity = 0
		end
	end)

	local buttons = UI.frame({
		Name = "Buttons",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -pad),
		Size = UDim2.new(1, -pad * 2, 0, btnH),
		ZIndex = 5,
		Parent = panel,
	})
	UI.list(buttons, Enum.FillDirection.Horizontal, S(12), Enum.HorizontalAlignment.Center)

	UI.sound(Fx.Sounds.whoosh, 1, 0.35)
	return {
		gui = g,
		panel = panel,
		edge = edge,
		title = title,
		count = count,
		countBox = countBox,
		timerBox = timerBox,
		timer = timer,
		clip = clip,
		strip = strip,
		buttons = buttons,
		cardW = cardW,
		cardH = cardH,
		gap = S(12),
		btnH = btnH,
		T = T,
		mobile = mobile,
	}
end

function StreakModal.isOpen(): boolean
	return ui ~= nil
end

function StreakModal.open(v: View)
	if not Config.StreakEnabled or typeof(v) ~= "table" then
		return
	end
	if v.state ~= "claim" and v.state ~= "lost" and v.state ~= "claimed" then
		return
	end
	if ui then
		-- Already up: a new day (or a fresh push) re-renders in place, unless a claim is in flight.
		if not busy then
			render(v)
		end
		return
	end
	sessionShown = true
	ClientState.streakOpen = true
	ClientState.lockMovement("streak", true)
	ui = build()
	task.defer(function()
		-- The row's width is known after a frame; place the focus card without a glide.
		if ui then
			centeredN = nil
			render(v)
		end
	end)
end

function StreakModal.init()
	ClientState.streakOpen = false
	ClientState.Juice:Connect(function(name: string, data: any)
		if name == "StreakOpen" then
			StreakModal.open(data)
		end
	end)
	-- Esc / B: claim (START OVER when lost); with nothing to claim they close.
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if not ui or busy or PurchaseSheet.isOpen() or CrateScene.isRunning() then
			return
		end
		if (input.KeyCode == Enum.KeyCode.Escape and not gameProcessed) or input.KeyCode == Enum.KeyCode.ButtonB then
			local f = claimFn
			if f then
				f()
			end
		end
	end)
	-- Dragging the row.
	UserInputService.InputChanged:Connect(function(input: InputObject)
		local d = dragging
		if not d or not ui then
			return
		end
		if
			input == d
			or (
				d.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseMovement
			)
		then
			local x = dragStartScroll + (input.Position.X - dragStartX)
			-- A soft give past either end.
			if x > scrollMax then
				x = scrollMax + (x - scrollMax) * 0.35
			elseif x < scrollMin then
				x = scrollMin + (x - scrollMin) * 0.35
			end
			velocity = (x - scrollX) * 60
			scrollX = x
			scrollTarget = x
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		local d = dragging
		if d and (input == d or input.UserInputType == d.UserInputType) then
			dragging = nil
			-- A flick carries on a little, then settles inside the ends.
			scrollTarget = math.clamp(scrollX + velocity * 0.18, scrollMin, scrollMax)
		end
	end)
	RunService.RenderStepped:Connect(function(dt: number)
		local u = ui
		if not u then
			return
		end
		if not dragging then
			scrollX += (scrollTarget - scrollX) * math.min(1, dt * 9)
		end
		u.strip.Position = UDim2.fromOffset(math.round(scrollX), u.strip.Position.Y.Offset)
	end)
	-- The countdowns tick.
	task.spawn(function()
		while true do
			task.wait(1)
			for _, t in timers do
				if t.label.Parent then
					t.label.Text = t.prefix .. untilTomorrow()
				end
			end
		end
	end)
	-- The server pushes the modal on join; this client also asks once its profile has synced, in case the push
	-- arrived before this module was listening (the session's open, with nothing to claim too).
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 20 do
			local sync = ClientState.sync
			if sync and (sync :: any).profile and ClientState.inHub() then
				break
			end
			task.wait(0.5)
		end
		task.wait(Config.StreakOpenDelaySec + 0.5)
		if ui or sessionShown or not Config.StreakOpenEverySession then
			return
		end
		local ok, v = pcall(function()
			return Remotes.StreakClaim:InvokeServer("view")
		end)
		if ok and v and ClientState.inHub() and not ui and not sessionShown then
			StreakModal.open(v)
		end
	end)
end

return StreakModal
