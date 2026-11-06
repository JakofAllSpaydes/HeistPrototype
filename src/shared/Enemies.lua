--!strict
-- The enemy roster (Brief 4): one row per archetype, numbers from Config.Enemies, plus the wave scaling and
-- the composition bracket lookup. Server and client both read it (the client only for names and colors).
local Config = require(script.Parent.Config)

export type Row = {
	id: string,
	name: string,
	hp: number,
	speed: number,
	dmg: number,
	range: number, -- studs: melee reach for melee kinds, hold distance for ranged kinds
	cooldown: number, -- seconds between attacks (0 = one-shot, the Boomer)
	scale: number,
	color: string, -- hex, the body color
	cash: number, -- match cash per kill before greed / elite / heat
	attack: string, -- melee | shooter | marksman | boomer | grenadier | heavy | boss
	noElite: boolean?, -- never rolls elite (Heavy)
	lean: boolean?, -- narrower body (Runner)
	round: boolean?, -- a belly (Boomer)
	backpack: boolean?, -- a pack on the back (Grenadier)
	wide: boolean?, -- a wider body with armor plates (Heavy)
	plates: number?, -- armor plates on a wide body (2 default: chest, shoulders; 4 adds a back plate and shoulder pads)
	boss: boolean?, -- a boss (minigun, Boss attribute, never flinches)
	noFlinch: boolean?,
}

local Enemies = {}

Enemies.List = {} :: { Row }
Enemies.ById = {} :: { [string]: Row }
for _, raw in Config.Enemies do
	local row = raw :: Row
	table.insert(Enemies.List, row)
	Enemies.ById[row.id] = row
end

Enemies.Default = "Henchman"

function Enemies.color(id: string): Color3
	local row = Enemies.ById[id]
	return if row then Color3.fromHex(row.color) else Color3.fromHex("8A8F99")
end

-- The Config.QueueDifficulties row for an id (Round 16: difficulty is live), the first row when unknown.
function Enemies.difficulty(id: string?): any
	for _, d in Config.QueueDifficulties do
		if d.id == id then
			return d
		end
	end
	return Config.QueueDifficulties[1]
end

-- FinalHp = BaseHp x (1 + HpWaveMult)^(wave - 1) x (1 + HpPerPlayerMult x (players - 1)) x the difficulty's hpMult
function Enemies.hpAt(row: Row, wave: number, players: number, difficultyId: string?): number
	return row.hp
		* (1 + Config.HpWaveMult) ^ math.max(0, wave - 1)
		* (1 + Config.HpPerPlayerMult * math.max(0, players - 1))
		* (Enemies.difficulty(difficultyId).hpMult or 1)
end

-- FinalDamage = BaseDamage x (1 + DamageWaveMult)^(wave - 1) x the difficulty's dmgMult (player count never scales damage)
function Enemies.dmgAt(row: Row, wave: number, difficultyId: string?): number
	return row.dmg
		* (1 + Config.DamageWaveMult) ^ math.max(0, wave - 1)
		* (Enemies.difficulty(difficultyId).dmgMult or 1)
end

-- The composition row for a wave: the one with the largest WaveMin at or below the wave, shifted `shift`
-- rows further down the table (heat), clamped to the last row.
function Enemies.bracketIndex(wave: number, shift: number?): number
	local index = 1
	for i, row in Config.Composition do
		if wave >= row.WaveMin then
			index = i
		end
	end
	return math.clamp(index + (shift or 0), 1, #Config.Composition)
end

function Enemies.bracket(wave: number, shift: number?): { [string]: number }
	return Config.Composition[Enemies.bracketIndex(wave, shift)]
end

-- Weighted roll over the bracket's archetype weights. Unknown keys (WaveMin) are skipped.
function Enemies.rollArchetype(wave: number, shift: number?): string
	local bracket = Enemies.bracket(wave, shift)
	local total = 0
	for _, row in Enemies.List do
		total += math.max(0, tonumber(bracket[row.id]) or 0)
	end
	if total <= 0 then
		return Enemies.Default
	end
	local r = math.random() * total
	for _, row in Enemies.List do
		r -= math.max(0, tonumber(bracket[row.id]) or 0)
		if r <= 0 then
			return row.id
		end
	end
	return Enemies.Default
end

return Enemies
