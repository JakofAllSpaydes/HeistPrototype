--!strict
-- Brief 6: revive token packs (the BOOSTS tab's bottom row, the hub token chip, GET TOKENS while downed).
local ReviveTokenPacks = {
	List = {
		{ id = "tokens_5", name = "5 REVIVE TOKENS", tokens = 5, price = 99 },
		{ id = "tokens_25", name = "25 REVIVE TOKENS", tokens = 25, price = 399, tag = "POPULAR" },
		{ id = "tokens_100", name = "100 REVIVE TOKENS", tokens = 100, price = 1299, tag = "BEST VALUE" },
	},
	Nudge = "tokens_5", -- the pack the zero-token GET TOKENS sheet opens on
}

return ReviveTokenPacks
