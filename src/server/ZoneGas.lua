--!strict
-- Round 19c: zone gas. Every ZoneGasEveryWaves (a random pick in the range) on THE BANK, ZoneGasDelaySec into a
-- wave, the zone the crew holds (World.crewZone) is gassed so nobody camps one room all run: the alarms ring and a
-- toast warns for ZoneGasWarnSec, then green gas fills the zone's volumes for ZoneGasSec. Anyone standing in it
-- takes ZoneGasDps and the screen tints, the same as the vault's gas; any other open zone is safe. Skipped (and
-- tried again next wave) on boss waves, while the vault window runs, when the crew zone is in ZoneGasSkipZones, or
-- when no other zone is open yet to move to.
--
-- Round 19d: lockdown gas (mode "force"). A door objective still shut DoorForceAfterWaves waves after the wave it
-- was called for (Doors.overdue) floods every zone except the ones that door opens: DoorForceDelaySec into the
-- wave the alarms ring and a countdown runs for DoorForceWarnSec, then the gas stays until the door is open (plus
-- DoorForceLingerSec to step through). Every DoorForceArrowEverySec the floor chevrons are re-planned from each
-- standing player to the door and its beacon pulses loud; the client pins a banner and a screen-edge arrow.
-- A lockdown takes precedence over the zone gas (a running zone gas ends).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Lines = require(Shared.CrewCall.Lines)
local World = require(script.Parent.World)
local Log = require(script.Parent.Log)
local MapLoader = require(script.Parent.MapLoader)
local PlayerState = require(script.Parent.PlayerState)
local Pause = require(script.Parent.Pause)
local Alarms = require(script.Parent.Alarms)
local VaultJob = require(script.Parent.VaultJob)
local Doors = require(script.Parent.Doors)
local GuidePath = require(script.Parent.GuidePath)

local ZoneGas = {}

local GAS = Color3.fromRGB(150, 220, 110)

-- idle | warn | gas | linger (force only: the door is open, the gas is about to clear)
ZoneGas.phase = "idle" :: string
-- zone (one zone gassed) | force (every zone but the safe ones)
ZoneGas.mode = "zone" :: string
local zone: string? = nil
local forceGroup: string? = nil
local forceTarget: Vector3? = nil
local safe: { [string]: boolean } = {}
local nextWave = 0
local token = 0
local forceToken = 0 -- a scheduled lockdown (its own token, so cancelling it never strands a zone gas)
local clouds: { BasePart } = {}
local tinted: { [Player]: boolean } = {}
local lastTick = 0
local lastArrows = 0

local function label(id: string): string
	local z = MapLoader.zones[id]
	return if z then z.label else string.upper(id)
end

local function rollNext(from: number)
	local range = Config.ZoneGasEveryWaves
	nextWave = from + math.random(range[1] or 3, range[2] or range[1] or 5)
end

local function tint(player: Player, on: boolean)
	if (tinted[player] == true) == on then
		return
	end
	tinted[player] = if on then true else nil
	Remotes.Juice:FireClient(player, "ZoneGasTint", { on = on })
end

local function clearClouds()
	for _, c in clouds do
		c:Destroy()
	end
	clouds = {}
end

-- One emitter per zone volume, filling its bottom ZoneGasHeight studs.
local function fillClouds(ids: { string }, rateMult: number)
	clearClouds()
	local effects = Workspace:FindFirstChild("Effects") or Workspace
	for _, id in ids do
		local z = MapLoader.zones[id]
		if not z then
			continue
		end
		for _, v in z.parts do
			local h = math.min(v.size.Y, Config.ZoneGasHeight)
			local p = Instance.new("Part")
			p.Name = "ZoneGas"
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Transparency = 1
			p.Size = Vector3.new(v.size.X, h, v.size.Z)
			p.CFrame = v.cframe * CFrame.new(0, -v.size.Y / 2 + h / 2, 0)
			local e = Instance.new("ParticleEmitter")
			e.Shape = Enum.ParticleEmitterShape.Box
			e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
			e.Rate = math.clamp(v.size.X * v.size.Z * Config.ZoneGasParticlesPerArea * rateMult, 10, 400)
			e.Lifetime = NumberRange.new(2.5, 4.5)
			e.Speed = NumberRange.new(0.5, 2)
			e.SpreadAngle = Vector2.new(180, 180)
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 11) })
			e.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.25, 0.65),
				NumberSequenceKeypoint.new(1, 1),
			})
			e.Color = ColorSequence.new(GAS)
			e.Drag = 1
			e.Parent = p
			p.Parent = effects
			table.insert(clouds, p)
		end
	end
end

local function finish(reason: string)
	token += 1
	local was = zone
	local wasForce = ZoneGas.mode == "force" and ZoneGas.phase ~= "idle"
	if ZoneGas.phase == "warn" then
		Alarms.set("zonegas", false)
	end
	ZoneGas.phase = "idle"
	ZoneGas.mode = "zone"
	zone = nil
	forceGroup = nil
	forceTarget = nil
	safe = {}
	clearClouds()
	for player in table.clone(tinted) do
		tint(player, false)
	end
	tinted = {}
	if wasForce then
		-- The client's banner and edge arrow go with any end (clear or reset).
		World.fireRun("ZoneGas", {
			phase = "clear",
			force = true,
			toast = if reason == "clear" then Lines.zoneGas.forceClearToast else nil,
		})
		Log.event("Zone", "lockdown gas over (%s)", reason)
	elseif was and reason == "clear" then
		World.fireRun(
			"ZoneGas",
			{ phase = "clear", zone = was, toast = string.format(Lines.zoneGas.clearToast, label(was)) }
		)
		Log.event("Zone", "gas cleared from %s", was)
	end
end

local function startGas(my: number)
	if my ~= token or ZoneGas.phase ~= "warn" or not zone then
		return
	end
	local id = zone :: string
	ZoneGas.phase = "gas"
	Alarms.set("zonegas", false)
	fillClouds({ id }, 1)
	lastTick = 0
	World.fireRun("ZoneGas", { phase = "gas", zone = id, toast = string.format(Lines.zoneGas.gasToast, label(id)) })
	Log.event("Zone", "gas in %s for %ds", id, Config.ZoneGasSec)
	Pause.delay(Config.ZoneGasSec, function()
		if my == token and ZoneGas.phase == "gas" then
			finish("clear")
		end
	end)
end

local function startWarn(my: number)
	if my ~= token or ZoneGas.phase ~= "idle" or not World.inRun() or World.runOver then
		return
	end
	local id = World.crewZone
	if not MapLoader.zones[id] or table.find(Config.ZoneGasSkipZones, id) then
		Log.event("Zone", "gas skipped: crew zone %s is not gassable", tostring(id))
		return
	end
	zone = id
	ZoneGas.phase = "warn"
	ZoneGas.mode = "zone"
	Alarms.set("zonegas", true)
	World.fireRun("ZoneGas", {
		phase = "warn",
		zone = id,
		endsAt = Workspace:GetServerTimeNow() + Config.ZoneGasWarnSec,
		toast = string.format(Lines.zoneGas.warnToast, label(id), Config.ZoneGasWarnSec),
	})
	Log.event("Zone", "gas warning for %s, %ds", id, Config.ZoneGasWarnSec)
	Pause.delay(Config.ZoneGasWarnSec, function()
		startGas(my)
	end)
end

------------------------------------------------------------------ Lockdown (Round 19d)
local function doorLabels(door: MapLoader.Door): string
	local out = {}
	for _, z in door.opens do
		table.insert(out, label(z))
	end
	return table.concat(out, " · ")
end

-- Chevrons from every standing player to the door, and its beacon loud until the next refresh.
local function guide()
	local group, target = forceGroup, forceTarget
	if not group or not target then
		return
	end
	lastArrows = os.clock()
	local sec = Config.DoorForceArrowEverySec + 0.5
	for _, p in World.runAudience() do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and PlayerState.isStanding(PlayerState.get(p)) then
			GuidePath.arrows(root.Position, target, sec)
		end
	end
	World.fireRun("DoorPing", { group = group, sec = sec + 0.5 })
end

-- Every open zone the lockdown fills (not the safe ones, never the vault or the tunnel: they have their own gas).
local function forceZones(): { string }
	local out = {}
	for id in MapLoader.zones do
		if not safe[id] and not table.find(Config.ZoneGasSkipZones, id) and MapLoader.zoneOpen(id) then
			table.insert(out, id)
		end
	end
	return out
end

local function forcePayload(phase: string, door: MapLoader.Door, extra: { [string]: any }?): { [string]: any }
	local data: { [string]: any } = {
		phase = phase,
		force = true,
		group = forceGroup,
		position = forceTarget,
		title = door.pingText,
		safeLabel = doorLabels(door),
	}
	for k, v in (extra or {}) :: { [string]: any } do
		data[k] = v
	end
	return data
end

local function startForceGas(my: number)
	if my ~= token or ZoneGas.mode ~= "force" or ZoneGas.phase ~= "warn" then
		return
	end
	local group = forceGroup :: string
	local door = MapLoader.doors[group]
	if not door then
		finish("reset")
		return
	end
	ZoneGas.phase = "gas"
	Alarms.set("zonegas", false)
	fillClouds(forceZones(), Config.DoorForceParticleMult)
	lastTick = 0
	World.fireRun(
		"ZoneGas",
		forcePayload("gas", door, { toast = string.format(Lines.zoneGas.forceGasToast, door.pingText) })
	)
	Log.event("Zone", "lockdown gas in for %s", group)
end

local function startForce(myForce: number, group: string)
	if myForce ~= forceToken or not World.inRun() or World.runOver then
		return
	end
	local door = MapLoader.doors[group]
	if not door or Doors.isOpen(group) then
		return
	end
	if ZoneGas.phase ~= "idle" then
		finish("reset") -- a running zone gas yields
	end
	token += 1
	local my = token
	ZoneGas.mode = "force"
	ZoneGas.phase = "warn"
	forceGroup = group
	forceTarget = Doors.target(group) or door.parts[1].cframe.Position
	safe = {}
	for _, z in door.opens do
		safe[z] = true
	end
	Alarms.set("zonegas", true)
	World.fireRun(
		"ZoneGas",
		forcePayload("warn", door, {
			endsAt = Workspace:GetServerTimeNow() + Config.DoorForceWarnSec,
			toast = string.format(Lines.zoneGas.forceWarnToast, Config.DoorForceWarnSec, door.pingText),
		})
	)
	guide()
	Log.event("Zone", "lockdown warning: %s still shut at wave %d", group, World.wave)
	Pause.delay(Config.DoorForceWarnSec, function()
		startForceGas(my)
	end)
end

------------------------------------------------------------------ Wave hook
-- Another open, gassable zone to move to?
local function hasRefuge(id: string): boolean
	for other in MapLoader.zones do
		if other ~= id and not table.find(Config.ZoneGasSkipZones, other) and MapLoader.zoneOpen(other) then
			return true
		end
	end
	return false
end

local function vaultRunning(): boolean
	local vp = VaultJob.phase
	return vp == "open" or vp == "warn" or vp == "gas"
end

function ZoneGas.onWaveStart(wave: number)
	if World.map == "Arena" or not MapLoader.loaded then
		return
	end
	if World.isBossWave(wave) or vaultRunning() then
		return -- try again next wave
	end
	-- Round 19d: an overdue door locks the building down (before the zone gas draw).
	if Config.DoorForceEnabled and ZoneGas.mode ~= "force" then
		local group = Doors.overdue(wave)
		if group then
			forceToken += 1
			local my = forceToken
			Pause.delay(Config.DoorForceDelaySec, function()
				startForce(my, group)
			end)
			Log.event("Zone", "lockdown due this wave (%d) for %s", wave, group)
			return
		end
	end
	if not Config.ZoneGasEnabled then
		return
	end
	if ZoneGas.phase ~= "idle" or wave < nextWave then
		return
	end
	local id = World.crewZone
	if not MapLoader.zones[id] or table.find(Config.ZoneGasSkipZones, id) or not hasRefuge(id) then
		return
	end
	rollNext(wave)
	token += 1
	local my = token
	Pause.delay(Config.ZoneGasDelaySec, function()
		startWarn(my)
	end)
	Log.event("Zone", "gas due this wave (%d); next from wave %d", wave, nextWave)
end

-- Run start / hub: clean air, the first event from ZoneGasFirstWave.
function ZoneGas.resetRun()
	forceToken += 1
	finish("reset")
	nextWave = Config.ZoneGasFirstWave
end

local function gassedAt(position: Vector3): boolean
	if ZoneGas.mode == "force" then
		local id = MapLoader.zoneAt(position) or MapLoader.nearestZone(position)
		return not (id and safe[id])
	end
	return zone ~= nil and MapLoader.zoneAt(position) == zone
end

function ZoneGas.init()
	nextWave = Config.ZoneGasFirstWave
	RunService.Heartbeat:Connect(function()
		if ZoneGas.phase == "idle" then
			return
		end
		if not World.inRun() or World.runOver then
			finish("reset")
			return
		end
		if ZoneGas.mode == "force" then
			local group = forceGroup :: string
			if Doors.isOpen(group) then
				if ZoneGas.phase == "warn" then
					finish("clear") -- opened before the gas came in
					return
				elseif ZoneGas.phase == "gas" then
					ZoneGas.phase = "linger"
					local my = token
					Pause.delay(Config.DoorForceLingerSec, function()
						if my == token and ZoneGas.phase == "linger" then
							finish("clear")
						end
					end)
				end
			elseif os.clock() - lastArrows >= Config.DoorForceArrowEverySec and not Pause.active() then
				guide()
			end
		end
		if ZoneGas.phase ~= "gas" and ZoneGas.phase ~= "linger" then
			return
		end
		local inside: { [Player]: boolean } = {}
		for _, player in World.runAudience() do
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and gassedAt(root.Position) then
				inside[player] = true
				tint(player, true)
			end
		end
		for player in table.clone(tinted) do
			if not inside[player] then
				tint(player, false)
			end
		end
		local t = Workspace:GetServerTimeNow()
		if t - lastTick >= Config.FieldTickSec and not Pause.active() then
			lastTick = t
			local dps = if ZoneGas.mode == "force" then Config.DoorForceGasDps else Config.ZoneGasDps
			for player in inside do
				if PlayerState.isStanding(PlayerState.get(player)) then
					PlayerState.damage(player, dps * Config.FieldTickSec, "gas")
				end
			end
		end
	end)
end

-- Debug: gas the crew zone now (warning first).
function ZoneGas.debugNow()
	if ZoneGas.phase ~= "idle" then
		finish("reset")
	end
	token += 1
	startWarn(token)
end

-- Debug: lock the building down on the called door now (warning first). False when no door is called.
function ZoneGas.debugForce(): boolean
	local group: string? = nil
	for gid, door in MapLoader.doors do
		if door.triggerWave > 0 and Doors.target(gid) and not Doors.isOpen(gid) then
			group = gid
			break
		end
	end
	if not group then
		return false
	end
	forceToken += 1
	startForce(forceToken, group)
	return true
end

return ZoneGas
