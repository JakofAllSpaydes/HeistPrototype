--!strict
-- Brief 6: timed boosts on a real-time clock from purchase (profile.boosts[id] = { expiresAt = os.time }). Buying
-- an active boost extends it. Effects apply where the value is computed: POWER in PlayerState.computed (weapon
-- damage) and the ability / element damage calls, CASH (plus VIP's permanent +25%) in the CASH GAIN multiplier,
-- LUCKY as a wave-bracket shift on the in-run rarity rolls. Nothing here touches Gold, XP, pass XP or paid crates.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local BoostDefs = require(Shared.BoostDefs)
local Profiles = require(script.Parent.Profiles)
local Log = require(script.Parent.Log)

local Boosts = {}

function Boosts.remaining(profile: any, id: string): number
	local b = profile and profile.boosts and profile.boosts[id]
	return if b then math.max(0, b.expiresAt - os.time()) else 0
end

function Boosts.active(player: Player, id: string): boolean
	return Boosts.remaining(Profiles.get(player), id) > 0
end

local function vipActive(player: Player): boolean
	local p = Profiles.get(player)
	return p ~= nil and p.vip.active == true
end

-- Start or extend a boost by `sec`. Returns the new os.time it runs out.
function Boosts.extend(player: Player, id: string, sec: number): number
	local profile = Profiles.get(player)
	if not profile or not BoostDefs.ById[id] then
		return 0
	end
	local now = os.time()
	local b = profile.boosts[id]
	local from = if b and b.expiresAt > now then b.expiresAt else now
	profile.boosts[id] = { expiresAt = from + sec }
	Profiles.markDirty(player)
	Log.event(
		"Boost",
		"%s %s %s +%dm, %dm left",
		player.Name,
		id,
		if b and b.expiresAt > now then "extended" else "started",
		sec // 60,
		(from + sec - now) // 60
	)
	return from + sec
end

-- POWER: weapon and ability damage.
function Boosts.damageMult(player: Player?): number
	if player and Boosts.active(player, "power") then
		return 1 + Config.PowerBoostPct
	end
	return 1
end

-- CASH (+50%) and VIP (+25%), additive, on every in-run cash source CASH GAIN scales.
function Boosts.cashMult(player: Player?): number
	if not player then
		return 1
	end
	local m = 1
	if Boosts.active(player, "cash") then
		m += Config.CashBoostPct
	end
	if vipActive(player) then
		m += Config.VipCashPct
	end
	return m
end

-- LUCKY: wave-bracket rows the in-run rarity rolls move up.
function Boosts.luckyShift(player: Player?): number
	if player and Boosts.active(player, "lucky") then
		return Config.LuckyWeightShift
	end
	return 0
end

function Boosts.init()
	-- Expiry: the chip pops out on the client; the server drops the record and toasts it once.
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.time()
			for _, player in Players:GetPlayers() do
				local profile = Profiles.get(player)
				if not profile then
					continue
				end
				for id, b in profile.boosts do
					if b.expiresAt <= now then
						profile.boosts[id] = nil
						Profiles.markDirty(player)
						local def = BoostDefs.ById[id]
						Remotes.Juice:FireClient(
							player,
							"BoostExpired",
							{ id = id, name = if def then def.name else id }
						)
						Log.event("Boost", "%s %s expired", player.Name, id)
					end
				end
			end
		end
	end)
end

return Boosts
