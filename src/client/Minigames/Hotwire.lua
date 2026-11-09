--!strict
-- Hotwire (drag). Colored stubs on the left, shuffled sockets on the right. Drag each stub to the socket
-- of its color; the wire draws live, locks on the right socket, snaps back from the wrong one.
-- Round 16: a COLORBLIND toggle on the panel (saved to the account, profile.options.hotwireSymbols) swaps the
-- original palette for the Okabe-Ito colorblind-safe set and letters every wire and its socket, so color is never
-- the only cue. It repaints live, mid-game.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local Client = script.Parent.Parent
local ClientState = require(Client:WaitForChild("ClientState"))
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local Frame = require(script.Parent.Frame)

local PALETTE = {
	Color3.fromHex("E8554D"),
	Color3.fromHex("4D9FE8"),
	Color3.fromHex("8FE3A1"),
	Color3.fromHex("E8B64C"),
	Color3.fromHex("A864E8"),
	Color3.fromHex("F2E6C8"),
}
-- Okabe-Ito: orange, sky blue, bluish green, yellow, reddish purple, plus white (its dark blue reads poorly here).
local COLORBLIND = {
	Color3.fromHex("E69F00"),
	Color3.fromHex("56B4E9"),
	Color3.fromHex("009E73"),
	Color3.fromHex("F0E442"),
	Color3.fromHex("CC79A7"),
	Color3.fromHex("F2F2F2"),
}
local SYMBOLS = { "A", "B", "C", "D", "E", "F" }

-- The local choice wins until the next sync carries it back from the server.
local symbolsOverride: boolean? = nil
local function symbolsOn(): boolean
	if symbolsOverride ~= nil then
		return symbolsOverride
	end
	local sync = ClientState.sync
	local options = sync and sync.profile and sync.profile.options
	return options ~= nil and options.hotwireSymbols == true
end

local Hotwire = {
	title = "HOTWIRE",
	hint = "DRAG EACH WIRE TO THE SOCKET OF ITS COLOR",
	padHint = "{DPadUp} PICK · {ButtonA} GRAB · {DPadDown} SOCKET · {ButtonA} DROP · {ButtonY} COLORBLIND",
	color = Theme.Colors.blue,
	aspect = 0.95,
}

type Wire = { index: number, stub: Frame, socket: Frame, line: Frame?, locked: boolean }

function Hotwire.open(host: Frame.Host)
	local u = host.u
	local n = Config.HotwireCountByTier[host.tier] or Config.HotwireCountByTier[1]
	n = math.clamp(n, 1, #PALETTE)

	local rowH = host.height / (n + 1)
	local stubW, stubH = u(70), math.min(u(36), math.floor(rowH * 0.7))
	local leftX = u(50)
	local rightX = host.width - u(50)

	-- Sockets take the stubs' colors in a shuffled order.
	local order = {}
	for i = 1, n do
		order[i] = i
	end
	for i = n, 2, -1 do
		local k = math.random(i)
		order[i], order[k] = order[k], order[i]
	end

	local wires: { Wire } = {}
	local sockets: { [GuiObject]: number } = {} -- socket frame -> color index
	local socketRows: { Frame } = {} -- brief 11: the sockets top to bottom (the pad walks them)
	local locked = 0
	local wireLayer =
		UI.frame({ BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = host.content })

	-- The active palette, and everything that wears a wire color (repainted when the toggle flips).
	local function col(i: number): Color3
		return (if symbolsOn() then COLORBLIND else PALETTE)[i]
	end
	local painters: { () -> () } = {}

	-- Symbol badges: a letter in a dark circle on every stub and socket, shown while SYMBOLS is on.
	local badges: { GuiObject } = {}
	local function badge(parent: GuiObject, i: number)
		local size = math.floor(stubH * 0.72)
		local b = UI.frame({
			BackgroundColor3 = Theme.Colors.black,
			BackgroundTransparency = 0.25,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(size, size),
			ZIndex = 7,
			Parent = parent,
		})
		UI.corner(b, size / 2)
		local letter = UI.text({
			Text = SYMBOLS[i],
			FontFace = Theme.Fonts.display,
			TextSize = math.floor(size * 0.7),
			TextColor3 = col(i),
			Size = UDim2.fromScale(1, 1),
			ZIndex = 8,
			Parent = b,
		})
		table.insert(painters, function()
			letter.TextColor3 = col(i)
		end)
		table.insert(badges, b)
	end

	for i = 1, n do
		local color = col(i)
		local y = rowH * i
		local stub = UI.frame({
			BackgroundColor3 = color,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(leftX, y),
			Size = UDim2.fromOffset(stubW, stubH),
			ZIndex = 5,
			Parent = host.content,
		})
		UI.corner(stub, u(8))
		UI.stroke(stub, Theme.Colors.black, u(1.5), 0.5)
		local socketColor = col(order[i])
		local socket = UI.frame({
			BackgroundColor3 = Theme.Colors.panel2,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(rightX, y),
			Size = UDim2.fromOffset(stubW, stubH),
			ZIndex = 4,
			Parent = host.content,
		})
		UI.corner(socket, u(8))
		local socketStroke = UI.stroke(socket, socketColor, u(3))
		local well = UI.frame({
			BackgroundColor3 = socketColor,
			BackgroundTransparency = 0.7,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.5, 0.5),
			ZIndex = 5,
			Parent = socket,
		})
		UI.corner(well, u(5))
		sockets[socket] = order[i]
		socketRows[i] = socket
		local wire: Wire = { index = i, stub = stub, socket = socket, line = nil, locked = false }
		wires[i] = wire
		local socketIndex = order[i]
		table.insert(painters, function()
			stub.BackgroundColor3 = col(i)
			socketStroke.Color = col(socketIndex)
			well.BackgroundColor3 = col(socketIndex)
			-- A wired socket is lit in its wire's color.
			for _, other in wires do
				if other.locked and other.index == socketIndex then
					socket.BackgroundColor3 = col(socketIndex)
				end
			end
			if wire.line then
				wire.line.BackgroundColor3 = col(i)
			end
		end)
		badge(stub, i)
		badge(socket, order[i])
	end

	-- SYMBOLS toggle, top center of the play area.
	local toggle = UI.button({
		Text = "",
		BackgroundColor3 = Theme.Colors.panel2,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(host.width / 2, u(4)),
		Size = UDim2.fromOffset(u(100), u(20)),
		ZIndex = 9,
		Parent = host.content,
	})
	UI.corner(toggle, u(10))
	local toggleStroke = UI.stroke(toggle, Theme.Colors.grey, u(1), 0.5)
	local toggleLabel = UI.text({
		Text = "COLORBLIND",
		FontFace = Theme.Fonts.display,
		TextSize = u(12),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 10,
		Parent = toggle,
	})
	local function paintSymbols()
		local on = symbolsOn()
		for _, b in badges do
			b.Visible = on
		end
		for _, paint in painters do
			paint()
		end
		toggle.BackgroundColor3 = if on then Theme.Colors.gold else Theme.Colors.panel2
		toggleLabel.TextColor3 = if on then Theme.Colors.bg else Theme.Colors.grey
		toggleStroke.Transparency = if on then 1 else 0.5
	end
	paintSymbols()
	host.track(toggle.Activated:Connect(function()
		local on = not symbolsOn()
		symbolsOverride = on
		Remotes.SetOption:FireServer("hotwireSymbols", on)
		UI.sound(Theme.Sounds.cardFlip, 1.2, 0.4)
		UI.punch(toggle, 1.08, 0.15)
		paintSymbols()
	end))

	-- Where a carried wire lands: the right socket locks it in, a wrong one shocks (and springs back), none springs
	-- back. The drag and the pad both end here.
	local function settle(w: Wire, line: Frame, from: Vector2, socket: GuiObject?)
		if socket and sockets[socket] == w.index then
			-- Right socket: the wire locks in and the socket lights.
			w.locked = true
			locked += 1
			Frame.setLine(line, from, Frame.centerOf(host, socket) - Vector2.new(stubW / 2, 0), u(6))
			socket.BackgroundColor3 = col(w.index)
			UI.punch(socket, 1.25, 0.3)
			w.stub.BackgroundTransparency = 0.5
			host.haptic(0.6)
			UI.sound(Theme.Sounds.take, 1 + locked * 0.12, 0.5)
			host.setHint(string.format("%d / %d WIRED", locked, n), Theme.Colors.cash)
			if locked >= n then
				host.finish("done")
			end
			return
		end
		-- Wrong socket (or nowhere): red flash and spring back.
		if socket then
			host.miss()
			Frame.padHaptic(0.9, 0.12, "Large") -- brief 11: the shock, sharp
			line.BackgroundColor3 = Theme.Colors.red
			socket.BackgroundColor3 = Theme.Colors.red
			UI.tween(socket, { BackgroundColor3 = Theme.Colors.panel2 }, 0.3)
			UI.shake(socket, u(3), 0.2)
		end
		local tween =
			UI.tween(line, { Size = UDim2.fromOffset(1, u(6)), Position = UDim2.fromOffset(from.X, from.Y) }, 0.2)
		tween.Completed:Once(function()
			if line.Parent then
				line:Destroy()
			end
		end)
		w.line = nil
	end
	for _, w in wires do
		local start = Vector2.zero
		local from = Vector2.zero
		Frame.drag(host, w.stub, function(p: Vector2)
			if w.locked then
				return
			end
			start = p
			from = Frame.centerOf(host, w.stub) + Vector2.new(stubW / 2, 0)
			if w.line then
				w.line:Destroy()
			end
			w.line = Frame.line(wireLayer, from, from, u(6), col(w.index), 3)
			UI.punch(w.stub, 1.1, 0.15)
		end, function(p: Vector2)
			local line = w.line
			if w.locked or not line then
				return
			end
			Frame.setLine(line, from, from + (p - start), u(6))
		end, function(p: Vector2)
			local line = w.line
			if w.locked or not line then
				return
			end
			local hit = Frame.hit(p, function(g)
				return sockets[g] ~= nil or (g.Parent ~= nil and sockets[g.Parent :: any] ~= nil)
			end)
			local socket: GuiObject? = if hit and sockets[hit] then hit elseif hit then hit.Parent :: GuiObject else nil
			if not socket then
				-- Lenient drop: the nearest socket within HotwireSnapPx (design px) counts, so a release that
				-- lands just beside the socket still connects.
				local bestDist = u(Config.HotwireSnapPx)
				for g in sockets do
					local center = g.AbsolutePosition + g.AbsoluteSize / 2
					local d = (center - p).Magnitude
					if d <= bestDist then
						bestDist = d
						socket = g
					end
				end
			end
			settle(w, line, from, socket)
		end)
	end
	-- Brief 11: the pad. Up / down (D-pad or left stick) pick a wire, A grabs it, up / down carry its end along
	-- the sockets, A drops it there (B puts it back; B with nothing in hand leaves the game).
	local unlocked: { Wire } = {}
	local pick = 1 -- index into the unlocked wires
	local carry: Wire? = nil
	local carryFrom = Vector2.zero
	local socketAt = 1
	local cursor = UI.frame({
		Name = "PadCursor",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		ZIndex = 9,
		Parent = host.content,
	})
	UI.corner(cursor, u(10))
	UI.new("UIStroke", { Color = Theme.Colors.gold, Thickness = u(3), Parent = cursor })
	local function refreshUnlocked()
		unlocked = {}
		for _, w in wires do
			if not w.locked then
				table.insert(unlocked, w)
			end
		end
		pick = math.clamp(pick, 1, math.max(1, #unlocked))
	end
	local function ring(target: GuiObject)
		local c = Frame.centerOf(host, target)
		cursor.Position = UDim2.fromOffset(c.X, c.Y)
		cursor.Size = UDim2.fromOffset(stubW + u(12), stubH + u(12))
	end
	local function paintCursor()
		cursor.Visible = Frame.onPad() and host.alive()
		if not cursor.Visible then
			return
		end
		local w = carry
		if w then
			local socket = socketRows[socketAt]
			ring(socket)
			local line = w.line
			if line then
				Frame.setLine(line, carryFrom, Frame.centerOf(host, socket) - Vector2.new(stubW / 2, 0), u(6))
			end
		else
			local target = unlocked[pick]
			if target then
				ring(target.stub)
			else
				cursor.Visible = false
			end
		end
	end
	local function step(dir: number)
		if carry then
			socketAt = math.clamp(socketAt + dir, 1, #socketRows)
		else
			refreshUnlocked()
			if #unlocked > 0 then
				pick = (pick - 1 + dir) % #unlocked + 1
			end
		end
		UI.sound(Theme.Sounds.reelTick, 1.4, 0.2)
		paintCursor()
	end
	local function grab()
		refreshUnlocked()
		local w = unlocked[pick]
		if not w then
			return
		end
		carry = w
		carryFrom = Frame.centerOf(host, w.stub) + Vector2.new(stubW / 2, 0)
		socketAt = w.index -- start level with the stub
		if w.line then
			w.line:Destroy()
		end
		w.line = Frame.line(wireLayer, carryFrom, carryFrom, u(6), col(w.index), 3)
		UI.punch(w.stub, 1.1, 0.15)
		Frame.padHaptic(0.25, 0.04)
		paintCursor()
	end
	local function drop()
		local w = carry
		if not w then
			return
		end
		carry = nil
		local line = w.line
		if line then
			settle(w, line, carryFrom, socketRows[socketAt])
		end
		refreshUnlocked()
		paintCursor()
	end
	refreshUnlocked()
	local held = 0 -- the stick's held direction (-1 up, 1 down) and its repeat clock
	local heldSince, heldLast = 0, 0
	host.pad = {
		button = function(key: string, down: boolean): boolean?
			if not down then
				return key ~= "ButtonB"
			end
			if key == "DPadUp" then
				step(-1)
			elseif key == "DPadDown" then
				step(1)
			elseif key == "ButtonA" then
				if carry then
					drop()
				else
					grab()
				end
			elseif key == "ButtonY" then
				-- the COLORBLIND toggle
				local on = not symbolsOn()
				symbolsOverride = on
				Remotes.SetOption:FireServer("hotwireSymbols", on)
				UI.sound(Theme.Sounds.cardFlip, 1.2, 0.4)
				UI.punch(toggle, 1.08, 0.15)
				paintSymbols()
			elseif key == "ButtonB" then
				local w = carry
				if not w then
					return false -- nothing in hand: leave the game
				end
				carry = nil
				if w.line then
					w.line:Destroy()
					w.line = nil
				end
				paintCursor()
			end
			return true
		end,
	}
	host.track(game:GetService("RunService").Heartbeat:Connect(function()
		if not host.alive() then
			cursor.Visible = false
			return
		end
		local s = Frame.stick(1)
		local dir = if s.Y > 0.6 then -1 elseif s.Y < -0.6 then 1 else 0
		local now = os.clock()
		if dir ~= held then
			held = dir
			heldSince, heldLast = now, now
			if dir ~= 0 then
				step(dir)
			end
		elseif dir ~= 0 and now - heldSince >= Config.NavRepeatDelaySec and now - heldLast >= Config.NavRepeatSec then
			heldLast = now
			step(dir)
		end
		paintCursor()
	end))
end

return Hotwire
