--!strict
-- Brief 6: the single entry point for every Robux-priced item. Prototype rule: every purchase succeeds against a
-- fake balance (profile.fakeRobux). The client's PurchaseSheet confirms, then invokes Remotes.Purchase; this
-- module validates, debits, grants through the kind's handler, writes the profile and logs
--   [GHS Purchase] purchase <id> R$<price> balance <after> (<context>)
-- Swapping in MarketplaceService later replaces this module and PurchaseSheet.lua, nothing else. Kind handlers
-- register themselves (crates, bundles, boosts, VIP, the pass, the dealer) so the modules never require each
-- other through here.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Products = require(Shared.Products)
local Profiles = require(script.Parent.Profiles)
local PlayerState = require(script.Parent.PlayerState)
local Runs = require(script.Parent.Runs)
local Economy = require(script.Parent.Economy)
local Grants = require(script.Parent.Grants)
local Log = require(script.Parent.Log)

export type Handler = {
	-- Refuse before any charge: return a reason string to refuse (shown on the sheet), nil to go on.
	check: ((Player, Profiles.Profile, Products.Product, any) -> string?)?,
	-- Grant after the charge. Returns data for the client (crate results, the stacked reveal) or nil. A string
	-- second value refuses after all (the charge is refunded).
	grant: (Player, Profiles.Profile, Products.Product, any) -> (any, string?),
}

local Purchases = {}
local handlers: { [string]: Handler } = {}

function Purchases.register(kind: string, h: Handler)
	handlers[kind] = h
end

-- Wave and run context for the readout (conversion points are read from the session log).
local function context(player: Player, extra: string?): string
	local World = Runs.worldOf(player)
	local where = if Runs.inRun(player)
		then string.format("in-run %s wave %d %s", World.map, World.wave, World.state)
		else "hub"
	return if extra and extra ~= "" then where .. " · " .. extra else where
end
Purchases.context = context

local function record(profile: Profiles.Profile, id: string, price: number)
	table.insert(profile.purchases, { id = id, price = price, at = os.time() })
	while #profile.purchases > Config.PurchaseLogKeep do
		table.remove(profile.purchases, 1)
	end
end

export type Response = { ok: boolean, reason: string?, balance: number, data: any? }

function Purchases.buy(player: Player, productId: string, args: any): Response
	local profile = Profiles.get(player)
	local product = Products.ById[productId]
	if not profile then
		return { ok = false, reason = "Profile loading", balance = 0 }
	end
	if not product then
		return { ok = false, reason = "Unknown item", balance = profile.fakeRobux }
	end
	local h = handlers[product.kind]
	if not h then
		return { ok = false, reason = "Not on sale yet", balance = profile.fakeRobux }
	end
	if not product.inRun and Runs.inRun(player) then
		return { ok = false, reason = "Not during a run", balance = profile.fakeRobux }
	end
	local check = h.check
	-- A check that errors is a bug, not a refusal: log it and decline with the error so it shows on the sheet.
	local checked, refusal = true, nil :: string?
	if check then
		checked, refusal = pcall(check, player, profile, product, args)
	end
	if not checked then
		warn(string.format("[GHS Purchase] %s check failed: %s", productId, tostring(refusal)))
		return { ok = false, reason = "Server error: " .. tostring(refusal), balance = profile.fakeRobux }
	end
	if refusal then
		return { ok = false, reason = refusal, balance = profile.fakeRobux }
	end
	local price = Products.priceFor(product, profile)
	if profile.fakeRobux < price then
		return { ok = false, reason = "Not enough Robux", balance = profile.fakeRobux }
	end
	profile.fakeRobux -= price
	local ok, data, late = pcall(h.grant, player, profile, product, args)
	if not ok or late then
		profile.fakeRobux += price
		Log.event(
			"Purchase",
			"%s: %s refunded (%s)",
			player.Name,
			productId,
			if not ok then tostring(data) else tostring(late)
		)
		return { ok = false, reason = if late then tostring(late) else "Purchase failed", balance = profile.fakeRobux }
	end
	if price > 0 then
		record(profile, productId, price)
	end
	Profiles.markDirty(player)
	PlayerState.get(player).dirty = true
	local extra = if typeof(args) == "table" and typeof(args.context) == "string" then args.context else nil
	print(
		string.format(
			"[GHS Purchase] purchase %s R$%d balance %d (%s, %s)",
			productId,
			price,
			profile.fakeRobux,
			player.Name,
			context(player, extra)
		)
	)
	return { ok = true, balance = profile.fakeRobux, data = data }
end

------------------------------------------------------------------ The simple kinds
Purchases.register("tokens", {
	grant = function(player, _profile, product)
		Grants.apply(player, { kind = "tokens", amount = product.tokens or 0 }, { source = product.id })
		return { tokens = product.tokens }
	end,
})

Purchases.register("gold", {
	grant = function(player, _profile, product)
		Grants.apply(player, { kind = "gold", amount = product.gold or 0 }, { source = product.id })
		return { gold = product.gold }
	end,
})

Purchases.register("cash_pack", {
	check = function(player)
		if not Runs.inRun(player) then
			return "Match cash is for a run"
		end
		return nil
	end,
	grant = function(player, _profile, product)
		local state = PlayerState.get(player)
		Economy.addCash(state, product.cash or 0)
		Remotes.Juice:FireClient(player, "CashPack", { cash = product.cash })
		return { cash = product.cash }
	end,
})

-- GET ROBUX: the placeholder top-up (free; adds FakeRobuxTopUp so a tester never gets stuck).
Purchases.register("robux_topup", {
	grant = function(player, profile)
		profile.fakeRobux += Config.FakeRobuxTopUp
		Log.event(
			"Purchase",
			"%s GET ROBUX +%d (placeholder), balance %d",
			player.Name,
			Config.FakeRobuxTopUp,
			profile.fakeRobux
		)
		return { robux = Config.FakeRobuxTopUp }
	end,
})

-- Debug: set the balance outright.
function Purchases.setBalance(player: Player, amount: number)
	local profile = Profiles.get(player)
	if not profile then
		return
	end
	profile.fakeRobux = math.max(0, math.floor(amount))
	Profiles.markDirty(player)
	PlayerState.get(player).dirty = true
	Log.event("Purchase", "%s balance set to R$ %d (debug)", player.Name, profile.fakeRobux)
end

function Purchases.init()
	Remotes.Purchase.OnServerInvoke = function(player: Player, productId: any, args: any): Response
		return Purchases.buy(player, tostring(productId), args)
	end
	Remotes.SheetState.OnServerEvent:Connect(function(player: Player, open: any)
		Runs.worldOf(player).sheetOpen[player.UserId] = if open == true then true else nil
	end)
	Players.PlayerRemoving:Connect(function(player)
		for _, s in Runs.allSlots() do
			s.World.sheetOpen[player.UserId] = nil
		end
	end)
end

return Purchases
