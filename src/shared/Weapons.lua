--!strict
-- Owned weapon pool for the prototype. Rarity is rolled per instance, never stored here.
-- displayName is the copy the player sees; keep names as near-names.
export type Weapon = {
	id: string,
	displayName: string,
	archetype: string,
	baseDmg: number,
	fireRate: number, -- shots per second
	magSize: number,
	reloadTime: number, -- seconds
	spread: number, -- cone half-angle in degrees
	pellets: number, -- raycasts per shot (shotguns)
	auto: boolean, -- hold to fire
	rarityWeights: { number }, -- multiplies the wave-bracket odds per rarity, 1 = unchanged
}

local Weapons = {}

local function def(t: { [string]: any }): Weapon
	t.pellets = t.pellets or 1
	t.auto = t.auto or false
	t.rarityWeights = t.rarityWeights or { 1, 1, 1, 1, 1 }
	return t :: Weapon
end

Weapons.List = {
	def({
		id = "M1911",
		displayName = "M1911",
		archetype = "Pistol",
		baseDmg = 22,
		fireRate = 4,
		magSize = 8,
		reloadTime = 1.2,
		spread = 1.2,
	}),
	def({
		id = "Glock",
		displayName = "Glock",
		archetype = "Pistol",
		baseDmg = 16,
		fireRate = 7,
		magSize = 17,
		reloadTime = 1.3,
		spread = 1.6,
	}),
	def({
		id = "UZI",
		displayName = "UZI",
		archetype = "SMG",
		baseDmg = 9,
		fireRate = 15,
		magSize = 32,
		reloadTime = 1.6,
		spread = 3.5,
		auto = true,
	}),
	def({
		id = "MP5",
		displayName = "MP5",
		archetype = "SMG",
		baseDmg = 12,
		fireRate = 12,
		magSize = 30,
		reloadTime = 1.7,
		spread = 2.2,
		auto = true,
	}),
	def({
		id = "AK-47",
		displayName = "AK-47",
		archetype = "Rifle",
		baseDmg = 26,
		fireRate = 9,
		magSize = 30,
		reloadTime = 2.2,
		spread = 2.0,
		auto = true,
	}),
	def({
		id = "M4A1",
		displayName = "M4A1",
		archetype = "Rifle",
		baseDmg = 20,
		fireRate = 11,
		magSize = 30,
		reloadTime = 1.9,
		spread = 1.5,
		auto = true,
	}),
	def({
		id = "SPAS-12",
		displayName = "SPAS-12",
		archetype = "Shotgun",
		baseDmg = 11,
		fireRate = 1.5,
		magSize = 8,
		reloadTime = 2.6,
		spread = 7,
		pellets = 8,
	}),
	def({
		id = "AWP",
		displayName = "AWP",
		archetype = "Sniper",
		baseDmg = 120,
		fireRate = 0.8,
		magSize = 5,
		reloadTime = 3.0,
		spread = 0.2,
	}),
} :: { Weapon }

Weapons.ById = {} :: { [string]: Weapon }
for _, w in Weapons.List do
	Weapons.ById[w.id] = w
end

Weapons.Starter = "M1911"

return Weapons
