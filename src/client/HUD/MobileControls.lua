--!strict
-- Mobile landscape: fire + ADS toggle bottom-right, reload tap button beside the weapon slot,
-- swap button above fire (visible only with a second weapon), POV left of the weapon slots (Round 28e). The joystick is Roblox's default dynamic thumbstick.
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

	-- Round 24b: FIRE's centre, from the bottom-right corner (Config.MobileFireRight / MobileFireUp clear its edge);
	-- ADS sits up-left of it on the diagonal, SWAP up-right.
	-- Round 28e: FIRE draws at Config.MobileFireScale around the same centre (the ring of buttons stays put).
	local baseFire = S(96)
	local fireSize = math.floor(baseFire * Config.MobileFireScale)
	local fcx = UI.S(Config.MobileFireRight) + baseFire / 2
	local fcy = UI.S(Config.MobileFireUp) + baseFire / 2
	local ring = baseFire / 2 + S(56) / 2 + UI.S(10)
	local diag = ring * 0.7071

	local fire = UI.button({
		Name = "FireButton",
		BackgroundColor3 = Theme.Colors.panel,
		BackgroundTransparency = 0.25,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -fcx, 1, -fcy), -- left of and above the jump button
		Size = UDim2.fromOffset(fireSize, fireSize),
		Text = "FIRE",
		FontFace = Theme.Fonts.display,
		TextSize = math.floor(S(22) * Config.MobileFireScale),
		Parent = gui,
	})
	UI.corner(fire, fireSize / 2)
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
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -fcx - diag, 1, -fcy - diag), -- up-left of FIRE
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
	-- Round 28e: ADS toggles on the press, so the same finger can carry on into a camera drag (the HUD's buttons
	-- look through, Camera.client) without the release having to land back on the button.
	ads.InputBegan:Connect(function(input)
		if
			input.UserInputType ~= Enum.UserInputType.Touch
			and input.UserInputType ~= Enum.UserInputType.MouseButton1
		then
			return
		end
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
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -fcx + diag, 1, -fcy - diag), -- up-right of FIRE
		Size = UDim2.fromOffset(S(56), S(56)),
		Text = "SWAP",
		FontFace = Theme.Fonts.display,
		TextSize = S(13),
		Visible = false,
		Parent = gui,
	})
	UI.corner(swap, S(28)) -- Round 28e: a circle like ADS
	UI.stroke(swap, Theme.Colors.text, S(2))
	swap.Activated:Connect(function()
		ClientState.Juice:Fire("SprintCancel", { reason = "swap" })
		Remotes.SwitchWeapon:FireServer()
		UI.punch(swap, 0.9, 0.15)
	end)
	-- Round 28e: only with a second weapon AND while the gun controls are up (FIRE is a HUD-managed piece, hidden in
	-- the hub and while spectating), so SWAP no longer floats over the hub HUD.
	local hasOffhand = false
	_track(ClientState.Changed:Connect(function(sync: any)
		hasOffhand = sync ~= nil and sync.offhand ~= nil
	end))

	-- Round 28e: POV, left of the weapon panel (mirrors RELOAD): cycles the same three views as the pad's camera
	-- button (normal -> far over the shoulder -> first person); three pips under the label show which one is on.
	local pov = UI.button({
		Name = "PovButton",
		BackgroundColor3 = Theme.Colors.panel,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(0.5, -UI.S(186 * G), 1, -UI.S(18)),
		Size = UDim2.fromOffset(S(56), S(56)),
		Text = "",
		Parent = gui,
	})
	UI.corner(pov, S(12))
	UI.stroke(pov, Theme.Colors.text, S(2))
	UI.text({
		Text = "POV",
		FontFace = Theme.Fonts.display,
		TextSize = S(20),
		Position = UDim2.fromOffset(0, S(6)),
		Size = UDim2.new(1, 0, 0, S(28)),
		Parent = pov,
	})
	local pips: { Frame } = {}
	for i = 1, 3 do
		local pip = UI.frame({
			BackgroundColor3 = Theme.Colors.grey,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, (i - 2) * S(12), 0, S(38)),
			Size = UDim2.fromOffset(S(8), S(8)),
			Parent = pov,
		})
		UI.corner(pip, S(4))
		pips[i] = pip
	end
	pov.Activated:Connect(function()
		ClientState.Juice:Fire("CameraCycle", {})
		UI.punch(pov, 0.9, 0.15)
	end)
	-- Round 29b: POV sits directly left of the equipped weapon card, measured from the card itself (the bottom
	-- centre panel grows on phones, so a fixed offset from the screen centre left it floating mid-screen).
	local slot: GuiObject? = nil
	_track(game:GetService("RunService").RenderStepped:Connect(function()
		if not slot or not slot.Parent then
			local found = gui:FindFirstChild("WeaponSlot", true)
			slot = if found and found:IsA("GuiObject") then found else nil
		end
		local s = slot
		if s and s.AbsoluteSize.X > 0 then
			local origin = gui.AbsolutePosition
			local x = s.AbsolutePosition.X - origin.X - UI.S(Config.MobilePovGap)
			local y = s.AbsolutePosition.Y - origin.Y + s.AbsoluteSize.Y
			pov.Position = UDim2.fromOffset(math.round(x), math.round(y))
		end
	end))

	-- Brief 11 step 3: the tap SPRINT button (settings: sprint = button), small, bottom-left under the thumbstick.
	local sprintBtn = UI.button({
		Name = "SprintButton",
		BackgroundColor3 = Theme.Colors.panel,
		BackgroundTransparency = 0.25,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, UI.S(16), 1, -UI.S(12)),
		Size = UDim2.fromOffset(S(64), S(30)),
		Text = "SPRINT",
		FontFace = Theme.Fonts.display,
		TextSize = S(13),
		Visible = false,
		Parent = gui,
	})
	UI.corner(sprintBtn, S(4))
	local sprintStroke = UI.stroke(sprintBtn, Theme.Colors.text, S(2))
	sprintBtn.Activated:Connect(function()
		ClientState.Juice:Fire("SprintTap", {})
		UI.punch(sprintBtn, 0.9, 0.15)
	end)
	_track(game:GetService("RunService").RenderStepped:Connect(function()
		swap.Visible = hasOffhand and fire.Visible
		for i, pip in pips do
			pip.BackgroundColor3 = if ClientState.cameraView == i then Theme.Colors.gold else Theme.Colors.grey
		end
		sprintBtn.Visible = ClientState.inputSettings().sprintTouch == "button" and not ClientState.combatOff()
		sprintStroke.Color = if ClientState.sprinting then Theme.Colors.gold else Theme.Colors.text
		sprintBtn.TextColor3 = if ClientState.sprinting then Theme.Colors.gold else Theme.Colors.text
	end))

	component.fire = fire
	return component
end

return MobileControls
