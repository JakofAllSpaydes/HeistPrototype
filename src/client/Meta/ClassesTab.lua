--!strict
-- Classes tab: the category pills ARE the classes (icon + name, lock on unowned); below them the selected
-- class's three ability rows, sized to fill the panel (big icon well with the in-match $ price, name and
-- hotkey, description, stats as current » next, UPGRADE), and the detail column on the right (tall class
-- well, name, EQUIPPED / UNLOCKED / LOCKED, the kit, EQUIP or UNLOCK). The preview plays the class idle.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Classes = require(Shared:WaitForChild("Classes"))
local AbilityGrowth = require(Shared:WaitForChild("AbilityGrowth"))
local Prices = require(Shared:WaitForChild("Prices"))

local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local MetaUI = require(script.Parent:WaitForChild("MetaUI"))

local ClassesTab = {}

local selected: string? = nil
local lastIdle: string? = nil

local function fmtVar(v: Classes.Var, value: number): string
	local s = if value == math.floor(value) then string.format("%d", value) else string.format("%.1f", value)
	return s .. v.unit
end

-- Class pill: colored circle with the initial, name, lock when unowned, blue when selected.
local function classPill(
	parent: Instance,
	order: number,
	c: Classes.Class,
	own: boolean,
	on: boolean,
	equipped: boolean,
	onPick: () -> ()
): TextButton
	local S = UI.S
	local b = UI.button({
		Text = "",
		BackgroundColor3 = if on then Theme.Colors.blue else Theme.Colors.panel,
		Size = UDim2.new(0.25, -S(5), 0, S(44)),
		LayoutOrder = order,
		Parent = parent,
	})
	UI.corner(b, S(4))
	local circle = UI.frame({
		BackgroundColor3 = if own then Color3.fromHex(c.color) else Theme.Colors.panel2,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, S(8), 0.5, 0),
		Size = UDim2.fromOffset(S(30), S(30)),
		Parent = b,
	})
	UI.corner(circle, 999)
	UI.text({
		Text = if own then string.sub(c.name, 1, 1) else "🔒",
		Font = Theme.Fonts.display,
		TextSize = S(if own then 16 else 13),
		TextColor3 = Theme.Colors.bg,
		Size = UDim2.fromScale(1, 1),
		Parent = circle,
	})
	UI.text({
		Text = string.upper(c.name) .. (if equipped then " ✔" else ""),
		Font = Theme.Fonts.body,
		TextSize = S(13),
		TextColor3 = if own then Theme.Colors.white else Theme.Colors.grey,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(S(46), 0),
		Size = UDim2.new(1, -S(50), 1, 0),
		Parent = b,
	})
	b.Activated:Connect(function()
		UI.punch(b, 0.95, 0.15)
		onPick()
	end)
	return b
end

-- One ability row at a fixed height: icon well left, name / description / stats in the middle, LV and
-- UPGRADE on the right.
local function abilityRow(
	scene: any,
	parent: Instance,
	order: number,
	rowH: number,
	class: Classes.Class,
	a: Classes.Ability,
	isOwned: boolean
)
	local S = UI.S
	local profile = scene.profile()
	local level = if profile then (profile.abilities[a.id] or 0) else 0
	local row = UI.frame({
		BackgroundColor3 = Theme.Colors.panel,
		Size = UDim2.new(1, -S(8), 0, rowH),
		LayoutOrder = order,
		Parent = parent,
	})
	UI.corner(row, S(8))
	local pad = S(12)
	local wellSize = math.min(rowH - pad * 2, S(110))
	local well = UI.frame({
		BackgroundColor3 = Color3.fromHex(class.color),
		BackgroundTransparency = if a.live then 0 else 0.5,
		Position = UDim2.fromOffset(pad, pad),
		Size = UDim2.fromOffset(wellSize, wellSize),
		Parent = row,
	})
	UI.corner(well, S(8))
	UI.text({
		Text = a.icon,
		Font = Theme.Fonts.display,
		TextSize = math.floor(wellSize * 0.3),
		TextColor3 = Theme.Colors.bg,
		Position = UDim2.fromOffset(0, -S(6)),
		Size = UDim2.fromScale(1, 1),
		Parent = well,
	})
	local pricePill, priceLabel = UI.pill(well, "$" .. a.price, Theme.Colors.bg, Theme.Colors.cash, S(20), S(12))
	pricePill.AnchorPoint = Vector2.new(0.5, 1)
	pricePill.Position = UDim2.new(0.5, 0, 1, -S(6))
	pricePill.BackgroundTransparency = 0.15
	priceLabel.Font = Theme.Fonts.display
	-- Hotkey on the icon's top-left corner.
	local hotkey, hotkeyLabel = UI.pill(well, a.hotkey, Theme.Colors.bg, Theme.Colors.white, S(22), S(13))
	hotkey.Position = UDim2.fromOffset(S(5), S(5))
	hotkey.ZIndex = 3
	hotkeyLabel.ZIndex = 3
	hotkeyLabel.Font = Theme.Fonts.display
	local textX = pad + wellSize + S(14)
	local rightW = S(170)
	UI.text({
		Text = a.name .. (if a.live then "" else "  ·  STUB · PHASE 2"),
		Font = Theme.Fonts.body,
		TextSize = S(20),
		TextColor3 = Theme.Colors.white,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(textX, pad),
		Size = UDim2.new(1, -textX - rightW, 0, S(24)),
		Parent = row,
	})
	-- The whole description, wrapped onto up to two lines under the name.
	UI.text({
		Text = a.description,
		TextSize = S(12),
		TextColor3 = Theme.Colors.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Position = UDim2.fromOffset(textX, pad + S(26)),
		Size = UDim2.new(1, -textX - rightW, 0, S(32)),
		Parent = row,
	})
	-- Stats fill the rest of the middle column.
	local statsY = pad + S(62)
	local stats = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(textX, statsY),
		Size = UDim2.new(1, -textX - rightW, 1, -statsY - pad),
		Parent = row,
	})
	UI.list(stats, Enum.FillDirection.Vertical, S(4))
	for k, v in a.vars do
		local cur = AbilityGrowth.at(a.id, v.id, v.base, level)
		local nxt = AbilityGrowth.at(a.id, v.id, v.base, level + 1)
		MetaUI.statRow(stats, k, v.label, fmtVar(v, cur), if isOwned then fmtVar(v, nxt) else nil)
	end
	-- Right: level on top, UPGRADE at the bottom.
	local lv, lvLabel = UI.pill(row, string.format("LV %d", level), Theme.Colors.gold, Theme.Colors.bg, S(30), S(16))
	lv.AnchorPoint = Vector2.new(1, 0)
	lv.Position = UDim2.new(1, -pad, 0, pad)
	lvLabel.Font = Theme.Fonts.display
	local btnHolder = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -pad, 1, -pad),
		Size = UDim2.fromOffset(rightW - S(12), S(44)),
		Parent = row,
	})
	UI.list(btnHolder, Enum.FillDirection.Vertical, 0)
	if isOwned then
		MetaUI.button(btnHolder, 1, "UPGRADE - " .. MetaUI.fmtGold(Prices.ability), "green", function()
			local r = scene.request("upgradeAbility", { abilityId = a.id })
			if r.ok then
				scene.refresh()
			end
		end)
	else
		MetaUI.button(btnHolder, 1, "NOT UNLOCKED", "disabled", nil)
	end
end

function ClassesTab.render(scene: any)
	local S = UI.S
	local panel: Frame = scene.panel
	if not panel then
		return
	end
	scene.setCustomize(false)
	local profile = scene.profile()
	local equipped = if profile then profile.classes.equipped else Classes.Default
	if not selected then
		selected = equipped
	end
	local class = Classes.ById[selected :: string] or Classes.ById[Classes.Default]
	local isOwned = profile ~= nil and profile.classes.owned[class.id] == true
	if lastIdle ~= class.id then
		lastIdle = class.id
		scene.preview.classIdle(class.id)
	end

	-- Class pills across the full width.
	local pills = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, S(44)),
		Parent = panel,
	})
	UI.list(pills, Enum.FillDirection.Horizontal, S(6))
	for i, c in Classes.List do
		local own = profile ~= nil and profile.classes.owned[c.id] == true
		classPill(pills, i, c, own, selected == c.id, equipped == c.id, function()
			selected = c.id
			UI.sound(Theme.Sounds.toast, 1.25, 0.3)
			scene.refresh()
		end)
	end

	local rightW = if scene.mobile then S(200) else S(260)
	local grid, card = MetaUI.columns(panel, rightW, S(54))
	UI.list(grid, Enum.FillDirection.Vertical, S(8))

	-- Three rows share the column's height (no dead space), with a floor so stats never clip.
	local n = #class.abilities
	local available = grid.AbsoluteSize.Y - S(26) - S(8) * (n + 1)
	local rowH = math.max(S(150), math.floor(available / math.max(n, 1)))
	MetaUI.header(grid, 1, string.upper(class.name) .. " · ABILITIES")
	for i, a in class.abilities do
		abilityRow(scene, grid, 1 + i, rowH, class, a, isOwned)
	end

	-- Detail: tall well, name, status, the kit, action.
	local ic =
		MetaUI.well(card, 1, Color3.fromHex(class.color), "class", string.sub(class.name, 1, 1), Theme.Colors.white)
	local well = ic.Parent
	if well and well:IsA("Frame") then
		well.Size = UDim2.new(1, 0, 0, S(220))
	end
	MetaUI.heading(
		card,
		2,
		class.name,
		if equipped == class.id then "EQUIPPED" elseif isOwned then "UNLOCKED" else "LOCKED",
		if equipped == class.id then MetaUI.Green elseif isOwned then Theme.Colors.gold else Theme.Colors.grey
	)
	MetaUI.header(card, 5, "KIT")
	for i, a in class.abilities do
		MetaUI.statRow(card, 10 + i, a.hotkey, a.name, nil)
	end
	MetaUI.statRow(card, 15, "Price", if class.free then "FREE" else MetaUI.fmtGold(Prices.class), nil)
	if equipped == class.id then
		MetaUI.button(card, 20, "EQUIPPED", "disabled", nil)
	elseif isOwned then
		MetaUI.button(card, 20, "EQUIP", "green", function()
			local r = scene.request("equipClass", { classId = class.id })
			if r.ok then
				scene.refresh()
			end
		end)
	else
		MetaUI.button(card, 20, "UNLOCK - " .. MetaUI.fmtGold(Prices.class), "green", function()
			local r = scene.request("unlockClass", { classId = class.id })
			if r.ok then
				scene.refresh()
			end
		end)
	end
end

function ClassesTab.onProfile(scene: any)
	scene.refresh()
end

function ClassesTab.leave(scene: any)
	-- Back to the equipped class's idle for the other tabs.
	lastIdle = nil
	local sync = scene.sync()
	scene.preview.classIdle(if sync then sync.classId else Classes.Default)
end

return ClassesTab
