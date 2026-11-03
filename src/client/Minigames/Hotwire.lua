--!strict
-- Hotwire (drag). Colored stubs on the left, shuffled sockets on the right. Drag each stub to the socket
-- of its color; the wire draws live, locks on the right socket, snaps back from the wrong one.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Client = script.Parent.Parent
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

local Hotwire = {
	title = "HOTWIRE",
	hint = "DRAG EACH WIRE TO THE SOCKET OF ITS COLOR",
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
	local locked = 0
	local wireLayer =
		UI.frame({ BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = host.content })

	for i = 1, n do
		local color = PALETTE[i]
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
		local socketColor = PALETTE[order[i]]
		local socket = UI.frame({
			BackgroundColor3 = Theme.Colors.panel2,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(rightX, y),
			Size = UDim2.fromOffset(stubW, stubH),
			ZIndex = 4,
			Parent = host.content,
		})
		UI.corner(socket, u(8))
		UI.stroke(socket, socketColor, u(3))
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
		wires[i] = { index = i, stub = stub, socket = socket, line = nil, locked = false }
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
			w.line = Frame.line(wireLayer, from, from, u(6), PALETTE[w.index], 3)
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
			if socket and sockets[socket] == w.index then
				-- Right socket: the wire locks in and the socket lights.
				w.locked = true
				locked += 1
				Frame.setLine(line, from, Frame.centerOf(host, socket) - Vector2.new(stubW / 2, 0), u(6))
				socket.BackgroundColor3 = PALETTE[w.index]
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
		end)
	end
end

return Hotwire
