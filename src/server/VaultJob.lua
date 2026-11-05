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
local BagSpots = require(Shared.BagSpots)
local Lines = require(Shared.CrewCall.Lines)
local Room = require(script.Parent.Room)
local World = require(script.Parent.World)
local Log = require(script.Parent.Log)
local PlayerState = require(script.Parent.PlayerState)
local Minigames = require(script.Parent.Minigames)
local Bags = require(script.Parent.Bags)

local VaultJob = {}

local AMBER = Color3.fromHex("E8B64C")
local BLUE = Color3.fromHex("4D9FE8")
local GREY = Color3.fromHex("5A5E66")
local RED = Color3.fromHex("E8554D")
local GAS = Color3.fromRGB(150, 220, 110)

-- closed | job | open | warn | gas | sealed
VaultJob.phase = "closed"
VaultJob.doneThisRun = false

local prompt: ProximityPrompt? = nil
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
	local v = Room.vault
	if not v then
		return
	end
	for _, b in v.beacons do
		b.Color = color
	end
end

local function setLights(on: boolean, color: Color3?)
	local v = Room.vault
	if not v then
		return
	end
	for _, l in v.lights do
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

local function setFog(on: boolean)
	local v = Room.vault
	if not v or not v.gas then
		return
	end
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
		e.Parent = v.gas
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
		if root and Room.insideVault(root.Position) then
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

-- Can CRACK THE VAULT be drawn this wave?
function VaultJob.available(wave: number): boolean
	if not Room.vault then
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
	local v = Room.vault
	return if v then v.front else Vector3.zero
end

-- Safe dial tier from the wave bracket (1..3).
local function tierFor(wave: number): number
	return math.clamp(Rarity.bracketIndex(wave), 1, 3)
end

-- The job was drawn: blue frame, a CRACK prompt on the door that opens the Safe dial. `onCracked` is
-- CrewCall finishing the job (which then calls VaultJob.open).
function VaultJob.startJob(onCracked: (Player) -> ())
	local v = Room.vault
	if not v then
		return
	end
	if VaultJob.phase == "sealed" then
		-- Drawn again after a seal (VaultJobOnce false): back to a closed, unlit vault.
		runToken += 1
		setFog(false)
		setLights(false)
		v.door.CFrame = v.doorClosed
	end
	VaultJob.phase = "job"
	paintBeacons(BLUE)
	removePrompt()
	local p = Instance.new("ProximityPrompt")
	p.ActionText = Lines.vault.promptAction
	p.ObjectText = Lines.vault.promptObject
	p.KeyboardKeyCode = Enum.KeyCode.F
	p.HoldDuration = 0
	p.MaxActivationDistance = 9
	p.RequiresLineOfSight = false
	p.Parent = v.door
	p.Triggered:Connect(function(player: Player)
		if VaultJob.phase ~= "job" then
			return
		end
		Minigames.open(player, "Safe", {
			position = v.front,
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
		paintBeacons(AMBER)
	end
end

local function seal()
	VaultJob.phase = "sealed"
	setFog(false)
	setLights(false)
	slideDoor(false)
	paintBeacons(GREY)
	for player in table.clone(tinted) do
		tint(player, false)
	end
	World.fireRun("VaultSealed", { position = VaultJob.front(), label = Lines.vault.sealedLabel })
	Log.event("Vault", "sealed")
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
	local v = Room.vault
	if
		not v
		or VaultJob.phase == "open"
		or VaultJob.phase == "warn"
		or VaultJob.phase == "gas"
		or VaultJob.phase == "sealed"
	then
		return
	end
	removePrompt()
	VaultJob.phase = "open"
	VaultJob.doneThisRun = true
	runToken += 1
	local token = runToken
	endsAt = now() + Config.VaultOpenSec
	warnAt = endsAt - Config.VaultGasWarnSec
	slideDoor(true)
	setLights(true)
	paintBeacons(AMBER)
	Bags.burstAtSpots(BagSpots.Vault, Config.VaultBurstCash, Config.VaultBurstGold, true)
	World.fireRun("VaultOpen", {
		position = v.front,
		endsAt = endsAt,
		warnAt = warnAt,
		openSec = Config.VaultOpenSec,
		name = Lines.vault.pillName,
		toast = Lines.vault.openToast,
		hint = Lines.vault.lootHint,
	})
	Log.event("Vault", "open for %ds, gas at %ds", Config.VaultOpenSec, Config.VaultGasWarnSec)
	task.delay(math.max(0, warnAt - now()), function()
		if token == runToken then
			startWarn()
		end
	end)
	task.delay(math.max(0, endsAt - now()), function()
		if token == runToken then
			startGas()
		end
	end)
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
	VaultJob.doneThisRun = false
	setFog(false)
	setLights(false)
	paintBeacons(AMBER)
	local v = Room.vault
	if v then
		v.door.CFrame = v.doorClosed
	end
	for player in table.clone(tinted) do
		tint(player, false)
	end
	tinted = {}
end

function VaultJob.init()
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
