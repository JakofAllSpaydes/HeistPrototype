--!strict
-- Growth per ability level for every upgradeable variable: stat at level = base x (1 + GrowthPct x level).
-- Keyed "<abilityId>.<variable>"; anything not listed uses Config.AbilityGrowthPct. 0.1 everywhere in the prototype.
local Config = require(script.Parent.Config)

local AbilityGrowth = {}

AbilityGrowth.GrowthPct = {} :: { [string]: number }

function AbilityGrowth.pct(abilityId: string, variable: string): number
	return AbilityGrowth.GrowthPct[abilityId .. "." .. variable] or Config.AbilityGrowthPct
end

-- base x (1 + pct x level)
function AbilityGrowth.at(abilityId: string, variable: string, base: number, level: number): number
	return base * (1 + AbilityGrowth.pct(abilityId, variable) * math.max(0, level))
end

return AbilityGrowth
