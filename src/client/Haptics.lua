--!strict
-- Brief 11: rumble on the pad through HapticService. One pulse helper over the Config.Haptic* specs; listens to the
-- events that already exist (LocalFire, Hit, PlayerHit, DoorOpened, VaultOpen, Downed) so no other module calls it,
-- except the minigames and sprint, which use Haptics.pulse directly. Gamepad only, off with the settings toggle.
local HapticService = game:GetService("HapticService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))

local Haptics = {}

export type Spec = { motor: string, strength: number, sec: number, pulses: number?, gap: number? }

local PAD = Enum.UserInputType.Gamepad1
local MOTORS: { [string]: Enum.VibrationMotor } = {
	Small = Enum.VibrationMotor.Small,
	Large = Enum.VibrationMotor.Large,
}
-- Each motor's current pulse: a token so a newer pulse's stop is the one that counts.
local tokens: { [string]: number } = { Small = 0, Large = 0 }
local buzz = 0 -- the auto-fire buzz's strength while RT is held (0 = off)

function Haptics.enabled(): boolean
	if ClientState.inputDevice ~= "gamepad" or not ClientState.inputSettings().haptics then
		return false
	end
	local ok, supported = pcall(function()
		return HapticService:IsVibrationSupported(PAD)
	end)
	return ok and supported == true
end

local function setMotor(motor: string, strength: number)
	local m = MOTORS[motor]
	if not m then
		return
	end
	pcall(function()
		HapticService:SetMotor(PAD, m, strength)
	end)
end

-- One pulse (or `pulses` of them, `gap` apart). Ignored when haptics are off or the pad has no motors.
function Haptics.pulse(spec: Spec?, force: boolean?)
	if not spec or (not force and not Haptics.enabled()) then
		return
	end
	local motor = spec.motor
	local n = math.max(1, spec.pulses or 1)
	tokens[motor] = (tokens[motor] or 0) + 1
	local token = tokens[motor]
	task.spawn(function()
		for i = 1, n do
			if tokens[motor] ~= token then
				return
			end
			setMotor(motor, spec.strength)
			task.wait(spec.sec)
			if tokens[motor] ~= token then
				return
			end
			setMotor(motor, if motor == "Small" then buzz else 0)
			if i < n then
				task.wait(spec.gap or 0.3)
			end
		end
	end)
end

-- The held gun's kind (GunModels writes GunKind on HeldGun).
local function gunKind(): string
	local char = Players.LocalPlayer.Character
	local gun = char and char:FindFirstChild("HeldGun")
	local kind = gun and gun:GetAttribute("GunKind")
	return if typeof(kind) == "string" then kind else "default"
end

local function fireSpec(): Spec
	local all = Config.HapticFire :: any
	return all[gunKind()] or all.default
end

-- Every motor off now (leaving a run, haptics switched off, the pad gone).
function Haptics.stop()
	buzz = 0
	for motor in MOTORS do
		tokens[motor] = (tokens[motor] or 0) + 1
		setMotor(motor, 0)
	end
end

-- Debug Haptics test: every event once, a beat apart.
function Haptics.test()
	task.spawn(function()
		for _, spec in
			{
				Config.HapticFire.pistol,
				Config.HapticFire.shotgun,
				Config.HapticHit,
				Config.HapticHeadshot,
				Config.HapticDamage,
				Config.HapticDoor,
				Config.HapticDowned,
				Config.HapticSprint,
			} :: { any }
		do
			Haptics.pulse(spec, true)
			task.wait(
				math.max(0.5, (spec.sec or 0.1) * (spec.pulses or 1) + (spec.gap or 0) * ((spec.pulses or 1) - 1) + 0.3)
			)
		end
	end)
end

function Haptics.init()
	ClientState.Juice:Connect(function(name: string, data: any)
		if name == "LocalFire" then
			local spec = fireSpec()
			if gunKind() == "pistol" or gunKind() == "shotgun" or gunKind() == "sniper" or gunKind() == "launcher" then
				Haptics.pulse(spec)
			elseif Haptics.enabled() then
				-- auto guns: a light buzz that holds while the trigger does (the Heartbeat below lets go of it)
				buzz = spec.strength * 0.6
				Haptics.pulse(spec)
			end
		elseif name == "Hit" and typeof(data) == "table" and not data.secondary then
			Haptics.pulse(if data.headshot then Config.HapticHeadshot else Config.HapticHit)
		elseif name == "PlayerHit" then
			Haptics.pulse(Config.HapticDamage)
		elseif name == "DoorOpened" or name == "VaultOpen" then
			Haptics.pulse(Config.HapticDoor)
		elseif name == "Downed" then
			Haptics.pulse(Config.HapticDowned)
		elseif name == "HubEnter" or name == "RunEndBegin" then
			Haptics.stop()
		end
	end)
	-- The auto buzz ends with the trigger (or a menu, or a device switch).
	RunService.Heartbeat:Connect(function()
		if buzz > 0 and (not ClientState.padFire or not Haptics.enabled()) then
			buzz = 0
			setMotor("Small", 0)
		end
	end)
	ClientState.DeviceChanged:Connect(function(d: string)
		if d ~= "gamepad" then
			Haptics.stop()
		end
	end)
	UserInputService.GamepadDisconnected:Connect(function()
		buzz = 0
	end)
end

return Haptics
