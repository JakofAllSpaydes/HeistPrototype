--!strict
-- Frequency jam (drag). Two waveforms on a scope: one fixed, one driven by a horizontal slider. Bring the
-- driven wave's frequency within FreqTolerance of the fixed one and hold for FreqLockSec to lock. The
-- moving wave tints red to green as it aligns; on lock both flash and merge. Tier adds locks and widens
-- the slider range.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local Frame = require(script.Parent.Frame)

local SAMPLES = 64

local Freq = {
	title = "FREQUENCY JAM",
	hint = "SLIDE UNTIL THE WAVES OVERLAP, THEN HOLD",
	color = Theme.Colors.red,
	aspect = 0.85,
}

function Freq.open(host: Frame.Host)
	local u = host.u
	local locksNeeded = Config.FreqLocksByTier[host.tier] or Config.FreqLocksByTier[1]
	local range = Config.FreqRangeByTier[host.tier] or Config.FreqRangeByTier[1]
	local tol = Config.FreqTolerance

	-- Scope.
	local scopeX, scopeY = u(16), u(8)
	local scopeW, scopeH = host.width - u(32), math.floor(host.height * 0.6)
	local scope = UI.frame({
		BackgroundColor3 = Theme.Colors.black,
		Position = UDim2.fromOffset(scopeX, scopeY),
		Size = UDim2.fromOffset(scopeW, scopeH),
		ClipsDescendants = true,
		Parent = host.content,
	})
	UI.corner(scope, u(10))
	local scopeStroke = UI.stroke(scope, Theme.Colors.grey, u(2), 0.4)
	for i = 1, 3 do
		UI.frame({
			BackgroundColor3 = Theme.Colors.panel2,
			Position = UDim2.new(0, 0, i / 4, 0),
			Size = UDim2.new(1, 0, 0, 1),
			Parent = scope,
		})
	end
	for i = 1, 7 do
		UI.frame({
			BackgroundColor3 = Theme.Colors.panel2,
			Position = UDim2.new(i / 8, 0, 0, 0),
			Size = UDim2.new(0, 1, 1, 0),
			Parent = scope,
		})
	end
	local midY = scopeH / 2
	local amp = scopeH * 0.32

	local function makeWave(color: Color3, thickness: number, zIndex: number): { Frame }
		local segs = {}
		for i = 1, SAMPLES - 1 do
			segs[i] = Frame.line(scope, Vector2.new(0, midY), Vector2.new(1, midY), thickness, color, zIndex)
		end
		return segs
	end
	local function drawWave(segs: { Frame }, freq: number, thickness: number)
		local prev: Vector2? = nil
		for i = 1, SAMPLES do
			local x = (i - 1) / (SAMPLES - 1) * scopeW
			local y = midY - math.sin((i - 1) / (SAMPLES - 1) * math.pi * 2 * freq) * amp
			local p = Vector2.new(x, y)
			if prev then
				Frame.setLine(segs[i - 1], prev, p, thickness)
			end
			prev = p
		end
	end
	local fixedSegs = makeWave(Theme.Colors.textDim, u(3), 2)
	local liveSegs = makeWave(Theme.Colors.red, u(4), 3)

	-- Slider.
	local trackY = scopeY + scopeH + u(34)
	local trackW = scopeW - u(40)
	local trackX = scopeX + u(20)
	local track = UI.frame({
		BackgroundColor3 = Theme.Colors.panel2,
		Position = UDim2.fromOffset(trackX, trackY),
		Size = UDim2.fromOffset(trackW, u(8)),
		Parent = host.content,
	})
	UI.corner(track, u(4))
	local knob = UI.frame({
		BackgroundColor3 = Theme.Colors.text,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(trackX, trackY + u(4)),
		Size = UDim2.fromOffset(u(30), u(30)),
		ZIndex = 4,
		Parent = host.content,
	})
	UI.corner(knob, u(15))
	UI.stroke(knob, Theme.Colors.black, u(2), 0.4)
	-- Lock progress bar under the slider.
	local holdBar = UI.frame({
		BackgroundColor3 = Theme.Colors.panel2,
		Position = UDim2.fromOffset(trackX, trackY + u(26)),
		Size = UDim2.fromOffset(trackW, u(5)),
		Parent = host.content,
	})
	UI.corner(holdBar, u(2))
	local holdFill = UI.frame({
		BackgroundColor3 = Theme.Colors.cash,
		Size = UDim2.fromScale(0, 1),
		Parent = holdBar,
	})
	UI.corner(holdFill, u(2))
	-- Pips on the right of the hint line.
	local pips: { Frame } = {}
	local pipSize = u(12)
	local pipRow = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(host.width / 2, trackY + u(40)),
		Size = UDim2.fromOffset(locksNeeded * (pipSize + u(8)), pipSize),
		Parent = host.content,
	})
	UI.list(pipRow, Enum.FillDirection.Horizontal, u(8), Enum.HorizontalAlignment.Center)
	for p = 1, locksNeeded do
		local pip = UI.frame({
			BackgroundColor3 = Theme.Colors.panel2,
			Size = UDim2.fromOffset(pipSize, pipSize),
			LayoutOrder = p,
			Parent = pipRow,
		})
		UI.corner(pip, pipSize / 2)
		UI.stroke(pip, Theme.Colors.grey, u(1), 0.5)
		pips[p] = pip
	end

	local locks = 0
	local baseFreq = 3
	local t = 0.5 -- slider 0..1
	local alignedSince = -1
	local done = false
	local merging = false

	-- The slider spans a fixed band around FreqCenter; each target lands somewhere new inside it (it used to be
	-- scaled off the target, which put every answer at the same slider spot).
	local fmin, fmax = Config.FreqCenter / range, Config.FreqCenter * range
	local function freqAt(slider: number): number
		return fmin + slider * (fmax - fmin)
	end

	local lastAnswer = -1
	local function newTarget()
		local edge = Config.FreqTargetEdge
		local answer
		repeat
			answer = edge + math.random() * (1 - 2 * edge)
		until lastAnswer < 0 or math.abs(answer - lastAnswer) > Config.FreqTargetMinMove
		lastAnswer = answer
		baseFreq = freqAt(answer)
		drawWave(fixedSegs, baseFreq, u(3))
		-- Start the slider well away from the answer.
		repeat
			t = math.random()
		until math.abs(t - answer) > 0.2
		alignedSince = -1
	end
	newTarget()

	local function paintKnob()
		knob.Position = UDim2.fromOffset(trackX + t * trackW, trackY + u(4))
	end
	paintKnob()

	local t0 = 0
	local p0 = Vector2.zero
	local dragArea = UI.button({
		BackgroundTransparency = 1,
		Text = "",
		Position = UDim2.fromOffset(trackX - u(24), trackY - u(28)),
		Size = UDim2.fromOffset(trackW + u(48), u(64)),
		ZIndex = 6,
		Parent = host.content,
	})
	local releaseDrag = Frame.drag(host, dragArea, function(p: Vector2)
		t0 = t
		p0 = p
		UI.punch(knob, 1.2, 0.15)
	end, function(p: Vector2)
		if done or merging then
			return
		end
		t = math.clamp(t0 + (p.X - p0.X) / trackW, 0, 1)
		paintKnob()
	end, function(_p: Vector2) end)

	host.track(RunService.Heartbeat:Connect(function()
		if done or merging then
			return
		end
		local f = freqAt(t)
		local off = math.abs(f - baseFreq) / baseFreq
		local closeness = math.clamp(1 - off / 0.5, 0, 1)
		local color = Theme.Colors.red:Lerp(Theme.Colors.cash, closeness)
		drawWave(liveSegs, f, u(4))
		for _, s in liveSegs do
			s.BackgroundColor3 = color
		end
		knob.BackgroundColor3 = color
		local aligned = off <= tol
		if aligned then
			if alignedSince < 0 then
				alignedSince = os.clock()
				UI.sound(Theme.Sounds.reelTick, 1.6, 0.3)
			end
			local progress = math.clamp((os.clock() - alignedSince) / Config.FreqLockSec, 0, 1)
			holdFill.Size = UDim2.fromScale(progress, 1)
			scopeStroke.Color = Theme.Colors.cash
			scopeStroke.Transparency = 0
			if progress >= 1 then
				-- Lock: both waves flash and merge into one line.
				locks += 1
				merging = true
				-- Drop the hold: the next frequency needs a fresh press, so a held slider can't drift onto it.
				releaseDrag()
				pips[locks].BackgroundColor3 = Theme.Colors.cash
				UI.punch(pips[locks], 1.5, 0.3)
				host.haptic(1)
				UI.sound(Theme.Sounds.take, 1 + locks * 0.15, 0.6)
				drawWave(liveSegs, baseFreq, u(4))
				for _, s in liveSegs do
					s.BackgroundColor3 = Theme.Colors.white
				end
				for _, s in fixedSegs do
					s.BackgroundColor3 = Theme.Colors.white
				end
				task.delay(0.35, function()
					if not host.alive() then
						return
					end
					for _, s in fixedSegs do
						s.BackgroundColor3 = Theme.Colors.textDim
					end
					if locks >= locksNeeded then
						done = true
						host.finish("done")
						return
					end
					merging = false
					holdFill.Size = UDim2.fromScale(0, 1)
					newTarget()
					paintKnob()
					host.setHint(
						string.format("%d / %d LOCKED · FIND THE NEXT", locks, locksNeeded),
						Theme.Colors.cash
					)
				end)
			end
		else
			alignedSince = -1
			holdFill.Size = UDim2.fromScale(0, 1)
			scopeStroke.Color = Theme.Colors.grey
			scopeStroke.Transparency = 0.4
		end
	end))
end

return Freq
