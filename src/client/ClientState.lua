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

function ClientState.isMouseFree(): boolean
	return ClientState.mouseFree or ClientState.mouseFreeHold or ClientState.blocked()
end

function ClientState.serverNow(): number
	return Workspace:GetServerTimeNow()
end

-- The player's fire-rate multiplier (upgrades, stim): held fire rate over the held gun's base rate.
-- Applied to other guns' base rates so floor tags and the reel compare like with like.
function ClientState.rateMult(): number
	local sync = ClientState.sync
	local held = sync and sync.held
	local w = held and Weapons.ById[held.weaponId]
	return if held and w and w.fireRate > 0 then held.fireRate / w.fireRate else 1
end

-- World point under the aim: the screen center when locked, the cursor when unlocked. Shared by the
-- gun (where bullets go) and the camera (which way the character faces).
local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Exclude
function ClientState.cursorAimPoint(char: Model): Vector3
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
	return if result then result.Position else ray.Origin + ray.Direction * Config.MaxShotRange
end

Remotes.StateSync.OnClientEvent:Connect(function(data: Types.Sync)
	ClientState.sync = data
	ClientState.Changed:Fire(data)
end)

Remotes.Juice.OnClientEvent:Connect(function(name: string, data: any)
	ClientState.Juice:Fire(name, data)
end)

return ClientState
