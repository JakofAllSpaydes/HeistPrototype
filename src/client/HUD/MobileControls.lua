--!strict
-- Mobile landscape: fire + ADS toggle bottom-right, reload tap button beside the weapon slot,
-- swap button above fire (visible only with a second weapon). The joystick is Roblox's default dynamic thumbstick.
-- Round 24: every button is Config.MobileButtonScale bigger, FIRE and ADS sit left of Roblox's jump button (which
-- keeps the corner), and FIRE is also a look stick: hold it to shoot and slide the thumb to aim.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

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
	local G = Config.MobileButtonScale
	local function S(n: number): number
		return UI.S(n * G)
	end

	local fire = UI.button({
		Name = "FireButton",
		BackgroundColor3 = Theme.Colors.panel,
		BackgroundTransparency = 0.25,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -UI.S(200), 1, -UI.S(36)), -- left of the jump button
		Size = UDim2.fromOffset(S(96), S(96)),
		Text = "FIRE",
		FontFace = Theme.Fonts.display,
		TextSize = S(22),
		Parent = gui,
	})
	UI.corner(fire, S(48))
	UI.stroke(fire, Theme.Colors.gold, S(3))
	-- The touch that pressed FIRE is followed globally: it keeps firing (and turning the camera) when the thumb
	-- slides off the button, and lets go only when that finger lifts.
	local fireInput: InputObject? = nil
	fire.InputBegan:Connect(function(input)
		if fireInput then
			return
		end
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			fireInput = input
			if input.UserInputType == Enum.UserInputType.Touch then
				ClientState.cameraTouches[input] = true
			end
			ClientState.touchFire = true
			fire.BackgroundTransparency = 0
		end
	end)
	_track(UserInputService.InputEnded:Connect(function(input)
		if input ~= fireInput then
			return
		end
		fireInput = nil
		ClientState.cameraTouches[input] = nil
		ClientState.touchFire = false
		fire.BackgroundTransparency = 0.25
		ClientState.Juice:Fire("TouchFireReleased", {})
	end))

	local ads = UI.button({
		Name = "ADSButton",
		BackgroundColor3 = Theme.Colors.panel,
		BackgroundTransparency = 0.25,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -UI.S(200) - S(96) - UI.S(14), 1, -UI.S(36)), -- left of FIRE, bottoms level
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
		Position = UDim2.new(0.5, UI.S(186 * G), 1, -UI.S(18)), -- Round 21: right of the second gun slot chip
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

	-- Round 22: SWAP button above fire, visible only when the player has a second weapon.
	local swap = UI.button({
		Name = "SwapButton",
		BackgroundColor3 = Theme.Colors.panel,
		BackgroundTransparency = 0.25,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -UI.S(200) - S(20), 1, -UI.S(36) - S(96) - UI.S(14)), -- above FIRE
		Size = UDim2.fromOffset(S(56), S(56)),
		Text = "SWAP",
		FontFace = Theme.Fonts.display,
		TextSize = S(13),
		Visible = false,
		Parent = gui,
	})
	UI.corner(swap, S(12))
	UI.stroke(swap, Theme.Colors.text, S(2))
	swap.Activated:Connect(function()
		Remotes.SwitchWeapon:FireServer()
		UI.punch(swap, 0.9, 0.15)
	end)
	_track(ClientState.Changed:Connect(function(sync: any)
		swap.Visible = sync and sync.offhand ~= nil
	end))

	component.fire = fire
	return component
end

return MobileControls
