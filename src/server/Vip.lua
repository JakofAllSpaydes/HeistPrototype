--!strict
-- Brief 6: VIP, a fake monthly subscription (profile.vip = { active, since, renewsAt, ever } on the fake clock).
-- Subscribing goes through the purchase sheet (Config.VipPrice / month): the VIP mask and the two VIP poses (kept
-- for good), VipMonthlyTokens revive tokens, and while active the VIP tag everywhere, a permanent +VipCashPct
-- CASH boost in runs (Boosts.cashMult), and the VipDailyGold gift once per fake UTC day.
-- Each fake renewal charges the fake balance again and pays the tokens; a short balance lapses it. CANCEL stops the
-- perks and keeps the cosmetics; a lapsed player gets the WELCOME BACK card in the VIP tab.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Clock = require(Shared.Clock)
local Remotes = require(Shared.Remotes)
local Profiles = require(script.Parent.Profiles)
local PlayerState = require(script.Parent.PlayerState)
local Purchases = require(script.Parent.Purchases)
local Grants = require(script.Parent.Grants)
local Shop = require(script.Parent.Shop)
local Hub = require(script.Parent.Hub)
local Log = require(script.Parent.Log)

local Vip = {}

Vip.Cosmetics = {
	{ kind = "mask", id = "vip_gold" },
	{ kind = "emote", id = "vip_stadium" },
	{ kind = "emote", id = "vip_tilt" },
}

local PERIOD = Config.VipPeriodDays * 86400

function Vip.active(player: Player): boolean
	local p = Profiles.get(player)
	return p ~= nil and p.vip.active == true
end

local function fakeNow(profile: Profiles.Profile): number
	return Clock.fake(os.time(), profile)
end

local function changed(player: Player)
	Profiles.markDirty(player)
	PlayerState.get(player).dirty = true
	Hub.refreshTag(player)
end

Purchases.register("vip", {
	check = function(_player, profile)
		if profile.vip.active then
			return "You are already a VIP"
		end
		return nil
	end,
	grant = function(player, profile)
		local now = fakeNow(profile)
		profile.vip.active = true
		profile.vip.since = now
		profile.vip.renewsAt = now + PERIOD
		profile.vip.ever = true
		local results = Grants.applyAll(player, Vip.Cosmetics :: any, { source = "vip", owned = "skip" })
		Grants.apply(player, { kind = "tokens", amount = Config.VipMonthlyTokens }, { source = "vip subscribe" })
		changed(player)
		Log.event("VIP", "%s subscribed (fake), renews in %dd", player.Name, Config.VipPeriodDays)
		return { results = results }
	end,
})

-- CANCEL (fake): the perks stop now; the mask and poses stay owned.
Shop.register("vipCancel", function(player, profile)
	if not profile.vip.active then
		return { ok = false, reason = "Not subscribed" }
	end
	profile.vip.active = false
	profile.vip.renewsAt = 0
	changed(player)
	Log.event("VIP", "%s cancelled (fake): perks off, cosmetics kept", player.Name)
	return { ok = true }
end)

-- The daily Gold gift (the one Gold perk, framed as a gift).
Shop.register("vipGift", function(player, profile)
	if not profile.vip.active then
		return { ok = false, reason = "VIP only" }
	end
	local day = Clock.day(fakeNow(profile))
	if profile.vipGiftDay >= day then
		return { ok = false, reason = "Already claimed today" }
	end
	profile.vipGiftDay = day
	Grants.apply(player, { kind = "gold", amount = Config.VipDailyGold }, { source = "vip daily gift" })
	Log.event("VIP", "%s claimed the daily gift +%d gold", player.Name, Config.VipDailyGold)
	return { ok = true, data = { gold = Config.VipDailyGold } }
end)

-- A fake renewal is due: charge the fake balance and pay the monthly tokens, or lapse.
local function tick(player: Player)
	local profile = Profiles.get(player)
	if not profile or not profile.vip.active then
		return
	end
	local now = fakeNow(profile)
	local guard = 0
	while profile.vip.active and now >= profile.vip.renewsAt and guard < 24 do
		guard += 1
		if profile.fakeRobux >= Config.VipPrice then
			profile.fakeRobux -= Config.VipPrice
			profile.vip.renewsAt += PERIOD
			table.insert(profile.purchases, { id = "vip_renewal", price = Config.VipPrice, at = os.time() })
			Grants.apply(player, { kind = "tokens", amount = Config.VipMonthlyTokens }, { source = "vip renewal" })
			print(
				string.format(
					"[GHS Purchase] purchase vip_renewal R$%d balance %d (%s, fake renewal)",
					Config.VipPrice,
					profile.fakeRobux,
					player.Name
				)
			)
			Remotes.Juice:FireClient(player, "VipRenewed", { tokens = Config.VipMonthlyTokens })
		else
			profile.vip.active = false
			Log.event("VIP", "%s lapsed: R$ %d short of the renewal", player.Name, Config.VipPrice - profile.fakeRobux)
		end
		changed(player)
	end
end

function Vip.init()
	task.spawn(function()
		while true do
			task.wait(5)
			for _, p in Players:GetPlayers() do
				tick(p)
			end
		end
	end)
	Profiles.Loaded:Connect(function(player: Player)
		task.defer(tick, player)
	end)
end

Vip.tick = tick

return Vip
