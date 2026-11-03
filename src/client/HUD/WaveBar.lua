--!strict
-- Top-center: WAVE N / NEXT WAVE IN N, heat stars, N LEFT, Auto Skip toggle left, skip Votes right (V).
-- Big center banners on wave start / wave clear and the last seconds of the countdown.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Client = script.Parent.Parent
local ClientState = require(Client:WaitForChild("ClientState"))
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))

local WaveBar = {}

local function starCell(parent: Instance, index: number, size: number): (Frame, Frame)
	local cell = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		LayoutOrder = index,
		Parent = parent,
	})
	UI.text({
		Text = "★",
		TextSize = size,
		TextColor3 = Theme.Colors.panel2,
		Size = UDim2.fromScale(1, 1),
		Parent = cell,
	})
	local clip =
		UI.frame({ BackgroundTransparency = 1, Size = UDim2.fromScale(0, 1), ClipsDescendants = true, Parent = cell })
	UI.text({
		Text = "★",
		TextSize = size,
		TextColor3 = Theme.Colors.gold,
		Size = UDim2.fromOffset(size, size),
		Parent = clip,
	})
	return cell, clip
end

-- A pill that acts as a button: transparent TextButton over the pill frame.
local function pillButton(pill: Frame, onPress: () -> ()): TextButton
	local button = UI.button({
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		Parent = pill,
	})
	button.Activated:Connect(function()
		UI.punch(pill, 0.92, 0.15)
		onPress()
	end)
	button.MouseEnter:Connect(function()
		if not UserInputService.TouchEnabled then
			UI.punch(pill, 1.06, 0.15)
		end
	end)
	return button
end

function WaveBar.build(gui: ScreenGui, track: (RBXScriptConnection) -> ())
	local S = UI.S
	local root = UI.frame({
		Name = "WaveBar",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, S(12)),
		Size = UDim2.fromOffset(S(560), S(84)),
		Parent = gui,
	})
	local wave = UI.text({
		Name = "Wave",
		Font = Theme.Fonts.display,
		TextSize = S(44),
		Text = "WAVE 1",
		Size = UDim2.new(1, 0, 0, S(50)),
		Parent = root,
	})
	UI.stroke(wave, Theme.Colors.black, S(2), 0.3)

	local starSize = S(22)
	local stars = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, S(52)),
		Size = UDim2.fromOffset(starSize * 5 + S(8), starSize),
		Parent = root,
	})
	UI.list(stars, Enum.FillDirection.Horizontal, S(2), Enum.HorizontalAlignment.Center)
	local clips: { Frame } = {}
	for i = 1, 5 do
		local _, clip = starCell(stars, i, starSize)
		clips[i] = clip
	end

	-- Enemies left under the stars; red and pulsing for the last few.
	local left = UI.text({
		Name = "Left",
		Font = Theme.Fonts.display,
		TextSize = S(14),
		Text = "",
		TextColor3 = Theme.Colors.grey,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, S(76)),
		Size = UDim2.fromOffset(S(160), S(18)),
		Parent = root,
	})
	UI.stroke(left, Theme.Colors.black, S(1), 0.5)

	-- Auto skip toggle (left) and skip votes (right).
	local autoSkip, autoSkipLabel = UI.pill(root, "AUTO SKIP", Theme.Colors.panel2, Theme.Colors.grey, S(24))
	autoSkip.AnchorPoint = Vector2.new(1, 0)
	autoSkip.Position = UDim2.new(0.5, -S(150), 0, S(12))
	local autoStroke = UI.stroke(autoSkip, Theme.Colors.grey, S(1), 0.5)
	local votes, votesLabel = UI.pill(root, "VOTES 0 / 1", Theme.Colors.panel2, Theme.Colors.grey, S(24))
	votes.AnchorPoint = Vector2.new(0, 0)
	votes.Position = UDim2.new(0.5, S(150), 0, S(12))
	local votesStroke = UI.stroke(votes, Theme.Colors.grey, S(1), 0.5)
	local votesHint = UI.text({
		Text = if ClientState.isMobile then "TAP TO SKIP" else "V TO SKIP",
		TextSize = S(10),
		TextColor3 = Theme.Colors.grey,
		Position = UDim2.new(0, 0, 1, S(2)),
		Size = UDim2.new(1, 0, 0, S(14)),
		Visible = false,
		Parent = votes,
	})

	local state = "Intro"
	local endsAt = 0
	local waveStartedAt = 0
	local currentWave = 1
	local lastShown = -1
	local myVote = false
	local myAuto = false
	local voteCount = 0
	local voteNeeded = 1

	local function paintVotes()
		local intermission = state == "Intermission"
		votesLabel.Text = string.format("VOTES %d / %d", voteCount, voteNeeded)
		local on = myVote or myAuto
		votesLabel.TextColor3 = if not intermission
			then Theme.Colors.grey
			elseif on then Theme.Colors.bg
			else Theme.Colors.text
		votes.BackgroundColor3 = if intermission and on then Theme.Colors.gold else Theme.Colors.panel2
		votes.BackgroundTransparency = if intermission then 0 else 0.4
		votesStroke.Color = if intermission then Theme.Colors.gold else Theme.Colors.grey
		votesStroke.Transparency = if intermission then 0 else 0.5
		votesHint.Visible = intermission and not on
	end
	local function paintAuto()
		autoSkipLabel.TextColor3 = if myAuto then Theme.Colors.bg else Theme.Colors.grey
		autoSkip.BackgroundColor3 = if myAuto then Theme.Colors.gold else Theme.Colors.panel2
		autoStroke.Color = if myAuto then Theme.Colors.gold else Theme.Colors.grey
		autoStroke.Transparency = if myAuto then 0 else 0.5
	end
	paintVotes()
	paintAuto()

	local function castVote()
		if state ~= "Intermission" then
			UI.shake(votes, S(2), 0.15)
			UI.sound(Theme.Sounds.deny, 1.2, 0.25)
			return
		end
		myVote = not myVote
		paintVotes()
		UI.sound(Theme.Sounds.toast, if myVote then 1.4 else 0.9, 0.4)
		Remotes.VoteSkip:FireServer(myVote)
	end
	pillButton(votes, castVote)
	pillButton(autoSkip, function()
		myAuto = not myAuto
		paintAuto()
		paintVotes()
		UI.sound(Theme.Sounds.toast, if myAuto then 1.4 else 0.9, 0.4)
		Remotes.SetAutoSkip:FireServer(myAuto)
	end)
	track(UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or ClientState.blocked() then
			return
		end
		if input.KeyCode == Enum.KeyCode.V then
			castVote()
		end
	end))

	-- Center banner: WAVE N, WAVE N CLEAR, the final countdown digits.
	local bannerToken = 0
	local function banner(text: string, color: Color3, size: number, hold: number, sound: string?, pitch: number?)
		bannerToken += 1
		local token = bannerToken
		local old = gui:FindFirstChild("WaveBanner")
		if old then
			old:Destroy()
		end
		local label = UI.text({
			Name = "WaveBanner",
			Text = text,
			Font = Theme.Fonts.display,
			TextSize = S(size),
			TextColor3 = color,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.36, 0),
			Size = UDim2.new(1, 0, 0, S(size + 20)),
			ZIndex = 6,
			Parent = gui,
		})
		UI.stroke(label, Theme.Colors.black, S(3), 0.2)
		UI.punch(label, 1.7, 0.45)
		if sound then
			UI.sound(sound, pitch or 1, 0.6)
		end
		task.delay(hold, function()
			if token ~= bannerToken or not label.Parent then
				return
			end
			UI.tween(label, { Position = UDim2.new(0.5, 0, 0.3, 0), TextTransparency = 1 }, 0.4)
			local stroke = label:FindFirstChildOfClass("UIStroke")
			if stroke then
				UI.tween(stroke, { Transparency = 1 }, 0.4)
			end
			task.delay(0.45, function()
				if label.Parent then
					label:Destroy()
				end
			end)
		end)
	end

	local lastAutoText = ""
	track(RunService.Heartbeat:Connect(function()
		-- AUTO SKIP counts down to the next wave during a wave.
		local autoText = "AUTO SKIP"
		if myAuto and state == "Wave" then
			local remaining = math.ceil(waveStartedAt + Config.AutoSkipWaveSec - ClientState.serverNow())
			autoText = if remaining > 0 then string.format("AUTO SKIP %ds", remaining) else "AUTO SKIP · NEXT"
		end
		if autoText ~= lastAutoText then
			lastAutoText = autoText
			autoSkipLabel.Text = autoText
			if myAuto and state == "Wave" then
				UI.punch(autoSkip, 1.06, 0.15)
			end
		end
		if state == "Intermission" then
			local remaining = math.max(0, math.ceil(endsAt - ClientState.serverNow()))
			if remaining ~= lastShown then
				lastShown = remaining
				wave.Text = string.format("NEXT WAVE IN %d", remaining)
				wave.TextColor3 = Theme.Colors.gold
				UI.punch(wave, 1.08, 0.2)
				if remaining >= 1 and remaining <= Config.CountdownTickFrom then
					banner(
						tostring(remaining),
						if remaining == 1 then Theme.Colors.red else Theme.Colors.gold,
						96,
						0.5,
						Theme.Sounds.reelTick,
						0.9 + (Config.CountdownTickFrom - remaining) * 0.25
					)
				end
			end
		end
	end))

	local shownHeat = -1
	local function setHeat(value: number, animate: boolean?)
		for i, clip in clips do
			local target = UDim2.fromScale(math.clamp(value - (i - 1), 0, 1), 1)
			if animate then
				UI.tween(clip, { Size = target }, 0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			else
				clip.Size = target
			end
		end
		shownHeat = value
	end

	local lastLeft = -1
	local leftPulse = 0
	track(RunService.Heartbeat:Connect(function(dt)
		if left.Visible and lastLeft > 0 and lastLeft <= 3 then
			leftPulse += dt * 6
			left.TextTransparency = 0.25 + 0.25 * math.sin(leftPulse)
		end
	end))
	local function setLeft(n: number)
		if state ~= "Wave" or n <= 0 then
			left.Visible = false
			lastLeft = -1
			return
		end
		left.Visible = true
		left.Text = string.format("%d LEFT", n)
		left.TextColor3 = if n <= 3 then Theme.Colors.red else Theme.Colors.grey
		left.TextTransparency = 0
		if lastLeft > 0 and n < lastLeft then
			UI.punch(left, if n <= 3 then 1.5 else 1.15, 0.25)
		end
		lastLeft = n
	end

	local component = {}

	-- Staging (the yard): the bar reads STAGING, no stars, no pills. Run over: RUN OVER.
	local function paintState()
		local inRun = state == "Intro" or state == "Wave" or state == "Intermission"
		stars.Visible = inRun
		autoSkip.Visible = inRun
		votes.Visible = inRun
		if not inRun then
			left.Visible = false
			lastLeft = -1
		end
	end

	function component.update(sync: any)
		local wasState = state
		state = sync.waveState
		endsAt = sync.intermissionEndsAt
		waveStartedAt = sync.waveStartedAt or waveStartedAt
		currentWave = sync.wave
		if state == "Staging" then
			wave.Text = "STAGING"
			wave.TextColor3 = Theme.Colors.grey
			lastShown = -1
		elseif state == "RunOver" or state == "RunEnd" or state == "Summary" then
			wave.Text = "RUN OVER"
			wave.TextColor3 = Theme.Colors.red
			lastShown = -1
		elseif state ~= "Intermission" then
			wave.Text = string.format("WAVE %d", currentWave)
			wave.TextColor3 = Theme.Colors.text
			lastShown = -1
		end
		if wasState ~= state then
			paintState()
		end
		if shownHeat < 0 then
			setHeat(sync.heat)
		end
		voteCount = sync.skipVotes or 0
		voteNeeded = sync.skipNeeded or 1
		myVote = sync.myVote == true
		myAuto = sync.autoSkip == true
		if wasState ~= state then
			paintAuto()
		end
		paintVotes()
		setLeft(sync.enemiesLeft or 0)
	end

	function component.onJuice(name: string, data: any)
		if name == "WaveStart" then
			state = if data.intro then "Intro" else "Wave"
			paintState()
			waveStartedAt = ClientState.serverNow()
			currentWave = data.wave
			wave.Text = string.format("WAVE %d", data.wave)
			wave.TextColor3 = Theme.Colors.text
			UI.punch(wave, 1.5, 0.45)
			UI.sound(Theme.Sounds.wave, 0.8, 0.5)
			myVote = false
			paintVotes()
			if data.intro then
				banner("GET READY", Theme.Colors.gold, 64, Config.WaveBannerHoldSec + 0.6)
			else
				banner(string.format("WAVE %d", data.wave), Theme.Colors.text, 80, Config.WaveBannerHoldSec)
			end
		elseif name == "Intermission" then
			state = "Intermission"
			endsAt = data.endsAt
			lastShown = -1
			setLeft(0)
			paintVotes()
			banner(
				string.format("WAVE %d CLEAR", data.wave or currentWave),
				Theme.Colors.cash,
				64,
				Config.WaveBannerHoldSec,
				Theme.Sounds.legendary,
				1.2
			)
			ClientState.Juice:Fire("RarityFlash", { color = Theme.Colors.cash, alpha = 0.2 })
		elseif name == "RunOver" then
			state = "RunOver"
			paintState()
			wave.Text = "RUN OVER"
			wave.TextColor3 = Theme.Colors.red
			banner(
				string.format("RUN OVER · WAVE %d", data.wave or currentWave),
				Theme.Colors.red,
				72,
				(data.slowSec or 1) + (data.holdSec or 2.5) - 0.5,
				Theme.Sounds.wave,
				0.45
			)
			ClientState.Juice:Fire("RarityFlash", { color = Theme.Colors.red, alpha = 0.35 })
			ClientState.Juice:Fire("Shake", { amp = 0.5, dur = 0.4 })
		elseif name == "SkipVote" then
			voteCount = data.votes or voteCount
			voteNeeded = data.needed or voteNeeded
			if data.userId == Players.LocalPlayer.UserId then
				if data.auto then
					myAuto = data.on == true
					paintAuto()
				else
					myVote = data.on == true
				end
			end
			paintVotes()
			UI.punch(votes, 1.2, 0.3)
		elseif name == "SkipPassed" then
			votes.BackgroundColor3 = Theme.Colors.cash
			votesStroke.Color = Theme.Colors.cash
			UI.punch(votes, 1.4, 0.4)
			UI.sound(Theme.Sounds.toast, 1.6, 0.5)
		elseif name == "HeatChanged" then
			local up = (data.delta or 0) > 0
			local color = if up then Theme.Colors.gold else Theme.Colors.red
			-- The row stretches wide and settles, each star pops in sequence, the changed star flashes.
			UI.punch(stars, if up then 1.9 else 0.5, 0.7)
			local changed = math.clamp(math.ceil(if up then data.value else data.value + 0.5), 1, 5)
			for i, clip in clips do
				local cell = clip.Parent :: GuiObject
				task.delay((i - 1) * 0.06, function()
					if not cell.Parent then
						return
					end
					UI.punch(cell, if i == changed then 2.4 else 1.5, 0.5)
					local goldStar = clip:FindFirstChildOfClass("TextLabel")
					if goldStar then
						goldStar.TextColor3 = if up then Theme.Colors.white else Theme.Colors.red
						UI.tween(goldStar, { TextColor3 = Theme.Colors.gold }, 0.5, nil, nil, 0.1)
					end
				end)
			end
			task.delay(0.2, function()
				setHeat(data.value, true)
			end)
			-- Big label under the stars, then a screen flash and shake.
			local label = UI.text({
				Text = if up then "HEAT UP" else "HEAT DOWN",
				Font = Theme.Fonts.display,
				TextSize = S(26),
				TextColor3 = color,
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, S(94)),
				Size = UDim2.fromOffset(S(240), S(32)),
				Parent = root,
			})
			UI.stroke(label, Theme.Colors.black, S(2), 0.3)
			UI.punch(label, 1.6, 0.5)
			UI.tween(label, { Position = UDim2.new(0.5, 0, 0, S(112)), TextTransparency = 1 }, 0.6, nil, nil, 0.6)
			task.delay(1.3, function()
				label:Destroy()
			end)
			ClientState.Juice:Fire("RarityFlash", { color = color, alpha = 0.25 })
			ClientState.Juice:Fire("Shake", { amp = if up then 0.2 else 0.35, dur = 0.25 })
			UI.sound(if up then Theme.Sounds.legendary else Theme.Sounds.deny, if up then 1.3 else 0.7, 0.6)
		end
	end

	component.frame = root
	return component
end

return WaveBar
