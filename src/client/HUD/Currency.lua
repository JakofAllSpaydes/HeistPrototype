--!strict
-- Bottom-left: Match Cash row with a + button, Gold row. Cash counts up when it changes.
local RunService = game:GetService("RunService")

local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))

local Currency = {}

function Currency.build(gui: ScreenGui, track: (RBXScriptConnection) -> ())
	local S = UI.S
	local root = UI.frame({
		Name = "Currency",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, S(20), 1, -S(20)),
		Size = UDim2.fromOffset(S(260), S(70)),
		Parent = gui,
	})

	-- Cash row
	local cashRow = UI.frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, S(40)), Parent = root })
	local cashIcon = UI.frame({
		BackgroundColor3 = Theme.Colors.cash,
		Size = UDim2.fromOffset(S(30), S(30)),
		Position = UDim2.fromOffset(0, S(5)),
		Parent = cashRow,
	})
	UI.corner(cashIcon, S(8))
	UI.text({
		Text = "$",
		Font = Theme.Fonts.display,
		TextSize = S(22),
		TextColor3 = Theme.Colors.bg,
		Size = UDim2.fromScale(1, 1),
		Parent = cashIcon,
	})
	local cashLabel = UI.text({
		Name = "Cash",
		Text = "$0",
		Font = Theme.Fonts.display,
		TextSize = S(30),
		TextColor3 = Theme.Colors.cash,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(S(40), 0),
		Size = UDim2.new(1, -S(80), 1, 0),
		Parent = cashRow,
	})
	UI.stroke(cashLabel, Theme.Colors.black, S(1.5), 0.4)
	local plus = UI.button({
		Text = "+",
		Font = Theme.Fonts.display,
		TextSize = S(20),
		TextColor3 = Theme.Colors.gold,
		BackgroundColor3 = Theme.Colors.panel,
		Size = UDim2.fromOffset(S(26), S(26)),
		Position = UDim2.fromOffset(S(40) + S(150), S(7)),
		Parent = cashRow,
	})
	UI.corner(plus, S(7))
	UI.stroke(plus, Theme.Colors.gold, S(1.5))
	-- Brief 6: the cash-pack sheet (fake Robux; the game keeps running behind it).
	plus.Activated:Connect(function()
		UI.punch(plus, 0.9, 0.15)
		local sheet = require(Client:WaitForChild("PurchaseSheet") :: ModuleScript) :: any
		sheet.choose("Match cash", { "cash_5k", "cash_20k", "cash_100k" }, { context = "cash +" })
	end)

	-- Banked row: the team's gold bag total, ticks on every bank.
	local bankedRow = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, S(26)),
		Position = UDim2.fromOffset(0, S(42)),
		Parent = root,
	})
	UI.text({
		Text = "◆",
		Font = Theme.Fonts.display,
		TextSize = S(18),
		TextColor3 = Theme.Colors.gold,
		Position = UDim2.fromOffset(S(5), 0),
		Size = UDim2.fromOffset(S(22), S(26)),
		Parent = bankedRow,
	})
	local bankedLabel = UI.text({
		Name = "Banked",
		Text = "0 BANKED",
		Font = Theme.Fonts.display,
		TextSize = S(18),
		TextColor3 = Theme.Colors.gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(S(40), 0),
		Size = UDim2.new(1, -S(40), 1, 0),
		Parent = bankedRow,
	})
	UI.stroke(bankedLabel, Theme.Colors.black, S(1.5), 0.4)

	local shown = 0
	local target = 0
	track(RunService.Heartbeat:Connect(function(dt)
		if shown == target then
			return
		end
		local diff = target - shown
		local step = math.max(1, math.abs(diff) * math.min(1, dt * 8))
		if math.abs(diff) <= step then
			shown = target
		else
			shown += step * math.sign(diff)
		end
		cashLabel.Text = UI.fmtCash(math.floor(shown))
	end))

	local component = {}
	component.frame = root
	component.cashLabel = cashLabel

	local shownBanked = -1
	function component.update(sync: any)
		local banked = tonumber(sync.banked) or 0
		if banked ~= shownBanked then
			bankedLabel.Text = string.format("%s BANKED", UI.fmtNum(banked))
			if shownBanked >= 0 and banked > shownBanked then
				UI.punch(bankedLabel, 1.2, 0.3)
			end
			shownBanked = banked
		end
		if sync.cash ~= target then
			target = sync.cash
			if target > shown then
				UI.punch(cashLabel, 1.12, 0.25)
			else
				-- Spend: flash the row and show the amount leaving.
				UI.shake(cashRow, S(2), 0.15)
				cashLabel.TextColor3 = Theme.Colors.malus
				UI.tween(cashLabel, { TextColor3 = Theme.Colors.cash }, 0.4)
				local spent = UI.text({
					Text = "-" .. UI.fmtCash(shown - target),
					Font = Theme.Fonts.display,
					TextSize = S(20),
					TextColor3 = Theme.Colors.malus,
					TextXAlignment = Enum.TextXAlignment.Left,
					Position = UDim2.fromOffset(S(40), -S(10)),
					Size = UDim2.fromOffset(S(160), S(24)),
					Parent = root,
				})
				UI.tween(spent, { Position = UDim2.fromOffset(S(40), -S(40)), TextTransparency = 1 }, 0.7)
				task.delay(0.75, function()
					spent:Destroy()
				end)
			end
		end
	end

	return component
end

return Currency
