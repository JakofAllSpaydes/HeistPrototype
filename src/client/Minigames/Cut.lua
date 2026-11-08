--!strict
-- Round 19c: Cut (hold and release). A bolt cutter on a chain: hold anywhere to squeeze, the pressure needle
-- climbs; let go while it is in the green band to cut a link. Squeeze to the top and the jaws slip (a miss, the
-- needle drops back). Each cut link falls away, the next band sits somewhere new and the needle climbs faster.
-- Tier sets the links and the band width. Reused by the door chains (D2) and the CUT THE CHAIN side job.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local Frame = require(script.Parent.Frame)

local STEEL = Color3.fromHex("9BA0A8")
local STEEL_DARK = Color3.fromHex("5A5E66")

local Cut = {
	title = "BOLT CUTTER",
	hint = "HOLD TO SQUEEZE · LET GO IN THE GREEN",
	color = Theme.Colors.amber,
	aspect = 0.8,
}

function Cut.open(host: Frame.Host)
	local u = host.u
	local links = Config.CutLinksByTier[host.tier] or Config.CutLinksByTier[1]
	local band = Config.CutBandByTier[host.tier] or Config.CutBandByTier[1]
	local fillSec = Config.CutFillSec
	local cut = 0
	local fill = 0 -- 0..1 needle
	local holding = false
	local stunUntil = 0
	local done = false
	local bandLo = 0

	-- The chain across the top: links alternate face-on (ring) and edge-on (bar). The live link glows.
	local chainY = math.floor(host.height * 0.24)
	local linkW = math.min(u(54), math.floor((host.width - u(40)) / math.max(links, 1)))
	local rowW = linkW * links
	local x0 = math.floor((host.width - rowW) / 2)
	local linkFrames: { Frame } = {}
	local linkStrokes: { UIStroke } = {}
	for i = 1, links do
		local ring = i % 2 == 1
		local f = UI.frame({
			BackgroundTransparency = if ring then 1 else 0,
			BackgroundColor3 = STEEL,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(x0 + linkW * (i - 0.5), chainY),
			Size = if ring then UDim2.fromOffset(linkW + u(8), u(34)) else UDim2.fromOffset(linkW + u(8), u(10)),
			ZIndex = 3,
			Parent = host.content,
		})
		UI.corner(f, u(17))
		linkStrokes[i] = UI.stroke(f, STEEL, if ring then u(6) else u(2))
		linkFrames[i] = f
	end
	-- The anchor posts at both ends.
	for _, side in { -1, 1 } do
		local post = UI.frame({
			BackgroundColor3 = STEEL_DARK,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(if side < 0 then x0 - u(10) else x0 + rowW + u(10), chainY),
			Size = UDim2.fromOffset(u(12), u(56)),
			ZIndex = 2,
			Parent = host.content,
		})
		UI.corner(post, u(4))
	end

	-- The pressure gauge: a wide bar, the green band, the needle.
	local gaugeW = math.floor(host.width * 0.78)
	local gaugeH = u(30)
	local gaugeY = math.floor(host.height * 0.56)
	local gauge = UI.frame({
		BackgroundColor3 = Theme.Colors.panel2,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(math.floor(host.width / 2), gaugeY),
		Size = UDim2.fromOffset(gaugeW, gaugeH),
		ZIndex = 3,
		Parent = host.content,
	})
	UI.corner(gauge, u(8))
	local gaugeStroke = UI.stroke(gauge, Theme.Colors.grey, u(2))
	local bandFrame = UI.frame({
		BackgroundColor3 = Theme.Colors.cash,
		Size = UDim2.fromScale(band, 1),
		ZIndex = 4,
		Parent = gauge,
	})
	UI.corner(bandFrame, u(6))
	local fillFrame = UI.frame({
		BackgroundColor3 = Theme.Colors.amber,
		BackgroundTransparency = 0.55,
		Size = UDim2.fromScale(0, 1),
		ZIndex = 5,
		Parent = gauge,
	})
	UI.corner(fillFrame, u(6))
	local needle = UI.frame({
		BackgroundColor3 = Theme.Colors.text,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(0, u(5), 1, u(14)),
		ZIndex = 6,
		Parent = gauge,
	})
	UI.corner(needle, u(2))

	-- The cutter's jaws under the gauge: they close with the needle.
	local jawY = math.floor(host.height * 0.8)
	local jaws: { Frame } = {}
	for _, side in { -1, 1 } do
		local jaw = UI.frame({
			BackgroundColor3 = Theme.Colors.malus,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(math.floor(host.width / 2) + side * u(30), jawY),
			Size = UDim2.fromOffset(u(16), u(54)),
			Rotation = side * 18,
			ZIndex = 3,
			Parent = host.content,
		})
		UI.corner(jaw, u(6))
		table.insert(jaws, jaw)
	end

	local function placeBand()
		-- Somewhere in the upper part of the gauge, never at the very bottom (a tap is never a cut).
		bandLo = Config.CutBandMin + math.random() * math.max(0, 0.96 - band - Config.CutBandMin)
		bandFrame.Position = UDim2.fromScale(bandLo, 0)
		bandFrame.Size = UDim2.fromScale(band, 1)
	end
	local function paintLinks()
		for i, s in linkStrokes do
			if i <= cut then
				continue
			end
			s.Color = if i == cut + 1 then Theme.Colors.amber else STEEL
		end
	end
	placeBand()
	paintLinks()

	local function slip()
		host.miss()
		stunUntil = os.clock() + Config.CutSlipSec
		holding = false
		fill = 0
		gaugeStroke.Color = Theme.Colors.red
		UI.tween(gaugeStroke, { Color = Theme.Colors.grey }, 0.35, nil, nil, 0.1)
		host.setHint("SLIPPED · LET GO SOONER", Theme.Colors.red)
		UI.sound(Theme.Sounds.deny, 0.9, 0.45)
	end

	local function release()
		if not holding or done then
			holding = false
			return
		end
		holding = false
		if fill >= bandLo and fill <= bandLo + band then
			cut += 1
			local link = linkFrames[cut]
			-- The cut link splits and drops.
			UI.tween(link, {
				Position = link.Position + UDim2.fromOffset(0, u(140)),
				Rotation = (math.random() - 0.5) * 120,
				BackgroundTransparency = 1,
			}, 0.5)
			UI.tween(linkStrokes[cut], { Transparency = 1 }, 0.5)
			for _, j in jaws do
				UI.punch(j, 1.25, 0.2)
			end
			host.haptic(0.8)
			UI.sound(Theme.Sounds.snip, 1 + cut * 0.05, 0.4) -- Round 19e: a snip, not the crash
			fill = 0
			if cut >= links then
				done = true
				host.stamp("CUT", Theme.Colors.amber)
				host.haptic(1)
				task.delay(0.35, function()
					host.finish("done")
				end)
				return
			end
			fillSec *= Config.CutSpeedUp
			placeBand()
			paintLinks()
			host.setHint(string.format("%d / %d CUT", cut, links), Theme.Colors.amber)
		elseif fill > 0.02 then
			-- Not enough: the jaws spring open (no miss: only an over-squeeze slips).
			host.setHint("MORE PRESSURE", Theme.Colors.text)
			UI.sound(Theme.Sounds.reelTick, 0.6, 0.3)
		end
	end

	-- Hold anywhere on the play area (mouse or touch), or Space / the gamepad's A.
	local area = UI.button({
		BackgroundTransparency = 1,
		Text = "",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 8,
		Parent = host.content,
	})
	Frame.drag(host, { area, host.zone }, function()
		if os.clock() >= stunUntil and not done then
			holding = true
		end
	end, function() end, function()
		release()
	end)
	host.track(UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or done then
			return
		end
		if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonA then
			if os.clock() >= stunUntil then
				holding = true
			end
		end
	end))
	host.track(UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonA then
			release()
		end
	end))

	host.track(RunService.Heartbeat:Connect(function(dt)
		if done then
			return
		end
		if holding then
			fill += dt / math.max(fillSec, 0.1)
			if fill >= 1 then
				slip()
			end
		else
			-- Let go: the needle falls back quickly.
			fill = math.max(0, fill - dt * 3)
		end
		needle.Position = UDim2.fromScale(fill, 0.5)
		fillFrame.Size = UDim2.fromScale(fill, 1)
		local close = math.clamp(fill, 0, 1) * 16
		for i, j in jaws do
			j.Rotation = (if i == 1 then -1 else 1) * (18 - close)
		end
	end))
end

return Cut
