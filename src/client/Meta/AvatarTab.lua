--!strict
-- Avatar tab in the shared format: category pills (MASKS active, two FUTURE disabled), OWNED / UNOWNED mask
-- tiles 4 per row on the left, detail column on the right (mask well, name, shape · sale, EQUIP or price).
-- Selecting previews the mask live on the character.
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
	scene.setCustomize(false)
	local profile = scene.profile()
	local equipped = if profile then profile.masks.equipped else Masks.Default
	if not selected then
		selected = equipped
	end
	local mask = Masks.ById[selected :: string] or Masks.ById[Masks.Default]
	local isOwned = profile ~= nil and profile.masks.owned[mask.id] == true
	scene.preview.mask(mask.color, mask.shape)

	MetaUI.pills(panel, {
		{ id = "MASKS", name = "MASKS" },
		{ id = "F1", name = "FUTURE", disabled = true },
		{ id = "F2", name = "FUTURE", disabled = true },
	}, "MASKS", function() end)
	local rightW = if scene.mobile then S(200) else S(250)
	local grid, card = MetaUI.columns(panel, rightW, S(44))
	UI.list(grid, Enum.FillDirection.Vertical, S(8))
	local perRow = 4
	local tileW = MetaUI.tileWidth(grid, perRow)

	local ownedList, unownedList = {}, {}
	for _, m in Masks.List do
		local own = profile ~= nil and profile.masks.owned[m.id] == true
		table.insert(if own then ownedList else unownedList, m)
	end
	local function tilesFor(list: { Masks.Mask }, header: string, order: number)
		MetaUI.header(grid, order, header)
		if #list == 0 then
			return
		end
		local row = MetaUI.row(grid, order + 1, tileW, perRow)
		for i, m in list do
			local own = profile ~= nil and profile.masks.owned[m.id] == true
			local pill: string, pillColor: Color3
			if own then
				pill = if equipped == m.id then "EQUIPPED" else "OWNED"
				pillColor = if equipped == m.id then MetaUI.Green else Theme.Colors.grey
			else
				pill, pillColor = MetaUI.acquisition(m.saleType, m.price or Prices.mask)
			end
			local b = MetaUI.tile(row, {
				name = m.name,
				pill = pill,
				pillColor = pillColor,
				color = Color3.fromHex(m.color),
				owned = own,
				selected = selected == m.id,
				tag = if own and m.saleType ~= "Direct" then string.upper(m.saleType) else nil,
				tagColor = Theme.Colors.blue,
				icon = "mask",
				iconColor = Theme.Colors.white,
				size = tileW,
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

	-- Detail.
	MetaUI.well(card, 1, Color3.fromHex(mask.color), "mask", nil, Theme.Colors.white)
	MetaUI.heading(
		card,
		2,
		mask.name,
		string.format("%s · %s", string.upper(mask.shape), if isOwned then "OWNED" else string.upper(mask.saleType)),
		if isOwned then Theme.Colors.gold else Theme.Colors.grey
	)
	MetaUI.statRow(card, 10, "Shape", string.upper(mask.shape), nil)
	MetaUI.statRow(card, 11, "Color", "#" .. mask.color, nil)
	if equipped == mask.id then
		MetaUI.button(card, 20, "EQUIPPED", "disabled", nil)
	elseif isOwned then
		MetaUI.button(card, 20, "EQUIP", "green", function()
			local r = scene.request("equipMask", { maskId = mask.id })
			if r.ok then
				scene.preview.commit()
				scene.refresh()
			end
		end)
	elseif mask.saleType == "Direct" then
		MetaUI.button(card, 20, "UNLOCK - " .. MetaUI.fmtGold(mask.price or Prices.mask), "green", function()
			local r = scene.request("buyMask", { maskId = mask.id })
			if r.ok then
				scene.refresh()
			end
		end)
	elseif mask.saleType == "Crate" then
		MetaUI.button(card, 20, "VIEW CRATE", "blue", function()
			scene.toast("CRATE UI · PHASE 4", "click")
		end)
	else
		MetaUI.button(card, 20, "EVENT ONLY", "disabled", nil)
	end
end

function AvatarTab.onProfile(scene: any)
	scene.refresh()
end

function AvatarTab.leave(scene: any)
	scene.preview.mask(nil, nil)
end

return AvatarTab
