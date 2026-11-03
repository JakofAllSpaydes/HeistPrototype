--!strict
-- Shared payload shapes. The server builds them, the client only reads them.

export type Card = {
	stat: string,
	tier: number,
	pct: number,
	name: string,
	isTradeoff: boolean,
	malusStat: string?,
	malusPct: number?,
}

export type TrackerItem = { count: number, pct: number, highestTier: number, everMalus: boolean }
export type Tracker = { order: { string }, items: { [string]: TrackerItem }, total: number }

export type Held = { weaponId: string, rarity: number, uid: number }

export type HeldView = {
	weaponId: string,
	displayName: string,
	archetype: string,
	rarity: number,
	rarityName: string,
	dmg: number,
	dps: number,
	fireRate: number,
	magSize: number,
	reloadTime: number,
	spread: number,
	pellets: number,
	auto: boolean,
	uid: number,
}

export type Computed = {
	damage: number,
	fireRate: number,
	magSize: number,
	reloadTime: number,
	maxHP: number,
	hpRegen: number,
	moveSpeed: number,
	critChance: number,
	headshotMult: number,
	greed: number,
	spreadMult: number,
	pierce: number,
	ricochet: number,
	splash: number,
	multishot: number,
	lifesteal: number,
}

export type Ability = { cooldown: number, cooldownEndsAt: number, activeUntil: number? }

export type Sync = {
	abilities: { [string]: Ability },
	wave: number,
	waveState: string,
	intermissionEndsAt: number,
	heat: number,
	cash: number,
	gold: number,
	maxHP: number,
	held: HeldView,
	stats: Computed,
	prices: { upgrade: number, weapon: number },
	tracker: Tracker,
	openPick3: { Card }?,
	cratesTaken: { string },
	god: boolean,
	spawnsPaused: boolean,
	debugEnabled: boolean,
	playerCount: number,
}

return {}
