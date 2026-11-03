--!strict
-- Tiny signal so client modules can talk without BindableEvents.
local Signal = {}
Signal.__index = Signal

export type Connection = { Disconnect: (self: Connection) -> () }

function Signal.new(): any
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal.Connect(self: any, fn: (...any) -> ()): Connection
	table.insert(self._handlers, fn)
	local handlers = self._handlers
	return {
		Disconnect = function(_self)
			local i = table.find(handlers, fn)
			if i then
				table.remove(handlers, i)
			end
		end,
	}
end

function Signal.Fire(self: any, ...: any)
	for _, fn in table.clone(self._handlers) do
		task.spawn(fn, ...)
	end
end

return Signal
