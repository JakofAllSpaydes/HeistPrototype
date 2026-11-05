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
local Lines = require(Shared:WaitForChild("CrewCall"):WaitForChild("Lines"))

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

	-- Mobile: a small ≡ chip beside N LEFT hints that tapping the wave bar opens the scoreboard.
	if ClientState.isMobile then
		local chip = UI.frame({
			Name = "ScoreChip",
			BackgroundColor3 = Theme.Colors.panel,
			BackgroundTransparency = 0.3,
			AnchorPoint = Vector2.new(0, 0),
			Position = UDim2.new(0.5, S(86), 0, S(74)),
			Size = UDim2.fromOffset(S(24), S(20)),
			Parent = root,
		})
		UI.corner(chip, S(6))
		UI.stroke(chip, Theme.Colors.grey, S(1), 0.5)
		UI.text({
			Text = "≡",
			Font = Theme.Fonts.display,
			TextSize = S(16),
			TextColor3 = Theme.Colors.grey,
			Size = UDim2.fromScale(1, 1),
			Parent = chip,
		})
		-- Under the pills (ZIndex 0) so AUTO SKIP and VOTES still take their taps.
		local tap = UI.button({
			Name = "ScoreTap",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, S(96)),
			ZIndex = 0,
			Parent = root,
		})
		tap.Activated:Connect(function()
			ClientState.Juice:Fire("ToggleScoreboard", {})
			UI.punch(chip, 1.2, 0.2)
		end)
	end

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
		if gameProcessed or ClientState.blocked() or ClientState.inHub() then
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
	local heatFloats = 0
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

	-- Hub (the yard): the bar is hidden by the hub HUD; it reads HUB if ever shown. Run over: RUN OVER.
	local function paintState()
		local inRun = state == "Intro" or state == "Wave" or state == "Intermission" or state == "Dealer"
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
		if state == "Hub" then
			wave.Text = "HUB"
			wave.TextColor3 = Theme.Colors.grey
			lastShown = -1
		elseif state == "RunOver" or state == "RunEnd" or state == "Summary" then
			wave.Text = "RUN OVER"
			wave.TextColor3 = Theme.Colors.red
			lastShown = -1
		elseif state == "Dealer" then
			wave.Text = "DEALER"
			wave.TextColor3 = Theme.Colors.amber
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
		elseif name == "CallStart" and data.jobKind == "vault" then
			-- CRACK THE VAULT is impossible to miss: the stamp in the wave-banner style with the job sting.
			banner("VAULT JOB", Theme.Colors.amber, 76, Config.VaultStampSec, Theme.Sounds.call, 0.85)
			ClientState.Juice:Fire("RarityFlash", { color = Theme.Colors.amber, alpha = 0.2 })
		elseif name == "RunResumed" then
			banner("SECOND CHANCE", Theme.Colors.cash, 64, 1.2, Theme.Sounds.legendary, 1.1)
			ClientState.Juice:Fire("RarityFlash", { color = Theme.Colors.cash, alpha = 0.3 })
		elseif name == "BossDown" then
			banner(
				string.format(Lines.boss.downStamp, string.upper(tostring(data.name or "BOSS"))),
				Theme.Colors.red,
				84,
				1.8,
				Theme.Sounds.legendary,
				0.9
			)
			ClientState.Juice:Fire("RarityFlash", { color = Theme.Colors.red, alpha = 0.4 })
			ClientState.Juice:Fire("Shake", { amp = 0.6, dur = 0.5 })
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
			-- Heat as pace: the changed star pops and a small `+0.5 FAST CLEAR` floats off the row's edge with
			-- the reason. Quiet on purpose; several components stack a beat apart at wave end.
			local delta = tonumber(data.delta) or 0
			local up = delta > 0
			local color = if up then Theme.Colors.gold else Theme.Colors.red
			local changed = math.clamp(math.ceil(if up then data.value else data.value + 0.5), 1, 5)
			local cell = clips[changed] and clips[changed].Parent
			if cell and cell:IsA("GuiObject") then
				UI.punch(cell, if up then 1.8 else 0.6, 0.4)
				local goldStar = clips[changed]:FindFirstChildOfClass("TextLabel")
				if goldStar then
					goldStar.TextColor3 = if up then Theme.Colors.white else Theme.Colors.red
					UI.tween(goldStar, { TextColor3 = Theme.Colors.gold }, 0.5, nil, nil, 0.1)
				end
			end
			setHeat(data.value, true)
			heatFloats += 1
			local slot = heatFloats
			local float = UI.text({
				Text = string.format(
					"%s%s %s",
					if up then "+" else "−",
					UI.fmtNum(math.abs(delta)),
					tostring(data.reason or "")
				),
				Font = Theme.Fonts.display,
				TextSize = S(13),
				TextColor3 = color,
				TextXAlignment = Enum.TextXAlignment.Left,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0.5, S(70), 0, S(63)),
				Size = UDim2.fromOffset(S(180), S(16)),
				Parent = root,
			})
			UI.stroke(float, Theme.Colors.black, S(1.5), 0.3)
			UI.punch(float, 1.3, 0.3)
			UI.tween(
				float,
				{ Position = UDim2.new(0.5, S(70), 0, S(63) - S(22)), TextTransparency = 1 },
				1.1,
				nil,
				nil,
				0.5
			)
			task.delay(1.7, function()
				float:Destroy()
				if heatFloats == slot then
					heatFloats = 0
				end
			end)
			UI.sound(Theme.Sounds.toast, if up then 1.5 else 0.8, 0.35)
		end
	end

	component.frame = root
	return component
end

return WaveBar
