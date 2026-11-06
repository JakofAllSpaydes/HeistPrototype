--!strict
-- Brief 6: the stacked reveal. Everything a purchase or a claim granted cards in one by one
-- (Config.BundleRevealStagger apart) over a dim, each with its rarity glow, art, name and a NEW or DUPLICATE line,
-- a stinger by tier; DONE returns to wherever it was opened from. Bundles use it full size, pass and Job claims in
-- miniature (`mini`).
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Rewards = require(Shared:WaitForChild("Rewards"))

local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local Fx = require(script.Parent:WaitForChild("Fx"))
local ItemArt = require(script.Parent:WaitForChild("ItemArt"))

local Reveal = {}

export type Item = {
	kind: string,
	id: string?,
	amount: number?,
	sec: number?,
	name: string?,
	rarity: number?,
	new: boolean?,
	dupe: boolean?,
	gold: number?,
	mastery: number?,
	skipped: boolean?,
}

-- Shows `items` over `parent` (a full-screen layer). Calls onDone when DONE is pressed (or the backdrop, for mini).
function Reveal.stack(parent: Instance, items: { Item }, title: string, opts: { mini: boolean?, onDone: (() -> ())? }?)
	local S = UI.S
	local o = opts or {}
	local mini = o.mini == true
	local shown: { Item } = {}
	for _, it in items do
		if not it.skipped then
			table.insert(shown, it)
		end
	end
	local layer = UI.frame({
		Name = "Reveal",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Active = true,
		ZIndex = 60,
		Parent = parent,
	})
	UI.tween(layer, { BackgroundTransparency = if mini then 0.45 else 0.25 }, 0.2)
	local head = UI.text({
		Text = title,
		Font = Theme.Fonts.display,
		TextSize = S(if mini then 26 else 38),
		TextColor3 = Theme.Colors.gold,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, if mini then 0.24 else 0.12, 0),
		Size = UDim2.fromOffset(S(700), S(44)),
		ZIndex = 62,
		Parent = layer,
	})
	UI.stroke(head, Color3.new(0, 0, 0), S(2), 0.2)
	UI.punch(head, 1.4, 0.4)
	local cardW = if mini then 120 else 168
	local cardH = if mini then 150 else 214
	local perRow = math.clamp(#shown, 1, if mini then 6 else 5)
	local grid = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, if mini then 0.5 else 0.52),
		Size = UDim2.fromOffset(perRow * S(cardW + 14), S(cardH + 14) * math.ceil(#shown / perRow)),
		ZIndex = 61,
		Parent = layer,
	})
	UI.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(S(cardW), S(cardH)),
		CellPadding = UDim2.fromOffset(S(14), S(14)),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	local stagger = Config.BundleRevealStagger * (if mini then 0.6 else 1)
	for i, it in shown do
		local rarity = it.rarity or Rewards.rarity(it :: any)
		local color = Fx.rarityColor(rarity)
		local cell = UI.frame({
			BackgroundTransparency = 1,
			LayoutOrder = i,
			Visible = false,
			ZIndex = 62,
			Parent = grid,
		})
		local _g, setGlow = Fx.glow(cell, color, S(12), 62)
		setGlow(1.3)
		local body = UI.frame({
			BackgroundColor3 = Color3.fromHex("15151A"),
			Size = UDim2.fromScale(1, 1),
			ZIndex = 63,
			Parent = cell,
		})
		UI.corner(body, S(12))
		UI.stroke(body, color, S(2), 0.1)
		UI.new("UIGradient", {
			Color = ColorSequence.new(Fx.shade(color, -0.55), Color3.fromHex("101014")),
			Rotation = 90,
			Parent = body,
		})
		if rarity >= 5 then
			Fx.rays(body, color, 8, S(cardW + 40), 63, 14)
		end
		local art = ItemArt.draw(body, it :: any, S(if mini then 64 else 96), 65)
		art.AnchorPoint = Vector2.new(0.5, 0.5)
		art.Position = UDim2.fromScale(0.5, 0.36)
		Fx.bob(art, S(3), 2.4)
		if rarity >= 4 then
			Fx.particles(body, color, 4, 66)
		end
		UI.text({
			Text = it.name or Rewards.name(it :: any),
			Font = Theme.Fonts.display,
			TextSize = S(if mini then 12 else 15),
			TextColor3 = Theme.Colors.white,
			TextWrapped = true,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0.66, 0),
			Size = UDim2.new(1, -S(12), 0, S(if mini then 28 else 36)),
			ZIndex = 66,
			Parent = body,
		})
		local subText = if it.dupe and (it.gold or 0) > 0
			then string.format(
				"DUPLICATE · +◆ %d%s",
				it.gold or 0,
				if (it.mastery or 0) > 0 then " · +" .. it.mastery .. " mastery" else ""
			)
			elseif it.new then "NEW"
			else Rewards.kindLabel(it :: any)
		UI.text({
			Text = subText,
			Font = Theme.Fonts.body,
			TextSize = S(if mini then 9 else 10),
			TextColor3 = if it.new
				then Color3.fromHex("3FD47A")
				elseif it.dupe then Theme.Colors.gold
				else Theme.Colors.textDim,
			TextWrapped = true,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -S(6)),
			Size = UDim2.new(1, -S(10), 0, S(24)),
			ZIndex = 66,
			Parent = body,
		})
		task.delay(0.25 + (i - 1) * stagger, function()
			if not cell.Parent then
				return
			end
			cell.Visible = true
			local sc = UI.new("UIScale", { Scale = 0.3, Parent = cell })
			UI.tween(sc, { Scale = 1 }, 0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			Fx.stinger(rarity)
			if rarity >= 5 then
				Fx.haptic(0.8)
			end
		end)
	end
	local done, _ =
		Fx.button(layer, "DONE", Color3.fromHex("2FB75A"), Theme.Colors.white, UDim2.fromOffset(S(220), S(52)), 64)
	done.AnchorPoint = Vector2.new(0.5, 1)
	done.Position = UDim2.new(0.5, 0, if mini then 0.8 else 0.92, 0)
	done.Visible = false
	task.delay(0.35 + #shown * stagger, function()
		if done.Parent then
			done.Visible = true
			UI.punch(done, 1.2, 0.3)
		end
	end)
	local function finish()
		if not layer.Parent then
			return
		end
		UI.tween(layer, { BackgroundTransparency = 1 }, 0.15)
		layer:Destroy()
		if o.onDone then
			o.onDone()
		end
	end
	done.Activated:Connect(finish)
	return layer
end

return Reveal
