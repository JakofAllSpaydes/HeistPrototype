--!strict
-- Bottom-center toast above the health bar: "+11% DAMAGE", debug notices, downed stub.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local Rarity = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Rarity"))
local Weapons = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Weapons"))

local Toast = {}

function Toast.build(gui: ScreenGui, _track: (RBXScriptConnection) -> ())
	local S = UI.S
	local root = UI.frame({
		Name = "Toast",
		BackgroundColor3 = Theme.Colors.panel,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -S(120)),
		Size = UDim2.fromOffset(S(260), S(40)),
		AutomaticSize = Enum.AutomaticSize.X,
		Visible = false,
		Parent = gui,
	})
	UI.corner(root, S(10))
	local stroke = UI.stroke(root, Theme.Colors.cash, S(2))
	UI.pad(root, S(16), 0, S(16), 0)
	local label = UI.text({
		Text = "",
		FontFace = Theme.Fonts.display,
		TextSize = S(20),
		TextColor3 = Theme.Colors.cash,
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = root,
	})

	local token = 0
	local component = {}
	component.frame = root

	function component.show(text: string, color: Color3?, duration: number?)
		token += 1
		local mine = token
		local c = color or Theme.Colors.cash
		label.Text = text
		label.TextColor3 = c
		stroke.Color = c
		root.Visible = true
		UI.punch(root, 1.15, 0.25)
		task.delay(duration or 1, function()
			if mine == token then
				root.Visible = false
			end
		end)
	end

	function component.onJuice(name: string, data: any)
		if name == "Toast" then
			component.show(tostring(data.text), Theme.Colors.gold, 1.2)
		elseif name == "Swap" then
			local rarity = Rarity.color(data.rarity or 1)
			local w = Weapons.ById[data.weaponId]
			local label = if w then string.upper(w.displayName) else tostring(data.weaponId)
			component.show(
				string.format("EQUIPPED %s · %s", label, string.upper(Rarity.name(data.rarity or 1))),
				rarity,
				1.2
			)
		end
	end

	return component
end

return Toast
