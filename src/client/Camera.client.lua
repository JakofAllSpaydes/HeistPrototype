--!strict
-- Right-shoulder third person with mouse look, shift-lock style. Scroll wheel / pinch zooms between
-- Config.CameraZoomMax and first person (character hidden locally). ADS narrows the FOV and pulls the camera in.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera :: Camera

local yaw = 0
local pitch = -0.12
local PITCH_MIN, PITCH_MAX = -1.2, 0.9

-- Zoom: targetZoom is what the player asked for (0 = first person), zoom eases toward it.
local targetZoom = Config.CameraZoomDefault
local zoom = targetZoom
local pinching = false
local pinchStartZoom = targetZoom

local function snapZoom(z: number): number
	z = math.clamp(z, 0, Config.CameraZoomMax)
	return if z < Config.CameraFirstPersonBelow then 0 else z
end

local function zoomStep(ticks: number)
	if ticks > 0 then
		-- Zoom in.
		targetZoom = snapZoom(targetZoom - ticks * Config.CameraZoomStep)
	elseif ticks < 0 then
		-- Zoom out: leaving first person jumps straight to the threshold.
		local from = if targetZoom == 0 then Config.CameraFirstPersonBelow else targetZoom
		local extra = if targetZoom == 0 then -ticks - 1 else -ticks
		targetZoom = snapZoom(from + extra * Config.CameraZoomStep)
	end
end

-- Cursor unlocked: holding RMB drags the camera round like default Roblox, so RMB still aims and turns.
local rmbHeld = false
local function dragging(): boolean
	return rmbHeld and ClientState.isMouseFree() and not ClientState.blocked()
end

-- Round 22: only touches that started on the right 60% of the screen drive the camera. The left side is the
-- movement thumbstick; without this filter, dragging the joystick rotates the camera too.
-- Round 24: the filter runs once, when the touch begins. After that a tracked touch turns the camera whatever
-- it slides over (gameProcessed is ignored on move), so a thumb on the stick, one on FIRE and a drag all work
-- together. The hub turns too (touch never waited on RMB).
local cameraTouches = ClientState.cameraTouches
local opticSens = 1 -- Round 24r: look slows with a magnified optic's zoom
local assistFriction = 1 -- Round 24 aim assist: look sensitivity multiplier while the crosshair is on a target
-- Round 24g: this frame's look input (radians), so the assist can tell when you are pulling off a target.
local inputYaw, inputPitch = 0, 0
local awayUntil = 0
-- Round 24d: a second finger that lands while the thumbstick is held comes in flagged gameProcessed (or never
-- reaches InputBegan at all: the stick's own touch handling takes it), so move + look never worked together.
-- The camera now decides for itself: a touch right of TouchCameraStartX is a look touch unless it lands on one
-- of our buttons. It listens on three paths (InputBegan, TouchStarted, a high-priority ContextAction that
-- passes the input on), and claiming the same touch twice is harmless.
local GuiService = game:GetService("GuiService")
local ContextActionService = game:GetService("ContextActionService")
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

local function onOurButton(p: Vector2): boolean
	local inset = GuiService:GetGuiInset()
	for _, at in { p, p + inset } do
		for _, g in playerGui:GetGuiObjectsAtPosition(at.X, at.Y) do
			if (g:IsA("GuiButton") or g:IsA("TextBox")) and not g:FindFirstAncestor("TouchGui") then
				return true
			end
		end
	end
	return false
end

local function claimTouch(input: InputObject)
	if input.UserInputType ~= Enum.UserInputType.Touch or cameraTouches[input] ~= nil then
		return
	end
	local vp = camera.ViewportSize
	local p = Vector2.new(input.Position.X, input.Position.Y)
	if p.X > vp.X * Config.TouchCameraStartX and not onOurButton(p) then
		cameraTouches[input] = true
	end
end

UserInputService.InputBegan:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		rmbHeld = true
	else
		claimTouch(input)
	end
end)
UserInputService.TouchStarted:Connect(function(input: InputObject)
	claimTouch(input)
end)
ContextActionService:BindActionAtPriority(
	"GHSTouchLook",
	function(_name: string, state: Enum.UserInputState, input: InputObject)
		if state == Enum.UserInputState.Begin then
			claimTouch(input)
		end
		return Enum.ContextActionResult.Pass
	end,
	false,
	Enum.ContextActionPriority.High.Value + 50,
	Enum.UserInputType.Touch
)
UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		rmbHeld = false
	elseif input.UserInputType == Enum.UserInputType.Touch then
		cameraTouches[input] = nil
	end
end)

UserInputService.InputChanged:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		if not ClientState.blocked() then
			zoomStep(input.Position.Z)
		end
		return
	end
	local sens = (if ClientState.ads then Config.AdsSensitivityMult else 1) * assistFriction * opticSens
	if input.UserInputType == Enum.UserInputType.Touch then
		return -- touch look is polled every frame (pollTouches)
	end
	-- Cursor unlocked: the camera holds still (the character turns toward the cursor in the render step)
	-- unless RMB is held, which drags it.
	if ClientState.isMouseFree() and not dragging() then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		yaw -= input.Delta.X * Config.MouseSensitivity * sens
		inputYaw -= input.Delta.X * Config.MouseSensitivity * sens
		inputPitch -= input.Delta.Y * Config.MouseSensitivity * sens
		pitch = math.clamp(pitch - input.Delta.Y * Config.MouseSensitivity * sens, PITCH_MIN, PITCH_MAX)
	end
end)

-- Pinch: scale is relative to the gesture start, so spreading the fingers (scale > 1) zooms in.
UserInputService.TouchPinch:Connect(
	function(touches: { Vector2 }, scale: number, _velocity: number, state: Enum.UserInputState, gameProcessed: boolean)
		if state == Enum.UserInputState.Begin then
			if gameProcessed or ClientState.blocked() then
				return
			end
			-- Round 24f: Roblox reports ANY two moving fingers as a pinch, the thumbstick thumb included, and a pinch
			-- froze touch look: moving + looking died after a tiny flick. A real pinch has both fingers in the look
			-- area, right of the stick.
			local edge = camera.ViewportSize.X * Config.TouchCameraStartX
			for _, t in touches do
				if t.X <= edge then
					return
				end
			end
			pinching = true
			pinchStartZoom = if targetZoom == 0 then Config.CameraFirstPersonBelow else targetZoom
		elseif not pinching then
			return
		elseif state == Enum.UserInputState.Change then
			targetZoom = math.clamp(pinchStartZoom / math.max(scale, 0.05), 0, Config.CameraZoomMax)
		else
			pinching = false
			targetZoom = snapZoom(targetZoom)
		end
	end
)

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude

-- FOV kick on fire and camera shake, both decay each frame.
local fovKick = 0
local camPunch = 0 -- Round 24n: radians of upward camera kick, easing home
local stimFov = 0
local slowFov = 0
local shakeAmp = 0
local shakeLeft = 0
local shakeTotal = 0
local adsBlend = 0 -- 0 hip, 1 fully aimed
ClientState.Juice:Connect(function(name: string, data: any)
	if name == "LocalFire" then
		fovKick = Config.FireFovKick
		-- Round 24n: a camera punch per gun kind (every view), eased back home; snipers / shotguns hit hard.
		local char = player.Character
		local gun = char and char:FindFirstChild("HeldGun")
		local kind = gun and gun:GetAttribute("GunKind")
		local punch = (Config.CameraRecoilDeg :: any)[tostring(kind)] or 0
		camPunch = math.min(camPunch + math.rad(punch), math.rad(punch) * 2)
	elseif name == "Shake" then
		shakeAmp = math.max(shakeAmp, data.amp or 0)
		shakeTotal = data.dur or 0.2
		shakeLeft = shakeTotal
	elseif name == "StimStart" then
		stimFov = 6
	elseif name == "StimEnd" then
		stimFov = 0
	elseif name == "RunOver" then
		-- Slow-mo beat: pull the lens in, release as the red screen clears.
		slowFov = -10
		task.delay((data.slowSec or 1) + (data.holdSec or 2.5) - 0.5, function()
			slowFov = 0
		end)
	elseif name == "RunResumed" then
		slowFov = 0
	elseif name == "CameraZoomReset" then
		-- A scene is taking the camera: back to the default third-person distance so the character is not
		-- left hidden by a first-person zoom.
		targetZoom = Config.CameraZoomDefault
		zoom = targetZoom
	end
end)

-- First person hides the whole local character; FirstPersonView.client draws the camera-locked gun and arms
-- (Round 24c: the real arms sat right in front of the lens).
local hiddenChar: Model? = nil
local function setHidden(char: Model?, hidden: boolean)
	if not char then
		return
	end
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			d.LocalTransparencyModifier = if hidden then 1 else 0
		elseif
			d:IsA("ParticleEmitter")
			or d:IsA("Light")
			or d:IsA("Beam")
			or d:IsA("Trail")
			or d:IsA("Sparkles")
			or d:IsA("Fire")
			or d:IsA("Smoke")
		then
			-- Round 24g: effects on the body (buff auras, status embers, sparkles) emit right at the lens in
			-- first person: off locally while hidden, back as they were after.
			local fx = d :: any
			if hidden then
				if fx.Enabled then
					d:SetAttribute("FPWasOn", true)
					fx.Enabled = false
				end
			elseif d:GetAttribute("FPWasOn") then
				d:SetAttribute("FPWasOn", nil)
				fx.Enabled = true
			end
		end
	end
end
local fpEyeRel: Vector3? = nil -- the head's offset from the root, smoothed (the steady eye)

-- Round 24 aim assist (touch / gamepad; mouse too with Config.AimAssistMouse). The enemy nearest the crosshair
-- inside AimAssistConeDeg pulls the camera toward its torso; with the crosshair held above AimAssistHeadBias of
-- the way from torso to head on screen, the pull goes to the head instead. Near a target, look input slows
-- (AimAssistFriction) so the crosshair sticks. Firing and ADS pull harder.
local assistParams = RaycastParams.new()
assistParams.FilterType = Enum.RaycastFilterType.Exclude
local assistModel: Model? = nil
local assistHead = false
local firingUntil = 0
ClientState.Juice:Connect(function(name: string)
	if name == "LocalFire" then
		firingUntil = os.clock() + 0.25
	end
end)

local assistScale = 1 -- Round 24aa: 1 for touch / gamepad, AimAssistMouseScale for the mouse
local function assistWanted(): boolean
	if not Config.AimAssistEnabled then
		return false
	end
	if ClientState.blocked() or ClientState.combatOff() or ClientState.isMouseFree() or ClientState.downed then
		return false
	end
	assistScale = 1
	if ClientState.isMobile or Config.AimAssistMouse then
		return true
	end
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch or string.find(last.Name, "Gamepad") ~= nil then
		return true
	end
	-- Round 24aa: mouse gets a faint version (AimAssistMouseScale of the pull and stickiness, a narrower cone).
	assistScale = Config.AimAssistMouseScale
	return assistScale > 0
end

local function wrapAngle(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

local function aimAssist(dt: number, char: Model)
	assistFriction = 1
	local hadYaw, hadPitch = inputYaw, inputPitch
	inputYaw, inputPitch = 0, 0 -- consumed below only when a target is in reach
	if not assistWanted() then
		assistModel = nil
		return
	end
	local folder = Workspace:FindFirstChild("Enemies")
	if not folder then
		return
	end
	local camCf = camera.CFrame
	local camPos = camCf.Position
	local look = camCf.LookVector
	local ads = ClientState.ads
	local cone = math.rad(if ads then Config.AimAssistAdsConeDeg else Config.AimAssistConeDeg)
		* (if assistScale < 1 then Config.AimAssistMouseCone else 1)
	local range = Config.AimAssistRange
	local vp = camera.ViewportSize
	local centreY = vp.Y / 2

	-- Nearest enemy to the crosshair by angle (to its torso or head, whichever is closer); the current target
	-- gets a little slack so two enemies side by side don't flicker.
	local best: Model?, bestAngle = nil, math.huge
	local bestRoot: BasePart?, bestHead: BasePart? = nil, nil
	for _, model in folder:GetChildren() do
		if not model:IsA("Model") then
			continue
		end
		local hp = model:GetAttribute("HP")
		if typeof(hp) == "number" and hp <= 0 then
			continue
		end
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		local head = model:FindFirstChild("Head") :: BasePart?
		if not root then
			continue
		end
		local toRoot = root.Position - camPos
		if toRoot.Magnitude > range then
			continue
		end
		local a = math.acos(math.clamp(look:Dot(toRoot.Unit), -1, 1))
		if head then
			local toHead = head.Position - camPos
			a = math.min(a, math.acos(math.clamp(look:Dot(toHead.Unit), -1, 1)))
		end
		if model == assistModel then
			a *= 0.8
		end
		if a < cone and a < bestAngle then
			best, bestAngle, bestRoot, bestHead = model, a, root, head
		end
	end
	if not best or not bestRoot then
		assistModel = nil
		return
	end

	-- Torso or head: where the crosshair sits between them on screen.
	local aimHead = false
	if bestHead then
		local rs = camera:WorldToViewportPoint(bestRoot.Position)
		local hs = camera:WorldToViewportPoint(bestHead.Position)
		local bias = Config.AimAssistHeadBias
		if best == assistModel and assistHead then
			bias *= 0.6 -- hysteresis: once on the head it stays there unless you pull clearly down
		end
		local switchY = rs.Y + (hs.Y - rs.Y) * bias
		aimHead = centreY < switchY
	end
	local part = if aimHead and bestHead then bestHead else bestRoot
	local point = part.Position

	-- Only through a clear line.
	local filter: { Instance } = { char }
	for _, name in { "GroundLoot", "Effects" } do
		local f = Workspace:FindFirstChild(name)
		if f then
			table.insert(filter, f)
		end
	end
	assistParams.FilterDescendantsInstances = filter
	local hit = Workspace:Raycast(camPos, point - camPos, assistParams)
	if hit and not hit.Instance:IsDescendantOf(best) then
		assistModel = nil
		return
	end
	assistModel, assistHead = best, aimHead

	local d = (point - camPos).Unit
	local angle = math.acos(math.clamp(look:Dot(d), -1, 1))
	local falloff = math.clamp(1 - angle / cone, 0, 1)
	local pull = (if ads then Config.AimAssistAdsPull else Config.AimAssistPull) * assistScale
	if os.clock() < firingUntil or ClientState.touchFire then
		pull *= Config.AimAssistFiringMult
	end
	local wantYaw = math.atan2(-d.X, -d.Z)
	local wantPitch = math.asin(math.clamp(d.Y, -1, 1))
	-- Pulling away: look input pointing off the target lets go (most of the pull, all of the friction) for a
	-- moment, so breaking off is easy while tracking still sticks.
	local toYaw, toPitch = wrapAngle(wantYaw - yaw), wantPitch - pitch
	local inMag = math.sqrt(hadYaw * hadYaw + hadPitch * hadPitch)
	if inMag > 1e-4 and (hadYaw * toYaw + hadPitch * toPitch) < 0 then
		awayUntil = os.clock() + Config.AimAssistReleaseSec
	end
	local away = os.clock() < awayUntil
	if away then
		pull *= Config.AimAssistPullAwayMult
	end
	local k = (1 - math.exp(-pull * dt)) * math.sqrt(falloff)
	yaw += wrapAngle(wantYaw - yaw) * k
	pitch = math.clamp(pitch + (wantPitch - pitch) * k, PITCH_MIN, PITCH_MAX)

	local frictionCone = math.rad(Config.AimAssistFrictionDeg)
	if angle < frictionCone and not away then
		assistFriction = 1 - (1 - Config.AimAssistFriction) * (1 - angle / frictionCone) * assistScale
	end
end

-- Round 24b: touch look reads each tracked finger's live Position every frame instead of trusting InputChanged.
-- With the thumbstick held, the FIRE thumb's move events did not reach this script (the stick's own touch
-- handling ate them), so moving + firing + aiming never worked together. The InputObject's Position updates
-- regardless, so polling it always sees the drag.
local touchLast: { [InputObject]: Vector3 } = {}
local function pollTouches()
	for input in touchLast do
		if not cameraTouches[input] then
			touchLast[input] = nil
		end
	end
	local sens = (if ClientState.ads then Config.AdsSensitivityMult else 1) * assistFriction * opticSens
	local canTurn = not pinching and not ClientState.blocked()
	for input in cameraTouches do
		if input.UserInputState == Enum.UserInputState.End or input.UserInputState == Enum.UserInputState.Cancel then
			cameraTouches[input] = nil
			touchLast[input] = nil
			continue
		end
		local pos = input.Position
		local last = touchLast[input]
		touchLast[input] = pos
		if last and canTurn then
			local d = pos - last
			yaw -= d.X * Config.TouchSensitivity * sens
			inputYaw -= d.X * Config.TouchSensitivity * sens
			inputPitch -= d.Y * Config.TouchSensitivity * sens
			pitch = math.clamp(pitch - d.Y * Config.TouchSensitivity * sens, PITCH_MIN, PITCH_MAX)
		end
	end
end

-- The held gun's magnified optic zoom (an FOV multiplier) in first person, or nil.
local function opticZoom(): number?
	if not ClientState.firstPerson then
		return nil
	end
	local char = player.Character
	local gun = char and char:FindFirstChild("HeldGun")
	local sight = gun and gun:GetAttribute("Sight")
	if sight == "scope" then
		return Config.ScopeFovMult
	elseif sight == "acog" then
		return Config.AcogFovMult
	elseif sight == "medium" then
		return Config.MediumScopeFovMult
	end
	return nil
end

local pivotYNow = 1.5
local shoulderBlend = 1 -- Round 24aa: 1 over the shoulder, 0 centred (cursor unlocked)
RunService:BindToRenderStep("GHSCamera", Enum.RenderPriority.Camera.Value, function(dt)
	camera.CameraType = Enum.CameraType.Scriptable
	local requested = ClientState.requestCameraYaw
	if requested then
		-- A sequence just ended behind the player: pick up facing the same way.
		yaw = requested
		pitch = -0.12
		ClientState.requestCameraYaw = nil
	end
	fovKick = math.max(0, fovKick - dt * 18)
	local adsGoal = if ClientState.ads then 1 else 0
	local adsRate = dt / math.max(Config.AdsBlendSec, 0.01)
	adsBlend += math.clamp(adsGoal - adsBlend, -adsRate, adsRate)
	-- Unlocked cursor: ADS only pulls in a little.
	local unlocked = ClientState.isMouseFree() and not ClientState.blocked()
	local adsFov = if unlocked then Config.AdsFovMultUnlocked else Config.AdsFovMult
	-- Round 24r: magnified optics in first person zoom further (sniper scope, ACOG) and slow the look to match.
	local zoomMult = opticZoom()
	if zoomMult then
		adsFov = zoomMult
		opticSens = 1 + (zoomMult / Config.AdsFovMult - 1) * adsBlend
	else
		opticSens = 1
	end
	local adsZoom = if unlocked then Config.AdsZoomMultUnlocked else Config.AdsZoomMult
	local fovMult = 1 + (adsFov - 1) * adsBlend
	camera.FieldOfView = Config.CameraFov * fovMult + fovKick + stimFov + slowFov
	local free = ClientState.isMouseFree()
	local drag = dragging()
	UserInputService.MouseBehavior = if not free
		then Enum.MouseBehavior.LockCenter
		elseif drag then Enum.MouseBehavior.LockCurrentPosition
		else Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = free and not drag
	-- Spectate and the run start / end sequences drive the camera themselves.
	if ClientState.cameraMode ~= "gameplay" then
		return
	end
	pollTouches()

	zoom += (targetZoom - zoom) * math.min(1, dt * Config.CameraZoomSmoothing)
	if math.abs(targetZoom - zoom) < 0.02 then
		zoom = targetZoom
	end
	local firstPerson = zoom < Config.CameraFirstPersonBelow
	ClientState.firstPerson = firstPerson -- FirstPersonView draws the viewmodel

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not root then
		return
	end

	-- Character visibility follows the first-person state, re-applied on respawn.
	local wantHidden: Model? = if firstPerson then char else nil
	if wantHidden ~= hiddenChar then
		if hiddenChar and hiddenChar.Parent then
			setHidden(hiddenChar, false)
		end
		setHidden(wantHidden, true)
		hiddenChar = wantHidden
	elseif firstPerson then
		-- Re-applied every frame: parts added after the switch (a new HeldGun, a fresh mag) and anything the
		-- PlayerModule's own transparency pass touches stay the way first person wants them.
		setHidden(char, true)
	end

	aimAssist(dt, char)
	camPunch *= math.exp(-dt * Config.CameraRecoilReturn)
	local rot = CFrame.fromEulerAnglesYXZ(math.clamp(pitch + camPunch, PITCH_MIN, PITCH_MAX), yaw, 0)
	-- Downed: the pivot drops to DownedCameraHeight above the floor (the root sits 3 studs up). It eases there and
	-- back, so a revive lifts the camera with the stand-up instead of snapping.
	local targetY = if ClientState.downed then Config.DownedCameraHeight - 3 else 1.5
	pivotYNow += (targetY - pivotYNow) * math.clamp(dt * 6, 0, 1)
	local pivot = root.Position + Vector3.new(0, pivotYNow, 0)
	local camPos: Vector3
	if firstPerson then
		-- Round 24b: a steady eye. The head's offset from the root is smoothed (FirstPersonSteadyRate) and only
		-- FirstPersonBobKeep of the walk bob comes through, so running no longer rocks the view.
		local head = char:FindFirstChild("Head") :: BasePart?
		local raw = if head then head.Position else pivot
		local rel = raw - root.Position
		local prev = fpEyeRel or rel
		local smoothed = prev:Lerp(rel, 1 - math.exp(-dt * Config.FirstPersonSteadyRate))
		fpEyeRel = smoothed
		camPos = (root.Position + smoothed):Lerp(raw, Config.FirstPersonBobKeep)
	else
		fpEyeRel = nil
		local dist = zoom * (1 + (adsZoom - 1) * adsBlend)
		local side = math.clamp(dist / Config.CameraZoomDefault, 0, 1)
		-- Round 24aa: cursor unlocked (Ctrl / Alt): the shoulder offset eases out so the character sits mid-screen.
		local wantShoulder = if ClientState.mouseFree or ClientState.mouseFreeHold then 0 else 1
		shoulderBlend += (wantShoulder - shoulderBlend) * math.clamp(dt * Config.CameraCenterRate, 0, 1)
		local offset = Vector3.new(Config.CameraShoulder.X * side * shoulderBlend, Config.CameraShoulder.Y * side, dist)
		local desired = pivot + rot:VectorToWorldSpace(offset)
		local filter: { Instance } = { char }
		for _, name in { "GroundLoot", "Effects", "Enemies" } do
			local f = Workspace:FindFirstChild(name)
			if f then
				table.insert(filter, f)
			end
		end
		params.FilterDescendantsInstances = filter
		local hit = Workspace:Raycast(pivot, desired - pivot, params)
		camPos = if hit then hit.Position + (pivot - desired).Unit * 0.6 else desired
	end
	local shake = CFrame.identity
	if shakeLeft > 0 then
		shakeLeft = math.max(0, shakeLeft - dt)
		local k = shakeAmp * (shakeLeft / math.max(shakeTotal, 0.01))
		shake = CFrame.new((math.random() - 0.5) * 2 * k, (math.random() - 0.5) * 2 * k, 0)
		if shakeLeft <= 0 then
			shakeAmp = 0
		end
	end
	camera.CFrame = CFrame.new(camPos) * rot * shake
	camera.Focus = CFrame.new(pivot)

	if hum and hum.Health > 0 and ClientState.combatOff() then
		-- Hub: the cursor is free, the character turns with its own movement (default Roblox), RMB drags.
		hum.AutoRotate = true
	elseif hum and hum.Health > 0 then
		hum.AutoRotate = false
		local faceYaw = yaw
		if free and not ClientState.blocked() then
			-- Face the cursor's world point so you can aim all the way around while the camera stays put.
			local aim = ClientState.cursorAimPoint(char)
			local dx, dz = aim.X - root.Position.X, aim.Z - root.Position.Z
			if dx * dx + dz * dz > 1 then
				faceYaw = math.atan2(-dx, -dz)
			end
		end
		root.CFrame = CFrame.new(root.Position) * CFrame.fromEulerAnglesYXZ(0, faceYaw, 0)
	end
end)
