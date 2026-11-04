--!strict
-- Weapons tab (GDD_7 Weapons): OWNED row then UNOWNED grid, 5 per row; detail card with stats at the
-- current level and current > next deltas; UNLOCK / UPGRADE / EQUIP STARTER / CUSTOMIZE; the wraps
-- sub-panel pushes the camera in on the gun and previews wraps live.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Weapons = require(Shared:WaitForChild("Weapons"))
local Wraps = require(Shared:WaitForChild("Wraps"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Prices = require(Shared:WaitForChild("Prices"))

local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local MetaUI = require(script.Parent:WaitForChild("MetaUI"))

local WeaponsTab = {}

local selected: string? = nil
local wrapsOpen = false
local wrapPreview: string? = nil

local function levelOf(profile: any, id: string): number
	local e = profile and profile.weapons and profile.weapons[id]
	return if e then (e.level or 0) else 0
end

local function owned(profile: any, id: string): boolean
	return profile ~= nil and profile.weapons ~= nil and profile.weapons[id] ~= nil
end

local function fmtReload(t: number): string
	return string.format("%.2fs", t)
end

------------------------------------------------------------------ Detail card
local function detail(scene: any, card: Frame, w: Weapons.Weapon)
	local S = UI.S
	local profile = scene.profile()
	local isOwned = owned(profile, w.id)
	local level = levelOf(profile, w.id)
	local isStarter = profile and profile.starterWeaponId == w.id
	for _, c in card:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	UI.pad(card, S(14), S(12), S(14), S(12))
	UI.list(card, Enum.FillDirection.Vertical, S(6))
	local well = UI.frame({
		BackgroundColor3 = Theme.Colors.panel2,
		Size = UDim2.new(1, 0, 0, S(70)),
		LayoutOrder = 1,
		Parent = card,
	})
	UI.corner(well, S(10))
	local ic = UI.gunIcon(well, if isOwned then Rarity.color(1) else Theme.Colors.grey, S(60))
	ic.AnchorPoint = Vector2.new(0.5, 0.5)
	ic.Position = UDim2.fromScale(0.5, 0.5)
	local wrapId = profile and profile.weapons[w.id] and profile.weapons[w.id].wrap
	if wrapId and Wraps.ById[wrapId] then
		UI.recolorIcon(ic, Color3.fromHex(Wraps.ById[wrapId].color))
	end
	UI.text({
		Text = string.upper(w.displayName),
		Font = Theme.Fonts.display,
		TextSize = S(20),
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, S(24)),
		LayoutOrder = 2,
		Parent = card,
	})
	UI.text({
		Text = string.format(
			"%s · %s",
			string.upper(w.archetype),
			if isOwned then string.format("LV %d", level) else "LOCKED"
		),
		TextSize = S(11),
		TextColor3 = if isOwned then Theme.Colors.gold else Theme.Colors.grey,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, S(14)),
		LayoutOrder = 3,
		Parent = card,
	})
	-- Stat rows at the current level, with the next level in green when owned.
	local cur = Weapons.atLevel(w, level)
	local nxt = Weapons.atLevel(w, level + 1)
	local rate = Weapons.effectiveRate(w, Weapons.levelRateMult(level))
	local nrate = Weapons.effectiveRate(w, Weapons.levelRateMult(level + 1))
	local function n(v: number): string
		return UI.fmtDmg(v, w.pellets)
	end
	MetaUI.statRow(card, 10, "DMG", n(cur.dmg), if isOwned then n(nxt.dmg) else nil)
	MetaUI.statRow(card, 11, "RATE", UI.fmtRate(rate), if isOwned then UI.fmtRate(nrate) else nil)
	MetaUI.statRow(card, 12, "MAG", tostring(cur.magSize), if isOwned then tostring(nxt.magSize) else nil)
	MetaUI.statRow(card, 13, "RELOAD", fmtReload(cur.reloadTime), if isOwned then fmtReload(nxt.reloadTime) else nil)

	-- Buttons by state.
	if not isOwned then
		if w.saleType == "Direct" then
			MetaUI.button(card, 20, "UNLOCK · " .. MetaUI.fmtGold(Weapons.unlockCost(w)), "primary", function()
				local r = scene.request("unlockWeapon", { weaponId = w.id })
				if r.ok then
					scene.refresh()
				end
			end)
		elseif w.saleType == "Crate" then
			MetaUI.button(card, 20, "VIEW CRATE", "blue", function()
				scene.toast("CRATE UI · PHASE 4", "click")
			end)
		else
			MetaUI.button(card, 20, "EVENT ONLY", "disabled", nil)
		end
		return
	end
	MetaUI.button(card, 20, "UPGRADE · " .. MetaUI.fmtGold(Weapons.upgradeCost(w, level)), "primary", function()
		local r = scene.request("upgradeWeapon", { weaponId = w.id })
		if r.ok then
			scene.refresh()
		end
	end)
	if isStarter then
		MetaUI.button(card, 21, "EQUIPPED", "disabled", nil)
	else
		MetaUI.button(card, 21, "EQUIP STARTER", "green", function()
			local r = scene.request("equipStarter", { weaponId = w.id })
			if r.ok then
				scene.refresh()
			end
		end)
	end
	MetaUI.button(card, 22, "CUSTOMIZE", "blue", function()
		wrapsOpen = true
		scene.refresh()
	end)
end

------------------------------------------------------------------ Wraps sub-panel
local function renderWraps(scene: any)
	local S = UI.S
	local panel: Frame = scene.panel
	local profile = scene.profile()
	local w = selected and Weapons.ById[selected]
	if not w then
		wrapsOpen = false
		scene.refresh()
		return
	end
	scene.title.Text = string.upper(w.displayName) .. " · CUSTOMIZE"
	scene.pushCamera(true)
	scene.hideHud(true)
	local entry = profile and profile.weapons[w.id]
	local applied: string? = if entry then entry.wrap else nil
	-- Bottom-center strip with one category (WRAPS), then the wraps row.
	local strip = UI.frame({
		BackgroundColor3 = Theme.Colors.panel,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, S(150)),
		Parent = panel,
	})
	UI.corner(strip, S(12))
	UI.stroke(strip, Theme.Colors.blue, S(1.5))
	local cat, catLabel = UI.pill(strip, "WRAPS", Theme.Colors.blue, Theme.Colors.bg, S(22), S(12))
	cat.Position = UDim2.fromOffset(S(12), S(10))
	catLabel.Font = Theme.Fonts.display
	local back = UI.button({
		Text = "◀ BACK",
		Font = Theme.Fonts.display,
		TextSize = S(13),
		TextColor3 = Theme.Colors.text,
		BackgroundColor3 = Theme.Colors.panel2,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -S(12), 0, S(8)),
		Size = UDim2.fromOffset(S(90), S(26)),
		Parent = strip,
	})
	UI.corner(back, S(8))
	back.Activated:Connect(function()
		wrapsOpen = false
		wrapPreview = nil
		scene.preview.wrap(nil)
		scene.refresh()
	end)
	local row = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(S(12), S(44)),
		Size = UDim2.new(1, -S(24), 0, S(96)),
		Parent = strip,
	})
	UI.list(row, Enum.FillDirection.Horizontal, S(8))
	local tileSize = if scene.mobile then S(64) else S(70)
	for i, wrap in Wraps.List do
		local isOwned = profile and profile.wraps.owned[wrap.id] == true
		local isApplied = applied == wrap.id
		local b = MetaUI.tile(row, {
			name = wrap.name,
			sub = if isApplied then "APPLIED" elseif isOwned then "OWNED" else MetaUI.fmtGold(Prices.wrap),
			subColor = if isApplied then Theme.Colors.cash elseif isOwned then Theme.Colors.grey else Theme.Colors.gold,
			color = Color3.fromHex(wrap.color),
			owned = isOwned,
			selected = wrapPreview == wrap.id,
			icon = "wrap",
			size = tileSize,
			order = i,
		})
		b.Activated:Connect(function()
			wrapPreview = wrap.id
			scene.preview.wrap(wrap.color)
			UI.sound(Theme.Sounds.toast, 1.3, 0.3)
			scene.refresh()
		end)
	end
	-- APPLY / BUY for the previewed wrap, and CLEAR.
	local actions = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, S(200), 0, S(100)),
		Parent = panel,
	})
	UI.list(actions, Enum.FillDirection.Vertical, S(6))
	local pw = wrapPreview and Wraps.ById[wrapPreview]
	if pw then
		local isOwned = profile and profile.wraps.owned[pw.id] == true
		if isOwned then
			MetaUI.button(actions, 1, "APPLY " .. string.upper(pw.name), "primary", function()
				local r = scene.request("applyWrap", { weaponId = w.id, wrapId = pw.id })
				if r.ok then
					scene.preview.commit()
					scene.refresh()
				end
			end)
		else
			MetaUI.button(actions, 1, "BUY · " .. MetaUI.fmtGold(Prices.wrap), "primary", function()
				local r = scene.request("buyWrap", { wrapId = pw.id })
				if r.ok then
					scene.refresh()
				end
			end)
		end
	end
	if applied then
		MetaUI.button(actions, 2, "REMOVE WRAP", "blue", function()
			local r = scene.request("applyWrap", { weaponId = w.id, wrapId = nil })
			if r.ok then
				wrapPreview = nil
				scene.preview.commit()
				scene.preview.wrap(nil)
				scene.refresh()
			end
		end)
	end
end

------------------------------------------------------------------ Grid
function WeaponsTab.render(scene: any)
	local S = UI.S
	local panel: Frame = scene.panel
	if not panel then
		return
	end
	if wrapsOpen then
		renderWraps(scene)
		return
	end
	scene.title.Text = "WEAPONS"
	local profile = scene.profile()
	if not selected then
		selected = if profile then profile.starterWeaponId else Weapons.Starter
	end
	local rightW = if scene.mobile then S(190) else S(230)
	local grid, card = MetaUI.columns(panel, rightW)
	UI.list(grid, Enum.FillDirection.Vertical, S(6))
	local perRow = 5
	local tileSize = math.max(S(64), math.floor((grid.AbsoluteSize.X - S(8) * (perRow + 1) - S(10)) / perRow))
	tileSize = math.min(tileSize, S(96))
	local ownedList, unownedList = {}, {}
	for _, w in Weapons.List do
		table.insert(if owned(profile, w.id) then ownedList else unownedList, w)
	end
	local function tilesFor(list: { Weapons.Weapon }, header: string, order: number)
		if #list == 0 then
			return
		end
		MetaUI.header(grid, order, header)
		local row = MetaUI.row(grid, order + 1, tileSize, perRow)
		for i, w in list do
			local isOwned = owned(profile, w.id)
			local sub: string, subColor: Color3
			if isOwned then
				sub = string.format("LV %d", levelOf(profile, w.id))
				subColor = Theme.Colors.gold
			else
				sub, subColor = MetaUI.acquisition(w.saleType, Weapons.unlockCost(w))
			end
			local tag: string? = nil
			local tagColor: Color3? = nil
			if isOwned and profile and profile.starterWeaponId == w.id then
				tag, tagColor = "STARTER", Theme.Colors.gold
			elseif isOwned and w.saleType ~= "Direct" then
				tag, tagColor = string.upper(w.saleType), Theme.Colors.blue
			end
			local wrapId = profile and profile.weapons[w.id] and profile.weapons[w.id].wrap
			local color = if wrapId and Wraps.ById[wrapId]
				then Color3.fromHex(Wraps.ById[wrapId].color)
				else Rarity.color(1)
			local b = MetaUI.tile(row, {
				name = w.displayName,
				sub = sub,
				subColor = subColor,
				color = color,
				owned = isOwned,
				selected = selected == w.id,
				tag = tag,
				tagColor = tagColor,
				icon = "gun",
				size = tileSize,
				order = i,
			})
			b.Activated:Connect(function()
				selected = w.id
				UI.sound(Theme.Sounds.toast, 1.25, 0.3)
				scene.preview.weapon(w.id)
				scene.refresh()
			end)
		end
	end
	tilesFor(ownedList, "OWNED", 1)
	tilesFor(unownedList, "UNOWNED", 10)
	local w = selected and Weapons.ById[selected]
	if w then
		detail(scene, card, w)
	end
	local _ = Config
end

function WeaponsTab.onProfile(scene: any)
	scene.refresh()
end

function WeaponsTab.leave(scene: any)
	wrapsOpen = false
	wrapPreview = nil
	scene.preview.wrap(nil)
	scene.pushCamera(false)
	scene.hideHud(false)
end

return WeaponsTab
