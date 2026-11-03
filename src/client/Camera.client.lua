--!strict
-- Fixed right-shoulder third person, mouse look, shift-lock style. No first person.
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
local SHOULDER = Vector3.new(2.6, 1.2, 8) -- right, up, back

UserInputService.InputChanged:Connect(function(input: InputObject, gameProcessed: boolean)
	if ClientState.isMouseFree() then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		yaw -= input.Delta.X * Config.MouseSensitivity
		pitch = math.clamp(pitch - input.Delta.Y * Config.MouseSensitivity, PITCH_MIN, PITCH_MAX)
	elseif input.UserInputType == Enum.UserInputType.Touch and not gameProcessed then
		yaw -= input.Delta.X * Config.TouchSensitivity
		pitch = math.clamp(pitch - input.Delta.Y * Config.TouchSensitivity, PITCH_MIN, PITCH_MAX)
	end
end)

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude

-- FOV kick on fire and camera shake, both decay each frame.
local fovKick = 0
local shakeAmp = 0
local shakeLeft = 0
local shakeTotal = 0
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
	end
end)
local stimFov = 0

RunService:BindToRenderStep("GHSCamera", Enum.RenderPriority.Camera.Value, function(dt)
	camera.CameraType = Enum.CameraType.Scriptable
	fovKick = math.max(0, fovKick - dt * 18)
	camera.FieldOfView = Config.CameraFov + fovKick + stimFov
	local free = ClientState.isMouseFree()
	UserInputService.MouseBehavior = if free then Enum.MouseBehavior.Default else Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = free

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not root then
		return
	end

	local rot = CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)
	local pivot = root.Position + Vector3.new(0, 1.5, 0)
	local desired = pivot + rot:VectorToWorldSpace(SHOULDER)
	local filter: { Instance } = { char }
	for _, name in { "GroundLoot", "Effects" } do
		local f = Workspace:FindFirstChild(name)
		if f then
			table.insert(filter, f)
		end
	end
	params.FilterDescendantsInstances = filter
	local hit = Workspace:Raycast(pivot, desired - pivot, params)
	local camPos = if hit then hit.Position + (pivot - desired).Unit * 0.6 else desired
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
		root.CFrame = CFrame.new(root.Position) * CFrame.fromEulerAnglesYXZ(0, yaw, 0)
	end
end)
