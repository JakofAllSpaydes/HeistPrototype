--!strict
-- Brief 6: the GOLD tab's six packs. The BEST VALUE tag goes on the pack with the most Gold per Robux.
local GoldPacks = {
	List = {
		{ id = "gold_pouch", name = "POUCH", gold = 1000, price = 99 },
		{ id = "gold_stack", name = "STACK", gold = 3000, price = 249 },
		{ id = "gold_case", name = "CASE", gold = 7500, price = 499 },
		{ id = "gold_duffel", name = "DUFFEL", gold = 16000, price = 999 },
		{ id = "gold_vault", name = "VAULT", gold = 35000, price = 1999 },
		{ id = "gold_reserve", name = "RESERVE", gold = 80000, price = 3999 },
	},
}

-- R$ per 100 Gold (the value line under each pack).
function GoldPacks.per100(pack: { gold: number, price: number }): number
	return pack.price / pack.gold * 100
end

function GoldPacks.bestValueId(): string
	local best, bestV = "", math.huge
	for _, p in GoldPacks.List do
		local v = GoldPacks.per100(p)
		if v < bestV then
			best, bestV = p.id, v
		end
	end
	return best
end

return GoldPacks
