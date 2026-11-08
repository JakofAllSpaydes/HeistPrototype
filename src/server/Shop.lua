--!strict
-- Brief 6: the non-purchase store actions behind Remotes.Shop (claims, rerolls, the VIP gift, banked crate opens),
-- routed to whichever module registered them, plus the bundle purchase kind. Every action returns
-- { ok, reason?, data? } and resyncs the player.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local Bundles = require(Shared.Bundles)
local Rewards = require(Shared.Rewards)
local DailyShop = require(Shared.DailyShop)
local Clock = require(Shared.Clock)
local Profiles = require(script.Parent.Profiles)
local PlayerState = require(script.Parent.PlayerState)
local Purchases = require(script.Parent.Purchases)
local Grants = require(script.Parent.Grants)
local Boosts = require(script.Parent.Boosts)
local Log = require(script.Parent.Log)

export type Result = { ok: boolean, reason: string?, data: any? }

local Shop = {}
local actions: { [string]: (Player, Profiles.Profile, any) -> Result } = {}

function Shop.register(action: string, fn: (Player, Profiles.Profile, any) -> Result)
	actions[action] = fn
end

------------------------------------------------------------------ Bundles
-- One write grants everything not yet owned (owned rows were taken off the price); the client plays the stacked
-- reveal from the results.
Purchases.register("bundle", {
	check = function(_player, profile, product)
		local b = product.bundleId and Bundles.ById[product.bundleId]
		if not b then
			return "Unknown bundle"
		end
		local _, owned = Bundles.priceFor(b, profile)
		local all = true
		for i in b.contents do
			if not owned[i] then
				all = false
			end
		end
		if all then
			return "You own everything in this bundle"
		end
		return nil
	end,
	grant = function(player, _profile, product)
		local b = Bundles.ById[product.bundleId :: string]
		local list: { Rewards.Reward } = {}
		for _, c in b.contents do
			table.insert(list, { kind = c.kind, id = c.id, amount = c.amount, sec = c.sec })
		end
		local target: string? = nil
		for _, c in b.contents do
			if c.kind == "wrap" and c.id then
				target = Bundles.WrapTarget[c.id]
			end
		end
		local results = Grants.applyAll(player, list, { source = b.id, owned = "skip", wrapOn = target })
		return { bundleId = b.id, results = results }
	end,
})

------------------------------------------------------------------ FEATURED daily items (Round 17c)
Purchases.register("item", {
	check = function(_player, profile, product)
		local r = { kind = product.itemKind or "", id = product.itemId }
		if Rewards.owned(profile, r) then
			return "Already owned"
		end
		local day = Clock.day(Clock.fake(os.time(), profile))
		if not DailyShop.offeredOn(day, r.kind, r.id or "", DailyShop.rerollsOn(profile, day)) then
			return "That item has left the shop"
		end
		return nil
	end,
	grant = function(player, _profile, product)
		local res = Grants.apply(
			player,
			{ kind = product.itemKind :: string, id = product.itemId },
			{ source = product.id, owned = "skip" }
		)
		return { results = { res } }
	end,
})

-- Round 18: REROLL on DAILY ITEMS. A fresh draw for this profile today (the count resets with the fake day).
Purchases.register("daily_reroll", {
	grant = function(_player, profile, _product)
		local day = Clock.day(Clock.fake(os.time(), profile))
		local count = DailyShop.rerollsOn(profile, day) + 1
		profile.dailyReroll = { day = day, count = count }
		return { day = day, rerolls = count }
	end,
})

------------------------------------------------------------------ Boosts
-- Timed: buying an active boost extends it.
Purchases.register("boost", {
	grant = function(player, _profile, product)
		local expiresAt = Boosts.extend(player, product.boostId :: string, product.sec or 0)
		return { boostId = product.boostId, expiresAt = expiresAt }
	end,
})

function Shop.init()
	Remotes.Shop.OnServerInvoke = function(player: Player, action: any, args: any): Result
		local fn = actions[tostring(action)]
		if not fn then
			return { ok = false, reason = "Unknown action" }
		end
		local profile = Profiles.get(player)
		if not profile then
			return { ok = false, reason = "Profile loading" }
		end
		local ok, res = pcall(fn, player, profile, args)
		if not ok then
			Log.event("Shop", "%s: %s failed: %s", player.Name, tostring(action), tostring(res))
			return { ok = false, reason = "Server error" }
		end
		Profiles.markDirty(player)
		PlayerState.get(player).dirty = true
		return res
	end
end

return Shop
