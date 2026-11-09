--!strict
-- Single source of truth for every remote. The server creates them here; the client waits for them.
-- Nothing else in the project creates a RemoteEvent or RemoteFunction.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DEFS: { [string]: string } = {
	FireShot = "RemoteEvent", -- client -> server: origin, direction, clientTime, rounds left in the mag after the shot
	AmmoReport = "RemoteEvent", -- client -> server: rounds in the held gun's mag (after a reload); the gun remembers it
	GunPose = "RemoteEvent", -- client -> server: { pitch, ads, reload (seconds, 0 = none), shell }; mirrored to character attributes so every client poses the gun
	BuyUpgrade = "RemoteFunction", -- client -> server: none; returns { ok, cards | reason }
	TakeUpgrade = "RemoteEvent", -- client -> server: cardIndex
	SwapWeapon = "RemoteEvent", -- client -> server: ground gun Part
	SwitchWeapon = "RemoteEvent", -- client -> server: none; swap the two loadout slots (key 1, Round 21)
	StateSync = "RemoteEvent", -- server -> client: Types.Sync
	Juice = "RemoteEvent", -- server -> client: event name, data
	Debug = "RemoteEvent", -- client -> server: command, args
	UseAbility = "RemoteEvent", -- client -> server: abilityId (one of the equipped class's three, Classes.lua), the cursor's floor point
	VoteSkip = "RemoteEvent", -- client -> server: on (boolean); only counts during an intermission
	SetAutoSkip = "RemoteEvent", -- client -> server: on (boolean); votes to skip every intermission
	MinigameStart = "RemoteEvent", -- server -> client: { token, name, tier }; open that game's panel
	MinigameResult = "RemoteEvent", -- client -> server: token, outcome (done | fail | cancel), misses
	ReviveHold = "RemoteEvent", -- client -> server: on (boolean); holding F / the REVIVE button near a downed teammate
	SelfRevive = "RemoteEvent", -- client -> server: none; the SELF-REVIVE button while downed
	GiveUp = "RemoteEvent", -- client -> server: none; the GIVE UP button while downed (bleed out now)
	ReviveEverybody = "RemoteEvent", -- client -> server: none; the spectate screen button
	SummaryChoice = "RemoteEvent", -- client -> server: "again" | "lobby" from the summary panel
	-- Brief 3: hub, queue, meta
	QueueAction = "RemoteEvent", -- client -> server: "create" { settings } | "cancel" | "leave"
	QueueState = "RemoteEvent", -- server -> client: the zone / party view for the local player (Queue.lua)
	Meta = "RemoteFunction", -- client -> server: action, args; returns { ok, reason?, toast? } (unlock / upgrade / equip)
	-- Brief 5: the dealer break and the pause
	DealerAction = "RemoteEvent", -- client -> server: "buy" (stand index | "crate" | "heal" | "reroll") | "skip" | "teleport"
	PauseAction = "RemoteEvent", -- client -> server: "vote" | "unvote" (to pause) | "extend" | "resume" (votes while paused)
	-- Round 16
	BeamAim = "RemoteEvent", -- client -> server: the cursor's world point while a held plasma beam runs (Round 24ab: it steers)
	SetSprint = "RemoteEvent", -- client -> server: boolean (Round 24aa prototype: Shift sprint, gun away, SprintSpeedMult)
	SetOption = "RemoteEvent", -- client -> server: key (Profiles.OPTIONS), value (boolean); saved to the profile
	-- Brief 6: the fake purchase flow and the shop actions
	Purchase = "RemoteFunction", -- client -> server: productId, args; returns { ok, reason?, balance, data? } (Purchases.lua)
	SheetState = "RemoteEvent", -- client -> server: open (boolean): the purchase sheet is up (the SECOND CHANCE window holds)
	Shop = "RemoteFunction", -- client -> server: action, args; returns { ok, reason?, data? } (claims, rerolls, VIP gift, crate credits)
	-- Brief 9: the Skill Web
	SkillBuy = "RemoteFunction", -- client -> server: node id; returns { ok, reason?, owned = { ids }, gold } (SkillService.lua)
	SkillSeen = "RemoteEvent", -- client -> server: { ids }: affordable nodes the player has now seen (they pulse once, then not)
	-- Brief 10: retention
	StreakClaim = "RemoteFunction", -- client -> server: "claim" | "over" | "vip"; returns { ok, reason?, day, results, crates } (Streak.lua; a paid RESTORE goes through Purchase "streak_restore")
	DailyCrateOpen = "RemoteFunction", -- client -> server: none; returns { ok, reason?, crateId, results } (DailyCrate.lua; ROLL AGAIN goes through Purchase "dailycrate_reroll")
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
