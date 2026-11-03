--!strict
-- Builds the ScreenGui and every HUD component, binds StateSync and Juice, rebuilds on big viewport changes.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local Signal = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Signal"))

local WaveBar = require(script.WaveBar)
local CallSlot = require(script.CallSlot)
local BuyColumn = require(script.BuyColumn)
local AbilityColumn = require(script.AbilityColumn)
local Currency = require(script.Currency)
local BottomCenter = require(script.BottomCenter)
local Ammo = require(script.Ammo)
local Crosshair = require(script.Crosshair)
local WorldFx = require(script.WorldFx)
local Toast = require(script.Toast)
local MobileControls = require(script.MobileControls)

export type Component = { update: ((any) -> ())?, onJuice: ((string, any) -> ())?, [string]: any }

local HUD = {
	Rebuilt = Signal.new(),
	gui = nil :: ScreenGui?,
	components = {} :: { [string]: Component },
}

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
		buy = BuyColumn.build(gui, track),
		abilities = AbilityColumn.build(gui, track),
		currency = Currency.build(gui, track),
		bottom = BottomCenter.build(gui, track),
		ammo = Ammo.build(gui, track),
		crosshair = Crosshair.build(gui, track),
		worldFx = WorldFx.build(gui, track),
		toast = Toast.build(gui, track),
		mobile = MobileControls.build(gui, track),
	}
	if ClientState.sync then
		HUD.update(ClientState.sync)
	end
	HUD.Rebuilt:Fire(HUD.components)
end

function HUD.update(sync: any)
	for _, c in HUD.components do
		if c.update then
			c.update(sync)
		end
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
