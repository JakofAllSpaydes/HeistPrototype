--!strict
-- One line per server event so the designer can read a playtest back from the output window.
local Log = {}

function Log.event(tag: string, fmt: string, ...: any)
	print(string.format("[GHS %s] " .. fmt, tag, ...))
end

return Log
