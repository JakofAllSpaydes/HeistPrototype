--!strict
-- Pick-3 generation, Take, stat application and the run tracker state.
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

local function randomStat(exclude: { [string]: boolean }, forMalus: boolean?): string
	local pool = {}
	for _, s in Upgrades.Stats do
		if not exclude[s.id] and not (forMalus and s.noMalus) then
			table.insert(pool, s.id)
		end
	end
	return pool[math.random(#pool)]
end

function UpgradeShop.generate(state: PlayerState.State, wave: number): { Types.Card }
	local cards: { Types.Card } = {}
	local used: { [string]: boolean } = {}
	local forcedIndex = if state.forceTradeoff then math.random(1, 3) else nil
	for i = 1, 3 do
		local tier = Rarity.roll(wave)
		local statId = randomStat(used)
		used[statId] = true
		local isTradeoff = forcedIndex == i or math.random() < Config.TradeoffChance[tier]
		local card: Types.Card = {
			stat = statId,
			tier = tier,
			pct = Upgrades.magnitude(statId, tier),
			name = Upgrades.cardName(statId, tier),
			isTradeoff = isTradeoff,
			malusStat = nil,
			malusPct = nil,
		}
		if isTradeoff then
			-- Buff rolls one tier higher; malus on a different random stat at the ratio.
			card.pct = Upgrades.magnitude(statId, math.min(tier + 1, 5))
			card.malusStat = randomStat({ [statId] = true }, true)
			card.malusPct = math.round(card.pct * Config.TradeoffMalusRatio * 10) / 10
		end
		cards[i] = card
	end
	state.forceTradeoff = false
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

local function applyStat(state: PlayerState.State, statId: string, pct: number, tier: number, isMalus: boolean)
	local item = state.upgrades[statId]
	if not item then
		item = { count = 0, pct = 0, highestTier = 0, everMalus = false }
		state.upgrades[statId] = item
		table.insert(state.upgradeOrder, statId)
	end
	item.pct = math.round((item.pct + pct) * 10) / 10
	if isMalus then
		item.everMalus = true
	else
		item.count += 1
		item.highestTier = math.max(item.highestTier, tier)
	end
end

local function totalsText(state: PlayerState.State): string
	local parts = {}
	for _, statId in state.upgradeOrder do
		local item = state.upgrades[statId]
		table.insert(parts, string.format("%s %s x%d", statId, Upgrades.pctText(item.pct, statId), item.count))
	end
	return table.concat(parts, ", ")
end

-- BuyUpgrade: charge once on press; reopening an unclaimed pick-3 is free and returns the same cards.
function UpgradeShop.buy(player: Player): any
	local state = PlayerState.get(player)
	if state.downed or state.bledOut then
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
	applyStat(state, card.stat, card.pct, card.tier, false)
	if card.malusStat and card.malusPct then
		applyStat(state, card.malusStat, -card.malusPct, 0, true)
	end
	state.openPick3 = nil
	PlayerState.applyCharacterStats(state)
	state.dirty = true
	Remotes.Juice:FireClient(player, "UpgradeApplied", { card = card, totalPct = state.upgrades[card.stat].pct })
	Log.event(
		"Upgrade",
		"%s took %s (%s). Totals: %s",
		player.Name,
		card.name,
		describeCards({ card }),
		totalsText(state)
	)
end

function UpgradeShop.init()
	Remotes.BuyUpgrade.OnServerInvoke = UpgradeShop.buy
	Remotes.TakeUpgrade.OnServerEvent:Connect(UpgradeShop.take)
end

return UpgradeShop
