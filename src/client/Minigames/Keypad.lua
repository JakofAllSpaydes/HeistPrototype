--!strict
-- Keypad (tap-sequence). The code shows on the display for KeypadShowSec, fades, then the pad lights.
-- Type it. A wrong digit flashes the display red, re-shows the code briefly and clears the entry.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local Frame = require(script.Parent.Frame)

local Keypad = {
	title = "KEYPAD",
	hint = "MEMORISE THE CODE, THEN TYPE IT · TYPE EARLY TO HIDE IT",
	padHint = "MEMORISE THE CODE · {DPadUp} MOVE · {ButtonA} PRESS · {ButtonB} BACK",
	color = Theme.Colors.cash,
	aspect = 1.15,
}

function Keypad.open(host: Frame.Host)
	local u = host.u
	local digits = Config.KeypadDigitsByTier[host.tier] or Config.KeypadDigitsByTier[1]
	local code = {}
	for i = 1, digits do
		code[i] = math.random(0, 9)
	end
	local codeText = ""
	for _, d in code do
		codeText ..= tostring(d) .. " "
	end
	codeText = string.sub(codeText, 1, -2)

	local entered = 0
	local showing = true -- taps ignored while the code is on the display
	local done = false
	local showToken = 0

	-- Display
	local display = UI.frame({
		BackgroundColor3 = Theme.Colors.black,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, u(6)),
		Size = UDim2.fromOffset(host.width - u(40), u(62)),
		Parent = host.content,
	})
	UI.corner(display, u(10))
	local displayStroke = UI.stroke(display, Theme.Colors.grey, u(2), 0.4)
	local codeLabel = UI.text({
		Text = codeText,
		FontFace = Theme.Fonts.mono,
		TextSize = u(34),
		TextColor3 = Theme.Colors.cash,
		Size = UDim2.fromScale(1, 1),
		Parent = display,
	})
	-- Entry dots under the display, one per digit.
	local dots: { Frame } = {}
	local dotSize = u(14)
	local dotRow = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, u(74)),
		Size = UDim2.fromOffset(digits * (dotSize + u(10)), dotSize),
		Parent = host.content,
	})
	UI.list(dotRow, Enum.FillDirection.Horizontal, u(10), Enum.HorizontalAlignment.Center)
	for i = 1, digits do
		local dot = UI.frame({
			BackgroundColor3 = Theme.Colors.panel2,
			Size = UDim2.fromOffset(dotSize, dotSize),
			LayoutOrder = i,
			Parent = dotRow,
		})
		UI.corner(dot, dotSize / 2)
		UI.stroke(dot, Theme.Colors.grey, u(1), 0.5)
		dots[i] = dot
	end
	local function paintDots()
		for i, dot in dots do
			dot.BackgroundColor3 = if i <= entered then Theme.Colors.cash else Theme.Colors.panel2
		end
	end

	-- Pad: 3 x 4, digits 1-9 then 0 in the middle of the last row.
	local padTop = u(96)
	local padH = host.height - padTop - u(8)
	local cols, rows = 3, 4
	local gap = u(8)
	local keyW = math.floor((host.width - u(40) - gap * (cols - 1)) / cols)
	local keyH = math.floor((padH - gap * (rows - 1)) / rows)
	local pad = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, padTop),
		Size = UDim2.fromOffset(keyW * cols + gap * (cols - 1), padH),
		Parent = host.content,
	})
	local keys: { TextButton } = {}
	local function paintPad(lit: boolean)
		for _, k in keys do
			k.TextColor3 = if lit then Theme.Colors.text else Theme.Colors.grey
			k.BackgroundColor3 = if lit then Theme.Colors.panel2 else Theme.Colors.panel
		end
	end

	local function showCode(seconds: number)
		showToken += 1
		local token = showToken
		showing = true
		codeLabel.Text = codeText
		codeLabel.TextTransparency = 0
		codeLabel.TextColor3 = Theme.Colors.cash
		paintPad(false)
		task.delay(seconds, function()
			if token ~= showToken or not host.alive() then
				return
			end
			UI.tween(codeLabel, { TextTransparency = 1 }, 0.3)
			task.delay(0.3, function()
				if token ~= showToken or not host.alive() then
					return
				end
				codeLabel.Text = string.rep("· ", digits)
				codeLabel.TextTransparency = 0
				codeLabel.TextColor3 = Theme.Colors.grey
				showing = false
				paintPad(true)
				UI.punch(pad, 1.04, 0.2)
				UI.sound(Theme.Sounds.toast, 1.3, 0.35)
			end)
		end)
	end

	local function press(digit: number)
		if done then
			return
		end
		if showing then
			-- Typing early is allowed: the code hides at once and the pad lights.
			showToken += 1
			showing = false
			codeLabel.Text = string.rep("· ", digits)
			codeLabel.TextTransparency = 0
			codeLabel.TextColor3 = Theme.Colors.grey
			paintPad(true)
		end
		if digit == code[entered + 1] then
			entered += 1
			paintDots()
			UI.punch(dots[entered], 1.5, 0.25)
			host.haptic(0.4)
			UI.sound(Theme.Sounds.reelTick, 1.1 + entered * 0.1, 0.4)
			if entered >= digits then
				done = true
				display.BackgroundColor3 = Theme.Colors.cash
				displayStroke.Color = Theme.Colors.cash
				codeLabel.Text = codeText
				codeLabel.TextColor3 = Theme.Colors.bg
				paintPad(false)
				host.finish("done")
			end
			return
		end
		-- Wrong digit: red flash, the code shows again, entry clears.
		host.miss()
		entered = 0
		paintDots()
		display.BackgroundColor3 = Theme.Colors.red
		UI.tween(display, { BackgroundColor3 = Theme.Colors.black }, 0.35)
		showCode(Config.KeypadReshowSec)
	end

	local layout = { 1, 2, 3, 4, 5, 6, 7, 8, 9, -1, 0, -1 }
	for i, digit in layout do
		if digit < 0 then
			continue
		end
		local col = (i - 1) % cols
		local row = math.floor((i - 1) / cols)
		local key = UI.button({
			Text = tostring(digit),
			FontFace = Theme.Fonts.display,
			TextSize = math.floor(keyH * 0.55),
			TextColor3 = Theme.Colors.grey,
			BackgroundColor3 = Theme.Colors.panel,
			Position = UDim2.fromOffset(col * (keyW + gap), row * (keyH + gap)),
			Size = UDim2.fromOffset(keyW, keyH),
			Parent = pad,
		})
		UI.corner(key, u(10))
		UI.stroke(key, Theme.Colors.grey, u(1), 0.5)
		table.insert(keys, key)
		Frame.press(host, key, function()
			UI.punch(key, 0.9, 0.12)
			press(digit)
		end)
		-- Brief 11: the pad walks the keys (GamepadNav) and A presses the selected one.
		host.track(key.Activated:Connect(function(input: InputObject?)
			if input and string.sub(input.UserInputType.Name, 1, 7) == "Gamepad" and host.alive() then
				UI.punch(key, 0.9, 0.12)
				press(digit)
			end
		end))
		if digit == 5 then
			key:SetAttribute("NavDefault", true)
		end
	end
	-- B takes back the last digit; with nothing typed it leaves the game.
	host.pad = {
		navWalk = true,
		button = function(k: string, down: boolean): boolean?
			if k == "ButtonB" and down and entered > 0 and not done then
				entered -= 1
				paintDots()
				UI.sound(Theme.Sounds.reelTick, 0.8, 0.3)
				return true
			end
			return false
		end,
	}

	showCode(Config.KeypadShowSec)
end

return Keypad
