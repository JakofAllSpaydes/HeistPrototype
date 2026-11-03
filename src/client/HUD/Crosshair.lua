--!strict
-- Center crosshair with fire kick and a hitmarker that flashes on Hit (gold on headshot, red on kill).
local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))

local Crosshair = {}

function Crosshair.build(gui: ScreenGui, _track: (RBXScriptConnection) -> ())
	local S = UI.S
	local root = UI.frame({
		Name = "Crosshair",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(S(40), S(40)),
		Parent = gui,
	})
	local gap = S(5)
	local len = S(9)
	local thick = S(2)
	local lines: { Frame } = {}
	local offsets = {
		{ Vector2.new(0, -1), UDim2.fromOffset(thick, len) },
		{ Vector2.new(0, 1), UDim2.fromOffset(thick, len) },
		{ Vector2.new(-1, 0), UDim2.fromOffset(len, thick) },
		{ Vector2.new(1, 0), UDim2.fromOffset(len, thick) },
	}
	for i, o in offsets do
		local dir = o[1] :: Vector2
		local line = UI.frame({
			BackgroundColor3 = Theme.Colors.text,
			AnchorPoint = Vector2.new(0.5 - dir.X * 0.5, 0.5 - dir.Y * 0.5),
			Position = UDim2.new(0.5, dir.X * gap, 0.5, dir.Y * gap),
			Size = o[2] :: UDim2,
			Parent = root,
		})
		UI.stroke(line, Theme.Colors.black, 1, 0.5)
		lines[i] = line
	end
	local dot = UI.frame({
		BackgroundColor3 = Theme.Colors.text,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(S(3), S(3)),
		Parent = root,
	})
	UI.corner(dot, S(2))

	local marker = UI.frame({
		Name = "Hitmarker",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(S(26), S(26)),
		Visible = false,
		Parent = root,
	})
	local markerLines: { Frame } = {}
	for i = 1, 4 do
		local angle = 45 + (i - 1) * 90
		local l = UI.frame({
			BackgroundColor3 = Theme.Colors.text,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(S(2), S(26)),
			Rotation = angle,
			Parent = marker,
		})
		local cover = UI.frame({
			BackgroundColor3 = Theme.Colors.text,
			Size = UDim2.fromScale(1, 0.35),
			Position = UDim2.fromScale(0, 0.325),
			BackgroundTransparency = 1,
			Parent = l,
		})
		cover.Visible = false
		markerLines[i] = l
	end

	local markerToken = 0
	local function flash(color: Color3)
		markerToken += 1
		local token = markerToken
		for _, l in markerLines do
			l.BackgroundColor3 = color
			l.BackgroundTransparency = 0
		end
		marker.Visible = true
		UI.punch(marker, 1.5, 0.15)
		task.delay(0.12, function()
			if token ~= markerToken then
				return
			end
			for _, l in markerLines do
				UI.tween(l, { BackgroundTransparency = 1 }, 0.12)
			end
			task.delay(0.13, function()
				if token == markerToken then
					marker.Visible = false
				end
			end)
		end)
	end

	local function kick()
		for i, line in lines do
			local dir = offsets[i][1] :: Vector2
			line.Position = UDim2.new(0.5, dir.X * (gap + S(5)), 0.5, dir.Y * (gap + S(5)))
			UI.tween(line, { Position = UDim2.new(0.5, dir.X * gap, 0.5, dir.Y * gap) }, 0.12)
		end
	end

	local component = {}
	component.frame = root

	function component.onJuice(name: string, data: any)
		if name == "LocalFire" then
			kick()
		elseif name == "Hit" then
			flash(
				if data.killed then Theme.Colors.red elseif data.headshot then Theme.Colors.gold else Theme.Colors.text
			)
		end
	end

	return component
end

return Crosshair
