--!strict
-- Latest StateSync, juice events and input blocking shared by every client module.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Signal = require(Shared:WaitForChild("Signal"))
local Types = require(Shared:WaitForChild("Types"))

local ClientState = {
	sync = nil :: Types.Sync?,
	Changed = Signal.new(), -- (sync)
	Juice = Signal.new(), -- (name, data) from the server, plus local events (LocalFire, LocalReload)
	Ammo = Signal.new(), -- ({ mag, max, reloading })
	BlockChanged = Signal.new(),
	ammo = { mag = 0, max = 0, reloading = false },
	blocks = {} :: { [string]: boolean }, -- reasons the gun is held and the mouse is free
	touchFire = false, -- mobile fire button held
	isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled,
}

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

Remotes.StateSync.OnClientEvent:Connect(function(data: Types.Sync)
	ClientState.sync = data
	ClientState.Changed:Fire(data)
end)

Remotes.Juice.OnClientEvent:Connect(function(name: string, data: any)
	ClientState.Juice:Fire(name, data)
end)

return ClientState
