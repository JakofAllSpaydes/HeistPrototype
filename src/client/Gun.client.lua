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
	-- Mag out, mag in: two clicks.
	UI.sound(Theme.Sounds.reload, 0.7, 0.45)
	task.delay(0.16, function()
		UI.sound(Theme.Sounds.reload, 1.05, 0.45)
	end)
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

ClientState.Changed:Connect(function(sync: Types.Sync)
	local h = sync.held
	if not held or h.uid ~= held.uid then
		held = h
		mag = h.magSize
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
	Remotes.FireShot:FireServer(headPos, sendDir, Workspace:GetServerTimeNow())

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

	local pitch = if h.archetype == "Sniper"
		then 0.6
		elseif h.archetype == "Shotgun" then 0.7
		elseif h.archetype == "SMG" then 1.3
		elseif h.archetype == "LMG" then 0.85
		else 1
	UI.sound(Theme.Sounds.shot, pitch, 0.35)
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
	if not h or ClientState.blocked() or ClientState.downed then
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
		if not ClientState.blocked() then
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

ClientState.Juice:Connect(function(name: string)
	if name == "LocalReload" then
		if not cancelReload() then
			reload()
		end
	elseif name == "TouchFireReleased" then
		semiLatch = false
	end
end)
