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

function Rarity.bracketIndex(wave: number): number
	for i, bracket in Config.RarityOddsByWaveBracket do
		if wave <= bracket.maxWave then
			return i
		end
	end
	return #Config.RarityOddsByWaveBracket
end

function Rarity.odds(wave: number): { number }
	return Config.RarityOddsByWaveBracket[Rarity.bracketIndex(wave)].odds
end

-- Weighted roll for the wave bracket. `floor` forces at least that rarity, `weights` multiplies per rarity.
function Rarity.roll(wave: number, floor: number?, weights: { number }?): number
	local odds = Rarity.odds(wave)
	local minRarity = floor or 1
	local total = 0
	local w: { number } = {}
	for r = 1, 5 do
		local v = if r < minRarity then 0 else odds[r] * ((weights and weights[r]) or 1)
		w[r] = v
		total += v
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
