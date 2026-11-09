--!strict
-- Run end on the client: the camera timeline (low front shot of the line, push in on the poses, hold for
-- the cash rain, cut to a tight 3/4 shot of the MVP with a slow orbit), the poses, the MVP stamp with gold
-- rays, then the summary panel (GOLD BANKED count-up, per-player rows, the level card above, PLAY AGAIN /
-- TO LOBBY with the auto countdown). Runs off the server clock in RunEndBegin.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Lines = require(Shared:WaitForChild("CrewCall"):WaitForChild("Lines")) -- brief 13
local Remotes = require(Shared:WaitForChild("Remotes"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local HUD = require(script.Parent:WaitForChild("HUD"))
local Juice = require(script.Parent:WaitForChild("Juice"))
local Spectate = require(script.Parent:WaitForChild("Spectate"))
local RunStartUI = require(script.Parent:WaitForChild("RunStartUI"))
local MinigameFrame = require(script.Parent:WaitForChild("Minigames"):WaitForChild("Frame"))
local LevelCard = require(script.Parent:WaitForChild("HUD"):WaitForChild("LevelCard"))
local LevelRewards = require(Shared:WaitForChild("LevelRewards"))
local Skills = require(Shared:WaitForChild("Skills"))

local RunEndUI = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = Workspace.CurrentCamera :: Camera

local data: any = nil
local fired: { [string]: boolean } = {}
local gui: ScreenGui? = nil
local dim: Frame? = nil
local stampFrame: Frame? = nil
local summaryShownAt = -1
local hiddenForMvp: { Instance } = {} -- the rest of the crew and their tags, hidden locally for the MVP beat
local bankedLabel: TextLabel? = nil
local xpAnim: any = nil -- the XP row and its fill segments (see showSummary)
local skillsLine: TextLabel? = nil -- brief 9: N SKILLS AFFORDABLE under the Gold gain (once the count-up lands)

local function fmtClock(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

local function xpToLevel(level: number): number
	return LevelRewards.xpToLevel(level)
end

-- Camera framing: characters stand about 5 studs tall with the root 3 up, so chest is ~3 and the head ~5.
local EYE_LINE = 2.6
local PAN_HEIGHT = 3.6
local PAN_FAR = 11
local PAN_NEAR = 8.5
local MVP_DIST = 6.5
local MVP_HEIGHT = 3.4

local function hideOthers(d: any)
	hiddenForMvp = {}
	for _, row in d.players do
		if d.mvp and row.userId == d.mvp.userId then
			continue
		end
		local char = RunStartUI.charFor(row)
		if not char then
			continue
		end
		for _, part in char:GetDescendants() do
			if part:IsA("BasePart") or part:IsA("Decal") then
				part.LocalTransparencyModifier = 1
				table.insert(hiddenForMvp, part)
			elseif part:IsA("BillboardGui") then
				part.Enabled = false
				table.insert(hiddenForMvp, part)
			end
		end
	end
end

local function showOthers()
	for _, inst in hiddenForMvp do
		if inst:IsA("BasePart") or inst:IsA("Decal") then
			inst.LocalTransparencyModifier = 0
		elseif inst:IsA("BillboardGui") then
			inst.Enabled = true
		end
	end
	hiddenForMvp = {}
end
local lobbyButton: TextButton? = nil
local chosen = false
local passAfterHub = false -- Round 19c: CLAIM IN PASS was pressed: the pass opens once we are back in the hub

local function easeOut(s: number): number
	s = math.clamp(s, 0, 1)
	return 1 - (1 - s) * (1 - s)
end

local function rootFor(entry: any): BasePart?
	local char = RunStartUI.charFor(entry)
	local root = char and char:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function once(beat: string, fn: () -> ())
	if not fired[beat] then
		fired[beat] = true
		fn()
	end
end

local function fmtCash(n: number): string
	return UI.fmtCash(n)
end

local function teardown()
	data = nil
	pcall(function()
		RunService:UnbindFromRenderStep("GHSRunEnd")
	end)
	if gui then
		gui:Destroy()
		gui = nil
	end
	showOthers()
	dim = nil
	stampFrame = nil
	bankedLabel = nil
	skillsLine = nil
	xpAnim = nil
	lobbyButton = nil
	summaryShownAt = -1
	chosen = false
end

local function finish()
	if not data then
		return
	end
	teardown()
	ClientState.cameraMode = "gameplay"
	ClientState.requestCameraYaw = 0
	ClientState.setBlock("cinematic", false)
	HUD.setMode(HUD.baseMode())
end

local function showMvp(d: any)
	local g = gui
	if not g or not d.mvp then
		return
	end
	local S = UI.S
	local frame = UI.frame({
		Name = "MvpStamp",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.3, 0),
		Size = UDim2.fromOffset(S(520), S(190)),
		ZIndex = 5,
		Parent = g,
	})
	stampFrame = frame
	local mvp = UI.text({
		Text = "MVP",
		FontFace = Theme.Fonts.display,
		TextSize = S(110),
		TextColor3 = Theme.Colors.gold,
		Size = UDim2.new(1, 0, 0, S(110)),
		Rotation = -8,
		ZIndex = 6,
		Parent = frame,
	})
	UI.stroke(mvp, Theme.Colors.black, S(4), 0.1)
	local name = UI.text({
		Text = string.upper(tostring(d.mvp.name)),
		FontFace = Theme.Fonts.display,
		TextSize = S(34),
		TextColor3 = Theme.Colors.text,
		Position = UDim2.fromOffset(0, S(112)),
		Size = UDim2.new(1, 0, 0, S(40)),
		ZIndex = 6,
		Parent = frame,
	})
	UI.stroke(name, Theme.Colors.black, S(2), 0.2)
	local stat = UI.text({
		Text = tostring(d.mvp.statLine),
		FontFace = Theme.Fonts.display,
		TextSize = S(24),
		TextColor3 = Theme.Colors.gold,
		Position = UDim2.fromOffset(0, S(152)),
		Size = UDim2.new(1, 0, 0, S(30)),
		ZIndex = 6,
		Parent = frame,
	})
	UI.stroke(stat, Theme.Colors.black, S(2), 0.2)
	UI.punch(frame, 2.2, 0.5)
	local center = frame.AbsolutePosition + frame.AbsoluteSize / 2
	Juice.rays(center, Theme.Colors.gold, 14, 300, 0.9)
	ClientState.Juice:Fire("RarityFlash", { color = Theme.Colors.gold, alpha = 0.4 })
	ClientState.Juice:Fire("Shake", { amp = 0.6, dur = 0.4 })
	UI.sound(Theme.Sounds.legendary, 1, 0.8)
	MinigameFrame.haptic(1)
	task.delay(0.3, function()
		MinigameFrame.haptic(0.8)
	end)
	-- The rest of the crew steps out of frame; the MVP gets a flex of their own under the stamp.
	hideOthers(d)
	local beats = d.beats
	local flex = if typeof(d.mvp.mvpAnim) == "string" then d.mvp.mvpAnim else Config.MvpAnimationId
	RunStartUI.playAnim(RunStartUI.charFor(d.mvp), flex, (beats.summary - beats.mvp) + 0.5, RunStartUI.EMOTE_PRIORITY)
end

local function showSummary(d: any)
	local g = gui
	if not g then
		return
	end
	local S = UI.S
	summaryShownAt = os.clock()
	showOthers()
	local dimFrame = dim
	if dimFrame then
		UI.tween(dimFrame, { BackgroundTransparency = 0.45 }, 0.4)
	end
	if stampFrame then
		for _, l in stampFrame:GetDescendants() do
			if l:IsA("TextLabel") then
				UI.tween(l, { TextTransparency = 1 }, 0.3)
			elseif l:IsA("UIStroke") then
				UI.tween(l, { Transparency = 1 }, 0.3)
			end
		end
	end

	local rows: { any } = d.players
	local n = #rows
	local vp = camera.ViewportSize
	local W = math.min(math.floor(vp.X * 0.9), S(700))
	local rowH = S(30)
	local headerH = S(114) -- the headline block (the level card floats above the panel); brief 9: +14 for the skills line
	local H = headerH + S(24) + rowH * n + S(72) + S(28)
	H = math.min(H, math.floor(vp.Y * 0.94))
	local panel = UI.frame({
		Name = "Summary",
		BackgroundColor3 = Theme.Colors.bg,
		BackgroundTransparency = 0.08,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 1.3, 0),
		Size = UDim2.fromOffset(W, H),
		ZIndex = 10,
		Parent = g,
	})
	UI.corner(panel, S(16))
	UI.stroke(panel, Theme.Colors.gold, S(3))
	UI.tween(panel, { Position = UDim2.fromScale(0.5, 0.5) }, 0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	UI.sound(Theme.Sounds.call, 1, 0.6)

	-- Headline: GOLD BANKED, one number: the team's gold bags plus the run payout and your side job gold, all
	-- of it paid to your profile. Cash is the per-run currency and sits in the rows.
	UI.text({
		Text = "GOLD BANKED",
		FontFace = Theme.Fonts.display,
		TextSize = S(16),
		TextColor3 = Theme.Colors.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(S(24), S(12)),
		Size = UDim2.fromOffset(S(300), S(20)),
		ZIndex = 11,
		Parent = panel,
	})
	bankedLabel = UI.text({
		Text = "◆ 0",
		FontFace = Theme.Fonts.display,
		TextSize = S(40),
		TextColor3 = Theme.Colors.gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(S(24), S(30)),
		Size = UDim2.fromOffset(S(360), S(46)),
		ZIndex = 11,
		Parent = panel,
	})
	-- Your own row: NEW BEST callouts under the headline when the run beat your top wave or top banked.
	local myRow: any = nil
	for _, row in rows do
		if row.userId == player.UserId then
			myRow = row
		end
	end
	local bests = {}
	if myRow and myRow.newBest then
		table.insert(bests, "★ NEW PERSONAL BEST WAVE")
	end
	if myRow and myRow.newBestBanked then
		table.insert(bests, "★ NEW BEST BANKED")
	end
	UI.text({
		Text = if #bests > 0 then table.concat(bests, "  ·  ") else "PAID TO YOUR PROFILE",
		FontFace = if #bests > 0 then Theme.Fonts.display else Theme.Fonts.body,
		TextSize = if #bests > 0 then S(13) else S(10),
		TextColor3 = if #bests > 0 then Theme.Colors.cash else Theme.Colors.grey,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(S(26), S(80)),
		Size = UDim2.fromOffset(S(400), S(14)),
		ZIndex = 11,
		Parent = panel,
	})
	-- Brief 9: the Skill Web breadcrumb, filled in when the count-up lands (the new balance decides N).
	skillsLine = UI.text({
		Name = "SkillsAffordable",
		Text = "",
		FontFace = Theme.Fonts.display,
		TextSize = S(12),
		TextColor3 = Theme.Colors.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(S(26), S(96)),
		Size = UDim2.fromOffset(S(400), S(14)),
		Visible = false,
		ZIndex = 11,
		Parent = panel,
	})
	-- WAVE N with the final star count beside it.
	local wavePill, waveLabel = UI.pill(
		panel,
		string.format(
			"WAVE %d · %s · ★ %s",
			d.wave or 1,
			fmtClock(tonumber(d.survivedSec) or 0),
			UI.fmtNum(tonumber(d.heat) or 0)
		),
		Theme.Colors.gold,
		Theme.Colors.bg,
		S(30),
		S(16)
	)
	wavePill.AnchorPoint = Vector2.new(1, 0)
	wavePill.Position = UDim2.new(1, -S(24), 0, S(36))
	wavePill.ZIndex = 11
	waveLabel.ZIndex = 12
	waveLabel.FontFace = Theme.Fonts.display
	-- Brief 13: how long the crew stood on the street before the breach, small under the time, when it was long.
	local idle = tonumber(d.idleBeforeBreachSec) or 0
	if idle > Config.BreachIdleShowSec then
		UI.text({
			Name = "IdleBeforeBreach",
			Text = string.format(Lines.preHeist.idleRow, fmtClock(idle)),
			FontFace = Theme.Fonts.display,
			TextSize = S(12),
			TextColor3 = Theme.Colors.grey,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -S(26), 0, S(70)),
			Size = UDim2.fromOffset(S(260), S(14)),
			ZIndex = 11,
			Parent = panel,
		})
	end
	-- Brief 7: the map and difficulty the run was on, small over the wave pill.
	if typeof(d.mapName) == "string" then
		UI.text({
			Text = string.format("%s · %s", d.mapName, tostring(d.difficultyName or "")),
			FontFace = Theme.Fonts.body,
			TextSize = S(11),
			TextColor3 = Theme.Colors.grey,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -S(26), 0, S(16)),
			Size = UDim2.fromOffset(S(260), S(14)),
			ZIndex = 11,
			Parent = panel,
		})
	end

	-- The level card floats above the panel (its own piece, not nested): hidden until the Gold count-up is
	-- done, then it drops in and the bar fills with `+N XP` counting on the right.
	local award = myRow and myRow.xp
	local mastery = myRow and myRow.mastery
	local masteryLines = if mastery and typeof(mastery.lines) == "table" then mastery.lines else {}
	if award then
		local card = LevelCard.build(g, W, false)
		-- The MASTERY line sits between the card and the panel when the run earned any.
		local masteryGap = if #masteryLines > 0 then S(24) else 0
		local cardY = -H / 2 - S(14) - masteryGap
		card.frame.AnchorPoint = Vector2.new(0.5, 1)
		card.frame.Position = UDim2.new(0.5, 0, 0.5, cardY - S(40))
		card.frame.Visible = false
		card.set(award.fromLevel, award.fromXp, xpToLevel(award.fromLevel), "", nil)
		-- Segments of the fill: each level crossed, then the last partial one.
		local segments = {}
		local level, x = award.fromLevel, award.fromXp
		for _ = 1, 200 do
			local need = xpToLevel(level)
			if level < award.toLevel then
				table.insert(segments, { level = level, from = x, to = need, need = need, levelUp = true })
				level += 1
				x = 0
			else
				table.insert(segments, { level = level, from = x, to = award.toXp, need = need, levelUp = false })
				break
			end
		end
		xpAnim = {
			card = card,
			cardY = cardY,
			segments = segments,
			gained = math.max(1, tonumber(award.gained) or 1),
			sub = if award.first then string.format("FIRST HEIST OF THE DAY ×%s", UI.fmtNum(award.mult or 2)) else nil,
			popped = {},
			shown = false,
			levelUps = award.levelUps or {},
			masteryLabel = nil :: TextLabel?,
			masteryTierUps = if mastery and typeof(mastery.tierUps) == "table" then mastery.tierUps else {},
			masteryPopped = false,
		}
		if #masteryLines > 0 then
			local parts = {}
			for _, l in masteryLines do
				table.insert(parts, string.format("%s +%d", tostring(l.name), tonumber(l.gained) or 0))
			end
			local label = UI.text({
				Text = "MASTERY   " .. table.concat(parts, "  ·  "),
				FontFace = Theme.Fonts.display,
				TextSize = S(14),
				TextColor3 = Theme.Colors.text,
				TextTruncate = Enum.TextTruncate.AtEnd,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 0.5, -H / 2 - S(6)),
				Size = UDim2.fromOffset(W, S(18)),
				Visible = false,
				ZIndex = 12,
				Parent = g,
			})
			UI.stroke(label, Theme.Colors.black, S(1.5), 0.3)
			xpAnim.masteryLabel = label
		end
	end

	-- Brief 6: the PASS XP bar under the panel, after the account XP bar has filled (CLAIM IN PASS opens the scene).
	local passAward = myRow and myRow.passXp
	if passAward then
		local PassSummary = require(script.Parent:WaitForChild("Pass"):WaitForChild("PassSummary")) :: any
		local delay = math.max(d.countUpSec or 1, 0.05) + 0.15 + (tonumber(d.xpFillSec) or 1.2) + 0.4
		-- Round 19c: CLAIM IN PASS = TO LOBBY, then the pass opens in the hub (not over the end-of-run set).
		PassSummary.show(g, W, UDim2.new(0.5, 0, 0.5, H / 2 + S(12)), passAward, delay, function()
			passAfterHub = true
			if not chosen then
				chosen = true
				Remotes.SummaryChoice:FireServer("lobby")
				UI.sound(Theme.Sounds.toast, 1.3, 0.5)
				local b = lobbyButton
				if b then
					b.Text = "BACK TO THE HUB…"
				end
			end
		end)
	end
	-- Brief 6: the Job ticks after the XP bars.
	local ticks = myRow and myRow.jobTicks
	if typeof(ticks) == "table" and #ticks > 0 then
		local JobSummary = require(script.Parent:WaitForChild("Jobs"):WaitForChild("JobSummary")) :: any
		local delay = math.max(d.countUpSec or 1, 0.05) + 0.15 + (tonumber(d.xpFillSec) or 1.2) + 1.6
		local y = H / 2 + S(12) + (if passAward then S(66) else 0)
		JobSummary.show(g, W, UDim2.new(0.5, 0, 0.5, y), ticks, delay)
	end

	-- Table.
	local cols = {
		{ title = "CREW", w = 0.34, align = Enum.TextXAlignment.Left },
		{ title = "KILLS", w = 0.13, align = Enum.TextXAlignment.Center },
		{ title = "JOBS", w = 0.13, align = Enum.TextXAlignment.Center },
		{ title = "CASH", w = 0.18, align = Enum.TextXAlignment.Center },
		{ title = "DOWNS", w = 0.11, align = Enum.TextXAlignment.Center },
		{ title = "REVIVES", w = 0.11, align = Enum.TextXAlignment.Center },
	}
	local tableX, tableW = S(24), W - S(48)
	local y = headerH
	local function cell(parent: Instance, text: string, col: any, x: number, color: Color3, size: number, font: Font)
		return UI.text({
			Text = text,
			FontFace = font,
			TextSize = size,
			TextColor3 = color,
			TextXAlignment = col.align,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(x, 0),
			Size = UDim2.new(col.w, 0, 1, 0),
			ZIndex = 12,
			Parent = parent,
		})
	end
	local header = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(tableX, y),
		Size = UDim2.fromOffset(tableW, S(20)),
		ZIndex = 11,
		Parent = panel,
	})
	local x = 0
	for _, col in cols do
		cell(header, col.title, col, x, Theme.Colors.grey, S(11), Theme.Fonts.body)
		x += math.floor(tableW * col.w)
	end
	y += S(24)
	for i, row in rows do
		local rowFrame = UI.frame({
			BackgroundColor3 = Theme.Colors.panel,
			BackgroundTransparency = if i % 2 == 0 then 0.6 else 0.3,
			Position = UDim2.fromOffset(tableX, y),
			Size = UDim2.fromOffset(tableW, rowH - S(4)),
			ZIndex = 11,
			Parent = panel,
		})
		UI.corner(rowFrame, S(6))
		local isMvp = d.mvp and d.mvp.userId == row.userId
		local color = Color3.fromHex(tostring(row.maskColor or "F2E6C8"))
		local xx = 0
		-- Level before the name on every row.
		local nameCell = cell(
			rowFrame,
			string.format("LV %d  %s", tonumber(row.level) or 1, string.upper(tostring(row.name))),
			cols[1],
			xx + S(8),
			color,
			S(14),
			Theme.Fonts.display
		)
		if row.newBest then
			nameCell.Text = nameCell.Text .. "  ★ NEW BEST"
		end
		-- Brief 6: VIP's gold tag before the name and a softly pulsing gold frame on the row.
		if row.vip then
			nameCell.RichText = true
			nameCell.Text = UI.vipName(nameCell.Text, true)
			local frame = UI.stroke(rowFrame, Color3.fromHex("F2C14E"), S(2), 0)
			task.spawn(function()
				local t0 = os.clock()
				while rowFrame.Parent do
					frame.Transparency = 0.15 + 0.35 * (math.sin((os.clock() - t0) * 3) + 1) / 2
					task.wait(0.05)
				end
			end)
		end
		if isMvp then
			local tag, tagLabel = UI.pill(rowFrame, "MVP", Theme.Colors.gold, Theme.Colors.bg, S(16), S(10))
			tag.AnchorPoint = Vector2.new(1, 0.5)
			tag.Position = UDim2.new(cols[1].w, -S(6), 0.5, 0)
			tag.ZIndex = 13
			tagLabel.ZIndex = 14
			tagLabel.FontFace = Theme.Fonts.display
			nameCell.Size = UDim2.new(cols[1].w, -S(60), 1, 0)
		end
		xx += math.floor(tableW * cols[1].w)
		-- Side jobs plus minigames completed.
		cell(rowFrame, tostring(row.kills or 0), cols[2], xx, Theme.Colors.text, S(13), Theme.Fonts.body)
		xx += math.floor(tableW * cols[2].w)
		cell(rowFrame, tostring(row.jobs or 0), cols[3], xx, Theme.Colors.blue, S(13), Theme.Fonts.body)
		xx += math.floor(tableW * cols[3].w)
		cell(rowFrame, fmtCash(row.cash or 0), cols[4], xx, Theme.Colors.cash, S(13), Theme.Fonts.body)
		xx += math.floor(tableW * cols[4].w)
		cell(rowFrame, tostring(row.downs or 0), cols[5], xx, Theme.Colors.malus, S(13), Theme.Fonts.body)
		xx += math.floor(tableW * cols[5].w)
		cell(rowFrame, tostring(row.revives or 0), cols[6], xx, Theme.Colors.text, S(13), Theme.Fonts.body)
		if row.userId == player.UserId then
			UI.stroke(rowFrame, color, S(1.5), 0.3)
		end
		y += rowH
	end

	-- Buttons.
	local btnY = H - S(72)
	local function choose(choice: string, button: TextButton)
		if chosen then
			return
		end
		chosen = true
		Remotes.SummaryChoice:FireServer(choice)
		UI.punch(button, 0.92, 0.2)
		UI.sound(Theme.Sounds.toast, 1.3, 0.5)
		button.Text = if choice == "again" then "RE-FORMING THE PARTY…" else "BACK TO THE HUB…"
	end
	local again = UI.button({
		Text = "PLAY AGAIN",
		FontFace = Theme.Fonts.display,
		TextSize = S(22),
		TextColor3 = Theme.Colors.bg,
		BackgroundColor3 = Theme.Colors.cash,
		Position = UDim2.fromOffset(S(24), btnY),
		Size = UDim2.new(0.5, -S(32), 0, S(54)),
		ZIndex = 11,
		Parent = panel,
	})
	UI.corner(again, S(12))
	UI.stroke(again, Theme.Colors.black, S(2), 0.4)
	again:SetAttribute("NavDefault", true) -- brief 11: the pad lands on PLAY AGAIN
	again.Activated:Connect(function()
		choose("again", again)
	end)
	local lobby = UI.button({
		Text = "TO LOBBY",
		FontFace = Theme.Fonts.display,
		TextSize = S(22),
		TextColor3 = Theme.Colors.gold,
		BackgroundColor3 = Theme.Colors.panel2,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -S(24), 0, btnY),
		Size = UDim2.new(0.5, -S(32), 0, S(54)),
		ZIndex = 11,
		Parent = panel,
	})
	UI.corner(lobby, S(12))
	UI.stroke(lobby, Theme.Colors.gold, S(2))
	lobby.Activated:Connect(function()
		choose("lobby", lobby)
	end)
	lobbyButton = lobby
	UI.text({
		Text = "PLAY AGAIN RE-FORMS THE PARTY IN THE QUEUE ZONE · TO LOBBY RETURNS TO THE HUB",
		TextSize = S(10),
		TextColor3 = Theme.Colors.grey,
		Position = UDim2.fromOffset(0, H - S(16)),
		Size = UDim2.new(1, 0, 0, S(12)),
		ZIndex = 11,
		Parent = panel,
	})
end

local lastCF: CFrame? = nil

-- Brief 7: the line's own frame. The arena's line faces -Z at floor height (the plain world frame, so nothing
-- moves there); a map that sends `facing` (THE BANK: the crew faces the bank) turns every shot with it.
local function lineFrame(d: any, line: { CFrame }, center: Vector3): CFrame
	local floorY = (if #line > 0 then line[1].Position.Y else Config.FloorTop + 3) - (Config.FloorTop + 3)
	local p = Vector3.new(center.X, floorY, center.Z)
	local f = d.facing
	if typeof(f) == "Vector3" and Vector3.new(f.X, 0, f.Z).Magnitude > 0.1 then
		return CFrame.lookAt(p, p + Vector3.new(f.X, 0, f.Z))
	end
	return CFrame.new(p)
end

local function step(_dt: number)
	local d = data
	if not d then
		return
	end
	local t = ClientState.serverNow() - d.startedAt
	local beats = d.beats
	local line: { CFrame } = d.line
	local sum = Vector3.zero
	for _, cf in line do
		sum += cf.Position
	end
	local center = if #line > 0 then sum / #line else Vector3.zero
	local F = lineFrame(d, line, center)
	local lineShot = CFrame.lookAt(
		F:PointToWorldSpace(Vector3.new(0, 4.2, -12)),
		F:PointToWorldSpace(Vector3.new(0, EYE_LINE - 0.4, 0))
	)

	local cf: CFrame = lineShot
	if t < beats.mvp then
		-- One slow pan along the whole team up to the MVP beat, easing in a little as it goes. The poses
		-- and the cash rain land inside it.
		if t >= beats.poses then
			once("poses", function()
				for i, row in d.players do
					local pose = Config.Poses[row.pose] or Config.Poses[1]
					local animId = if typeof(row.poseAnim) == "string" then row.poseAnim else pose.animationId
					local hold = tonumber(row.poseHold) or pose.holdSec
					task.delay(Config.PoseStagger * (i - 1), function()
						if data == d then
							RunStartUI.playAnim(RunStartUI.charFor(row), animId, hold, RunStartUI.EMOTE_PRIORITY)
						end
					end)
				end
				UI.sound(Theme.Sounds.reelLand, 1, 0.5)
			end)
		end
		if t >= beats.rain then
			once("rain", function()
				UI.sound(Theme.Sounds.crate, 1.2, 0.5)
				task.spawn(function()
					local ticks = math.clamp(math.floor((d.rainCount or 0) / 8), 3, 24)
					for i = 1, ticks do
						if data ~= d then
							return
						end
						UI.sound(Theme.Sounds.reelTick, 1.2 + (i % 4) * 0.15, 0.2)
						task.wait((d.rainSec or 2) / ticks)
					end
				end)
			end)
		end
		local s = math.clamp(t / math.max(beats.mvp, 0.01), 0, 1)
		local a = F:PointToObjectSpace(if #line > 0 then line[1].Position else center)
		local b = F:PointToObjectSpace(if #line > 0 then line[#line].Position else center)
		local x = (a.X - 1.5) + ((b.X + 1.5) - (a.X - 1.5)) * s
		local dist = PAN_FAR + (PAN_NEAR - PAN_FAR) * s
		cf = CFrame.lookAt(
			F:PointToWorldSpace(Vector3.new(x, PAN_HEIGHT, -dist)),
			F:PointToWorldSpace(Vector3.new(x, EYE_LINE, 0))
		)
	elseif t < beats.summary then
		once("mvp", function()
			showMvp(d)
		end)
		-- Tight 3/4 shot on the MVP, slow orbit.
		local mvpRoot = if d.mvp then rootFor(d.mvp) else nil
		local pos = if mvpRoot then mvpRoot.Position else center
		local s = (t - beats.mvp) / math.max(d.mvpOrbitSec or 2.5, 0.1)
		local a = 0.55 - 0.8 * math.clamp(s, 0, 1)
		-- Full body in frame: a touch above eye line, looking down at the chest.
		cf = CFrame.lookAt(
			pos + F:VectorToWorldSpace(Vector3.new(math.sin(a) * MVP_DIST, MVP_HEIGHT, -math.cos(a) * MVP_DIST)),
			pos + Vector3.new(0, EYE_LINE - 0.3, 0)
		)
	else
		once("summary", function()
			showSummary(d)
		end)
		cf = lineShot
	end
	lastCF = cf
	camera.CFrame = cf
	camera.Focus = cf

	-- The GOLD BANKED count-up and the lobby countdown.
	if summaryShownAt >= 0 then
		local e = os.clock() - summaryShownAt
		local countUp = math.max(d.countUpSec or 1, 0.05)
		local k = easeOut(e / countUp)
		if bankedLabel then
			-- Your own total: the team's banked bags plus the run payout and your side job gold.
			local mine = (tonumber(d.banked) or 0) + (tonumber(d.gold) or 0)
			for _, row in d.players do
				if row.userId == player.UserId and typeof(row.goldTotal) == "number" then
					mine = row.goldTotal
				end
			end
			bankedLabel.Text = string.format("◆ %d", math.floor(mine * k))
			bankedLabel.TextSize = if k < 1 then UI.S(40 + 6 * math.sin(e * 30)) else UI.S(40)
		end
		-- Brief 9: the Gold landed; if the new balance makes N >= 1 Skill Web nodes affordable, say so once.
		local sl = skillsLine
		if sl and k >= 1 and not sl:GetAttribute("Done") then
			sl:SetAttribute("Done", true)
			local profile = ClientState.sync and ClientState.sync.profile
			local gold = if profile and typeof(profile.gold) == "number" then profile.gold else 0
			local owned = profile and profile.skills and profile.skills.owned or {}
			local count = #Skills.affordableIds(owned, gold)
			if count >= 1 then
				sl.Text = string.format("%d SKILL%s AFFORDABLE", count, if count == 1 then "" else "S")
				sl.Visible = true
				sl.TextTransparency = 1
				UI.tween(sl, { TextTransparency = 0 }, 0.3)
			end
		end
		-- The level card: drops in after the Gold count-up, the bar fills over XpFillSec at a constant XP
		-- speed with `+N XP` counting; a level crossed flashes, bumps the card, pops the reward line and keeps
		-- filling.
		local anim = xpAnim
		if anim then
			local xpStart = countUp + 0.15
			if e >= xpStart then
				local card = anim.card
				if not anim.shown then
					anim.shown = true
					card.frame.Visible = true
					UI.tween(
						card.frame,
						{ Position = UDim2.new(0.5, 0, 0.5, anim.cardY) },
						0.35,
						Enum.EasingStyle.Back,
						Enum.EasingDirection.Out
					)
					UI.sound(Theme.Sounds.toast, 1.2, 0.4)
					local ml = anim.masteryLabel
					if ml then
						ml.Visible = true
						UI.punch(ml, 1.2, 0.3)
					end
				end
				local u = math.clamp((e - xpStart) / math.max(tonumber(d.xpFillSec) or 1.2, 0.05), 0, 1)
				-- After the fill: the run's mastery tier-ups pop one by one above the card.
				if u >= 1 and not anim.masteryPopped and #anim.masteryTierUps > 0 then
					anim.masteryPopped = true
					for n, up in anim.masteryTierUps do
						task.delay(0.3 + (n - 1) * 0.9, function()
							if not card.frame.Parent then
								return
							end
							local pop = UI.text({
								Text = tostring(up.text or ""),
								FontFace = Theme.Fonts.display,
								TextSize = UI.S(16),
								TextColor3 = Theme.Colors.cash,
								AnchorPoint = Vector2.new(0.5, 1),
								Position = UDim2.new(0.5, 0, 0, -UI.S(6)),
								Size = UDim2.new(1, 0, 0, UI.S(22)),
								ZIndex = 15,
								Parent = card.frame,
							})
							UI.stroke(pop, Theme.Colors.black, UI.S(1.5), 0.3)
							UI.punch(pop, 1.6, 0.4)
							UI.sound(Theme.Sounds.legendary, 1.3, 0.5)
							UI.tween(
								pop,
								{ Position = UDim2.new(0.5, 0, 0, -UI.S(34)), TextTransparency = 1 },
								1.0,
								nil,
								nil,
								1.2
							)
							task.delay(2.4, function()
								pop:Destroy()
							end)
						end)
					end
				end
				local consumed = u * anim.gained
				local acc = 0
				for i, seg in anim.segments do
					local len = seg.to - seg.from
					if consumed <= acc + len or i == #anim.segments then
						local into = math.clamp(consumed - acc, 0, len)
						card.set(
							seg.level,
							math.floor(seg.from + into),
							seg.need,
							string.format("+%d XP", math.floor(consumed)),
							anim.sub
						)
						break
					end
					acc += len
					if seg.levelUp and not anim.popped[i] then
						-- Crossed a level: the flash, the bump and the reward line above the card.
						anim.popped[i] = true
						card.flash()
						card.punch()
						UI.sound(Theme.Sounds.legendary, 1.2, 0.6)
						ClientState.Juice:Fire("RarityFlash", { color = Theme.Colors.gold, alpha = 0.25 })
						local up = anim.levelUps[i] -- the k-th level crossed is the k-th level-up
						local line = if up then tostring(up.line or "") else ""
						local pop = UI.text({
							Text = string.format("LEVEL %d · %s", seg.level + 1, line),
							FontFace = Theme.Fonts.display,
							TextSize = UI.S(16),
							TextColor3 = Theme.Colors.gold,
							AnchorPoint = Vector2.new(0.5, 1),
							Position = UDim2.new(0.5, 0, 0, -UI.S(6)),
							Size = UDim2.new(1, 0, 0, UI.S(22)),
							ZIndex = 15,
							Parent = card.frame,
						})
						UI.stroke(pop, Theme.Colors.black, UI.S(1.5), 0.3)
						UI.punch(pop, 1.6, 0.4)
						UI.tween(
							pop,
							{ Position = UDim2.new(0.5, 0, 0, -UI.S(34)), TextTransparency = 1 },
							1.2,
							nil,
							nil,
							1.4
						)
						task.delay(2.8, function()
							pop:Destroy()
						end)
					end
				end
			end
		end
		if lobbyButton and not chosen then
			local left = math.max(0, math.ceil((d.autoLobbySec or 30) - e))
			lobbyButton.Text = string.format("TO LOBBY (%d)", left)
		end
	end
end

local function begin(d: any)
	teardown()
	data = d
	fired = {}
	lastCF = nil
	Spectate.exit(true)
	MinigameFrame.close("cancel")
	ClientState.setAds(false)
	ClientState.cameraMode = "cinematic"
	ClientState.setBlock("cinematic", true)
	HUD.setMode("none")
	local g = UI.new("ScreenGui", {
		Name = "RunEnd",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 12,
		Parent = playerGui,
	}) :: ScreenGui
	gui = g
	dim = UI.frame({
		Name = "Dim",
		BackgroundColor3 = Theme.Colors.black,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = g,
	})
	RunService:BindToRenderStep("GHSRunEnd", Enum.RenderPriority.Camera.Value + 1, step)
end

function RunEndUI.init()
	ClientState.Juice:Connect(function(name: string, d: any)
		if name == "RunEndBegin" then
			begin(d)
		elseif name == "HubEnter" then
			finish()
			if passAfterHub then
				passAfterHub = false
				task.delay(Config.SummaryPassOpenDelaySec, function()
					ClientState.Juice:Fire("OpenPass", {})
				end)
			end
		end
	end)
end

return RunEndUI
