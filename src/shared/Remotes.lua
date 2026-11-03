--!strict
-- Single source of truth for every remote. The server creates them here; the client waits for them.
-- Nothing else in the project creates a RemoteEvent or RemoteFunction.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DEFS: { [string]: string } = {
	FireShot = "RemoteEvent", -- client -> server: origin, direction, clientTime
	BuyUpgrade = "RemoteFunction", -- client -> server: none; returns { ok, cards | reason }
	TakeUpgrade = "RemoteEvent", -- client -> server: cardIndex
	BuyWeapon = "RemoteFunction", -- client -> server: none; returns { ok, weapon | reason }
	SwapWeapon = "RemoteEvent", -- client -> server: ground gun Part
	TakeCrateWeapon = "RemoteEvent", -- client -> server: crateId, slot
	StateSync = "RemoteEvent", -- server -> client: Types.Sync
	Juice = "RemoteEvent", -- server -> client: event name, data
	Debug = "RemoteEvent", -- client -> server: command, args
	UseAbility = "RemoteEvent", -- client -> server: abilityId (turret | barricade | stim)
	VoteSkip = "RemoteEvent", -- client -> server: on (boolean); only counts during an intermission
	SetAutoSkip = "RemoteEvent", -- client -> server: on (boolean); votes to skip every intermission
	MinigameStart = "RemoteEvent", -- server -> client: { token, name, tier }; open that game's panel
	MinigameResult = "RemoteEvent", -- client -> server: token, outcome (done | fail | cancel), misses
	ReviveHold = "RemoteEvent", -- client -> server: on (boolean); holding F / the REVIVE button near a downed teammate
	SelfRevive = "RemoteEvent", -- client -> server: none; the SELF-REVIVE button while downed
	ReviveEverybody = "RemoteEvent", -- client -> server: none; the spectate screen button
	SummaryChoice = "RemoteEvent", -- client -> server: "again" | "lobby" from the summary panel
}

local folder: Instance
if RunService:IsServer() then
	local existing = ReplicatedStorage:FindFirstChild("Remotes")
	if existing then
		folder = existing
	else
		local f = Instance.new("Folder")
		f.Name = "Remotes"
		f.Parent = ReplicatedStorage
		folder = f
	end
	for name, class in DEFS do
		if not folder:FindFirstChild(name) then
			local r = Instance.new(class) :: Instance
			r.Name = name
			r.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes")
end

local Remotes = {} :: { [string]: any }
for name in DEFS do
	Remotes[name] = folder:WaitForChild(name)
end

return Remotes
