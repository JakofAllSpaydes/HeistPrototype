--!strict
-- Downed / revive / bleed-out / game over. 0 HP downs a player instead of killing them: crawl speed, no
-- fire, a bleed timer, enemies ignore them. A standing teammate within ReviveRadius holds F (mobile: the
-- REVIVE button) for ReviveHoldSec, or the SELF-REVIVE button, stands them up. Bleeding out removes the
-- character and makes them a spectator; REVIVE EVERYBODY stands the whole crew up where they fell. The run
-- is over when nobody is standing and nobody is still bleeding.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local PlayerState = require(script.Parent.PlayerState)
local World = require(script.Parent.World)
local Log = require(script.Parent.Log)
local WeaponRoll = require(script.Parent.WeaponRoll)
local Heat = require(script.Parent.Heat)

local Downed = {}

-- Sidearm: the held gun is stowed and a Common DownedPistolId (at its own Armory level, full mag) takes
-- its place. Revive hands the stowed gun back exactly (same uid, the mag it had: the record carries the
-- last count the client reported); bleed-out drops it on the floor with that mag.
local function giveSidearm(state: PlayerState.State)
	if not Config.DownedCanShoot or state.stowed then
		return
	end
	state.stowed = state.held
	local pistol = Config.DownedPistolId
	PlayerState.setHeld(state, pistol, 1, PlayerState.weaponLevel(state, pistol))
	Log.event("Downed", "%s stowed %s and drew the %s sidearm", state.player.Name, state.stowed.weaponId, pistol)
end

local function restoreStowed(state: PlayerState.State)
	local stowed = state.stowed
	if not stowed then
		return
	end
	state.stowed = nil
	state.held = stowed -- same uid and mag: the client loads what the record says
	PlayerState.refreshHeldVisual(state)
	state.dirty = true
	Log.event("Downed", "%s has %s back", state.player.Name, stowed.weaponId)
end

local function dropStowed(state: PlayerState.State, position: Vector3)
	local stowed = state.stowed
	if not stowed then
		return
	end
	state.stowed = nil
	local cf = CFrame.new(position.X, Config.FloorTop + 0.35, position.Z)
		* CFrame.Angles(0, math.random() * math.pi * 2, 0)
		* CFrame.Angles(0, 0, math.rad(math.random(-12, 12)))
	WeaponRoll.dropGun(state, stowed, cf)
	Log.event("Downed", "%s's %s dropped on the floor", state.player.Name, stowed.weaponId)
end

local holding: { [Player]: boolean } = {}
local lastSent: { [Player]: number } = {}

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function humanoidOf(player: Player): Humanoid?
	local char = player.Character
	return if char then char:FindFirstChildOfClass("Humanoid") else nil
end

local function rootOf(player: Player): BasePart?
	local char = player.Character
	return if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

local function sendProgress(target: Player, reviver: Player?, progress: number, force: boolean)
	local t = os.clock()
	if not force and t - (lastSent[target] or 0) < 0.1 then
		return
	end
	lastSent[target] = t
	World.fireRun("ReviveProgress", {
		userId = target.UserId,
		name = target.Name,
		reviverId = if reviver then reviver.UserId else nil,
		reviver = if reviver then reviver.Name else nil,
		progress = progress,
		bleedEndsAt = PlayerState.get(target).bleedEndsAt, -- moves while a hold pauses the bleed
	})
end

-- The run ends when no player is on their feet and none is still bleeding (every bleed can self-revive).
function Downed.checkRunOver()
	if not World.inRun() or World.runOver then
		return
	end
	for _, player in World.runAudience() do
		local state = PlayerState.get(player)
		if state.downed or PlayerState.isStanding(state) then
			return
		end
	end
	World.runOver = true
	World.skipRequested = true
	Log.event("Run", "nobody standing or bleeding: run over at wave %d", World.wave)
end

function Downed.down(player: Player)
	local state = PlayerState.get(player)
	local hum = humanoidOf(player)
	if state.downed or state.bledOut or not hum then
		return
	end
	state.downed = true
	state.downs += 1
	state.bleedEndsAt = now() + Config.BleedOutSec
	state.reviveProgress = 0
	state.reviver = nil
	state.buffId = nil
	state.buffUntil = 0
	state.savedJump = { useJumpPower = hum.UseJumpPower, jumpPower = hum.JumpPower, jumpHeight = hum.JumpHeight }
	hum.Health = 1
	hum.UseJumpPower = true
	hum.JumpPower = 0
	hum.WalkSpeed = Config.DownedWalkSpeed
	giveSidearm(state)
	state.dirty = true
	Remotes.Juice:FireClient(player, "Downed", {
		bleedEndsAt = state.bleedEndsAt,
		selfRevives = state.selfRevives,
		canShoot = Config.DownedCanShoot,
	})
	World.fireRun("PlayerDowned", { userId = player.UserId, name = player.Name, bleedEndsAt = state.bleedEndsAt })
	Heat.onDowned() -- counts against this wave's score (capped), lands at its end
	Log.event("Downed", "%s is down (down #%d), bleeds out in %ds", player.Name, state.downs, Config.BleedOutSec)
end

function Downed.standUp(player: Player, hpPct: number, by: string)
	local state = PlayerState.get(player)
	local hum = humanoidOf(player)
	if not hum then
		return
	end
	state.downed = false
	state.bledOut = false
	state.reviveProgress = 0
	state.reviver = nil
	local saved = state.savedJump
	if saved then
		hum.UseJumpPower = saved.useJumpPower
		hum.JumpPower = saved.jumpPower
		hum.JumpHeight = saved.jumpHeight
		state.savedJump = nil
	else
		hum.UseJumpPower = false
		hum.JumpHeight = 7.2
	end
	hum.Health = math.max(1, math.floor(hum.MaxHealth * hpPct / 100))
	restoreStowed(state)
	PlayerState.applyCharacterStats(state)
	state.invulnUntil = now() + Config.ReviveInvulnSec
	state.dirty = true
	Remotes.Juice:FireClient(player, "Revived", { by = by, hpPct = hpPct })
	World.fireRun("PlayerRevived", { userId = player.UserId, name = player.Name, by = by })
	Log.event("Downed", "%s stood up (%s) at %d%% HP", player.Name, by, hpPct)
end

function Downed.bleedOut(player: Player)
	local state = PlayerState.get(player)
	if not state.downed then
		return
	end
	state.downed = false
	state.bledOut = true
	state.reviveProgress = 0
	state.reviver = nil
	local root = rootOf(player)
	if root then
		state.lastPosition = root.Position
	end
	dropStowed(state, state.lastPosition)
	state.dirty = true
	Remotes.Juice:FireClient(player, "BledOut", {})
	World.fireRun("PlayerBledOut", { userId = player.UserId, name = player.Name })
	Log.event("Downed", "%s bled out", player.Name)
	local char = player.Character
	player.Character = nil
	if char then
		char:Destroy()
	end
	Downed.checkRunOver()
end

-- Everyone downed or bled out stands up at ReviveHPPct where they fell. Free, counted per buyer.
function Downed.reviveEverybody(buyer: Player?)
	local who = if buyer then buyer.Name else "DEBUG"
	local count = 0
	for _, player in World.runAudience() do
		local state = PlayerState.get(player)
		if state.bledOut then
			count += 1
			state.bledOut = false
			state.pendingSpawnCFrame = CFrame.new(state.lastPosition + Vector3.new(0, 1, 0))
			player:LoadCharacter()
			task.spawn(function()
				local char = player.Character or player.CharacterAdded:Wait()
				char:WaitForChild("Humanoid", 5)
				char:WaitForChild("HumanoidRootPart", 5)
				task.wait()
				Downed.standUp(player, Config.ReviveHPPct, who)
			end)
		elseif state.downed then
			count += 1
			Downed.standUp(player, Config.ReviveHPPct, who)
		end
	end
	if buyer then
		local bs = PlayerState.get(buyer)
		bs.reviveAllUsed += 1
		bs.dirty = true
	end
	World.fireRun("CrewRevived", { name = who, count = count })
	Log.event("Downed", "%s revived the crew (%d players)", who, count)
end

local function onHold(player: Player, on: any)
	holding[player] = on == true
end

local function onSelfRevive(player: Player)
	local state = PlayerState.get(player)
	if not state.downed then
		return
	end
	state.selfRevives += 1
	Downed.standUp(player, Config.SelfReviveHPPct, "self")
end

local function onGiveUp(player: Player)
	local state = PlayerState.get(player)
	if state.downed then
		Log.event("Downed", "%s gave up", player.Name)
		Downed.bleedOut(player)
	end
end

local function onReviveEverybody(player: Player)
	local state = PlayerState.get(player)
	if not state.bledOut then
		return
	end
	if World.state == "RunOver" then
		-- Inside the run-over window: the crew stands up and the run resumes (GameLoop watches runOver).
		Downed.reviveEverybody(player)
		World.runOver = false
		World.skipRequested = false
		Log.event("Run", "%s revived the crew on the run over screen: second chance", player.Name)
	elseif World.inRun() then
		Downed.reviveEverybody(player)
	end
	-- Any later press (run end, summary) is ignored.
end

-- Nearest downed player within ReviveRadius of a point, excluding `except`.
local function nearestDowned(from: Vector3, except: Player): Player?
	local best: Player? = nil
	local bestDist = Config.ReviveRadius
	for _, player in World.runAudience() do
		if player == except then
			continue
		end
		local state = PlayerState.get(player)
		local root = rootOf(player)
		if state.downed and root then
			local d = (root.Position - from).Magnitude
			if d <= bestDist then
				bestDist = d
				best = player
			end
		end
	end
	return best
end

function Downed.init()
	PlayerState.onZeroHP = Downed.down
	Remotes.ReviveHold.OnServerEvent:Connect(onHold)
	Remotes.SelfRevive.OnServerEvent:Connect(onSelfRevive)
	Remotes.GiveUp.OnServerEvent:Connect(onGiveUp)
	Remotes.ReviveEverybody.OnServerEvent:Connect(onReviveEverybody)
	Players.PlayerRemoving:Connect(function(player)
		holding[player] = nil
		lastSent[player] = nil
		task.delay(0.1, Downed.checkRunOver)
	end)

	RunService.Heartbeat:Connect(function(dt)
		local t = now()
		-- Bleed timers.
		for _, player in World.runAudience() do
			local state = PlayerState.get(player)
			if state.downed and t >= state.bleedEndsAt then
				Downed.bleedOut(player)
			end
		end
		-- Revive holds: a standing holder feeds progress into the nearest downed player in range.
		local progressed: { [Player]: Player } = {}
		for reviver, on in holding do
			if not on or not reviver.Parent then
				continue
			end
			local rs = PlayerState.get(reviver)
			local rroot = rootOf(reviver)
			if not rroot or not PlayerState.isStanding(rs) then
				continue
			end
			local target = nearestDowned(rroot.Position, reviver)
			if target then
				local ts = PlayerState.get(target)
				if ts.reviver == nil or ts.reviver == reviver then
					ts.reviver = reviver
					ts.reviveProgress = math.min(1, ts.reviveProgress + dt / math.max(Config.ReviveHoldSec, 0.1))
					progressed[target] = reviver
					if Config.RevivePausesBleed then
						-- The bleed timer stands still for as long as the hold lasts.
						ts.bleedEndsAt += dt
					end
				end
			end
		end
		for _, player in World.runAudience() do
			local ts = PlayerState.get(player)
			if not ts.downed then
				continue
			end
			local reviver = progressed[player]
			if reviver then
				local full = ts.reviveProgress >= 1
				sendProgress(player, reviver, ts.reviveProgress, full)
				if full then
					ts.reviveProgress = 0
					ts.reviver = nil
					local rs = PlayerState.get(reviver)
					rs.revives += 1
					rs.dirty = true
					Downed.standUp(player, Config.ReviveHPPct, reviver.Name)
				end
			elseif ts.reviveProgress > 0 or ts.reviver then
				-- Released early or walked away: the ring resets.
				ts.reviveProgress = 0
				ts.reviver = nil
				sendProgress(player, nil, 0, true)
			end
		end
	end)
end

return Downed
