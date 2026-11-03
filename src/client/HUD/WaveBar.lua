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

	local function setHeat(value: number)
		for i, clip in clips do
			clip.Size = UDim2.fromScale(math.clamp(value - (i - 1), 0, 1), 1)
		end
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
		setHeat(sync.heat)
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
		end
	end

	component.frame = root
	return component
end

return WaveBar
