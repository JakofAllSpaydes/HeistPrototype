--!strict
-- The in-run scoreboard: hold Tab on PC, or tap the wave bar on mobile (tap again or anywhere outside to
-- close). A translucent panel over the game (which keeps running, nothing is blocked): header WAVE N ·
-- TIME · stars · ◆ BANKED · $ CASH, then one row per party member in MVP order (level and class icon,
-- state dot, kills, cash, bags, jobs, downs, revives, MVP score), your own row highlighted. Reads
-- StateSync.roster, which the server rebuilds every RosterSyncSec.
-- Under the rows: your three daily Jobs and the weekly bounty as small paper cards (the JOBS board's look): title in
-- dark ink, a progress bar with the count. Done and unclaimed: green bar, green rim, a green check badge, a breathing
-- glow. Claimed: the sheet greys and lies flat, ink fades, a blue check badge. The bounty is the tan poster with a
-- red double rule, set a little apart. Cards cascade in on open; live progress tweens the bar in place.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Classes = require(Shared:WaitForChild("Classes"))
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local JobPool = require(Shared:WaitForChild("JobPool"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local Hint = require(script.Parent:WaitForChild("Hint"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local Icons = require(script.Parent:WaitForChild("UI"):WaitForChild("Icons"))
local Fx = require(script.Parent:WaitForChild("Store"):WaitForChild("Fx"))

local Scoreboard = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui: ScreenGui? = nil
local panel: Frame? = nil
local header: TextLabel? = nil
local rowsFrame: Frame? = nil
local open = false
local rowH = 0

-- Job cards: the strip lives across re-renders (rows rebuild every sync) so the entrance and the glow keep running.
type CardRef = {
	id: string,
	progress: number,
	target: number,
	barH: number,
	fill: Frame,
	count: TextLabel,
	track: Frame,
	fillTween: Tween?,
}
local jobsStrip: Frame? = nil
local jobsStamp = "" -- the strip's structure (ids, done, claimed, layout); a change rebuilds it
local jobsEntrance = false -- the next build cascades the cards in (the first one after opening)
local cardRefs: { CardRef } = {}

local COLS = {
	{ title = "CREW", w = 0.30, align = Enum.TextXAlignment.Left },
	{ title = "KILLS", w = 0.10, align = Enum.TextXAlignment.Center },
	{ title = "CASH", w = 0.14, align = Enum.TextXAlignment.Center },
	{ title = "BAGS", w = 0.09, align = Enum.TextXAlignment.Center },
	{ title = "JOBS", w = 0.09, align = Enum.TextXAlignment.Center },
	{ title = "DOWNS", w = 0.09, align = Enum.TextXAlignment.Center },
	{ title = "REVIVES", w = 0.09, align = Enum.TextXAlignment.Center },
	{ title = "MVP", w = 0.10, align = Enum.TextXAlignment.Right },
}

local function fmtClock(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

local function stars(heat: number): string
	local full = math.floor(heat)
	local half = heat - full >= 0.5
	return string.rep("★", full)
		.. (if half then "½" else "")
		.. string.rep("☆", 5 - full - (if half then 1 else 0))
end

------------------------------------------------------------------ Job cards
-- Paper and ink from the JOBS board: text on paper is dark ink; state lives in the bar, the rim, the badge, the glow.
local PAPER = Color3.fromHex("F4EBD3")
local POSTER = Color3.fromHex("EAD7AC")
local SETTLED = Color3.fromHex("C9C4B8")
local INK = Color3.fromHex("241C16")
local WANTED = Color3.fromHex("C8323C")
local PAID = Color3.fromHex("2B4C8C")
local GREEN = Color3.fromHex("2FB75A")
local FILL = Color3.fromHex("F0A02E")
local FILL_DONE = Color3.fromHex("3FC060")
local TRACK = Color3.fromHex("3A2E24")
local PIN = Color3.fromHex("E8554D")
local TILT = { -1.4, 1, -0.7, 1.1 }

-- The player's Jobs in board order: the three dailies, then the bounty.
local function jobItems(): { { e: any, def: any, weekly: boolean } }
	local sync = ClientState.sync
	local prof: any = sync and sync.profile
	local jobs = prof and prof.jobs
	local out = {}
	if typeof(jobs) ~= "table" then
		return out
	end
	for _, key in { "daily", "bounty" } do
		local list = jobs[key]
		if typeof(list) == "table" then
			for i, e in list do
				local def = JobPool.ById[tostring(e.id)]
				if def and (key == "daily" or i == 1) then
					table.insert(out, { e = e, def = def, weekly = key == "bounty" })
				end
			end
		end
	end
	return out
end

-- Any progress at all shows at least a round nub.
local function fillSize(k: number, barH: number): UDim2
	return if k > 0 then UDim2.new(k, math.floor(barH * (1 - k)), 1, 0) else UDim2.fromScale(0, 1)
end

-- A round badge on the card's top-right corner with a check drawn from two bars.
local function checkBadge(parent: Instance, color: Color3, z: number): Frame
	local S = UI.S
	local d = S(22)
	local b = UI.frame({
		Name = "Badge",
		BackgroundColor3 = color,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -S(3), 0, S(3)),
		Size = UDim2.fromOffset(d, d),
		ZIndex = z,
		Parent = parent,
	})
	UI.corner(b, d // 2)
	UI.stroke(b, Theme.Colors.white, S(2), 0)
	for _, leg in { { 0.36, 0.58, 0.32, 45 }, { 0.58, 0.47, 0.56, -50 } } do
		local f = UI.frame({
			BackgroundColor3 = Theme.Colors.white,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(leg[1], leg[2]),
			Size = UDim2.new(leg[3], 0, 0, math.max(2, S(3))),
			Rotation = leg[4],
			ZIndex = z + 1,
			Parent = b,
		})
		UI.corner(f, S(1))
	end
	return b
end

-- One card: holder (placed by the strip) > Lift (tilt; the cascade moves it) > Shadow, Glow, Paper.
local function jobCard(parent: Frame, item: any, slot: number, pos: Vector2, w: number, h: number): (Frame, CardRef)
	local S = UI.S
	local def: any = item.def
	local target = def.target
	local progress = math.min(tonumber(item.e.progress) or 0, target)
	local claimed = item.e.claimed == true
	local done = progress >= target
	local waiting = done and not claimed
	local holder = UI.frame({
		Name = "Job" .. slot,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(pos.X, pos.Y),
		Size = UDim2.fromOffset(w, h),
		-- A glowing card sits under its neighbours so its glow never washes over their paper.
		ZIndex = if waiting then 1 else 2,
		Parent = parent,
	})
	local lift = UI.frame({
		Name = "Lift",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Rotation = if done or claimed then 0 else (TILT[slot] or 0),
		Parent = holder,
	})
	local shadow = UI.frame({
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = if claimed then 0.8 else 0.55,
		Position = if claimed then UDim2.fromOffset(S(1), S(2)) else UDim2.fromOffset(S(3), S(4)),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = lift,
	})
	UI.corner(shadow, S(5))
	if waiting then
		local _g, setGlow = Fx.glow(lift, FILL_DONE, S(5), 2)
		Fx.pulse(setGlow, function()
			return open and lift.Parent ~= nil
		end, Config.JobClaimPulseSec, 0.8, 1.6)
	end
	local base = if item.weekly then POSTER else PAPER
	local paper = UI.frame({
		Name = "Paper",
		BackgroundColor3 = if claimed then base:Lerp(SETTLED, 0.6) else base,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		Parent = lift,
	})
	UI.corner(paper, S(5))
	if waiting then
		UI.stroke(paper, GREEN, S(2.5), 0)
	elseif item.weekly then
		UI.stroke(paper, WANTED, S(2), if claimed then 0.65 else 0.1)
	else
		UI.stroke(paper, Fx.shade(base, -0.35), S(1), 0.3)
	end
	UI.new("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromHex("E2E2E2")),
		Rotation = 90,
		Parent = paper,
	})
	if item.weekly then
		-- The poster's inner rule.
		local ring = UI.frame({
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -S(7), 1, -S(7)),
			ZIndex = 4,
			Parent = paper,
		})
		UI.corner(ring, S(3))
		UI.stroke(ring, WANTED, S(1), if claimed then 0.75 else 0.35)
	end
	local pin = UI.frame({
		BackgroundColor3 = PIN,
		BackgroundTransparency = if claimed then 0.5 else 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, S(5)),
		Size = UDim2.fromOffset(S(9), S(9)),
		ZIndex = 6,
		Parent = paper,
	})
	UI.corner(pin, S(5))
	UI.stroke(pin, Color3.fromHex("7A1E1A"), S(1), if claimed then 0.5 else 0)
	-- Title: dark ink, as big as two lines allow.
	local inkT = if claimed then 0.45 else 0
	local barH = S(20)
	local padX, top, bottom = S(9), S(12), S(9)
	local title = UI.text({
		Text = def.title,
		FontFace = Theme.Fonts.display,
		TextColor3 = INK,
		TextTransparency = inkT,
		TextWrapped = true,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(padX, top),
		Size = UDim2.new(1, -(padX + (if done then S(14) else padX)), 0, h - top - bottom - barH - S(5)),
		ZIndex = 6,
		Parent = paper,
	})
	UI.new("UITextSizeConstraint", { MaxTextSize = S(17), MinTextSize = S(9), Parent = title })
	-- The bar: dark inset track, saturated fill, the count inside.
	local track = UI.frame({
		Name = "Track",
		BackgroundColor3 = TRACK,
		BackgroundTransparency = if claimed then 0.45 else 0,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, padX, 1, -bottom),
		Size = UDim2.new(1, -padX * 2, 0, barH),
		ZIndex = 6,
		Parent = paper,
	})
	UI.corner(track, barH // 2)
	UI.stroke(track, Color3.fromHex("140F0B"), S(1.5), if claimed then 0.5 else 0)
	local k = math.clamp(progress / math.max(target, 1), 0, 1)
	local fill = UI.frame({
		Name = "Fill",
		BackgroundColor3 = if claimed then Fx.shade(SETTLED, -0.3) elseif done then FILL_DONE else FILL,
		Size = if jobsEntrance then UDim2.fromScale(0, 1) else fillSize(k, barH),
		ZIndex = 7,
		Parent = track,
	})
	UI.corner(fill, barH // 2)
	UI.new("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200)),
		Rotation = 90,
		Parent = fill,
	})
	local ref: CardRef = {
		id = tostring(item.e.id),
		progress = progress,
		target = target,
		barH = barH,
		fill = fill,
		count = nil :: any,
		track = track,
		fillTween = nil,
	}
	if jobsEntrance then
		ref.fillTween = UI.tween(
			fill,
			{ Size = fillSize(k, barH) },
			Config.ScoreJobFillSec,
			Enum.EasingStyle.Quart,
			Enum.EasingDirection.Out,
			(slot - 1) * Config.ScoreJobStaggerSec + 0.15
		)
	end
	local count = UI.text({
		Text = UI.fmtInt(progress) .. " / " .. UI.fmtInt(target),
		FontFace = Theme.Fonts.display,
		TextScaled = true,
		TextColor3 = Theme.Colors.white,
		TextTransparency = if claimed then 0.35 else 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -S(8), 1, -S(4)),
		ZIndex = 8,
		Parent = track,
	})
	UI.new("UITextSizeConstraint", { MaxTextSize = S(14), MinTextSize = S(8), Parent = count })
	UI.stroke(count, Color3.new(0, 0, 0), S(1.5), if claimed then 0.5 else 0.1)
	ref.count = count
	if waiting then
		checkBadge(paper, GREEN, 9)
	elseif claimed then
		checkBadge(paper, PAID, 9)
	end
	return holder, ref
end

-- Lays the strip out at `y` on the panel and returns its height (0 when there are no Jobs). Rebuilds the cards when
-- the structure changed; otherwise only the bars and counts move.
local function paintJobs(p: Frame, y: number): number
	local S = UI.S
	local items = jobItems()
	if #items == 0 then
		if jobsStrip then
			jobsStrip:Destroy()
		end
		jobsStrip, jobsStamp, cardRefs = nil, "", {}
		return 0
	end
	local stripW = p.Size.X.Offset - S(32)
	local gap, groupGap = S(10), S(18)
	local n = #items
	local hasGroup = items[1] and not items[1].weekly and items[n].weekly
	local extra = if hasGroup then groupGap - gap else 0
	-- One row of cards; a narrow panel folds to two columns.
	local cols = n
	local cardW = math.floor((stripW - gap * (n - 1) - extra) / n)
	if cardW < S(108) and n > 2 then
		cols, extra = 2, 0
		cardW = math.floor((stripW - gap) / 2)
	end
	local cardH = S(Config.ScoreJobCardH)
	local rows = math.ceil(n / cols)
	local topPad = S(8) -- room for the pins and badges
	local stripH = topPad + rows * cardH + (rows - 1) * gap
	local parts = { tostring(cols), tostring(stripW) }
	for _, it in items do
		local pr = tonumber(it.e.progress) or 0
		table.insert(parts, string.format("%s:%s:%s", it.def.id, tostring(pr >= it.def.target), tostring(it.e.claimed)))
	end
	local stamp = table.concat(parts, "|")
	local strip = jobsStrip
	if strip and strip.Parent == p and stamp == jobsStamp and #cardRefs == n then
		-- Live progress: the bar tweens, the count updates, a small bump when it moves up.
		for i, it in items do
			local ref = cardRefs[i]
			local pr = math.min(tonumber(it.e.progress) or 0, ref.target)
			if pr ~= ref.progress then
				local up = pr > ref.progress
				ref.progress = pr
				ref.count.Text = UI.fmtInt(pr) .. " / " .. UI.fmtInt(ref.target)
				if ref.fillTween then
					ref.fillTween:Cancel()
				end
				ref.fillTween = UI.tween(
					ref.fill,
					{ Size = fillSize(math.clamp(pr / math.max(ref.target, 1), 0, 1), ref.barH) },
					Config.ScoreJobFillSec,
					Enum.EasingStyle.Quart
				)
				if up then
					UI.punch(ref.track, 1.08, 0.25)
				end
			end
		end
	else
		local wasOpen: { [string]: boolean } = {}
		for _, ref in cardRefs do
			if ref.progress < ref.target then
				wasOpen[ref.id] = true
			end
		end
		if strip then
			strip:Destroy()
		end
		local s = UI.frame({
			Name = "JobsStrip",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(stripW, stripH),
			Parent = p,
		})
		jobsStrip, jobsStamp, cardRefs = s, stamp, {}
		local holders: { GuiObject } = {}
		local x = 0
		for i, it in items do
			local row, col = (i - 1) // cols, (i - 1) % cols
			if cols == n then
				if hasGroup and i == n then
					x += extra
				end
			else
				x = col * (cardW + gap)
			end
			local holder, ref = jobCard(s, it, i, Vector2.new(x, topPad + row * (cardH + gap)), cardW, cardH)
			if cols == n then
				x += cardW + gap
			end
			table.insert(holders, holder)
			table.insert(cardRefs, ref)
			-- A Job that finished while the board was up pops once.
			if not jobsEntrance and wasOpen[ref.id] and ref.progress >= ref.target then
				local paper = holder:FindFirstChild("Paper", true)
				if paper and paper:IsA("GuiObject") then
					UI.punch(paper, 1.15, 0.3)
				end
			end
		end
		if jobsEntrance then
			jobsEntrance = false
			Fx.cascade(holders, Config.ScoreJobStaggerSec, 14)
		end
	end
	local st = jobsStrip :: Frame
	st.Position = UDim2.fromOffset(S(16), y)
	st.Size = UDim2.fromOffset(stripW, stripH)
	return stripH
end

local function build()
	if gui then
		gui:Destroy()
	end
	jobsStrip, jobsStamp, cardRefs = nil, "", {}
	local S = UI.S
	local g = UI.new("ScreenGui", {
		Name = "Scoreboard",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 8,
		Enabled = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	}) :: ScreenGui
	gui = g
	-- Phone width: the panel never runs past the screen.
	local vp = (game:GetService("Workspace").CurrentCamera :: Camera).ViewportSize
	local W = math.min(S(620), math.floor(vp.X * 0.94))
	local p = UI.frame({
		Name = "Panel",
		BackgroundColor3 = Theme.Colors.bg,
		BackgroundTransparency = 0.25,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.46),
		Size = UDim2.fromOffset(W, S(120)),
		Active = false,
		Parent = g,
	})
	UI.corner(p, S(14))
	UI.stroke(p, Theme.Colors.gold, S(2), 0.3)
	panel = p
	header = UI.text({
		Text = "",
		FontFace = Theme.Fonts.display,
		TextSize = S(15),
		TextColor3 = Theme.Colors.text,
		Position = UDim2.fromOffset(0, S(10)),
		Size = UDim2.new(1, 0, 0, S(22)),
		Parent = p,
	})
	UI.stroke(header :: TextLabel, Theme.Colors.black, S(1.5), 0.3)
	-- Column titles.
	local titles = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(S(16), S(38)),
		Size = UDim2.new(1, -S(32), 0, S(16)),
		Parent = p,
	})
	local x = 0
	local tableW = W - S(32)
	for _, col in COLS do
		UI.text({
			Text = col.title,
			TextSize = S(10),
			TextColor3 = Theme.Colors.grey,
			TextXAlignment = col.align,
			Position = UDim2.fromOffset(x + (if col.align == Enum.TextXAlignment.Left then S(8) else 0), 0),
			Size = UDim2.new(col.w, 0, 1, 0),
			Parent = titles,
		})
		x += math.floor(tableW * col.w)
	end
	rowsFrame = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(S(16), S(58)),
		Size = UDim2.new(1, -S(32), 0, 0),
		Parent = p,
	})
	UI.list(rowsFrame :: Frame, Enum.FillDirection.Vertical, S(4))
	rowH = S(28)
	-- Brief 5: VOTE TO PAUSE from the scoreboard (P works anywhere in a run).
	local pauseBtn = UI.button({
		Name = "Pause",
		Text = if ClientState.isMobile then "VOTE PAUSE" else "VOTE PAUSE [P]",
		FontFace = Theme.Fonts.display,
		TextSize = S(10),
		TextColor3 = Theme.Colors.bg,
		BackgroundColor3 = Theme.Colors.grey,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -S(10), 0, S(10)),
		Size = UDim2.fromOffset(S(96), S(20)),
		ZIndex = 3,
		Parent = p,
	})
	UI.corner(pauseBtn, S(6))
	if not ClientState.isMobile then
		-- Brief 11: a pad has no pause key (the button itself is selectable with the pad).
		Hint.bind(pauseBtn, function()
			return if Hint.gamepad() then "VOTE PAUSE" else Hint.text("VOTE PAUSE [{key}]", "pause", "run")
		end)
	end
	pauseBtn.Activated:Connect(function()
		local pv = ClientState.sync and (ClientState.sync :: any).pause
		if pv and not pv.active then
			Remotes.PauseAction:FireServer(if pv.myVote then "unvote" else "vote")
			UI.punch(pauseBtn, 0.9, 0.15)
		end
	end)
	local closeHint = UI.text({
		Text = "TAP TO CLOSE",
		TextSize = S(9),
		TextColor3 = Theme.Colors.grey,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -S(4)),
		Size = UDim2.new(1, 0, 0, S(12)),
		Parent = p,
	})
	if not ClientState.isMobile then
		Hint.bind(closeHint, function()
			return if Hint.gamepad()
				then Hint.text("{key} TO CLOSE", "scoreboard", "run")
				else Hint.text("RELEASE {key} TO CLOSE", "scoreboard", "run")
		end)
	end
end

local function paint()
	local sync = ClientState.sync
	local p, hdr, rf = panel, header, rowsFrame
	if not sync or not p or not hdr or not rf then
		return
	end
	local roster: any = sync.roster
	local S = UI.S
	hdr.Text = string.format(
		"WAVE %d%s  ·  TIME %s  ·  %s  ·  ◆ BANKED %s  ·  $ CASH %s",
		tonumber(sync.wave) or 1,
		if roster and typeof(roster.zone) == "string" then "  ·  " .. roster.zone else "",
		fmtClock(if roster then tonumber(roster.survivedSec) or 0 else 0),
		stars(tonumber(sync.heat) or 0),
		UI.fmtNum(if roster then tonumber(roster.banked) or 0 else tonumber(sync.banked) or 0),
		string.sub(UI.fmtCash(if roster then tonumber(roster.cash) or 0 else 0), 2)
	) .. (if roster and roster.vault then "  ·  VAULT OPEN" else "")
	hdr.TextColor3 = if roster and roster.vault then Theme.Colors.amber else Theme.Colors.text
	for _, c in rf:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local rows: { any } = if roster then roster.rows or {} else {}
	local tableW = p.AbsoluteSize.X - S(32)
	if tableW <= 0 then
		tableW = S(620) - S(32)
	end
	for i, row in rows do
		local mine = row.userId == player.UserId
		local frame = UI.frame({
			BackgroundColor3 = if mine then Theme.Colors.panel2 else Theme.Colors.panel,
			BackgroundTransparency = if mine then 0.1 else 0.4,
			Size = UDim2.new(1, 0, 0, rowH - S(4)),
			LayoutOrder = i,
			Parent = rf,
		})
		UI.corner(frame, S(6))
		if mine then
			UI.stroke(frame, Theme.Colors.gold, S(1.5), 0.2)
		end
		local class = Classes.ById[tostring(row.classId)] or Classes.ById[Classes.Default]
		local x = 0
		-- Name cell: state dot, class circle with the class emblem, LV n NAME.
		local dot = UI.frame({
			BackgroundColor3 = if row.state == "standing"
				then Theme.Colors.cash
				elseif row.state == "downed" then Theme.Colors.red
				else Theme.Colors.grey,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, S(6), 0.5, 0),
			Size = UDim2.fromOffset(S(8), S(8)),
			Parent = frame,
		})
		UI.corner(dot, S(4))
		local circle = UI.frame({
			BackgroundColor3 = Color3.fromHex(class.color),
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, S(18), 0.5, 0),
			Size = UDim2.fromOffset(S(16), S(16)),
			Parent = frame,
		})
		UI.corner(circle, S(8))
		Icons.fit(circle, class.id, 0.74, Theme.Colors.bg, Color3.fromHex(class.color), class.glyph)
		UI.text({
			Text = UI.vipName(
				string.format("LV %d  %s", tonumber(row.level) or 1, string.upper(tostring(row.name))),
				row.vip
			),
			RichText = true,
			FontFace = Theme.Fonts.display,
			TextSize = S(12),
			TextColor3 = if mine then Theme.Colors.gold else Theme.Colors.text,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(S(40), 0),
			Size = UDim2.new(COLS[1].w, -S(40), 1, 0),
			Parent = frame,
		})
		x += math.floor(tableW * COLS[1].w)
		local values = {
			{ tostring(row.kills or 0), Theme.Colors.text },
			{ UI.fmtCash(tonumber(row.cash) or 0), Theme.Colors.cash },
			{ tostring(row.bags or 0), Theme.Colors.gold },
			{ tostring(row.jobs or 0), Theme.Colors.blue },
			{ tostring(row.downs or 0), Theme.Colors.malus },
			{ tostring(row.revives or 0), Theme.Colors.text },
			{ tostring(math.round(tonumber(row.score) or 0)), Theme.Colors.gold },
		}
		for k, v in values do
			local col = COLS[k + 1]
			UI.text({
				Text = v[1],
				TextSize = S(12),
				TextColor3 = v[2],
				TextXAlignment = col.align,
				Position = UDim2.fromOffset(x - (if col.align == Enum.TextXAlignment.Right then S(8) else 0), 0),
				Size = UDim2.new(col.w, 0, 1, 0),
				Parent = frame,
			})
			x += math.floor(tableW * col.w)
		end
	end
	-- Brief 6 / Round 17: your daily Jobs and the bounty as small paper cards under the rows.
	local rowsEnd = S(58) + rowH * math.max(#rows, 1)
	local stripH = paintJobs(p, rowsEnd + S(2))
	p.Size = UDim2.fromOffset(p.Size.X.Offset, rowsEnd + (if stripH > 0 then S(2) + stripH else 0) + S(18))
end

function Scoreboard.setOpen(on: boolean)
	if open == on then
		return
	end
	if on and ClientState.inHub() then
		return
	end
	open = on
	ClientState.scoreboardOpen = on -- brief 11: Create toggles it on a pad (Input.lua)
	local g = gui
	if not g then
		return
	end
	g.Enabled = on
	if on then
		jobsEntrance, jobsStamp = true, "" -- rebuild the cards and cascade them in
		paint()
		local p = panel
		if p then
			UI.punch(p, 1.04, 0.2)
		end
		UI.sound(Theme.Sounds.toast, 1.1, 0.25)
	end
end

function Scoreboard.isOpen(): boolean
	return open
end

function Scoreboard.init()
	build()
	local HUD = require(script.Parent:WaitForChild("HUD"))
	HUD.Rebuilt:Connect(function()
		build()
		if open then
			local g = gui
			if g then
				g.Enabled = true
			end
			paint()
		end
	end)
	ClientState.Changed:Connect(function()
		if open then
			paint()
		end
	end)
	-- PC: hold Tab. Mobile: the wave bar fires ToggleScoreboard; a tap anywhere else closes it.
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if input.KeyCode == Enum.KeyCode.Tab and not gameProcessed then
			Scoreboard.setOpen(true)
		elseif open and ClientState.isMobile and input.UserInputType == Enum.UserInputType.Touch then
			-- A tap outside the panel closes it (the wave bar's own tap toggles through the juice event).
			local p = panel
			if p then
				local pos = input.Position
				local a, b = p.AbsolutePosition, p.AbsolutePosition + p.AbsoluteSize
				if pos.X < a.X or pos.X > b.X or pos.Y < a.Y or pos.Y > b.Y then
					task.defer(Scoreboard.setOpen, false)
				end
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.Tab then
			Scoreboard.setOpen(false)
		end
	end)
	ClientState.Juice:Connect(function(name: string, data: any)
		if name == "ToggleScoreboard" then
			Scoreboard.setOpen(not open)
		elseif name == "ScoreboardHold" then
			-- Brief 11: the pad's Create (Input.lua): a tap toggles, a hold peeks; a run only.
			local on = typeof(data) == "table" and data.on == true
			Scoreboard.setOpen(on and not ClientState.inHub())
		elseif name == "HubEnter" or name == "RunEndBegin" then
			Scoreboard.setOpen(false)
		end
	end)
end

return Scoreboard
