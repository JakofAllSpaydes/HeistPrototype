--!strict
-- Brief 10 / Round 27c: the daily crate podium sheet, in every state. E at the podium (the server's Juice "DailySheet")
-- pushes the camera onto it (CameraShots.daily, the JOBS board's timing) and docks the compact sheet on the right (the
-- Skill Web's card; bottom-right at 42% of the width on a phone, the action under the thumb):
--   DAILY CRATE (the tier's colour) · LV N · X
--   the crate beside its state line: PLAY A MATCH TO UNLOCK / READY / NEW CRATE IN 21H 06M 12S (ticking), the pool
--   line, FIRST ONE'S A GUN (while it applies)
--   what it can drop (the best few items of your band, framed in their rarity) and the odds row
--   ready: OPEN · locked: BUY 1 · R$ 99 · claimed: ROLL AGAIN · R$ 79 (no BACK: Round 27i)
-- OPEN / a purchase -> the server rolls -> the existing crate scene -> the camera comes back to the podium and lets go.
-- The X, Esc or B (or a tap off the sheet) close it.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Crates = require(Shared:WaitForChild("Crates"))
local Catalog = require(Shared:WaitForChild("Catalog"))
local Clock = require(Shared:WaitForChild("Clock"))

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
local AMBER = Color3.fromHex("F2A93B")
local CONTENTS = 6 -- item tiles shown

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

local function untilTomorrow(): string
	local now = ClientState.fakeNow()
	local sec = math.max(0, Clock.nextDay(now) - now)
	return string.format("%dH %02dM %02dS", sec // 3600, (sec % 3600) // 60, sec % 60)
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

-- The best few of the pool (rarest first), guns and masks mixed (guns only while the first one's a gun).
local function showcase(gunOnly: boolean): { Catalog.Item }
	local items = table.clone(Catalog.dailyItems(if gunOnly then "weapon" else nil, nil))
	table.sort(items, function(a, b)
		if a.rarity ~= b.rarity then
			return a.rarity > b.rarity
		end
		return a.id < b.id
	end)
	local out = {}
	local masks = 0
	for _, it in items do
		-- Keep the last slot for a mask when the pool has them, so the mix reads.
		if #out == CONTENTS - 1 and masks == 0 and not gunOnly and it.kind ~= "mask" then
			continue
		end
		if it.kind == "mask" then
			masks += 1
		end
		table.insert(out, it)
		if #out >= CONTENTS then
			break
		end
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
		-- Round 27g: control comes straight back. The crate scene hands its camera back to our shot about 0.13 s after
		-- this (its dip to black); letting go just after puts you behind your character while it is still black
		-- (holding the podium shot for ~2 s read as being stuck).
		task.delay(0.25, function()
			release()
		end)
	end)
end

function DailySheet.open(state: string)
	if gui or playing or not ClientState.inHub() or not Config.DailyCrateEnabled then
		return
	end
	if state ~= "ready" and state ~= "claimed" and state ~= "locked" then
		return
	end
	local S = UI.S
	local mobile = ClientState.isMobile
	local function T(n: number): number
		return if mobile then math.round(S(n) * (Config.MobileStoreTextScale or 1)) else S(n)
	end
	local vp = (workspace.CurrentCamera :: Camera).ViewportSize
	local def = tierDef()
	local trim = Color3.fromHex(def.trim)
	local first = player:GetAttribute("DailyCrateFirst") == true
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

	local w = if mobile then math.floor(vp.X * 0.42) else S(400)
	local margin = S(14)
	local pad = S(14)
	local headH = T(30)
	local wellSize = if mobile then math.floor(w * 0.24) else S(86)
	local tileGap = S(6)
	local tile = math.floor((w - pad * 2 - tileGap * (CONTENTS - 1)) / CONTENTS)
	local oddsH = T(22)
	local btnH = if mobile then math.max(48, S(56)) else S(52)
	-- Round 27i: no BACK button (the X, Esc / B and a tap off the sheet close it).
	local h = pad + headH + S(8) + wellSize + S(10) + tile + S(8) + oddsH + S(12) + btnH + pad
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

	-- Header.
	UI.text({
		Text = "DAILY CRATE",
		FontFace = Theme.Fonts.display,
		TextSize = T(if mobile then 22 else 28),
		TextColor3 = trim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(pad, pad),
		Size = UDim2.new(1, -pad * 2, 0, headH),
		ZIndex = 21,
		Parent = s,
	})
	UI.text({
		Text = "LV " .. level,
		FontFace = Theme.Fonts.display,
		TextSize = T(15),
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
	Icons.fit(x, "close", 0.55, Theme.Colors.white).ZIndex = 22
	x.Activated:Connect(DailySheet.close)

	-- The crate and its state.
	local bodyY = pad + headH + S(8)
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
	local status = UI.text({
		Text = "",
		FontFace = Theme.Fonts.display,
		TextSize = T(if mobile then 18 else 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(textX, bodyY),
		Size = UDim2.new(1, -textX - pad, 0, T(26)),
		ZIndex = 21,
		Parent = s,
	})
	if state == "ready" then
		status.Text = "READY"
		status.TextColor3 = Theme.Colors.health
	elseif state == "claimed" then
		status.TextColor3 = Theme.Colors.white
		task.spawn(function()
			while status.Parent do
				status.Text = "NEW CRATE IN " .. untilTomorrow()
				task.wait(1)
			end
		end)
	else
		status.Text = "PLAY A MATCH TO UNLOCK"
		status.TextColor3 = AMBER
	end
	UI.text({
		Text = "GUNS + MASKS · YOUR LEVEL",
		FontFace = Theme.Fonts.display,
		TextSize = T(14),
		TextColor3 = Theme.Colors.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(textX, bodyY + T(28)),
		Size = UDim2.new(1, -textX - pad, 0, T(18)),
		ZIndex = 21,
		Parent = s,
	})
	if first then
		UI.text({
			Text = "FIRST ONE'S A GUN",
			FontFace = Theme.Fonts.display,
			TextSize = T(15),
			TextColor3 = Theme.Colors.gold,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(textX, bodyY + T(48)),
			Size = UDim2.new(1, -textX - pad, 0, T(18)),
			ZIndex = 21,
			Parent = s,
		})
	end

	-- What it can drop.
	local contentsY = bodyY + wellSize + S(10)
	local strip = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(pad, contentsY),
		Size = UDim2.new(1, -pad * 2, 0, tile),
		ZIndex = 21,
		Parent = s,
	})
	UI.list(strip, Enum.FillDirection.Horizontal, tileGap, Enum.HorizontalAlignment.Left)
	for i, it in showcase(first) do
		local cell = UI.frame({
			BackgroundColor3 = PANEL,
			Size = UDim2.fromOffset(tile, tile),
			LayoutOrder = i,
			ZIndex = 21,
			Parent = strip,
		})
		UI.corner(cell, S(3))
		UI.stroke(cell, Rarity.color(it.rarity), S(1.5), 0.1)
		ItemArt.draw(cell, { kind = it.kind, id = it.id }, tile, 22)
	end

	-- The odds row: a chip per rarity the roll can land on, in its colour.
	local oddsY = contentsY + tile + S(8)
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
				TextSize = T(14),
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
	local productId: string? = nil
	local label = "OPEN"
	if state == "locked" then
		productId = "dailycrate_buy"
		label = string.format("BUY 1 · R$ %s", UI.fmtInt(Config.DailyCrateBuyPrice))
	elseif state == "claimed" then
		if Config.DailyCrateRerollEnabled then
			productId = "dailycrate_reroll"
			label = string.format("ROLL AGAIN · R$ %s", UI.fmtInt(Config.DailyCrateRerollPrice))
		else
			label = ""
		end
	end
	local main: TextButton? = nil
	if label ~= "" then
		local btn, handle = Fx.button(s, label, GREEN, Theme.Colors.white, UDim2.new(1, -pad * 2, 0, btnH), 22)
		btn.Position = UDim2.fromOffset(pad, btnY)
		btn.TextSize = T(if mobile then 22 else 24)
		btn.Selectable = true
		Fx.shine(btn)
		main = btn
		btn.Activated:Connect(function()
			if busy then
				return
			end
			busy = true
			handle.setEnabled(false)
			local pid = productId
			if pid then
				PurchaseSheet.open(pid, {
					context = "daily crate " .. state,
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
	end
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = main or x
	end
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
