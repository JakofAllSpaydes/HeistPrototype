--!strict
-- The one slot under the wave bar. Crew call frames, the timer pill and the ARMS DROP banner live here.
-- A toast temporarily hides whatever else is in the slot.
local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local ClientState = require(Client:WaitForChild("ClientState"))

local CallSlot = {}

function CallSlot.build(gui: ScreenGui, _track: (RBXScriptConnection) -> ())
	local S = UI.S
	local profile = if ClientState.isMobile then Theme.Mobile else Theme.Desktop
	local width = S(profile.callWidth)
	local root = UI.frame({
		Name = "CallSlot",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, S(104)),
		Size = UDim2.fromOffset(width, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = gui,
	})
	UI.list(root, Enum.FillDirection.Vertical, S(6), Enum.HorizontalAlignment.Center)

	local component = {}
	component.frame = root
	component.width = width

	function component.add(frame: GuiObject, order: number)
		frame.LayoutOrder = order
		frame.Parent = root
	end

	local toastToken = 0
	local hiddenByToast: { GuiObject } = {}
	local function restoreHidden()
		for _, c in hiddenByToast do
			if c.Parent then
				c.Visible = true
			end
		end
		hiddenByToast = {}
	end
	function component.toast(text: string, color: Color3, duration: number)
		toastToken += 1
		local token = toastToken
		-- A new toast replaces the old one; give back whatever the old one hid first.
		restoreHidden()
		local hidden: { GuiObject } = {}
		for _, c in root:GetChildren() do
			if c:IsA("GuiObject") and c.Visible and c.Name ~= "SlotToast" then
				c.Visible = false
				table.insert(hidden, c)
			end
		end
		hiddenByToast = hidden
		local old = root:FindFirstChild("SlotToast")
		if old then
			old:Destroy()
		end
		local toast = UI.frame({
			Name = "SlotToast",
			BackgroundColor3 = Theme.Colors.panel,
			Size = UDim2.fromOffset(width, S(40)),
			LayoutOrder = -100,
			Parent = root,
		})
		UI.corner(toast, S(10))
		UI.stroke(toast, color, S(2))
		UI.text({
			Text = text,
			Font = Theme.Fonts.display,
			TextSize = S(20),
			TextColor3 = color,
			Size = UDim2.fromScale(1, 1),
			Parent = toast,
		})
		UI.punch(toast, 1.15, 0.25)
		UI.sound(Theme.Sounds.toast, 1.2, 0.5)
		task.delay(duration, function()
			if token ~= toastToken then
				return
			end
			toast:Destroy()
			restoreHidden()
		end)
	end

	-- System notices that belong in the center: heat changes (wave and crate notices come from their owners).
	function component.onJuice(name: string, data: any)
		if name == "HeatChanged" then
			local up = (data.delta or 0) > 0
			component.toast(
				if up then "HEAT UP" else "HEAT DOWN",
				if up then Theme.Colors.gold else Theme.Colors.red,
				1
			)
		end
	end

	return component
end

return CallSlot
