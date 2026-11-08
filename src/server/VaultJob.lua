--!strict
-- CRACK THE VAULT: the one side job kind with its own beats, on top of CrewCall. The vault closet sits on
-- the arena's north wall (Room.vault). Draw: the door frame turns job blue and F at the door opens the Safe
-- dial (tier from the wave bracket). Done: the door slides up, the lights snap on, VaultBurstCash /
-- VaultBurstGold bags drop onto the spots inside, and a VaultOpenSec loot window runs. VaultGasWarnSec
-- before it ends: alarm, red strobe, MARLOW's warning. At zero: gas (fog, screen tint for anyone inside,
-- VaultGasDps until they step out), the bags left inside fizzle, and the door closes only once nobody is in
-- the room. Sealed, it never reopens this run. The shell (call -> interact -> reward -> timed room ->
-- consequence) is what door objectives reuse on the real map.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Rarity = require(Shared.Rarity)
local Lines = require(Shared.CrewCall.Lines)
local Room = require(script.Parent.Room)
local World = require(script.Parent.World)
local Log = require(script.Parent.Log)
local PlayerState = require(script.Parent.PlayerState)
local Minigames = require(script.Parent.Minigames)
local Bags = require(script.Parent.Bags)
local Pause = require(script.Parent.Pause)
local Abilities = require(script.Parent.Abilities)

local VaultJob = {}

-- Brief 7: THE BANK's vault, installed by Doors (VaultJob cannot require it: CrewCall -> VaultJob). The shell is
-- the same on both maps; only these pieces differ: the wheel door (D4) and its server door, the VaultRoom
-- volume, the lights and gas anchor generated in the room, and the hatch that opens with the first window.
export type Site = {
	inside: (Vector3) -> boolean,
	front: () -> Vector3, -- floor point on the landing side of the wheel door
	doorPart: () -> BasePart?, -- where the CRACK prompt and the pulse light sit
	open: () -> (), -- the wheel spins, the vault door and the server door swing (D4)
	close: () -> (), -- both back shut
	setCalled: (boolean) -> (), -- the D4 beacons turn job blue while drawn
	lights: () -> { BasePart },
	gasAnchor: () -> BasePart?,
	gasCost: (boolean) -> (), -- the VaultGas path cost on the room while gassed
	ready: () -> boolean, -- the draw is legal: the stairwell is open
	openHatch: () -> (),
	hatchPosition: () -> Vector3?,
	afterSeal: () -> (), -- HatchOneWayAfterSeal false: shut the hatch when the tunnel is empty
	zoneAt: (Vector3) -> string?,
}
VaultJob.site = nil :: Site?

-- The site in play: THE BANK's on any map but the arena, nil on the arena (its closet vault).
local function site(): Site?
	if World.map == "Arena" then
		return nil
	end
	return VaultJob.site
end

-- Inside the vault (the arena closet's floor volume, or the VaultRoom node).
function VaultJob.inside(position: Vector3): boolean
	local s = site()
	if s then
		return s.inside(position)
	end
	return Room.insideVault(position)
end

local AMBER = Color3.fromHex("E8B64C")
local BLUE = Color3.fromHex("4D9FE8")
local GREY = Color3.fromHex("5A5E66")
local RED = Color3.fromHex("E8554D")
local GAS = Color3.fromRGB(150, 220, 110)

-- closed | job | open | warn | gas | sealed
VaultJob.phase = "closed"
VaultJob.doneThisRun = false

local prompt: ProximityPrompt? = nil
local exits: { [Player]: any } = {}
local trackExits: () -> ()
local fog: ParticleEmitter? = nil
local endsAt = 0 -- server time the loot window ends
local warnAt = 0
local runToken = 0
local tinted: { [Player]: boolean } = {}
local lastGasTick = 0

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function paintBeacons(color: Color3)
	local s = site()
	if s then
		s.setCalled(color == BLUE)
		return
	end
	local v = Room.vault
	if not v then
		return
	end
	for _, b in v.beacons do
		b.Color = color
	end
end

local function setLights(on: boolean, color: Color3?)
	local s = site()
	local v = Room.vault
	local lights = if s then s.lights() elseif v then v.lights else {}
	for _, l in lights do
		l.Color = color or Color3.fromRGB(255, 242, 217)
		l.Transparency = if on then 0 else 0.6
		local light = l:FindFirstChildOfClass("PointLight")
		if light then
			light.Enabled = on
			light.Color = color or Color3.fromRGB(255, 242, 217)
		end
	end
end

local function slideDoor(open: boolean)
	local s = site()
	if s then
		if open then
			s.open()
		else
			s.close()
		end
		return
	end
	local v = Room.vault
	if not v then
		return
	end
	TweenService:Create(
		v.door,
		TweenInfo.new(0.9, Enum.EasingStyle.Quad, if open then Enum.EasingDirection.Out else Enum.EasingDirection.In),
		{
			CFrame = if open then v.doorOpen else v.doorClosed,
		}
	):Play()
end

local fogAnchor: BasePart? = nil
local function setFog(on: boolean)
	local s = site()
	local v = Room.vault
	local anchor = if s then s.gasAnchor() elseif v then v.gas else nil
	if s then
		s.gasCost(on)
	end
	if not anchor then
		return
	end
	-- The emitter moves with the map in play (the arena closet or THE BANK's vault room).
	if fog and fogAnchor ~= anchor then
		fog:Destroy()
		fog = nil
	end
	fogAnchor = anchor
	if not fog then
		local e = Instance.new("ParticleEmitter")
		e.Name = "Gas"
		e.Rate = 0
		e.Lifetime = NumberRange.new(2.5, 4)
		e.Speed = NumberRange.new(2, 4)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 9) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
		e.Color = ColorSequence.new(GAS)
		e.Acceleration = Vector3.new(0, -2, 0)
		e.Drag = 1
		e.Parent = anchor
		fog = e
	end
	local e = fog :: ParticleEmitter
	e.Rate = if on then 40 else 0
	e.Enabled = on
end

local function tint(player: Player, on: boolean)
	if (tinted[player] == true) == on then
		return
	end
	tinted[player] = if on then true else nil
	Remotes.Juice:FireClient(player, "VaultGasTint", { on = on })
end

local function playersInside(): { Player }
	local out = {}
	for _, player in World.runAudience() do
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and VaultJob.inside(root.Position) then
			table.insert(out, player)
		end
	end
	return out
end

local function removePrompt()
	if prompt then
		prompt:Destroy()
		prompt = nil
	end
end

-- While the job is drawn and not yet cracked the door pulses amber with a light (VaultDoorPulseSec a cycle).
local function pulseDoor()
	local s = site()
	local v = Room.vault
	local door = if s then s.doorPart() elseif v then v.door else nil
	if not door then
		return
	end
	local baseColor = door.Color
	local light = door:FindFirstChild("PulseLight") :: PointLight?
	if not light then
		local l = Instance.new("PointLight")
		l.Name = "PulseLight"
		l.Color = AMBER
		l.Range = 18
		l.Brightness = 0
		l.Parent = door
		light = l
	end
	local token = runToken
	task.spawn(function()
		local t0 = os.clock()
		while VaultJob.phase == "job" and token == runToken and door.Parent do
			local k = 0.5 + 0.5 * math.sin((os.clock() - t0) / math.max(Config.VaultDoorPulseSec, 0.1) * math.pi * 2)
			door.Color = baseColor:Lerp(AMBER, 0.25 + 0.6 * k)
			if light then
				light.Brightness = 1 + 3 * k
			end
			task.wait(1 / 30)
		end
		door.Color = baseColor
		if light then
			light.Brightness = 0
		end
	end)
end

-- Can CRACK THE VAULT be drawn this wave?
function VaultJob.available(wave: number): boolean
	local s = site()
	if World.map == "Arena" and not Room.vault then
		return false
	end
	-- THE BANK: legal only once the stairwell is open (D3), like a job spot in a closed zone.
	if World.map ~= "Arena" and (not s or not s.ready()) then
		return false
	end
	-- Closed, or sealed from an earlier draw when the vault may come back (VaultJobOnce false).
	if VaultJob.phase ~= "closed" and not (VaultJob.phase == "sealed" and not Config.VaultJobOnce) then
		return false
	end
	if wave < Config.VaultJobMinWave then
		return false
	end
	if Config.VaultJobOnce and VaultJob.doneThisRun then
		return false
	end
	return true
end

function VaultJob.front(): Vector3
	local s = site()
	if s then
		return s.front()
	end
	local v = Room.vault
	return if v then v.front else Vector3.zero
end

-- Safe dial tier from the wave bracket, capped at VaultSafeTierMax (so a late vault is never the 4-number dial).
local function tierFor(wave: number): number
	return math.clamp(Rarity.bracketIndex(wave), 1, Config.VaultSafeTierMax)
end

-- The job was drawn: blue frame, a CRACK prompt on the door that opens the Safe dial. `onCracked` is
-- CrewCall finishing the job (which then calls VaultJob.open).
function VaultJob.startJob(onCracked: (Player) -> ())
	local s = site()
	local v = Room.vault
	local doorPart = if s then s.doorPart() elseif v then v.door else nil
	if not doorPart then
		return
	end
	local front = VaultJob.front()
	if VaultJob.phase == "sealed" then
		-- Drawn again after a seal (VaultJobOnce false): back to a closed, unlit vault.
		runToken += 1
		setFog(false)
		setLights(false)
		if v and not s then
			v.door.CFrame = v.doorClosed
		end
	end
	VaultJob.phase = "job"
	World.vaultLive = true
	PlayerState.markAllDirty()
	paintBeacons(BLUE)
	removePrompt()
	pulseDoor()
	-- Floor arrows from the crew to the door (the client lays the chevrons).
	local sum, n = Vector3.zero, 0
	for _, p in World.runAudience() do
		local char = p.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			sum += root.Position
			n += 1
		end
	end
	if n > 0 then
		World.fireRun("VaultArrows", { from = sum / n, to = front, sec = Config.VaultArrowSec })
	end
	local p = Instance.new("ProximityPrompt")
	p.ActionText = Lines.vault.promptAction
	p.ObjectText = Lines.vault.promptObject
	p.KeyboardKeyCode = Enum.KeyCode.F
	p.HoldDuration = 0
	p.MaxActivationDistance = 9
	p.RequiresLineOfSight = false
	p.Parent = doorPart
	p.Triggered:Connect(function(player: Player)
		if VaultJob.phase ~= "job" then
			return
		end
		Minigames.open(player, "Safe", {
			position = front,
			tier = tierFor(World.wave),
			onDone = function(pl: Player)
				if VaultJob.phase == "job" then
					Log.event("Vault", "%s cracked the dial", pl.Name)
					onCracked(pl)
				end
			end,
		})
	end)
	prompt = p
	Log.event("Vault", "CRACK THE VAULT drawn at wave %d (Safe tier %d)", World.wave, tierFor(World.wave))
end

-- The job ended: a fail (expiry) shuts it again so it can be redrawn; a success opens it.
function VaultJob.jobEnded(success: boolean)
	removePrompt()
	if VaultJob.phase ~= "job" then
		return
	end
	if success then
		VaultJob.open()
	else
		VaultJob.phase = "closed"
		World.vaultLive = false
		PlayerState.markAllDirty()
		paintBeacons(AMBER)
	end
end

local function seal()
	VaultJob.phase = "sealed"
	World.vaultLive = false
	PlayerState.markAllDirty()
	setFog(false)
	setLights(false)
	slideDoor(false)
	paintBeacons(GREY)
	for player in table.clone(tinted) do
		tint(player, false)
	end
	-- Nothing stays behind the door: a turret or barricade left inside would be out of every enemy's reach.
	local cleared = Abilities.clearWhere(VaultJob.inside, "sealed in the vault")
	local s = site()
	if s then
		s.afterSeal()
	end
	VaultJob.logExits()
	World.fireRun("VaultSealed", { position = VaultJob.front(), label = Lines.vault.sealedLabel })
	Log.event("Vault", "sealed (%d placeables / fields inside cleared)", cleared)
end

local function startGas()
	if VaultJob.phase ~= "warn" and VaultJob.phase ~= "open" then
		return
	end
	VaultJob.phase = "gas"
	setFog(true)
	setLights(true, GAS)
	Bags.fizzleVault()
	lastGasTick = 0
	World.fireRun("VaultGas", { phase = "gas", position = VaultJob.front() })
	Log.event("Vault", "gas in, %d inside", #playersInside())
end

local function startWarn()
	if VaultJob.phase ~= "open" then
		return
	end
	VaultJob.phase = "warn"
	World.fireRun("VaultGas", {
		phase = "warn",
		endsAt = endsAt,
		position = VaultJob.front(),
		crewLead = Lines.vault.crewLead,
		title = Lines.vault.gasTitle,
		text = Lines.vault.gasText,
	})
	Log.event("Vault", "gas warning, %ds left", Config.VaultGasWarnSec)
	-- Red strobe until the gas or the seal.
	local token = runToken
	task.spawn(function()
		local on = true
		while token == runToken and VaultJob.phase == "warn" do
			setLights(on, RED)
			on = not on
			task.wait(0.25)
		end
	end)
end

-- Open the door onto the bag burst and start the loot window.
function VaultJob.open()
	local s = site()
	local v = Room.vault
	if
		(not v and not s)
		or VaultJob.phase == "open"
		or VaultJob.phase == "warn"
		or VaultJob.phase == "gas"
		or VaultJob.phase == "sealed"
	then
		return
	end
	removePrompt()
	VaultJob.phase = "open"
	World.vaultLive = true
	VaultJob.doneThisRun = true
	runToken += 1
	local token = runToken
	endsAt = now() + Config.VaultOpenSec
	warnAt = endsAt - Config.VaultGasWarnSec
	slideDoor(true)
	setLights(true)
	if not s then
		paintBeacons(AMBER)
	end
	Bags.burstAtSpots(Room.current().vaultSpots, Config.VaultBurstCash, Config.VaultBurstGold, true)
	-- THE BANK: the hatch opens with the first window (the tunnel's way out), with a beacon on the street side.
	if s then
		s.openHatch()
	end
	VaultJob.windowStart()
	World.fireRun("VaultOpen", {
		position = VaultJob.front(),
		tunnelText = if s then Config.VaultPillTunnelText else nil,
		hatch = if s then s.hatchPosition() else nil,
		endsAt = endsAt,
		warnAt = warnAt,
		openSec = Config.VaultOpenSec,
		name = Lines.vault.pillName,
		toast = Lines.vault.openToast,
		hint = Lines.vault.lootHint,
	})
	Log.event("Vault", "open for %ds, gas at %ds", Config.VaultOpenSec, Config.VaultGasWarnSec)
	Pause.delay(math.max(0, warnAt - now()), function()
		if token == runToken then
			startWarn()
		end
	end)
	Pause.delay(math.max(0, endsAt - now()), function()
		if token == runToken then
			startGas()
		end
	end)
end

------------------------------------------------------------------ The window's exits (brief 7)
-- Per member per window: when they last left the vault room and which way (the zone they stepped into:
-- stairs or tunnel), logged at the seal as [GHS Vault] window used <sec> exit <stairs|tunnel|none> <name>.
type Exit = { inside: boolean, entered: boolean, leftAt: number, way: string }
exits = {} :: { [Player]: Exit }
local windowAt = 0

function VaultJob.windowStart()
	windowAt = os.clock()
	exits = {}
end

function trackExits()
	if VaultJob.phase ~= "open" and VaultJob.phase ~= "warn" and VaultJob.phase ~= "gas" then
		return
	end
	local s = site()
	for _, player in World.runAudience() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			continue
		end
		local e = exits[player]
		if not e then
			e = { inside = false, entered = false, leftAt = 0, way = "none" }
			exits[player] = e
		end
		local inside = VaultJob.inside(root.Position)
		if inside then
			e.entered = true
		elseif e.inside then
			e.leftAt = os.clock()
			local z = if s then s.zoneAt(root.Position) else nil
			e.way = if z == "tunnel" then "tunnel" elseif z == "stairs" then "stairs" else "none"
		end
		e.inside = inside
	end
end

function VaultJob.logExits()
	for player, e in exits do
		if e.entered then
			Log.event(
				"Vault",
				"window used %.1f exit %s %s",
				if e.leftAt > 0 then e.leftAt - windowAt else os.clock() - windowAt,
				e.way,
				player.Name
			)
		end
	end
	exits = {}
end

-- Debug: jump to the gas now.
function VaultJob.debugGas()
	if VaultJob.phase == "open" or VaultJob.phase == "warn" then
		runToken += 1
		startGas()
	end
end

-- Run start / hub: closed, unlit, amber, undone.
function VaultJob.resetRun()
	runToken += 1
	removePrompt()
	VaultJob.phase = "closed"
	World.vaultLive = false
	VaultJob.doneThisRun = false
	setFog(false)
	setLights(false)
	paintBeacons(AMBER)
	local v = Room.vault
	if v then
		v.door.CFrame = v.doorClosed
	end
	local s = site()
	if s then
		s.close()
		s.gasCost(false)
	end
	exits = {}
	for player in table.clone(tinted) do
		tint(player, false)
	end
	tinted = {}
end

function VaultJob.init()
	Pause.onTick(function(dt)
		if VaultJob.phase == "open" or VaultJob.phase == "warn" then
			endsAt += dt
			warnAt += dt
		end
	end)
	local v = Room.vault
	if not v then
		Log.event("Vault", "no VaultDoor in the map; CRACK THE VAULT is never drawn")
		return
	end
	setLights(false)
	paintBeacons(AMBER)
	-- The VAULT sign over the door.
	local sign = v.sign
	if sign then
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		gui.Parent = sign
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.LuckiestGuy
		label.Text = "VAULT"
		label.TextScaled = true
		label.TextColor3 = AMBER
		label.Parent = gui
	end
	RunService.Heartbeat:Connect(function()
		trackExits()
		if VaultJob.phase ~= "gas" then
			return
		end
		local t = now()
		local inside = playersInside()
		local insideSet: { [Player]: boolean } = {}
		for _, player in inside do
			insideSet[player] = true
			tint(player, true)
		end
		for player in table.clone(tinted) do
			if not insideSet[player] then
				tint(player, false)
			end
		end
		if t - lastGasTick >= Config.FieldTickSec then
			lastGasTick = t
			for _, player in inside do
				if PlayerState.isStanding(PlayerState.get(player)) then
					PlayerState.damage(player, Config.VaultGasDps * Config.FieldTickSec, "gas")
				end
			end
		end
		if #inside == 0 then
			seal()
		end
	end)
end

return VaultJob
