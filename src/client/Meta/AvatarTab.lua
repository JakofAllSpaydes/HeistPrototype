--!strict
-- Avatar tab (GDD_7 Avatar): category tabs at the top (MASKS active, two FUTURE tabs disabled), OWNED then
-- UNOWNED mask grid with the weapons tab's tile rules, live preview on the character, EQUIP or ◆ 100.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Masks = require(Shared:WaitForChild("Masks"))
local Prices = require(Shared:WaitForChild("Prices"))

local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local MetaUI = require(script.Parent:WaitForChild("MetaUI"))

local AvatarTab = {}

local selected: string? = nil

function AvatarTab.render(scene: any)
	local S = UI.S
	local panel: Frame = scene.panel
	if not panel then
		return
	end
	scene.title.Text = "AVATAR"
	local profile = scene.profile()
	local equipped = if profile then profile.masks.equipped else Masks.Default
	if not selected then
		selected = equipped
	end
	local mask = Masks.ById[selected :: string] or Masks.ById[Masks.Default]
	local isOwned = profile ~= nil and profile.masks.owned[mask.id] == true
	scene.preview.mask(mask.color, mask.shape)

	-- Category tabs.
	local cats = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, S(30)),
		Parent = panel,
	})
	UI.list(cats, Enum.FillDirection.Horizontal, S(8))
	for i, name in { "MASKS", "FUTURE", "FUTURE" } do
		local active = i == 1
		local pill, label = UI.pill(
			cats,
			name,
			if active then Theme.Colors.gold else Theme.Colors.panel2,
			if active then Theme.Colors.bg else Theme.Colors.grey,
			S(26),
			S(12)
		)
		pill.LayoutOrder = i
		label.Font = Theme.Fonts.display
		if not active then
			UI.stroke(pill, Theme.Colors.grey, S(1), 0.6)
		end
	end

	local body = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, S(38)),
		Size = UDim2.new(1, 0, 1, -S(38)),
		Parent = panel,
	})
	local rightW = if scene.mobile then S(180) else S(220)
	local grid, card = MetaUI.columns(body, rightW)
	UI.list(grid, Enum.FillDirection.Vertical, S(6))
	local perRow = 4
	local tileSize = math.max(S(64), math.floor((grid.AbsoluteSize.X - S(8) * (perRow + 1) - S(10)) / perRow))
	tileSize = math.min(tileSize, S(100))
	local ownedList, unownedList = {}, {}
	for _, m in Masks.List do
		local own = profile ~= nil and profile.masks.owned[m.id] == true
		table.insert(if own then ownedList else unownedList, m)
	end
	local function tilesFor(list: { Masks.Mask }, header: string, order: number)
		if #list == 0 then
			return
		end
		MetaUI.header(grid, order, header)
		local row = MetaUI.row(grid, order + 1, tileSize, perRow)
		for i, m in list do
			local own = profile ~= nil and profile.masks.owned[m.id] == true
			local sub: string, subColor: Color3
			if own then
				sub = if equipped == m.id then "EQUIPPED" else "OWNED"
				subColor = if equipped == m.id then Theme.Colors.cash else Theme.Colors.grey
			else
				sub, subColor = MetaUI.acquisition(m.saleType, m.price or Prices.mask)
			end
			local b = MetaUI.tile(row, {
				name = m.name,
				sub = sub,
				subColor = subColor,
				color = Color3.fromHex(m.color),
				owned = own,
				selected = selected == m.id,
				tag = if own and m.saleType ~= "Direct" then string.upper(m.saleType) else nil,
				tagColor = Theme.Colors.blue,
				icon = "mask",
				size = tileSize,
				order = i,
			})
			b.Activated:Connect(function()
				selected = m.id
				UI.sound(Theme.Sounds.toast, 1.25, 0.3)
				scene.refresh()
			end)
		end
	end
	tilesFor(ownedList, "OWNED", 1)
	tilesFor(unownedList, "UNOWNED", 10)

	-- Detail: preview swatch, name, EQUIP / price.
	UI.pad(card, S(14), S(12), S(14), S(12))
	UI.list(card, Enum.FillDirection.Vertical, S(8))
	local well = UI.frame({
		BackgroundColor3 = Theme.Colors.panel2,
		Size = UDim2.new(1, 0, 0, S(80)),
		LayoutOrder = 1,
		Parent = card,
	})
	UI.corner(well, S(10))
	local swatch = UI.frame({
		BackgroundColor3 = Color3.fromHex(mask.color),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(S(50), S(50)),
		Parent = well,
	})
	UI.corner(swatch, S(12))
	UI.text({
		Text = string.upper(mask.name),
		Font = Theme.Fonts.display,
		TextSize = S(18),
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, S(22)),
		LayoutOrder = 2,
		Parent = card,
	})
	UI.text({
		Text = string.format("%s · %s", string.upper(mask.shape), string.upper(mask.saleType)),
		TextSize = S(11),
		TextColor3 = Theme.Colors.grey,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, S(14)),
		LayoutOrder = 3,
		Parent = card,
	})
	if equipped == mask.id then
		MetaUI.button(card, 10, "EQUIPPED", "disabled", nil)
	elseif isOwned then
		MetaUI.button(card, 10, "EQUIP", "green", function()
			local r = scene.request("equipMask", { maskId = mask.id })
			if r.ok then
				scene.preview.commit()
				scene.refresh()
			end
		end)
	elseif mask.saleType == "Direct" then
		MetaUI.button(card, 10, MetaUI.fmtGold(mask.price or Prices.mask), "primary", function()
			local r = scene.request("buyMask", { maskId = mask.id })
			if r.ok then
				scene.refresh()
			end
		end)
	elseif mask.saleType == "Crate" then
		MetaUI.button(card, 10, "VIEW CRATE", "blue", function()
			scene.toast("CRATE UI · PHASE 4", "click")
		end)
	else
		MetaUI.button(card, 10, "EVENT ONLY", "disabled", nil)
	end
end

function AvatarTab.onProfile(scene: any)
	scene.refresh()
end

function AvatarTab.leave(scene: any)
	scene.preview.mask(nil, nil)
end

return AvatarTab
