--!strict
-- Pick-3 generation, Take, stat application and the run tracker state. The dealer (brief 5) draws its stock
-- through the same generator (UpgradeShop.generate with a count) and applies it through UpgradeShop.applyCard.
-- Cards draw a category by Config.CategoryWeights (gun / element / utility), then a stat inside it. Tradeoff
-- cards roll at Config.TradeoffChance per tier, never on an element card, and the malus never lands on an element
-- or CASH GAIN. An element's first take grants its base chance; later takes add the card's chance and power.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Upgrades = require(Shared.Upgrades)
local Rarity = require(Shared.Rarity)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local PlayerState = require(script.Parent.PlayerState)
local Economy = require(script.Parent.Economy)
local World = require(script.Parent.World)
local Log = require(script.Parent.Log)

local UpgradeShop = {}

local function statsIn(category: string?, exclude: { [string]: boolean }, forMalus: boolean?): { string }
	local pool = {}
	for _, s in Upgrades.Stats do
		if (category == nil or s.category == category) and not exclude[s.id] and not (forMalus and s.noMalus) then
			table.insert(pool, s.id)
		end
	end
	return pool
end

-- A category by weight (skipping any with nothing left to offer), then a stat inside it.
local function randomStat(exclude: { [string]: boolean }, forced: string?): string
	if forced then
		local pool = statsIn(forced, exclude)
		if #pool > 0 then
			return pool[math.random(#pool)]
		end
	end
	local total = 0
	local weights: { [string]: number } = {}
	for _, cat in Upgrades.Categories do
		local w = (Config.CategoryWeights :: any)[cat] or 0
		if w > 0 and #statsIn(cat, exclude) > 0 then
			weights[cat] = w
			total += w
		end
	end
	if total > 0 then
		local x = math.random() * total
		for _, cat in Upgrades.Categories do
			local w = weights[cat]
			if w then
				x -= w
				if x < 0 then
					local pool = statsIn(cat, exclude)
					return pool[math.random(#pool)]
				end
			end
		end
	end
	local pool = statsIn(nil, exclude)
	return pool[math.random(#pool)]
end

local function malusStat(exclude: string): string
	local pool = statsIn(nil, { [exclude] = true }, true)
	return pool[math.random(#pool)]
end

-- The chance (or magnitude) a card of this stat and tier adds for this player right now.
local function cardValue(state: PlayerState.State, statId: string, tier: number): number
	if Upgrades.isElement(statId) and not state.upgrades[statId] then
		return Upgrades.elementBase(statId)
	end
	return Upgrades.magnitude(statId, tier)
end

-- `count` cards (3 for the pick-3, Config.DealerStock for the dealer), each a different stat.
function UpgradeShop.generate(state: PlayerState.State, wave: number, count: number?): { Types.Card }
	local n = count or 3
	local cards: { Types.Card } = {}
	local used: { [string]: boolean } = {}
	local forcedIndex = if state.forceTradeoff then math.random(1, n) else nil
	local elementIndex = if state.forceElement then math.random(1, n) else nil
	for i = 1, n do
		local tier = Rarity.roll(wave)
		local statId = randomStat(used, if elementIndex == i then "element" else nil)
		used[statId] = true
		local element = Upgrades.isElement(statId)
		local isTradeoff = not element and (forcedIndex == i or math.random() < Config.TradeoffChance[tier])
		local card: Types.Card = {
			stat = statId,
			tier = tier,
			pct = cardValue(state, statId, tier),
			name = Upgrades.cardName(statId, tier),
			isTradeoff = isTradeoff,
			malusStat = nil,
			malusPct = nil,
		}
		if isTradeoff then
			-- Buff rolls one tier higher; malus on a different random stat at the ratio.
			card.pct = Upgrades.magnitude(statId, math.min(tier + 1, 5))
			card.malusStat = malusStat(statId)
			card.malusPct = math.round(card.pct * Config.TradeoffMalusRatio * 10) / 10
		end
		cards[i] = card
	end
	state.forceTradeoff = false
	state.forceElement = false
	return cards
end

local function describeCards(cards: { Types.Card }): string
	local parts = {}
	for _, c in cards do
		local s = string.format("%s T%d +%s%%", c.stat, c.tier, tostring(c.pct))
		if c.isTradeoff then
			s ..= string.format(" / -%s%% %s", tostring(c.malusPct), tostring(c.malusStat))
		end
		table.insert(parts, s)
	end
	return table.concat(parts, " | ")
end
UpgradeShop.describeCards = describeCards

local function applyStat(state: PlayerState.State, statId: string, pct: number, tier: number, isMalus: boolean)
	local item = state.upgrades[statId]
	local fresh = item == nil
	if not item then
		item = { count = 0, pct = 0, highestTier = 0, everMalus = false }
		state.upgrades[statId] = item
		table.insert(state.upgradeOrder, statId)
	end
	local it = item :: Types.TrackerItem
	it.pct = math.round((it.pct + pct) * 10) / 10
	if isMalus then
		it.everMalus = true
	else
		it.count += 1
		it.highestTier = math.max(it.highestTier, tier)
		if Upgrades.isElement(statId) then
			-- The first take grants the effect at power 1; every later take adds its tier's power.
			it.power = if fresh then 1 else (it.power or 1) + (Config.ElementPowerByTier[math.clamp(tier, 1, 5)] or 0)
		end
	end
end

-- Grant an element at its base chance without a card (TORCH's HOT ROUNDS mastery at run start).
function UpgradeShop.grantElement(state: PlayerState.State, statId: string)
	if state.upgrades[statId] then
		return
	end
	applyStat(state, statId, Upgrades.elementBase(statId), 1, false)
	state.dirty = true
end

local function totalsText(state: PlayerState.State): string
	local parts = {}
	for _, statId in state.upgradeOrder do
		local item = state.upgrades[statId]
		table.insert(parts, string.format("%s %s x%d", statId, Upgrades.pctText(item.pct, statId), item.count))
	end
	return table.concat(parts, ", ")
end

-- Apply a card (the pick-3 take or a dealer purchase): the stat, its malus, character stats, the juice.
function UpgradeShop.applyCard(player: Player, card: Types.Card, source: string)
	local state = PlayerState.get(player)
	applyStat(state, card.stat, card.pct, card.tier, false)
	if card.malusStat and card.malusPct then
		applyStat(state, card.malusStat, -card.malusPct, 0, true)
	end
	PlayerState.applyCharacterStats(state)
	state.dirty = true
	Remotes.Juice:FireClient(player, "UpgradeApplied", { card = card, totalPct = state.upgrades[card.stat].pct })
	Log.event(
		"Upgrade",
		"%s took %s from the %s (%s). Totals: %s",
		player.Name,
		card.name,
		source,
		describeCards({ card }),
		totalsText(state)
	)
end

-- BuyUpgrade: charge once on press; reopening an unclaimed pick-3 is free and returns the same cards.
function UpgradeShop.buy(player: Player): any
	local state = PlayerState.get(player)
	if state.downed or state.bledOut or not World.inRun() or not World.isInParty(player) then
		return { ok = false, reason = "downed" }
	end
	if state.openPick3 then
		return { ok = true, cards = state.openPick3, reopened = true }
	end
	local price = Economy.upgradePrice(state)
	if not Economy.tryCharge(state, price) then
		return { ok = false, reason = "cash", price = price }
	end
	state.upgradesBought += 1
	state.waveUpgrades += 1
	state.openPick3 = UpgradeShop.generate(state, World.wave)
	state.dirty = true
	Log.event(
		"Upgrade",
		"%s bought pick-3 #%d for $%d: %s",
		player.Name,
		state.upgradesBought,
		price,
		describeCards(state.openPick3 :: { Types.Card })
	)
	return { ok = true, cards = state.openPick3, reopened = false }
end

function UpgradeShop.take(player: Player, index: any)
	local state = PlayerState.get(player)
	local cards = state.openPick3
	if not cards or typeof(index) ~= "number" then
		return
	end
	local card = cards[index]
	if not card then
		return
	end
	state.openPick3 = nil
	UpgradeShop.applyCard(player, card, "pick-3")
end

function UpgradeShop.init()
	Remotes.BuyUpgrade.OnServerInvoke = UpgradeShop.buy
	Remotes.TakeUpgrade.OnServerEvent:Connect(UpgradeShop.take)
end

return UpgradeShop
