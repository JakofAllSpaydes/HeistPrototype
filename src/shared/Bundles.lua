--!strict
-- Brief 6: FEATURED set bundles. Each content row is a Rewards.Reward plus `value`, its list share in R$; the list
-- price is their sum and the -X% ribbon compares it with the bundle price. With Config.BundleOwnedDiscount, items
-- the player already owns are struck through and their list share comes off the price, in the same proportion.
local Config = require(script.Parent.Config)
local Rewards = require(script.Parent.Rewards)

export type Content = { kind: string, id: string?, amount: number?, sec: number?, value: number }
export type Bundle = {
	id: string,
	name: string,
	tagline: string,
	color: string, -- the hero card's key color
	hero: Content, -- the item drawn big on the card
	contents: { Content },
	price: number,
}

local Bundles = {}

Bundles.List = {
	{
		id = "bundle_starter",
		name = "STARTER HEIST",
		tagline = "EVERYTHING YOU NEED FOR NIGHT ONE",
		color = "E8792A",
		price = 399,
		contents = {
			{ kind = "class", id = "TORCH", value = 300 },
			{ kind = "weapon", id = "FAL", value = 250 },
			{ kind = "gold", amount = 2000, value = 249 },
			{ kind = "tokens", amount = 5, value = 99 },
			{ kind = "crate", id = "arms", amount = 1, value = 129 },
		},
	},
	{
		id = "bundle_marksman",
		name = "THE MARKSMAN SET",
		tagline = "ONE SHOT, ONE KILL, ONE LOOK",
		color = "5C7A52",
		price = 1299,
		contents = {
			{ kind = "class", id = "SHARPSHOOTER", value = 300 },
			{ kind = "weapon", id = "Mosin", value = 400 },
			{ kind = "mask", id = "b_ghillie", value = 200 },
			{ kind = "emote", id = "b_salute", value = 150 },
			{ kind = "wrap", id = "b_woodland", value = 150 },
			{ kind = "gold", amount = 5000, value = 400 },
			{ kind = "tokens", amount = 10, value = 199 },
		},
	},
	{
		id = "bundle_highroller",
		name = "HIGH ROLLER",
		tagline = "TWENTY CRATES AND A DAY OF POWER",
		color = "A864E8",
		price = 1999,
		contents = {
			{ kind = "crate", id = "arms", amount = 10, value = 799 },
			{ kind = "crate", id = "mask", amount = 10, value = 699 },
			{ kind = "boost", id = "power", sec = 86400, value = 499 },
			{ kind = "tokens", amount = 25, value = 399 },
		},
	},
} :: { Bundle }

Bundles.ById = {} :: { [string]: Bundle }
for _, b in Bundles.List do
	-- The hero is the first item (class / weapon) or the first row.
	local hero = b.contents[1]
	for _, c in b.contents do
		if c.kind == "weapon" then
			hero = c
			break
		end
	end
	b.hero = hero
	Bundles.ById[b.id] = b
end

-- The Marksman's wrap goes on the bundle's weapon when granted.
Bundles.WrapTarget = { b_woodland = "Mosin" } :: { [string]: string }

function Bundles.listPrice(b: Bundle): number
	local sum = 0
	for _, c in b.contents do
		sum += c.value
	end
	return sum
end

-- The -X% on the ribbon: how far under the list price the bundle sells.
function Bundles.discountPct(b: Bundle): number
	local list = Bundles.listPrice(b)
	return if list > 0 then math.max(0, math.floor((1 - b.price / list) * 100 + 0.5)) else 0
end

-- The price for this profile: the owned items' list share comes off (never below a tenth of the price).
function Bundles.priceFor(b: Bundle, profile: any): (number, { boolean })
	local owned: { boolean } = {}
	local list = Bundles.listPrice(b)
	local ownedValue = 0
	for i, c in b.contents do
		local o = Config.BundleOwnedDiscount and Rewards.owned(profile, c :: any)
		owned[i] = o
		if o then
			ownedValue += c.value
		end
	end
	if ownedValue <= 0 or list <= 0 then
		return b.price, owned
	end
	local price = math.max(math.ceil(b.price * 0.1), math.floor(b.price * (1 - ownedValue / list) + 0.5))
	return price, owned
end

-- Every bundle a reward appears in (VIEW BUNDLE deep links).
function Bundles.containing(kind: string, id: string): { string }
	local out = {}
	for _, b in Bundles.List do
		for _, c in b.contents do
			if c.kind == kind and c.id == id then
				table.insert(out, b.id)
				break
			end
		end
	end
	return out
end

return Bundles
