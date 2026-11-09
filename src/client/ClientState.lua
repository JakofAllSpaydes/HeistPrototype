--!strict
-- Latest StateSync, juice events and input blocking shared by every client module.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Weapons = require(Shared:WaitForChild("Weapons"))
local Signal = require(Shared:WaitForChild("Signal"))
local Types = require(Shared:WaitForChild("Types"))
local InputSettings = require(Shared:WaitForChild("InputSettings"))

local ClientState = {
	sync = nil :: Types.Sync?,
	Changed = Signal.new(), -- (sync)
	Juice = Signal.new(), -- (name, data) from the server, plus local events (LocalFire, LocalReload)
	Ammo = Signal.new(), -- ({ mag, max, reloading })
	BlockChanged = Signal.new(),
	ammo = { mag = 0, max = 0, reloading = false, shell = false, reloadStartedAt = 0, reloadEndsAt = 0 },
	blocks = {} :: { [string]: boolean }, -- reasons the gun is held and the mouse is free
	touchFire = false, -- mobile fire button held
	-- Round 24: touches that turn the camera (a drag that began on open screen right of the thumbstick, or on
	-- the FIRE button: drag from FIRE to aim while shooting). Camera.client reads it, MobileControls adds to it.
	cameraTouches = {} :: { [InputObject]: boolean },
	ads = false, -- aiming down sights (RMB held, or mobile ADS toggle)
	isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled,
	downed = false, -- the local player is down: crawl, no fire, no buys
	spectating = false, -- bled out: the camera rides a teammate
	viewMuzzleAtt = nil :: Attachment?, -- Round 24i: the first-person viewmodel's muzzle (local tracers start on it)
	dealerFocus = false, -- Round 25: a dealer stand / prop is what the interact key does now (gun prompts step aside)
	sprinting = false, -- Round 24aa prototype: Shift held while moving (no fire, no ADS, faster)
	chargeProgress = 0, -- Round 24v: 0..1 the plasma charge (the crosshair ring)
	fpWallK = 0, -- Round 25: 0..1 a wall right ahead of the first-person eye (the viewmodel lowers)
	fpAdsT = 0, -- Round 24r: 0..1 how far the first-person viewmodel is into ADS (the scope overlay fades with it)
	firstPerson = false, -- Round 24c: the gameplay camera is in first person (FirstPersonView draws the viewmodel)
	cameraView = 1, -- Round 28e: 1 normal, 2 far over the shoulder, 3 first person (the POV button's pips)
	cameraMode = "gameplay", -- gameplay | spectate | cinematic: who drives the camera
	reviveProgress = 0, -- 0..1 while this player holds a revive on a teammate (ring on the crosshair)
	reviveNearby = false, -- a downed teammate is within ReviveRadius: F means revive, gun prompts step aside
	downedPlayers = {} :: { [number]: boolean }, -- userId -> currently down (any player)
	requestCameraYaw = nil :: number?, -- a sequence hands the gameplay camera back facing this yaw
	musicDuck = false, -- Round 19d: a big moment (the boss cutscene) holds the soundtrack down (Music.lua)
	streakOpen = false, -- brief 10: the streak modal is up (first-time pulses wait behind it)
	dailyOpenOnArrival = false, -- Round 27c: the summary's crate card was tapped: the podium opens once you land
	-- Brief 11: the input device ("keyboard" | "touch" | "gamepad"), from the last real input with a short hold
	-- (Input.lua); every prompt, hint and layout reads it. DeviceChanged fires (device) on each switch.
	inputDevice = if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		then "touch"
		else "keyboard",
	DeviceChanged = Signal.new(),
	padFire = false, -- RT held (Gun.client reads it beside touchFire)
	padInteract = false, -- X held as the prompt (DownedUI's revive hold reads it)
	dealerActive = false, -- the dealer break is on (DealerUI)
	scoreboardOpen = false, -- the in-run scoreboard is up (Scoreboard.setOpen)
	promptVisible = false, -- a ProximityPrompt is showing (Input.lua: X is the prompt, not a reload)
	-- The right stick this frame and what the camera made of it (the Input monitor reads it).
	padLook = { x = 0, y = 0, amount = 0, yawRate = 0, pitchRate = 0, edgeSec = 0 },
}

-- Round 25: how squarely the player is looking at a world point, for choosing between interactables in reach
-- (lower is better): degrees off the camera's look line plus InteractDistWeight per stud from the character.
function ClientState.aimScore(pos: Vector3): number
	local cam = Workspace.CurrentCamera
	local char = game:GetService("Players").LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not cam then
		return math.huge
	end
	local to = pos - cam.CFrame.Position
	local angle = if to.Magnitude > 0.01
		then math.deg(math.acos(math.clamp(cam.CFrame.LookVector:Dot(to.Unit), -1, 1)))
		else 0
	local dist = if root then (pos - root.Position).Magnitude else 0
	return angle + dist * Config.InteractDistWeight
end

function ClientState.setAds(on: boolean)
	if ClientState.ads == on then
		return
	end
	ClientState.ads = on
	ClientState.Juice:Fire("Ads", { on = on })
end

function ClientState.setBlock(reason: string, on: boolean)
	ClientState.blocks[reason] = if on then true else nil
	ClientState.BlockChanged:Fire()
end

function ClientState.blocked(): boolean
	return next(ClientState.blocks) ~= nil
end

-- Mouse unlocked by the player (Ctrl toggle, Alt hold). Camera stops following the mouse; the gun still fires.
ClientState.mouseFree = false
ClientState.mouseFreeHold = false

-- Movement lock for the dedicated screens (customization scene, Create Match): the PlayerModule controls go
-- off while any reason is held, so the character stays put and reads as part of the screen.
local controlLocks: { [string]: boolean } = {}
local function controls(): any
	local ok, module = pcall(function()
		local Players = game:GetService("Players")
		local scripts = Players.LocalPlayer:WaitForChild("PlayerScripts", 5)
		local pm = scripts and scripts:FindFirstChild("PlayerModule")
		return if pm then require(pm :: ModuleScript) else nil
	end)
	if ok and module and typeof(module) == "table" and module.GetControls then
		return module:GetControls()
	end
	return nil
end

local lockedRoot: BasePart? = nil
local savedWalkSpeed: number? = nil

-- Brief 11: the movement-lock reasons held now (GamepadNav reads screens from these and the blocks).
function ClientState.movementLocks(): { [string]: boolean }
	return controlLocks
end

function ClientState.lockMovement(reason: string, on: boolean)
	controlLocks[reason] = if on then true else nil
	local want = next(controlLocks) == nil
	local c = controls()
	if c then
		if want then
			c:Enable()
		else
			c:Disable()
		end
	end
	-- Hard lock as well: the root anchors locally (the client owns its character's physics) and the walk
	-- speed drops to 0, so no input path can move the character while a screen is up.
	local char = game:GetService("Players").LocalPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not want then
		if hum then
			hum:Move(Vector3.zero, false)
			if savedWalkSpeed == nil then
				savedWalkSpeed = hum.WalkSpeed
			end
			hum.WalkSpeed = 0
		end
		if root and root:IsA("BasePart") then
			root.AssemblyLinearVelocity = Vector3.zero
			root.Anchored = true
			lockedRoot = root
		end
	else
		if lockedRoot and lockedRoot.Parent then
			lockedRoot.Anchored = false
		end
		lockedRoot = nil
		if hum and savedWalkSpeed ~= nil then
			hum.WalkSpeed = savedWalkSpeed
		end
		savedWalkSpeed = nil
	end
end

function ClientState.movementLocked(): boolean
	return next(controlLocks) ~= nil
end

-- Brief 11: on a gamepad the Ctrl / Alt free-cursor mode does not exist (the character always faces the camera aim).
function ClientState.isMouseFree(): boolean
	local manual = (ClientState.mouseFree or ClientState.mouseFreeHold) and ClientState.inputDevice ~= "gamepad"
	return manual or ClientState.blocked() or ClientState.combatOff()
end

-- Brief 11: the profile's INPUT settings (defaults until the first sync).
function ClientState.inputSettings(): InputSettings.Values
	local sync = ClientState.sync
	local p = sync and (sync :: any).profile
	local s = p and p.settings
	return InputSettings.merge(s and s.input)
end

-- Can the player raise the gun into ADS right now (RMB, LT, the ADS button)?
function ClientState.canAds(): boolean
	return not ClientState.blocked() and not ClientState.downed and not ClientState.combatOff()
end

function ClientState.serverNow(): number
	return Workspace:GetServerTimeNow()
end

-- The player's fire-rate multiplier (upgrades, stim): held fire rate over the held gun's base rate at its
-- Armory level. Applied to other guns' leveled base rates so floor tags and the reel compare like with like.
function ClientState.rateMult(): number
	local sync = ClientState.sync
	local held = sync and sync.held
	local w = held and Weapons.ById[held.weaponId]
	if not (held and w and w.fireRate > 0) then
		return 1
	end
	return held.fireRate / (w.fireRate * (tonumber(held.levelRateMult) or 1))
end

-- A gun on the floor (or in the crate reel) as the local player would hold it (Round 16): their own Armory level
-- for that weapon id and their own in-run damage pct, whoever dropped or rolled it. Returns the shot damage and
-- the level's fire-rate multiplier (the held gun's upgrades go on top through rateMult).
function ClientState.gunAsMine(weaponId: string, rarity: number): (number, number)
	local sync = ClientState.sync
	if not Weapons.ById[weaponId] then
		return 0, 1
	end
	local entry = sync and sync.profile and sync.profile.weapons and sync.profile.weapons[weaponId]
	local level = if entry then tonumber(entry.level) or 0 else 0
	local dmgPct = if sync then tonumber((sync :: any).dmgPct) or 0 else 0
	-- Brief 12: every damage source adds (dmgPct already holds the web's and the run's), plus the gun type's own.
	local r = sync and (sync :: any).resolved
	local typed = if typeof(r) == "table" and typeof(r.typeDamage) == "table"
		then tonumber(r.typeDamage[Weapons.ById[weaponId].archetype]) or 0
		else 0
	local dmg: number = Weapons.damageWith(weaponId, math.clamp(rarity, 1, 5), level, dmgPct * 100 + typed)
	local rate: number = Weapons.levelRateMult(level)
	return dmg, rate
end

-- True while this player is in the hub (not in a run, not in a party that is in the arena).
function ClientState.inHub(): boolean
	local sync = ClientState.sync
	return sync == nil or sync.waveState == "Hub"
end

-- Brief 8: standing in the hub's training range (armed: fire, reload, ADS, abilities, the camera lock).
function ClientState.inRange(): boolean
	local sync = ClientState.sync :: any
	return sync ~= nil and sync.waveState == "Hub" and sync.inRange == true
end

-- No combat here: the hub outside the range.
function ClientState.combatOff(): boolean
	return ClientState.inHub() and not ClientState.inRange()
end

-- World point under the aim: the screen center when locked, the cursor when unlocked. Shared by the
-- gun (where bullets go) and the camera (which way the character faces).
local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Exclude
function ClientState.cursorAimPoint(char: Model): Vector3
	local point = ClientState.cursorAim(char)
	return point
end

-- The same aim as the point, the camera ray's origin and the part it hit (nil past MaxShotRange). Thrown
-- abilities send all three so the server's aim assist can lock what the cursor is on (Round 16).
function ClientState.cursorAim(char: Model): (Vector3, Vector3, Instance?)
	local camera = Workspace.CurrentCamera :: Camera
	local x, y
	if ClientState.isMouseFree() then
		local m = UserInputService:GetMouseLocation()
		x, y = m.X, m.Y
	else
		local vp = camera.ViewportSize
		x, y = vp.X / 2, vp.Y / 2
	end
	local ray = camera:ViewportPointToRay(x, y)
	local filter: { Instance } = { char }
	for _, name in { "GroundLoot", "Effects" } do
		local f = Workspace:FindFirstChild(name)
		if f then
			table.insert(filter, f)
		end
	end
	aimParams.FilterDescendantsInstances = filter
	local result = Workspace:Raycast(ray.Origin, ray.Direction * Config.MaxShotRange, aimParams)
	if result then
		return result.Position, ray.Origin, result.Instance
	end
	return ray.Origin + ray.Direction * Config.MaxShotRange, ray.Origin, nil
end

-- Brief 6: the server's os.time (boost expiries, the fake clocks) as of now, from the last sync's stamp.
local osOffset: number? = nil
function ClientState.osNow(): number
	return if osOffset then os.clock() + osOffset else os.time()
end

-- The player's fake clock (real UTC + the profile's debug offset): seasons, rotations, VIP renewals, Job resets.
function ClientState.fakeNow(): number
	local sync = ClientState.sync
	local p = sync and sync.profile
	local off = if p and typeof(p.clockOffset) == "number" then p.clockOffset else 0
	return ClientState.osNow() + off
end

Remotes.StateSync.OnClientEvent:Connect(function(data: Types.Sync)
	local stamp = (data :: any).osTime
	if typeof(stamp) == "number" then
		local fresh = stamp - os.clock()
		-- os.time is whole seconds: keep the offset that reads latest so the clock never steps back.
		if not osOffset or fresh > (osOffset :: number) or (osOffset :: number) - fresh > 2 then
			osOffset = fresh
		end
	end
	ClientState.sync = data
	ClientState.Changed:Fire(data)
end)

Remotes.Juice.OnClientEvent:Connect(function(name: string, data: any)
	ClientState.Juice:Fire(name, data)
end)

return ClientState
