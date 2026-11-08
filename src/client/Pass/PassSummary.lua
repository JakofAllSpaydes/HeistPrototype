--!strict
-- Brief 6: the summary screen's PASS XP bar, under the panel after the account XP bar fills: the season diamond
-- with the level, a bar that fills from the run's start to its end (a level crossed pops `PASS LV 8` and bumps the
-- diamond), `+N PASS XP` counting, and CLAIM IN PASS (Round 19c: `onClaim`, the summary sends you back to the hub
-- and the pass opens there, so it never stacks on the end-of-run set).
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PassSeason = require(Shared:WaitForChild("PassSeason"))

local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local ClientState = require(Client:WaitForChild("ClientState"))
local Fx = require(Client:WaitForChild("Store"):WaitForChild("Fx"))

local PassSummary = {}

local ORANGE = Color3.fromHex("E8792A")

-- `award` is the server's Pass.addXp result for the run; `delay` seconds before it slides in. Returns the frame.
function PassSummary.show(
	parent: Instance,
	width: number,
	position: UDim2,
	award: any,
	delay: number,
	onClaim: (() -> ())?
): Frame?
	if typeof(award) ~= "table" then
		return nil
	end
	local S = UI.S
	local per = tonumber(award.perLevel) or Config.PassXpPerLevel
	local frame = UI.frame({
		Name = "PassSummary",
		BackgroundColor3 = Color3.fromHex("141216"),
		BackgroundTransparency = 0.05,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = position,
		Size = UDim2.fromOffset(width, S(58)),
		Visible = false,
		ZIndex = 12,
		Parent = parent,
	})
	UI.corner(frame, S(10))
	UI.stroke(frame, ORANGE, S(1.5), 0.2)
	local diamond = UI.frame({
		BackgroundColor3 = ORANGE,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, S(32), 0.5, 0),
		Size = UDim2.fromOffset(S(32), S(32)),
		Rotation = 45,
		ZIndex = 13,
		Parent = frame,
	})
	UI.corner(diamond, S(5))
	local lv = UI.text({
		Text = tostring(award.fromLevel or 1),
		Font = Theme.Fonts.display,
		TextSize = S(16),
		TextColor3 = Theme.Colors.white,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, S(32), 0.5, 0),
		Size = UDim2.fromOffset(S(36), S(30)),
		ZIndex = 14,
		Parent = frame,
	})
	UI.stroke(lv, Color3.new(0, 0, 0), S(1.5), 0.2)
	UI.text({
		Text = "PASS XP",
		Font = Theme.Fonts.display,
		TextSize = S(13),
		TextColor3 = ORANGE,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(S(60), S(6)),
		Size = UDim2.fromOffset(S(120), S(16)),
		ZIndex = 13,
		Parent = frame,
	})
	local gainLabel = UI.text({
		Text = "+0",
		Font = Theme.Fonts.display,
		TextSize = S(15),
		TextColor3 = Theme.Colors.cash,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -S(170), 0, S(5)),
		Size = UDim2.fromOffset(S(140), S(18)),
		ZIndex = 13,
		Parent = frame,
	})
	local bar = UI.frame({
		BackgroundColor3 = Color3.fromHex("26262E"),
		Position = UDim2.fromOffset(S(60), S(28)),
		Size = UDim2.new(1, -S(230), 0, S(14)),
		ZIndex = 13,
		Parent = frame,
	})
	UI.corner(bar, S(7))
	local fill = UI.frame({
		BackgroundColor3 = ORANGE,
		Size = UDim2.fromScale(math.clamp((tonumber(award.fromXp) or 0) / per, 0, 1), 1),
		ZIndex = 14,
		Parent = bar,
	})
	UI.corner(fill, S(7))
	local claimBtn, _h = Fx.button(
		frame,
		"CLAIM IN PASS",
		Color3.fromHex("2FB75A"),
		Theme.Colors.white,
		UDim2.fromOffset(S(150), S(40)),
		14
	)
	claimBtn.AnchorPoint = Vector2.new(1, 0.5)
	claimBtn.Position = UDim2.new(1, -S(10), 0.5, 0)
	claimBtn.TextSize = S(15)
	claimBtn.Activated:Connect(function()
		if onClaim then
			claimBtn.Text = "TO THE HUB…"
			onClaim()
		else
			ClientState.Juice:Fire("OpenPass", {})
		end
	end)
	local sync = ClientState.sync
	local waiting = PassSeason.claimableCount(sync and sync.profile and sync.profile.pass)
	if waiting > 0 then
		Fx.particles(claimBtn, Color3.fromHex("FFE08A"), 4, 15)
	end

	task.delay(delay, function()
		if not frame.Parent then
			return
		end
		frame.Visible = true
		Fx.slideIn(frame, UDim2.fromOffset(0, S(20)), 0.3)
		UI.sound(Fx.Sounds.whoosh, 1.3, 0.3)
		-- Fill segment by segment: each level crossed, then the remainder.
		local gained = tonumber(award.gained) or 0
		local segments = {}
		local level, x = tonumber(award.fromLevel) or 1, tonumber(award.fromXp) or 0
		local toLevel, toXp = tonumber(award.toLevel) or level, tonumber(award.toXp) or x
		for _ = 1, 60 do
			if level < toLevel then
				table.insert(segments, { from = x, to = per, levelUp = level + 1 })
				level += 1
				x = 0
			else
				table.insert(segments, { from = x, to = toXp, levelUp = nil })
				break
			end
		end
		Fx.countUp(gainLabel, 0, gained, 1.2, function(n: number): string
			return "+" .. UI.fmtInt(n) .. " PASS XP"
		end, true)
		local segSec = 1.2 / math.max(#segments, 1)
		for _, seg in segments do
			fill.Size = UDim2.fromScale(seg.from / per, 1)
			UI.tween(
				fill,
				{ Size = UDim2.fromScale(math.clamp(seg.to / per, 0, 1), 1) },
				segSec,
				Enum.EasingStyle.Linear
			)
			task.wait(segSec)
			if not frame.Parent then
				return
			end
			if seg.levelUp then
				lv.Text = tostring(seg.levelUp)
				UI.punch(diamond, 1.4, 0.35)
				UI.punch(lv, 1.5, 0.35)
				Fx.stinger(3)
				local pop = UI.text({
					Text = "PASS LV " .. seg.levelUp,
					Font = Theme.Fonts.display,
					TextSize = S(16),
					TextColor3 = ORANGE,
					AnchorPoint = Vector2.new(0, 1),
					Position = UDim2.new(0, S(60), 0, -S(2)),
					Size = UDim2.fromOffset(S(200), S(20)),
					TextXAlignment = Enum.TextXAlignment.Left,
					ZIndex = 15,
					Parent = frame,
				})
				UI.stroke(pop, Color3.new(0, 0, 0), S(1.5), 0.2)
				UI.punch(pop, 1.5, 0.3)
				UI.tween(pop, { TextTransparency = 1, Position = UDim2.new(0, S(60), 0, -S(24)) }, 0.9, nil, nil, 0.8)
				task.delay(1.8, function()
					pop:Destroy()
				end)
			end
		end
	end)
	return frame
end

return PassSummary
