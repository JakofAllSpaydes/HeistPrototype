--!strict
-- Run start on the client: the camera timeline (door shot on the van, one slow pan from the farthest crew
-- member to you that pushes in as it arrives, orbit to behind you) and the animations (mask-on, poses)
-- played on every character in the line. Runs off the server clock in RunStartBegin; input locked, HUD
-- down to the wave bar, not skippable.
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
local chasePos: Vector3? = nil -- smoothed camera position while following the van

-- Camera framing: characters stand about 5 studs tall with the root 3 up, so chest is ~3 and the head ~5.
local EYE_LINE = 2.8 -- where the camera looks on a character
local PAN_HEIGHT = 3.6
local PAN_FAR = 10 -- distance from the line at the start of the pan
local PAN_NEAR = 5.5 -- distance when it lands on you

local function easeOut(s: number): number
	s = math.clamp(s, 0, 1)
	return 1 - (1 - s) * (1 - s)
end

local function smooth(s: number): number
	s = math.clamp(s, 0, 1)
	return s * s * (3 - 2 * s)
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
	HUD.setMode(HUD.baseMode())
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
	local lineZ = line[1].Position.Z
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
	-- The pan starts on whoever stands farthest from you in the line.
	local farX = if myIndex <= #line / 2 then line[#line].Position.X else line[1].Position.X

	local cf: CFrame
	if t < beats.doors then
		-- Chase the van from behind-right and above, through the door and into the arena.
		local door: Vector3 = d.door
		local body = vanBody()
		local target = if body then body.Position else door
		local want = target + Vector3.new(2, 6, 14)
		local prev = chasePos
		chasePos = if prev then prev:Lerp(want, 0.25) else want
		cf = CFrame.lookAt(chasePos, target + Vector3.new(0, 1.5, -4))
	elseif t < beats.orbit then
		once("doors", function()
			UI.sound(Theme.Sounds.take, 0.8, 0.6)
		end)
		if t >= beats.masks then
			once("masks", function()
				for _, entry in d.players do
					RunStartUI.playAnim(RunStartUI.charFor(entry), Config.MaskOnAnimationId, beats.poses - beats.masks)
				end
				UI.sound(Theme.Sounds.swap, 1.1, 0.5)
			end)
		end
		if t >= beats.poses then
			once("poses", function()
				for i, entry in d.players do
					local pose = Config.Poses[entry.pose] or Config.Poses[1]
					local animId = if typeof(entry.poseAnim) == "string" then entry.poseAnim else pose.animationId
					local hold = tonumber(entry.poseHold) or pose.holdSec
					task.delay(Config.PoseStagger * (i - 1), function()
						if data == d then
							RunStartUI.playAnim(RunStartUI.charFor(entry), animId, hold)
						end
					end)
				end
				UI.sound(Theme.Sounds.reelLand, 1, 0.5)
			end)
		end
		-- One slow pan from the farthest crew member to you, pushing in as it lands on you.
		local s = smooth((t - beats.doors) / math.max(beats.orbit - beats.doors, 0.01))
		local x = farX + (myPos.X - farX) * s
		local dist = PAN_FAR + (PAN_NEAR - PAN_FAR) * s
		local height = PAN_HEIGHT + (EYE_LINE + 0.4 - PAN_HEIGHT) * s
		cf = CFrame.lookAt(Vector3.new(x, height, lineZ - dist), Vector3.new(x, EYE_LINE, lineZ))
	elseif t < d.introSec then
		-- Orbit 180 degrees from the tight front shot to behind you, widening into the gameplay camera.
		local s = easeOut((t - beats.orbit) / math.max(d.introSec - beats.orbit, 0.01))
		local theta = math.pi * (1 - s)
		local r = PAN_NEAR + (Config.CameraZoomDefault - PAN_NEAR) * s
		local offset = Vector3.new(
			math.sin(theta) * r + Config.CameraShoulder.X * s,
			(EYE_LINE + 0.4) + (1.5 + Config.CameraShoulder.Y - (EYE_LINE + 0.4)) * s,
			math.cos(theta) * r
		)
		local look = Vector3.new(myPos.X, EYE_LINE - 1.1 * s, myPos.Z - 8 * s)
		cf = CFrame.lookAt(myPos + offset, look)
	else
		finish()
		return
	end
	camera.CFrame = cf
	camera.Focus = cf
end

local function begin(d: any)
	finish()
	data = d
	fired = {}
	chasePos = nil
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
		elseif name == "HubEnter" or name == "RunOver" then
			finish()
		end
	end)
end

return RunStartUI
