--!strict
-- Builds the ScreenGui and every HUD component, binds StateSync and Juice, rebuilds on big viewport changes.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Signal = require(Shared:WaitForChild("Signal"))
local Config = require(Shared:WaitForChild("Config"))

local WaveBar = require(script.WaveBar)
local CallSlot = require(script.CallSlot)
local TopRight = require(script.TopRight)
local BuyColumn = require(script.BuyColumn)
local AbilityColumn = require(script.AbilityColumn)
local Currency = require(script.Currency)
local BottomCenter = require(script.BottomCenter)
local Ammo = require(script.Ammo)
local Crosshair = require(script.Crosshair)
local WorldFx = require(script.WorldFx)
local Toast = require(script.Toast)
local MobileControls = require(script.MobileControls)
local HubHUD = require(script.HubHUD)
local BossBar = require(script.BossBar)

export type Component = { update: ((any) -> ())?, onJuice: ((string, any) -> ())?, [string]: any }

local HUD = {
	Rebuilt = Signal.new(),
	gui = nil :: ScreenGui?,
	components = {} :: { [string]: Component },
	mode = "gameplay", -- gameplay | hub | meta | downed | spectate | cinematic | none
}

-- Top-level pieces a mode can hide. Toast and Combo show themselves, so a mode only ever hides them.
local MANAGED = {
	"WaveBar",
	"CallSlot",
	"TopRight",
	"BuyColumn",
	"AbilityColumn",
	"Currency",
	"BottomCenter",
	"Ammo",
	"Crosshair",
	"HurtVignette",
	"RarityFlash",
	"FireButton",
	"ADSButton",
	"ReloadButton",
	"HubHUD",
}
-- The boss bar shows itself (only while a boss is live); modes may hide it but never force it on.
local SELF_MANAGED = { Toast = true, Combo = true, BossBar = true }
-- Downed: buys and abilities go; with the sidearm (Config.DownedCanShoot) the crosshair, ammo and fire
-- controls stay so you can keep shooting from the floor.
local DOWNED_HIDE: { [string]: boolean } = if Config.DownedCanShoot
	then { BuyColumn = true, AbilityColumn = true, HubHUD = true }
	else {
		Crosshair = true,
		Ammo = true,
		BuyColumn = true,
		AbilityColumn = true,
		FireButton = true,
		ADSButton = true,
		ReloadButton = true,
		HubHUD = true,
	}
local MODES: { [string]: { hide: { [string]: boolean }?, only: { [string]: boolean }? } } = {
	gameplay = { hide = { HubHUD = true } },
	-- The hub: match HUD down (buy column, abilities, wave bar, health, ammo, held slot), hub layout up.
	hub = { only = { HubHUD = true, Toast = true } },
	-- Customization scene: it draws its own ScreenGui; the HUD holds only toasts.
	meta = { only = { Toast = true } },
	downed = { hide = DOWNED_HIDE },
	spectate = {
		hide = {
			Crosshair = true,
			Ammo = true,
			BuyColumn = true,
			AbilityColumn = true,
			FireButton = true,
			ADSButton = true,
			ReloadButton = true,
			BottomCenter = true,
			Currency = true,
			Combo = true,
			HubHUD = true,
		},
	},
	cinematic = { only = { WaveBar = true } },
	-- The boss cutscene: MARLOW's call in the top-right stack, nothing else.
	boss = { only = { TopRight = true, Toast = true } },
	none = { only = {} },
}

-- The mode the HUD rests in when nothing special is on: the hub layout in the hub, the match HUD in a run.
function HUD.baseMode(): string
	local sync = ClientState.sync
	return if sync and sync.waveState == "Hub" then "hub" else "gameplay"
end

-- Show or hide HUD pieces for a mode (downed, spectating, the run start / end sequences).
function HUD.setMode(mode: string)
	HUD.mode = mode
	local spec = MODES[mode] or MODES.gameplay
	local gui = HUD.gui
	if not gui then
		return
	end
	for _, child in gui:GetChildren() do
		if not child:IsA("GuiObject") then
			continue
		end
		local name = child.Name
		local managed = table.find(MANAGED, name) ~= nil
		if spec.only then
			if SELF_MANAGED[name] then
				-- Toast / Combo show themselves: a mode may hide them, never force them on (that left an empty
				-- toast bubble and a stale BLED OUT notice on screen in the hub).
				if not spec.only[name] then
					child.Visible = false
				end
			elseif managed then
				child.Visible = spec.only[name] == true
			end
		elseif spec.hide and spec.hide[name] then
			child.Visible = false
		elseif managed then
			child.Visible = true
		elseif name == "BossBar" then
			-- Back from a sequence or a mode that hid it: the live boss bar comes back with the match HUD.
			local sync = ClientState.sync
			child.Visible = sync ~= nil and sync.boss ~= nil
		end
	end
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = Workspace.CurrentCamera :: Camera
local connections: { RBXScriptConnection } = {}

function HUD.profile()
	return if ClientState.isMobile then Theme.Mobile else Theme.Desktop
end

local function track(conn: RBXScriptConnection)
	table.insert(connections, conn)
end

function HUD.build()
	for _, c in connections do
		c:Disconnect()
	end
	connections = {}
	if HUD.gui then
		HUD.gui:Destroy()
	end
	local p = HUD.profile()
	UI.scale = math.clamp(camera.ViewportSize.Y / p.scaleBasis, p.minScale, p.maxScale)

	local gui = UI.new("ScreenGui", {
		Name = "HUD",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 1,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	}) :: ScreenGui
	HUD.gui = gui

	HUD.components = {
		waveBar = WaveBar.build(gui, track),
		callSlot = CallSlot.build(gui, track),
		topRight = TopRight.build(gui, track),
		buy = BuyColumn.build(gui, track),
		abilities = AbilityColumn.build(gui, track),
		currency = Currency.build(gui, track),
		bottom = BottomCenter.build(gui, track),
		ammo = Ammo.build(gui, track),
		crosshair = Crosshair.build(gui, track),
		worldFx = WorldFx.build(gui, track),
		toast = Toast.build(gui, track),
		mobile = MobileControls.build(gui, track),
		hub = HubHUD.build(gui, track),
		bossBar = BossBar.build(gui, track),
	}
	if ClientState.sync then
		HUD.update(ClientState.sync)
	end
	HUD.setMode(HUD.mode)
	HUD.Rebuilt:Fire(HUD.components)
end

function HUD.update(sync: any)
	for _, c in HUD.components do
		if c.update then
			c.update(sync)
		end
	end
	-- Hub <-> match: the resting mode follows the sync; sequences and overlays set their own modes on top.
	local hubNow = sync.waveState == "Hub"
	if hubNow and HUD.mode == "gameplay" then
		HUD.setMode("hub")
	elseif not hubNow and HUD.mode == "hub" then
		HUD.setMode("gameplay")
	end
end

function HUD.get(name: string): any
	return HUD.components[name]
end

function HUD.init()
	HUD.build()
	ClientState.Changed:Connect(HUD.update)
	ClientState.Juice:Connect(function(name: string, data: any)
		for _, c in HUD.components do
			if c.onJuice then
				c.onJuice(name, data)
			end
		end
	end)
	local lastY = camera.ViewportSize.Y
	local pending = false
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		if pending then
			return
		end
		pending = true
		task.delay(0.5, function()
			pending = false
			local y = camera.ViewportSize.Y
			if math.abs(y - lastY) / math.max(lastY, 1) > 0.15 then
				lastY = y
				HUD.build()
			end
		end)
	end)
end

return HUD
