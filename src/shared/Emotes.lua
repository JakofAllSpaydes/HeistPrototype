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
	saleType: string, -- Direct | Crate | Event | Bundle | VIP | Pass
	price: number?, -- nil = Prices.emote
	rarity: number, -- 1..5 (Emotes.Rarity): the tile color on the Avatar tab
}

local Poses = require(script.Parent.Poses)

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
	-- Brief 6: the MARKSMAN SET pose, the two VIP poses and the battle pass poses (ids in Poses.lua).
	{
		id = "b_salute",
		name = "Salute",
		slot = "squad",
		animationId = Poses.Salute,
		holdSec = 1.6,
		saleType = "Bundle",
	},
	{
		id = "vip_stadium",
		name = "Stadium",
		slot = "squad",
		animationId = Poses.Stadium,
		holdSec = 1.8,
		saleType = "VIP",
	},
	{ id = "vip_tilt", name = "Big Tilt", slot = "mvp", animationId = Poses.Tilt, holdSec = 3, saleType = "VIP" },
	{ id = "p_shrug", name = "Shrug", slot = "squad", animationId = Poses.Shrug, holdSec = 1.4, saleType = "Pass" },
	{ id = "p_hello", name = "Hello", slot = "squad", animationId = Poses.Hello, holdSec = 1.6, saleType = "Pass" },
	{
		id = "p_callout",
		name = "Call Out",
		slot = "squad",
		animationId = Poses.CallOut,
		holdSec = 1.6,
		saleType = "Pass",
	},
	{ id = "p_godlike", name = "Godlike", slot = "mvp", animationId = Poses.Godlike, holdSec = 3, saleType = "Pass" },
	{
		id = "p_celebrate",
		name = "Celebrate",
		slot = "mvp",
		animationId = Poses.Celebrate,
		holdSec = 3,
		saleType = "Pass",
	},
	{
		id = "p_herolanding",
		name = "Hero Landing",
		slot = "mvp",
		animationId = Poses.HeroLanding,
		holdSec = 3,
		saleType = "Pass",
	},
} :: { Emote }

-- Rarity per emote (Rarity.Colors on the tiles and the detail row).
Emotes.Rarity = {
	wave = 1,
	point = 1,
	cheer = 2,
	laugh = 2,
	shuffle = 4,
	dance = 1,
	dance2 = 2,
	dance3 = 3,
	victory = 5,
	b_salute = 3,
	vip_stadium = 4,
	vip_tilt = 4,
	p_shrug = 2,
	p_hello = 3,
	p_callout = 3,
	p_godlike = 5,
	p_celebrate = 4,
	p_herolanding = 5,
} :: { [string]: number }

Emotes.ById = {} :: { [string]: Emote }
for _, e in Emotes.List do
	e.rarity = Emotes.Rarity[e.id] or 1
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
