--!strict
-- Server entry point. Wires the shared modules (profiles, per-player state, the store, the pass, Jobs, the hub and
-- the queue pads), then Runs.start() clones Run/ once per map and starts every slot's Run/Main: the hub slot
-- (Run/ itself) and one run slot per map, each with its own run state machine (brief 8: concurrent runs).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)

local Profiles = require(script.Parent.Profiles)
local PlayerState = require(script.Parent.PlayerState)
local Runs = require(script.Parent.Runs)
local Hub = require(script.Parent.Hub)
local Queue = require(script.Parent.Queue)
local Meta = require(script.Parent.Meta)
local Purchases = require(script.Parent.Purchases)
local Boosts = require(script.Parent.Boosts)
local Shop = require(script.Parent.Shop)
local CrateOpen = require(script.Parent.CrateOpen)
local Vip = require(script.Parent.Vip)
local Pass = require(script.Parent.Pass)
local Jobs = require(script.Parent.Jobs)
local SkillService = require(script.Parent.SkillService)
local Streak = require(script.Parent.Streak)
local DailyCrate = require(script.Parent.DailyCrate)

Profiles.init()
PlayerState.init()
-- Per-player views that live in a run slot: each player's own slot answers.
PlayerState.syncHooks.dealer = function(p: Player)
	return Runs.modOf(p, "Dealer").view(p)
end
PlayerState.syncHooks.pause = function(p: Player)
	return Runs.modOf(p, "Pause").view(p)
end
-- Brief 6: the revive token costs and the server's os.time (the client's fake clocks and boost timers run off it).
PlayerState.syncHooks.revive = function(p: Player)
	return { selfCost = Config.SelfReviveTokens, allCost = Runs.modOf(p, "Downed").reviveAllCost() }
end
PlayerState.syncHooks.osTime = function()
	return os.time()
end
-- 0 HP goes to the Downed of the player's run.
PlayerState.onZeroHP = function(p: Player)
	Runs.modOf(p, "Downed").down(p)
end
Purchases.init()
Boosts.init()
Shop.init()
local _ = CrateOpen -- registers the crate purchase kind and the free-open action
Vip.init()
Pass.init()
Jobs.init()
SkillService.init() -- brief 9: the Skill Web
Streak.init() -- brief 10: the login streak
DailyCrate.init() -- brief 10: the daily crate podium

-- The run slots: the hub's first (it builds the room the hub reads), then one per map.
Runs.start()
Hub.init()
Queue.init()
Meta.init()
