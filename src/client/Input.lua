--!strict
-- Brief 11: the gamepad's way in. GamepadMap (shared, pure) decides what a pad input means; this module feeds it the
-- real InputObjects and runs each action down the path the keyboard / touch already use, so the run code never asks
-- which device it is. It also owns the input device (ClientState.inputDevice, with the switch debounce), the
-- "a prompt is up" flag the X rule needs, the Input monitor's log and the per-wave assist hit rates.
local ContextActionService = game:GetService("ContextActionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Signal = require(Shared:WaitForChild("Signal"))
local GamepadMap = require(Shared:WaitForChild("GamepadMap"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))

local Input = {}

export type LogEntry = { t: number, raw: string, action: string }
Input.log = {} :: { LogEntry } -- newest last, at most LOG_MAX (the Input monitor)
Input.Logged = Signal.new()
Input.forcedDevice = nil :: string? -- debug Force device
local LOG_MAX = 14

local router = GamepadMap.newRouter()
local tracker = GamepadMap.newDeviceTracker(ClientState.inputDevice)

local function record(raw: string, action: string)
	table.insert(Input.log, { t = os.clock(), raw = raw, action = action })
	while #Input.log > LOG_MAX do
		table.remove(Input.log, 1)
	end
	Input.Logged:Fire()
end

------------------------------------------------------------------ device

local function setDevice(d: string)
	if ClientState.inputDevice == d then
		return
	end
	ClientState.inputDevice = d
	print("[GHS Input] device " .. d)
	ClientState.DeviceChanged:Fire(d)
end

local function seeInput(input: InputObject)
	if Input.forcedDevice then
		return
	end
	local mag: number? = nil
	local key = input.KeyCode.Name
	if key == "Thumbstick1" or key == "Thumbstick2" then
		mag = Vector2.new(input.Position.X, input.Position.Y).Magnitude
	elseif key == "ButtonL2" or key == "ButtonR2" then
		mag = if input.UserInputState == Enum.UserInputState.Begin and input.Position.Z == 0
			then 1
			else input.Position.Z
	end
	local d = GamepadMap.deviceOf(input.UserInputType.Name, key, mag)
	if tracker:see(d, os.clock()) then
		setDevice(tracker.current)
	end
end

function Input.forceDevice(d: string?)
	Input.forcedDevice = d
	if d then
		tracker.current = d
		setDevice(d)
	end
end

UserInputService.InputBegan:Connect(seeInput)
UserInputService.InputChanged:Connect(function(input: InputObject)
	local t = input.UserInputType.Name
	if string.sub(t, 1, 7) == "Gamepad" then
		seeInput(input)
	end
end)
UserInputService.TouchStarted:Connect(seeInput)

-- A pad already in use when the client starts (Studio with the DualSense) begins on the pad.
do
	local last = UserInputService:GetLastInputType()
	if string.sub(last.Name, 1, 7) == "Gamepad" then
		tracker.current = "gamepad"
		setDevice("gamepad")
	end
end

------------------------------------------------------------------ prompts (the X rule)

local shownPrompts: { [ProximityPrompt]: boolean } = {}
local function refreshPrompts()
	for p in shownPrompts do
		if not p.Parent or not p.Enabled then
			shownPrompts[p] = nil
		end
	end
	ClientState.promptVisible = next(shownPrompts) ~= nil
end
ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
	shownPrompts[prompt] = true
	refreshPrompts()
end)
ProximityPromptService.PromptHidden:Connect(function(prompt: ProximityPrompt)
	shownPrompts[prompt] = nil
	refreshPrompts()
end)

------------------------------------------------------------------ actions

local ABILITY = { ability1 = 1, ability2 = 2, ability3 = 3 }

local function dispatch(action: string, phase: string)
	local on = phase == "begin"
	if action == "fire" then
		ClientState.padFire = on
		if not on then
			ClientState.Juice:Fire("PadFireReleased")
		end
	elseif action == "ads" then
		if on then
			if ClientState.canAds() and not ClientState.sprinting then
				ClientState.setAds(true)
			end
		else
			ClientState.setAds(false)
		end
	elseif action == "reload" then
		ClientState.Juice:Fire("LocalReload")
	elseif action == "interact" then
		ClientState.padInteract = on
	elseif action == "swap" then
		if not ClientState.combatOff() and not UserInputService:GetFocusedTextBox() then
			Remotes.SwitchWeapon:FireServer()
		end
	elseif ABILITY[action] then
		ClientState.Juice:Fire("UseAbilitySlot", { slot = ABILITY[action] })
	elseif action == "sprint" then
		ClientState.Juice:Fire("PadSprint", { on = on })
	elseif action == "dealerTeleport" or action == "dealerPrev" or action == "dealerNext" or action == "dealerBuy" then
		ClientState.Juice:Fire("PadDealer", { action = action })
	elseif action == "voteSkip" then
		if ClientState.dealerActive then
			ClientState.Juice:Fire("PadDealer", { action = action })
		else
			ClientState.Juice:Fire("PadVoteSkip")
		end
	elseif action == "scoreboard" then
		ClientState.Juice:Fire("ScoreboardHold", { on = on })
	elseif action == "settings" then
		ClientState.Juice:Fire("OpenSettings")
	end
end

local function ctx(): GamepadMap.Ctx
	local sync = ClientState.sync
	local s = ClientState.inputSettings()
	return {
		context = if ClientState.combatOff() then "hub" else "run",
		promptVisible = ClientState.promptVisible,
		reviveNearby = ClientState.reviveNearby,
		dealerActive = ClientState.dealerActive,
		dealerPanel = ClientState.dealerActive and ClientState.dealerFocus,
		intermission = sync ~= nil and sync.waveState == "Intermission",
		adsToggle = s.adsToggle,
		blocked = ClientState.blocked(),
	}
end

local function run(list: { GamepadMap.Emit }): string
	local names = {}
	for _, e in list do
		dispatch(e.action, e.phase)
		table.insert(names, e.action .. (if e.phase == "tap" then "" else " " .. e.phase))
	end
	return table.concat(names, ", ")
end

-- Every pad button the map can bind (both contexts), plus the triggers' analog travel.
local KEYS: { Enum.KeyCode } = {}
do
	local seen: { [string]: boolean } = {}
	for _, map in Config.GamepadMap do
		for key in map do
			if not seen[key] then
				seen[key] = true
				local ok, code = pcall(function()
					return (Enum.KeyCode :: any)[key]
				end)
				if ok and code then
					table.insert(KEYS, code)
				else
					warn("[GHS Input] GamepadMap names an unknown button " .. key)
				end
			end
		end
	end
end

local function onPad(_name: string, _state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if string.sub(input.UserInputType.Name, 1, 7) ~= "Gamepad" then
		return Enum.ContextActionResult.Pass
	end
	local out, sink = router:input(input, ctx(), os.clock())
	local key = input.KeyCode.Name
	local isTrigger = key == "ButtonL2" or key == "ButtonR2"
	-- The monitor: every press / release (the triggers' analog travel only when it changes the action).
	if input.UserInputState ~= Enum.UserInputState.Change or #out > 0 then
		local raw = key .. " " .. string.lower(input.UserInputState.Name)
		if isTrigger then
			raw ..= string.format(" %.2f", input.Position.Z)
		end
		local names = run(out)
		local action = if names ~= ""
			then names
			elseif GamepadMap.resolve(ctx().context, key) == "jump" then "jump (roblox)"
			elseif key == "ButtonX" then "prompt (roblox)"
			else "-"
		record(raw, action)
	end
	return if sink then Enum.ContextActionResult.Sink else Enum.ContextActionResult.Pass
end

ContextActionService:BindActionAtPriority(
	"GHSGamepad",
	onPad,
	false,
	Enum.ContextActionPriority.High.Value + 20,
	table.unpack(KEYS)
)

-- Buttons the map does not bind still show on the monitor (B, the D-pad in the hub, sticks clicking...).
UserInputService.InputBegan:Connect(function(input: InputObject)
	if string.sub(input.UserInputType.Name, 1, 7) ~= "Gamepad" then
		return
	end
	local key = input.KeyCode.Name
	if string.sub(key, 1, 10) == "Thumbstick" and key ~= "Thumbstick1" and key ~= "Thumbstick2" then
		return
	end
	if key == "Thumbstick1" or key == "Thumbstick2" then
		return
	end
	if GamepadMap.resolve(ctx().context, key) == nil then
		record(key .. " begin", if key == "ButtonB" then "back (screens)" else "-")
	end
end)

-- Held things let go when a screen opens, the pad goes away or the character dies.
local function letGo(why: string)
	local out = router:reset()
	if #out > 0 then
		record("(" .. why .. ")", run(out))
	end
	ClientState.padFire = false
	ClientState.padInteract = false
end
ClientState.BlockChanged:Connect(function()
	if ClientState.blocked() then
		letGo("screen")
	end
end)
UserInputService.GamepadDisconnected:Connect(function()
	letGo("pad off")
end)

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	if not Input.forcedDevice and tracker:tick(now) then
		setDevice(tracker.current)
	end
	local out = router:tick(ctx(), now)
	if #out > 0 then
		record("ButtonSelect held", run(out))
	end
end)

------------------------------------------------------------------ assist hit rate per device, per wave

local shots: { [string]: number } = {}
local hits: { [string]: number } = {}
local lastHitAt = 0
local lastWave: number? = nil
ClientState.Juice:Connect(function(name: string, data: any)
	if name == "LocalFire" then
		local d = ClientState.inputDevice
		shots[d] = (shots[d] or 0) + 1
	elseif name == "Hit" and typeof(data) == "table" and not data.secondary then
		-- A shotgun's pellets land as several hits from one shot: count one per shot window.
		local now = os.clock()
		if now - lastHitAt > 0.05 then
			local d = ClientState.inputDevice
			hits[d] = (hits[d] or 0) + 1
		end
		lastHitAt = now
	end
end)
ClientState.Changed:Connect(function(sync: any)
	local wave = tonumber(sync.wave)
	if wave == nil or wave == lastWave then
		return
	end
	if lastWave ~= nil then
		for d, n in shots do
			if n > 0 then
				print(string.format("[GHS Input] assist %s hits %d/%d (wave %d)", d, hits[d] or 0, n, lastWave))
			end
		end
	end
	lastWave = wave
	shots, hits = {}, {}
end)

return Input
