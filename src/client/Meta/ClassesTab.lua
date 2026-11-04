--!strict
-- Classes tab (GDD_7 Classes): a carousel of the four class icons with EQUIPPED / ◆ 100 / UNLOCKED labels,
-- the character preview switching to the class idle, EQUIP / UNLOCK under it, and one row per ability
-- with the in-match $ price, description, upgradeable stats as current > next and UPGRADE · ◆ 100.
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

function ClassesTab.render(scene: any)
	local S = UI.S
	local panel: Frame = scene.panel
	if not panel then
		return
	end
	scene.title.Text = "CLASSES"
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

	-- Carousel.
	local carousel = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, S(96)),
		Parent = panel,
	})
	UI.list(carousel, Enum.FillDirection.Horizontal, S(14), Enum.HorizontalAlignment.Center)
	for i, c in Classes.List do
		local own = profile ~= nil and profile.classes.owned[c.id] == true
		local holder = UI.button({
			Text = "",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(S(90), S(96)),
			LayoutOrder = i,
			Parent = carousel,
		})
		local circle = UI.frame({
			BackgroundColor3 = if own then Color3.fromHex(c.color) else Theme.Colors.panel2,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, S(4)),
			Size = UDim2.fromOffset(S(54), S(54)),
			Parent = holder,
		})
		UI.corner(circle, 999)
		UI.stroke(
			circle,
			if selected == c.id then Theme.Colors.blue else Theme.Colors.black,
			S(if selected == c.id then 3 else 1.5),
			0.2
		)
		UI.text({
			Text = string.sub(c.name, 1, 1),
			Font = Theme.Fonts.display,
			TextSize = S(26),
			TextColor3 = if own then Theme.Colors.bg else Theme.Colors.grey,
			Size = UDim2.fromScale(1, 1),
			Parent = circle,
		})
		UI.text({
			Text = string.upper(c.name),
			Font = Theme.Fonts.display,
			TextSize = S(11),
			TextColor3 = if selected == c.id then Theme.Colors.text else Theme.Colors.grey,
			Position = UDim2.fromOffset(0, S(60)),
			Size = UDim2.new(1, 0, 0, S(16)),
			Parent = holder,
		})
		local label = if equipped == c.id then "EQUIPPED" elseif own then "UNLOCKED" else MetaUI.fmtGold(Prices.class)
		UI.text({
			Text = label,
			TextSize = S(10),
			TextColor3 = if equipped == c.id
				then Theme.Colors.cash
				elseif own then Theme.Colors.grey
				else Theme.Colors.gold,
			Position = UDim2.fromOffset(0, S(76)),
			Size = UDim2.new(1, 0, 0, S(14)),
			Parent = holder,
		})
		holder.Activated:Connect(function()
			selected = c.id
			UI.sound(Theme.Sounds.toast, 1.25, 0.3)
			scene.refresh()
		end)
	end

	-- Under the preview: EQUIPPED / ◆ 100 / EQUIP.
	local actionRow = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, S(102)),
		Size = UDim2.new(1, 0, 0, S(40)),
		Parent = panel,
	})
	local action = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.fromOffset(S(220), S(40)),
		Parent = actionRow,
	})
	UI.list(action, Enum.FillDirection.Vertical, 0)
	if equipped == class.id then
		MetaUI.button(action, 1, "EQUIPPED", "disabled", nil)
	elseif isOwned then
		MetaUI.button(action, 1, "EQUIP", "green", function()
			local r = scene.request("equipClass", { classId = class.id })
			if r.ok then
				scene.refresh()
			end
		end)
	else
		MetaUI.button(action, 1, "UNLOCK · " .. MetaUI.fmtGold(Prices.class), "primary", function()
			local r = scene.request("unlockClass", { classId = class.id })
			if r.ok then
				scene.refresh()
			end
		end)
	end

	-- Ability rows.
	local list = UI.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, S(150)),
		Size = UDim2.new(1, 0, 1, -S(150)),
		CanvasSize = UDim2.fromOffset(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = S(6),
		ScrollBarImageColor3 = Theme.Colors.grey,
		Parent = panel,
	}) :: ScrollingFrame
	UI.list(list, Enum.FillDirection.Vertical, S(8))
	for i, a in class.abilities do
		local level = if profile then (profile.abilities[a.id] or 0) else 0
		local rowH = S(64) + S(26) * #a.vars
		local row = UI.frame({
			BackgroundColor3 = Theme.Colors.panel,
			Size = UDim2.new(1, -S(8), 0, rowH),
			LayoutOrder = i,
			Parent = list,
		})
		UI.corner(row, S(10))
		UI.stroke(row, if a.live then Theme.Colors.grey else Theme.Colors.panel2, S(1), 0.5)
		local iconWell = UI.frame({
			BackgroundColor3 = Theme.Colors.panel2,
			Position = UDim2.fromOffset(S(10), S(10)),
			Size = UDim2.fromOffset(S(44), S(44)),
			Parent = row,
		})
		UI.corner(iconWell, S(8))
		UI.text({
			Text = a.icon,
			Font = Theme.Fonts.display,
			TextSize = S(13),
			TextColor3 = Color3.fromHex(class.color),
			Size = UDim2.fromScale(1, 1),
			Parent = iconWell,
		})
		local pricePill, priceLabel = UI.pill(iconWell, "$" .. a.price, Theme.Colors.cash, Theme.Colors.bg, S(14), S(9))
		pricePill.AnchorPoint = Vector2.new(0.5, 1)
		pricePill.Position = UDim2.new(0.5, 0, 1, S(6))
		pricePill.ZIndex = 3
		priceLabel.ZIndex = 3
		UI.text({
			Text = string.format(
				"%s · %s%s",
				string.upper(a.name),
				a.hotkey,
				if a.live then "" else " · STUB · PHASE 2"
			),
			Font = Theme.Fonts.display,
			TextSize = S(15),
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(S(64), S(8)),
			Size = UDim2.new(1, -S(200), 0, S(20)),
			Parent = row,
		})
		UI.text({
			Text = a.description,
			TextSize = S(11),
			TextColor3 = Theme.Colors.textDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			Position = UDim2.fromOffset(S(64), S(28)),
			Size = UDim2.new(1, -S(200), 0, S(28)),
			Parent = row,
		})
		local lv = UI.text({
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
		local _ = lv
		local stats = UI.frame({
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(S(64), S(58)),
			Size = UDim2.new(1, -S(200), 0, S(26) * #a.vars),
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
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -S(10), 0, S(30)),
			Size = UDim2.fromOffset(S(120), S(38)),
			Parent = row,
		})
		UI.list(btnHolder, Enum.FillDirection.Vertical, 0)
		if isOwned then
			MetaUI.button(btnHolder, 1, "UPGRADE · " .. MetaUI.fmtGold(Prices.ability), "primary", function()
				local r = scene.request("upgradeAbility", { abilityId = a.id })
				if r.ok then
					scene.refresh()
				end
			end)
		else
			MetaUI.button(btnHolder, 1, "NOT UNLOCKED", "disabled", nil)
		end
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
