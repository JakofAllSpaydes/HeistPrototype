--!strict
-- Brief 6: the non-purchase store actions behind Remotes.Shop (claims, rerolls, the VIP gift, banked crate opens),
-- routed to whichever module registered them, plus the bundle purchase kind. Every action returns
-- { ok, reason?, data? } and resyncs the player.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local Bundles = require(Shared.Bundles)
local Rewards = require(Shared.Rewards)
local Profiles = require(script.Parent.Profiles)
local PlayerState = require(script.Parent.PlayerState)
local Purchases = require(script.Parent.Purchases)
local Grants = require(script.Parent.Grants)
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
