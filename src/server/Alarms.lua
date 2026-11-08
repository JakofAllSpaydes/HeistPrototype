--!strict
-- Round 19c: the building alarm. THE BANK's asset has alarm fixtures on its walls (geometry parts named in
-- Config.AlarmPartNames); while any source holds the alarm on they strobe red with a light, and every client in
-- the run plays the alarm (a horn every AlarmHornEverySec and a faint red pulse at the screen's edge). Sources:
--   vault    - the vault's gas warning (beside the vault room's own red strobe)
--   heat     - a whole star gained: a short pulse (AlarmHeatUpSec)
--   job      - SILENCE THE ALARM, until the panel is shut off or the job runs out
--   zonegas  - the zone gas warning (ZoneGas.lua)
-- The arena has no fixtures: there it is the client half only.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local World = require(script.Parent.World)
local Log = require(script.Parent.Log)
-- No MapLoader require: VaultJob -> Alarms, and MapLoader -> CrewCall -> VaultJob would cycle.

local Alarms = {}

type Fixture = { part: BasePart, color: Color3, transparency: number, material: Enum.Material, light: PointLight }

local RED = Color3.fromRGB(255, 60, 50)
local fixtures: { Fixture } = {}
local sources: { [string]: boolean } = {}
local pulses: { [string]: number } = {} -- source -> token of its running pulse
local ringing = false
local token = 0

local function anyOn(): boolean
	return next(sources) ~= nil
end

local function paint(on: boolean)
	for _, f in fixtures do
		if f.part.Parent then
			f.part.Color = if on then RED else f.color
			f.part.Material = if on then Enum.Material.Neon else f.material
			f.part.Transparency = if on then 0 else f.transparency
			f.light.Enabled = on
		end
	end
end

local function startStrobe()
	token += 1
	local my = token
	task.spawn(function()
		local on = true
		while my == token and ringing do
			-- Only the bank's fixtures strobe; the arena has none and THE BANK's are off-map on the arena.
			if World.map ~= "Arena" then
				paint(on)
			end
			on = not on
			task.wait(Config.AlarmStrobeSec)
		end
		paint(false)
	end)
end

local function refresh(reason: string)
	local want = anyOn()
	if want == ringing then
		return
	end
	ringing = want
	if want then
		startStrobe()
	else
		token += 1
		paint(false)
	end
	World.fireRun("Alarm", { on = want })
	Log.event("Alarm", "%s (%s)", if want then "ringing" else "quiet", reason)
end

-- Hold the alarm on (or let go) for `source`.
function Alarms.set(source: string, on: boolean)
	if (sources[source] == true) == on then
		return
	end
	sources[source] = if on then true else nil
	pulses[source] = nil
	refresh(source)
end

-- On for `sec`, then off (a later pulse or set from the same source takes over).
function Alarms.pulse(source: string, sec: number)
	if sec <= 0 then
		return
	end
	Alarms.set(source, true)
	local my = (pulses[source] or 0) + 1
	pulses[source] = my
	task.delay(sec, function()
		if pulses[source] == my then
			Alarms.set(source, false)
		end
	end)
end

function Alarms.isRinging(): boolean
	return ringing
end

-- Run start / hub: quiet.
function Alarms.resetRun()
	sources = {}
	pulses = {}
	refresh("reset")
end

function Alarms.init()
	local bank = Workspace:FindFirstChild("Bank")
	local geo = bank and bank:FindFirstChild("Geometry")
	if geo then
		for _, d in geo:GetDescendants() do
			if d:IsA("BasePart") and table.find(Config.AlarmPartNames, d.Name) then
				local light = Instance.new("PointLight")
				light.Name = "AlarmLight"
				light.Color = RED
				light.Range = Config.AlarmLightRange
				light.Brightness = 3
				light.Enabled = false
				light.Parent = d
				table.insert(fixtures, {
					part = d,
					color = d.Color,
					transparency = d.Transparency,
					material = d.Material,
					light = light,
				})
			end
		end
	end
	-- A whole star gained: a short burst of alarm (Heat goes through World.addHeat).
	World.onStarUp = function(_stars: number)
		Alarms.pulse("heat", Config.AlarmHeatUpSec)
	end
	Log.event("Alarm", "%d alarm fixtures", #fixtures)
end

return Alarms
