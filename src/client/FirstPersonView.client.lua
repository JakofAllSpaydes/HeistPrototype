--!strict
-- Round 24c: the first-person viewmodel. In first person the real character is hidden (its arms sat right in
-- front of the lens: big dark blocks over half the screen), and this script draws a local copy of the held gun
-- plus two forearms locked to the camera. Hip fire holds the gun low right; ADS brings the sight line onto the
-- crosshair (optics fade so you look through them). Motion is smooth by design: a slight lag behind camera turns,
-- a small walk bob, a short recoil kick. Every number is a Config.FirstPerson* tunable.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local GunModels = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GunModels"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))

local player = Players.LocalPlayer

local OPTICS = {
	Scope = true,
	ScopeBell = true,
	ScopeEye = true,
	ScopeLens = true,
	ScopeMountF = true,
	ScopeMountR = true,
	Turret = true,
	RedDot = true,
	Lens = true,
	SightBase = true,
	RedDotRing = true,
	HoloBody = true,
	HoloHood = true,
	HoloButtons = true,
	HoloGlass = true,
}

local source: BasePart? = nil -- the real HeldGun this copy was made from
local gun: BasePart? = nil -- the copy
local holder: Model? = nil -- wraps the copy so Model:ScaleTo shrinks parts and attachments together
local parts: { BasePart } = {}
local optics: { BasePart } = {}
local blockers: { BasePart } = {} -- Round 24aa: parts behind the sight that rise into the sight line (fade in ADS)
local gripPos = Vector3.zero
local sightPos = Vector3.zero
local relief = 0.3 -- ADS: the sight's rear this far ahead of the eye (per gun kind)
local foreAtt: Attachment? = nil
local magParts: { BasePart } = {} -- Round 24h: the magazine (and its segments), animated on reload
local wellAtt: Attachment? = nil
local muzzleAtt: Attachment? = nil
local reloadW = 0 -- 0 = no reload pose, 1 = full
local drawAt = -math.huge
local wasScoped = false
local armR: Part? = nil
local armL: Part? = nil

local adsT = 0
local swayX, swayY = 0, 0 -- lag behind camera turns (radians)
local kick = 0 -- studs the viewmodel is pushed back (Round 24n: per gun kind)
local rise = 0 -- radians the muzzle flips up
local bobPhase = 0
local bobAmp = 0
local lastLook: Vector3? = nil

local function smooth(e0: number, e1: number, x: number): number
	local t = math.clamp((x - e0) / (e1 - e0), 0, 1)
	return t * t * (3 - 2 * t)
end

local builtCount = 0 -- descendants of the real gun when the copy was made (a gun still being assembled rebuilds)
local heldSeen: BasePart? = nil
local heldSeenAt = 0

local function clearGun()
	if holder then
		holder:Destroy()
	end
	if gun then
		gun:Destroy()
	end
	holder = nil
	gun, source, foreAtt = nil, nil, nil
	parts, optics, magParts, blockers = {}, {}, {}, {}
	wellAtt = nil
	muzzleAtt = nil
	ClientState.viewMuzzleAtt = nil
	ClientState.fpAdsT = 0
	wasScoped = false
end

local function clearArms()
	for _, a in { armR, armL } do
		if a then
			a:Destroy()
		end
	end
	armR, armL = nil, nil
end

local function clear()
	clearGun()
	clearArms()
	lastLook = nil
end

local function armColor(char: Model): Color3
	local p = char:FindFirstChild("RightLowerArm") or char:FindFirstChild("Right Arm")
	if p and p:IsA("BasePart") then
		return p.Color
	end
	return Color3.fromHex("C9A27E")
end

local function newArm(color: Color3): Part
	local p = Instance.new("Part")
	p.Name = "FPArm"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Color = color
	p.Size = Vector3.new(Config.FirstPersonArmWidth, Config.FirstPersonArmWidth, 1)
	p.Parent = Workspace.CurrentCamera
	return p
end

local function build(char: Model, held: BasePart)
	clearGun()
	builtCount = #held:GetDescendants()
	-- Round 24k: a fresh model from the weapon id (cloning the server's gun failed after a range swap: no gun,
	-- arms left frozen in the world), painted part by part like the real one (rarity, wrap). Clone is the fallback.
	local copy: BasePart? = nil
	local weaponId = held:GetAttribute("WeaponId")
	if typeof(weaponId) == "string" then
		local ok, built = pcall(GunModels.build, weaponId, { anchored = true })
		if ok and built then
			copy = built
			local src = GunModels.parts(held)
			for i, part in GunModels.parts(built) do
				local from = src[i]
				if from and from.Name == part.Name then
					part.Color = from.Color
					part.Material = from.Material
				end
			end
		end
	end
	if not copy then
		copy = held:Clone()
	end
	if not copy then
		error("no copy of " .. held:GetFullName())
	end
	for _, d in copy:GetDescendants() do
		if d:IsA("JointInstance") and d.Name == "GunJoint" then
			d:Destroy()
		elseif d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("Beam") or d:IsA("Trail") then
			d:Destroy() -- Round 24g: no effects on the viewmodel
		end
	end
	copy.Name = "FPGun"
	for _, p in GunModels.parts(copy) do
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.LocalTransparencyModifier = 0
		table.insert(parts, p)
		if OPTICS[p.Name] then
			table.insert(optics, p)
		end
	end
	-- Round 24e: the viewmodel is drawn at FirstPersonGunScale (at full size a stud from the eye it filled half
	-- the screen). Attributes are in unscaled gun space, so they scale by hand.
	local k = Config.FirstPersonGunScale
	local m = Instance.new("Model")
	m.Name = "FPViewmodel"
	copy.Parent = m
	m.PrimaryPart = copy
	m.Parent = Workspace.CurrentCamera
	if k ~= 1 then
		m:ScaleTo(k)
	end
	holder = m
	local grip = copy:FindFirstChild("Grip") :: Attachment?
	gripPos = if grip then grip.CFrame.Position else Vector3.zero
	local sightY = (tonumber(copy:GetAttribute("SightY")) or 0.3) * k
	local sightZ = (tonumber(copy:GetAttribute("SightZ")) or tonumber(copy:GetAttribute("ButtZ")) or 0.5) * k
	sightPos = Vector3.new(0, sightY, sightZ)
	-- Round 24aa: anything behind the rear sight (toward the eye) whose top comes within a hair of the sight line
	-- would sit right in front of the lens when aimed: it fades out with the aim-in.
	local rootCf = copy.CFrame
	for _, part in parts do
		if part ~= copy and not OPTICS[part.Name] and copy:GetAttribute("Sight") ~= "bare" then
			local l = rootCf:ToObjectSpace(part.CFrame)
			local sz = part.Size / 2
			local function extent(axis: Vector3): number
				return math.abs(l.XVector:Dot(axis)) * sz.X
					+ math.abs(l.YVector:Dot(axis)) * sz.Y
					+ math.abs(l.ZVector:Dot(axis)) * sz.Z
			end
			local rearEnd = l.Position.Z + extent(Vector3.zAxis)
			local topY = l.Position.Y + extent(Vector3.yAxis)
			if rearEnd > sightZ + 0.02 * k and topY > sightY - 0.05 * k then
				table.insert(blockers, part)
			end
		end
	end
	local reliefs = Config.FirstPersonAdsRelief :: any
	relief = reliefs[tostring(copy:GetAttribute("GunKind"))] or reliefs.default or 0.3
	foreAtt = copy:FindFirstChild("Foregrip", true) :: Attachment?
	wellAtt = copy:FindFirstChild("MagWell") :: Attachment?
	muzzleAtt = copy:FindFirstChild("Muzzle") :: Attachment?
	local magJoint = copy:FindFirstChild("MagJoint", true)
	local mag = if magJoint and magJoint:IsA("Motor6D") then magJoint.Part1 else nil
	if mag then
		table.insert(magParts, mag)
		for _, d in mag:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(magParts, d)
			end
		end
	end
	gun, source = copy, held
	drawAt = os.clock() -- Round 24aa: every new gun (a swap, a pickup) is drawn up into view
end

local function ensureArms(char: Model)
	if armR and armR.Parent and armL and armL.Parent then
		return
	end
	clearArms()
	local color = armColor(char)
	armR = newArm(color)
	armL = newArm(color)
end

-- A forearm block from `hand` back toward `elbow` (both world points).
local function placeArm(arm: Part?, hand: Vector3, elbow: Vector3)
	if not arm then
		return
	end
	local d = elbow - hand
	local len = math.max(d.Magnitude, 0.1)
	arm.Size = Vector3.new(arm.Size.X, arm.Size.Y, len)
	arm.CFrame = CFrame.lookAt(hand + d / 2, elbow)
end

local function recoilOf(): any
	local table_ = Config.FirstPersonRecoil :: any
	local kind = gun and gun:GetAttribute("GunKind")
	return table_[tostring(kind)] or table_.rifle
end

ClientState.Juice:Connect(function(name: string)
	if name == "LocalFire" then
		local r = recoilOf()
		local m = if ClientState.ads then Config.FirstPersonRecoilAdsMult else 1
		kick = math.min(kick + r.kick * m, r.kick * 2)
		rise = math.min(rise + math.rad(r.rise) * m, math.rad(r.rise) * 2)
	end
end)

RunService:BindToRenderStep("GHSFirstPersonView", Enum.RenderPriority.Camera.Value + 1, function(dt)
	local char = player.Character
	local held = char and char:FindFirstChild("HeldGun") :: BasePart?
	local want = ClientState.firstPerson == true
		and ClientState.cameraMode == "gameplay"
		and not ClientState.downed
		and char ~= nil
	if not want or not char then
		if gun or armR then
			clear()
		end
		return
	end
	local cam = (Workspace.CurrentCamera :: Camera).CFrame
	ensureArms(char)
	local hum = char:FindFirstChildOfClass("Humanoid")
	local moving = hum ~= nil and hum.MoveDirection.Magnitude > 0.1 and hum.FloorMaterial ~= Enum.Material.Air

	-- Round 24j: the hub (outside the range) is empty-handed: no gun, just the arms swinging as you run.
	if ClientState.combatOff() or not held or ClientState.sprinting then -- Round 24aa: sprinting = empty hands, pumping
		if gun then
			clearGun()
		end
		local speed = if hum then math.clamp(hum.WalkSpeed / 16, 0.5, 2) else 1
		bobAmp += ((if moving then 1 else 0) - bobAmp) * (1 - math.exp(-dt * 6))
		bobPhase += dt * Config.FirstPersonRunSwingSpeed * speed
		local sw = math.sin(bobPhase) * Config.FirstPersonRunSwing * bobAmp
		local function handAt(side: number, phase: number): Vector3
			-- Hands low at the bottom corners; running pumps them forward and up in turn.
			local fwd = phase * 0.25
			local up = math.max(phase, -0.3) * 0.18
			return Vector3.new(side * 0.42, -0.72 + up + bobAmp * 0.08, -0.75 - fwd - bobAmp * 0.1)
		end
		placeArm(armR, cam:PointToWorldSpace(handAt(1, sw)), cam:PointToWorldSpace(Vector3.new(0.6, -1.25, -0.2)))
		placeArm(armL, cam:PointToWorldSpace(handAt(-1, -sw)), cam:PointToWorldSpace(Vector3.new(-0.6, -1.25, -0.2)))
		for _, a in { armR, armL } do
			if a then
				-- Standing still the hands sink out of view; running brings them up.
				a.Transparency = if bobAmp < 0.05 then 1 else 0
			end
		end
		return
	end

	-- A new gun (range in / out, a swap) builds once it has settled: a copy made while the server was still
	-- assembling it came out broken.
	if held ~= heldSeen then
		heldSeen = held
		heldSeenAt = os.clock()
	end
	local stale = source ~= held or not gun or not gun.Parent or not holder or not holder.Parent
	-- (Only while it is new: a reload may add / move pieces later, which must not rebuild every frame.)
	if not stale and os.clock() - heldSeenAt < 1.5 and #held:GetDescendants() ~= builtCount then
		stale = true
	end
	local function hideArms()
		for _, arm in { armR, armL } do
			if arm then
				arm.Transparency = 1 -- never left standing where they were last placed
			end
		end
	end
	if stale then
		if os.clock() - heldSeenAt < 0.15 then
			if gun then
				clearGun()
			end
			hideArms()
			return
		end
		local ok, err = pcall(build, char, held)
		if not ok then
			warn("[FirstPersonView] build failed: " .. tostring(err))
			clearGun()
			hideArms()
			return
		end
	end
	local g = gun :: BasePart
	if not g then
		hideArms()
		return
	end
	if armR then
		armR.Transparency = 0
	end

	-- Sway: the gun trails camera turns a little and settles back.
	local look = cam.LookVector
	local last = lastLook or look
	lastLook = look
	local rel = cam:VectorToObjectSpace(last)
	local k = 1 - math.exp(-dt * Config.FirstPersonSwayReturn)
	local maxSway = math.rad(Config.FirstPersonSwayMaxDeg)
	swayX = math.clamp(swayX + rel.X * Config.FirstPersonSway, -maxSway, maxSway) * (1 - k)
	swayY = math.clamp(swayY + rel.Y * Config.FirstPersonSway, -maxSway, maxSway) * (1 - k)

	-- Walk bob: small, eased in and out with movement.
	bobAmp += ((if moving then 1 else 0) - bobAmp) * (1 - math.exp(-dt * 6))
	bobPhase += dt * Config.FirstPersonBobSpeed
	local bobScale = bobAmp * (1 - adsT * 0.7)
	local bob = Vector3.new(
		math.sin(bobPhase) * Config.FirstPersonBobX * bobScale,
		-math.abs(math.cos(bobPhase)) * Config.FirstPersonBobY * bobScale,
		0
	)

	-- Recoil eases home (FirstPersonRecoilReturn per second, exponential: a big sniper kick reads, then settles).
	local back = math.exp(-dt * Config.FirstPersonRecoilReturn)
	kick *= back
	rise *= back
	local adsGoal = if ClientState.ads then 1 else 0
	adsT += (adsGoal - adsT) * (1 - math.exp(-dt / math.max(Config.AdsBlendSec, 0.01) * 3))
	-- Round 24h: reload. t runs 0..1 over the reload (or one shell); the pose eases in and out at the ends.
	local ammo = ClientState.ammo
	local rt: number? = nil
	local shell = false
	if ammo and ammo.reloading then
		local len = math.max(ammo.reloadEndsAt - ammo.reloadStartedAt, 0.05)
		rt = math.clamp((os.clock() - ammo.reloadStartedAt) / len, 0, 1)
		shell = ammo.shell == true
	end
	reloadW += ((if rt then 1 else 0) - reloadW) * (1 - math.exp(-dt * 12))
	local tilt = reloadW
	if rt and not shell then
		tilt *= smooth(0, 0.15, rt) * (1 - smooth(0.85, 1, rt))
	end
	local a = adsT * adsT * (3 - 2 * adsT) * (1 - tilt) -- a reload drops the sights

	-- Hip: the grip low right. ADS: the sight line on the crosshair, FirstPersonAdsRelief ahead of the eye.
	-- Round 24p: at the hip the barrel converges on the crosshair line FirstPersonConverge studs out, so the bullet
	-- lines leave the muzzle straight down the barrel (a fixed tilt left long guns pointing past it and the lines
	-- ran downhill). FirstPersonHipTilt adds a cant on top.
	local hipGrip = Config.FirstPersonHipGrip
	local mz = muzzleAtt
	local boreUp = if mz then mz.CFrame.Position.Y - gripPos.Y else 0
	local aimFrom = hipGrip + Vector3.new(0, boreUp, 0)
	local aimRot = CFrame.lookAt(aimFrom, Vector3.new(0, 0, -Config.FirstPersonConverge)).Rotation
	local hipCF = CFrame.new(hipGrip)
		* aimRot
		* CFrame.Angles(math.rad(Config.FirstPersonHipTilt.X), math.rad(Config.FirstPersonHipTilt.Y), 0)
		* CFrame.new(-gripPos)
	local adsCF = CFrame.new(0, -Config.FirstPersonAdsDrop, -relief) * CFrame.new(-sightPos)
	if g:GetAttribute("Sight") == "bare" then
		-- Round 24aa: no sights to look down (launchers, elemental guns, TNT): aiming brings the gun in low and
		-- centred, still converging on the crosshair, which stays up (the body along the eye line filled the view).
		local bareGrip = Config.FirstPersonBareAdsGrip
		local from = bareGrip + Vector3.new(0, boreUp, 0)
		local rot = CFrame.lookAt(from, Vector3.new(0, 0, -Config.FirstPersonConverge)).Rotation
		adsCF = CFrame.new(bareGrip) * rot * CFrame.new(-gripPos)
	end
	local local_ = hipCF:Lerp(adsCF, a)
	local motion = CFrame.new(bob) * CFrame.Angles(swayY, -swayX, 0) * CFrame.new(0, 0, kick)
	-- Round 24aa: the draw: up from below the screen, tipped forward and rolled, settling in FirstPersonDrawSec.
	local drawK = 1 - smooth(0, Config.FirstPersonDrawSec, os.clock() - drawAt)
	if drawK > 0 then
		motion = motion
			* CFrame.new(0.05 * drawK, -0.45 * drawK, 0.12 * drawK)
			* CFrame.Angles(math.rad(-45) * drawK, math.rad(10) * drawK, math.rad(20) * drawK)
	end
	if rise > 0 then
		-- Muzzle flip about the grip.
		local_ = local_ * CFrame.new(gripPos) * CFrame.Angles(rise, 0, 0) * CFrame.new(-gripPos)
	end
	-- Reload tilt about the grip: muzzle up a little, rolled in toward the centre, pulled down and in.
	if tilt > 0 then
		local rot = Config.FirstPersonReloadTilt
		local bump = 0
		if rt and shell then
			bump = math.sin(smooth(0.45, 0.8, rt) * math.pi) * Config.FirstPersonShellBump -- each shell pushed in
		end
		local_ = CFrame.new(Config.FirstPersonReloadPull * tilt)
			* local_
			* CFrame.new(gripPos)
			* CFrame.Angles(math.rad(rot.X) * tilt + bump, math.rad(rot.Y) * tilt, math.rad(rot.Z) * tilt)
			* CFrame.new(-gripPos)
	end
	GunModels.pivot(g, cam * motion * local_)

	-- The mag drops out (0.15-0.4, fading), is gone, then a fresh one rises in from below (0.55-0.8).
	local magDrop, magFade = 0, 0
	if rt and not shell then
		local k = Config.FirstPersonGunScale
		if rt < 0.15 then
			magDrop = 0
		elseif rt < 0.4 then
			local u = smooth(0.15, 0.4, rt)
			magDrop = -Config.FirstPersonMagDrop * k * u * u
			magFade = smooth(0.3, 0.4, rt)
		elseif rt < 0.55 then
			magFade = 1
		elseif rt < 0.8 then
			magDrop = -Config.FirstPersonMagDrop * k * 0.8 * (1 - smooth(0.55, 0.8, rt))
		end
	end
	local down = g.CFrame.UpVector
	for _, mp in magParts do
		if magDrop ~= 0 then
			mp.CFrame = mp.CFrame + down * magDrop
		end
		mp.LocalTransparencyModifier = if wasScoped then 1 else magFade
	end

	ClientState.viewMuzzleAtt = muzzleAtt

	-- Optics fade while aimed so the view goes through them. Round 24r: a sniper scope at full zoom hides the whole
	-- viewmodel (the HUD draws the scope ring and reticle instead).
	ClientState.fpAdsT = a
	local scoped = g:GetAttribute("Sight") == "scope" and a > 0.85
	if scoped ~= wasScoped then
		wasScoped = scoped
		for _, p in parts do
			p.LocalTransparencyModifier = if scoped then 1 else 0
		end
		for _, arm in { armR, armL } do
			if arm then
				arm.LocalTransparencyModifier = if scoped then 1 else 0
			end
		end
	end
	if not scoped then
		for _, p in optics do
			p.LocalTransparencyModifier = a * 0.9
		end
		for _, p in blockers do
			p.LocalTransparencyModifier = a
		end
	end

	-- Forearms: from the grip and the foregrip back and down out of the bottom of the view.
	local hand = g.CFrame:PointToWorldSpace(gripPos)
	local elbowR = cam:PointToWorldSpace(Config.FirstPersonElbowR)
	placeArm(armR, hand, elbowR)
	local fore = foreAtt
	-- Reloading: the support hand goes to the mag (or the loading port for shells) instead of the foregrip.
	local reloadHand: Vector3? = nil
	if rt and tilt > 0.3 then
		if not shell and magParts[1] and rt > 0.12 and rt < 0.85 then
			reloadHand = if rt < 0.4 or rt > 0.55
				then magParts[1].Position
				else cam:PointToWorldSpace(Vector3.new(0.05, -0.75, -0.7)) -- down at the belt for the fresh one
		elseif shell and wellAtt then
			reloadHand = wellAtt.WorldPosition
		end
	end
	if reloadHand then
		placeArm(armL, reloadHand, cam:PointToWorldSpace(Config.FirstPersonElbowL))
		if armL then
			armL.Transparency = 0
		end
	elseif fore and fore.Parent then
		placeArm(armL, fore.WorldPosition, cam:PointToWorldSpace(Config.FirstPersonElbowL))
		if armL then
			armL.Transparency = 0
		end
	elseif armL then
		armL.Transparency = 1
	end
end)

player.CharacterRemoving:Connect(clear)
