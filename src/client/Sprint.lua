--!strict
-- Brief 11 step 3: sprint on PC, pad and touch over one rule (shared/SprintRule): fire always wins.
--   PC: Shift (hold, or toggle in settings). Pad: L3 (toggle, or hold). Touch: push the thumbstick through its ring
--   (or a small SPRINT button, or off, in settings).
--   Any fire / ADS / ability / interact / swap ends the sprint and the action happens in the same frame (callers fire
--   Juice "SprintCancel" { reason }, or call Sprint.cancel); sprint then needs a fresh engage.
-- The server owns the speed (Remotes.SetSprint); this module owns ClientState.sprinting, the FOV push (Camera reads
-- Sprint.fovAdd), the engage tick, the touch stretch arc and the `[GHS Input] sprint` log.
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Signal = require(Shared:WaitForChild("Signal"))
local SprintRule = require(Shared:WaitForChild("SprintRule"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local Haptics = require(script.Parent:WaitForChild("Haptics"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local Sprint = {}

Sprint.Changed = Signal.new() -- (on: boolean)
Sprint.Ended = Signal.new() -- (record: SprintRule.Record) every finished sprint
Sprint.fovAdd = 0 -- eased degrees the camera adds
Sprint.showLog = false -- debug: the sprint log on screen
Sprint.history = {} :: { SprintRule.Record } -- the last sprints, newest last (debug)

local player = Players.LocalPlayer
local rule = SprintRule.new(ClientState.inputDevice, true)
local fireEarly, total = 0, 0

------------------------------------------------------------------ settings

local function settings()
	return ClientState.inputSettings()
end

-- Hold or toggle for the device that gave the engage.
local function holdModeFor(device: string): boolean
	local s = settings()
	if device == "gamepad" then
		return false -- L3 always toggles
	elseif device == "touch" then
		return false -- push-through and the button are edges
	end
	return s.sprintPc ~= "toggle"
end

------------------------------------------------------------------ apply / log

local function logEnd(rec: SprintRule.Record?)
	if not rec then
		return
	end
	total += 1
	if rec.reason == "fire" and rec.sec < 0.5 then
		fireEarly += 1
	end
	print(
		string.format(
			"[GHS Input] sprint engage %s %.2fs ended-by %s (fire<0.5s %d/%d)",
			rec.device,
			rec.sec,
			rec.reason,
			fireEarly,
			total
		)
	)
	Sprint.Ended:Fire(rec)
	table.insert(Sprint.history, rec)
	while #Sprint.history > 8 do
		table.remove(Sprint.history, 1)
	end
end

local function setChar(on: boolean)
	local char = player.Character
	if char then
		-- Locally at once (GunAnim lowers / raises the arms off this); the server sets the same value.
		char:SetAttribute("Sprinting", if on then true else nil)
	end
end

local function apply(on: boolean)
	if ClientState.sprinting == on then
		return
	end
	ClientState.sprinting = on
	Remotes.SetSprint:FireServer(on)
	setChar(on)
	if on then
		ClientState.setAds(false)
		Haptics.pulse(Config.HapticSprint)
	elseif
		-- Round 25: RMB still held when the sprint ends: straight back into ADS.
		UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) and ClientState.canAds()
	then
		ClientState.setAds(true)
	end
	Sprint.Changed:Fire(on)
end

-- End the sprint for an action (fire, ads, ability, interact, swap, minigame). Safe to call when not sprinting.
function Sprint.cancel(reason: string)
	local rec = rule:cancel(reason, os.clock())
	logEnd(rec)
	apply(false)
end

-- Round 29b: the hub outside the range walks fast already; sprint is off there (Config.SprintInHub).
local function hubBlocked(): boolean
	return not Config.SprintInHub and ClientState.combatOff()
end

local function press(device: string)
	if hubBlocked() then
		return
	end
	rule.device = device
	rule.holdMode = holdModeFor(device)
	local rec = rule:press(os.clock())
	if rec then
		logEnd(rec)
		apply(false)
	end
end

local function release()
	local rec = rule:release(os.clock())
	if rec then
		logEnd(rec)
		apply(false)
	end
end

------------------------------------------------------------------ PC: Shift

local shiftHeld = false
UserInputService.InputBegan:Connect(function(input: InputObject)
	if input.KeyCode == Enum.KeyCode.LeftShift and not UserInputService:GetFocusedTextBox() then
		shiftHeld = true
		press("keyboard")
	end
end)
UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.KeyCode == Enum.KeyCode.LeftShift then
		shiftHeld = false
		if rule.device == "keyboard" then
			release()
		end
	end
end)

------------------------------------------------------------------ touch: push-through

local touch: InputObject? = nil
local touchCenter = Vector2.zero
local touchForward = 0
local pushSince: number? = nil
local rearmed = true
local arc: Frame? = nil

local function thumbstickFrame(): GuiObject?
	local pg = player:FindFirstChild("PlayerGui")
	local tg = pg and pg:FindFirstChild("TouchGui")
	local f = tg and tg:FindFirstChild("DynamicThumbstickFrame", true)
	return if f and f:IsA("GuiObject") then f else nil
end

-- The ring radius in screen px: Roblox's own ring image when it can be read, else Config.SprintTouchRingPx.
local function ringRadius(): number
	local f = thumbstickFrame()
	local best = 0
	if f then
		for _, d in f:GetDescendants() do
			if d:IsA("ImageLabel") and d.Visible then
				best = math.max(best, d.AbsoluteSize.X / 2)
			end
		end
	end
	if best >= 20 then
		return math.min(best, UI.S(Config.SprintTouchRingMaxPx)) -- Round 29b: never a half-screen push
	end
	return UI.S(Config.SprintTouchRingPx)
end

local function inThumbZone(p: Vector2): boolean
	local f = thumbstickFrame()
	if f and f.AbsoluteSize.X > 0 then
		local a, s = f.AbsolutePosition, f.AbsoluteSize
		return p.X >= a.X and p.X <= a.X + s.X and p.Y >= a.Y and p.Y <= a.Y + s.Y
	end
	local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1000, 600)
	return p.X < vp.X * 0.4 and p.Y > vp.Y * 0.35
end

local function showArc(on: boolean, radius: number)
	local a = arc
	if not a then
		return
	end
	a.Visible = on
	if on then
		local d = radius * Config.SprintPushRadius * 2
		a.Size = UDim2.fromOffset(d, d)
		a.Position = UDim2.fromOffset(touchCenter.X, touchCenter.Y)
	end
end

local function touchMode(): string
	return settings().sprintTouch
end

UserInputService.TouchStarted:Connect(function(input: InputObject)
	if touch or not ClientState.isMobile or touchMode() ~= "push" then
		return
	end
	local p = Vector2.new(input.Position.X, input.Position.Y)
	if inThumbZone(p) then
		touch = input
		touchCenter = p
		touchForward = 0
		pushSince = nil
		rearmed = true
	end
end)
UserInputService.TouchMoved:Connect(function(input: InputObject)
	if input ~= touch then
		return
	end
	local radius = ringRadius()
	local p = Vector2.new(input.Position.X, input.Position.Y)
	local ratio, angle, forward = SprintRule.touch(p.X - touchCenter.X, p.Y - touchCenter.Y, radius)
	touchForward = forward
	if SprintRule.rearmed(ratio) then
		rearmed = true
	end
	local pushing = SprintRule.pushing(ratio, angle)
	showArc(pushing and not ClientState.sprinting, radius)
	if pushing and rearmed then
		local now = os.clock()
		pushSince = pushSince or now
		if now - (pushSince :: number) >= Config.SprintPushHoldSec then
			rearmed = false
			pushSince = nil
			showArc(false, radius)
			press("touch")
		end
	elseif not pushing then
		pushSince = nil
	end
end)
UserInputService.TouchEnded:Connect(function(input: InputObject)
	if input == touch then
		touch = nil
		touchForward = 0
		pushSince = nil
		showArc(false, 0)
	end
end)

-- The tap button (settings: sprint = button).
function Sprint.tapButton()
	press("touch")
end

------------------------------------------------------------------ tick

local lastMoving = 0

local function cond(): SprintRule.Cond
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local moving = hum ~= nil and hum.MoveDirection.Magnitude > 0.1
	local now = os.clock()
	if moving then
		lastMoving = now
	end
	local keep = moving
	if rule.device == "gamepad" then
		-- L3 is a toggle: it holds in any direction until you stop (a stick swinging through centre is not a stop)
		keep = now - lastMoving <= Config.SprintPadStopGraceSec
	elseif rule.device == "touch" then
		-- the tap button holds while moving; push-through holds while the thumb stays forward
		keep = moving and (touchMode() == "button" or touchForward >= Config.SprintKeepThreshold)
	end
	local allowed = Config.SprintEnabled
		and not hubBlocked()
		and not ClientState.downed
		and not ClientState.blocked()
		and ClientState.cameraMode == "gameplay"
		and not (rule.device == "touch" and touchMode() == "off")
	return { moving = moving, keep = keep, allowed = allowed, downed = ClientState.downed }
end

-- Called every frame by Gun.client before it decides to fire (so a cancel and the shot share the frame).
function Sprint.update()
	local changed, rec = rule:tick(os.clock(), cond())
	if changed then
		logEnd(rec)
		apply(rule.on)
	end
end

function Sprint.init()
	-- Every action ends the sprint at once (the callers then do the action).
	ClientState.Juice:Connect(function(name: string, data: any)
		if name == "SprintCancel" and typeof(data) == "table" then
			Sprint.cancel(tostring(data.reason or "action"))
		elseif name == "Ads" and typeof(data) == "table" and data.on and ClientState.sprinting then
			Sprint.cancel("ads")
		elseif name == "SprintTap" then
			Sprint.tapButton()
		elseif name == "PadSprint" and typeof(data) == "table" then
			if data.on then
				press("gamepad")
			elseif rule.device == "gamepad" then
				release()
			end
		end
	end)
	ProximityPromptService.PromptButtonHoldBegan:Connect(function()
		Sprint.cancel("interact")
	end)
	ProximityPromptService.PromptTriggered:Connect(function()
		Sprint.cancel("interact")
	end)
	-- The touch stretch arc: a faint ring segment over the thumbstick, only while the thumb is past the ring.
	if ClientState.isMobile then
		local g = UI.new("ScreenGui", {
			Name = "SprintArc",
			IgnoreGuiInset = false, -- touch positions are below the inset, like this gui
			ResetOnSpawn = false,
			DisplayOrder = 2,
			Parent = player:WaitForChild("PlayerGui"),
		}) :: ScreenGui
		local a = UI.frame({
			Name = "Arc",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Visible = false,
			Parent = g,
		})
		UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = a })
		local stroke = UI.new("UIStroke", { Color = Theme.Colors.gold, Thickness = UI.S(4), Parent = a })
		-- only the top of the ring shows
		UI.new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.35),
				NumberSequenceKeypoint.new(0.3, 0.8),
				NumberSequenceKeypoint.new(0.45, 1),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = stroke,
		})
		arc = a
		-- The sprint mark over the thumbstick while a push-through sprint holds (the knob itself is Roblox's).
		local mark, markLabel = UI.pill(g, "» SPRINT", Theme.Colors.gold, Theme.Colors.bg, UI.S(26), UI.S(14))
		mark.AnchorPoint = Vector2.new(0.5, 1)
		mark.Visible = false
		markLabel.FontFace = Theme.Fonts.display
		RunService.RenderStepped:Connect(function()
			local show = ClientState.sprinting and rule.device == "touch" and touch ~= nil
			mark.Visible = show
			if show then
				mark.Position = UDim2.fromOffset(touchCenter.X, touchCenter.Y - ringRadius() - UI.S(6))
			end
		end)
	end
	RunService.RenderStepped:Connect(function(dt: number)
		local target = if ClientState.sprinting then Config.SprintFovAdd else 0
		Sprint.fovAdd += (target - Sprint.fovAdd) * math.min(1, dt * Config.SprintFovRate)
	end)
	player.CharacterAdded:Connect(function()
		rule:cancel("down", os.clock())
		apply(false)
	end)
end

-- Debug: is Shift held right now (the old Gun.client query).
function Sprint.shiftHeld(): boolean
	return shiftHeld
end

return Sprint
