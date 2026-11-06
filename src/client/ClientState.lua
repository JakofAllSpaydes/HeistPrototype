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

local ClientState = {
	sync = nil :: Types.Sync?,
	Changed = Signal.new(), -- (sync)
	Juice = Signal.new(), -- (name, data) from the server, plus local events (LocalFire, LocalReload)
	Ammo = Signal.new(), -- ({ mag, max, reloading })
	BlockChanged = Signal.new(),
	ammo = { mag = 0, max = 0, reloading = false, shell = false, reloadStartedAt = 0, reloadEndsAt = 0 },
	blocks = {} :: { [string]: boolean }, -- reasons the gun is held and the mouse is free
	touchFire = false, -- mobile fire button held
	ads = false, -- aiming down sights (RMB held, or mobile ADS toggle)
	isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled,
	downed = false, -- the local player is down: crawl, no fire, no buys
	spectating = false, -- bled out: the camera rides a teammate
	cameraMode = "gameplay", -- gameplay | spectate | cinematic: who drives the camera
	reviveProgress = 0, -- 0..1 while this player holds a revive on a teammate (ring on the crosshair)
	reviveNearby = false, -- a downed teammate is within ReviveRadius: F means revive, gun prompts step aside
	downedPlayers = {} :: { [number]: boolean }, -- userId -> currently down (any player)
	requestCameraYaw = nil :: number?, -- a sequence hands the gameplay camera back facing this yaw
}

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

function ClientState.isMouseFree(): boolean
	return ClientState.mouseFree or ClientState.mouseFreeHold or ClientState.blocked() or ClientState.inHub()
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
	local dmg: number = Weapons.damageAt(weaponId, math.clamp(rarity, 1, 5), dmgPct, level)
	local rate: number = Weapons.levelRateMult(level)
	return dmg, rate
end

-- True while this player is in the hub (not in a run, not in a party that is in the arena).
function ClientState.inHub(): boolean
	local sync = ClientState.sync
	return sync == nil or sync.waveState == "Hub"
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

Remotes.StateSync.OnClientEvent:Connect(function(data: Types.Sync)
	ClientState.sync = data
	ClientState.Changed:Fire(data)
end)

Remotes.Juice.OnClientEvent:Connect(function(name: string, data: any)
	ClientState.Juice:Fire(name, data)
end)

return ClientState
