--!strict
-- Top-center: WAVE N / NEXT WAVE IN N, heat stars under it, Auto Skip pill left, Votes pill right.
local RunService = game:GetService("RunService")

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

	local autoSkip = UI.pill(root, "AUTO SKIP", Theme.Colors.panel2, Theme.Colors.grey, S(24))
	autoSkip.AnchorPoint = Vector2.new(1, 0)
	autoSkip.Position = UDim2.new(0.5, -S(150), 0, S(12))
	UI.stroke(autoSkip, Theme.Colors.grey, S(1), 0.5)
	local votes = UI.pill(root, "VOTES 0 / 1", Theme.Colors.panel2, Theme.Colors.grey, S(24))
	votes.AnchorPoint = Vector2.new(0, 0)
	votes.Position = UDim2.new(0.5, S(150), 0, S(12))
	UI.stroke(votes, Theme.Colors.grey, S(1), 0.5)

	local state = "Intro"
	local endsAt = 0
	local currentWave = 1
	local lastShown = -1

	track(RunService.Heartbeat:Connect(function()
		if state == "Intermission" then
			local remaining = math.max(0, math.ceil(endsAt - ClientState.serverNow()))
			if remaining ~= lastShown then
				lastShown = remaining
				wave.Text = string.format("NEXT WAVE IN %d", remaining)
				wave.TextColor3 = Theme.Colors.gold
				UI.punch(wave, 1.08, 0.2)
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

	local component = {}

	function component.update(sync: any)
		state = sync.waveState
		endsAt = sync.intermissionEndsAt
		currentWave = sync.wave
		if state ~= "Intermission" then
			wave.Text = string.format("WAVE %d", currentWave)
			wave.TextColor3 = Theme.Colors.text
			lastShown = -1
		end
		if shownHeat < 0 then
			setHeat(sync.heat)
		end
		local players = sync.playerCount or 1
		local votesLabel = votes:FindFirstChildOfClass("TextLabel")
		if votesLabel then
			votesLabel.Text = string.format("VOTES 0 / %d", players)
		end
	end

	function component.onJuice(name: string, data: any)
		if name == "WaveStart" then
			state = "Wave"
			currentWave = data.wave
			wave.Text = string.format("WAVE %d", data.wave)
			wave.TextColor3 = Theme.Colors.text
			UI.punch(wave, 1.5, 0.45)
			UI.sound(Theme.Sounds.wave, 0.8, 0.5)
		elseif name == "Intermission" then
			state = "Intermission"
			endsAt = data.endsAt
			lastShown = -1
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
				Position = UDim2.new(0.5, 0, 0, S(78)),
				Size = UDim2.fromOffset(S(240), S(32)),
				Parent = root,
			})
			UI.stroke(label, Theme.Colors.black, S(2), 0.3)
			UI.punch(label, 1.6, 0.5)
			UI.tween(label, { Position = UDim2.new(0.5, 0, 0, S(96)), TextTransparency = 1 }, 0.6, nil, nil, 0.6)
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
