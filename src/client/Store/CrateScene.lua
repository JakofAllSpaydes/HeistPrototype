--!strict
-- Brief 6: the crate opening sequence on the CRATE ROOM set (Sets.lua), full screen. The server has already rolled
-- and granted every result; this plays them back:
--   Open    CrateOpenSec: the crate rattles with rising ticks while its seams glow in the rolled rarity's color (the
--           telegraph), then the lid blows with a flash, a shake and the stinger for that tier
--   Reveal  the item rises on a beam and turns slowly; rays by tier, sparks on Epic+, Legendary slow motion
--           (CrateLegendarySlowSec) and a sting; the name card slams in with the rarity label and either a NEW
--           ribbon or `DUPLICATE · +◆ 160 · +80 mastery`
--   ×1      CONFIRM → back to the store on CRATES
--   ×N      NEXT (or CrateAutoNextSec) → the crate resets and opens again; SKIP (from the first reveal) jumps to
--           the summary: a grid of every result, the Gold and mastery totals, OPEN AGAIN and DONE
-- Mobile: full screen, SKIP and NEXT are 56px, haptics on the lid and on Legendary.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Crates = require(Shared:WaitForChild("Crates"))
local Rarity = require(Shared:WaitForChild("Rarity"))

local Client = script.Parent.Parent
local ClientState = require(Client:WaitForChild("ClientState"))
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local PurchaseSheet = require(Client:WaitForChild("PurchaseSheet"))
local Fx = require(script.Parent:WaitForChild("Fx"))
local Sets = require(script.Parent:WaitForChild("Sets"))
local Models = require(script.Parent:WaitForChild("Models"))
local ItemArt = require(script.Parent:WaitForChild("ItemArt"))
local StoreScene = require(script.Parent:WaitForChild("StoreScene"))

local CrateScene = {}

export type Result = {
	kind: string,
	id: string,
	rarity: number,
	name: string,
	new: boolean,
	dupe: boolean,
	gold: number,
	mastery: number,
	pity: boolean?,
	pityLeft: number?,
}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = Workspace.CurrentCamera :: Camera

local running = false
local token = 0

local function alive(t: number): boolean
	return running and token == t
end

-- Waits `sec`, returning false as soon as the run was skipped or ended.
local function wait(t: number, sec: number): boolean
	local t0 = os.clock()
	while os.clock() - t0 < sec do
		if not alive(t) then
			return false
		end
		task.wait()
	end
	return alive(t)
end

local function screenPos(p: Vector3): UDim2
	local v = camera:WorldToViewportPoint(p)
	return UDim2.fromOffset(v.X, v.Y)
end

-- The whole sequence. `results` came back from the server; `productId` is what OPEN AGAIN buys (nil: free opens).
function CrateScene.play(crateId: string, results: { Result }, productId: string?, onDone: (() -> ())?)
	if running then
		return
	end
	local crate = Crates.ById[crateId]
	if not crate or #results == 0 then
		return
	end
	running = true
	token += 1
	local t = token
	local S = UI.S
	local mobile = ClientState.isMobile
	local ctx = StoreScene.ctx()
	ctx.hideChrome(true)

	local gui = UI.new("ScreenGui", {
		Name = "CrateScene",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 20,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	}) :: ScreenGui
	local flash = UI.frame({
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 50,
		Parent = gui,
	})
	-- Vignette for the one-spotlight look.
	local vignette = UI.frame({
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = gui,
	})
	UI.new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(0.3, 1),
			NumberSequenceKeypoint.new(0.7, 1),
			NumberSequenceKeypoint.new(1, 0.2),
		}),
		Parent = vignette,
	})
	local counter = UI.text({
		Text = "",
		Font = Theme.Fonts.display,
		TextSize = S(26),
		TextColor3 = Theme.Colors.white,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -S(24), 0, S(20)),
		Size = UDim2.fromOffset(S(200), S(32)),
		ZIndex = 10,
		Parent = gui,
	})
	UI.stroke(counter, Color3.new(0, 0, 0), S(2), 0.3)
	UI.text({
		Text = crate.name,
		Font = Theme.Fonts.display,
		TextSize = S(18),
		TextColor3 = Color3.fromHex(crate.trim),
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(S(24), S(24)),
		Size = UDim2.fromOffset(S(300), S(24)),
		ZIndex = 10,
		Parent = gui,
	})
	local btnH = if mobile then S(56) else S(50)
	local skip, _skipH =
		Fx.button(gui, "SKIP", Color3.fromHex("2E3135"), Theme.Colors.white, UDim2.fromOffset(S(140), btnH), 12)
	skip.AnchorPoint = Vector2.new(1, 1)
	skip.Position = UDim2.new(1, -S(24), 1, -S(24))
	skip.Visible = false
	local nextBtn, _nextH =
		Fx.button(gui, "NEXT", Color3.fromHex("2FB75A"), Theme.Colors.white, UDim2.fromOffset(S(200), btnH), 12)
	nextBtn.AnchorPoint = Vector2.new(0.5, 1)
	nextBtn.Position = UDim2.new(0.5, 0, 1, -S(24))
	nextBtn.Visible = false
	local nextFill = UI.frame({
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.75,
		Size = UDim2.fromScale(0, 1),
		ZIndex = 13,
		Parent = nextBtn,
	})
	UI.corner(nextFill, S(8))

	local set = Sets.get("CrateRoom")
	local model: Models.CrateModel? = nil
	local item: Model? = nil
	local beam: Part? = nil
	local spinConn: RBXScriptConnection? = nil
	local nameCard: Frame? = nil
	local rays: Frame? = nil
	local advance = false
	local skipped = false
	-- Inside a reveal SKIP cuts straight to the summary.
	local function go(): boolean
		return alive(t) and not skipped
	end
	local function pause(sec: number): boolean
		local p0 = os.clock()
		while os.clock() - p0 < sec do
			if not go() then
				return false
			end
			task.wait()
		end
		return go()
	end

	local function clearReveal()
		if spinConn then
			spinConn:Disconnect()
			spinConn = nil
		end
		if item then
			item:Destroy()
			item = nil
		end
		if beam then
			beam:Destroy()
			beam = nil
		end
		if nameCard then
			nameCard:Destroy()
			nameCard = nil
		end
		if rays then
			rays:Destroy()
			rays = nil
		end
	end

	local function clearAll()
		clearReveal()
		if model then
			model.model:Destroy()
			model = nil
		end
	end

	local function finish()
		if not running then
			return
		end
		running = false
		token += 1
		clearAll()
		StoreScene.dip(function()
			gui:Destroy()
			ctx.hideChrome(false)
			StoreScene.backToShowroom()
			StoreScene.select("CRATES", { crate = crateId })
		end)
		if onDone then
			onDone()
		end
	end

	skip.Activated:Connect(function()
		skipped = true
		advance = true
	end)
	nextBtn.Activated:Connect(function()
		advance = true
	end)

	-- Into the room.
	StoreScene.dip(function()
		camera.CFrame = set.pullback
		StoreScene.easeCamera(set.shot, set.pullback, 0.8)
	end)
	UI.sound(Fx.Sounds.whoosh, 0.8, 0.4)

	local function openOne(i: number, r: Result): boolean
		counter.Text = string.format("%d / %d", i, #results)
		UI.punch(counter, 1.2, 0.25)
		local color = Rarity.color(r.rarity)
		local tier = r.rarity
		-- A fresh crate drops onto the pedestal.
		local m = Models.crate(crateId, set.pedestal * CFrame.new(0, 3, 0))
		model = m
		m.model.Parent = set.model
		local restCf = set.pedestal
		local t0 = os.clock()
		while os.clock() - t0 < 0.22 do
			local k = (os.clock() - t0) / 0.22
			m.model:PivotTo(restCf * CFrame.new(0, 3 * (1 - k * k), 0))
			task.wait()
		end
		m.model:PivotTo(restCf)
		UI.sound(Fx.Sounds.thump, 0.8, 0.5)
		if not pause(0.25) then
			return false
		end
		-- Open: rattle with rising ticks, the seams glow in the rarity color (the telegraph).
		local openSec = Config.CrateOpenSec
		t0 = os.clock()
		local nextTick = 0
		while os.clock() - t0 < openSec do
			if not go() then
				return false
			end
			local k = (os.clock() - t0) / openSec
			local amp = 0.02 + k * k * 0.12
			m.model:PivotTo(
				restCf
					* CFrame.new((math.random() - 0.5) * amp, 0, (math.random() - 0.5) * amp)
					* CFrame.Angles(0, 0, (math.random() - 0.5) * amp * 0.6)
			)
			m.setGlow(color, k * (0.5 + tier * 0.1))
			if os.clock() >= nextTick then
				nextTick = os.clock() + (0.16 - k * 0.11)
				UI.sound(Fx.Sounds.rattle, 0.9 + k * 1.1, 0.18 + k * 0.2)
			end
			task.wait()
		end
		m.model:PivotTo(restCf)
		m.setGlow(color, 1)
		-- The lid blows.
		flash.BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.6)
		flash.BackgroundTransparency = 0.25 - tier * 0.04
		UI.tween(flash, { BackgroundTransparency = 1 }, 0.4)
		Fx.stinger(tier)
		UI.sound(Fx.Sounds.lid, 0.7, 0.6)
		Fx.haptic(0.6)
		ClientState.Juice:Fire("Shake", { amp = 0.15 + tier * 0.06, dur = 0.25 })
		local lid = m.lid
		local lid0 = lid:GetPivot()
		local spin = (math.random() - 0.5) * 6
		task.spawn(function()
			local l0 = os.clock()
			while lid.Parent and os.clock() - l0 < 1.2 do
				local s = os.clock() - l0
				lid:PivotTo(
					lid0 * CFrame.new(spin * s * 0.6, 9 * s - 6 * s * s, -2 * s) * CFrame.Angles(s * 3, spin * s, s * 2)
				)
				task.wait()
			end
			if lid.Parent then
				lid:Destroy()
			end
		end)
		-- Reveal: the item rises on a beam and turns slowly.
		local it = Models.item({ kind = r.kind, id = r.id }, r.rarity)
		item = it
		it.Parent = set.model
		local start = restCf * CFrame.new(0, 1.2, 0)
		local top = restCf * CFrame.new(0, 3.4, 0)
		it:PivotTo(start)
		local b = Instance.new("Part")
		b.Anchored = true
		b.CanCollide = false
		b.CanQuery = false
		b.Material = Enum.Material.Neon
		b.Color = color
		b.Transparency = 0.55
		b.Shape = Enum.PartType.Cylinder
		b.Size = Vector3.new(0.1, 1.6, 1.6)
		b.CFrame = restCf * CFrame.new(0, 1.6, 0) * CFrame.Angles(0, 0, math.rad(90))
		b.Parent = set.model
		beam = b
		if tier >= 4 then
			local p = Instance.new("ParticleEmitter")
			p.Color = ColorSequence.new(color)
			p.LightEmission = 1
			p.Size = NumberSequence.new(0.25, 0)
			p.Lifetime = NumberRange.new(0.8, 1.4)
			p.Rate = if tier == 5 then 60 else 30
			p.Speed = NumberRange.new(1.5, 3.5)
			p.SpreadAngle = Vector2.new(180, 180)
			p.Parent = it.PrimaryPart
			local l = Instance.new("PointLight")
			l.Color = color
			l.Brightness = 3
			l.Range = 12
			l.Parent = it.PrimaryPart
		end
		local yaw = 0
		local slow = if tier >= 5 then 0.25 else 1
		local slowUntil = os.clock() + (if tier >= 5 then Config.CrateLegendarySlowSec else 0)
		local rise0 = os.clock()
		local riseSec = 0.8
		spinConn = RunService.RenderStepped:Connect(function(dt)
			local rate = if os.clock() < slowUntil then slow else 1
			yaw += dt * 0.9 * rate
			local k = math.clamp((os.clock() - rise0) / (riseSec / rate), 0, 1)
			local e = 1 - (1 - k) ^ 3
			if it.Parent then
				it:PivotTo(
					start:Lerp(top, e) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, 0, math.sin(yaw * 0.7) * 0.08)
				)
			end
			if b.Parent then
				b.Size = Vector3.new(0.1 + e * 5, 1.6 - e * 0.4, 1.6 - e * 0.4)
				b.CFrame = restCf * CFrame.new(0, 1.2 + e * 2.5, 0) * CFrame.Angles(0, 0, math.rad(90))
			end
		end)
		if tier >= 5 then
			UI.sound(Fx.Sounds.chime, 0.8, 0.8)
			Fx.haptic(1)
		end
		-- Rays by tier behind the item (screen space).
		task.delay(0.15, function()
			if not alive(t) or not it.Parent then
				return
			end
			local holder = UI.frame({
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = screenPos((top * CFrame.new(0, 0.2, 0)).Position),
				Size = UDim2.fromOffset(S(10), S(10)),
				ZIndex = 2,
				Parent = gui,
			})
			rays = holder
			if tier >= 2 then
				Fx.rays(holder, color, 6 + tier * 2, S(140 + tier * 90), 2, 8 + tier * 3)
			end
		end)
		skip.Visible = #results > 1
		-- The name card slams in.
		local wait1 = if tier >= 5 then Config.CrateLegendarySlowSec + 0.3 else 0.45
		if not pause(wait1) then
			return false
		end
		local card = UI.frame({
			BackgroundColor3 = Color3.fromHex("121216"),
			BackgroundTransparency = 0.05,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -(btnH + S(44))),
			Size = UDim2.fromOffset(S(460), S(110)),
			ZIndex = 8,
			Parent = gui,
		})
		nameCard = card
		UI.corner(card, S(12))
		UI.stroke(card, color, S(2.5), 0)
		local _g, setGlow = Fx.glow(card, color, S(12), 7)
		setGlow(1.4)
		UI.text({
			Text = string.upper(Rarity.name(tier)),
			Font = Theme.Fonts.display,
			TextSize = S(16),
			TextColor3 = color,
			Position = UDim2.fromOffset(0, S(10)),
			Size = UDim2.new(1, 0, 0, S(20)),
			ZIndex = 9,
			Parent = card,
		})
		local nm = UI.text({
			Text = string.upper(r.name),
			Font = Theme.Fonts.display,
			TextSize = S(34),
			TextColor3 = Theme.Colors.white,
			Position = UDim2.fromOffset(0, S(30)),
			Size = UDim2.new(1, 0, 0, S(40)),
			ZIndex = 9,
			Parent = card,
		})
		UI.stroke(nm, Color3.new(0, 0, 0), S(2), 0.3)
		local sub = if r.dupe
			then string.format("DUPLICATE · +◆ %d · +%d mastery", r.gold, r.mastery)
			else (if r.kind == "weapon" then "NEW WEAPON · IN YOUR ARMORY" else "NEW MASK · IN YOUR LOCKER")
		UI.text({
			Text = sub,
			Font = Theme.Fonts.body,
			TextSize = S(12),
			TextColor3 = if r.dupe then Theme.Colors.gold else Color3.fromHex("8FE3A1"),
			Position = UDim2.fromOffset(0, S(76)),
			Size = UDim2.new(1, 0, 0, S(18)),
			ZIndex = 9,
			Parent = card,
		})
		if not r.dupe then
			local ribbon = UI.frame({
				BackgroundColor3 = Color3.fromHex("3FD47A"),
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, S(8), 0, -S(10)),
				Size = UDim2.fromOffset(S(64), S(24)),
				Rotation = 8,
				ZIndex = 10,
				Parent = card,
			})
			UI.corner(ribbon, S(4))
			UI.text({
				Text = "NEW",
				Font = Theme.Fonts.display,
				TextSize = S(15),
				TextColor3 = Theme.Colors.white,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 11,
				Parent = ribbon,
			})
		end
		if r.pity then
			UI.text({
				Text = "PITY · EPIC+ GUARANTEED",
				Font = Theme.Fonts.body,
				TextSize = S(10),
				TextColor3 = Fx.rarityColor(4),
				Position = UDim2.fromOffset(0, S(92)),
				Size = UDim2.new(1, 0, 0, S(14)),
				ZIndex = 9,
				Parent = card,
			})
		end
		local sc = UI.new("UIScale", { Scale = 1.8, Parent = card })
		UI.tween(sc, { Scale = 1 }, 0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		UI.sound(Fx.Sounds.stamp, 0.9 + tier * 0.1, 0.5)
		if tier >= 4 then
			Fx.particles(card, color, 8, 10)
		end
		return true
	end

	-- Summary grid (×N, or after SKIP).
	local function summary()
		clearAll()
		counter.Text = ""
		skip.Visible = false
		nextBtn.Visible = false
		local layer = UI.frame({
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.35,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 20,
			Parent = gui,
		})
		local title = UI.text({
			Text = string.format("%s ×%d", crate.name, #results),
			Font = Theme.Fonts.display,
			TextSize = S(34),
			TextColor3 = Color3.fromHex(crate.trim),
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0.06, 0),
			Size = UDim2.fromOffset(S(600), S(40)),
			ZIndex = 21,
			Parent = layer,
		})
		UI.stroke(title, Color3.new(0, 0, 0), S(2), 0.2)
		local perRow = if #results > 5 then 5 else #results
		local cell = if mobile then 104 else 128
		local grid = UI.frame({
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0.16, 0),
			Size = UDim2.fromOffset(perRow * S(cell + 12), math.ceil(#results / perRow) * S(cell + 34)),
			ZIndex = 21,
			Parent = layer,
		})
		UI.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(S(cell), S(cell + 22)),
			CellPadding = UDim2.fromOffset(S(12), S(12)),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = grid,
		})
		local gold, mastery, best = 0, 0, 1
		for i, r in results do
			gold += r.gold
			mastery += r.mastery
			best = math.max(best, r.rarity)
			local color = Rarity.color(r.rarity)
			local c = UI.frame({ BackgroundTransparency = 1, LayoutOrder = i, ZIndex = 22, Parent = grid })
			local _g, setGlow = Fx.glow(c, color, S(10), 22)
			setGlow(if r.rarity >= 4 then 1.5 else 0.9)
			local body = UI.frame({
				BackgroundColor3 = Color3.fromHex("16161B"),
				Size = UDim2.fromScale(1, 1),
				ZIndex = 23,
				Parent = c,
			})
			UI.corner(body, S(10))
			UI.stroke(body, color, S(2), 0.05)
			UI.new("UIGradient", {
				Color = ColorSequence.new(Fx.shade(color, -0.5), Color3.fromHex("101014")),
				Rotation = 90,
				Parent = body,
			})
			local art = ItemArt.draw(body, { kind = r.kind, id = r.id }, S(cell - 40), 24)
			art.AnchorPoint = Vector2.new(0.5, 0)
			art.Position = UDim2.new(0.5, 0, 0, S(6))
			UI.text({
				Text = string.upper(r.name),
				Font = Theme.Fonts.display,
				TextSize = S(12),
				TextColor3 = Theme.Colors.white,
				TextWrapped = true,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -S(20)),
				Size = UDim2.new(1, -S(8), 0, S(16)),
				ZIndex = 24,
				Parent = body,
			})
			UI.text({
				Text = if r.dupe then string.format("DUPE +◆%d", r.gold) else "NEW",
				Font = Theme.Fonts.body,
				TextSize = S(10),
				TextColor3 = if r.dupe then Theme.Colors.gold else Color3.fromHex("3FD47A"),
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -S(4)),
				Size = UDim2.new(1, 0, 0, S(14)),
				ZIndex = 24,
				Parent = body,
			})
			c.Visible = false
			task.delay((i - 1) * 0.05, function()
				if c.Parent then
					c.Visible = true
					local sc = UI.new("UIScale", { Scale = 0.4, Parent = c })
					UI.tween(sc, { Scale = 1 }, 0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
					UI.sound(Fx.Sounds.tick, 1 + r.rarity * 0.15, 0.2)
				end
			end)
		end
		local totals = UI.text({
			Text = string.format("DUPLICATES PAID +◆ %s GOLD · +%s MASTERY XP", UI.fmtInt(gold), UI.fmtInt(mastery)),
			Font = Theme.Fonts.display,
			TextSize = S(18),
			TextColor3 = Theme.Colors.gold,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -(btnH + S(46))),
			Size = UDim2.fromOffset(S(700), S(24)),
			ZIndex = 21,
			Parent = layer,
		})
		UI.stroke(totals, Color3.new(0, 0, 0), S(1.5), 0.3)
		local row = UI.frame({
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -S(24)),
			Size = UDim2.fromOffset(S(480), btnH),
			ZIndex = 21,
			Parent = layer,
		})
		UI.list(row, Enum.FillDirection.Horizontal, S(16), Enum.HorizontalAlignment.Center)
		if productId then
			local again, _a = Fx.button(
				row,
				"OPEN AGAIN",
				Color3.fromHex("2FB75A"),
				Theme.Colors.white,
				UDim2.fromOffset(S(220), btnH),
				22
			)
			again.Activated:Connect(function()
				PurchaseSheet.open(productId, {
					context = "crate OPEN AGAIN",
					onSuccess = function(data: any)
						if typeof(data) == "table" and typeof(data.results) == "table" then
							running = false
							token += 1
							gui:Destroy()
							CrateScene.play(crateId, data.results, productId, onDone)
						end
					end,
				})
			end)
		end
		local doneBtn, _d =
			Fx.button(row, "DONE", Color3.fromHex("2E3135"), Theme.Colors.white, UDim2.fromOffset(S(200), btnH), 22)
		doneBtn.Activated:Connect(finish)
		if best >= 5 then
			Fx.stinger(5)
		end
	end

	task.spawn(function()
		if not wait(t, 0.6) then
			return
		end
		for i, r in results do
			if skipped then
				break
			end
			advance = false
			local ok = openOne(i, r)
			if skipped and alive(t) then
				break
			end
			if not ok or not alive(t) then
				return
			end
			if skipped then
				break
			end
			if #results == 1 then
				-- ×1: CONFIRM.
				local confirm, _c = Fx.button(
					gui,
					"CONFIRM",
					Color3.fromHex("2FB75A"),
					Theme.Colors.white,
					UDim2.fromOffset(S(240), btnH),
					12
				)
				confirm.AnchorPoint = Vector2.new(0.5, 1)
				confirm.Position = UDim2.new(0.5, 0, 1, -S(24))
				UI.punch(confirm, 1.2, 0.3)
				confirm.Activated:Connect(finish)
				return
			end
			if i == #results then
				break
			end
			-- ×N: NEXT, or by itself after CrateAutoNextSec.
			nextBtn.Visible = true
			nextFill.Size = UDim2.fromScale(0, 1)
			UI.tween(nextFill, { Size = UDim2.fromScale(1, 1) }, Config.CrateAutoNextSec, Enum.EasingStyle.Linear)
			local t0 = os.clock()
			while not advance and os.clock() - t0 < Config.CrateAutoNextSec do
				if not alive(t) then
					return
				end
				task.wait()
			end
			nextBtn.Visible = false
			clearAll()
		end
		if not alive(t) then
			return
		end
		if not skipped then
			-- The last reveal holds a beat before the grid.
			nextBtn.Visible = false
			wait(t, 1.2)
		end
		if alive(t) then
			summary()
		end
	end)
end

function CrateScene.isRunning(): boolean
	return running
end

return CrateScene
