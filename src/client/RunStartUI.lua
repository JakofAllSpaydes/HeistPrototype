--!strict
-- Run start on the client: the camera timeline (door shot on the van, one slow pan from the farthest crew
-- member to you that pushes in as it arrives, orbit to behind you) and the animations (mask-on, poses)
-- played on every character in the line. Runs off the server clock in RunStartBegin; input locked, HUD
-- down to the wave bar, not skippable. Brief 8: before it, HubDepart is a short chase behind the hub van as it
-- pulls out of the garage (the cut to the map's drive-in comes with RunStartBegin).
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Emotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Emotes"))
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

-- Emotes (SQUAD poses, MVP flexes, the dummies' line-up poses) play one priority above everything else on a
-- character: the class idles (MetaScene) and the mask-on play at Action, and two tracks at the SAME priority blend
-- by weight, so an emote at Action came out half-strength over a looping idle. GunAnim still hands the arms back for
-- Action2 (it checks Action..Action4).
RunStartUI.EMOTE_PRIORITY = Enum.AnimationPriority.Action2

-- Play an animation on any character (local playback on every client reads the same for everyone). `priority`
-- defaults to Action; emotes pass RunStartUI.EMOTE_PRIORITY.
function RunStartUI.playAnim(
	char: Model?,
	id: string,
	holdSec: number?,
	priority: Enum.AnimationPriority?
): AnimationTrack?
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
	track.Priority = priority or Enum.AnimationPriority.Action
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

-- The van being chased: the arrival van the server sent (brief 8), else the old yard van.
local function vanPoint(d: any): Vector3?
	local van = d and d.van
	if typeof(van) == "Instance" and van:IsA("Model") and van.Parent then
		return van:GetPivot().Position + Vector3.new(0, 4, 0)
	end
	local room = Workspace:FindFirstChild("Room")
	local old = room and room:FindFirstChild("Van")
	local body = old and old:FindFirstChild("Body")
	return if body and body:IsA("BasePart") then body.Position else nil
end

------------------------------------------------------------------ Van drives (brief 8)
-- The server sends both ends of a drive; every client moves the van itself each frame (smooth), with the same
-- easing as the server's clock, and the chase cameras read the same curve.
local function vanEase(s: number, ease: string?): number
	s = math.clamp(s, 0, 1)
	return if ease == "in" then s * s else 1 - (1 - s) * (1 - s)
end

local function vanAt(d: any, now: number): CFrame?
	if typeof(d.from) ~= "CFrame" or typeof(d.to) ~= "CFrame" then
		return nil
	end
	local sec = math.max(tonumber(d.sec) or 1, 0.01)
	local s = (now - (tonumber(d.startedAt) or now)) / sec
	return (d.from :: CFrame):Lerp(d.to :: CFrame, vanEase(s, d.ease))
end

local drives: { [Model]: any } = {}
local function startDrive(d: any)
	local van = d.van
	if typeof(van) ~= "Instance" or not van:IsA("Model") then
		return
	end
	drives[van] = d
end
RunService.RenderStepped:Connect(function()
	if next(drives) == nil then
		return
	end
	local now = ClientState.serverNow()
	for van, d in drives do
		local cf = vanAt(d, now)
		if not cf or not van.Parent then
			drives[van] = nil
			continue
		end
		van:PivotTo(cf)
		if now - (tonumber(d.startedAt) or now) >= (tonumber(d.sec) or 0) then
			drives[van] = nil
		end
	end
end)

-- Behind and above a van, looking past its nose.
local function chaseShot(van: CFrame): CFrame
	local look = Vector3.new(van.LookVector.X, 0, van.LookVector.Z)
	look = if look.Magnitude > 0.1 then look.Unit else Vector3.new(0, 0, -1)
	local at = van.Position - look * 18 + Vector3.new(0, 7, 0)
	return CFrame.lookAt(at, van.Position + look * 12 + Vector3.new(0, 2.5, 0))
end

------------------------------------------------------------------ The hub departure (brief 8)
local departing = false
local departChase: Vector3? = nil

local function departStop(restore: boolean?)
	if not departing then
		return
	end
	departing = false
	pcall(function()
		RunService:UnbindFromRenderStep("GHSHubDepart")
	end)
	if restore and not data then
		-- No cut came (the run never started): hand the camera and the HUD back.
		ClientState.cameraMode = "gameplay"
		ClientState.setBlock("cinematic", false)
		HUD.setMode(HUD.baseMode())
	end
end

-- Behind and above the hub van, looking past its nose, until the cut (RunStartBegin) or a timeout.
local function departStart(d: any)
	local van = d.van
	if typeof(van) ~= "Instance" or not van:IsA("Model") then
		return
	end
	departStop()
	departing = true
	departChase = nil
	local t0 = os.clock()
	local sec = (tonumber(d.sec) or 2.5) + 2
	ClientState.setAds(false)
	ClientState.cameraMode = "cinematic"
	ClientState.setBlock("cinematic", true)
	HUD.setMode("cinematic")
	UI.sound(Theme.Sounds.shutter, 1.15, 0.45)
	RunService:BindToRenderStep("GHSHubDepart", Enum.RenderPriority.Camera.Value + 1, function()
		if not van.Parent or os.clock() - t0 > sec then
			departStop(true)
			return
		end
		local cf = chaseShot(van:GetPivot()) -- the van moves smoothly on this client (VanDrive)
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = cf
		camera.Focus = cf
	end)
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
	-- The gameplay camera picks up behind the line: north (-Z) on the arena, the line's own look on a map
	-- (Round 19c: THE BANK's crew faces +Z, toward the building).
	local f = d.facing
	if typeof(f) == "Vector3" and Vector3.new(f.X, 0, f.Z).Magnitude > 0.1 then
		ClientState.requestCameraYaw = math.atan2(-f.X, -f.Z)
	else
		ClientState.requestCameraYaw = 0
	end
	ClientState.setBlock("cinematic", false)
	HUD.setMode(HUD.baseMode())
end

-- Brief 7: the line's own frame. The arena's line faces -Z at floor height (the plain world frame, so nothing
-- moves there); a map that sends `facing` (THE BANK: the crew faces the bank) turns every shot with it.
local function lineFrame(d: any, line: { CFrame }, center: Vector3): CFrame
	local floorY = (if #line > 0 then line[1].Position.Y else Config.FloorTop + 3) - (Config.FloorTop + 3)
	local p = Vector3.new(center.X, floorY, center.Z)
	local f = d.facing
	if typeof(f) == "Vector3" and Vector3.new(f.X, 0, f.Z).Magnitude > 0.1 then
		return CFrame.lookAt(p, p + Vector3.new(f.X, 0, f.Z))
	end
	return CFrame.new(p)
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
	local lineCenter = Vector3.zero
	for _, l in line do
		lineCenter += l.Position
	end
	lineCenter /= #line
	local F = lineFrame(d, line, lineCenter)
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
	-- The pan starts on whoever stands farthest from you in the line (x along the line, in its frame).
	local farX = F:PointToObjectSpace(if myIndex <= #line / 2 then line[#line].Position else line[1].Position).X
	local myL = F:PointToObjectSpace(myPos)

	local cf: CFrame
	if t < beats.doors then
		-- Chase the van from behind as it drives in (the same curve the van follows on this client).
		local vanCF = vanAt(
			{ from = d.vanFrom, to = d.vanTo, sec = beats.doors, startedAt = d.startedAt, ease = "out" },
			ClientState.serverNow()
		)
		if vanCF then
			cf = chaseShot(vanCF)
		else
			local door: Vector3 = d.door
			local target = vanPoint(d) or door
			cf = CFrame.lookAt(target + F:VectorToWorldSpace(Vector3.new(2, 6, 14)), target)
		end
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
							RunStartUI.playAnim(RunStartUI.charFor(entry), animId, hold, RunStartUI.EMOTE_PRIORITY)
						end
					end)
				end
				UI.sound(Theme.Sounds.reelLand, 1, 0.5)
			end)
		end
		-- One slow pan from the farthest crew member to you, pushing in as it lands on you.
		local s = smooth((t - beats.doors) / math.max(beats.orbit - beats.doors, 0.01))
		local x = farX + (myL.X - farX) * s
		local dist = PAN_FAR + (PAN_NEAR - PAN_FAR) * s
		local height = PAN_HEIGHT + (EYE_LINE + 0.4 - PAN_HEIGHT) * s
		cf = CFrame.lookAt(
			F:PointToWorldSpace(Vector3.new(x, height, -dist)),
			F:PointToWorldSpace(Vector3.new(x, EYE_LINE, 0))
		)
	elseif t < d.introSec then
		-- Orbit 180 degrees from the tight front shot to behind you, widening into the gameplay camera.
		local s = easeOut((t - beats.orbit) / math.max(d.introSec - beats.orbit, 0.01))
		local theta = math.pi * (1 - s)
		local r = PAN_NEAR + (Config.CameraZoomDefault - PAN_NEAR) * s
		local offset = F:VectorToWorldSpace(
			Vector3.new(
				math.sin(theta) * r + Config.CameraShoulder.X * s,
				(EYE_LINE + 0.4) + (1.5 + Config.CameraShoulder.Y - (EYE_LINE + 0.4)) * s,
				math.cos(theta) * r
			)
		)
		local look = F:PointToWorldSpace(Vector3.new(myL.X, EYE_LINE - 1.1 * s, myL.Z - 8 * s))
		cf = CFrame.lookAt(myPos + offset, look)
	else
		finish()
		return
	end
	camera.CFrame = cf
	camera.Focus = cf
end

local function begin(d: any)
	departStop()
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

-- Fetch every emote / line-up animation once up front, so a pose's first play (a 1.2 s hold) is not spent
-- downloading the clip and the first preview tap in the Avatar tab lands at once.
local function preloadEmotes()
	local seen: { [string]: boolean } = {}
	local anims: { Instance } = {}
	local function add(id: any)
		if typeof(id) == "string" and id ~= "" and not seen[id] then
			seen[id] = true
			local a = Instance.new("Animation")
			a.AnimationId = id
			table.insert(anims, a)
		end
	end
	for _, e in Emotes.List do
		add(e.animationId)
	end
	for _, p in Config.Poses do
		add(p.animationId)
	end
	add(Config.MvpAnimationId)
	add(Config.MaskOnAnimationId)
	pcall(function()
		ContentProvider:PreloadAsync(anims)
	end)
end

function RunStartUI.init()
	task.spawn(preloadEmotes)
	ClientState.Juice:Connect(function(name: string, d: any)
		if name == "RunStartBegin" then
			begin(d)
		elseif name == "HubDepart" then
			departStart(d)
		elseif name == "VanDrive" then
			startDrive(d)
		elseif name == "HubEnter" or name == "RunOver" then
			departStop()
			finish()
		end
	end)
end

return RunStartUI
