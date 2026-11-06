--!strict
-- Brief 6: the fake purchase popup, modeled on the Roblox purchase prompt so the rhythm matches the real one: item
-- art, name, R$ price, a green `Buy for R$ <price>` and Cancel. Confirm → a PurchaseProcessingSec spinner →
-- Remotes.Purchase → a success toast (`<item> purchased!`, chime, sparks) and the sheet closes, or a decline. Short
-- of Robux the button reads `Not enough Robux` and GET ROBUX sits under it (the placeholder top-up). The same sheet
-- runs in a run and freezes nothing. Replacing this module and server Purchases.lua is the real integration.
--   PurchaseSheet.open(productId, opts)          one product
--   PurchaseSheet.choose(title, productIds, opts) a short list (cash packs), tap one to confirm it
--   PurchaseSheet.getRobux(opts)                  the GET ROBUX placeholder
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Products = require(Shared:WaitForChild("Products"))
local Rewards = require(Shared:WaitForChild("Rewards"))

local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local StoreFolder = script.Parent:WaitForChild("Store")
local Fx = require(StoreFolder:WaitForChild("Fx"))
local ItemArt = require(StoreFolder:WaitForChild("ItemArt"))

export type Opts = {
	onSuccess: ((any, Products.Product) -> ())?, -- the server's response data and the product
	onClose: ((boolean) -> ())?, -- true when something was bought
	context: string?, -- for the purchase log ("downed", "store FEATURED")
	args: any?, -- passed to the server handler
	title: string?,
	note: string?, -- a line over the button (why this sheet opened)
}

local PurchaseSheet = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local SHEET_BG = Color3.fromHex("232527")
local SHEET_BG2 = Color3.fromHex("2E3135")
local GREEN = Color3.fromHex("2FB75A")
local GREEN_DARK = Color3.fromHex("1E7A3B")

local gui: ScreenGui? = nil
local panel: Frame? = nil
local openNow = false
local busy = false
local current: Opts? = nil
local bought = false
local toastToken = 0

local function balance(): number
	local sync = ClientState.sync
	local p = sync and sync.profile
	return if p and typeof(p.fakeRobux) == "number" then p.fakeRobux else 0
end

local function priceOf(product: any): number
	local sync = ClientState.sync
	return Products.priceFor(product, sync and sync.profile)
end

local function ensureGui(): ScreenGui
	local g = gui
	if g and g.Parent then
		return g
	end
	local ng = UI.new("ScreenGui", {
		Name = "PurchaseSheet",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 60,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	}) :: ScreenGui
	gui = ng
	return ng
end

------------------------------------------------------------------ Toast
-- `<item> purchased!` top-center, with sparks; also used for the in-scene grant lines.
function PurchaseSheet.toast(text: string, color: Color3?, sound: boolean?)
	local S = UI.S
	local g = ensureGui()
	toastToken += 1
	local token = toastToken
	local old = g:FindFirstChild("Toast")
	if old then
		old:Destroy()
	end
	local pill = UI.frame({
		Name = "Toast",
		BackgroundColor3 = SHEET_BG,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, S(24)),
		Size = UDim2.fromOffset(0, S(44)),
		AutomaticSize = Enum.AutomaticSize.X,
		ZIndex = 80,
		Parent = g,
	})
	UI.corner(pill, S(22))
	UI.stroke(pill, color or GREEN, S(2), 0)
	UI.pad(pill, S(20), 0, S(20), 0)
	UI.text({
		Text = text,
		Font = Theme.Fonts.display,
		TextSize = S(20),
		TextColor3 = color or Color3.fromHex("8FE3A1"),
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		ZIndex = 81,
		Parent = pill,
	})
	Fx.slideIn(pill, UDim2.fromOffset(0, -S(40)), 0.3)
	if sound ~= false then
		UI.sound(Fx.Sounds.chime, 1.2, 0.45)
	end
	task.delay(0.05, function()
		if pill.Parent then
			Fx.burst(g :: any, UDim2.new(0.5, 0, 0, S(46)), color or GREEN, 14, 79)
		end
	end)
	task.delay(1.9, function()
		if token == toastToken and pill.Parent then
			UI.tween(
				pill,
				{ Position = UDim2.new(0.5, 0, 0, -S(60)) },
				0.25,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.In
			)
			task.delay(0.3, function()
				pill:Destroy()
			end)
		end
	end)
end

------------------------------------------------------------------ Open / close
local function setState(on: boolean)
	if openNow == on then
		return
	end
	openNow = on
	ClientState.setBlock("purchase", on)
	Remotes.SheetState:FireServer(on)
end

function PurchaseSheet.close()
	local p = panel
	panel = nil
	local opts = current
	current = nil
	busy = false
	if p then
		local dim = p.Parent and p.Parent:FindFirstChild("Dim")
		UI.tween(p, { Position = p.Position + UDim2.fromOffset(0, UI.S(30)) }, 0.15)
		local group = p:FindFirstChildOfClass("UIScale")
		if group then
			UI.tween(group, { Scale = 0.9 }, 0.15)
		end
		task.delay(0.15, function()
			p:Destroy()
			if dim and not panel then
				dim:Destroy()
			end
		end)
	end
	setState(false)
	if opts and opts.onClose then
		opts.onClose(bought)
	end
	bought = false
end

function PurchaseSheet.isOpen(): boolean
	return openNow
end

-- The sheet's frame: dim, panel, header with the title and X. Returns the content list frame.
local function frame(title: string): Frame
	local S = UI.S
	local g = ensureGui()
	if panel then
		panel:Destroy()
		panel = nil
	end
	local dim = g:FindFirstChild("Dim") :: Frame?
	if not dim then
		local d = UI.frame({
			Name = "Dim",
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 1,
			Parent = g,
		})
		UI.tween(d, { BackgroundTransparency = 0.55 }, 0.15)
		dim = d
	end
	local w = if ClientState.isMobile then S(360) else S(400)
	local p = UI.frame({
		Name = "Sheet",
		BackgroundColor3 = SHEET_BG,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(w, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Active = true,
		ZIndex = 10,
		Parent = g,
	})
	panel = p
	UI.corner(p, S(14))
	UI.stroke(p, Color3.new(1, 1, 1), S(1), 0.85)
	local scale = UI.new("UIScale", { Scale = 0.88, Parent = p })
	UI.tween(scale, { Scale = 1 }, 0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	UI.pad(p, S(18), S(14), S(18), S(18))
	UI.list(p, Enum.FillDirection.Vertical, S(12), Enum.HorizontalAlignment.Center)
	local header = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, S(30)),
		LayoutOrder = 0,
		ZIndex = 11,
		Parent = p,
	})
	UI.text({
		Text = title,
		Font = Theme.Fonts.body,
		TextSize = S(18),
		TextColor3 = Theme.Colors.white,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -S(40), 1, 0),
		ZIndex = 11,
		Parent = header,
	})
	local x = UI.button({
		Text = "X",
		Font = Theme.Fonts.display,
		TextSize = S(16),
		TextColor3 = Theme.Colors.textDim,
		BackgroundColor3 = SHEET_BG2,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(S(30), S(30)),
		ZIndex = 12,
		Parent = header,
	})
	UI.corner(x, S(15))
	Fx.interactive(x)
	x.Activated:Connect(function()
		if not busy then
			PurchaseSheet.close()
		end
	end)
	setState(true)
	return p
end

-- The item row: art in a rarity well, name, sub line, the R$ price.
local function itemRow(parent: Frame, product: any, price: number, order: number)
	local S = UI.S
	local row = UI.frame({
		BackgroundColor3 = SHEET_BG2,
		Size = UDim2.new(1, 0, 0, S(108)),
		LayoutOrder = order,
		ZIndex = 11,
		Parent = parent,
	})
	UI.corner(row, S(10))
	local rarity = if product.icon.kind == "robux" or product.icon.kind == "cash"
		then 3
		else Rewards.rarity(product.icon :: any)
	local wellColor = Fx.rarityColor(rarity)
	local well = UI.frame({
		BackgroundColor3 = Fx.shade(wellColor, -0.55),
		Position = UDim2.fromOffset(S(8), S(8)),
		Size = UDim2.fromOffset(S(92), S(92)),
		ZIndex = 12,
		Parent = row,
	})
	UI.corner(well, S(8))
	UI.stroke(well, wellColor, S(2), 0.1)
	UI.new("UIGradient", {
		Color = ColorSequence.new(Fx.shade(wellColor, -0.2), Fx.shade(wellColor, -0.7)),
		Rotation = 90,
		Parent = well,
	})
	local art = ItemArt.draw(well, product.icon :: any, S(76), 13)
	art.AnchorPoint = Vector2.new(0.5, 0.5)
	art.Position = UDim2.fromScale(0.5, 0.5)
	Fx.bob(art, S(2), 2.2)
	UI.text({
		Text = product.name,
		Font = Theme.Fonts.display,
		TextSize = S(19),
		TextColor3 = Theme.Colors.white,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Position = UDim2.fromOffset(S(112), S(10)),
		Size = UDim2.new(1, -S(120), 0, S(44)),
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 12,
		Parent = row,
	})
	if product.sub then
		UI.text({
			Text = product.sub,
			Font = Theme.Fonts.body,
			TextSize = S(11),
			TextColor3 = Theme.Colors.textDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			Position = UDim2.fromOffset(S(112), S(52)),
			Size = UDim2.new(1, -S(120), 0, S(26)),
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = 12,
			Parent = row,
		})
	end
	local priceRow = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(S(112), S(78)),
		Size = UDim2.new(1, -S(120), 0, S(22)),
		ZIndex = 12,
		Parent = row,
	})
	UI.list(priceRow, Enum.FillDirection.Horizontal, S(6), nil, Enum.VerticalAlignment.Center)
	Fx.robux(priceRow, S(18), 13)
	UI.text({
		Text = if price > 0 then UI.fmtInt(price) else "FREE",
		Font = Theme.Fonts.display,
		TextSize = S(20),
		TextColor3 = Theme.Colors.white,
		Size = UDim2.fromOffset(0, S(22)),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 2,
		ZIndex = 13,
		Parent = priceRow,
	})
	if product.kind == "vip" then
		UI.text({
			Text = "/ month",
			Font = Theme.Fonts.body,
			TextSize = S(12),
			TextColor3 = Theme.Colors.textDim,
			Size = UDim2.fromOffset(0, S(22)),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = 3,
			ZIndex = 13,
			Parent = priceRow,
		})
	end
end

local function line(parent: Frame, text: string, color: Color3, order: number, size: number?): TextLabel
	local S = UI.S
	return UI.text({
		Text = text,
		Font = Theme.Fonts.body,
		TextSize = S(size or 12),
		TextColor3 = color,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, S((size or 12) + 6)),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
		ZIndex = 11,
		Parent = parent,
	})
end

-- A spinner on the button while the purchase processes.
local function spinner(parent: GuiObject): Frame
	local S = UI.S
	local holder = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, S(14), 0.5, 0),
		Size = UDim2.fromOffset(S(24), S(24)),
		ZIndex = (parent.ZIndex or 1) + 2,
		Parent = parent,
	})
	for i = 1, 8 do
		local a = (i - 1) / 8 * math.pi * 2
		local dot = UI.frame({
			BackgroundColor3 = Theme.Colors.white,
			BackgroundTransparency = (i - 1) / 9,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, math.cos(a) * S(9), 0.5, math.sin(a) * S(9)),
			Size = UDim2.fromOffset(S(4), S(4)),
			ZIndex = holder.ZIndex,
			Parent = holder,
		})
		UI.corner(dot, S(2))
	end
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function(dt)
		if not holder.Parent then
			conn:Disconnect()
			return
		end
		holder.Rotation = (holder.Rotation + dt * 360) % 360
	end)
	return holder
end

local confirm: (any, Opts) -> ()

-- The decline view: the reason and OK.
local function declined(product: any, reason: string, opts: Opts)
	local S = UI.S
	local p = frame("Purchase declined")
	line(p, product.name, Theme.Colors.white, 1, 16)
	line(p, reason, Theme.Colors.malus, 2, 13)
	UI.sound(Fx.Sounds.deny, 1, 0.4)
	local ok, _ = Fx.button(p, "OK", SHEET_BG2, Theme.Colors.white, UDim2.new(1, 0, 0, S(48)), 12)
	ok.LayoutOrder = 3
	ok.Activated:Connect(function()
		PurchaseSheet.close()
	end)
	local _ = opts
end

-- Confirm → processing → server → success / decline.
local function buy(product: any, opts: Opts, button: TextButton)
	if busy then
		return
	end
	busy = true
	button.Text = "      Processing..."
	button.AutoButtonColor = false
	button.BackgroundColor3 = GREEN_DARK
	spinner(button)
	local t0 = os.clock()
	local payload = if typeof(opts.args) == "table" then table.clone(opts.args) else {}
	payload.context = opts.context
	local ok, resp = pcall(function()
		return Remotes.Purchase:InvokeServer(product.id, payload)
	end)
	local wait = Config.PurchaseProcessingSec - (os.clock() - t0)
	if wait > 0 then
		task.wait(wait)
	end
	busy = false
	if not panel then
		return
	end
	if not ok or typeof(resp) ~= "table" then
		declined(product, "The server did not answer. Nothing was charged.", opts)
		return
	end
	if not resp.ok then
		if resp.reason == "Not enough Robux" then
			confirm(product, opts) -- redraw: the button reads Not enough Robux now
			return
		end
		declined(product, tostring(resp.reason or "Declined"), opts)
		return
	end
	bought = true
	Fx.haptic(0.6)
	if product.kind ~= "robux_topup" then
		PurchaseSheet.toast(product.name .. " purchased!")
	else
		PurchaseSheet.toast(Fx.fmtRobux(Config.FakeRobuxTopUp) .. " added!")
	end
	local cb = opts.onSuccess
	PurchaseSheet.close()
	if cb then
		cb(resp.data, product)
	end
end

confirm = function(product: any, opts: Opts)
	local S = UI.S
	local price = priceOf(product)
	local bal = balance()
	local p = frame(opts.title or (if product.kind == "vip" then "Subscribe" else "Buy item"))
	itemRow(p, product, price, 1)
	if opts.note then
		line(p, opts.note, Theme.Colors.gold, 2, 12)
	end
	local short = bal < price
	local balLine = line(
		p,
		if short
			then string.format("Your balance: %s", Fx.fmtRobux(bal))
			else string.format("Your balance: %s  →  %s", Fx.fmtRobux(bal), Fx.fmtRobux(bal - price)),
		if short then Theme.Colors.malus else Theme.Colors.textDim,
		3,
		12
	)
	balLine.TextXAlignment = Enum.TextXAlignment.Left
	local h = if ClientState.isMobile then S(56) else S(52)
	local label = if short
		then "Not enough Robux"
		elseif price <= 0 then "Get for free"
		elseif product.kind == "vip" then string.format("Subscribe for R$ %s / month", UI.fmtInt(price))
		else string.format("Buy for R$ %s", UI.fmtInt(price))
	local btn, handle = Fx.button(
		p,
		label,
		if short then Color3.fromHex("4A4D52") else GREEN,
		Theme.Colors.white,
		UDim2.new(1, 0, 0, h),
		12
	)
	btn.TextSize = S(19)
	btn.LayoutOrder = 4
	handle.setEnabled(not short)
	btn.Activated:Connect(function()
		if not short then
			buy(product, opts, btn)
		end
	end)
	if short then
		local get, _ =
			Fx.button(p, "GET ROBUX", Color3.fromHex("2FD46A"), Color3.fromHex("0E2A17"), UDim2.new(1, 0, 0, h), 12)
		get.LayoutOrder = 5
		get.Activated:Connect(function()
			PurchaseSheet.getRobux({
				onClose = function()
					-- Back to the item with the new balance.
					task.defer(function()
						if not openNow then
							PurchaseSheet.open(product.id, opts)
						end
					end)
				end,
			})
		end)
		UI.shake(btn, S(3), 0.2)
		UI.sound(Fx.Sounds.deny, 1, 0.3)
	end
	local cancel = UI.button({
		Text = "Cancel",
		Font = Theme.Fonts.body,
		TextSize = S(15),
		TextColor3 = Theme.Colors.textDim,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, S(30)),
		LayoutOrder = 6,
		ZIndex = 12,
		Parent = p,
	})
	cancel.Activated:Connect(function()
		if not busy then
			UI.sound(Fx.Sounds.press, 0.9, 0.25)
			PurchaseSheet.close()
		end
	end)
end

function PurchaseSheet.open(productId: string, opts: Opts?)
	local product = Products.ById[productId]
	if not product then
		warn("[PurchaseSheet] no product " .. tostring(productId))
		return
	end
	if busy then
		return
	end
	bought = false
	current = opts or {}
	UI.sound(Fx.Sounds.whoosh, 1.3, 0.3)
	confirm(product, current :: Opts)
end

-- A short list of products (the cash packs, token packs): tap one to confirm it in the same sheet.
function PurchaseSheet.choose(title: string, productIds: { string }, opts: Opts?)
	local S = UI.S
	if busy then
		return
	end
	bought = false
	local o = opts or {}
	current = o
	local p = frame(title)
	if o.note then
		line(p, o.note, Theme.Colors.gold, 1, 12)
	end
	local rows: { GuiObject } = {}
	for i, id in productIds do
		local product = Products.ById[id]
		if not product then
			continue
		end
		local holder = UI.frame({
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, S(64)),
			LayoutOrder = 1 + i,
			ZIndex = 11,
			Parent = p,
		})
		local b = UI.button({
			BackgroundColor3 = SHEET_BG2,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 12,
			Parent = holder,
		})
		UI.corner(b, S(10))
		UI.stroke(b, Color3.new(1, 1, 1), S(1), 0.88)
		local art = ItemArt.draw(b, product.icon :: any, S(48), 13)
		art.AnchorPoint = Vector2.new(0, 0.5)
		art.Position = UDim2.new(0, S(8), 0.5, 0)
		UI.text({
			Text = product.name,
			Font = Theme.Fonts.display,
			TextSize = S(17),
			TextColor3 = Theme.Colors.white,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(S(66), S(8)),
			Size = UDim2.new(1, -S(170), 0, S(24)),
			ZIndex = 13,
			Parent = b,
		})
		if product.sub then
			UI.text({
				Text = product.sub,
				TextSize = S(11),
				TextColor3 = Theme.Colors.textDim,
				TextXAlignment = Enum.TextXAlignment.Left,
				Position = UDim2.fromOffset(S(66), S(34)),
				Size = UDim2.new(1, -S(170), 0, S(18)),
				ZIndex = 13,
				Parent = b,
			})
		end
		local pill = UI.frame({
			BackgroundColor3 = GREEN,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -S(10), 0.5, 0),
			Size = UDim2.fromOffset(S(92), S(34)),
			ZIndex = 13,
			Parent = b,
		})
		UI.corner(pill, S(8))
		UI.text({
			Text = "R$ " .. UI.fmtInt(priceOf(product)),
			Font = Theme.Fonts.display,
			TextSize = S(16),
			TextColor3 = Theme.Colors.white,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 14,
			Parent = pill,
		})
		Fx.interactive(b, { lift = holder })
		b.Activated:Connect(function()
			confirm(product, o)
		end)
		table.insert(rows, holder)
	end
	Fx.cascade(rows, 0.04)
	local cancel = UI.button({
		Text = "Cancel",
		Font = Theme.Fonts.body,
		TextSize = S(15),
		TextColor3 = Theme.Colors.textDim,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, S(30)),
		LayoutOrder = 99,
		ZIndex = 12,
		Parent = p,
	})
	cancel.Activated:Connect(function()
		PurchaseSheet.close()
	end)
	UI.sound(Fx.Sounds.whoosh, 1.3, 0.3)
end

-- GET ROBUX: the placeholder top-up so a tester can never get stuck.
function PurchaseSheet.getRobux(opts: Opts?)
	local o = opts or {}
	o.title = "Get Robux"
	o.note = "Prototype placeholder: no real Robux, this just tops up the fake balance."
	PurchaseSheet.open("robux_topup", o)
end

function PurchaseSheet.init()
	-- A dead character or a hub return never leaves the sheet's block behind.
	ClientState.Juice:Connect(function(name: string, data: any)
		if name == "HubEnter" and openNow and not busy then
			PurchaseSheet.close()
		elseif name == "CashPack" and typeof(data) == "table" then
			-- The cash lands in the HUD's cash row (it counts up); a quick burst marks it.
			UI.sound(Fx.Sounds.chime, 1.5, 0.3)
			ClientState.Juice:Fire("RarityFlash", { color = Theme.Colors.cash, alpha = 0.12 })
		elseif name == "VipRenewed" and typeof(data) == "table" then
			PurchaseSheet.toast(
				string.format("VIP RENEWED · +%d TOKENS", tonumber(data.tokens) or 0),
				Color3.fromHex("F2C14E")
			)
		end
	end)
end

return PurchaseSheet
