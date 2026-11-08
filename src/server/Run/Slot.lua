--!strict
-- Brief 8: who this copy of Run/ is. The Run/ folder in the place is the template and doubles as the hub slot
-- (state Hub forever, the range lives here); Runs clones it once per map and configures each clone before
-- anything in it is required, so every module in a clone sees its own id and map.
local Slot = {
	id = "hub",
	mapId = "Hub", -- the map this slot's runs play on ("Hub" for the hub slot)
	isHub = true,
}

function Slot.configure(id: string, mapId: string)
	Slot.id = id
	Slot.mapId = mapId
	Slot.isHub = false
end

return Slot
