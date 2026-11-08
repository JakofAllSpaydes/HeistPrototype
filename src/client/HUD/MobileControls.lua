--!strict
-- Mobile landscape: fire + ADS toggle bottom-right, reload tap button beside the weapon slot.
-- The joystick is Roblox's default dynamic thumbstick.
local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local ClientState = require(Client:WaitForChild("ClientState"))

local MobileControls = {}

function MobileControls.build(gui: ScreenGui, _track: (RBXScriptConnection) -> ())
	local component = {}
	if not ClientState.isMobile then
		return component
	end
	local S = UI.S

	local fire = UI.button({
		Name = "FireButton",
		BackgroundColor3 = Theme.Colors.panel,
		BackgroundTransparency = 0.25,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -S(40), 1, -S(90)),
		Size = UDim2.fromOffset(S(96), S(96)),
		Text = "FIRE",
		FontFace = Theme.Fonts.display,
		TextSize = S(22),
		Parent = gui,
	})
	UI.corner(fire, S(48))
	UI.stroke(fire, Theme.Colors.gold, S(3))
	fire.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			ClientState.touchFire = true
			fire.BackgroundTransparency = 0
		end
	end)
	fire.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			ClientState.touchFire = false
			fire.BackgroundTransparency = 0.25
			ClientState.Juice:Fire("TouchFireReleased", {})
		end
	end)

	local ads = UI.button({
		Name = "ADSButton",
		BackgroundColor3 = Theme.Colors.panel,
		BackgroundTransparency = 0.25,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -S(150), 1, -S(70)),
		Size = UDim2.fromOffset(S(56), S(56)),
		Text = "ADS",
		FontFace = Theme.Fonts.display,
		TextSize = S(14),
		TextColor3 = Theme.Colors.grey,
		Parent = gui,
	})
	UI.corner(ads, S(28))
	local adsStroke = UI.stroke(ads, Theme.Colors.grey, S(2))
	local function paintAds(on: boolean)
		ads.TextColor3 = if on then Theme.Colors.gold else Theme.Colors.grey
		adsStroke.Color = if on then Theme.Colors.gold else Theme.Colors.grey
		ads.BackgroundTransparency = if on then 0 else 0.25
	end
	paintAds(ClientState.ads)
	ads.Activated:Connect(function()
		ClientState.setAds(not ClientState.ads)
		UI.punch(ads, 0.9, 0.15)
	end)
	_track(ClientState.Juice:Connect(function(name: string, data: any)
		if name == "Ads" then
			paintAds(data.on == true)
		end
	end))

	local reload = UI.button({
		Name = "ReloadButton",
		BackgroundColor3 = Theme.Colors.panel,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0.5, S(120), 1, -S(18)),
		Size = UDim2.fromOffset(S(56), S(56)),
		Text = "R",
		FontFace = Theme.Fonts.display,
		TextSize = S(24),
		Parent = gui,
	})
	UI.corner(reload, S(12))
	UI.stroke(reload, Theme.Colors.text, S(2))
	reload.Activated:Connect(function()
		ClientState.Juice:Fire("LocalReload", {})
		UI.punch(reload, 0.9, 0.15)
	end)

	component.fire = fire
	return component
end

return MobileControls
