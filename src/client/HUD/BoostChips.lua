--!strict
-- Brief 6: the boost chips. Every active boost as a chip (Round 18: just the pictogram, with the live mm:ss
-- under it; no name or amount) plus VIP's permanent chip; a chip pulses in its last Config.BoostChipWarnSec and pops out on expiry with a toast. Used
-- twice: the hub HUD's BOOSTS corner (bottom-right, with the VIP daily gift chip and a + into the store) and the
-- match HUD (small, under the heat stars; below the boss bar while one is up).
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local BoostDefs = require(Shared:WaitForChild("BoostDefs"))
local Clock = require(Shared:WaitForChild("Clock"))

local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local Icons = require(Client:WaitForChild("UI"):WaitForChild("Icons"))
local ClientState = require(Client:WaitForChild("ClientState"))

local BoostChips = {}

local VIP_GOLD = Color3.fromHex("F2C14E")

-- Chip ids whose Icons.lua pictogram has another name (the rest use their own id).
local CHIP_ICONS: { [string]: string } = { tokens = "revive" }

export type Opts = {
	size: number, -- chip size, px (already scaled)
	align: Enum.HorizontalAlignment,
	hub: boolean, -- the hub corner: gift chip and the + tile
	onPlus: (() -> ())?,
	onGift: (() -> ())?,
	onTokens: (() -> ())?, -- hub: the revive token chip (×N instead of a timer) opens the token packs
}

export type Handle = { frame: Frame, update: (any) -> () }

local function vipActive(p: any): boolean
	return p ~= nil and p.vip ~= nil and p.vip.active == true
end

-- The VIP gift is claimable once per fake UTC day.
local function giftReady(p: any): boolean
	return vipActive(p) and Clock.day(ClientState.fakeNow()) > (tonumber(p.vipGiftDay) or 0)
end

function BoostChips.new(parent: Instance, opts: Opts, track: ((RBXScriptConnection) -> ())?): Handle
	local S = UI.S
	local size = opts.size
	local row = UI.frame({
		Name = "BoostChipRow",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, size + S(if opts.hub then 16 else 12)),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = parent,
	})
	UI.list(row, Enum.FillDirection.Horizontal, S(if opts.hub then 10 else 6), opts.align)
	type Chip = { holder: Frame, chip: Frame, timer: TextLabel?, id: string, warned: boolean }
	local chips: { [string]: Chip } = {}

	local function makeChip(id: string, order: number, glyph: string, color: Color3, clickable: (() -> ())?): Chip
		local holder = UI.frame({
			Name = id,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(size, size + S(if opts.hub then 16 else 12)),
			LayoutOrder = order,
			Parent = row,
		})
		local chip = (if clickable then UI.button({ Text = "", AutoButtonColor = false }) else UI.frame({})) :: any
		chip.Name = "Chip"
		chip.BackgroundColor3 = Theme.Colors.panel
		chip.Size = UDim2.fromOffset(size, size)
		chip.Parent = holder
		UI.corner(chip, math.floor(size * 0.2))
		UI.stroke(chip, color, S(1.5), 0)
		-- The chip's pictogram (UI/Icons.lua, keyed by the chip id: BoostDefs ids, vip, gift, plus, tokens -> revive);
		-- `glyph` is the text fallback.
		local icon = Icons.draw(chip, CHIP_ICONS[id] or id, math.floor(size * 0.66), color, Theme.Colors.panel, glyph)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		local timer = UI.text({
			Text = "",
			Font = Theme.Fonts.display,
			TextSize = math.max(9, math.floor(size * 0.22)),
			TextColor3 = Theme.Colors.text,
			Position = UDim2.fromOffset(0, size + S(1)),
			Size = UDim2.new(1, 0, 0, math.max(10, math.floor(size * 0.24))),
			Parent = holder,
		})
		UI.stroke(timer, Theme.Colors.black, S(1.5), 0.3)
		if clickable then
			(chip :: TextButton).Activated:Connect(function()
				UI.punch(chip, 0.9, 0.15)
				clickable()
			end)
		end
		local sc = UI.new("UIScale", { Scale = 0.2, Parent = chip })
		UI.tween(sc, { Scale = 1 }, 0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		return { holder = holder, chip = chip, timer = timer, id = id, warned = false }
	end

	local function remove(id: string, toast: string?)
		local c = chips[id]
		if not c then
			return
		end
		chips[id] = nil
		local sc = c.chip:FindFirstChildOfClass("UIScale")
		if sc then
			UI.tween(sc, { Scale = 0 }, 0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		end
		task.delay(0.22, function()
			c.holder:Destroy()
		end)
		if toast then
			local HUD = require(Client:WaitForChild("HUD")) :: any
			local t = HUD.get("toast")
			if t then
				t.show(toast, Theme.Colors.grey, 1.4)
			end
		end
	end

	local plusChip: Chip? = nil
	if opts.hub then
		local pc = makeChip("plus", 99, "+", Theme.Colors.grey, opts.onPlus)
		plusChip = pc
		local stroke = pc.chip:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = 0.5
		end
		local pt = pc.timer
		if pt then
			pt.Text = "BOOST"
			pt.TextColor3 = Theme.Colors.textDim
		end
	end

	local lastProfile: any = nil
	local function refresh(p: any)
		lastProfile = p
		local now = ClientState.osNow()
		-- Timed boosts.
		for i, def in BoostDefs.List do
			local b = p and p.boosts and p.boosts[def.id]
			local left = if b then (tonumber(b.expiresAt) or 0) - now else 0
			if left > 0 and not chips[def.id] then
				chips[def.id] = makeChip(def.id, i, def.glyph, Color3.fromHex(def.color), opts.onPlus)
			elseif left <= 0 and chips[def.id] then
				remove(def.id, def.name .. " BOOST ENDED")
			end
		end
		-- VIP's permanent CASH chip.
		if vipActive(p) and not chips.vip then
			chips.vip = makeChip("vip", 10, "VIP", VIP_GOLD, opts.onPlus) -- permanent: no timer
		elseif not vipActive(p) and chips.vip then
			remove("vip", nil)
		end
		-- With any boost (or VIP) chip up, the + steps aside: tapping a live chip opens the store.
		if plusChip then
			local live = chips.vip ~= nil
			for _, def in BoostDefs.List do
				if chips[def.id] then
					live = true
				end
			end
			plusChip.holder.Visible = not live
		end
		-- Revive tokens (hub only): a chip with the count where a timer would be.
		if opts.hub then
			local n = if p and typeof(p.reviveTokens) == "number" then p.reviveTokens else 0
			local c = chips.tokens
			if not c then
				c = makeChip("tokens", 50, "+", Color3.fromHex("3FD47A"), opts.onTokens)
				chips.tokens = c
			end
			local tl = c.timer
			if tl then
				local text = "×" .. tostring(n)
				if tl.Text ~= text then
					if tl.Text ~= "" then
						UI.punch(c.chip, 1.2, 0.3)
					end
					tl.Text = text
					tl.TextColor3 = if n > 0 then Color3.fromHex("8FE3A1") else Theme.Colors.red
				end
			end
		end
		-- The VIP daily gift (hub only).
		if opts.hub then
			local ready = giftReady(p)
			if ready and not chips.gift then
				local c = makeChip("gift", 0, "GFT", VIP_GOLD, opts.onGift)
				chips.gift = c
				if c.timer then
					c.timer.Text = "CLAIM"
					c.timer.TextColor3 = VIP_GOLD
				end
			elseif not ready and chips.gift then
				remove("gift", nil)
			end
		end
	end

	local lastSec: { [string]: number } = {}
	local pulseAt = 0
	local conn = RunService.Heartbeat:Connect(function()
		if not row.Parent then
			return
		end
		local p = lastProfile
		local now = ClientState.osNow()
		local pulse = os.clock() >= pulseAt
		if pulse then
			pulseAt = os.clock() + 1
		end
		for _, def in BoostDefs.List do
			local c = chips[def.id]
			local b = p and p.boosts and p.boosts[def.id]
			if c and b and c.timer then
				local left = (tonumber(b.expiresAt) or 0) - now
				local sec = math.ceil(left)
				if sec ~= lastSec[def.id] then
					lastSec[def.id] = sec
					c.timer.Text = Clock.timer(left)
					c.timer.TextColor3 = if left <= Config.BoostChipWarnSec then Theme.Colors.red else Theme.Colors.text
				end
				if left <= Config.BoostChipWarnSec and pulse then
					UI.punch(c.chip, 1.15, 0.4)
				end
				if left <= 0 then
					refresh(p)
				end
			end
		end
		local gift = chips.gift
		if gift and pulse then
			UI.punch(gift.chip, 1.08, 0.5)
		end
	end)
	if track then
		track(conn)
	end

	return {
		frame = row,
		update = function(sync: any)
			refresh(sync and sync.profile)
		end,
	}
end

-- The match HUD component (Round 17c): the chips sit bottom-left, just above the cash row (Currency).
function BoostChips.build(gui: ScreenGui, track: (RBXScriptConnection) -> ())
	local S = UI.S
	local holder = UI.frame({
		Name = "BoostChips",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, S(20), 1, -S(20) - S(70) - S(6)),
		Size = UDim2.fromOffset(S(300), S(46)),
		Parent = gui,
	})
	local h = BoostChips.new(holder, {
		size = S(32),
		align = Enum.HorizontalAlignment.Left,
		hub = false,
	}, track)
	h.frame.AnchorPoint = Vector2.new(0, 1)
	h.frame.Position = UDim2.fromScale(0, 1)
	local component = {}
	component.frame = holder
	function component.update(sync: any)
		h.update(sync)
	end
	return component
end

return BoostChips
