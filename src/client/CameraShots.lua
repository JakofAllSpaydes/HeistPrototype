--!strict
-- Brief 10: named camera frames on hub objects and the push onto them (the JOBS board's timing: 0.6 s, cubic out).
-- CameraShots.daily(): the daily crate podium, three-quarter on and a little high, the crate left of centre so the
-- right-docked sheet never covers it. push() holds the camera there (ClientState.cameraMode = "shot") until
-- release(); a scene that takes over (the crate scene) saves and restores the mode itself.
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent:WaitForChild("ClientState"))

local CameraShots = {}

local camera = Workspace.CurrentCamera :: Camera
local active = false
local camFrom: CFrame? = nil
local camTo: CFrame? = nil
local camT0, camSec = 0, 0.6

-- The podium's crate spot (Workspace.Hub.DailyPodium.CrateSpot), nil when the hub has no podium.
function CameraShots.dailySpot(): BasePart?
	local hub = Workspace:FindFirstChild("Hub")
	local podium = hub and hub:FindFirstChild("DailyPodium")
	local spot = podium and podium:FindFirstChild("CrateSpot")
	return if spot and spot:IsA("BasePart") then spot else nil
end

function CameraShots.daily(): CFrame?
	local spot = CameraShots.dailySpot()
	if not spot then
		return nil
	end
	local cf = spot.CFrame
	local front = cf.LookVector -- toward the room
	local right = cf.RightVector
	local target = cf.Position + Vector3.new(0, 1, 0)
	local eye = target + front * 9 - right * 2.2 + Vector3.new(0, 3.2, 0)
	-- Aim past the crate's right so it sits left of centre.
	return CFrame.lookAt(eye, target + right * 2.4)
end

function CameraShots.push(to: CFrame, sec: number?)
	camFrom = camera.CFrame
	camTo = to
	camT0, camSec = os.clock(), sec or 0.6
	if active then
		return
	end
	active = true
	ClientState.cameraMode = "shot"
	RunService:BindToRenderStep("GHSShotCamera", Enum.RenderPriority.Camera.Value + 3, function()
		local target = camTo
		if not active or not target or ClientState.cameraMode ~= "shot" then
			return
		end
		camera.CameraType = Enum.CameraType.Scriptable
		local s = math.clamp((os.clock() - camT0) / camSec, 0, 1)
		local k = 1 - (1 - s) ^ 3
		camera.CFrame = (camFrom or target):Lerp(target, k)
	end)
end

function CameraShots.isActive(): boolean
	return active
end

function CameraShots.release()
	if not active then
		return
	end
	active = false
	pcall(function()
		RunService:UnbindFromRenderStep("GHSShotCamera")
	end)
	camFrom, camTo = nil, nil
	camera.CameraType = Enum.CameraType.Custom
	if ClientState.cameraMode == "shot" then
		ClientState.cameraMode = "gameplay"
	end
end

return CameraShots
