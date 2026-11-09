--!strict
-- Fire input, mag + reload, local tracer, send FireShot. Damage is server-side only.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Types"))
local Weapons = require(Shared:WaitForChild("Weapons"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Tracer = require(script.Parent:WaitForChild("Tracer"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local player = Players.LocalPlayer
local effects = Workspace:WaitForChild("Effects")
local groundLoot = Workspace:WaitForChild("GroundLoot")

local held: Types.HeldView? = nil
local mag = 0
local reloading = false
local reloadToken = 0
local lastShot = 0
local firing = false
local semiLatch = false

local reloadStartedAt = 0
local reloadEndsAt = 0

local function publishAmmo()
	ClientState.ammo = {
		mag = mag,
		max = if held then held.magSize else 0,
		reloading = reloading,
		shell = held ~= nil and held.shellReload,
		reloadStartedAt = reloadStartedAt,
		reloadEndsAt = reloadEndsAt,
	}
	ClientState.Ammo:Fire(ClientState.ammo)
end

-- Tube-fed guns load one shell per reloadTime; the ring fills once per shell. Firing cancels the rest.
local function shellReload(token: number)
	task.spawn(function()
		while true do
			local h = held
			if token ~= reloadToken or not h then
				return
			end
			reloadStartedAt = os.clock()
			reloadEndsAt = reloadStartedAt + h.reloadTime
			publishAmmo()
			task.wait(h.reloadTime)
			h = held
			if token ~= reloadToken or not h then
				return
			end
			mag = math.min(h.magSize, mag + 1)
			Remotes.AmmoReport:FireServer(mag)
			UI.sound(Theme.Sounds.shellLoad, 1 + (mag / h.magSize) * 0.12, 0.45) -- Round 24o: a click, near natural pitch
			if mag >= h.magSize then
				reloading = false
				publishAmmo()
				return
			end
			publishAmmo()
		end
	end)
end

local function reload()
	if reloading or not held or mag >= held.magSize then
		return
	end
	reloading = true
	reloadToken += 1
	local token = reloadToken
	-- Mag out now; Round 19d: the mag seats near the end of the reload (a shell reload clicks per shell instead).
	UI.sound(Theme.Sounds.reloadOut, 1, 0.45)
	if not held.shellReload then
		local seatAt = held.reloadTime * Config.ReloadSeatShare
		task.delay(seatAt, function()
			if token == reloadToken and reloading then
				UI.sound(Theme.Sounds.reloadIn, 1, 0.5)
			end
		end)
	end
	if held.shellReload then
		shellReload(token)
		return
	end
	reloadStartedAt = os.clock()
	reloadEndsAt = reloadStartedAt + held.reloadTime
	publishAmmo()
	task.delay(held.reloadTime, function()
		if token == reloadToken and held then
			mag = held.magSize
			reloading = false
			Remotes.AmmoReport:FireServer(mag)
			publishAmmo()
		end
	end)
end

-- Stop a shell reload where it is (only when there is something in the tube to shoot).
local function cancelReload(): boolean
	local h = held
	if not reloading or not h or not h.shellReload or mag <= 0 then
		return false
	end
	reloadToken += 1
	reloading = false
	publishAmmo()
	return true
end

-- The mag lives with the gun on the server (every shot and reload reports it), so a new uid arrives with
-- the rounds that gun had when it was last put down: full for a fresh gun, whatever was left for a floor
-- pickup or the stowed gun coming back after a revive.
ClientState.Changed:Connect(function(sync: Types.Sync)
	local h = sync.held
	if not held or h.uid ~= held.uid then
		held = h
		mag = if h.mag ~= nil then math.clamp(h.mag, 0, h.magSize) else h.magSize
		reloading = false
		reloadToken += 1
	else
		held = h
		mag = math.min(mag, h.magSize)
	end
	publishAmmo()
end)

local function coneSpread(direction: Vector3, halfAngleDeg: number): Vector3
	if halfAngleDeg <= 0 then
		return direction
	end
	local angle = math.rad(halfAngleDeg) * math.sqrt(math.random())
	local roll = math.random() * math.pi * 2
	local cf = CFrame.lookAt(Vector3.zero, direction)
	return (cf * CFrame.Angles(0, 0, roll) * CFrame.Angles(angle, 0, 0)).LookVector
end

local function rayParams(char: Model): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char, groundLoot, effects }
	return params
end

-- Screen center when locked, the cursor when unlocked (Ctrl / Alt).
local function aimPoint(char: Model): Vector3
	return ClientState.cursorAimPoint(char)
end

-- Round 24v: Explosive / Elemental weapons. No tracer (the server's projectile, or the stream / arc fx, is the
-- feedback); each shot / tick spends one round, a charged plasma shot up to its maxCost.
local SPECIAL_SOUND = {
	projectile = { id = "shot", pitch = 0.42, vol = 0.45 },
	charge = { id = "laser", pitch = 0.8, vol = 0.4 },
	stream = { id = "hiss", pitch = 1.1, vol = 0.12 },
	chain = { id = "laser", pitch = 1.6, vol = 0.12 },
}
local function specialOf(h: Types.HeldView?): any
	local w = h and Weapons.ById[h.weaponId]
	return if w and w.mode and w.mode ~= "hitscan" then w else nil
end

local function fireSpecial(h: Types.HeldView, w: any, head: BasePart, char: Model, chargeT: number)
	local cost = 1
	if w.mode == "charge" then
		cost = 1 + math.floor(chargeT * (w.charge.maxCost - 1) + 0.5)
	end
	cost = math.min(cost, mag)
	mag -= cost
	publishAmmo()
	local headPos = head.Position
	local dir = (aimPoint(char) - headPos).Unit
	if w.mode == "projectile" and h.spread > 0 then
		dir = coneSpread(dir, h.spread * (if ClientState.ads then Config.AdsSpreadMult else 1))
	end
	-- Round 24aa: lobbed rounds are solved onto the crosshair point on the server.
	Remotes.FireShot:FireServer(
		headPos,
		dir,
		Workspace:GetServerTimeNow(),
		mag,
		{ charge = chargeT, target = aimPoint(char) }
	)
	local snd = SPECIAL_SOUND[w.mode]
	if w.id == "TNT" then
		UI.sound(Theme.Sounds.swap, 1.6, 0.45)
	elseif snd then
		UI.sound(
			(Theme.Sounds :: any)[snd.id],
			snd.pitch * (if w.mode == "charge" then 1 + chargeT * 0.4 else 1),
			snd.vol
		)
	end
	if w.mode == "stream" then
		ClientState.Juice:Fire("LocalStream", { element = w.stream.element })
	end
	-- Round 24ab: a held plasma beam follows the cursor while it lasts: stream the aim point to the server.
	if w.mode == "charge" then
		local c = w.charge
		local dur = c.minDur + (c.maxDur - c.minDur) * chargeT
		if dur > 0.12 then
			task.spawn(function()
				local t0 = os.clock()
				while os.clock() - t0 < dur do
					local ch = player.Character
					if ch then
						Remotes.BeamAim:FireServer(aimPoint(ch))
					end
					task.wait(0.07)
				end
			end)
		end
	end
	-- Streams and the arc tick ten times a second: no per-tick kick or flash, only the projectile guns kick.
	if w.mode == "projectile" or w.mode == "charge" then
		ClientState.Juice:Fire("LocalFire", { weaponId = h.weaponId })
	end
	if mag <= 0 then
		task.delay(0.15, reload)
	end
end

local function fire(chargeT: number?)
	local h = held
	local char = player.Character
	local head = char and char:FindFirstChild("Head") :: BasePart?
	if not h or not char or not head then
		return
	end
	if reloading and not cancelReload() then
		return
	end
	if mag <= 0 then
		reload()
		return
	end
	local special = specialOf(h)
	if special then
		fireSpecial(h, special, head, char, chargeT or 0)
		return
	end
	mag -= 1
	publishAmmo()

	local target = aimPoint(char)
	local headPos = head.Position
	local dir = (target - headPos).Unit
	local spread = h.spread * (if ClientState.ads then Config.AdsSpreadMult else 1)
	local sendDir = if h.pellets > 1 then dir else coneSpread(dir, spread)
	Remotes.FireShot:FireServer(headPos, sendDir, Workspace:GetServerTimeNow(), mag)

	-- Round 24i: the line leaves the gun's muzzle in every view (feedback only; the hit rays above and below
	-- start at the head). In first person the real gun is hidden under the camera: the viewmodel's muzzle.
	local fpMuzzle = if ClientState.firstPerson then ClientState.viewMuzzleAtt else nil
	-- Round 24p: in first person the start is pinned where the muzzle is now, before this shot's kick flips the
	-- viewmodel up (a start riding the flip made every line run downhill).
	-- Round 24q: ...but in camera space, so it moves with the view while you walk and turn.
	local from: any = Tracer.muzzleOf(char) or headPos
	-- Round 25: aimed in first person (iron, red dot or a scope with the viewmodel hidden) the line starts off-axis
	-- in camera space, whatever the viewmodel is doing; the offset shrinks with the zoom so a magnified scope still
	-- shows the streak inside its ring.
	local adsTracer = ClientState.firstPerson and ClientState.ads
	if adsTracer or fpMuzzle then
		local cam = Workspace.CurrentCamera :: Camera
		local localStart: Vector3
		if adsTracer then
			local st = Config.FirstPersonAdsTracerStart
			local zoomK = math.clamp(
				math.tan(math.rad(cam.FieldOfView / 2)) / math.tan(math.rad(Config.CameraFov * Config.AdsFovMult / 2)),
				0.15,
				1.5
			)
			localStart = Vector3.new(st.X * zoomK, st.Y * zoomK, st.Z)
		else
			localStart = cam.CFrame:PointToObjectSpace((fpMuzzle :: Attachment).WorldPosition)
		end
		from = function(): Vector3
			return cam.CFrame:PointToWorldSpace(localStart)
		end
	end
	local wdef = Weapons.ById[h.weaponId]
	local tracerColor = if wdef and wdef.tracer then Color3.fromHex(wdef.tracer) else nil -- Round 24ad
	local params = rayParams(char)
	for i = 1, h.pellets do
		local d = if h.pellets > 1 then coneSpread(dir, spread) else sendDir
		local result = Workspace:Raycast(headPos, d * Config.MaxShotRange, params)
		local endPoint = if result then result.Position else headPos + d * Config.MaxShotRange
		Tracer.draw(
			from,
			endPoint,
			tracerColor,
			fpMuzzle ~= nil or adsTracer,
			if adsTracer then Config.FirstPersonAdsTracerLife else nil,
			adsTracer
		)
	end

	UI.sound(Theme.Sounds.shot, Config.ShotPitchByArchetype[h.archetype] or 1, 0.35)
	ClientState.Juice:Fire("LocalFire", { weaponId = h.weaponId })

	if mag <= 0 then
		task.delay(0.15, reload)
	end
end

-- Burst guns: one pull fires `burst` shots at fireRate, then burstDelay before the next burst.
local burstLeft = 0
local burstEndedAt = -math.huge
local chargeStart: number? = nil -- Round 24v: the plasma trigger went down at this clock

-- Round 24aa prototype: sprint. Hold Shift while moving: the gun goes away (no fire, no ADS) and the server runs
-- you SprintSpeedMult faster. Letting go, stopping, or a menu ends it.
local shiftHeld = false
local padSprint = false
local function updateSprint()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local moving = hum ~= nil and hum.MoveDirection.Magnitude > 0.1
	if not moving then
		padSprint = false
	end
	local want = Config.SprintEnabled
		and (shiftHeld or padSprint)
		and moving
		and not ClientState.downed
		and not ClientState.blocked()
		and ClientState.cameraMode == "gameplay"
	if want ~= ClientState.sprinting then
		ClientState.sprinting = want
		Remotes.SetSprint:FireServer(want)
		if want then
			ClientState.setAds(false)
			chargeStart = nil
			ClientState.chargeProgress = 0
		elseif
			-- Round 25: RMB still held when the sprint ends (or pressed during it): straight back into ADS.
			UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
			and not ClientState.blocked()
			and not ClientState.downed
			and not ClientState.combatOff()
		then
			ClientState.setAds(true)
		end
	end
end
ContextActionService:BindActionAtPriority("GHSSprint", function(_name, inputState: Enum.UserInputState)
	if inputState == Enum.UserInputState.Begin then
		shiftHeld = true
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		shiftHeld = false
	end
	return Enum.ContextActionResult.Pass
end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.LeftShift)

RunService.Heartbeat:Connect(function()
	updateSprint()
	local h = held
	-- Downed: the sidearm still fires while crawling (Config.DownedCanShoot); a bled-out spectator never does.
	if
		not h
		or ClientState.blocked()
		or ClientState.combatOff()
		or (ClientState.downed and not Config.DownedCanShoot)
		or ClientState.sprinting
	then
		burstLeft = 0
		return
	end
	local now = os.clock()
	-- Round 24v: charge weapons: hold to charge (the crosshair ring fills), release to fire. A full charge costs
	-- maxCost rounds, so the charge stops growing at what the mag can pay for.
	local special = specialOf(h)
	if special and special.mode == "charge" then
		local want = firing or ClientState.touchFire or ClientState.padFire
		if want and not chargeStart and mag > 0 and not reloading and now - lastShot >= 1 / h.fireRate then
			chargeStart = now
		end
		local start = chargeStart
		if start then
			local c = special.charge
			local cap = if c.maxCost > 1 then math.clamp((mag - 1) / (c.maxCost - 1), 0, 1) else 1
			local t = math.min(cap, (now - start) / c.sec)
			ClientState.chargeProgress = t
			if not want then
				chargeStart = nil
				ClientState.chargeProgress = 0
				lastShot = now
				fire(t)
			end
		end
		return
	elseif chargeStart then
		chargeStart = nil
		ClientState.chargeProgress = 0
	end
	if now - lastShot < 1 / h.fireRate then
		return
	end
	if h.burst > 1 then
		if burstLeft > 0 then
			-- The rest of a burst comes out whether or not the button is still held.
			burstLeft -= 1
			lastShot = now
			fire()
			if burstLeft == 0 or mag <= 0 then
				burstLeft = 0
				burstEndedAt = now
			end
			return
		end
		local want = firing or ClientState.touchFire or ClientState.padFire
		if not want or now - burstEndedAt < h.burstDelay then
			return
		end
		if Config.HoldToFire or not semiLatch then
			semiLatch = true
			burstLeft = h.burst - 1
			lastShot = now
			fire()
			if mag <= 0 then
				burstLeft = 0
				burstEndedAt = now
			end
		end
		return
	end
	local want = firing or ClientState.touchFire or ClientState.padFire
	if not want then
		return
	end
	if h.auto or Config.HoldToFire or not semiLatch then
		lastShot = now
		semiLatch = true
		fire()
	end
end)

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		firing = true
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		-- No ADS while downed: the sidearm is hip-fire only. Round 24d: none in the hub either (outside the range):
		-- there RMB only drags the camera round.
		if
			not ClientState.blocked()
			and not ClientState.downed
			and not ClientState.combatOff()
			and not ClientState.sprinting
		then
			ClientState.setAds(true)
		end
	elseif input.KeyCode == Enum.KeyCode.R then
		-- R mid shell-reload stops it; otherwise starts one.
		if not cancelReload() then
			reload()
		end
	end
end)

-- Round 21: 1 switches loadout slots. Bound through ContextActionService above the default priority so nothing
-- else (a core hotbar binding, a gameProcessed flag) can swallow the key; the server decides whether there is a
-- second gun to switch to (and logs why not).
ContextActionService:BindActionAtPriority("GHSSwitchWeapon", function(_name, inputState: Enum.UserInputState)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	-- Round 24aa: the training range is armed too (it was blocked with the rest of the hub).
	if UserInputService:GetFocusedTextBox() or ClientState.combatOff() then
		return Enum.ContextActionResult.Pass
	end
	Remotes.SwitchWeapon:FireServer()
	return Enum.ContextActionResult.Sink
end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.One)

UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		firing = false
		semiLatch = false
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		ClientState.setAds(false)
	end
end)

-- Opening the overlay or losing the mouse drops ADS so the camera never stays pulled in.
ClientState.BlockChanged:Connect(function()
	if ClientState.blocked() then
		ClientState.setAds(false)
	end
end)

ClientState.Juice:Connect(function(name: string, data: any)
	if name == "LocalReload" then
		if not cancelReload() then
			reload()
		end
	elseif name == "TouchFireReleased" or name == "PadFireReleased" then
		semiLatch = false
	elseif name == "PadSprint" and typeof(data) == "table" and data.on then
		-- Brief 11 step 2: L3 latches the sprint until you stop moving (step 3 gives it the full model).
		padSprint = true
	elseif name == "MagAdd" then
		-- SHARPSHOOTER's DEAD EYE OVERDRIVE mastery: a headshot during Dead Eye puts a round back in the mag.
		local h = held
		if h then
			local n = if typeof(data) == "table" then tonumber(data.n) or 1 else 1
			mag = math.min(h.magSize, mag + n)
			Remotes.AmmoReport:FireServer(mag)
			publishAmmo()
		end
	end
end)
