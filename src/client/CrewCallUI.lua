--!strict
-- Crew call component in the slot under the wave bar: expanded card -> timer pill -> result card -> toast.
-- Also owns the ARMS DROP banner since it shares the slot.
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

local activeCall: any = nil -- { data, frame, timerLabel, stroke, pill: boolean, token }
local callToken = 0

local function slot()
	return HUD.get("callSlot")
end

local function fmtTime(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

local function clearCall()
	if activeCall and activeCall.frame then
		activeCall.frame:Destroy()
	end
	activeCall = nil
end

-- The timer pill lives top-right above the abilities so the center stays clear.
local function pillHome()
	return HUD.get("topRight")
end

local function buildPill(data: any): (Frame, TextLabel, UIStroke)
	local S = UI.S
	local cs = pillHome()
	local color = KIND_COLORS[data.kind] or Theme.Colors.blue
	local pill = UI.frame({
		Name = "CallPill",
		BackgroundColor3 = Theme.Colors.panel,
		Size = UDim2.fromOffset(cs.width, S(38)),
	})
	UI.corner(pill, S(19))
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
		Size = UDim2.fromOffset(S(70), S(38)),
		Parent = pill,
	})
	UI.text({
		Text = data.rewardLine,
		TextSize = S(12),
		TextColor3 = Theme.Colors.cash,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -S(12), 0, 0),
		Size = UDim2.fromOffset(S(84), S(38)),
		Parent = pill,
	})
	return pill, timer, stroke
end

-- Expanded card: portrait, name, type pill or title, timer (optional), 2 lines, reward line.
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

local function buildExpanded(spec: CardSpec): (Frame, TextLabel)
	local S = UI.S
	local cs = slot()
	local color = spec.labelColor or KIND_COLORS[spec.kind] or Theme.Colors.blue
	local h = S(112)
	local frame = UI.frame({
		Name = "CallCard",
		BackgroundColor3 = Theme.Colors.panel,
		Size = UDim2.fromOffset(cs.width, h),
		ClipsDescendants = true,
	})
	UI.corner(frame, S(12))
	UI.stroke(frame, color, S(2))
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
		Size = UDim2.fromOffset(S(140), S(24)),
		Parent = frame,
	})
	local labelPill = UI.pill(frame, spec.label, color, Theme.Colors.bg, S(16), S(10))
	labelPill.Position = UDim2.fromOffset(textX + S(118), S(12))
	local timer = UI.text({
		Text = if spec.duration then fmtTime(spec.duration) else "",
		Font = Theme.Fonts.display,
		TextSize = S(22),
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -S(12), 0, S(8)),
		Size = UDim2.fromOffset(S(80), S(26)),
		Visible = spec.showTimer,
		Parent = frame,
	})
	UI.text({
		Text = table.concat(spec.text, "\n"),
		TextSize = S(12),
		TextColor3 = Theme.Colors.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Position = UDim2.fromOffset(textX, S(36)),
		Size = UDim2.new(1, -textX - S(12), 0, S(44)),
		Parent = frame,
	})
	UI.text({
		Text = spec.rewardLine,
		Font = Theme.Fonts.display,
		TextSize = S(14),
		TextColor3 = Theme.Colors.cash,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(textX, h - S(30)),
		Size = UDim2.new(1, -textX, 0, S(22)),
		Parent = frame,
	})
	return frame, timer
end

local function slideIn(frame: Frame, height: number)
	local cs = slot()
	frame.Size = UDim2.fromOffset(cs.width, 0)
	UI.tween(frame, { Size = UDim2.fromOffset(cs.width, height) }, 0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
end

local function onCallStart(data: any)
	clearCall()
	callToken += 1
	local token = callToken
	local cs = slot()
	local expanded, expandedTimer = buildExpanded({
		kind = data.kind,
		crewLead = data.crewLead,
		label = data.typeLabel,
		text = data.text,
		rewardLine = data.rewardLine,
		showTimer = true,
		duration = data.duration,
	})
	activeCall =
		{ data = data, frame = expanded, timerLabel = expandedTimer, stroke = nil, pill = false, token = token }
	cs.add(expanded, 1)
	slideIn(expanded, UI.S(112))
	UI.sound(Theme.Sounds.call, 1, 0.6)

	task.delay(Config.CallHoldSec, function()
		if not activeCall or activeCall.token ~= token then
			return
		end
		local shrink = UI.tween(
			expanded,
			{ Size = UDim2.fromOffset(cs.width, 0) },
			0.2,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		)
		shrink.Completed:Wait()
		if not activeCall or activeCall.token ~= token then
			return
		end
		expanded:Destroy()
		local pill, pillTimer, stroke = buildPill(data)
		pillHome().add(pill, 1)
		UI.punch(pill, 1.15, 0.3)
		activeCall.frame = pill
		activeCall.timerLabel = pillTimer
		activeCall.stroke = stroke
		activeCall.pill = true
	end)
end

-- Result: a "nice work" / "too slow" card from the crew lead, then the toast.
local function onCallEnd(data: any)
	clearCall()
	callToken += 1
	local token = callToken
	local cs = slot()
	local color = if data.success then Theme.Colors.cash else Theme.Colors.red
	local card = buildExpanded({
		kind = data.kind or "job",
		crewLead = data.crewLead or Lines.job.crewLead,
		label = data.title or (if data.success then Lines.job.doneTitle else Lines.failToast),
		labelColor = color,
		text = data.text or {},
		rewardLine = data.rewardLine or "",
		showTimer = false,
	})
	cs.add(card, 1)
	slideIn(card, UI.S(112))
	UI.sound(if data.success then Theme.Sounds.legendary else Theme.Sounds.deny, if data.success then 1.1 else 0.8, 0.6)
	if data.success then
		UI.punch(card, 1.06, 0.4)
	else
		UI.shake(card, UI.S(3), 0.3)
	end
	task.delay(Config.CallHoldSec, function()
		if token ~= callToken then
			return
		end
		local shrink = UI.tween(
			card,
			{ Size = UDim2.fromOffset(cs.width, 0) },
			0.2,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		)
		shrink.Completed:Wait()
		card:Destroy()
		if token == callToken then
			cs.toast(tostring(data.toast), color, 0.8)
		end
	end)
end

function CrewCallUI.init()
	ClientState.Juice:Connect(function(name: string, data: any)
		if name == "CallStart" then
			onCallStart(data)
		elseif name == "CallEnd" then
			onCallEnd(data)
		elseif name == "CrateIncoming" then
			-- Transient only: no persistent arms-drop banner.
			slot().toast("ARMS DROP INCOMING", Theme.Colors.gold, 1)
			UI.sound(Theme.Sounds.crate, 0.6, 0.6)
		elseif name == "CrateLand" then
			slot().toast(string.format("ARMS DROP · %d GUNS", data.total or data.left or 0), Theme.Colors.gold, 1.2)
			UI.sound(Theme.Sounds.crate, 0.9, 0.7)
			ClientState.Juice:Fire("Shake", { amp = 0.35, dur = 0.3 })
		end
	end)

	HUD.Rebuilt:Connect(function()
		-- The HUD was rebuilt; re-add the live pill.
		local call = activeCall
		activeCall = nil
		if call and call.data and call.data.endsAt then
			local pill, timer, stroke = buildPill(call.data)
			pillHome().add(pill, 1)
			activeCall =
				{ data = call.data, frame = pill, timerLabel = timer, stroke = stroke, pill = true, token = call.token }
		end
	end)

	-- Timer tick.
	local pulse = 0
	RunService.Heartbeat:Connect(function(dt)
		local call = activeCall
		if not call or not call.frame.Parent or not call.data.endsAt then
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
