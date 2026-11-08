--!strict
-- Fire input, mag + reload, local tracer, send FireShot. Damage is server-side only.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Types"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
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
			UI.sound(Theme.Sounds.take, 1.1 + (mag / h.magSize) * 0.4, 0.35)
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

local function tracer(from: Vector3, to: Vector3, color: Color3)
	local a0 = Instance.new("Attachment")
	a0.WorldPosition = from
	a0.Parent = Workspace.Terrain
	local a1 = Instance.new("Attachment")
	a1.WorldPosition = to
	a1.Parent = Workspace.Terrain
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = 0.12
	beam.Width1 = 0.05
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.Color = ColorSequence.new(color)
	beam.Transparency = NumberSequence.new(0.1)
	beam.Parent = a0
	task.delay(0.05, function()
		a0:Destroy()
		a1:Destroy()
	end)
end

local function fire()
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
	mag -= 1
	publishAmmo()

	local target = aimPoint(char)
	local headPos = head.Position
	local dir = (target - headPos).Unit
	local spread = h.spread * (if ClientState.ads then Config.AdsSpreadMult else 1)
	local sendDir = if h.pellets > 1 then dir else coneSpread(dir, spread)
	Remotes.FireShot:FireServer(headPos, sendDir, Workspace:GetServerTimeNow(), mag)

	local heldGun = char:FindFirstChild("HeldGun")
	local muzzleAtt = heldGun and heldGun:FindFirstChild("Muzzle") :: Attachment?
	local muzzle = if muzzleAtt then muzzleAtt.WorldPosition else headPos
	local color = Color3.fromHex("FFE2A0")
	local params = rayParams(char)
	for i = 1, h.pellets do
		local d = if h.pellets > 1 then coneSpread(dir, spread) else sendDir
		local result = Workspace:Raycast(headPos, d * Config.MaxShotRange, params)
		local endPoint = if result then result.Position else headPos + d * Config.MaxShotRange
		tracer(muzzle, endPoint, color)
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

RunService.Heartbeat:Connect(function()
	local h = held
	-- Downed: the sidearm still fires while crawling (Config.DownedCanShoot); a bled-out spectator never does.
	if not h or ClientState.blocked() or ClientState.inHub() or (ClientState.downed and not Config.DownedCanShoot) then
		burstLeft = 0
		return
	end
	local now = os.clock()
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
		local want = firing or ClientState.touchFire
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
	local want = firing or ClientState.touchFire
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
		-- No ADS while downed: the sidearm is hip-fire only.
		if not ClientState.blocked() and not ClientState.downed then
			ClientState.setAds(true)
		end
	elseif input.KeyCode == Enum.KeyCode.R then
		-- R mid shell-reload stops it; otherwise starts one.
		if not cancelReload() then
			reload()
		end
	end
end)

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
	elseif name == "TouchFireReleased" then
		semiLatch = false
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
