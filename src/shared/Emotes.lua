--!strict
-- Emotes for the Avatar tab's SQUAD and MVP categories. A SQUAD emote is the pose the player strikes in the
-- run start and run end line-ups; the MVP emote is the flex played alone under the MVP stamp. Default R15
-- animations stand in for real emotes. Tapping one in the tab previews it on the avatar.
export type Emote = {
	id: string,
	name: string,
	slot: string, -- squad | mvp
	animationId: string,
	holdSec: number, -- how long the pose plays in the line-ups
	saleType: string, -- Direct | Crate | Event
	price: number?, -- nil = Prices.emote
}

local Emotes = {}

Emotes.List = {
	-- Squad poses (the line-ups).
	{
		id = "wave",
		name = "Wave",
		slot = "squad",
		animationId = "rbxassetid://507770239",
		holdSec = 1.2,
		saleType = "Direct",
	},
	{
		id = "point",
		name = "Point",
		slot = "squad",
		animationId = "rbxassetid://507770453",
		holdSec = 1.2,
		saleType = "Direct",
	},
	{
		id = "cheer",
		name = "Cheer",
		slot = "squad",
		animationId = "rbxassetid://507770677",
		holdSec = 1.2,
		saleType = "Direct",
	},
	{
		id = "laugh",
		name = "Laugh",
		slot = "squad",
		animationId = "rbxassetid://507770818",
		holdSec = 1.4,
		saleType = "Direct",
	},
	{
		id = "shuffle",
		name = "Shuffle",
		slot = "squad",
		animationId = "rbxassetid://507776043",
		holdSec = 1.4,
		saleType = "Crate",
	},
	-- MVP flexes (the MVP beat).
	{
		id = "dance",
		name = "Dance",
		slot = "mvp",
		animationId = "rbxassetid://507771019",
		holdSec = 3,
		saleType = "Direct",
	},
	{
		id = "dance2",
		name = "Groove",
		slot = "mvp",
		animationId = "rbxassetid://507776043",
		holdSec = 3,
		saleType = "Direct",
	},
	{
		id = "dance3",
		name = "Strut",
		slot = "mvp",
		animationId = "rbxassetid://507777268",
		holdSec = 3,
		saleType = "Direct",
	},
	{
		id = "victory",
		name = "Victory",
		slot = "mvp",
		animationId = "rbxassetid://507770677",
		holdSec = 3,
		saleType = "Event",
	},
} :: { Emote }

Emotes.ById = {} :: { [string]: Emote }
for _, e in Emotes.List do
	Emotes.ById[e.id] = e
end

-- Owned and equipped on a fresh profile.
Emotes.DefaultOwned = { "wave", "point", "cheer", "dance" }
Emotes.DefaultSquad = "wave"
Emotes.DefaultMvp = "dance"

function Emotes.forSlot(slot: string): { Emote }
	local out = {}
	for _, e in Emotes.List do
		if e.slot == slot then
			table.insert(out, e)
		end
	end
	return out
end

return Emotes
