--!strict
-- Art pass: procedural gun animation for every crew member (no uploaded animation assets).
-- Each client poses every R15 character holding a HeldGun (GunModels): the gun is placed from a per-kind stance
-- (Config.GunPoses: hip / aimed, stance twist, aim pitch), then both arms are solved with two-bone IK so the right
-- hand lands on the grip and the left on the foregrip. On top: recoil springs, the pistol slide, pump / bolt /
-- lever cycling, magazine reloads (mag drops, a fresh one comes from the belt and seats) and shell-by-shell
-- reloads, muzzle flash and brass. Teammates' aim pitch / ADS / reload state arrive as character attributes
-- (Remotes.GunPose -> Combat), their shots through the RemoteShot juice event.
-- Runs in PreSimulation, after the Animator has written this frame's joints, so walk / idle legs keep playing.
-- Any Action-priority track (the downed crawl, line-up poses, emotes) or the hub hands the arms back.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Weapons = require(Shared:WaitForChild("Weapons"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))

local player = Players.LocalPlayer
local effects = Workspace:WaitForChild("Effects")

local ID = CFrame.identity

type Pieces = { [string]: Motor6D }

-- A body joint: a Motor6D, or (Roblox's avatar joint upgrade) an AnimationConstraint wrapped to look like one
-- (C0 / C1 from its attachments, Transform read / written through).
type Joint = { C0: CFrame, C1: CFrame, Transform: CFrame, Parent: Instance? }

type Rig = {
	char: Model,
	hum: Humanoid,
	hrp: BasePart,
	upper: BasePart, -- UpperTorso (R15) / Torso (R6)
	r15: boolean,
	armLen: number, -- R6: the arm's length (the gun hand is the arm's end)
	rootJ: Joint,
	waist: Joint?, -- R15 only
	neck: Joint?,
	rs: Joint,
	re: Joint?, -- R15 only (elbows / wrists)
	rw: Joint?,
	ls: Joint,
	le: Joint?,
	lw: Joint?,
	-- gun (refreshed when HeldGun changes)
	gun: BasePart?,
	joint: Motor6D?,
	pieces: Pieces,
	kind: string,
	action: string,
	magKind: string,
	fireRate: number,
	gripPos: Vector3,
	buttPos: Vector3,
	sightPos: Vector3,
	magWell: Vector3,
	fore: Attachment?,
	magParts: { [BasePart]: number },
	-- state
	weight: number,
	ads: number,
	pitch: number,
	yaw: number,
	reloadW: number,
	kick: number,
	kickV: number,
	rise: number,
	riseV: number,
	yawKick: number,
	yawKickV: number,
	lastShot: number,
	cycleStart: number,
	cycleSec: number,
	cycleEjected: boolean,
	leftPos: Vector3?,
	shell: BasePart?,
	reloadKey: number,
	reloadEmpty: boolean,
	reloadEjected: boolean,
	touched: boolean,
	last: { [string]: CFrame },
	base: { [string]: CFrame },
}

local rigs: { [Model]: Rig } = {}

------------------------------------------------------------------ helpers
local function smooth(e0: number, e1: number, x: number): number
	local t = math.clamp((x - e0) / (e1 - e0), 0, 1)
	return t * t * (3 - 2 * t)
end

local function approach(cur: number, target: number, sec: number, dt: number): number
	if sec <= 0 then
		return target
	end
	local step = dt / sec
	if cur < target then
		return math.min(target, cur + step)
	end
	return math.max(target, cur - step)
end

local function motor(parent: Instance?, name: string): Motor6D?
	local m = parent and parent:FindFirstChild(name)
	return if m and m:IsA("Motor6D") then m else nil
end

-- A body joint by name under `parent` (or anywhere in the character): Motor6D or AnimationConstraint.
local function joint(char: Model, parent: Instance?, name: string): Joint?
	local j = (parent and parent:FindFirstChild(name)) or char:FindFirstChild(name, true)
	if not j then
		return nil
	end
	if j:IsA("Motor6D") then
		return (j :: any) :: Joint
	end
	if j:IsA("AnimationConstraint") then
		local ac = j :: any
		local a0, a1 = ac.Attachment0, ac.Attachment1
		if not a0 or not a1 then
			return nil
		end
		local proxy = setmetatable({ C0 = a0.CFrame, C1 = a1.CFrame }, {
			__index = function(_, k)
				if k == "Transform" then
					return ac.Transform
				elseif k == "Parent" then
					return ac.Parent
				end
				return nil
			end,
			__newindex = function(_, k, v)
				if k == "Transform" then
					ac.Transform = v
				end
			end,
		})
		return (proxy :: any) :: Joint
	end
	return nil
end

-- A rotation that carries the local bone direction `restDir` onto `worldDir`, with the local X (the R15 elbow
-- hinge) on `hinge`.
local function frameFrom(restDir: Vector3, worldDir: Vector3, hinge: Vector3): CFrame
	local lp = restDir.Unit
	local lx = Vector3.xAxis - lp * Vector3.xAxis:Dot(lp)
	if lx.Magnitude < 1e-4 then
		lx = Vector3.zAxis
	end
	lx = lx.Unit
	local lz = lx:Cross(lp)
	local wp = worldDir.Unit
	local wx = hinge - wp * hinge:Dot(wp)
	if wx.Magnitude < 1e-4 then
		wx = Vector3.xAxis
	end
	wx = wx.Unit
	local wz = wx:Cross(wp)
	return CFrame.fromMatrix(Vector3.zero, wx, wp, wz) * CFrame.fromMatrix(Vector3.zero, lx, lp, lz):Inverse()
end

-- Two-bone IK: puts the hand's centre on `target` with the elbow bent toward `pole`. Writes the shoulder / elbow /
-- wrist transforms blended by `w` and returns the hand's resulting CFrame.
local function solveArm(
	torso: CFrame,
	sh: Joint,
	el: Joint,
	wr: Joint,
	target: Vector3,
	pole: Vector3,
	w: number
): CFrame
	local S = (torso * sh.C0).Position
	local restU = el.C0.Position - sh.C1.Position
	local restL = wr.C0.Position - el.C1.Position
	local a, b = restU.Magnitude, restL.Magnitude
	local h = wr.C1.Position.Magnitude
	local toT = target - S
	local dist = toT.Magnitude
	if dist > 1e-3 and a > 1e-3 and b > 1e-3 then
		local n = toT / dist
		local d = math.clamp(dist - h, math.abs(a - b) + 0.01, a + b - 0.002)
		local cosA = math.clamp((a * a + d * d - b * b) / (2 * a * d), -1, 1)
		local sinA = math.sqrt(1 - cosA * cosA)
		local p = pole - n * pole:Dot(n)
		if p.Magnitude < 1e-3 then
			p = torso.UpVector:Cross(n)
		end
		p = p.Unit
		local E = S + n * (a * cosA) + p * (a * sinA)
		local Wp = S + n * d
		local hinge = p:Cross(n)
		local upperCF = CFrame.new(S) * frameFrom(restU, E - S, hinge) * CFrame.new(-sh.C1.Position)
		local lowerCF = CFrame.new(E) * frameFrom(restL, Wp - E, hinge) * CFrame.new(-el.C1.Position)
		local tS = sh.C0:Inverse() * torso:Inverse() * upperCF * sh.C1
		local tE = el.C0:Inverse() * upperCF:Inverse() * lowerCF * el.C1
		sh.Transform = sh.Transform:Lerp(tS, w)
		el.Transform = el.Transform:Lerp(tE, w)
	end
	wr.Transform = wr.Transform:Lerp(ID, w)
	local upperNow = torso * sh.C0 * sh.Transform * sh.C1:Inverse()
	local lowerNow = upperNow * el.C0 * el.Transform * el.C1:Inverse()
	return lowerNow * wr.C0 * wr.Transform * wr.C1:Inverse()
end

-- A gun-space move of a piece about its motor's pivot, as that motor's Transform.
local function gunSpace(m: Motor6D, delta: CFrame): CFrame
	local p = m.C0.Position
	return m.C0:Inverse() * CFrame.new(p) * delta * CFrame.new(-p) * m.C0
end

-- Transforms layered on top of what the Animator wrote this frame. If the Animator did not touch the joint this
-- frame (it still holds our last write), the base is the one we used last time, so nothing accumulates.
local function additive(rig: Rig, key: string, m: Joint, add: CFrame)
	local cur = m.Transform
	local base = if rig.last[key] ~= nil and cur == rig.last[key] then rig.base[key] else cur
	local out = base * add
	m.Transform = out
	rig.last[key] = out
	rig.base[key] = base
end

-- R6 (no elbow): swing the whole arm so its palm end points at `target`. Returns the arm's CFrame.
local function aimArm(torso: CFrame, sh: Joint, armLen: number, target: Vector3, w: number): CFrame
	local S = (torso * sh.C0).Position
	local tip = Vector3.new(0, -armLen / 2 + 0.25, 0)
	local rest = tip - sh.C1.Position
	local dir = target - S
	if dir.Magnitude > 1e-3 and rest.Magnitude > 1e-3 then
		local armCF = CFrame.new(S) * frameFrom(rest, dir, torso.RightVector) * CFrame.new(-sh.C1.Position)
		sh.Transform = sh.Transform:Lerp(sh.C0:Inverse() * torso:Inverse() * armCF * sh.C1, w)
	end
	return torso * sh.C0 * sh.Transform * sh.C1:Inverse()
end

local function deg(v: Vector3): CFrame
	return CFrame.Angles(math.rad(v.X), math.rad(v.Y), math.rad(v.Z))
end

------------------------------------------------------------------ rig discovery
-- Why a character can't be posed (warned once per character, so a silent idle has a reason in the output).
local warned: { [Model]: boolean } = {}
local function whyNot(char: Model, msg: string)
	if warned[char] or not char:FindFirstChild("HeldGun") then
		return
	end
	warned[char] = true
	local kinds = {}
	for _, d in char:GetDescendants() do
		if d:IsA("Motor6D") or d:IsA("AnimationConstraint") then
			table.insert(kinds, d.ClassName .. ":" .. d.Name)
		end
	end
	warn(string.format("[GunAnim] can't pose %s: %s (joints: %s)", char.Name, msg, table.concat(kinds, ", ")))
end

local function buildRig(char: Model): Rig?
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp or not hrp:IsA("BasePart") then
		return nil
	end
	local upper = char:FindFirstChild("UpperTorso")
	local lower = char:FindFirstChild("LowerTorso")
	local r6Torso = char:FindFirstChild("Torso")
	local r15 = upper ~= nil and lower ~= nil
	local rootJ, waist, rs, re, rw, ls, le, lw
	local armLen = 2
	if r15 then
		rootJ = joint(char, lower, "Root")
		waist = joint(char, upper, "Waist")
		rs = joint(char, char:FindFirstChild("RightUpperArm"), "RightShoulder")
		re = joint(char, char:FindFirstChild("RightLowerArm"), "RightElbow")
		rw = joint(char, char:FindFirstChild("RightHand"), "RightWrist")
		ls = joint(char, char:FindFirstChild("LeftUpperArm"), "LeftShoulder")
		le = joint(char, char:FindFirstChild("LeftLowerArm"), "LeftElbow")
		lw = joint(char, char:FindFirstChild("LeftHand"), "LeftWrist")
		if not (rootJ and waist and rs and re and rw and ls and le and lw) then
			whyNot(char, "missing an R15 joint")
			return nil
		end
	elseif r6Torso and r6Torso:IsA("BasePart") then
		upper = r6Torso
		rootJ = joint(char, hrp, "RootJoint")
		rs = joint(char, r6Torso, "Right Shoulder")
		ls = joint(char, r6Torso, "Left Shoulder")
		local arm = char:FindFirstChild("Right Arm")
		if arm and arm:IsA("BasePart") then
			armLen = arm.Size.Y
		end
		if not (rootJ and rs and ls) then
			whyNot(char, "missing an R6 joint")
			return nil
		end
	else
		whyNot(char, "no UpperTorso / Torso")
		return nil
	end
	return {
		char = char,
		hum = hum,
		hrp = hrp,
		upper = upper :: BasePart,
		r15 = r15,
		armLen = armLen,
		rootJ = rootJ :: Joint,
		waist = waist,
		neck = joint(char, if r15 then char:FindFirstChild("Head") else r6Torso, "Neck"),
		rs = rs,
		re = re,
		rw = rw,
		ls = ls,
		le = le,
		lw = lw,
		gun = nil,
		joint = nil,
		pieces = {},
		kind = "rifle",
		action = "auto",
		magKind = "stick",
		fireRate = 5,
		gripPos = Vector3.zero,
		buttPos = Vector3.zero,
		sightPos = Vector3.zero,
		magWell = Vector3.zero,
		fore = nil,
		magParts = {},
		weight = 0,
		ads = 0,
		pitch = 0,
		yaw = 0,
		reloadW = 0,
		kick = 0,
		kickV = 0,
		rise = 0,
		riseV = 0,
		yawKick = 0,
		yawKickV = 0,
		lastShot = -math.huge,
		cycleStart = -math.huge,
		cycleSec = 0.3,
		cycleEjected = true,
		leftPos = nil,
		shell = nil,
		reloadKey = 0,
		reloadEmpty = false,
		reloadEjected = true,
		touched = false,
		last = {},
		base = {},
	}
end

local function attPos(gun: BasePart, name: string, fallback: Vector3): Vector3
	local a = gun:FindFirstChild(name)
	return if a and a:IsA("Attachment") then a.Position else fallback
end

local function bindGun(rig: Rig, gun: BasePart?)
	rig.gun = gun
	rig.joint = nil
	rig.pieces = {}
	rig.magParts = {}
	rig.fore = nil
	if not gun then
		return
	end
	rig.joint = motor(gun, "GunJoint")
	rig.kind = tostring(gun:GetAttribute("GunKind") or "rifle")
	rig.action = tostring(gun:GetAttribute("GunAction") or "auto")
	rig.magKind = tostring(gun:GetAttribute("GunMag") or "stick")
	local w = Weapons.ById[tostring(gun:GetAttribute("WeaponId") or "")]
	rig.fireRate = if w then w.fireRate else 5
	rig.gripPos = attPos(gun, "Grip", Vector3.zero)
	rig.buttPos = attPos(gun, "Butt", Vector3.new(0, 0, 1))
	rig.magWell = attPos(gun, "MagWell", Vector3.new(0, -0.3, 0))
	local sightY = tonumber(gun:GetAttribute("SightY")) or 0.3
	rig.sightPos = Vector3.new(0, sightY, rig.buttPos.Z)
	for _, d in gun:GetDescendants() do
		if d:IsA("Motor6D") and d.Name ~= "GunJoint" then
			rig.pieces[d.Name] = d
		elseif d:IsA("Attachment") and d.Name == "Foregrip" then
			rig.fore = d
		end
	end
	local mag = rig.pieces.MagJoint
	if mag and mag.Part1 then
		local mp = mag.Part1
		rig.magParts[mp] = mp.Transparency
		for _, d in mp:GetDescendants() do
			if d:IsA("BasePart") then
				rig.magParts[d] = d.Transparency
			end
		end
	end
end

local function setMagFade(rig: Rig, f: number)
	for p, base in rig.magParts do
		p.Transparency = base + (1 - base) * f
	end
end

------------------------------------------------------------------ effects
local function muzzleFlash(rig: Rig)
	local gun = rig.gun
	local att = gun and gun:FindFirstChild("Muzzle")
	if not Config.GunMuzzleFlash or not att or not att:IsA("Attachment") then
		return
	end
	local cf = att.WorldCFrame
	local big = if rig.kind == "shotgun" or rig.kind == "sniper" then 1.6 elseif rig.kind == "pistol" then 0.8 else 1
	local color = Color3.fromHex(Config.GunMuzzleFlashColor)
	local holder = Instance.new("Part")
	holder.Name = "MuzzleFlash"
	holder.Shape = Enum.PartType.Ball
	holder.Size = Vector3.one * 0.35 * big
	holder.CFrame = cf * CFrame.new(0, 0, -0.12 * big)
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.CastShadow = false
	holder.Material = Enum.Material.Neon
	holder.Color = color
	holder.Transparency = 0.15
	local roll = math.random() * math.pi
	local template = holder:Clone()
	for i = 0, 1 do
		local petal = template:Clone()
		petal.Shape = Enum.PartType.Block
		petal.Size = Vector3.new(0.06 * big, 0.5 * big, 0.06 * big)
		petal.CFrame = cf * CFrame.new(0, 0, -0.18 * big) * CFrame.Angles(0, 0, roll + i * math.pi / 2)
		petal.Parent = holder
	end
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 10
	light.Brightness = 3
	light.Shadows = false
	light.Parent = holder
	holder.Parent = effects
	task.delay(Config.GunMuzzleFlashSec, function()
		holder:Destroy()
	end)
end

local function casing(rig: Rig)
	local gun = rig.gun
	local att = gun and gun:FindFirstChild("Eject")
	if not Config.GunShellCasings or not gun or not att or not att:IsA("Attachment") then
		return
	end
	local shotgun = rig.kind == "shotgun"
	local cf = att.WorldCFrame
	local p = Instance.new("Part")
	p.Name = "Casing"
	p.Shape = Enum.PartType.Cylinder
	p.Size = if shotgun then Vector3.new(0.24, 0.12, 0.12) else Vector3.new(0.14, 0.06, 0.06)
	p.Color = if shotgun then Color3.fromHex("B3261E") else Color3.fromHex("C9A043")
	p.Material = if shotgun then Enum.Material.SmoothPlastic else Enum.Material.Metal
	p.CFrame = cf
	p.CanCollide = true
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.AssemblyLinearVelocity = cf.LookVector * (6 + math.random() * 3)
		+ Vector3.yAxis * (4 + math.random() * 3)
		+ gun.CFrame.LookVector * -1.5
	p.AssemblyAngularVelocity = Vector3.new(math.random() * 20 - 10, math.random() * 20 - 10, math.random() * 20 - 10)
	p.Parent = effects
	task.delay(Config.GunCasingLifeSec, function()
		p:Destroy()
	end)
end

local function onShot(rig: Rig)
	local now = os.clock()
	local recoils = Config.GunRecoil :: any
	local r = recoils[rig.kind] or recoils.rifle
	local mult = 1 - (1 - Config.GunAdsRecoilMult) * rig.ads
	local cap = Config.GunRecoilMaxStack
	rig.kick = math.min(rig.kick + r.kick * mult, r.kick * cap)
	rig.rise = math.min(rig.rise + r.rise * mult, r.rise * cap)
	rig.yawKick += (math.random() * 2 - 1) * r.rise * 0.3 * mult
	rig.lastShot = now
	muzzleFlash(rig)
	if rig.action == "pump" or rig.action == "bolt" or rig.action == "lever" then
		rig.cycleStart = now + Config.GunCycleDelay
		rig.cycleSec = math.min(Config.GunCycleSec, 0.75 / math.max(rig.fireRate, 0.1))
		rig.cycleEjected = false
	elseif rig.action ~= "break" then
		casing(rig)
	end
end

------------------------------------------------------------------ reload state
type Reload = { t: number, shell: boolean, key: number }

-- This rig's reload progress: t in [0, 1] through the reload (or the current shell), nil when not reloading.
local function reloadState(rig: Rig, isLocal: boolean): Reload?
	if isLocal then
		local a = ClientState.ammo
		if not a or not a.reloading then
			return nil
		end
		local len = math.max(a.reloadEndsAt - a.reloadStartedAt, 0.05)
		return {
			t = math.clamp((os.clock() - a.reloadStartedAt) / len, 0, 1),
			shell = a.shell == true,
			key = a.reloadStartedAt,
		}
	end
	local at = rig.char:GetAttribute("GunReloadAt")
	local sec = tonumber(rig.char:GetAttribute("GunReloadSec")) or 1
	if typeof(at) ~= "number" then
		return nil
	end
	local t = (Workspace:GetServerTimeNow() - at) / math.max(sec, 0.05)
	if t > 1 then
		return nil
	end
	return { t = math.clamp(t, 0, 1), shell = rig.char:GetAttribute("GunReloadShell") == true, key = at }
end

------------------------------------------------------------------ the pose
local function spring(x: number, v: number, dt: number): (number, number)
	local k = Config.GunRecoilSpring
	local c = 2 * math.sqrt(k)
	local steps = math.max(1, math.ceil(dt / (1 / 240)))
	local h = dt / steps
	for _ = 1, steps do
		v += (-k * x - c * v) * h
		x += v * h
	end
	return x, v
end

local function releaseRig(rig: Rig)
	if not rig.touched then
		return
	end
	rig.touched = false
	if rig.joint then
		rig.joint.Transform = ID
	end
	for _, m in rig.pieces do
		m.Transform = ID
	end
	setMagFade(rig, 0)
	for key, m in { waist = rig.waist, neck = rig.neck } :: { [string]: Joint? } do
		if m and rig.last[key] ~= nil and m.Transform == rig.last[key] then
			m.Transform = rig.base[key]
		end
	end
	rig.last = {}
	rig.base = {}
	if rig.rw then
		rig.rw.Transform = ID
	end
	if rig.lw then
		rig.lw.Transform = ID
	end
	if rig.shell then
		rig.shell:Destroy()
		rig.shell = nil
	end
	rig.leftPos = nil
end

-- The class idles (the hub's stand-in idles) play at Action priority but loop under everything: never a reason to
-- hand the arms back.
local idleIds: { [string]: boolean } = {}
for _, id in Config.ClassIdleAnimationId do
	idleIds[id] = true
end

local function actionTrackPlaying(rig: Rig): boolean
	local animator = rig.hum:FindFirstChildOfClass("Animator")
	if not animator then
		return false
	end
	for _, track in animator:GetPlayingAnimationTracks() do
		local p = track.Priority
		if
			(
				p == Enum.AnimationPriority.Action
				or p == Enum.AnimationPriority.Action2
				or p == Enum.AnimationPriority.Action3
				or p == Enum.AnimationPriority.Action4
			)
			and track.WeightCurrent > 0.05
			and not (track.Animation and idleIds[track.Animation.AnimationId])
		then
			return true
		end
	end
	return false
end

local function shellPart(rig: Rig): BasePart
	if rig.shell and rig.shell.Parent then
		return rig.shell
	end
	local p = Instance.new("Part")
	p.Name = "ReloadShell"
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(0.26, 0.13, 0.13)
	p.Color = Color3.fromHex("B3261E")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = effects
	rig.shell = p
	return p
end

local function step(rig: Rig, dt: number, isLocal: boolean)
	local char = rig.char
	local gun = char:FindFirstChild("HeldGun")
	if gun ~= rig.gun then
		releaseRig(rig)
		bindGun(rig, if gun and gun:IsA("BasePart") then gun else nil)
	end
	local joint = rig.joint
	local want = Config.GunAnimEnabled
		and rig.gun ~= nil
		and joint ~= nil
		and not ClientState.inHub()
		and rig.hum.Health > 0
		and not actionTrackPlaying(rig)
	rig.weight = approach(rig.weight, if want then 1 else 0, Config.GunPoseBlendSec, dt)
	if rig.weight <= 0 or not joint or not rig.gun then
		releaseRig(rig)
		return
	end
	local g = rig.gun :: BasePart
	rig.touched = true
	local w = smooth(0, 1, rig.weight)
	local now = os.clock()
	local s = rig.upper.Size.X / 2 -- avatar scale (blocky R15 = 1)

	-- Aim: pitch / yaw toward the aim point (local), or the shooter's replicated pitch.
	local ads = if isLocal then ClientState.ads else char:GetAttribute("GunAds") == true
	rig.ads = approach(rig.ads, if ads then 1 else 0, Config.GunAdsBlendSec, dt)
	local pitchT, yawT = 0, 0
	local flat = CFrame.lookAlong(rig.hrp.Position, rig.hrp.CFrame.LookVector * Vector3.new(1, 0, 1))
	local chestGuess = rig.hrp.Position + Vector3.new(0, 1.5 * s, 0)
	if isLocal then
		local aim = ClientState.cursorAimPoint(char)
		local d = aim - chestGuess
		if d.Magnitude > 1 then
			local l = flat:VectorToObjectSpace(d.Unit)
			pitchT = math.deg(math.asin(math.clamp(l.Y, -1, 1)))
			yawT = math.deg(math.atan2(-l.X, -l.Z))
		end
	else
		pitchT = tonumber(char:GetAttribute("GunPitch")) or 0
	end
	pitchT = math.clamp(pitchT, -Config.GunAimPitchMax, Config.GunAimPitchMax)
	yawT = math.clamp(yawT, -Config.GunAimYawMax, Config.GunAimYawMax)
	local a = 1 - math.exp(-dt * 18)
	rig.pitch += (pitchT - rig.pitch) * a
	rig.yaw += (yawT - rig.yaw) * a

	-- Recoil springs.
	rig.kick, rig.kickV = spring(rig.kick, rig.kickV, dt)
	rig.rise, rig.riseV = spring(rig.rise, rig.riseV, dt)
	rig.yawKick, rig.yawKickV = spring(rig.yawKick, rig.yawKickV, dt)

	-- Reload.
	local rl = reloadState(rig, isLocal)
	if rl and rl.key ~= rig.reloadKey then
		rig.reloadKey = rl.key
		rig.reloadEjected = false
		if isLocal and not rl.shell then
			local am = ClientState.ammo
			rig.reloadEmpty = am ~= nil and am.mag <= 0
		elseif not rl.shell then
			rig.reloadEmpty = false
		end
	end
	local magReload = rl ~= nil and not rl.shell
	rig.reloadW = approach(rig.reloadW, if rl then 1 else 0, 0.15, dt)
	local tilt = rig.reloadW
	if rl and magReload then
		tilt = smooth(0, 0.12, rl.t) * (1 - smooth(0.86, 1, rl.t))
	end

	-- Stance twist + upper-body lean (additive over the walk / idle).
	local poses = Config.GunPoses :: any
	local pose = poses[rig.kind] or poses.rifle
	local blade = math.rad(pose.blade) * w
	local lean = math.rad(rig.pitch * Config.GunTorsoAimShare) * w
	local waist = rig.waist
	if waist then
		additive(rig, "waist", waist, CFrame.Angles(lean, -blade, 0))
		if rig.neck then
			additive(rig, "neck", rig.neck, CFrame.Angles(math.rad(rig.pitch) * 0.4 * w, blade, 0))
		end
	end
	local lowerCF = rig.hrp.CFrame * rig.rootJ.C0 * rig.rootJ.Transform * rig.rootJ.C1:Inverse()
	local torso = if waist then lowerCF * waist.C0 * waist.Transform * waist.C1:Inverse() else lowerCF

	-- Aim space: the middle of the shoulders, facing the aim.
	local chest = torso * Vector3.new(0, rig.rs.C0.Position.Y, 0)
	local A = CFrame.new(chest)
		* flat.Rotation
		* CFrame.Angles(0, math.rad(rig.yaw), 0)
		* CFrame.Angles(math.rad(rig.pitch), 0, 0)

	-- Where the gun goes: hip <-> aimed, then the reload tilt, then recoil about the grip.
	local anchors = { butt = rig.buttPos, grip = rig.gripPos, sight = rig.sightPos }
	local function stance(p: any): CFrame
		local anchor = anchors[p.anchor] or rig.gripPos
		return CFrame.new(p.pos * s) * deg(p.rot) * CFrame.new(-anchor)
	end
	local adsT = smooth(0, 1, rig.ads) * (1 - tilt)
	local off = stance(pose.hip):Lerp(stance(pose.ads), adsT)
	if tilt > 0 then
		local gp = rig.gripPos
		off = CFrame.new(Config.GunReloadPull * s * tilt)
			* off
			* CFrame.new(gp)
			* deg(Config.GunReloadTilt * tilt)
			* CFrame.new(-gp)
	end
	do
		local gp = rig.gripPos
		off = off
			* CFrame.new(gp)
			* CFrame.Angles(math.rad(rig.rise), math.rad(rig.yawKick), 0)
			* CFrame.new(-gp)
			* CFrame.new(0, 0, rig.kick)
	end
	local G = A * off

	-- Moving pieces.
	local P = rig.pieces
	local t = rl and rl.t or 0
	local seat = Config.ReloadSeatShare
	if P.SlideJoint then
		local since = now - rig.lastShot
		local back = if since < 0.03 then since / 0.03 else math.max(0, 1 - (since - 0.03) / 0.07)
		if isLocal then
			local am = ClientState.ammo
			local empty = am ~= nil and am.mag <= 0
			if empty and not (magReload and t >= seat + 0.05) then
				back = 1
			end
		end
		P.SlideJoint.Transform = gunSpace(P.SlideJoint, CFrame.new(0, 0, Config.GunSlideTravel * back))
	end
	local c = (now - rig.cycleStart) / rig.cycleSec
	local cycling = c >= 0 and c <= 1
	if cycling and c >= 0.5 and not rig.cycleEjected then
		rig.cycleEjected = true
		casing(rig)
	end
	if P.PumpJoint then
		local z = if cycling then math.sin(math.pi * c) * 0.32 else 0
		if rl and rl.shell == false then
			z = 0
		end
		P.PumpJoint.Transform = gunSpace(P.PumpJoint, CFrame.new(0, 0, z))
	end
	if P.BoltJoint then
		local up, back = 0, 0
		if cycling then
			up = smooth(0, 0.25, c) * (1 - smooth(0.75, 1, c))
			back = smooth(0.25, 0.5, c) * (1 - smooth(0.5, 0.75, c))
		elseif magReload or (rl and rig.magKind == "none") then
			up = smooth(0, 0.1, t) * (1 - smooth(0.85, 0.95, t))
			back = smooth(0.08, 0.18, t) * (1 - smooth(0.78, 0.88, t))
		end
		P.BoltJoint.Transform =
			gunSpace(P.BoltJoint, CFrame.new(0, 0, back * 0.35) * CFrame.Angles(0, 0, up * math.rad(70)))
	end
	if P.LeverJoint then
		local ang = if cycling then math.sin(math.pi * c) * math.rad(50) else 0
		P.LeverJoint.Transform = gunSpace(P.LeverJoint, CFrame.Angles(ang, 0, 0))
	end
	if P.BarrelsJoint then
		local open = if magReload then smooth(0, 0.18, t) * (1 - smooth(0.78, 0.92, t)) else 0
		if magReload and t > 0.12 and not rig.reloadEjected then
			rig.reloadEjected = true
			casing(rig)
			casing(rig)
		end
		P.BarrelsJoint.Transform = gunSpace(P.BarrelsJoint, CFrame.Angles(-open * math.rad(38), 0, 0))
	end
	local chargePull = 0
	if P.ChargeJoint then
		if magReload and rig.reloadEmpty then
			chargePull = smooth(0.82, 0.87, t) * (1 - smooth(0.88, 0.93, t))
		end
		P.ChargeJoint.Transform = gunSpace(P.ChargeJoint, CFrame.new(0, 0, chargePull * 0.3))
	end

	-- Right arm onto the grip; the gun follows the hand exactly (blended by the pose weight).
	local torsoRot = torso.Rotation
	local gripW = (G * CFrame.new(rig.gripPos)).Position
	local rHand = if rig.re and rig.rw
		then solveArm(torso, rig.rs, rig.re, rig.rw, gripW, torsoRot * Vector3.new(0.7, -1, 0.5), w)
		else aimArm(torso, rig.rs, rig.armLen, gripW, w)
	local rest = rHand * joint.C0
	local gunCF = rest:Lerp(G, w)
	joint.Transform = joint.C0:Inverse() * rHand:Inverse() * gunCF

	-- Left hand: the foregrip, or the reload path (mag well -> belt pouch -> mag well).
	local function pieceWorld(m: Motor6D): CFrame
		return gunCF * m.C0 * m.Transform * m.C1:Inverse()
	end
	local foreWorld: Vector3
	local fa = rig.fore
	if fa then
		local parent = fa.Parent
		local pm = if parent and parent ~= g then parent:FindFirstChildOfClass("Motor6D") else nil
		local pcf = if pm then pieceWorld(pm) else gunCF
		foreWorld = (pcf * fa.CFrame).Position
	else
		foreWorld = (gunCF * CFrame.new(rig.gripPos + Vector3.new(-0.2, 0, -0.5))).Position
	end
	local up = if rig.magKind == "top" then 1 else -1
	local grab = rig.magWell + Vector3.new(0, up * (if rig.magKind == "pistol" then 0.08 else 0.25), 0)
	local grabW = (gunCF * CFrame.new(grab)).Position
	local belowW = (gunCF * CFrame.new(rig.magWell + Vector3.new(0, up * 0.6, 0))).Position
	local pouchW = (torso * CFrame.new(Config.GunPouchOffset * s)).Position
	local leftT = foreWorld
	local magFade, magDrop, magInHand = 0, 0, false
	local shellVisible = false
	if rl and rl.shell then
		-- Shell by shell: pouch -> loading port -> push, every reloadTime.
		local portW = (gunCF * CFrame.new(rig.magWell + Vector3.new(0, -0.12, 0))).Position
		if rl.t < 0.45 then
			leftT = portW:Lerp(pouchW, smooth(0, 0.45, rl.t))
		elseif rl.t < 0.85 then
			leftT = pouchW:Lerp(portW, smooth(0.45, 0.85, rl.t))
			shellVisible = true
		else
			leftT = portW
			shellVisible = rl.t < 0.92
		end
	elseif rl and (rig.magKind == "none" or rig.magKind == "tube") and rig.action ~= "break" then
		-- Stripper clip / top loading: hand to the top, the belt, press in.
		if t < 0.15 then
			leftT = foreWorld:Lerp(grabW, smooth(0, 0.15, t))
		elseif t < 0.4 then
			leftT = grabW:Lerp(pouchW, smooth(0.15, 0.4, t))
		elseif t < seat then
			leftT = pouchW:Lerp(grabW, smooth(0.4, seat, t))
		elseif t < seat + 0.1 then
			leftT = grabW
		else
			leftT = grabW:Lerp(foreWorld, smooth(seat + 0.1, 0.95, t))
		end
	elseif rl and rig.action == "break" then
		local breechW = (gunCF * CFrame.new(rig.magWell)).Position
		if t < 0.2 then
			leftT = foreWorld
		elseif t < 0.45 then
			leftT = foreWorld:Lerp(pouchW, smooth(0.2, 0.45, t))
		elseif t < 0.7 then
			leftT = pouchW:Lerp(breechW, smooth(0.45, 0.7, t))
			shellVisible = true
		else
			leftT = breechW:Lerp(foreWorld, smooth(0.72, 0.95, t))
		end
	elseif rl then
		-- Magazine: grab, drop it, fetch a fresh one from the belt, seat it, back to the handguard.
		if t < 0.15 then
			leftT = foreWorld:Lerp(grabW, smooth(0, 0.15, t))
		elseif t < 0.42 then
			leftT = grabW:Lerp(pouchW, smooth(0.15, 0.42, t))
			local d = (t - 0.15) / 0.27
			magDrop = d
			magFade = smooth(0.45, 1, d)
		elseif t < seat - 0.1 then
			leftT = pouchW:Lerp(belowW, smooth(0.42, seat - 0.1, t))
			magInHand = true
		elseif t < seat then
			leftT = belowW:Lerp(grabW, smooth(seat - 0.1, seat, t))
			magInHand = true
		elseif t < seat + 0.08 then
			leftT = grabW
		elseif chargePull > 0 or (rig.reloadEmpty and P.ChargeJoint and t < 0.93) then
			local ch = P.ChargeJoint
			local chW = if ch then pieceWorld(ch).Position else foreWorld
			leftT = grabW:Lerp(chW, smooth(seat + 0.08, 0.82, t))
		else
			leftT = grabW:Lerp(foreWorld, smooth(seat + 0.08, 0.96, t))
		end
	end
	-- Ease the left hand along so phase changes (a cancelled shell reload, a swap) never teleport it.
	local lp = rig.leftPos
	if lp == nil then
		lp = leftT
	else
		lp = lp:Lerp(leftT, 1 - math.exp(-dt * 30))
	end
	rig.leftPos = lp
	local lHand = if rig.le and rig.lw
		then solveArm(torso, rig.ls, rig.le, rig.lw, lp :: Vector3, torsoRot * Vector3.new(-0.5, -1, 0.15), w)
		else aimArm(torso, rig.ls, rig.armLen, lp :: Vector3, w)

	-- The magazine: seated, falling away, or riding in the left hand until it seats.
	local mj = P.MagJoint
	if mj then
		if magInHand then
			local handLocal = gunCF:PointToObjectSpace(lHand.Position)
			mj.Transform = gunSpace(mj, CFrame.new(handLocal - grab))
		elseif magDrop > 0 then
			mj.Transform = gunSpace(mj, CFrame.new(0, up * 1.6 * magDrop * magDrop, 0.1 * magDrop))
		else
			mj.Transform = ID
		end
		setMagFade(rig, magFade)
	end

	-- A shell in the left hand while it travels to the port.
	if shellVisible and rig.weight > 0.5 then
		local sp = shellPart(rig)
		sp.CFrame = lHand * CFrame.new(0, -0.15, 0) * CFrame.Angles(0, math.rad(90), 0)
		local head = char:FindFirstChild("Head")
		sp.LocalTransparencyModifier = if head and head:IsA("BasePart") then head.LocalTransparencyModifier else 0
	elseif rig.shell then
		rig.shell:Destroy()
		rig.shell = nil
	end
end

------------------------------------------------------------------ local pose broadcast
local sentAt = 0
local sentPitch = 0
local sentAds = false
local sentReloadKey: number? = nil

local function broadcast(rig: Rig?)
	local now = os.clock()
	local a = ClientState.ammo
	local reloadKey = if a and a.reloading then a.reloadStartedAt else nil
	local pose: { [string]: any } = {}
	local dirty = false
	if reloadKey ~= sentReloadKey then
		sentReloadKey = reloadKey
		pose.reload = if reloadKey and a then math.max(a.reloadEndsAt - a.reloadStartedAt, 0.05) else 0
		pose.shell = a ~= nil and a.shell == true
		dirty = true
	end
	local pitch = if rig then math.round(rig.pitch) else 0
	if ClientState.ads ~= sentAds then
		dirty = true
	end
	if now - sentAt >= 1 / Config.GunPoseSendHz and math.abs(pitch - sentPitch) >= 2 then
		dirty = true
	end
	if not dirty then
		return
	end
	sentAt = now
	sentPitch = pitch
	sentAds = ClientState.ads
	pose.pitch = pitch
	pose.ads = ClientState.ads
	Remotes.GunPose:FireServer(pose)
end

------------------------------------------------------------------ wiring
RunService.PreSimulation:Connect(function(dt: number)
	dt = math.min(dt, 1 / 20)
	local seen: { [Model]: boolean } = {}
	for _, p in Players:GetPlayers() do
		local char = p.Character
		if char and char.Parent then
			seen[char] = true
			local rig = rigs[char]
			if not rig or not rig.hrp.Parent or not rig.rs.Parent then
				rig = buildRig(char)
				if rig then
					rigs[char] = rig
				else
					rigs[char] = nil
				end
			end
			if rig then
				local ok, err = pcall(step, rig, dt, p == player)
				if not ok then
					warn("[GunAnim] " .. tostring(err))
					releaseRig(rig)
				end
				if p == player and not ClientState.inHub() then
					broadcast(rig)
				end
			end
		end
	end
	for char, rig in rigs do
		if not seen[char] then
			if rig.shell then
				rig.shell:Destroy()
			end
			rigs[char] = nil
		end
	end
end)

ClientState.Juice:Connect(function(name: string, data: any)
	if name == "LocalFire" then
		local char = player.Character
		local rig = char and rigs[char]
		if rig and rig.weight > 0 then
			onShot(rig)
		end
	elseif name == "RemoteShot" and typeof(data) == "table" then
		local p = Players:GetPlayerByUserId(tonumber(data.userId) or 0)
		if p and p ~= player and p.Character then
			local rig = rigs[p.Character]
			if rig and rig.weight > 0 then
				onShot(rig)
			end
		end
	end
end)
