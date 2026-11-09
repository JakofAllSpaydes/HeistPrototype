--!strict
-- Arm charges (tap-sequence). Numbered blast caps on a wall; press 1 to N in order. An armed cap turns
-- amber with a wire lighting to the next; a wrong cap pulses every cap red and resets the chain.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local Frame = require(script.Parent.Frame)

local Charges = {
	title = "ARM CHARGES",
	hint = "PRESS THE CAPS IN ORDER, 1 FIRST",
	padHint = "{DPadUp} TO A CAP · {ButtonA} PRESS · IN ORDER, 1 FIRST",
	color = Theme.Colors.amber,
	aspect = 0.9,
}

type Cap = { number: number, button: TextButton, stroke: UIStroke, center: Vector2 }

function Charges.open(host: Frame.Host)
	local u = host.u
	local n = Config.ChargesCountByTier[host.tier] or Config.ChargesCountByTier[1]
	local cols = if n > 6 then 4 else 3
	local rows = math.ceil(n / cols)
	local gap = u(14)
	local cellW = math.floor((host.width - u(32) - gap * (cols - 1)) / cols)
	local cellH = math.floor((host.height - u(24) - gap * (rows - 1)) / rows)
	local size = math.min(cellW, cellH, u(86))

	-- Wall backdrop.
	local wall = UI.frame({
		BackgroundColor3 = Theme.Colors.panel,
		Position = UDim2.fromOffset(u(8), u(6)),
		Size = UDim2.new(1, -u(16), 1, -u(12)),
		Parent = host.content,
	})
	UI.corner(wall, u(12))
	local wireLayer =
		UI.frame({ BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = host.content })

	-- Shuffle the numbers over the grid cells.
	local cells = {}
	for i = 1, cols * rows do
		cells[i] = i
	end
	for i = #cells, 2, -1 do
		local k = math.random(i)
		cells[i], cells[k] = cells[k], cells[i]
	end

	local caps: { Cap } = {}
	local gridW = cols * size + (cols - 1) * gap
	local gridH = rows * size + (rows - 1) * gap
	local originX = math.floor((host.width - gridW) / 2)
	local originY = math.floor((host.height - gridH) / 2)
	for number = 1, n do
		local cell = cells[number]
		local col = (cell - 1) % cols
		local row = math.floor((cell - 1) / cols)
		local x = originX + col * (size + gap)
		local y = originY + row * (size + gap)
		local button = UI.button({
			Text = tostring(number),
			FontFace = Theme.Fonts.display,
			TextSize = math.floor(size * 0.5),
			TextColor3 = Theme.Colors.text,
			BackgroundColor3 = Theme.Colors.panel2,
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(size, size),
			ZIndex = 5,
			Parent = host.content,
		})
		UI.corner(button, size / 2)
		local stroke = UI.stroke(button, Theme.Colors.grey, u(2))
		caps[number] = {
			number = number,
			button = button,
			stroke = stroke,
			center = Vector2.new(x + size / 2, y + size / 2),
		}
	end

	local armed = 0
	local wires: { Frame } = {}
	local done = false

	local function resetChain()
		armed = 0
		for _, w in wires do
			w:Destroy()
		end
		wires = {}
		for _, cap in caps do
			cap.button.BackgroundColor3 = Theme.Colors.panel2
			cap.button.TextColor3 = Theme.Colors.text
			cap.stroke.Color = Theme.Colors.grey
		end
	end

	local function flashAll()
		for _, cap in caps do
			cap.button.BackgroundColor3 = Theme.Colors.red
			cap.stroke.Color = Theme.Colors.red
			UI.punch(cap.button, 1.15, 0.25)
		end
		task.delay(0.25, function()
			if host.alive() then
				resetChain()
			end
		end)
	end

	-- Brief 11: the pad's cursor snaps cap to cap by direction (D-pad), A presses; it starts on cap 1.
	local padCaps: { Frame.GridItem } = {}
	for _, cap in caps do
		local function hit()
			if done then
				return
			end
			if cap.number ~= armed + 1 then
				host.miss()
				flashAll()
				return
			end
			armed += 1
			cap.button.BackgroundColor3 = Theme.Colors.amber
			cap.button.TextColor3 = Theme.Colors.bg
			cap.stroke.Color = Theme.Colors.amber
			UI.punch(cap.button, 1.3, 0.25)
			host.haptic(0.5)
			UI.sound(Theme.Sounds.reelTick, 0.9 + armed * 0.1, 0.45)
			host.setHint(string.format("%d / %d ARMED", armed, n), Theme.Colors.amber)
			if armed >= n then
				done = true
				-- Final cap: flash and the ARMED stamp.
				local flash = UI.frame({
					BackgroundColor3 = Theme.Colors.amber,
					BackgroundTransparency = 0.2,
					Size = UDim2.fromScale(1, 1),
					ZIndex = 10,
					Parent = host.content,
				})
				UI.tween(flash, { BackgroundTransparency = 1 }, 0.4)
				for _, c in caps do
					UI.punch(c.button, 1.4, 0.4)
				end
				host.stamp("ARMED", Theme.Colors.amber)
				host.haptic(1)
				task.delay(0.35, function()
					host.finish("done")
				end)
				return
			end
			-- Wire from this cap to the next one in the chain.
			local nextCap = caps[armed + 1]
			local wire = Frame.line(wireLayer, cap.center, nextCap.center, u(5), Theme.Colors.amber, 2)
			wire.Size = UDim2.fromOffset(1, u(5))
			UI.tween(wire, { Size = UDim2.fromOffset((nextCap.center - cap.center).Magnitude, u(5)) }, 0.18)
			table.insert(wires, wire)
			nextCap.stroke.Color = Theme.Colors.amber
			UI.punch(nextCap.button, 1.1, 0.2)
		end
		Frame.press(host, cap.button, function()
			hit()
		end)
		padCaps[cap.number] = { button = cap.button, press = hit }
	end
	local grid = Frame.padGrid(host, padCaps, 1)
	host.pad = { button = grid }
end

return Charges
