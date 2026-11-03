--!strict
-- Wave state shared by every server module. GameLoop writes, everyone else reads.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local World = {
	heat = Config.HeatStart, -- stars, 0..5
	wave = 1,
	state = "Intro", -- Intro | Wave | Intermission
	intermissionEndsAt = 0, -- server time (workspace:GetServerTimeNow())
	pendingWave = nil :: number?, -- set by debug: next loop iteration jumps here
	skipRequested = false, -- set by debug: end the current wave / intermission now
	spawnsPaused = false,
}

-- Heat moves in half-star steps. Everyone sees the change; PlayerState resends on the next flush.
World.heatDirty = false
function World.addHeat(delta: number, reason: string)
	if delta == 0 then
		return
	end
	local before = World.heat
	World.heat = math.clamp(math.round((before + delta) * 2) / 2, 0, 5)
	if World.heat == before then
		return
	end
	World.heatDirty = true
	Remotes.Juice:FireAllClients("HeatChanged", { delta = World.heat - before, value = World.heat, reason = reason })
	print(
		string.format(
			"[GHS Heat] %s: %.1f -> %.1f (%s)",
			reason,
			before,
			World.heat,
			if delta > 0 then "up" else "down"
		)
	)
end

return World
