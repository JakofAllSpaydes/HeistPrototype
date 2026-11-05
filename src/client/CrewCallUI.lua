--!strict
-- Crew call component. Everything lives in one box in the top-right corner: the call card slides in
-- from the right edge, collapses in place to the timer pill, expands back for the result card, then
-- slides out. Result and arms-drop toasts go to the center slot with the other system notices.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Lines = require(Shared:WaitForChild("CrewCall"):WaitForChild("Lines"))

local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local HUD = require(script.Parent:WaitForChild("HUD"))

local CrewCallUI = {}

local KIND_COLORS = {
	job = Theme.Colors.blue,
	door = Theme.Colors.amber,
	ftue = Theme.Colors.grey,
	legendary = Theme.Colors.gold,
}

local CARD_H = 112
local PILL_H = 38
local SLIDE = 420 -- px (pre-scale) the box travels when sliding in from / out to the right edge

-- One box at a time. { data, box, inner, timerLabel, stroke, token }
local active: any = nil
local callToken = 0

local function centerSlot()
	return HUD.get("callSlot")
end

local function home()
	return HUD.get("topRight")
end

local function fmtTime(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

local function destroyActive()
	if active and active.box then
		active.box:Destroy()
	end
	active = nil
end

-- The outer box clips; `inner` is what slides. Content frames are parented to inner.
local function buildBox(height: number): (Frame, Frame)
	local S = UI.S
	local h = home()
	local box = UI.frame({
		Name = "CallBox",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(h.width, S(height)),
		ClipsDescendants = true,
	})
	local inner = UI.frame({
		Name = "Inner",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.fromOffset(0, 0),
		Parent = box,
	})
	h.add(box, 1)
	return box, inner
end

local function buildPill(parent: Instance, data: any): (Frame, TextLabel, UIStroke)
	local S = UI.S
	local color = KIND_COLORS[data.kind] or Theme.Colors.blue
	local pill = UI.frame({
		Name = "CallPill",
		BackgroundColor3 = Theme.Colors.panel,
		Size = UDim2.new(1, 0, 0, S(PILL_H)),
		Parent = parent,
	})
	UI.corner(pill, S(PILL_H / 2))
	local stroke = UI.stroke(pill, color, S(2))
	local icon = UI.frame({
		BackgroundColor3 = color,
		Position = UDim2.fromOffset(S(8), S(7)),
		Size = UDim2.fromOffset(S(24), S(24)),
		Parent = pill,
	})
	UI.corner(icon, S(6))
	UI.text({
		Text = "!",
		Font = Theme.Fonts.display,
		TextSize = S(18),
		TextColor3 = Theme.Colors.bg,
		Size = UDim2.fromScale(1, 1),
		Parent = icon,
	})
	UI.text({
		Text = data.name,
		Font = Theme.Fonts.display,
		TextSize = S(16),
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(S(40), 0),
		Size = UDim2.new(0.5, 0, 1, 0),
		Parent = pill,
	})
	local timer = UI.text({
		Text = "1:15",
		Font = Theme.Fonts.display,
		TextSize = S(18),
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -S(100), 0, 0),
		Size = UDim2.fromOffset(S(70), S(PILL_H)),
		Parent = pill,
	})
	UI.text({
		Text = data.rewardShort or data.rewardLine,
		TextSize = S(12),
		TextColor3 = Theme.Colors.cash,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -S(12), 0, 0),
		Size = UDim2.fromOffset(S(84), S(PILL_H)),
		Parent = pill,
	})
	-- Capture point: a thin progress bar along the bottom of the pill.
	if data.jobKind == "capture" then
		local bar = UI.frame({
			Name = "Progress",
			BackgroundColor3 = Theme.Colors.bg,
			Position = UDim2.new(0, S(14), 1, -S(7)),
			Size = UDim2.new(1, -S(28), 0, S(4)),
			ZIndex = 3,
			Parent = pill,
		})
		UI.corner(bar, S(2))
		local fill = UI.frame({
			Name = "Fill",
			BackgroundColor3 = Theme.Colors.cash,
			Size = UDim2.fromScale(active and active.progress or 0, 1),
			ZIndex = 3,
			Parent = bar,
		})
		UI.corner(fill, S(2))
	end
	return pill, timer, stroke
end

local function setPillProgress(progress: number, inside: boolean)
	if not active or not active.box then
		return
	end
	local bar = active.box:FindFirstChild("Progress", true)
	local fill = bar and bar:FindFirstChild("Fill")
	if fill and fill:IsA("Frame") then
		fill.Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1)
		fill.BackgroundColor3 = if inside then Theme.Colors.cash else Theme.Colors.malus
	end
end

-- Dialogue types out character by character with a soft tick; the portrait head bobs while "talking".
local function typewrite(label: TextLabel, head: GuiObject)
	local text = label.Text
	local total = utf8.len(text) or #text
	label.MaxVisibleGraphemes = 0
	task.spawn(function()
		local shown = 0
		local perChar = 1 / math.max(Config.CallTypeCharsPerSec, 1)
		while shown < total and label.Parent do
			shown += 1
			label.MaxVisibleGraphemes = shown
			if shown % 3 == 0 and string.sub(text, shown, shown) ~= " " then
				UI.sound(Theme.Sounds.reelTick, 1.5 + math.random() * 0.5, 0.06)
			end
			if shown % 5 == 0 and head.Parent then
				UI.punch(head, 1.12, 0.14)
			end
			task.wait(perChar)
		end
		if label.Parent then
			label.MaxVisibleGraphemes = -1
		end
	end)
end

type CardSpec = {
	kind: string,
	crewLead: string,
	label: string, -- type pill text or result title
	labelColor: Color3?,
	text: { string },
	rewardLine: string,
	showTimer: boolean,
	duration: number?,
}

local function buildCard(parent: Instance, spec: CardSpec): (Frame, TextLabel, UIStroke)
	local S = UI.S
	local color = spec.labelColor or KIND_COLORS[spec.kind] or Theme.Colors.blue
	local h = S(CARD_H)
	local frame = UI.frame({
		Name = "CallCard",
		BackgroundColor3 = Theme.Colors.panel,
		Size = UDim2.new(1, 0, 0, h),
		Parent = parent,
	})
	UI.corner(frame, S(12))
	local stroke = UI.stroke(frame, color, S(2))
	local portrait = UI.frame({
		BackgroundColor3 = Theme.Colors.panel2,
		Position = UDim2.fromOffset(S(10), S(10)),
		Size = UDim2.fromOffset(h - S(20), h - S(20)),
		Parent = frame,
	})
	UI.corner(portrait, S(10))
	local head = UI.frame({
		BackgroundColor3 = Theme.Colors.grey,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, S(12)),
		Size = UDim2.fromOffset(S(28), S(28)),
		Parent = portrait,
	})
	UI.corner(head, S(14))
	local shoulders = UI.frame({
		BackgroundColor3 = Theme.Colors.grey,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -S(14)),
		Size = UDim2.fromOffset(S(56), S(30)),
		Parent = portrait,
	})
	UI.corner(shoulders, S(12))
	UI.text({
		Text = Lines.portraitLabel,
		TextSize = S(9),
		TextColor3 = Theme.Colors.grey,
		Position = UDim2.new(0, 0, 1, -S(14)),
		Size = UDim2.new(1, 0, 0, S(12)),
		Parent = portrait,
	})
	local textX = h + S(4)
	UI.text({
		Text = spec.crewLead,
		Font = Theme.Fonts.display,
		TextSize = S(18),
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(textX, S(8)),
		Size = UDim2.fromOffset(S(120), S(24)),
		Parent = frame,
	})
	local labelPill = UI.pill(frame, spec.label, color, Theme.Colors.bg, S(16), S(10))
	labelPill.Position = UDim2.fromOffset(textX + S(96), S(12))
	local timer = UI.text({
		Text = if spec.duration then fmtTime(spec.duration) else "",
		Font = Theme.Fonts.display,
		TextSize = S(20),
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -S(10), 0, S(8)),
		Size = UDim2.fromOffset(S(60), S(26)),
		Visible = spec.showTimer,
		Parent = frame,
	})
	local body = UI.text({
		Text = table.concat(spec.text, "\n"),
		TextSize = S(11),
		TextColor3 = Theme.Colors.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Position = UDim2.fromOffset(textX, S(36)),
		Size = UDim2.new(1, -textX - S(10), 0, S(46)),
		Parent = frame,
	})
	typewrite(body, head)
	UI.text({
		Text = spec.rewardLine,
		Font = Theme.Fonts.display,
		TextSize = S(14),
		TextColor3 = Theme.Colors.cash,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(textX, h - S(28)),
		Size = UDim2.new(1, -textX, 0, S(22)),
		Parent = frame,
	})
	return frame, timer, stroke
end

local function slideIn(inner: Frame)
	inner.Position = UDim2.fromOffset(UI.S(SLIDE), 0)
	UI.tween(inner, { Position = UDim2.fromOffset(0, 0) }, 0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
end

local function slideOut(inner: Frame): Tween
	return UI.tween(
		inner,
		{ Position = UDim2.fromOffset(UI.S(SLIDE), 0) },
		0.3,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In
	)
end

local function resizeBox(box: Frame, height: number): Tween
	return UI.tween(
		box,
		{ Size = UDim2.fromOffset(home().width, UI.S(height)) },
		0.25,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)
end

local function onCallStart(data: any)
	destroyActive()
	callToken += 1
	local token = callToken
	local box, inner = buildBox(CARD_H)
	local card, timer, stroke = buildCard(inner, {
		kind = data.kind,
		crewLead = data.crewLead,
		label = data.typeLabel,
		text = data.text,
		rewardLine = data.rewardLine,
		showTimer = true,
		duration = data.duration,
	})
	active = {
		data = data,
		box = box,
		inner = inner,
		timerLabel = timer,
		stroke = stroke,
		token = token,
		progress = 0,
		lastTick = 0,
	}
	slideIn(inner)
	UI.sound(Theme.Sounds.call, 1, 0.6)

	task.delay(Config.CallHoldSec, function()
		if not active or active.token ~= token then
			return
		end
		-- Collapse in place: shrink the box to pill height while the pill takes over.
		local pill, pillTimer, pillStroke = buildPill(inner, data)
		pill.BackgroundTransparency = 1
		pill.ZIndex = 2
		UI.tween(card, { BackgroundTransparency = 1 }, 0.15)
		for _, d in card:GetDescendants() do
			if d:IsA("TextLabel") then
				UI.tween(d, { TextTransparency = 1 }, 0.12)
			elseif d:IsA("Frame") then
				UI.tween(d, { BackgroundTransparency = 1 }, 0.12)
			elseif d:IsA("UIStroke") then
				UI.tween(d, { Transparency = 1 }, 0.12)
			end
		end
		UI.tween(pill, { BackgroundTransparency = 0 }, 0.2, nil, nil, 0.1)
		local shrink = resizeBox(box, PILL_H)
		shrink.Completed:Wait()
		if not active or active.token ~= token then
			return
		end
		card:Destroy()
		UI.punch(pill, 1.1, 0.3)
		active.timerLabel = pillTimer
		active.stroke = pillStroke
	end)
end

-- Half-time reminder: the pill expands back into a card with the nudge, then collapses again. The capture
-- progress and the timer carry over.
local function onCallReminder(data: any)
	local call = active
	if not call or not call.data or call.data.id ~= data.id then
		return
	end
	local progress = call.progress or 0
	local d = table.clone(call.data)
	d.text = data.text or d.text
	d.typeLabel = data.title or d.typeLabel
	onCallStart(d)
	if active then
		active.progress = progress
		active.wasInside = call.wasInside
	end
	centerSlot().toast(tostring(data.title or "STILL OPEN"), Theme.Colors.amber, 1.2)
end

-- Result: expand from the pill into a "nice work" / "too slow" card, hold, slide out. Toast in the center.
local function onCallEnd(data: any)
	callToken += 1
	local token = callToken
	local color = if data.success then Theme.Colors.cash else Theme.Colors.red
	local box: Frame
	local inner: Frame
	if active and active.box and active.box.Parent then
		box = active.box
		inner = active.inner
		for _, c in inner:GetChildren() do
			c:Destroy()
		end
	else
		box, inner = buildBox(PILL_H)
		slideIn(inner)
	end
	local card = buildCard(inner, {
		kind = data.kind or "job",
		crewLead = data.crewLead or Lines.job.crewLead,
		label = data.title or (if data.success then Lines.job.doneTitle else Lines.failToast),
		labelColor = color,
		text = data.text or {},
		rewardLine = data.rewardLine or "",
		showTimer = false,
	})
	active = { data = data, box = box, inner = inner, timerLabel = nil, stroke = nil, token = token }
	resizeBox(box, CARD_H)
	UI.sound(if data.success then Theme.Sounds.legendary else Theme.Sounds.deny, if data.success then 1.1 else 0.8, 0.6)
	if data.success then
		UI.punch(card, 1.06, 0.4)
		ClientState.Juice:Fire("Shake", { amp = 0.2, dur = 0.25 })
	else
		UI.shake(card, UI.S(3), 0.3)
	end
	centerSlot().toast(tostring(data.toast), color, 1.2)

	task.delay(Config.CallHoldSec, function()
		if not box.Parent then
			return
		end
		local out = slideOut(inner)
		out.Completed:Wait()
		if active and active.token == token then
			destroyActive()
		else
			box:Destroy()
		end
	end)
end

-- A line with no job behind it (MARLOW's boss call): the card slides in, holds, slides out.
local function onCrewLine(data: any)
	destroyActive()
	callToken += 1
	local token = callToken
	local box, inner = buildBox(CARD_H)
	buildCard(inner, {
		kind = tostring(data.kind or "door"),
		crewLead = tostring(data.crewLead or Lines.job.crewLead),
		label = tostring(data.typeLabel or ""),
		text = data.text or {},
		rewardLine = "",
		showTimer = false,
	})
	active = { data = { id = "line" }, box = box, inner = inner, timerLabel = nil, stroke = nil, token = token }
	slideIn(inner)
	UI.sound(Theme.Sounds.call, 0.9, 0.6)
	task.delay(tonumber(data.hold) or Config.CallHoldSec, function()
		if not active or active.token ~= token or not box.Parent then
			return
		end
		local out = slideOut(inner)
		out.Completed:Wait()
		if active and active.token == token then
			destroyActive()
		end
	end)
end

-- A pill with no card first (the open vault's VAULT · 0:60 timer).
local function showPill(data: any)
	destroyActive()
	callToken += 1
	local box, inner = buildBox(PILL_H)
	local pill, timer, stroke = buildPill(inner, data)
	active = { data = data, box = box, inner = inner, timerLabel = timer, stroke = stroke, token = callToken }
	slideIn(inner)
	UI.punch(pill, 1.1, 0.3)
end

local function slideOutActive()
	local call = active
	if not call or not call.box or not call.box.Parent then
		return
	end
	local token = call.token
	local out = slideOut(call.inner)
	out.Completed:Wait()
	if active and active.token == token then
		destroyActive()
	end
end

-- The vault: VAULT pill while the loot window runs, MARLOW's gas card at the warning (collapses back
-- to the pill, red under CallPillWarnSec), gone when the room seals.
local function onVaultOpen(data: any)
	showPill({
		id = "vault",
		jobKind = "vault",
		kind = "door",
		name = tostring(data.name or Lines.vault.pillName),
		crewLead = Lines.vault.crewLead,
		typeLabel = Lines.vault.typeLabel,
		text = {},
		rewardLine = "",
		rewardShort = tostring(data.hint or Lines.vault.lootHint),
		endsAt = tonumber(data.endsAt) or 0,
		duration = tonumber(data.openSec) or Config.VaultOpenSec,
	})
end

local function onVaultGas(data: any)
	if data.phase == "warn" then
		onCallStart({
			id = "vault",
			jobKind = "vault",
			kind = "door",
			name = Lines.vault.pillName,
			crewLead = tostring(data.crewLead or Lines.vault.crewLead),
			typeLabel = tostring(data.title or Lines.vault.gasTitle),
			text = data.text or Lines.vault.gasText,
			rewardLine = "",
			rewardShort = Lines.vault.gasHint,
			endsAt = tonumber(data.endsAt) or 0,
			duration = Config.VaultGasWarnSec,
		})
	else
		local call = active
		if call and call.data and call.data.id == "vault" then
			call.data.endsAt = nil
			if call.timerLabel then
				call.timerLabel.Text = Lines.vault.gasTitle
				call.timerLabel.TextColor3 = Theme.Colors.red
			end
		end
	end
end

function CrewCallUI.init()
	ClientState.Juice:Connect(function(name: string, data: any)
		if name == "CallStart" then
			onCallStart(data)
		elseif name == "CrewLine" then
			onCrewLine(data)
		elseif name == "VaultOpen" then
			-- The result card for the job is still up: the pill takes over after it has had its hold.
			task.delay(Config.CallHoldSec + 0.35, function()
				onVaultOpen(data)
			end)
		elseif name == "VaultGas" then
			onVaultGas(data)
		elseif name == "VaultSealed" then
			local call = active
			if call and call.data and call.data.id == "vault" then
				task.spawn(slideOutActive)
			end
		elseif name == "JobProgress" then
			local call = active
			if call and call.data and call.data.id == data.id then
				local progress = data.progress or 0
				call.progress = progress
				setPillProgress(progress, data.inside == true)
				-- A tick every 10% while holding, pitch climbing; a low buzz when you step off.
				local step = math.floor(progress * 10)
				if data.inside and step > (call.lastTick or 0) then
					call.lastTick = step
					UI.sound(Theme.Sounds.reelTick, 0.9 + step * 0.08, 0.35)
				elseif not data.inside and progress > 0 and progress < 1 and call.wasInside then
					UI.sound(Theme.Sounds.deny, 0.8, 0.3)
				end
				call.wasInside = data.inside == true
			end
		elseif name == "CallReminder" then
			onCallReminder(data)
		elseif name == "CallEnd" then
			onCallEnd(data)
		elseif name == "CrateIncoming" then
			centerSlot().toast("ARMS DROP INCOMING", Theme.Colors.gold, 1)
			UI.sound(Theme.Sounds.crate, 0.6, 0.6)
		elseif name == "CrateLand" then
			local rolls = tonumber(data.rolls) or 0
			centerSlot().toast(
				string.format("ARMS CRATE · %d ROLL%s", rolls, if rolls == 1 then "" else "S"),
				Theme.Colors.gold,
				1.2
			)
			UI.sound(Theme.Sounds.crate, 0.9, 0.7)
			ClientState.Juice:Fire("Shake", { amp = 0.35, dur = 0.3 })
		elseif name == "CallCleared" then
			-- The run ended (or debug reset) with a job open: no result card, the box just goes.
			destroyActive()
		end
	end)

	HUD.Rebuilt:Connect(function()
		-- The HUD was rebuilt; re-add the live pill if a job is running.
		local call = active
		active = nil
		if call and call.data and call.data.endsAt and call.data.endsAt > ClientState.serverNow() then
			local box, inner = buildBox(PILL_H)
			local _, timer, stroke = buildPill(inner, call.data)
			active =
				{ data = call.data, box = box, inner = inner, timerLabel = timer, stroke = stroke, token = call.token }
		end
	end)

	-- Timer tick.
	local pulse = 0
	RunService.Heartbeat:Connect(function(dt)
		local call = active
		if not call or not call.timerLabel or not call.box.Parent or not call.data.endsAt then
			return
		end
		local remaining = call.data.endsAt - ClientState.serverNow()
		call.timerLabel.Text = fmtTime(remaining)
		if remaining < Config.CallPillWarnSec then
			pulse += dt * 6
			call.timerLabel.TextColor3 = Theme.Colors.red
			local stroke = call.stroke
			if stroke then
				stroke.Color = Theme.Colors.red
				stroke.Transparency = 0.25 + 0.25 * math.sin(pulse)
				stroke.Thickness = UI.S(2) + UI.S(1.5) * (0.5 + 0.5 * math.sin(pulse))
			end
		end
	end)
end

return CrewCallUI
