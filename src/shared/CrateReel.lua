--!strict
-- Crate reel timing, shared so the server ejects each gun the moment every client's reel lands. One F plays every
-- roll the crate holds back to back: each is the sliding row of icons (RollDurationSec, ease-out onto the landed
-- gun), a hold on the result (RollLandHoldSec, longer from Epic up), the eject, then CrateRollGapSec to the next.
local Config = require(script.Parent.Config)

local CrateReel = {}

CrateReel.Cells = 18 -- icons in the row
CrateReel.Land = 14 -- the landed gun's cell; the cells after it make the stop read as a stop

-- From the roll starting to the gun leaving the crate.
function CrateReel.ejectSec(rarity: number): number
	return Config.RollDurationSec + Config.RollLandHoldSec + (if rarity >= 4 then Config.RollHighTierHoldSec else 0)
end

-- From one roll starting to the next one starting.
function CrateReel.rollSec(rarity: number): number
	return CrateReel.ejectSec(rarity) + Config.RollEjectSec + Config.CrateRollGapSec
end

return CrateReel
