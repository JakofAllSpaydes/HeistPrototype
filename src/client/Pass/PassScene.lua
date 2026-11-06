--!strict
-- Brief 6: the battle pass scene, its own door (the hub HUD PASS button, the summary's CLAIM IN PASS, VIEW PASS on
-- any PASS-tagged item) and its own set (the PASS STAGE). Layout, from the references:
--   top-left      SEASON 1 · NIGHT SHIFT, the level badge, the XP bar, ENDS IN 9d 12h, SKIP ×1 / ×5 / ×10
--   left column   the premium sell card: the PREMIUM+ hero, NEW MASKS, WRAPS, POSES, CRATES, GET PREMIUM /
--                 GET PREMIUM+ with prices, FREE ✓ · PREMIUM ✗ · PREMIUM+ ✗
--   center        the selected reward large in 3D (on the mannequin for cosmetics, on the pedestal otherwise), with
--                 its card on the right: name, rarity, REQUIRES PREMIUM / UNLOCKS AT LEVEL 12, a line, CLAIM
--   bottom        the track: level diamonds lit through the current level, three cells per level stacked FREE /
--                 PREMIUM / PREMIUM+ (claimable pulse, claimed check, locked padlock), BACK / NEXT by
--                 Config.PassPageLevels, GO TO CURRENT LEVEL; CLAIM ALL bottom-right
-- A season that ended shows the SEASON OVER sheet on the next open.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local PassSeason = require(Shared:WaitForChild("PassSeason"))
local Rewards = require(Shared:WaitForChild("Rewards"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Clock = require(Shared:WaitForChild("Clock"))
local Classes = require(Shared:WaitForChild("Classes"))
local Products = require(Shared:WaitForChild("Products"))

local Client = script.Parent.Parent
local ClientState = require(Client:WaitForChild("ClientState"))
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local HUD = require(Client:WaitForChild("HUD"))
local PurchaseSheet = require(Client:WaitForChild("PurchaseSheet"))
local StoreFolder = Client:WaitForChild("Store")
local Fx = require(StoreFolder:WaitForChild("Fx"))
local Sets = require(StoreFolder:WaitForChild("Sets"))
local Models = require(StoreFolder:WaitForChild("Models"))
local ItemArt = require(StoreFolder:WaitForChild("ItemArt"))
local Reveal = require(StoreFolder:WaitForChild("Reveal"))

local PassScene = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = Workspace.CurrentCamera :: Camera

local ORANGE = Color3.fromHex("E8792A")
local GREEN = Color3.fromHex("2FB75A")

local open = false
local gui: ScreenGui? = nil
local layers: { [string]: Frame } = {}
local page = 1 -- first level shown on the track
local selLevel = 1
local selLane = "free"
local mannequin: Sets.Mannequin? = nil
local pedestalModel: Model? = nil
local spinConn: RBXScriptConnection? = nil
local set: Sets.Set? = nil
local camFrom: CFrame? = nil
local camTo: CFrame? = nil
local camT0, camSec = 0, 0.6
local savedMode = "gameplay"
local savedHud = "hub"
local lockedMovement = false
local fade: Frame? = nil

------------------------------------------------------------------ Profile helpers
local function profile(): any
	local sync = ClientState.sync
	return sync and sync.profile
end

local function passOf(p: any): any
	return (p and p.pass) or { season = 1, level = 1, xp = 0, tier = 0, claimed = {} }
end

local function seasonNow(p: any): PassSeason.Season
	local pass = passOf(p)
	local n = if (tonumber(pass.season) or 0) > 0 then pass.season else PassSeason.numberAt(ClientState.fakeNow())
	return PassSeason.forNumber(n)
end

local function claimed(p: any, level: number, lane: string): boolean
	local c = passOf(p).claimed["L" .. level]
	return c ~= nil and c[lane] == true
end

local function reached(p: any, level: number): boolean
	return level <= passOf(p).level
end

local function laneOwned(p: any, lane: string): boolean
	return (PassSeason.LaneTier[lane] or 9) <= (tonumber(passOf(p).tier) or 0)
end

local function cellClaimable(p: any, level: number, lane: string): boolean
	return reached(p, level) and laneOwned(p, lane) and not claimed(p, level, lane)
end

-- Exported for the hub HUD's red dot.
function PassScene.claimableCount(p: any): number
	local n = 0
	for level = 1, math.min(passOf(p).level, Config.PassLevels) do
		for _, lane in PassSeason.Lanes do
			if cellClaimable(p, level, lane) then
				n += 1
			end
		end
	end
	return n
end

local function shop(action: string, args: any?): any
	local ok, res = pcall(function()
		return Remotes.Shop:InvokeServer(action, args)
	end)
	return if ok and typeof(res) == "table" then res else { ok = false, reason = "Server error" }
end

------------------------------------------------------------------ Camera and the 3D preview
local function stepCamera()
	local to = camTo
	if not to then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	local s = math.clamp((os.clock() - camT0) / camSec, 0, 1)
	local k = 1 - (1 - s) ^ 3
	local cf = (camFrom or to):Lerp(to, k)
	camera.CFrame = cf
	camera.Focus = cf
end

local function clearPedestal()
	if spinConn then
		spinConn:Disconnect()
		spinConn = nil
	end
	if pedestalModel then
		pedestalModel:Destroy()
		pedestalModel = nil
	end
end

-- Cosmetics go on the mannequin; everything else stands on the pedestal and turns.
local function preview(cell: PassSeason.Cell?)
	clearPedestal()
	local m = mannequin
	local s = set
	if not s then
		return
	end
	local cosmetic = cell ~= nil and (cell.kind == "mask" or cell.kind == "emote" or cell.kind == "wrap")
	if m then
		m.model.Parent = if cosmetic then Workspace:FindFirstChild("PremiumSets") else nil
		m.mask(if cell and cell.kind == "mask" then cell.id else nil)
		m.wrap(if cell and cell.kind == "wrap" then cell.id else nil)
		if cell and cell.kind == "emote" and cell.id then
			m.pose(cell.id)
		end
	end
	if cell and not cosmetic then
		local rarity = Rewards.rarity(cell)
		local model: Model
		if cell.kind == "crate" and cell.id then
			model = Models.crate(cell.id, CFrame.new()).model
		else
			model = Models.item(cell, rarity)
		end
		model.Parent = s.model
		pedestalModel = model
		local base = s.pedestal * CFrame.new(0, if cell.kind == "crate" then 0.1 else 1.8, 0)
		local yaw = 0
		if rarity >= 4 and model.PrimaryPart then
			local p = Instance.new("ParticleEmitter")
			p.Color = ColorSequence.new(Rarity.color(rarity))
			p.LightEmission = 1
			p.Size = NumberSequence.new(0.2, 0)
			p.Lifetime = NumberRange.new(0.8, 1.2)
			p.Rate = 20
			p.Speed = NumberRange.new(1, 2.5)
			p.SpreadAngle = Vector2.new(180, 180)
			p.Parent = model.PrimaryPart
		end
		spinConn = RunService.RenderStepped:Connect(function(dt)
			yaw += dt * 0.7
			if model.Parent then
				model:PivotTo(base * CFrame.new(0, math.sin(yaw * 1.6) * 0.1, 0) * CFrame.Angles(0, yaw, 0))
			end
		end)
	end
end

------------------------------------------------------------------ UI pieces
local render: () -> ()
local renderTrack: (any) -> ()
local renderSelected: (any) -> ()

local function clearLayer(name: string): Frame
	local f = layers[name]
	for _, c in f:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	return f
end

-- A small padlock drawn in frames (house style: shapes, no glyph).
local function padlock(parent: Instance, size: number, z: number)
	local holder = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		ZIndex = z,
		Parent = parent,
	})
	local shackle = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.05),
		Size = UDim2.fromScale(0.5, 0.5),
		ZIndex = z,
		Parent = holder,
	})
	UI.corner(shackle, math.floor(size * 0.25))
	UI.stroke(shackle, Theme.Colors.text, math.max(2, size // 9), 0)
	local body = UI.frame({
		BackgroundColor3 = Theme.Colors.text,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.95),
		Size = UDim2.fromScale(0.72, 0.5),
		ZIndex = z + 1,
		Parent = holder,
	})
	UI.corner(body, math.max(2, size // 10))
	UI.frame({
		BackgroundColor3 = Color3.fromHex("1A1A20"),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.16, 0.4),
		ZIndex = z + 2,
		Parent = body,
	})
end

local function check(parent: Instance, size: number, z: number): Frame
	local c = UI.frame({
		BackgroundColor3 = Color3.fromHex("3FD47A"),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -2, 0, 2),
		Size = UDim2.fromOffset(size, size),
		ZIndex = z,
		Parent = parent,
	})
	UI.corner(c, size // 2)
	UI.text({
		Text = "✓",
		Font = Theme.Fonts.body,
		TextSize = math.floor(size * 0.75),
		TextColor3 = Theme.Colors.white,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z + 1,
		Parent = c,
	})
	return c
end

local function claimResults(res: any, title: string)
	if res.ok and res.data and typeof(res.data.results) == "table" then
		local any = false
		for _, r in res.data.results do
			if r.kind == "gold" then
				any = true
			end
		end
		Reveal.stack(layers.overlay, res.data.results, title, { mini = true })
		if any then
			UI.sound(Fx.Sounds.chime, 1.3, 0.3)
		end
	else
		PurchaseSheet.toast(tostring(res.reason or "Could not claim"), Theme.Colors.malus, false)
	end
end

-- Top-left: the banner, level, XP, season clock and the skips.
local function renderBanner(p: any)
	local S = UI.S
	local f = clearLayer("banner")
	local s = seasonNow(p)
	local pass = passOf(p)
	local color = Color3.fromHex(s.color)
	local card = UI.frame({
		BackgroundColor3 = Color3.fromHex("121216"),
		BackgroundTransparency = 0.08,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
		Parent = f,
	})
	UI.corner(card, S(12))
	UI.stroke(card, color, S(1.5), 0.3)
	UI.new(
		"UIGradient",
		{ Color = ColorSequence.new(Fx.shade(color, -0.6), Color3.fromHex("101014")), Rotation = 0, Parent = card }
	)
	UI.pad(card, S(14), S(10), S(14), S(10))
	local num = tonumber(pass.season) or s.id
	UI.text({
		Text = string.format("SEASON %d · %s", num, s.name),
		Font = Theme.Fonts.display,
		TextSize = S(22),
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(S(70), 0),
		Size = UDim2.new(1, -S(70), 0, S(26)),
		ZIndex = 6,
		Parent = card,
	})
	-- The level badge: a diamond with the number.
	local badge = UI.frame({
		BackgroundColor3 = color,
		Position = UDim2.fromOffset(S(6), S(6)),
		Size = UDim2.fromOffset(S(48), S(48)),
		Rotation = 45,
		ZIndex = 6,
		Parent = card,
	})
	UI.corner(badge, S(8))
	UI.stroke(badge, Color3.new(1, 1, 1), S(2), 0.3)
	local lv = UI.text({
		Text = tostring(pass.level),
		Font = Theme.Fonts.display,
		TextSize = S(24),
		TextColor3 = Theme.Colors.white,
		Position = UDim2.fromOffset(S(6), S(6)),
		Size = UDim2.fromOffset(S(48), S(48)),
		ZIndex = 7,
		Parent = card,
	})
	UI.stroke(lv, Color3.new(0, 0, 0), S(1.5), 0.2)
	local maxed = pass.level >= Config.PassLevels
	local bar = UI.frame({
		BackgroundColor3 = Color3.fromHex("26262E"),
		Position = UDim2.fromOffset(S(70), S(30)),
		Size = UDim2.new(1, -S(70), 0, S(14)),
		ZIndex = 6,
		Parent = card,
	})
	UI.corner(bar, S(7))
	local fill = UI.frame({
		BackgroundColor3 = color,
		Size = UDim2.fromScale(math.clamp((tonumber(pass.xp) or 0) / Config.PassXpPerLevel, 0, 1), 1),
		ZIndex = 7,
		Parent = bar,
	})
	UI.corner(fill, S(7))
	UI.text({
		Text = if maxed
			then string.format(
				"MAX LEVEL · %s / %s TO +%d GOLD",
				UI.fmtInt(pass.xp),
				UI.fmtInt(Config.PassXpPerLevel),
				Config.PassOverflowGold
			)
			else string.format(
				"%s / %s TO LV %d",
				UI.fmtInt(pass.xp),
				UI.fmtInt(Config.PassXpPerLevel),
				pass.level + 1
			),
		Font = Theme.Fonts.display,
		TextSize = S(12),
		TextColor3 = Theme.Colors.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(S(70), S(46)),
		Size = UDim2.new(0.6, 0, 0, S(16)),
		ZIndex = 6,
		Parent = card,
	})
	local ends = UI.text({
		Text = "",
		Font = Theme.Fonts.display,
		TextSize = S(12),
		TextColor3 = Color3.fromHex("FF9A8C"),
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, S(46)),
		Size = UDim2.new(0.4, 0, 0, S(16)),
		ZIndex = 6,
		Parent = card,
	})
	local endsAt = PassSeason.endsAt(num)
	task.spawn(function()
		while ends.Parent do
			ends.Text = "ENDS IN " .. Clock.span(endsAt - ClientState.fakeNow())
			task.wait(1)
		end
	end)
	-- SKIP ×1 / ×5 / ×10.
	local skips = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, S(68)),
		Size = UDim2.new(1, 0, 0, S(40)),
		ZIndex = 6,
		Parent = card,
	})
	UI.list(skips, Enum.FillDirection.Horizontal, S(8))
	UI.text({
		Text = "SKIP",
		Font = Theme.Fonts.display,
		TextSize = S(16),
		TextColor3 = Theme.Colors.textDim,
		Size = UDim2.fromOffset(S(46), S(40)),
		ZIndex = 7,
		Parent = skips,
	})
	for i, n in PassSeason.SkipCounts do
		local b, h =
			Fx.button(skips, "", Color3.fromHex("2A2A33"), Theme.Colors.white, UDim2.fromOffset(S(96), S(40)), 7)
		b.LayoutOrder = i
		UI.text({
			Text = "×" .. n,
			Font = Theme.Fonts.display,
			TextSize = S(15),
			TextColor3 = Theme.Colors.white,
			Position = UDim2.fromOffset(0, S(3)),
			Size = UDim2.new(1, 0, 0, S(18)),
			ZIndex = 9,
			Parent = b,
		})
		UI.text({
			Text = "R$ " .. UI.fmtInt(Config.PassSkipPrice * n),
			Font = Theme.Fonts.body,
			TextSize = S(10),
			TextColor3 = Color3.fromHex("8FE3A1"),
			Position = UDim2.fromOffset(0, S(22)),
			Size = UDim2.new(1, 0, 0, S(14)),
			ZIndex = 9,
			Parent = b,
		})
		-- A skip never runs past the last level (it would charge for levels it cannot give).
		local fits = pass.level + n <= Config.PassLevels
		h.setEnabled(fits)
		b.Activated:Connect(function()
			if not fits then
				return
			end
			PurchaseSheet.open(PassSeason.skipProductId(n), { context = "pass skip" })
		end)
	end
end

-- Left column: the chase. The PREMIUM+ heroes are the rewards that sell the pass, so they lead the card: the final
-- one (level 30) big with rays, the other two beside it; tapping one shows it in 3D. Then GET PREMIUM / PREMIUM+.
local function renderSell(p: any)
	local S = UI.S
	local f = clearLayer("sell")
	local s = seasonNow(p)
	local tier = tonumber(passOf(p).tier) or 0
	local GOLDC = Color3.fromHex("F2C14E")
	local card = UI.frame({
		BackgroundColor3 = Color3.fromHex("141216"),
		BackgroundTransparency = 0.05,
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = true,
		ZIndex = 5,
		Parent = f,
	})
	UI.corner(card, S(12))
	UI.stroke(card, GOLDC, S(2), 0.1)
	UI.new(
		"UIGradient",
		{ Color = ColorSequence.new(Color3.fromHex("2A1E0E"), Color3.fromHex("0E0D10")), Rotation = 90, Parent = card }
	)
	local title = UI.text({
		Text = "PREMIUM+ CHASE",
		Font = Theme.Fonts.display,
		TextSize = S(20),
		TextColor3 = GOLDC,
		Position = UDim2.fromOffset(0, S(8)),
		Size = UDim2.new(1, 0, 0, S(22)),
		ZIndex = 7,
		Parent = card,
	})
	UI.stroke(title, Color3.new(0, 0, 0), S(1.5), 0.2)
	local buttonsH = S(40) * 2 + S(8) + S(12)
	local heroArea = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(S(10), S(34)),
		Size = UDim2.new(1, -S(20), 1, -(S(34) + buttonsH + S(6))),
		ZIndex = 6,
		Parent = card,
	})
	local function heroTile(index: number, parent: Instance, size: UDim2, pos: UDim2, big: boolean)
		local hero = s.heroes[index]
		if not hero then
			return
		end
		local level = PassSeason.heroLevel(s, index)
		local rc = Rarity.color(Rewards.rarity(hero))
		local b = UI.button({
			BackgroundColor3 = Fx.shade(rc, -0.7),
			Position = pos,
			Size = size,
			ClipsDescendants = true,
			ZIndex = 7,
			Parent = parent,
		})
		UI.corner(b, S(10))
		local selected = selLevel == level and selLane == "p2"
		UI.stroke(b, if selected then Theme.Colors.white else GOLDC, S(if big then 2.5 else 1.5), 0)
		UI.new(
			"UIGradient",
			{ Color = ColorSequence.new(Fx.shade(rc, -0.35), Fx.shade(rc, -0.85)), Rotation = 90, Parent = b }
		)
		if big then
			Fx.rays(b, rc, 10, S(420), 7, 9)
			Fx.particles(b, GOLDC, 5, 9)
		end
		local abs = b.AbsoluteSize
		local artPx = math.floor(
			math.min(if abs.X > 0 then abs.X else S(120), if abs.Y > 0 then abs.Y else S(120))
				* (if big then 0.62 else 0.6)
		)
		local art = ItemArt.draw(b, hero, artPx, 9)
		art.AnchorPoint = Vector2.new(0.5, 0.5)
		art.Position = UDim2.fromScale(0.5, if big then 0.44 else 0.42)
		Fx.bob(art, S(3), 2.4, if big then 3 else 1.5)
		local lv = UI.frame({
			BackgroundColor3 = GOLDC,
			Position = UDim2.fromOffset(S(6), S(6)),
			Size = UDim2.fromOffset(S(if big then 58 else 44), S(18)),
			ZIndex = 10,
			Parent = b,
		})
		UI.corner(lv, S(5))
		UI.text({
			Text = "LV " .. level,
			Font = Theme.Fonts.display,
			TextSize = S(if big then 14 else 11),
			TextColor3 = Theme.Colors.bg,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 11,
			Parent = lv,
		})
		local nm = UI.text({
			Text = Rewards.name(hero),
			Font = Theme.Fonts.display,
			TextSize = S(if big then 17 else 11),
			TextColor3 = Theme.Colors.white,
			TextWrapped = true,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -S(4)),
			Size = UDim2.new(1, -S(8), 0, S(if big then 22 else 26)),
			ZIndex = 10,
			Parent = b,
		})
		UI.stroke(nm, Color3.new(0, 0, 0), S(1.5), 0.2)
		local sc = UI.new("UIScale", { Parent = b })
		b.MouseEnter:Connect(function()
			UI.tween(sc, { Scale = 1.04 }, 0.1)
		end)
		b.MouseLeave:Connect(function()
			UI.tween(sc, { Scale = 1 }, 0.1)
		end)
		b.Activated:Connect(function()
			selLevel, selLane = level, "p2"
			UI.sound(Fx.Sounds.press, 1.3, 0.25)
			render()
		end)
	end
	-- The final hero on the left, big; the other two stacked on the right.
	heroTile(3, heroArea, UDim2.new(0.62, -S(4), 1, 0), UDim2.fromScale(0, 0), true)
	heroTile(2, heroArea, UDim2.new(0.38, -S(4), 0.5, -S(4)), UDim2.new(0.62, S(4), 0, 0), false)
	heroTile(1, heroArea, UDim2.new(0.38, -S(4), 0.5, -S(4)), UDim2.new(0.62, S(4), 0.5, S(4)), false)
	local buttons = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, S(10), 1, -S(10)),
		Size = UDim2.new(1, -S(20), 0, S(40) * 2 + S(8)),
		ZIndex = 6,
		Parent = card,
	})
	UI.list(buttons, Enum.FillDirection.Vertical, S(8))
	local function tierButton(order: number, label: string, productId: string, t: number, color: Color3)
		local owned = tier >= t
		local price = if owned then 0 else Products.priceFor(Products.ById[productId], p)
		local b, h = Fx.button(
			buttons,
			if owned then label .. "  ✓" else string.format("%s · R$ %s", label, UI.fmtInt(price)),
			if owned then Color3.fromHex("2E3135") else color,
			Theme.Colors.white,
			UDim2.new(1, 0, 0, S(40)),
			7
		)
		b.LayoutOrder = order
		b.TextSize = S(16)
		h.setEnabled(not owned)
		if not owned and t == 2 then
			Fx.shine(b, 2.2)
		end
		b.Activated:Connect(function()
			if owned then
				return
			end
			PurchaseSheet.open(productId, {
				context = "pass " .. productId,
				onSuccess = function()
					Fx.stinger(5)
					Fx.burst(
						gui :: any,
						UDim2.fromOffset(b.AbsolutePosition.X + b.AbsoluteSize.X / 2, b.AbsolutePosition.Y),
						color,
						24,
						80
					)
				end,
			})
		end)
	end
	tierButton(1, "GET PREMIUM", "pass_premium", 1, ORANGE)
	tierButton(2, "GET PREMIUM+", "pass_premiumplus", 2, Color3.fromHex("A864E8"))
end

-- Right of the 3D preview: the selected reward's card.
renderSelected = function(p: any)
	local S = UI.S
	local f = clearLayer("selected")
	local s = seasonNow(p)
	local cell = PassSeason.cell(s, selLevel, selLane)
	preview(cell)
	if not cell then
		return
	end
	local rarity = Rewards.rarity(cell)
	local color = Rarity.color(rarity)
	local card = UI.frame({
		BackgroundColor3 = Color3.fromHex("121216"),
		BackgroundTransparency = 0.08,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 5,
		Parent = f,
	})
	UI.corner(card, S(12))
	UI.stroke(card, color, S(2), 0.2)
	UI.pad(card, S(16), S(14), S(16), S(14))
	UI.list(card, Enum.FillDirection.Vertical, S(6))
	Fx.slideIn(card, UDim2.fromOffset(S(30), 0), 0.22)
	local isHero = selLane == "p2" and selLevel % math.max(1, math.floor(Config.PassLevels / 3)) == 0
	UI.text({
		Text = if isHero
			then string.format("PREMIUM+ HERO · LEVEL %d", selLevel)
			else string.format("LEVEL %d · %s", selLevel, PassSeason.LaneName[selLane]),
		Font = Theme.Fonts.display,
		TextSize = S(12),
		TextColor3 = Theme.Colors.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, S(16)),
		LayoutOrder = 1,
		ZIndex = 6,
		Parent = card,
	})
	local name = UI.text({
		Text = Rewards.name(cell),
		Font = Theme.Fonts.display,
		TextSize = S(28),
		TextColor3 = Theme.Colors.white,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, S(34)),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		ZIndex = 6,
		Parent = card,
	})
	UI.stroke(name, Color3.new(0, 0, 0), S(1.5), 0.3)
	local pills = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, S(22)),
		LayoutOrder = 3,
		ZIndex = 6,
		Parent = card,
	})
	UI.list(pills, Enum.FillDirection.Horizontal, S(6))
	local rp, rl = UI.pill(pills, string.upper(Rarity.name(rarity)), color, Theme.Colors.bg, S(20), S(11))
	rp.ZIndex = 7
	rl.ZIndex = 8
	rl.Font = Theme.Fonts.display
	local tagText: string? = nil
	if not laneOwned(p, selLane) then
		tagText = "REQUIRES " .. PassSeason.LaneName[selLane]
	elseif not reached(p, selLevel) then
		tagText = "UNLOCKS AT LEVEL " .. selLevel
	elseif claimed(p, selLevel, selLane) then
		tagText = "CLAIMED"
	end
	if tagText then
		local tp, tl = UI.pill(pills, tagText, Color3.fromHex("2E3135"), Theme.Colors.text, S(20), S(11))
		tp.LayoutOrder = 2
		tp.ZIndex = 7
		tl.ZIndex = 8
		tl.Font = Theme.Fonts.display
	end
	local desc = Rewards.kindLabel(cell)
	if cell.kind == "mask" then
		desc = "A new mask for your Locker, worn in the hub and the run."
	elseif cell.kind == "wrap" then
		desc = "A new wrap for any of your guns."
	elseif cell.kind == "emote" then
		desc = "A new pose for the line-ups."
	elseif cell.kind == "crate" then
		desc = "Free crate opens, banked in the store's CRATES tab."
	elseif cell.kind == "boost" then
		desc = "Starts the moment you claim it."
	elseif cell.kind == "mastery" then
		desc = "Mastery XP on your starter gun and equipped class."
	end
	UI.text({
		Text = desc,
		Font = Theme.Fonts.body,
		TextSize = S(12),
		TextColor3 = Theme.Colors.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, S(16)),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 4,
		ZIndex = 6,
		Parent = card,
	})
	if cellClaimable(p, selLevel, selLane) then
		local b, _h = Fx.button(card, "CLAIM", GREEN, Theme.Colors.white, UDim2.new(1, 0, 0, S(48)), 7)
		b.LayoutOrder = 5
		b.TextSize = S(22)
		Fx.particles(b, Color3.fromHex("8FE3A1"), 3, 9)
		b.Activated:Connect(function()
			claimResults(shop("passClaim", { level = selLevel, lane = selLane }), "LEVEL " .. selLevel)
		end)
	end
end

-- The bottom track (Round 17b): one row of level cards. Each level is one card: its FREE reward large on top, the
-- PREMIUM and PREMIUM+ rewards side by side under it, so a free player sees what each upgrade adds at a glance.
-- Diamonds above the cards are lit through the current level; BACK / NEXT page by Config.PassPageLevels.
local LANE_COLOR =
	{ free = Color3.fromHex("9BA0A8"), p1 = ORANGE, p2 = Color3.fromHex("B46CFF") } :: { [string]: Color3 }

local function slotButton(
	parent: Instance,
	p: any,
	s: PassSeason.Season,
	level: number,
	lane: string,
	pos: UDim2,
	size: UDim2,
	artPx: number,
	z: number
)
	local S = UI.S
	local cell = PassSeason.cell(s, level, lane)
	if not cell then
		return
	end
	local rarity = Rewards.rarity(cell)
	local rc = Rarity.color(rarity)
	local isClaimed = claimed(p, level, lane)
	local owned = laneOwned(p, lane)
	local lit = reached(p, level)
	local can = cellClaimable(p, level, lane)
	local selected = level == selLevel and lane == selLane
	local b = UI.button({
		BackgroundColor3 = Color3.fromHex("16161C"),
		Position = pos,
		Size = size,
		ClipsDescendants = true,
		ZIndex = z,
		Parent = parent,
	})
	UI.corner(b, S(8))
	local stroke = UI.stroke(
		b,
		if selected then Theme.Colors.white else rc,
		S(if selected then 2.5 else 1),
		if selected then 0 else 0.5
	)
	UI.new("UIGradient", {
		Color = ColorSequence.new(Fx.shade(rc, -0.45), Color3.fromHex("111116")),
		Rotation = 90,
		Parent = b,
	})
	-- The lane color along the bottom.
	UI.frame({
		BackgroundColor3 = LANE_COLOR[lane],
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, S(3)),
		ZIndex = z + 1,
		Parent = b,
	})
	if rarity >= 5 then
		Fx.rays(b, rc, 6, artPx * 2, z, 10)
	end
	local art = ItemArt.draw(b, cell, artPx, z + 2)
	art.AnchorPoint = Vector2.new(0.5, 0.5)
	art.Position = UDim2.new(0.5, 0, 0.46, 0)
	local amount = if cell.kind == "gold"
			or cell.kind == "tokens"
			or cell.kind == "mastery"
		then UI.fmtInt(cell.amount or 0)
		elseif cell.kind == "crate" then "×" .. (cell.amount or 1)
		elseif cell.kind == "boost" then Rewards.duration(cell.sec or 0)
		else nil
	if amount then
		local a = UI.text({
			Text = amount,
			Font = Theme.Fonts.display,
			TextSize = S(12),
			TextColor3 = Theme.Colors.white,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -S(5), 1, -S(5)),
			Size = UDim2.fromOffset(S(60), S(14)),
			ZIndex = z + 4,
			Parent = b,
		})
		UI.stroke(a, Color3.new(0, 0, 0), S(1.5), 0.2)
	end
	local isHero = lane == "p2" and level % math.max(1, math.floor(Config.PassLevels / 3)) == 0
	if isHero then
		stroke.Color = Color3.fromHex("F2C14E")
		stroke.Thickness = S(2.5)
		stroke.Transparency = 0
		local ribbon = UI.frame({
			BackgroundColor3 = Color3.fromHex("F2C14E"),
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, S(14)),
			Size = UDim2.fromOffset(S(44), S(14)),
			ZIndex = z + 6,
			Parent = b,
		})
		UI.corner(ribbon, S(4))
		UI.text({
			Text = "HERO",
			Font = Theme.Fonts.display,
			TextSize = S(11),
			TextColor3 = Theme.Colors.bg,
			Size = UDim2.fromScale(1, 1),
			ZIndex = z + 7,
			Parent = ribbon,
		})
		Fx.particles(b, Color3.fromHex("F2C14E"), 3, z + 4)
	end
	do
		local tag = UI.text({
			Text = PassSeason.LaneName[lane],
			Font = Theme.Fonts.display,
			TextSize = S(9),
			TextColor3 = LANE_COLOR[lane],
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(S(4), S(2)),
			Size = UDim2.new(1, -S(8), 0, S(11)),
			ZIndex = z + 4,
			Parent = b,
		})
		UI.stroke(tag, Color3.new(0, 0, 0), S(1), 0.3)
	end
	if isClaimed then
		check(b, S(16), z + 5)
		for _, d in art:GetDescendants() do
			if d:IsA("Frame") then
				d.BackgroundTransparency = math.max(d.BackgroundTransparency, 0.5)
			end
		end
	elseif not owned then
		local veil = UI.frame({
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.5,
			Size = UDim2.fromScale(1, 1),
			ZIndex = z + 5,
			Parent = b,
		})
		padlock(veil, S(18), z + 6)
	elseif not lit then
		for _, d in art:GetDescendants() do
			if d:IsA("Frame") then
				d.BackgroundTransparency = math.max(d.BackgroundTransparency, 0.35)
			end
		end
	end
	if can then
		-- Claimable: the edge breathes green and a spark or two rises.
		Fx.particles(b, Color3.fromHex("8FE3A1"), 2, z + 4)
		task.spawn(function()
			local t0 = os.clock()
			while b.Parent do
				local k = (math.sin((os.clock() - t0) * 5) + 1) / 2
				stroke.Color = Color3.fromHex("3FD47A"):Lerp(Theme.Colors.white, k * 0.5)
				stroke.Thickness = S(1.5 + k * 1.5)
				stroke.Transparency = 0
				task.wait(0.04)
			end
		end)
	end
	local sc = UI.new("UIScale", { Parent = b })
	b.MouseEnter:Connect(function()
		UI.tween(sc, { Scale = 1.05 }, 0.1)
		UI.sound(Fx.Sounds.hover, 1.8, 0.08)
	end)
	b.MouseLeave:Connect(function()
		UI.tween(sc, { Scale = 1 }, 0.1)
	end)
	b.Activated:Connect(function()
		selLevel, selLane = level, lane
		UI.sound(Fx.Sounds.press, 1.3, 0.25)
		if can then
			claimResults(shop("passClaim", { level = level, lane = lane }), "LEVEL " .. level)
		else
			renderSelected(p)
			renderTrack(p)
		end
	end)
end

renderTrack = function(p: any)
	local S = UI.S
	local f = clearLayer("track")
	local s = seasonNow(p)
	local pass = passOf(p)
	local per = Config.PassPageLevels
	page = math.clamp(page, 1, math.max(1, Config.PassLevels - per + 1))
	local bg = UI.frame({
		BackgroundColor3 = Color3.fromHex("0C0C10"),
		BackgroundTransparency = 0.12,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
		Parent = f,
	})
	UI.corner(bg, S(14))
	UI.stroke(bg, Color3.new(1, 1, 1), S(1), 0.86)
	local arrowW = S(44)
	local markerH = S(34)
	local fw, fh = f.AbsoluteSize.X, f.AbsoluteSize.Y
	if fw < 50 then
		fw, fh = S(1100), S(214)
	end
	local gridW = fw - arrowW * 2 - S(28)
	local colW = math.floor(gridW / per)
	local cardH = fh - markerH - S(16)
	local gridX = arrowW + S(14)
	-- BACK / NEXT.
	local function arrow(side: number)
		local b, h = Fx.button(
			bg,
			if side < 0 then "<" else ">",
			Color3.fromHex("2A2A33"),
			Theme.Colors.white,
			UDim2.fromOffset(arrowW - S(8), fh - S(24)),
			7
		)
		b.AnchorPoint = Vector2.new(if side < 0 then 0 else 1, 0.5)
		b.Position = if side < 0 then UDim2.new(0, S(8), 0.5, 0) else UDim2.new(1, -S(8), 0.5, 0)
		b.TextSize = S(26)
		local can = if side < 0 then page > 1 else page + per <= Config.PassLevels
		h.setEnabled(can)
		b.Activated:Connect(function()
			if can then
				page = math.clamp(page + side * per, 1, Config.PassLevels - per + 1)
				UI.sound(Fx.Sounds.whoosh, 1.4, 0.25)
				render()
			end
		end)
	end
	arrow(-1)
	arrow(1)
	for i = 0, per - 1 do
		local level = page + i
		if level > Config.PassLevels then
			break
		end
		local lit = level <= pass.level
		local current = level == pass.level
		local col = UI.frame({
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(gridX + i * colW, S(6)),
			Size = UDim2.fromOffset(colW - S(8), fh - S(12)),
			ZIndex = 6,
			Parent = bg,
		})
		-- The ribbon between diamonds, lit through the current level.
		if i < per - 1 and level < Config.PassLevels then
			UI.frame({
				BackgroundColor3 = if level < pass.level then ORANGE else Color3.fromHex("2A2A33"),
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0.5, 0, 0, markerH / 2),
				Size = UDim2.new(1, S(8), 0, S(4)),
				ZIndex = 6,
				Parent = col,
			})
		end
		local d = UI.frame({
			BackgroundColor3 = if lit then ORANGE else Color3.fromHex("2A2A33"),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, markerH / 2),
			Size = UDim2.fromOffset(S(24), S(24)),
			Rotation = 45,
			ZIndex = 7,
			Parent = col,
		})
		UI.corner(d, S(4))
		UI.stroke(
			d,
			if current then Theme.Colors.white else Color3.new(0, 0, 0),
			S(if current then 2 else 1),
			if current then 0 else 0.5
		)
		UI.text({
			Text = tostring(level),
			Font = Theme.Fonts.display,
			TextSize = S(13),
			TextColor3 = if lit then Theme.Colors.white else Theme.Colors.textDim,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, markerH / 2),
			Size = UDim2.fromOffset(S(30), S(24)),
			ZIndex = 8,
			Parent = col,
		})
		-- The level card: FREE on top, PREMIUM and PREMIUM+ under it.
		local card = UI.frame({
			BackgroundColor3 = if lit then Color3.fromHex("1A1612") else Color3.fromHex("121216"),
			Position = UDim2.fromOffset(0, markerH + S(4)),
			Size = UDim2.new(1, 0, 0, cardH),
			ZIndex = 6,
			Parent = col,
		})
		UI.corner(card, S(10))
		UI.stroke(
			card,
			if current then Theme.Colors.white elseif lit then ORANGE else Color3.fromHex("2A2A33"),
			S(if current then 2 else 1),
			if current then 0 else 0.4
		)
		local pad = S(5)
		local bandH = S(22)
		local band = UI.frame({
			BackgroundColor3 = if lit then ORANGE else Color3.fromHex("26262E"),
			BackgroundTransparency = if lit then 0.15 else 0,
			Position = UDim2.fromOffset(pad, pad),
			Size = UDim2.new(1, -pad * 2, 0, bandH),
			ZIndex = 7,
			Parent = card,
		})
		UI.corner(band, S(6))
		UI.text({
			Text = "LEVEL " .. level,
			Font = Theme.Fonts.display,
			TextSize = S(14),
			TextColor3 = if lit then Theme.Colors.bg else Theme.Colors.textDim,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 8,
			Parent = band,
		})
		local innerW = colW - S(8) - pad * 2
		local tileW = math.floor((innerW - pad * 2) / 3)
		local tileH = cardH - bandH - pad * 3
		for k, lane in PassSeason.Lanes do
			slotButton(
				card,
				p,
				s,
				level,
				lane,
				UDim2.fromOffset(pad + (k - 1) * (tileW + pad), pad * 2 + bandH),
				UDim2.fromOffset(tileW, tileH),
				math.floor(math.min(tileW, tileH) * 0.82),
				7
			)
		end
	end
	if not open then
		return
	end
	-- GO TO CURRENT LEVEL above the track, CLAIM ALL bottom-right.
	local controls = clearLayer("controls")
	local gotoBtn, _g = Fx.button(
		controls,
		"GO TO CURRENT LEVEL",
		Color3.fromHex("2A2A33"),
		Theme.Colors.white,
		UDim2.fromOffset(S(220), S(38)),
		6
	)
	gotoBtn.AnchorPoint = Vector2.new(0.5, 1)
	gotoBtn.Position = UDim2.new(0.5, 0, 1, 0)
	gotoBtn.TextSize = S(14)
	gotoBtn.Activated:Connect(function()
		page = math.clamp(pass.level - math.floor(per / 2) + 1, 1, Config.PassLevels - per + 1)
		selLevel, selLane = pass.level, "free"
		render()
	end)
	local waiting = PassScene.claimableCount(p)
	local all, ah = Fx.button(
		controls,
		if waiting > 0 then string.format("CLAIM ALL (%d)", waiting) else "CLAIM ALL",
		GREEN,
		Theme.Colors.white,
		UDim2.fromOffset(S(230), S(50)),
		6
	)
	all.AnchorPoint = Vector2.new(1, 1)
	all.Position = UDim2.new(1, 0, 1, 0)
	all.TextSize = S(20)
	ah.setEnabled(waiting > 0)
	if waiting > 0 then
		all.ClipsDescendants = true
		Fx.particles(all, Color3.fromHex("FFE08A"), 6, 8)
		-- A shine sweeps across while something waits.
		local shine = UI.frame({
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.7,
			Position = UDim2.new(-0.3, 0, 0, 0),
			Size = UDim2.new(0.2, 0, 1, 0),
			Rotation = 15,
			ZIndex = 9,
			Parent = all,
		})
		task.spawn(function()
			while all.Parent do
				shine.Position = UDim2.new(-0.3, 0, 0, 0)
				UI.tween(shine, { Position = UDim2.new(1.2, 0, 0, 0) }, 0.6, Enum.EasingStyle.Quad)
				task.wait(1.6)
			end
		end)
	end
	all.Activated:Connect(function()
		if waiting > 0 then
			claimResults(shop("passClaimAll", {}), "PASS REWARDS")
		end
	end)
end

render = function()
	if not open then
		return
	end
	local p = profile()
	renderBanner(p)
	renderSell(p)
	renderTrack(p)
	renderSelected(p)
end

------------------------------------------------------------------ SEASON OVER
local function seasonOver(p: any)
	local info = passOf(p).seasonOver
	if typeof(info) ~= "table" then
		return
	end
	local S = UI.S
	local layer = layers.overlay
	local dim = UI.frame({
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
		Size = UDim2.fromScale(1, 1),
		Active = true,
		ZIndex = 70,
		Parent = layer,
	})
	local card = UI.frame({
		BackgroundColor3 = Color3.fromHex("15151A"),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(S(480), S(280)),
		ZIndex = 71,
		Parent = dim,
	})
	UI.corner(card, S(16))
	UI.stroke(card, ORANGE, S(2.5), 0)
	Fx.rays(card, ORANGE, 10, S(700), 70, 8)
	local sc = UI.new("UIScale", { Scale = 0.7, Parent = card })
	UI.tween(sc, { Scale = 1 }, 0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	Fx.stinger(5)
	local now = seasonNow(p)
	for i, line in
		{
			{ "SEASON OVER", 40, ORANGE },
			{
				string.format("SEASON %d · %s", tonumber(info.season) or 0, tostring(info.name or "")),
				18,
				Theme.Colors.text,
			},
			{
				string.format(
					"YOU REACHED LV %d · %d REWARDS AUTO-CLAIMED",
					tonumber(info.level) or 1,
					tonumber(info.autoClaimed) or 0
				),
				15,
				Theme.Colors.gold,
			},
			{
				string.format("SEASON %d · %s STARTS NOW", tonumber(passOf(p).season) or 0, now.name),
				18,
				Color3.fromHex(now.color),
			},
		}
	do
		local l = UI.text({
			Text = line[1] :: string,
			Font = Theme.Fonts.display,
			TextSize = S(line[2] :: number),
			TextColor3 = line[3] :: Color3,
			Position = UDim2.fromOffset(0, S(20) + (i - 1) * S(46)),
			Size = UDim2.new(1, 0, 0, S(44)),
			ZIndex = 72,
			Parent = card,
		})
		UI.stroke(l, Color3.new(0, 0, 0), S(1.5), 0.3)
	end
	local ok, _ = Fx.button(card, "LET'S GO", GREEN, Theme.Colors.white, UDim2.fromOffset(S(200), S(48)), 72)
	ok.AnchorPoint = Vector2.new(0.5, 1)
	ok.Position = UDim2.new(0.5, 0, 1, -S(16))
	ok.Activated:Connect(function()
		shop("passSeen", {})
		dim:Destroy()
	end)
end

------------------------------------------------------------------ Open / close
local function build()
	if gui then
		gui:Destroy()
	end
	local S = UI.S
	local mobile = ClientState.isMobile
	local g = UI.new("ScreenGui", {
		Name = "PassScene",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 25,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	}) :: ScreenGui
	gui = g
	local function layer(name: string, props: { [string]: any }): Frame
		local f = UI.frame(props)
		f.Name = name
		f.BackgroundTransparency = 1
		f.Parent = g
		layers[name] = f
		return f
	end
	-- Everything keeps clear of the Roblox top bar.
	local top = Fx.topInset()
	local trackH = if mobile then S(176) else S(196)
	layer("banner", { Position = UDim2.fromOffset(S(20), top), Size = UDim2.fromOffset(S(440), S(130)), ZIndex = 5 })
	layer("sell", {
		Position = UDim2.fromOffset(S(20), top + S(142)),
		Size = UDim2.new(0, S(if mobile then 220 else 280), 1, -(top + S(142) + trackH + S(84))),
		ZIndex = 5,
	})
	layer("selected", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -S(20), 0, top + S(66)),
		Size = UDim2.fromOffset(S(if mobile then 260 else 330), S(100)),
		ZIndex = 5,
	})
	layer("track", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -S(16)),
		Size = UDim2.new(1, -S(40), 0, trackH),
		ZIndex = 5,
	})
	layer("controls", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -(trackH + S(24))),
		Size = UDim2.new(1, -S(40), 0, S(56)),
		ZIndex = 5,
	})
	layer("overlay", { Size = UDim2.fromScale(1, 1), ZIndex = 60 })
	-- LEAVE, top-right.
	local leave, _ = Fx.button(
		g,
		if mobile then "X" else "LEAVE",
		Theme.Colors.red,
		Theme.Colors.white,
		UDim2.fromOffset(if mobile then S(48) else S(110), S(48)),
		20
	)
	leave.AnchorPoint = Vector2.new(1, 0)
	leave.Position = UDim2.new(1, -S(20), 0, top)
	leave.Activated:Connect(function()
		PassScene.close()
	end)
	fade = UI.frame({
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 100,
		Parent = g,
	})
	Fx.slideIn(layers.banner, UDim2.fromOffset(-S(60), 0), 0.3)
	Fx.slideIn(layers.sell, UDim2.fromOffset(-S(80), 0), 0.3)
	Fx.slideIn(layers.track, UDim2.fromOffset(0, S(80)), 0.3)
end

function PassScene.isOpen(): boolean
	return open
end

function PassScene.open(opts: { level: number? }?)
	local sync = ClientState.sync
	local state = if sync then sync.waveState else "Hub"
	if state ~= "Hub" and state ~= "Summary" then
		return
	end
	if ClientState.downed or ClientState.spectating then
		return
	end
	local p = profile()
	local pass = passOf(p)
	local o = opts or {}
	if open then
		if o.level then
			page = math.clamp(o.level - 2, 1, Config.PassLevels - Config.PassPageLevels + 1)
			selLevel = o.level
			render()
		end
		return
	end
	ClientState.Juice:Fire("CloseStore", {})
	ClientState.Juice:Fire("CloseMeta", {})
	open = true
	shop("passOpen", {})
	-- Unless a link asked for a level, the stage opens on the season's final PREMIUM+ hero: the chase.
	selLevel = o.level or PassSeason.heroLevel(seasonNow(p), 3)
	selLane = if o.level then "free" else "p2"
	page = math.clamp((o.level or pass.level) - 1, 1, Config.PassLevels - Config.PassPageLevels + 1)
	build()
	savedMode = ClientState.cameraMode
	savedHud = HUD.mode
	ClientState.cameraMode = "pass"
	ClientState.setBlock("pass", true)
	ClientState.setAds(false)
	lockedMovement = state == "Hub"
	if lockedMovement then
		ClientState.lockMovement("pass", true)
	end
	HUD.setMode("meta")
	RunService:BindToRenderStep("GHSPassCamera", Enum.RenderPriority.Camera.Value + 3, function()
		if open then
			stepCamera()
		end
	end)
	local f = fade
	if f then
		f.Visible = true
		f.BackgroundTransparency = 0
		UI.tween(f, { BackgroundTransparency = 1 }, 0.4)
	end
	Sets.dimWorld(true)
	local s = Sets.get("PassStage")
	set = s
	mannequin = Sets.mannequin(s.pedestal, s.shot.Position - s.pedestal.Position)
	if mannequin then
		mannequin.idle(if sync then sync.classId else Classes.Default)
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = s.pullback
	camFrom, camTo, camT0, camSec = s.pullback, s.shot, os.clock(), 0.9
	UI.sound(Fx.Sounds.whoosh, 1, 0.4)
	render()
	if typeof(pass.seasonOver) == "table" then
		task.delay(0.4, function()
			if open then
				seasonOver(profile())
			end
		end)
	end
end

function PassScene.close()
	if not open then
		return
	end
	open = false
	clearPedestal()
	if mannequin then
		mannequin.destroy()
		mannequin = nil
	end
	Sets.dimWorld(false)
	pcall(function()
		RunService:UnbindFromRenderStep("GHSPassCamera")
	end)
	camFrom, camTo = nil, nil
	if gui then
		gui:Destroy()
		gui = nil
	end
	layers = {}
	ClientState.setBlock("pass", false)
	if lockedMovement then
		ClientState.lockMovement("pass", false)
	end
	if ClientState.inHub() then
		ClientState.cameraMode = "gameplay"
		ClientState.requestCameraYaw = 0
		HUD.setMode(HUD.baseMode())
	else
		ClientState.cameraMode = savedMode
		HUD.setMode(savedHud)
	end
	UI.sound(Fx.Sounds.whoosh, 0.7, 0.35)
end

local lastStamp = ""
function PassScene.init()
	ClientState.Juice:Connect(function(name: string, data: any)
		if name == "OpenPass" then
			PassScene.open({ level = data and tonumber(data.level) })
		elseif name == "PassXp" and typeof(data) == "table" and not open then
			-- Pass XP outside the summary (Job claims, debug, skips): a toast, louder on a level-up.
			local ups = if typeof(data.levelUps) == "table" then #data.levelUps else 0
			if data.skip then
				PurchaseSheet.toast(string.format("PASS LV %d", tonumber(data.toLevel) or 1), ORANGE, false)
			elseif ups > 0 then
				PurchaseSheet.toast(
					string.format(
						"+%s PASS XP · PASS LV %d",
						UI.fmtInt(tonumber(data.gained) or 0),
						tonumber(data.toLevel) or 1
					),
					ORANGE
				)
			elseif (tonumber(data.gained) or 0) > 0 and ClientState.inHub() then
				PurchaseSheet.toast("+" .. UI.fmtInt(tonumber(data.gained) or 0) .. " PASS XP", ORANGE, false)
			end
		elseif name == "ClosePass" or name == "RunStartBegin" or name == "Downed" then
			PassScene.close()
		elseif name == "HubEnter" and open then
			-- The summary handed the party back to the hub: the scene stays, movement locks like in the hub.
			if not lockedMovement then
				lockedMovement = true
				ClientState.lockMovement("pass", true)
			end
			savedMode = "gameplay"
		end
	end)
	ClientState.Changed:Connect(function(sync: any)
		if not open then
			return
		end
		local p = sync.profile
		local pass = passOf(p)
		local parts = {
			tostring(pass.season),
			tostring(pass.level),
			tostring(pass.xp),
			tostring(pass.tier),
			tostring(p and p.fakeRobux),
		}
		for k, v in pass.claimed do
			table.insert(parts, k .. tostring(v.free) .. tostring(v.p1) .. tostring(v.p2))
		end
		local stamp = table.concat(parts, "|")
		if stamp ~= lastStamp then
			lastStamp = stamp
			render()
		end
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if open and input.KeyCode == Enum.KeyCode.Escape and not gameProcessed and not PurchaseSheet.isOpen() then
			PassScene.close()
		end
	end)
end

return PassScene
