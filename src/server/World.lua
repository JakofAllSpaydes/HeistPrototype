--!strict
-- Wave state shared by every server module. GameLoop writes, everyone else reads.
local World = {
	wave = 1,
	state = "Intro", -- Intro | Wave | Intermission
	intermissionEndsAt = 0, -- server time (workspace:GetServerTimeNow())
	pendingWave = nil :: number?, -- set by debug: next loop iteration jumps here
	skipRequested = false, -- set by debug: end the current wave / intermission now
	spawnsPaused = false,
}

return World
