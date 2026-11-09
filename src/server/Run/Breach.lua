--!strict
-- Brief 13: the pre-heist start. On a map that opts in (Maps row `preHeist`, from Config.PreHeistMaps: THE BANK)
-- the run does not start on a clock. After the drive-in the crew stands on the street in the PreHeist state: no
-- spawning, no heat, no wave counter, no dealer; the intro crate is there, every hub-safe verb works, and the
-- front-door objective (Config.BreachDoorGroup) is called from the first second with MARLOW's line and the full
-- guide. Nothing pressures the crew but MARLOW's nag every PreHeistNagSec.
--
-- The breach fires on the first of: the door group opens (its minigame done), or any member's character root
-- enters the BreachZone volume while the door is still shut (they came in through a shot-out window), or debug
-- Breach now. It sounds the alarm for BreachAlarmSec, blows the doors open from inside (no reward: nobody held
-- them), sends `Breach` (the HEIST ON stamp) and hands back to Main, which starts wave 1 (the wave bell, the
-- clock, the heat, the first side job: SILENCE THE ALARM on its panel inside the lobby).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Maps = require(Shared.Maps)
local Lines = require(Shared.CrewCall.Lines)
local World = require(script.Parent.World)
local MapLoader = require(script.Parent.MapLoader)
local Doors = require(script.Parent.Doors)
local Alarms = require(script.Parent.Alarms)
local PlayerState = require(script.Parent.Parent.PlayerState)
local Log = require(script.Parent.Parent.Log)

local Breach = {}

Breach.requested = false -- debug Breach now
Breach.active = false -- the pre-heist is on (the crew has not gone in)
Breach.startedAt = 0 -- os.clock() the pre-heist began

-- Does this run open in the pre-heist? (The map opts in and its nodes loaded.)
function Breach.enabled(): boolean
	local row = Maps.get(World.map) :: any
	return row.preHeist == true and World.map == MapLoader.MAP_ID and MapLoader.loaded
end

-- Seconds idled before the breach so far (the live pre-heist), or the last run's total.
function Breach.idleSec(): number
	if Breach.active then
		return os.clock() - Breach.startedAt
	end
	return World.idleBeforeBreach
end

-- The member standing in the breach zone while the door is shut, if any.
local function windowEntry(): Player?
	for _, p in World.partyPlayers() do
		local char = p.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and PlayerState.isStanding(PlayerState.get(p)) then
			if MapLoader.zoneAt(root.Position) == Config.BreachZone then
				return p
			end
		end
	end
	return nil
end

local function fire(how: string, who: Player?)
	local idle = os.clock() - Breach.startedAt
	Breach.active = false
	World.idleBeforeBreach = idle
	World.phase = "run"
	MapLoader.markBreach()
	local group = Config.BreachDoorGroup
	Alarms.pulse("breach", Config.BreachAlarmSec)
	if not Doors.isOpen(group) then
		-- Blown open from inside: the door's break, shake and zone burst, the call cleared with no reward.
		Doors.open(group, nil, "breach")
	end
	World.fireRun("Breach", {
		how = how,
		name = if who then who.Name else nil,
		alarmSec = Config.BreachAlarmSec,
		stamp = Lines.preHeist.stamp,
	})
	Log.event("Breach", "%s via %s t=%d", if who then who.Name else "debug", how, math.round(idle))
end

-- Yields through the pre-heist until the breach (or the run ends: the party left, debug reset). `setState` is
-- Main's (it marks every member's state dirty).
function Breach.waitForBreach(setState: (string) -> ())
	Breach.requested = false
	Breach.active = true
	Breach.startedAt = os.clock()
	World.phase = "preheist"
	World.idleBeforeBreach = 0
	setState("PreHeist")
	Log.event("Breach", "pre-heist on %s: the crew is on the street, %s called", World.map, Config.BreachDoorGroup)
	Doors.callNow(Config.BreachDoorGroup, Lines.preHeist.doorLine)
	local nagAt = os.clock() + Config.PreHeistNagSec
	local nagIndex = 0
	while not World.runOver do
		local opener: Player? = nil
		if Doors.isOpen(Config.BreachDoorGroup) then
			local log = Doors.openedLog
			local last = log[#log]
			for _, p in World.partyPlayers() do
				if last and p.Name == last.by then
					opener = p
				end
			end
			fire("door", opener)
			return
		end
		local inside = windowEntry()
		if inside then
			fire("window", inside)
			return
		end
		if Breach.requested then
			fire("debug", nil)
			return
		end
		if Config.PreHeistNagSec > 0 and os.clock() >= nagAt then
			nagAt = os.clock() + Config.PreHeistNagSec
			local lines = Lines.preHeistNag
			if #lines > 0 then
				nagIndex = nagIndex % #lines + 1
				World.fireRun("CrewLine", {
					kind = "door",
					crewLead = Lines.door.crewLead,
					typeLabel = Lines.preHeist.nagLabel,
					text = { lines[nagIndex] },
					hold = Config.CallHoldSec,
				})
				Log.event("Breach", "MARLOW nag %d at t=%d", nagIndex, math.round(os.clock() - Breach.startedAt))
			end
		end
		task.wait(0.1)
	end
	Breach.active = false
	World.phase = "run"
end

-- Run end / hub: nothing pending.
function Breach.resetRun()
	Breach.requested = false
	Breach.active = false
	World.phase = "run"
end

return Breach
