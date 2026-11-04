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

export type Held = { weaponId: string, rarity: number, level: number, uid: number }

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
	shellReload: boolean, -- reloadTime is per shell; firing cancels the rest
	burst: number, -- shots per trigger pull; fireRate paces shots inside the burst
	burstDelay: number,
	displayRate: number, -- shots per second as delivered (bursts count the pause): what RATE shows
	builtInPierce: number, -- the gun's own pierce at this rarity (snipers)
	uid: number,
	level: number, -- Armory level
	sidearm: boolean, -- the downed pistol; the real gun is stowed
	wrapColor: string?, -- hex of the equipped wrap on this gun
	levelRateMult: number, -- fire-rate multiplier from the level (so tags compare like with like)
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
	abilities: { [string]: Ability }, -- keyed by the equipped class's ability ids
	classId: string, -- equipped class
	profile: any, -- Profiles.Profile (gold, weapons, classes, abilities, masks, wraps, topWave, stats)
	inParty: boolean, -- in the party of the current / forming run
	wave: number,
	waveState: string, -- Hub | Intro | Wave | Intermission | RunOver | RunEnd | Summary (always Hub outside the party)
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
	enemiesLeft: number, -- unspawned budget + alive, 0 outside a wave
	waveStartedAt: number, -- server time the current wave started
	skipVotes: number, -- votes in (auto-skip players count)
	skipNeeded: number,
	myVote: boolean,
	autoSkip: boolean,
	minigameTier: number, -- 1..3, session-wide
	downed: boolean,
	bledOut: boolean,
	bleedEndsAt: number, -- server time, while downed
	selfRevives: number, -- used this run
	reviveAllUsed: number, -- REVIVE EVERYBODY presses this run
}

return {}
