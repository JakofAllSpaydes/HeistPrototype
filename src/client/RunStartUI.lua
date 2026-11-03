--!strict
-- Run start on the client: the camera timeline (door shot on the van, pan along the line, hold for masks,
-- push in on the poses, orbit to behind the local player) and the animations (mask-on, poses) played on
-- every character in the line. Runs off the server clock in RunStartBegin; input locked, HUD down to the
-- wave bar, not skippable.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local HUD = require(script.Parent:WaitForChild("HUD"))

local RunStartUI = {}

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera :: Camera

local data: any = nil
local fired: { [string]: boolean } = {}
local tracks: { AnimationTrack } = {}

local function easeOut(s: number): number
	s = math.clamp(s, 0, 1)
	return 1 - (1 - s) * (1 - s)
end

-- A roster entry's character: a dummy's model, or the player's character.
function RunStartUI.charFor(entry: any): Model?
	if typeof(entry.model) == "Instance" then
		return entry.model
	end
	local p = Players:GetPlayerByUserId(tonumber(entry.userId) or 0)
	return if p then p.Character else nil
end

-- Play an animation on any character (local playback on every client reads the same for everyone).
function RunStartUI.playAnim(char: Model?, id: string, holdSec: number?): AnimationTrack?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return nil
	end
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = hum
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = id
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	if not ok or not track then
		return nil
	end
	track.Priority = Enum.AnimationPriority.Action
	track:Play(0.1)
	table.insert(tracks, track)
	if holdSec then
		task.delay(holdSec, function()
			if track.IsPlaying then
				track:Stop(0.2)
			end
		end)
	end
	return track
end

local function stopTracks()
	for _, t in tracks do
		if t.IsPlaying then
			t:Stop(0.1)
		end
	end
	tracks = {}
end

local function vanBody(): BasePart?
	local room = Workspace:FindFirstChild("Room")
	local van = room and room:FindFirstChild("Van")
	local body = van and van:FindFirstChild("Body")
	return if body and body:IsA("BasePart") then body else nil
end

local function once(beat: string, fn: () -> ())
	if not fired[beat] then
		fired[beat] = true
		fn()
	end
end

local lastCF: CFrame? = nil

local function finish()
	local d = data
	if not d then
		return
	end
	data = nil
	pcall(function()
		RunService:UnbindFromRenderStep("GHSRunStart")
	end)
	stopTracks()
	ClientState.cameraMode = "gameplay"
	ClientState.requestCameraYaw = 0 -- the line faces north (-Z); the gameplay camera picks up behind
	ClientState.setBlock("cinematic", false)
	HUD.setMode("gameplay")
end

local function step(_dt: number)
	local d = data
	if not d then
		return
	end
	local t = ClientState.serverNow() - d.startedAt
	local beats = d.beats
	local line: { CFrame } = d.line
	if #line == 0 then
		if t >= d.introSec then
			finish()
		end
		return
	end
	local sum = Vector3.zero
	for _, cf in line do
		sum += cf.Position
	end
	local lineCenter = sum / #line
	local myIndex = 1
	for i, entry in d.players do
		if entry.userId == player.UserId then
			myIndex = i
		end
	end
	local myCF: CFrame = line[myIndex] or line[1]
	local myChar = player.Character
	local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	local myPos = if myRoot and t >= beats.doors then myRoot.Position else myCF.Position

	local cf: CFrame
	if t < beats.doors then
		-- Low, front-left of the door, watching the van come in.
		local door: Vector3 = d.door
		local body = vanBody()
		local target = if body then body.Position else door
		cf = CFrame.lookAt(door + Vector3.new(-16, 2.5, 14), target + Vector3.new(0, 1, 0))
	elseif t < beats.masks then
		once("doors", function()
			UI.sound(Theme.Sounds.take, 0.8, 0.6)
		end)
		-- Pan along the line at chest height.
		local s = (t - beats.doors) / math.max(beats.masks - beats.doors, 0.01)
		local a, b = line[1].Position, line[#line].Position
		local x = a.X + (b.X - a.X) * easeOut(s)
		cf = CFrame.lookAt(Vector3.new(x, 2.6, lineCenter.Z - 7), Vector3.new(x, 2.3, lineCenter.Z))
	elseif t < beats.poses then
		once("masks", function()
			for _, entry in d.players do
				RunStartUI.playAnim(RunStartUI.charFor(entry), Config.MaskOnAnimationId, beats.poses - beats.masks)
			end
			UI.sound(Theme.Sounds.swap, 1.1, 0.5)
		end)
		-- Holds.
		cf = lastCF or CFrame.lookAt(Vector3.new(lineCenter.X, 2.6, lineCenter.Z - 7), lineCenter)
	elseif t < beats.orbit then
		once("poses", function()
			for i, entry in d.players do
				local pose = Config.Poses[entry.pose] or Config.Poses[1]
				task.delay(Config.PoseStagger * (i - 1), function()
					if data == d then
						RunStartUI.playAnim(RunStartUI.charFor(entry), pose.animationId, pose.holdSec)
					end
				end)
			end
			UI.sound(Theme.Sounds.reelLand, 1, 0.5)
		end)
		-- Slow push in on the line.
		local s = easeOut((t - beats.poses) / math.max(beats.orbit - beats.poses, 0.01))
		cf = CFrame.lookAt(
			Vector3.new(lineCenter.X, 3.2 - 0.5 * s, lineCenter.Z - (10 - 3.5 * s)),
			lineCenter + Vector3.new(0, 2, 0)
		)
	elseif t < d.introSec then
		-- Orbit 180 degrees from the front to behind the local player, easing into the gameplay camera.
		local s = easeOut((t - beats.orbit) / math.max(d.introSec - beats.orbit, 0.01))
		local theta = math.pi * (1 - s)
		local r = Config.CameraZoomDefault
		local offset = Vector3.new(
			math.sin(theta) * r + Config.CameraShoulder.X * s,
			2.4 + Config.CameraShoulder.Y * s,
			math.cos(theta) * r
		)
		cf = CFrame.lookAt(myPos + offset, myPos + Vector3.new(0, 1.5, 0) + Vector3.new(0, 0, -6) * s)
	else
		finish()
		return
	end
	lastCF = cf
	camera.CFrame = cf
	camera.Focus = cf
end

local function begin(d: any)
	finish()
	data = d
	fired = {}
	lastCF = nil
	ClientState.setAds(false)
	ClientState.cameraMode = "cinematic"
	ClientState.setBlock("cinematic", true)
	HUD.setMode("cinematic")
	RunService:BindToRenderStep("GHSRunStart", Enum.RenderPriority.Camera.Value + 1, step)
	UI.sound(Theme.Sounds.wave, 0.7, 0.5)
end

function RunStartUI.init()
	ClientState.Juice:Connect(function(name: string, d: any)
		if name == "RunStartBegin" then
			begin(d)
		elseif name == "StagingEnter" or name == "RunOver" then
			finish()
		end
	end)
end

return RunStartUI
