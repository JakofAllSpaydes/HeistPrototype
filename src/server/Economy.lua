--!strict
-- Match Cash only. Prices escalate per purchase; charge happens on press. Brief 5: CASH GAIN on earned cash, and
-- the per-wave income log (`wave N cash earned X upgrades bought Y`) so CashWaveMult can be tuned from real runs.
local PlayerState = require(script.Parent.PlayerState)
local Stats = require(script.Parent.Stats)

local Economy = {}

-- Per wave, per player: { wave, rows = { { name, cash, upgrades } } } for the debug Stats print.
local history: { { wave: number, rows: { { name: string, cash: number, upgrades: number } } } } = {}

function Economy.upgradePrice(state: PlayerState.State): number
	return Stats.upgradePrice(state.upgradesBought)
end

function Economy.addCash(state: PlayerState.State, amount: number)
	state.cash += amount
	if amount > 0 then
		state.cashCollected += amount
		state.waveCash += amount
	end
	state.dirty = true
end

-- The player's CASH GAIN multiplier (kills, bags, job payouts).
function Economy.cashGain(state: PlayerState.State): number
	return PlayerState.computed(state).cashGain
end

-- Earned cash that CASH GAIN scales (bags, job payouts). Returns what was paid.
function Economy.addEarned(state: PlayerState.State, amount: number): number
	local paid = math.round(amount * Economy.cashGain(state))
	Economy.addCash(state, paid)
	return paid
end

function Economy.tryCharge(state: PlayerState.State, amount: number): boolean
	if state.cash < amount then
		return false
	end
	state.cash -= amount
	state.dirty = true
	return true
end

-- Wave end: one income line per party member, then the counters reset for the next wave.
function Economy.logWave(wave: number, players: { Player })
	local rows = {}
	for _, p in players do
		local state = PlayerState.get(p)
		print(
			string.format(
				"[GHS Income] wave %d cash earned %d upgrades bought %d (%s)",
				wave,
				math.round(state.waveCash),
				state.waveUpgrades,
				p.Name
			)
		)
		table.insert(rows, { name = p.Name, cash = state.waveCash, upgrades = state.waveUpgrades })
		state.waveCash = 0
		state.waveUpgrades = 0
	end
	table.insert(history, { wave = wave, rows = rows })
end

function Economy.resetRun(players: { Player })
	table.clear(history)
	for _, p in players do
		local state = PlayerState.get(p)
		state.waveCash = 0
		state.waveUpgrades = 0
	end
end

-- Debug Stats: upgrades per player per wave this run (target 1 to 1.5 through wave 20).
function Economy.printStats()
	print("[GHS Income] upgrades per player per wave this run:")
	if #history == 0 then
		print("  (no waves logged yet)")
		return
	end
	local sum, n = 0, 0
	for _, w in history do
		local ups, cash = 0, 0
		for _, r in w.rows do
			ups += r.upgrades
			cash += r.cash
		end
		local players = math.max(1, #w.rows)
		sum += ups / players
		n += 1
		print(
			string.format(
				"  wave %2d  cash/player %6d  upgrades/player %.2f",
				w.wave,
				math.round(cash / players),
				ups / players
			)
		)
	end
	print(string.format("  mean %.2f upgrades per player per wave over %d waves", sum / math.max(1, n), n))
end

return Economy
