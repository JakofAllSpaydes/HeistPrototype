--!strict
-- World-space juice: damage numbers, kill pop, cash floats, enemy hit flash, red screen pulse on damage.
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local Rarity = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Rarity"))

local WorldFx = {}

local function billboard(position: Vector3, width: number, height: number, lifetime: number): (BillboardGui, Attachment)
	local att = Instance.new("Attachment")
	att.WorldPosition = position
	att.Parent = Workspace.Terrain
	local gui = Instance.new("BillboardGui")
	gui.Adornee = att
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(width, height)
	gui.MaxDistance = 120
	gui.LightInfluence = 0
	gui.Parent = att
	task.delay(lifetime, function()
		att:Destroy()
	end)
	return gui, att
end

local function floatText(position: Vector3, text: string, color: Color3, size: number, rise: number, lifetime: number)
	local gui = billboard(position + Vector3.new((math.random() - 0.5) * 1.5, 0, 0), 160, 60, lifetime)
	local label = UI.text({
		Text = text,
		Font = Theme.Fonts.display,
		TextSize = size,
		TextColor3 = color,
		Size = UDim2.fromScale(1, 1),
		Parent = gui,
	})
	UI.stroke(label, Theme.Colors.black, 2, 0.2)
	UI.punch(label, 1.4, 0.25)
	UI.tween(gui, { StudsOffset = Vector3.new(0, rise, 0) }, lifetime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	UI.tween(
		label,
		{ TextTransparency = 1 },
		lifetime * 0.5,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In,
		lifetime * 0.5
	)
end

local function flashEnemy(model: Model)
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") and p.Name ~= "Head" then
			local original = p:GetAttribute("OrigColor") :: Color3?
			if not original then
				original = p.Color
				p:SetAttribute("OrigColor", original)
			end
			p.Color = Theme.Colors.red
			task.delay(0.08, function()
				if p.Parent and original then
					p.Color = original
				end
			end)
		end
	end
end

local function killPop(position: Vector3)
	local gui = billboard(position, 40, 40, 0.4)
	local ring = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.3, 0.3),
		Parent = gui,
	})
	UI.corner(ring, 999)
	local stroke = UI.stroke(ring, Theme.Colors.gold, 4)
	UI.tween(ring, { Size = UDim2.fromScale(1, 1) }, 0.3)
	UI.tween(stroke, { Transparency = 1 }, 0.3)
end

function WorldFx.build(gui: ScreenGui, _track: (RBXScriptConnection) -> ())
	local vignette = UI.frame({
		Name = "HurtVignette",
		BackgroundColor3 = Theme.Colors.red,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0,
		Parent = gui,
	})
	UI.new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.35, 1),
			NumberSequenceKeypoint.new(0.65, 1),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Parent = vignette,
	})

	local flash = UI.frame({
		Name = "RarityFlash",
		BackgroundColor3 = Theme.Colors.gold,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0,
		Parent = gui,
	})

	local component = {}

	function component.onJuice(name: string, data: any)
		if name == "RarityFlash" then
			flash.BackgroundColor3 = data.color or Theme.Colors.gold
			flash.BackgroundTransparency = 1 - (data.alpha or 0.3)
			UI.tween(flash, { BackgroundTransparency = 1 }, 0.4)
		elseif name == "Hit" then
			local color = if data.crit
				then Theme.Colors.red
				elseif data.headshot then Theme.Colors.gold
				else Theme.Colors.text
			local size = if data.crit then 34 elseif data.headshot then 30 else 24
			floatText(data.position, tostring(data.amount), color, size, 2.5, 0.7)
			if typeof(data.model) == "Instance" then
				flashEnemy(data.model)
			end
			UI.sound(Theme.Sounds.hit, if data.headshot then 1.4 else 1, 0.3)
			if data.killed then
				killPop(data.position)
				UI.sound(Theme.Sounds.kill, 1.2, 0.4)
				if data.cash and data.cash > 0 then
					floatText(
						data.position + Vector3.new(0, 1, 0),
						"+" .. UI.fmtCash(data.cash),
						Theme.Colors.cash,
						28,
						5,
						1.1
					)
				end
			end
		elseif name == "PlayerHit" then
			vignette.BackgroundTransparency = 0.55
			UI.tween(vignette, { BackgroundTransparency = 1 }, 0.45)
			UI.sound(Theme.Sounds.hurt, 1, 0.25)
		elseif name == "GunLanded" then
			UI.sound(Theme.Sounds.crate, 1.3, 0.5)
			local gui = billboard(data.position + Vector3.new(0, 1, 0), 60, 60, 0.5)
			local ring = UI.frame({
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.2, 0.2),
				Parent = gui,
			})
			UI.corner(ring, 999)
			local stroke = UI.stroke(ring, Rarity.color(data.rarity or 1), 4)
			UI.tween(ring, { Size = UDim2.fromScale(1, 1) }, 0.4)
			UI.tween(stroke, { Transparency = 1 }, 0.4)
		end
	end

	return component
end

return WorldFx
