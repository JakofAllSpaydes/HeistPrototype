--!strict
-- Classes tab: the category pills ARE the classes (icon + name, lock on unowned); below them the selected
-- class's three ability rows (icon with the in-match $ price, name and hotkey, description, stats as
-- current » next, UPGRADE), and the detail column on the right (class well, name, EQUIPPED / UNLOCKED /
-- LOCKED, EQUIP or UNLOCK). The preview plays the selected class's idle.
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
)
	local S = UI.S
	local b = UI.button({
		Text = "",
		BackgroundColor3 = if on then Theme.Colors.blue else Theme.Colors.panel,
		Size = UDim2.fromOffset(S(132), S(40)),
		LayoutOrder = order,
		Parent = parent,
	})
	UI.corner(b, S(4))
	local circle = UI.frame({
		BackgroundColor3 = if own then Color3.fromHex(c.color) else Theme.Colors.panel2,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, S(6), 0.5, 0),
		Size = UDim2.fromOffset(S(28), S(28)),
		Parent = b,
	})
	UI.corner(circle, 999)
	UI.text({
		Text = if own then string.sub(c.name, 1, 1) else "🔒",
		Font = Theme.Fonts.display,
		TextSize = S(if own then 15 else 13),
		TextColor3 = Theme.Colors.bg,
		Size = UDim2.fromScale(1, 1),
		Parent = circle,
	})
	UI.text({
		Text = string.upper(c.name) .. (if equipped then " ✔" else ""),
		Font = Theme.Fonts.body,
		TextSize = S(12),
		TextColor3 = if own then Theme.Colors.white else Theme.Colors.grey,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(S(40), 0),
		Size = UDim2.new(1, -S(44), 1, 0),
		Parent = b,
	})
	b.Activated:Connect(function()
		UI.punch(b, 0.95, 0.15)
		onPick()
	end)
	return b
end

local function abilityRow(
	scene: any,
	parent: Instance,
	order: number,
	class: Classes.Class,
	a: Classes.Ability,
	isOwned: boolean
)
	local S = UI.S
	local profile = scene.profile()
	local level = if profile then (profile.abilities[a.id] or 0) else 0
	local rowH = S(62) + S(30) * #a.vars
	local row = UI.frame({
		BackgroundColor3 = Theme.Colors.panel,
		Size = UDim2.new(1, -S(8), 0, rowH),
		LayoutOrder = order,
		Parent = parent,
	})
	UI.corner(row, S(6))
	local iconWell = UI.frame({
		BackgroundColor3 = Color3.fromHex(class.color),
		BackgroundTransparency = if a.live then 0 else 0.5,
		Position = UDim2.fromOffset(S(10), S(10)),
		Size = UDim2.fromOffset(S(46), S(46)),
		Parent = row,
	})
	UI.corner(iconWell, S(6))
	UI.text({
		Text = a.icon,
		Font = Theme.Fonts.display,
		TextSize = S(13),
		TextColor3 = Theme.Colors.bg,
		Size = UDim2.fromScale(1, 1),
		Parent = iconWell,
	})
	local pricePill, priceLabel = UI.pill(iconWell, "$" .. a.price, Theme.Colors.cash, Theme.Colors.bg, S(14), S(9))
	pricePill.AnchorPoint = Vector2.new(0.5, 1)
	pricePill.Position = UDim2.new(0.5, 0, 1, S(6))
	pricePill.ZIndex = 3
	priceLabel.ZIndex = 3
	priceLabel.Font = Theme.Fonts.display
	UI.text({
		Text = string.format("%s · %s%s", a.name, a.hotkey, if a.live then "" else " · STUB · PHASE 2"),
		Font = Theme.Fonts.body,
		TextSize = S(15),
		TextColor3 = Theme.Colors.white,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(S(66), S(8)),
		Size = UDim2.new(1, -S(230), 0, S(20)),
		Parent = row,
	})
	UI.text({
		Text = a.description,
		TextSize = S(11),
		TextColor3 = Theme.Colors.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Position = UDim2.fromOffset(S(66), S(28)),
		Size = UDim2.new(1, -S(230), 0, S(28)),
		Parent = row,
	})
	UI.text({
		Text = string.format("LV %d", level),
		Font = Theme.Fonts.display,
		TextSize = S(12),
		TextColor3 = Theme.Colors.gold,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -S(10), 0, S(8)),
		Size = UDim2.fromOffset(S(60), S(16)),
		Parent = row,
	})
	local stats = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(S(10), S(60)),
		Size = UDim2.new(1, -S(170), 0, S(30) * #a.vars),
		Parent = row,
	})
	UI.list(stats, Enum.FillDirection.Vertical, S(2))
	for k, v in a.vars do
		local cur = AbilityGrowth.at(a.id, v.id, v.base, level)
		local nxt = AbilityGrowth.at(a.id, v.id, v.base, level + 1)
		MetaUI.statRow(stats, k, v.label, fmtVar(v, cur), if isOwned then fmtVar(v, nxt) else nil)
	end
	local btnHolder = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -S(10), 1, -S(8)),
		Size = UDim2.fromOffset(S(150), S(44)),
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

	-- Class pills.
	local pills = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, S(40)),
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

	local rightW = if scene.mobile then S(200) else S(250)
	local grid, card = MetaUI.columns(panel, rightW, S(50))
	UI.list(grid, Enum.FillDirection.Vertical, S(8))

	-- Ability list.
	MetaUI.header(grid, 1, string.upper(class.name) .. " · ABILITIES")
	for i, a in class.abilities do
		abilityRow(scene, grid, 1 + i, class, a, isOwned)
	end

	-- Detail.
	MetaUI.well(card, 1, Color3.fromHex(class.color), "class", string.sub(class.name, 1, 1), Theme.Colors.white)
	MetaUI.heading(
		card,
		2,
		class.name,
		if equipped == class.id then "EQUIPPED" elseif isOwned then "UNLOCKED" else "LOCKED",
		if equipped == class.id then MetaUI.Green elseif isOwned then Theme.Colors.gold else Theme.Colors.grey
	)
	for i, a in class.abilities do
		MetaUI.statRow(card, 10 + i, a.hotkey, a.name, nil)
	end
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
