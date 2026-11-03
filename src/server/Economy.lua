--!strict
-- Match Cash only. Prices escalate per purchase; charge happens on press.
local PlayerState = require(script.Parent.PlayerState)
local Stats = require(script.Parent.Stats)

local Economy = {}

function Economy.upgradePrice(state: PlayerState.State): number
	return Stats.upgradePrice(state.upgradesBought)
end

function Economy.weaponPrice(state: PlayerState.State): number
	return Stats.weaponPrice(state.weaponsBought)
end

function Economy.addCash(state: PlayerState.State, amount: number)
	state.cash += amount
	state.dirty = true
end

function Economy.tryCharge(state: PlayerState.State, amount: number): boolean
	if state.cash < amount then
		return false
	end
	state.cash -= amount
	state.dirty = true
	return true
end

return Economy
