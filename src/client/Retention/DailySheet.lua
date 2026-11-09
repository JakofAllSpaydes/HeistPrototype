--!strict
-- Brief 10: the daily crate podium sheet. E at a ready podium (the server's Juice "DailySheet") pushes the camera onto
-- the podium (CameraShots.daily, the JOBS board's timing) and docks the compact sheet on the right, the Skill Web's
-- card (bottom-right at 40% of the width on a phone, OPEN under the thumb):
--   tier tag (the tier's colour) · LV N
--   the crate in its tier colours beside GOLD DAILY CRATE, GUNS + MASKS · YOUR LEVEL BAND, FIRST ONE'S A GUN (once)
--   the odds row (the tier's weights over the pool, the same rule the server rolls with)
--   OPEN  (claimed: ROLL AGAIN · R$ 79 through the purchase sheet)
-- OPEN -> the server rolls -> the existing crate scene plays -> the camera comes back to the podium, now claimed, and
-- lets go. BACK, the X, Esc or B close it.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Crates = require(Shared:WaitForChild("Crates"))
local Catalog = require(Shared:WaitForChild("Catalog"))

local Client = script.Parent.Parent
local ClientState = require(Client:WaitForChild("ClientState"))
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local Icons = require(Client:WaitForChild("UI"):WaitForChild("Icons"))
local HUD = require(Client:WaitForChild("HUD"))
local PurchaseSheet = require(Client:WaitForChild("PurchaseSheet"))
local CameraShots = require(Client:WaitForChild("CameraShots"))
local Store = Client:WaitForChild("Store")
local Fx = require(Store:WaitForChild("Fx"))
local ItemArt = require(Store:WaitForChild("ItemArt"))
local CrateScene = require(Store:WaitForChild("CrateScene"))

local DailySheet = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GREEN = Color3.fromHex("2FB75A")
local DARK = Color3.fromHex("2E3135")
local PANEL = Color3.fromHex("1C1C22")

local gui: ScreenGui? = nil
local busy = false
local playing = false -- the crate scene is up (the sheet is gone, the camera still ours)

local function tierId(): string
	local t = player:GetAttribute("DailyCrateTier")
	return if typeof(t) == "string" then t else "basic"
end

local function tierDef(): any
	return (Config.DailyCrateTierOdds :: any)[tierId()] or (Config.DailyCrateTierOdds :: any).basic
end

-- The roll's odds per rarity (rarities the pool lacks weigh nothing), as shares.
local function odds(gunOnly: boolean): { number }
	local def = tierDef()
	local kind = if gunOnly then "weapon" else nil
	local out, total = {}, 0
	for r = 1, 5 do
		out[r] = if #Catalog.dailyItems(kind, r) > 0 then (def.weights[r] or 0) else 0
		total += out[r]
	end
	for r = 1, 5 do
		out[r] = if total > 0 then out[r] / total else 0
	end
	return out
end

local function teardown()
	local g = gui
	gui = nil
	if g then
		g:Destroy()
	end
end

-- Everything back: the camera, the HUD, movement.
local function release()
	teardown()
	busy = false
	playing = false
	CameraShots.release()
	ClientState.setBlock("daily", false)
	ClientState.lockMovement("daily", false)
	if ClientState.inHub() then
		HUD.setMode(HUD.baseMode())
	end
end

function DailySheet.isOpen(): boolean
	return gui ~= nil or playing
end

function DailySheet.close()
	if playing then
		return
	end
	if gui then
		UI.sound(Fx.Sounds.whoosh, 0.7, 0.3)
	end
	release()
end

-- The crate the server rolled: hide the sheet, play the crate scene, come back to the podium, let go.
local function play(data: any)
	if typeof(data) ~= "table" or typeof(data.results) ~= "table" or #data.results == 0 then
		busy = false
		return
	end
	playing = true
	teardown()
	CrateScene.play(tostring(data.crateId), data.results, nil, function()
		local shot = CameraShots.daily()
		if shot then
			CameraShots.push(shot, 0.01)
		end
		task.delay(1.4, function()
			release()
		end)
	end)
end

function DailySheet.open(state: string)
	if gui or playing or not ClientState.inHub() or not Config.DailyCrateEnabled then
		return
	end
	if state ~= "ready" and state ~= "claimed" then
		return
	end
	local claimed = state == "claimed"
	local S = UI.S
	local mobile = ClientState.isMobile
	-- Phones draw at about half the desktop scale: text reads the store's MobileStoreTextScale bigger there.
	local function T(n: number): number
		return if mobile then math.round(S(n) * (Config.MobileStoreTextScale or 1)) else S(n)
	end
	local vp = (workspace.CurrentCamera :: Camera).ViewportSize
	local def = tierDef()
	local trim = Color3.fromHex(def.trim)
	local first = player:GetAttribute("DailyCrateFirst") == true and not claimed
	local profile = ClientState.sync and (ClientState.sync :: any).profile
	local level = if profile then tonumber(profile.level) or 1 else 1

	ClientState.lockMovement("daily", true)
	ClientState.setBlock("daily", true)
	HUD.setMode("meta")
	local shot = CameraShots.daily()
	if shot then
		CameraShots.push(shot)
	end

	local g = UI.new("ScreenGui", {
		Name = "DailySheet",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 9,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	}) :: ScreenGui
	gui = g
	-- A tap anywhere off the sheet closes it.
	local backdrop = UI.button({
		Name = "Backdrop",
		Text = "",
		Selectable = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = g,
	})
	backdrop.Activated:Connect(DailySheet.close)

	local w = if mobile then math.floor(vp.X * 0.4) else S(390)
	local margin = S(14)
	local pad = S(14)
	local headH = if mobile then T(24) else S(22)
	local wellSize = if mobile then math.floor(w * 0.26) else S(92)
	local oddsH = T(if mobile then 22 else 24)
	local nameH = if mobile then T(26) else S(32) -- the name line; the lines under it step by this
	local btnH = if mobile then math.max(48, S(56)) else S(52)
	local backH = S(if mobile then 34 else 30)
	local h = pad + headH + S(10) + wellSize + S(10) + oddsH + S(12) + btnH + S(8) + backH + pad
	local s = UI.button({
		Name = "Sheet",
		Text = "",
		Selectable = false,
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromHex("121216"),
		AnchorPoint = if mobile then Vector2.new(1, 1) else Vector2.new(1, 0.5),
		Position = if mobile then UDim2.new(1, -margin, 1, -margin) else UDim2.new(1, -margin, 0.5, 0),
		Size = UDim2.fromOffset(w, h),
		Active = true,
		ZIndex = 20,
		Parent = g,
	})
	UI.corner(s, S(6))
	UI.stroke(s, trim, S(1.5), 0.3)
	Fx.slideIn(s, UDim2.fromOffset(S(40), 0), 0.25)

	local tag = UI.text({
		Text = string.upper(def.name),
		FontFace = Theme.Fonts.display,
		TextSize = T(14),
		TextColor3 = Theme.Colors.bg,
		BackgroundTransparency = 0,
		BackgroundColor3 = trim,
		Position = UDim2.fromOffset(pad, pad),
		Size = UDim2.fromOffset(0, headH),
		AutomaticSize = Enum.AutomaticSize.X,
		ZIndex = 21,
		Parent = s,
	})
	UI.pad(tag, S(8), 0, S(8), 0)
	UI.corner(tag, S(3))
	UI.text({
		Text = "LV " .. level,
		FontFace = Theme.Fonts.display,
		TextSize = T(14),
		TextColor3 = Theme.Colors.textDim,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -(pad + headH + S(8)), 0, pad),
		Size = UDim2.fromOffset(S(90), headH),
		ZIndex = 21,
		Parent = s,
	})
	local x = UI.button({
		Name = "Close",
		Text = "",
		BackgroundColor3 = DARK,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -pad, 0, pad),
		Size = UDim2.fromOffset(headH, headH),
		ZIndex = 21,
		Parent = s,
	})
	UI.corner(x, S(3))
	Icons.fit(x, "close", 0.6, Theme.Colors.white).ZIndex = 22
	x.Activated:Connect(DailySheet.close)

	-- The crate and its lines.
	local bodyY = pad + headH + S(10)
	local well = UI.frame({
		BackgroundColor3 = PANEL,
		Position = UDim2.fromOffset(pad, bodyY),
		Size = UDim2.fromOffset(wellSize, wellSize),
		ZIndex = 21,
		Parent = s,
	})
	UI.corner(well, S(4))
	UI.stroke(well, trim, S(1), 0.5)
	local art = ItemArt.draw(well, { kind = "crate", id = Crates.dailyId(tierId()), amount = 1 }, wellSize, 22)
	art.AnchorPoint = Vector2.new(0.5, 0.5)
	art.Position = UDim2.fromScale(0.5, 0.5)
	local textX = pad + wellSize + S(12)
	UI.text({
		Text = string.upper(def.name) .. " DAILY CRATE",
		FontFace = Theme.Fonts.display,
		TextSize = if mobile then T(20) else S(26),
		TextColor3 = Theme.Colors.white,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(textX, bodyY - S(2)),
		Size = UDim2.new(1, -textX - pad, 0, nameH),
		ZIndex = 21,
		Parent = s,
	})
	UI.text({
		Text = if claimed then "OPENED TODAY · BACK TOMORROW" else "GUNS + MASKS · YOUR LEVEL BAND",
		FontFace = Theme.Fonts.display,
		TextSize = T(if mobile then 14 else 16),
		TextColor3 = Theme.Colors.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Position = UDim2.fromOffset(textX, bodyY + nameH),
		Size = UDim2.new(1, -textX - pad, 0, T(20)),
		ZIndex = 21,
		Parent = s,
	})
	if first then
		UI.text({
			Text = "FIRST ONE'S A GUN",
			FontFace = Theme.Fonts.display,
			TextSize = T(if mobile then 15 else 17),
			TextColor3 = Theme.Colors.gold,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(textX, bodyY + nameH + T(22)),
			Size = UDim2.new(1, -textX - pad, 0, T(20)),
			ZIndex = 21,
			Parent = s,
		})
	end

	-- The odds row: a chip per rarity the roll can land on, in its colour.
	local oddsY = bodyY + wellSize + S(10)
	local row = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(pad, oddsY),
		Size = UDim2.new(1, -pad * 2, 0, oddsH),
		ZIndex = 21,
		Parent = s,
	})
	UI.list(row, Enum.FillDirection.Horizontal, S(4), Enum.HorizontalAlignment.Left)
	local shares = odds(first)
	local live = 0
	for r = 1, 5 do
		if shares[r] > 0 then
			live += 1
		end
	end
	for r = 1, 5 do
		if shares[r] > 0 then
			local chip = UI.text({
				Text = string.format("%d%%", math.max(1, math.round(shares[r] * 100))),
				FontFace = Theme.Fonts.display,
				TextSize = T(if mobile then 13 else 15),
				TextColor3 = Theme.Colors.bg,
				BackgroundTransparency = 0,
				BackgroundColor3 = Rarity.color(r),
				Size = UDim2.new(1 / live, -S(4), 1, 0),
				LayoutOrder = r,
				ZIndex = 22,
				Parent = row,
			})
			UI.corner(chip, S(3))
		end
	end

	-- The action.
	local btnY = oddsY + oddsH + S(12)
	local label = if claimed
		then string.format("ROLL AGAIN · R$ %s", UI.fmtInt(Config.DailyCrateRerollPrice))
		else "OPEN"
	local btn, handle = Fx.button(s, label, GREEN, Theme.Colors.white, UDim2.new(1, -pad * 2, 0, btnH), 22)
	btn.Position = UDim2.fromOffset(pad, btnY)
	btn.TextSize = T(if mobile then 22 else 24)
	btn.Selectable = true
	if not claimed then
		Fx.shine(btn)
	end
	local back, _b = Fx.button(s, "BACK", DARK, Theme.Colors.white, UDim2.new(1, -pad * 2, 0, backH), 22)
	back.Position = UDim2.fromOffset(pad, btnY + btnH + S(8))
	back.TextSize = T(16)
	back.Activated:Connect(DailySheet.close)
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = btn
	end

	btn.Activated:Connect(function()
		if busy then
			return
		end
		busy = true
		handle.setEnabled(false)
		if claimed then
			PurchaseSheet.open("dailycrate_reroll", {
				context = "daily crate roll again",
				onSuccess = function(data: any)
					play(data)
				end,
				onClose = function(bought: boolean)
					if not bought and gui == g then
						busy = false
						handle.setEnabled(true)
					end
				end,
			})
			return
		end
		task.spawn(function()
			local ok, res = pcall(function()
				return Remotes.DailyCrateOpen:InvokeServer()
			end)
			if gui ~= g then
				return
			end
			if ok and typeof(res) == "table" and res.ok then
				UI.sound(Fx.Sounds.pop, 1, 0.5)
				play(res)
			else
				busy = false
				handle.setEnabled(true)
				local reason = if ok and typeof(res) == "table"
					then tostring(res.reason or "TRY AGAIN")
					else "TRY AGAIN"
				PurchaseSheet.toast(reason, Theme.Colors.red, true)
			end
		end)
	end)
	UI.sound(Fx.Sounds.whoosh, 1.1, 0.4)
end

function DailySheet.init()
	ClientState.Juice:Connect(function(name: string, data: any)
		if name == "DailySheet" then
			DailySheet.open(if typeof(data) == "table" then tostring(data.state) else "")
		elseif name == "RunStartBegin" or name == "Downed" then
			if gui and not playing then
				release()
			end
		end
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if not gui or playing or PurchaseSheet.isOpen() then
			return
		end
		if (input.KeyCode == Enum.KeyCode.Escape and not gameProcessed) or input.KeyCode == Enum.KeyCode.ButtonB then
			DailySheet.close()
		end
	end)
end

return DailySheet
