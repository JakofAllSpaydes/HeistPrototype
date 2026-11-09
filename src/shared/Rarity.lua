--!strict
-- Rarity enum, colors and the wave-bracket roll. Upgrade card tiers use the same odds.
local Config = require(script.Parent.Config)

local Rarity = {}

Rarity.Common = 1
Rarity.Uncommon = 2
Rarity.Rare = 3
Rarity.Epic = 4
Rarity.Legendary = 5

Rarity.Names = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }
Rarity.Letters = { "C", "U", "R", "E", "L" }
Rarity.Colors = {
	Color3.fromHex("9BA0A8"),
	Color3.fromHex("5FBF6B"),
	Color3.fromHex("4D9FE8"),
	Color3.fromHex("A864E8"),
	Color3.fromHex("F2A33C"),
}

-- Brief 13: relics sit above Legendary with their own colour. Never rolled (every roll stays in 1..5).
Rarity.Relic = 6
Rarity.Names[6] = "Relic"
Rarity.Letters[6] = "X"
Rarity.Colors[6] = Color3.fromHex(Config.RelicColor)

function Rarity.bracketIndex(wave: number): number
	for i, bracket in Config.RarityOddsByWaveBracket do
		if wave <= bracket.maxWave then
			return i
		end
	end
	return #Config.RarityOddsByWaveBracket
end

-- `shift` (brief 6 LUCKY boost) reads the bracket that many rows further up the table.
function Rarity.odds(wave: number, shift: number?): { number }
	local list = Config.RarityOddsByWaveBracket
	return list[math.clamp(Rarity.bracketIndex(wave) + (shift or 0), 1, #list)].odds
end

-- Brief 9 LUCK: `luck` (a share of the total, Config.LuckOddsStep per node) of the weight moves off the lowest tier
-- that has any onto the higher tiers that have some, in proportion to theirs. Never past the bracket's top tier (a
-- tier at 0 stays at 0); the lowest tier never goes below 0.
function Rarity.applyLuck(w: { number }, luck: number?)
	local l = luck or 0
	if l <= 0 then
		return
	end
	local total, low = 0, nil :: number?
	for r = 1, 5 do
		total += w[r]
		if low == nil and w[r] > 0 then
			low = r
		end
	end
	if low == nil or total <= 0 then
		return
	end
	local higher = 0
	for r = low + 1, 5 do
		higher += w[r]
	end
	if higher <= 0 then
		return
	end
	local move = math.min(w[low], total * l)
	local shares = {}
	for r = low + 1, 5 do
		shares[r] = w[r] / higher
	end
	w[low] -= move
	for r = low + 1, 5 do
		w[r] += move * shares[r]
	end
end

-- Weighted roll for the wave bracket. `floor` forces at least that rarity, `weights` multiplies per rarity.
-- `shift` moves up the bracket table (the LUCKY boost); `luck` is the Skill Web's share (Rarity.applyLuck).
function Rarity.roll(wave: number, floor: number?, weights: { number }?, shift: number?, luck: number?): number
	local odds = Rarity.odds(wave, shift)
	local minRarity = floor or 1
	local total = 0
	local w: { number } = {}
	for r = 1, 5 do
		local v = if r < minRarity then 0 else odds[r] * ((weights and weights[r]) or 1)
		w[r] = v
	end
	Rarity.applyLuck(w, luck)
	for r = 1, 5 do
		total += w[r]
	end
	if total <= 0 then
		return minRarity
	end
	local x = math.random() * total
	for r = 1, 5 do
		x -= w[r]
		if x < 0 then
			return r
		end
	end
	return 5
end

function Rarity.name(r: number): string
	return Rarity.Names[r] or "?"
end

function Rarity.color(r: number): Color3
	return Rarity.Colors[r] or Rarity.Colors[1]
end

function Rarity.fromLetter(letter: string): number?
	return table.find(Rarity.Letters, string.upper(letter))
end

return Rarity
