--!strict
-- VOTE TO PAUSE (brief 5). Available in a wave, the intermission and the dealer break, from the dealer card,
-- the scoreboard and P. Everyone in the party votes (solo pauses at once); then the server freezes the run:
-- enemies and their hazards stand still, nobody takes damage, players cannot move or fire, and every timer
-- stops (bleed, floor guns, crates, side jobs, the vault, the dealer, ability lifetimes and cooldowns, spawns,
-- the heat clock, the intermission and the run clock). A `PAUSED · <names>` overlay with RESUME any player can
-- press; at PauseMaxSec it resumes by itself after a 10s countdown. No limit on how often: solo pauses at once,
-- a party pauses whenever everyone votes.
--
-- How modules join in: `Pause.active()` to skip work, `Pause.delay(sec, fn)` for timers that must not run out
-- while paused, `Pause.onTick(fn)` to push deadlines forward by dt every frame of a pause, and `Pause.onResume(fn)`
-- for anything that is cheaper to shift once (attributes the clients read). This module requires only World.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(script.Parent.SlotRemotes)
local World = require(script.Parent.World)

local Pause = {}

local paused = false
local startedAt = 0 -- server time the pause began
local resumeAt = 0 -- server time it resumes by itself
local votes: { [number]: boolean } = {}
-- While paused: VOTE TO EXTEND (+PauseExtendSec, stack as often as everyone agrees) and VOTE TO RESUME.
local extendVotes: { [number]: boolean } = {}
local resumeVotes: { [number]: boolean } = {}
local tickHooks: { (number) -> () } = {}
local resumeHooks: { (number) -> () } = {}
local freezeHook: ((boolean) -> ())? = nil

function Pause.active(): boolean
	return paused
end

function Pause.onTick(fn: (number) -> ())
	table.insert(tickHooks, fn)
end

function Pause.onResume(fn: (number) -> ())
	table.insert(resumeHooks, fn)
end

-- PlayerState installs the character freeze (anchor + no walking) so this module stays a leaf.
function Pause.setFreezeHook(fn: (boolean) -> ())
	freezeHook = fn
end

-- Waits `seconds` of unpaused time.
function Pause.wait(seconds: number)
	local left = seconds
	while left > 0 do
		local dt = RunService.Heartbeat:Wait()
		if not paused then
			left -= dt
		end
	end
end

-- task.delay that does not count paused time.
function Pause.delay(seconds: number, fn: () -> ())
	task.spawn(function()
		Pause.wait(seconds)
		fn()
	end)
end

-- Yields while paused; returns how long it waited.
function Pause.hold(): number
	local waited = 0
	while paused do
		waited += RunService.Heartbeat:Wait()
	end
	return waited
end

local function allowedState(): boolean
	return World.state == "Wave" or World.state == "Intermission" or World.state == "Dealer"
end

function Pause.canVote(): boolean
	return not paused and allowedState()
end

local function names(): string
	local out = {}
	for _, p in World.runAudience() do
		table.insert(out, string.upper(p.Name))
	end
	return table.concat(out, ", ")
end

local function countIn(set: { [number]: boolean }): number
	local n = 0
	for _, p in World.runAudience() do
		if set[p.UserId] then
			n += 1
		end
	end
	return n
end

local function voteCount(): number
	return countIn(votes)
end

-- The sync view: Types.Sync.pause.
function Pause.view(player: Player): any
	return {
		active = paused,
		names = if paused then names() else "",
		startedAt = startedAt,
		resumeAt = resumeAt,
		countdownSec = Config.PauseCountdownSec,
		votes = voteCount(),
		needed = #World.runAudience(),
		myVote = votes[player.UserId] == true,
		canVote = Pause.canVote(),
		extendVotes = countIn(extendVotes),
		resumeVotes = countIn(resumeVotes),
		myExtend = extendVotes[player.UserId] == true,
		myResume = resumeVotes[player.UserId] == true,
		extendSec = Config.PauseExtendSec,
	}
end

local function dirtyAll()
	World.pauseDirty = true
end

local function begin()
	paused = true
	startedAt = Workspace:GetServerTimeNow()
	resumeAt = startedAt + Config.PauseMaxSec
	table.clear(votes)
	table.clear(extendVotes)
	table.clear(resumeVotes)
	if freezeHook then
		freezeHook(true)
	end
	World.fireRun("Paused", { names = names(), resumeAt = resumeAt, countdownSec = Config.PauseCountdownSec })
	print(string.format("[GHS Pause] paused at wave %d (%s) by %s", World.wave, World.state, names()))
	dirtyAll()
end

function Pause.resume(by: string)
	if not paused then
		return
	end
	paused = false
	local duration = Workspace:GetServerTimeNow() - startedAt
	for _, fn in resumeHooks do
		task.spawn(fn, duration)
	end
	if freezeHook then
		freezeHook(false)
	end
	World.fireRun("Resumed", { by = by, duration = duration })
	print(string.format("[GHS Pause] resumed by %s after %.1fs", by, duration))
	dirtyAll()
end

function Pause.vote(player: Player, on: boolean)
	if not World.isInParty(player) then
		return
	end
	if on and not Pause.canVote() then
		return
	end
	votes[player.UserId] = if on then true else nil
	dirtyAll()
	local n, need = voteCount(), #World.runAudience()
	World.fireRun("PauseVote", { name = player.Name, votes = n, needed = need, on = on })
	if on and n >= need then
		begin()
	end
end

-- While paused: toggle this player's extend or resume vote; when everyone agrees it happens (solo: at once).
local function pausedVote(player: Player, kind: string)
	if not paused or not World.isInParty(player) then
		return
	end
	local set = if kind == "extend" then extendVotes else resumeVotes
	set[player.UserId] = not set[player.UserId] or nil
	local need = #World.runAudience()
	if countIn(set) >= need then
		if kind == "extend" then
			table.clear(extendVotes)
			resumeAt += Config.PauseExtendSec
			World.fireRun("PauseExtended", { resumeAt = resumeAt, extendSec = Config.PauseExtendSec })
			print(string.format("[GHS Pause] extended by %ds", Config.PauseExtendSec))
		else
			Pause.resume(player.Name)
			return
		end
	end
	dirtyAll()
end

-- Debug: pause / resume at once, no vote.
function Pause.debugToggle(player: Player)
	if paused then
		Pause.resume(player.Name)
	elseif allowedState() then
		begin()
	end
end

-- A run ending or the hub: never stay paused.
function Pause.reset()
	if paused then
		Pause.resume("reset")
	end
	table.clear(votes)
end

function Pause.init()
	Remotes.PauseAction.OnServerEvent:Connect(function(player: Player, action: any)
		if action == "vote" then
			Pause.vote(player, true)
		elseif action == "unvote" then
			Pause.vote(player, false)
		elseif action == "extend" or action == "resume" then
			pausedVote(player, action)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		votes[player.UserId] = nil
		extendVotes[player.UserId] = nil
		resumeVotes[player.UserId] = nil
	end)
	RunService.Heartbeat:Connect(function(dt)
		if not paused then
			return
		end
		World.runClockPaused += dt -- the run clock (time survived) stands still
		World.intermissionEndsAt += dt
		for _, fn in tickHooks do
			fn(dt)
		end
		if not allowedState() or Workspace:GetServerTimeNow() >= resumeAt then
			Pause.resume("timer")
		end
	end)
end

return Pause
