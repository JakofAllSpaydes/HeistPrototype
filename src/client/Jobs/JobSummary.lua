--!strict
-- Brief 6: the summary's Job ticks, after the XP bars: one line per Job that moved this run (`KILL 60 RUNNERS
-- 12 → 30 / 60` with a small bar that ticks up); a finished one reads `JOB DONE · CLAIM AT THE BOARD` and opens the
-- board when tapped.
local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local ClientState = require(Client:WaitForChild("ClientState"))
local Fx = require(Client:WaitForChild("Store"):WaitForChild("Fx"))

local JobSummary = {}

function JobSummary.show(parent: Instance, width: number, position: UDim2, ticks: any, delay: number): Frame?
	if typeof(ticks) ~= "table" or #ticks == 0 then
		return nil
	end
	local S = UI.S
	local rowH = S(30)
	local frame = UI.frame({
		Name = "JobTicks",
		BackgroundColor3 = Color3.fromHex("16140F"),
		BackgroundTransparency = 0.08,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = position,
		Size = UDim2.fromOffset(width, S(10) + #ticks * rowH),
		Visible = false,
		ZIndex = 12,
		Parent = parent,
	})
	UI.corner(frame, S(10))
	UI.stroke(frame, Theme.Colors.gold, S(1.5), 0.3)
	for i, t in ticks do
		local y = S(5) + (i - 1) * rowH
		local done = t.done == true
		local row = (if done then UI.button({ Text = "", AutoButtonColor = false }) else UI.frame({})) :: any
		row.BackgroundTransparency = 1
		row.Position = UDim2.fromOffset(S(10), y)
		row.Size = UDim2.new(1, -S(20), 0, rowH - S(2))
		row.ZIndex = 13
		row.Parent = frame
		UI.text({
			Text = (if t.weekly then "BOUNTY · " else "JOB · ") .. tostring(t.title),
			FontFace = Theme.Fonts.display,
			TextSize = S(13),
			TextColor3 = if done then Theme.Colors.gold else Theme.Colors.text,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Size = UDim2.new(0.44, 0, 1, 0),
			ZIndex = 14,
			Parent = row,
		})
		local bar = UI.frame({
			BackgroundColor3 = Color3.fromHex("2A2A33"),
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0.46, 0, 0.5, 0),
			Size = UDim2.new(0.22, 0, 0, S(8)),
			ZIndex = 14,
			Parent = row,
		})
		UI.corner(bar, S(4))
		local target = math.max(1, tonumber(t.target) or 1)
		local fill = UI.frame({
			BackgroundColor3 = if done then Color3.fromHex("3FD47A") else Theme.Colors.gold,
			Size = UDim2.fromScale(math.clamp((tonumber(t.from) or 0) / target, 0, 1), 1),
			ZIndex = 15,
			Parent = bar,
		})
		UI.corner(fill, S(4))
		local label = UI.text({
			Text = if done
				then "JOB DONE · CLAIM AT THE BOARD"
				else string.format(
					"%s → %s / %s",
					UI.fmtInt(tonumber(t.from) or 0),
					UI.fmtInt(tonumber(t.to) or 0),
					UI.fmtInt(target)
				),
			FontFace = Theme.Fonts.display,
			TextSize = S(12),
			TextColor3 = if done then Color3.fromHex("3FD47A") else Theme.Colors.textDim,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0.31, 0, 1, 0),
			ZIndex = 14,
			Parent = row,
		})
		local _ = label
		if done then
			(row :: TextButton).Activated:Connect(function()
				ClientState.Juice:Fire("OpenJobs", {})
			end)
		end
		task.delay(delay + 0.3 + i * 0.2, function()
			if fill.Parent then
				UI.tween(fill, { Size = UDim2.fromScale(math.clamp((tonumber(t.to) or 0) / target, 0, 1), 1) }, 0.6)
				UI.sound(Fx.Sounds.tick, 1.2 + i * 0.1, 0.25)
				if done then
					UI.punch(row, 1.05, 0.3)
				end
			end
		end)
	end
	task.delay(delay, function()
		if frame.Parent then
			frame.Visible = true
			Fx.slideIn(frame, UDim2.fromOffset(0, S(16)), 0.3)
		end
	end)
	return frame
end

return JobSummary
