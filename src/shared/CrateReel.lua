--!strict
-- Crate reel timing, shared so the server ejects the gun the moment every client's reel lands.
-- CrateReelSteps icons, CrateReelSec each; the last two steps stretch by CrateReelEase (the ease-out).
local Config = require(script.Parent.Config)

local CrateReel = {}

-- Seconds each reel step holds, in order. The last entry is the landed weapon.
function CrateReel.steps(): { number }
	local n = math.max(1, Config.CrateReelSteps)
	local out = {}
	for i = 1, n do
		local mult = 1
		if i == n then
			mult = Config.CrateReelEase[2] or 1
		elseif i == n - 1 then
			mult = Config.CrateReelEase[1] or 1
		end
		out[i] = Config.CrateReelSec * mult
	end
	return out
end

-- From F to the land (the last icon appears).
function CrateReel.landSec(): number
	local steps = CrateReel.steps()
	local t = 0
	for i = 1, #steps - 1 do
		t += steps[i]
	end
	return t
end

-- From F to the gun leaving the crate: the land plus the hold on the landed icon.
function CrateReel.ejectSec(): number
	return CrateReel.landSec() + Config.CrateLandHoldSec
end

return CrateReel
