--!strict
-- Round 19c: zone gas. Every ZoneGasEveryWaves (a random pick in the range) on THE BANK, ZoneGasDelaySec into a
-- wave, the zone the crew holds (World.crewZone) is gassed so nobody camps one room all run: the alarms ring and a
-- toast warns for ZoneGasWarnSec, then green gas fills the zone's volumes for ZoneGasSec. Anyone standing in it
-- takes ZoneGasDps and the screen tints, the same as the vault's gas; any other open zone is safe. Skipped (and
-- tried again next wave) on boss waves, while the vault window runs, when the crew zone is in ZoneGasSkipZones, or
-- when no other zone is open yet to move to.
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

local ZoneGas = {}

local GAS = Color3.fromRGB(150, 220, 110)

-- idle | warn | gas
ZoneGas.phase = "idle"
local zone: string? = nil
local nextWave = 0
local token = 0
local clouds: { BasePart } = {}
local tinted: { [Player]: boolean } = {}
local lastTick = 0

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
local function fillClouds(id: string)
	clearClouds()
	local z = MapLoader.zones[id]
	if not z then
		return
	end
	local effects = Workspace:FindFirstChild("Effects") or Workspace
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
		e.Rate = math.clamp(v.size.X * v.size.Z * Config.ZoneGasParticlesPerArea, 10, 400)
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

local function finish(reason: string)
	token += 1
	local was = zone
	if ZoneGas.phase == "warn" then
		Alarms.set("zonegas", false)
	end
	ZoneGas.phase = "idle"
	zone = nil
	clearClouds()
	for player in table.clone(tinted) do
		tint(player, false)
	end
	tinted = {}
	if was and reason == "clear" then
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
	fillClouds(id)
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

-- Another open, gassable zone to move to?
local function hasRefuge(id: string): boolean
	for other in MapLoader.zones do
		if other ~= id and not table.find(Config.ZoneGasSkipZones, other) and MapLoader.zoneOpen(other) then
			return true
		end
	end
	return false
end

function ZoneGas.onWaveStart(wave: number)
	if not Config.ZoneGasEnabled or World.map == "Arena" or not MapLoader.loaded then
		return
	end
	if ZoneGas.phase ~= "idle" or wave < nextWave then
		return
	end
	if World.isBossWave(wave) then
		return -- try again next wave
	end
	local vp = VaultJob.phase
	if vp == "open" or vp == "warn" or vp == "gas" then
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
	finish("reset")
	nextWave = Config.ZoneGasFirstWave
end

function ZoneGas.init()
	nextWave = Config.ZoneGasFirstWave
	RunService.Heartbeat:Connect(function()
		if ZoneGas.phase ~= "gas" or not zone then
			return
		end
		if not World.inRun() or World.runOver then
			finish("reset")
			return
		end
		local id = zone :: string
		local inside: { [Player]: boolean } = {}
		for _, player in World.runAudience() do
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and MapLoader.zoneAt(root.Position) == id then
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
			for player in inside do
				if PlayerState.isStanding(PlayerState.get(player)) then
					PlayerState.damage(player, Config.ZoneGasDps * Config.FieldTickSec, "gas")
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

return ZoneGas
