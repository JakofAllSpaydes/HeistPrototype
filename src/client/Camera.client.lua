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
UserInputService.InputBegan:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		rmbHeld = true
	end
end)
UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		rmbHeld = false
	end
end)
local function dragging(): boolean
	return rmbHeld and ClientState.isMouseFree() and not ClientState.blocked()
end

UserInputService.InputChanged:Connect(function(input: InputObject, gameProcessed: boolean)
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		if not ClientState.blocked() then
			zoomStep(input.Position.Z)
		end
		return
	end
	-- Cursor unlocked: the camera holds still (the character turns toward the cursor in the render step)
	-- unless RMB is held, which drags it.
	if ClientState.isMouseFree() and not dragging() then
		return
	end
	local sens = if ClientState.ads then Config.AdsSensitivityMult else 1
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		yaw -= input.Delta.X * Config.MouseSensitivity * sens
		pitch = math.clamp(pitch - input.Delta.Y * Config.MouseSensitivity * sens, PITCH_MIN, PITCH_MAX)
	elseif input.UserInputType == Enum.UserInputType.Touch and not gameProcessed and not pinching then
		yaw -= input.Delta.X * Config.TouchSensitivity * sens
		pitch = math.clamp(pitch - input.Delta.Y * Config.TouchSensitivity * sens, PITCH_MIN, PITCH_MAX)
	end
end)

-- Pinch: scale is relative to the gesture start, so spreading the fingers (scale > 1) zooms in.
UserInputService.TouchPinch:Connect(
	function(
		_touches: { Vector2 },
		scale: number,
		_velocity: number,
		state: Enum.UserInputState,
		gameProcessed: boolean
	)
		if state == Enum.UserInputState.Begin then
			if gameProcessed or ClientState.blocked() then
				return
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
local stimFov = 0
local slowFov = 0
local shakeAmp = 0
local shakeLeft = 0
local shakeTotal = 0
local adsBlend = 0 -- 0 hip, 1 fully aimed
ClientState.Juice:Connect(function(name: string, data: any)
	if name == "LocalFire" then
		fovKick = Config.FireFovKick
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
	end
end)

-- First person hides the local character (gun and accessories included) so nothing sits in front of the lens.
local hiddenChar: Model? = nil
local function setHidden(char: Model?, hidden: boolean)
	if not char then
		return
	end
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			d.LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
end

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

	zoom += (targetZoom - zoom) * math.min(1, dt * Config.CameraZoomSmoothing)
	if math.abs(targetZoom - zoom) < 0.02 then
		zoom = targetZoom
	end
	local firstPerson = zoom < Config.CameraFirstPersonBelow

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
		-- Parts added after the switch (new HeldGun on swap) start visible; keep them hidden.
		local gun = char:FindFirstChild("HeldGun") :: BasePart?
		if gun and gun.LocalTransparencyModifier < 1 then
			setHidden(char, true)
		end
	end

	local rot = CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)
	-- Downed: the pivot drops to DownedCameraHeight above the floor (the root sits 3 studs up).
	local pivotY = if ClientState.downed then Config.DownedCameraHeight - 3 else 1.5
	local pivot = root.Position + Vector3.new(0, pivotY, 0)
	local camPos: Vector3
	if firstPerson then
		local head = char:FindFirstChild("Head") :: BasePart?
		camPos = if head then head.Position else pivot
	else
		local dist = zoom * (1 + (adsZoom - 1) * adsBlend)
		local side = math.clamp(dist / Config.CameraZoomDefault, 0, 1)
		local offset = Vector3.new(Config.CameraShoulder.X * side, Config.CameraShoulder.Y * side, dist)
		local desired = pivot + rot:VectorToWorldSpace(offset)
		local filter: { Instance } = { char }
		for _, name in { "GroundLoot", "Effects" } do
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

	if hum and hum.Health > 0 then
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
