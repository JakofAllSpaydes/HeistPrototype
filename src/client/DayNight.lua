--!strict
-- Round 21: the run's clock. Wave 1 starts at Config.RunClockStart (night) and every wave moves the clock on by
-- Config.RunClockPerWave hours, eased over Config.RunClockTweenSec as the wave starts. Lighting is one per server
-- and runs share a server (brief 8 slots), so each client drives its own Lighting from its own sync; the hub keeps
-- the place's own ClockTime (read once at load).
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))

local DayNight = {}

local hubClock = Lighting.ClockTime
local target: number? = nil -- the clock this wave sits at (nil = the hub's)
local from = hubClock
local delta = 0 -- forward hours from `from` to the target
local startedAt = 0
local animating = false

local function clockFor(wave: number): number
	return (Config.RunClockStart + math.max(0, wave - 1) * Config.RunClockPerWave) % 24
end

local function goTo(clock: number, snap: boolean)
	local cur = Lighting.ClockTime
	local d = (clock - cur) % 24 -- always forward (23:30 -> 00:00 is half an hour, not back round the dial)
	if snap or d > Config.RunClockMaxTweenHours or Config.RunClockTweenSec <= 0 then
		Lighting.ClockTime = clock
		animating = false
		return
	end
	from, delta, startedAt, animating = cur, d, os.clock(), true
end

function DayNight.init()
	ClientState.Changed:Connect(function(sync: any)
		local inRun = sync ~= nil and sync.waveState ~= "Hub" and typeof(sync.wave) == "number" and sync.wave > 0
		local want = if inRun then clockFor(sync.wave) else nil
		if want == target then
			return
		end
		local wasHub = target == nil
		target = want
		-- Entering a run or going back to the hub jumps; wave to wave eases forward.
		goTo(want or hubClock, wasHub or want == nil)
	end)
	RunService.Heartbeat:Connect(function()
		if not animating then
			return
		end
		local t = math.clamp((os.clock() - startedAt) / Config.RunClockTweenSec, 0, 1)
		local eased = t * t * (3 - 2 * t)
		Lighting.ClockTime = (from + delta * eased) % 24
		if t >= 1 then
			animating = false
		end
	end)
end

return DayNight
