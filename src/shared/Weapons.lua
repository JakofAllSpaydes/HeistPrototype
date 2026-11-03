--!strict
-- Owned weapon pool for the prototype. Rarity is rolled per instance, never stored here.
-- displayName is the copy the player sees; keep names as near-names.
-- Paper DPS at common (dmg x rate x pellets): pistols 128 / 140, SMGs 180, rifles 160 / 165, shotgun 179,
-- sniper 135 plus headshots. SMG and shotgun only hit that up close (Config.FalloffByArchetype); the sniper
-- never falls off. Rarity multiplies damage on top (Config.RarityDmgMult): the spread between the weakest
-- and strongest common (1.4x) stays under every rarity step, so a legendary pistol beats an epic rifle.
export type Weapon = {
	id: string,
	displayName: string,
	archetype: string,
	baseDmg: number,
	fireRate: number, -- shots per second
	magSize: number,
	reloadTime: number, -- seconds for the whole mag; with shellReload, seconds per shell
	spread: number, -- cone half-angle in degrees
	pellets: number, -- raycasts per shot (shotguns)
	auto: boolean, -- hold to fire
	shellReload: boolean, -- tube-fed: shells load one at a time and firing cancels the rest
	rarityWeights: { number }, -- multiplies the wave-bracket odds per rarity, 1 = unchanged
}

local Weapons = {}

local function def(t: { [string]: any }): Weapon
	t.pellets = t.pellets or 1
	t.auto = t.auto or false
	t.shellReload = t.shellReload or false
	t.rarityWeights = t.rarityWeights or { 1, 1, 1, 1, 1 }
	return t :: Weapon
end

Weapons.List = {
	def({
		id = "M1911",
		displayName = "M1911",
		archetype = "Pistol",
		baseDmg = 32,
		fireRate = 4,
		magSize = 8,
		reloadTime = 1.2,
		spread = 1.2,
	}),
	def({
		id = "Glock",
		displayName = "Glock",
		archetype = "Pistol",
		baseDmg = 20,
		fireRate = 7,
		magSize = 17,
		reloadTime = 1.3,
		spread = 1.6,
	}),
	def({
		id = "UZI",
		displayName = "UZI",
		archetype = "SMG",
		baseDmg = 12,
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
		baseDmg = 15,
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
		baseDmg = 20,
		fireRate = 8,
		magSize = 30,
		reloadTime = 2.2,
		spread = 2.0,
		auto = true,
	}),
	def({
		id = "M4A1",
		displayName = "M4A1",
		archetype = "Rifle",
		baseDmg = 15,
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
		baseDmg = 14,
		fireRate = 1.6,
		magSize = 8,
		reloadTime = 0.45, -- per shell (tube-fed); a full 8 takes 3.6s but you can stop and shoot any time
		spread = 7,
		pellets = 8,
		shellReload = true,
	}),
	def({
		id = "AWP",
		displayName = "AWP",
		archetype = "Sniper",
		baseDmg = 150,
		fireRate = 0.9,
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
