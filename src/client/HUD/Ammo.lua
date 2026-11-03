--!strict
-- Bottom-right: ammo large, hint line under it.
local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local ClientState = require(Client:WaitForChild("ClientState"))

local Ammo = {}

function Ammo.build(gui: ScreenGui, track: (RBXScriptConnection) -> ())
	local S = UI.S
	local root = UI.frame({
		Name = "Ammo",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -S(20), 1, -S(20)),
		Size = UDim2.fromOffset(S(260), S(70)),
		Parent = gui,
	})
	local ammo = UI.text({
		Name = "Count",
		Text = "0 / ∞",
		Font = Theme.Fonts.display,
		TextSize = S(40),
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.new(1, 0, 0, S(46)),
		Parent = root,
	})
	UI.stroke(ammo, Theme.Colors.black, S(1.5), 0.4)
	local hint = UI.text({
		Name = "Hint",
		Text = "R RELOAD · F INTERACT · Q E Z ABILITIES · CTRL CAMERA · ` DEBUG",
		TextSize = S(12),
		TextColor3 = Theme.Colors.grey,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.fromOffset(0, S(48)),
		Size = UDim2.new(1, 0, 0, S(18)),
		Visible = not ClientState.isMobile,
		Parent = root,
	})

	local function render(a: any)
		if a.reloading and a.shell then
			-- Shell by shell: the count ticks up live; the hint says you can stop.
			ammo.Text = string.format("%d / %d  LOADING", a.mag, a.max)
			ammo.TextColor3 = if a.mag > 0 then Theme.Colors.gold else Theme.Colors.malus
			UI.punch(ammo, 1.08, 0.15)
		elseif a.reloading then
			ammo.Text = "RELOADING"
			ammo.TextColor3 = Theme.Colors.gold
		else
			ammo.Text = if a.mag == 0 then "RELOAD" else string.format("%d / ∞", a.mag)
			local low = a.max > 0 and a.mag <= math.max(1, math.floor(a.max * 0.2))
			ammo.TextColor3 = if a.mag == 0
				then Theme.Colors.malus
				elseif low then Theme.Colors.gold
				else Theme.Colors.text
			if low then
				UI.punch(ammo, if a.mag == 0 then 1.3 else 1.12, 0.25)
			end
		end
	end
	track(ClientState.Ammo:Connect(render) :: any)
	render(ClientState.ammo)

	return { frame = root, label = ammo, hint = hint }
end

return Ammo
