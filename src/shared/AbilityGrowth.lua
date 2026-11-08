--!strict
-- Growth per ability level for every upgradeable variable: stat at level = base x (1 + GrowthPct x level), or the
-- soft-capped curve for ranges, slows, durations and buff percentages (Round 24ae, Config.AbilitySoftCap*).
-- Keyed "<abilityId>.<variable>"; anything not listed uses Config.AbilityGrowthPct. 0.1 everywhere in the prototype.
local Config = require(script.Parent.Config)

local AbilityGrowth = {}

AbilityGrowth.GrowthPct = {} :: { [string]: number }

function AbilityGrowth.pct(abilityId: string, variable: string): number
	return AbilityGrowth.GrowthPct[abilityId .. "." .. variable] or Config.AbilityGrowthPct
end

-- Round 24ae: the soft cap for a variable, as the most it can ever add (a multiple of base), or nil for straight-line
-- growth. An exact "<abilityId>.<variable>" entry in Config.AbilitySoftCap wins; otherwise the longest matching
-- name suffix in Config.AbilitySoftCapBy (Radius, Range, SlowPct, Duration, Pct, Pierce...). Damage, heal, HP and
-- DPS match nothing and keep growing in a straight line.
function AbilityGrowth.cap(abilityId: string, variable: string): number?
	local exact = (Config.AbilitySoftCap :: any)[abilityId .. "." .. variable]
	if exact then
		return exact
	end
	local best: number? = nil
	local bestLen = 0
	for suffix, cap in Config.AbilitySoftCapBy :: any do
		local n = #suffix
		if n > bestLen and string.sub(variable, -n) == suffix then
			best, bestLen = cap, n
		end
	end
	return best
end

-- Straight line: base x (1 + pct x level). Soft-capped variables start at the same slope and ease toward
-- base x (1 + cap): base x (1 + cap x (1 - e^(-pct x level / cap))). So a flashbang's radius grows like before for
-- the first levels, then levels off instead of covering the map.
function AbilityGrowth.at(abilityId: string, variable: string, base: number, level: number): number
	local pct = AbilityGrowth.pct(abilityId, variable)
	local lv = math.max(0, level)
	local cap = AbilityGrowth.cap(abilityId, variable)
	if cap and cap > 0 then
		return base * (1 + cap * (1 - math.exp(-pct * lv / cap)))
	end
	return base * (1 + pct * lv)
end

return AbilityGrowth
