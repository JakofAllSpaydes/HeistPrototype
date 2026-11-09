--!strict
-- Brief 10 / Round 27c: the daily crate podium sheet, in every state. E at the podium (the server's Juice "DailySheet")
-- pushes the camera onto it (CameraShots.daily, the JOBS board's timing) and docks the compact sheet on the right (the
-- Skill Web's card; bottom-right at 42% of the width on a phone, the action under the thumb):
--   DAILY CRATE (the tier's colour) · LV N · X
--   Round 30d: the state beside the title (READY / PLAY A MATCH TO UNLOCK / NEW IN 21H 06M 12S, ticking), then one
--   big mystery frame (the possible rewards turning in it, darkened, under a big ?), the odds row
--   ready: OPEN · locked: BUY 1 · R$ 99 · claimed: ROLL AGAIN · R$ 79 (no BACK: Round 27i), and ×3 / ×10 spins under it
-- OPEN / a purchase -> the server rolls -> the existing crate scene -> back on the sheet (spin again at once).
-- The X, Esc or B (or a tap off the sheet) close it.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Wraps = require(Shared:WaitForChild("Wraps"))
local Catalog = require(Shared:WaitForChild("Catalog"))
local Clock = require(Shared:WaitForChild("Clock"))

local Client = script.Parent.Parent
local ClientState = require(Client:WaitForChild("ClientState"))
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local CloseButton = require(Client:WaitForChild("UI"):WaitForChild("CloseButton"))
local HUD = require(Client:WaitForChild("HUD"))
local PurchaseSheet = require(Client:WaitForChild("PurchaseSheet"))
local CameraShots = require(Client:WaitForChild("CameraShots"))
local Store = Client:WaitForChild("Store")
local Fx = require(Store:WaitForChild("Fx"))
local ModelIcon = require(Client:WaitForChild("UI"):WaitForChild("ModelIcon")) -- Round 30d: the mystery frame
local CrateScene = require(Store:WaitForChild("CrateScene"))

local DailySheet = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GREEN = Color3.fromHex("2FB75A")
local PANEL = Color3.fromHex("1C1C22")
local AMBER = Color3.fromHex("F2A93B")

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
		-- Round 30d: back to the sheet (spin again at once). The crate scene hands its camera back to our podium shot
		-- about 0.13 s after this; the sheet reopens on it with the podium's new state, the block and lock still held.
		task.delay(0.25, function()
			playing = false
			busy = false
			local st = player:GetAttribute("DailyCrate")
			DailySheet.open(if typeof(st) == "string" then st else "claimed", true)
		end)
	end)
end

-- Round 30d: the mystery frame. Every DailyMysteryCycleSec the next possible reward (a gun, a mask, a shop wrap on one
-- of your guns, round again; guns only while the first one's a gun) turns slowly in it, darkened, under a big ?.
local function mysteryCycle(frame: Frame, first: boolean, profile: any)
	local holder = UI.frame({
		Name = "Preview",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.86, 0.86),
		ZIndex = 22,
		Parent = frame,
	})
	local guns = Catalog.dailyItems("weapon", nil)
	local masks = Catalog.dailyItems("mask", nil)
	local shopWraps = {}
	for _, w in Wraps.List do
		if Wraps.perGun(w) then
			table.insert(shopWraps, w.id)
		end
	end
	local owned = {}
	for id in (if profile and profile.weapons then profile.weapons else {}) do
		table.insert(owned, id)
	end
	local order = if first then { "weapon" } else { "weapon", "mask", "wrap" }
	local step = 0
	local function nextItem(): { kind: string, id: string, on: string? }?
		step += 1
		local kind = order[(step - 1) % #order + 1]
		if kind == "mask" and #masks > 0 then
			return { kind = "mask", id = masks[math.random(#masks)].id }
		elseif kind == "wrap" and #shopWraps > 0 then
			local on = if #owned > 0 then owned[math.random(#owned)] else nil
			return { kind = "wrap", id = shopWraps[math.random(#shopWraps)], on = on }
		elseif #guns > 0 then
			return { kind = "weapon", id = guns[math.random(#guns)].id }
		end
		return nil
	end
	task.spawn(function()
		local current: ViewportFrame? = nil
		while frame.Parent do
			local it = nextItem()
			if it then
				local vp = ModelIcon.item(holder, it, UDim2.fromScale(1, 1), { motion = "always", zIndex = 22 })
				if vp then
					vp.AnchorPoint = Vector2.new(0.5, 0.5)
					vp.Position = UDim2.fromScale(0.5, 0.5)
					ModelIcon.tint(vp, Color3.fromRGB(34, 34, 42), 0.05) -- darkened: a shape, not the answer
					vp.ImageTransparency = 1
					UI.tween(vp, { ImageTransparency = 0.05 }, 0.3)
					local old = current
					current = vp
					if old then
						UI.tween(old, { ImageTransparency = 1 }, 0.25)
						task.delay(0.3, function()
							old:Destroy()
						end)
					end
				end
			end
			task.wait(math.max(0.3, Config.DailyMysteryCycleSec))
		end
	end)
end

-- `reopen`: back from a crate scene (the camera shot, the movement lock and the block are still held).
function DailySheet.open(state: string, reopen: boolean?)
	if gui or playing or not ClientState.inHub() or not Config.DailyCrateEnabled then
		return
	end
	if state ~= "ready" and state ~= "claimed" and state ~= "locked" then
		if reopen then
			release()
		end
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

	HUD.setMode("meta")
	if not reopen then
		ClientState.lockMovement("daily", true)
		ClientState.setBlock("daily", true)
		local shot = CameraShots.daily()
		if shot then
			CameraShots.push(shot)
		end
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
	local closeSize = CloseButton.size()
	local headH = math.max(T(30), closeSize) -- the header row holds the shared X
	local mysteryH = if mobile then math.floor(w * 0.5) else S(176)
	local oddsH = T(22)
	local btnH = if mobile then math.max(48, S(56)) else S(52)
	local multiH = if mobile then math.max(40, S(44)) else S(40)
	local multi = Config.DailyCrateEnabled -- Round 30d: ×3 / ×10 spins in every state
	-- Round 27i: no BACK button (the X, Esc / B and a tap off the sheet close it).
	local h = pad + headH + S(8) + mysteryH + S(8) + oddsH + S(12) + btnH + (if multi then S(8) + multiH else 0) + pad
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
	if not reopen then
		Fx.slideIn(s, UDim2.fromOffset(S(40), 0), 0.25)
	end

	-- Header: DAILY CRATE, its state (the live countdown) beside it, the shared X. Round 30d: no LV.
	local titleW = T(if mobile then 132 else 168)
	UI.text({
		Text = "DAILY CRATE",
		FontFace = Theme.Fonts.display,
		TextSize = T(if mobile then 22 else 28),
		TextColor3 = trim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(pad, pad),
		Size = UDim2.fromOffset(titleW, headH),
		ZIndex = 21,
		Parent = s,
	})
	local statusX = pad + titleW + S(8)
	local status = UI.text({
		Text = "",
		FontFace = Theme.Fonts.display,
		TextSize = T(if mobile then 13 else 16),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(statusX, pad),
		Size = UDim2.new(1, -statusX - pad - closeSize - S(6), 0, headH),
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
				status.Text = "NEW IN " .. untilTomorrow()
				task.wait(1)
			end
		end)
	else
		status.Text = "PLAY A MATCH TO UNLOCK"
		status.TextColor3 = AMBER
	end
	-- The shared red X (CloseButton), top-right in the header row.
	local x = CloseButton.new(s, DailySheet.close, { margin = pad, top = pad + (headH - closeSize) // 2, z = 21 })

	-- Round 30d: one big mystery frame: what it can give, darkened and turning under a big ?.
	local bodyY = pad + headH + S(8)
	local mystery = UI.frame({
		Name = "Mystery",
		BackgroundColor3 = PANEL,
		ClipsDescendants = true,
		Position = UDim2.fromOffset(pad, bodyY),
		Size = UDim2.new(1, -pad * 2, 0, mysteryH),
		ZIndex = 21,
		Parent = s,
	})
	UI.corner(mystery, S(4))
	UI.stroke(mystery, trim, S(1.5), 0.3)
	UI.new("UIGradient", {
		Color = ColorSequence.new(PANEL:Lerp(trim, 0.12), PANEL),
		Rotation = 90,
		Parent = mystery,
	})
	mysteryCycle(mystery, first, profile)
	local q = UI.text({
		Name = "Question",
		Text = "?",
		FontFace = Theme.Fonts.display,
		TextSize = math.floor(mysteryH * 0.62),
		TextColor3 = trim,
		TextTransparency = 0.1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 24,
		Parent = mystery,
	})
	q:SetAttribute("FixedTextSize", true)
	UI.stroke(q, Theme.Colors.black, S(3), 0.2)
	UI.text({
		Text = if first then "FIRST ONE'S A GUN" else "GUNS · MASKS · WRAPS",
		FontFace = Theme.Fonts.display,
		TextSize = T(14),
		TextColor3 = if first then Theme.Colors.gold else Theme.Colors.textDim,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -S(6)),
		Size = UDim2.new(1, -S(12), 0, T(18)),
		ZIndex = 24,
		Parent = mystery,
	})
	-- A slow breathe on the ? so the frame feels alive between swaps.
	task.spawn(function()
		local t0 = os.clock()
		while q.Parent do
			q.TextTransparency = 0.1 + 0.12 * (0.5 + 0.5 * math.sin((os.clock() - t0) * 2.5))
			task.wait(1 / 30)
		end
	end)

	-- The odds row: a chip per rarity the roll can land on, in its colour.
	local oddsY = bodyY + mysteryH + S(8)
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
	local handles: { any } = {}
	local function setAll(on: boolean)
		for _, hd in handles do
			hd.setEnabled(on)
		end
	end
	-- Buys `pid` through the purchase sheet; the crate scene plays and the sheet comes back after it.
	local function buy(pid: string)
		if busy then
			return
		end
		busy = true
		setAll(false)
		PurchaseSheet.open(pid, {
			context = "daily crate " .. state,
			onSuccess = function(data: any)
				play(data)
			end,
			onClose = function(bought: boolean)
				if not bought and gui == g then
					busy = false
					setAll(true)
				end
			end,
		})
	end
	local main: TextButton? = nil
	if label ~= "" then
		local btn, handle = Fx.button(s, label, GREEN, Theme.Colors.white, UDim2.new(1, -pad * 2, 0, btnH), 22)
		table.insert(handles, handle)
		btn.Position = UDim2.fromOffset(pad, btnY)
		btn.TextSize = T(if mobile then 22 else 24)
		btn.Selectable = true
		btn:SetAttribute("NavDefault", true) -- brief 11: the pad lands on OPEN NOW / CRACK
		Fx.shine(btn)
		main = btn
		btn.Activated:Connect(function()
			if busy then
				return
			end
			local pid = productId
			if pid then
				buy(pid)
				return
			end
			busy = true
			setAll(false)
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
					setAll(true)
					local reason = if ok and typeof(res) == "table"
						then tostring(res.reason or "TRY AGAIN")
						else "TRY AGAIN"
					PurchaseSheet.toast(reason, Theme.Colors.red, true)
				end
			end)
		end)
	end
	-- Round 30d: ×3 and ×10 spins, smaller, in one row under the main button.
	if multi then
		local multiY = btnY + btnH + S(8)
		local half = (w - pad * 2 - S(8)) / 2
		for i, n in { 3, 10 } do
			local price = if n == 3 then Config.DailyCrateSpin3Price else Config.DailyCrateSpin10Price
			local b, handle = Fx.button(
				s,
				string.format("×%d · R$ %s", n, UI.fmtInt(price)),
				GREEN:Lerp(Color3.fromHex("121216"), 0.35),
				Theme.Colors.white,
				UDim2.fromOffset(half, multiH),
				22
			)
			table.insert(handles, handle)
			b.Position = UDim2.fromOffset(pad + (i - 1) * (half + S(8)), multiY)
			b.TextSize = T(if mobile then 16 else 18)
			b.Selectable = true
			b.Activated:Connect(function()
				buy("dailycrate_spin" .. n)
			end)
		end
	end
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = main or x
	end
	if not reopen then
		UI.sound(Fx.Sounds.whoosh, 1.1, 0.4)
	end
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
