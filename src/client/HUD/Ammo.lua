--!strict
-- Bottom-right: ammo large, hint line under it, and (Round 16) the camera lock state above it: a CTRL key chip
-- and CAMERA LOCKED / CAMERA FREE, so the Ctrl toggle is never a guess. Desktop only (touch has no lock).
local RunService = game:GetService("RunService")

local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local ClientState = require(Client:WaitForChild("ClientState"))
local Hint = require(Client:WaitForChild("Hint"))
local Glyphs = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Glyphs"))
local InputGlyphs = require(Client:WaitForChild("InputGlyphs"))

local Ammo = {}

function Ammo.build(gui: ScreenGui, track: (RBXScriptConnection) -> ())
	local S = UI.S
	local root = UI.frame({
		Name = "Ammo",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -S(20), 1, -S(20)),
		Size = UDim2.fromOffset(S(260), S(70)),
		Parent = gui,
	})
	local ammo = UI.text({
		Name = "Count",
		Text = "0 / ∞",
		FontFace = Theme.Fonts.display,
		TextSize = S(40),
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.new(1, 0, 0, S(46)),
		Parent = root,
	})
	UI.stroke(ammo, Theme.Colors.black, S(1.5), 0.4)
	local hint = UI.text({
		Name = "Hint",
		Text = "",
		TextSize = S(14),
		TextColor3 = Theme.Colors.grey,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.fromOffset(0, S(48)),
		Size = UDim2.new(1, 0, 0, S(22)),
		Visible = not ClientState.isMobile,
		Parent = root,
	})

	-- Brief 11: the keyboard line reads its keys from Glyphs; on a pad the line is drawn chips instead.
	local function keys(...: string): string
		local out = {}
		for _, a in { ... } do
			table.insert(out, Glyphs.keyboard(a) or "?")
		end
		return table.concat(out, " ")
	end
	local padRow = UI.frame({
		Name = "PadHint",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, S(48)),
		Size = UDim2.new(1, 0, 0, S(22)),
		Visible = false,
		Parent = root,
	})
	UI.list(padRow, Enum.FillDirection.Horizontal, S(5), Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
	local order = 0
	local function padItem(actions: { string }, words: string)
		for _, a in actions do
			order += 1
			InputGlyphs.chip(a, S(20), { LayoutOrder = order, Parent = padRow }, { context = "run", padOnly = true })
		end
		order += 1
		UI.text({
			Text = words,
			TextSize = S(14),
			TextColor3 = Theme.Colors.grey,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, S(20)),
			LayoutOrder = order,
			Parent = padRow,
		})
	end
	padItem({ "reload" }, "RELOAD")
	padItem({ "ability1", "ability2", "ability3" }, "ABILITIES")
	padItem({ "cameraCycle" }, "VIEW")
	Hint.watch(root, function()
		local pad = ClientState.inputDevice == "gamepad"
		padRow.Visible = pad and not ClientState.isMobile
		hint.Visible = not pad and not ClientState.isMobile
		hint.Text = string.format(
			"%s RELOAD · %s INTERACT · %s ABILITIES · %s DEBUG",
			keys("reload"),
			keys("interact"),
			keys("ability1", "ability2", "ability3"),
			keys("debug")
		)
	end)

	-- Brief 11 step 3: the sprint mark beside the count (PC and pad; touch wears it over the thumbstick).
	local sprintPill, sprintLabel = UI.pill(root, "» SPRINT", Theme.Colors.gold, Theme.Colors.bg, S(26), S(15))
	sprintPill.AnchorPoint = Vector2.new(0, 0.5)
	sprintPill.Position = UDim2.new(0, 0, 0, S(23))
	sprintPill.Visible = false
	sprintLabel.FontFace = Theme.Fonts.display
	track(RunService.RenderStepped:Connect(function()
		local on = ClientState.sprinting and not ClientState.isMobile
		if sprintPill.Visible ~= on then
			sprintPill.Visible = on
			if on then
				UI.punch(sprintPill, 1.12, 0.15)
			end
		end
	end) :: any)

	-- Camera lock chip, right-aligned just above the count.
	local camRow = UI.frame({
		Name = "CameraLock",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 0, -S(2)),
		Size = UDim2.fromOffset(S(240), S(24)),
		Visible = not ClientState.isMobile,
		Parent = root,
	})
	UI.list(camRow, Enum.FillDirection.Horizontal, S(6), Enum.HorizontalAlignment.Right)
	local key = UI.frame({
		BackgroundColor3 = Theme.Colors.panel2,
		Size = UDim2.fromOffset(S(46), S(22)),
		LayoutOrder = 1,
		Parent = camRow,
	})
	UI.corner(key, S(5))
	UI.stroke(key, Theme.Colors.grey, S(1), 0.4)
	UI.text({
		Text = "CTRL",
		FontFace = Theme.Fonts.display,
		TextSize = S(13),
		TextColor3 = Theme.Colors.textDim,
		Size = UDim2.fromScale(1, 1),
		Parent = key,
	})
	local camPill, camLabel = UI.pill(camRow, "CAMERA LOCKED", Theme.Colors.panel2, Theme.Colors.textDim, S(22), S(13))
	camPill.LayoutOrder = 2
	camLabel.FontFace = Theme.Fonts.display
	local lastFree: boolean? = nil
	track(RunService.RenderStepped:Connect(function()
		-- Brief 11: no free-cursor mode on a pad, so no chip.
		camRow.Visible = not ClientState.isMobile and ClientState.inputDevice == "keyboard"
		local free = ClientState.mouseFree or ClientState.mouseFreeHold
		if free == lastFree then
			return
		end
		local first = lastFree == nil
		lastFree = free
		camLabel.Text = if ClientState.mouseFreeHold and not ClientState.mouseFree
			then "CAMERA FREE (ALT)"
			elseif free then "CAMERA FREE"
			else "CAMERA LOCKED"
		camPill.BackgroundColor3 = if free then Theme.Colors.gold else Theme.Colors.panel2
		camLabel.TextColor3 = if free then Theme.Colors.bg else Theme.Colors.textDim
		if not first then
			UI.punch(camPill, 1.08, 0.15)
		end
	end) :: any)

	local function render(a: any)
		if a.reloading and a.shell then
			-- Shell by shell: the count ticks up live; the hint says you can stop.
			ammo.Text = string.format("%d / %d  LOADING", a.mag, a.max)
			ammo.TextColor3 = if a.mag > 0 then Theme.Colors.gold else Theme.Colors.malus
			UI.punch(ammo, 1.08, 0.15)
		elseif a.reloading then
			ammo.Text = "RELOADING"
			ammo.TextColor3 = Theme.Colors.gold
		else
			ammo.Text = if a.mag == 0 then "RELOAD" else string.format("%d / ∞", a.mag)
			local low = a.max > 0 and a.mag <= math.max(1, math.floor(a.max * 0.2))
			ammo.TextColor3 = if a.mag == 0
				then Theme.Colors.malus
				elseif low then Theme.Colors.gold
				else Theme.Colors.text
			if low then
				UI.punch(ammo, if a.mag == 0 then 1.3 else 1.12, 0.25)
			end
		end
	end
	track(ClientState.Ammo:Connect(render) :: any)
	render(ClientState.ammo)

	return { frame = root, label = ammo, hint = hint }
end

return Ammo
