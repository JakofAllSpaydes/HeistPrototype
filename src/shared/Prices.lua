--!strict
-- The only price file. Every Gold price in the meta screens reads from here; the economy is not what the
-- prototype tests, so everything is 100 and a fresh profile starts with Config.StartingGold.
local Prices = {
	weaponUnlock = 100, -- Direct-sale weapons (Weapons.lua unlockCost overrides per weapon when set)
	weaponUpgrade = 100, -- base cost of a weapon level; Config.RarityUpgCostMult ^ level on top
	class = 100,
	ability = 100, -- per ability level
	mask = 100,
	wrap = 100,
	emote = 100, -- SQUAD poses and MVP flexes
}

return Prices
