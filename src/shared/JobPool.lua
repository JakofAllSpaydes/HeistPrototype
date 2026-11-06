--!strict
-- Brief 6: the JOBS pool (daily quests and the weekly bounty). Three dailies are drawn per UTC day with no two of
-- the same `kind`; one bounty per UTC week (Monday). Progress comes from the run event bus (Jobs.lua):
--   kill (archetype or any) · elite · headshot · bag · goldBanked · wave (best wave in one run) · vault ·
--   sidejob · minigame · boss · revive · class (finish a run as it) · weapon (kills with an archetype)
-- `needsClass` keeps a class job off the board unless the player owns that class.
export type Job = {
	id: string,
	kind: string,
	target: number,
	arg: string?, -- archetype / class / weapon archetype the job counts
	title: string,
	flavor: string, -- MARLOW's line on the card
	needsClass: string?,
}

local JobPool = {}

JobPool.Daily = {
	{
		id = "d_runners",
		kind = "kill",
		arg = "Runner",
		target = 60,
		title = "KILL 60 RUNNERS",
		flavor = "The fast ones talk. Make them stop.",
	},
	{
		id = "d_henchmen",
		kind = "kill",
		arg = "Henchman",
		target = 150,
		title = "DROP 150 HENCHMEN",
		flavor = "Thin the payroll. Somebody's.",
	},
	{
		id = "d_any",
		kind = "kill",
		target = 250,
		title = "TAKE OUT 250 ENEMIES",
		flavor = "Volume work. Don't get precious.",
	},
	{ id = "d_bags", kind = "bag", target = 12, title = "COLLECT 12 BAGS", flavor = "If it's in a bag, it's ours." },
	{ id = "d_wave8", kind = "wave", target = 8, title = "REACH WAVE 8", flavor = "Stay alive past eight. That's it." },
	{ id = "d_vaults", kind = "vault", target = 2, title = "CRACK 2 VAULTS", flavor = "Two doors. Two dials. Go." },
	{
		id = "d_headshots",
		kind = "headshot",
		target = 40,
		title = "GET 40 HEADSHOTS",
		flavor = "Aim higher. Literally.",
	},
	{
		id = "d_revive",
		kind = "revive",
		target = 3,
		title = "REVIVE 3 TEAMMATES",
		flavor = "Nobody stays on the floor on my crew.",
	},
	{
		id = "d_torch",
		kind = "class",
		arg = "TORCH",
		target = 1,
		title = "RUN A HEIST AS TORCH",
		flavor = "Bring the matches. Bring a lot of them.",
		needsClass = "TORCH",
	},
	{
		id = "d_sharp",
		kind = "class",
		arg = "SHARPSHOOTER",
		target = 1,
		title = "RUN A HEIST AS SHARPSHOOTER",
		flavor = "Find a high spot and keep it.",
		needsClass = "SHARPSHOOTER",
	},
	{ id = "d_boss", kind = "boss", target = 1, title = "TAKE DOWN A BOSS", flavor = "Big one at ten. Put it down." },
	{
		id = "d_sidejobs",
		kind = "sidejob",
		target = 4,
		title = "FINISH 4 SIDE JOBS",
		flavor = "When I call, you pick up.",
	},
	{
		id = "d_minigames",
		kind = "minigame",
		target = 5,
		title = "BEAT 5 MINIGAMES",
		flavor = "Locks, wires, dials. Quiet hands.",
	},
	{ id = "d_elites", kind = "elite", target = 10, title = "KILL 10 ELITES", flavor = "The glowing ones pay triple." },
	{
		id = "d_shotgun",
		kind = "weapon",
		arg = "Shotgun",
		target = 50,
		title = "50 SHOTGUN KILLS",
		flavor = "Close and personal. Very close.",
	},
} :: { Job }

JobPool.Bounty = {
	{
		id = "w_titans",
		kind = "boss",
		target = 3,
		title = "TAKE DOWN 3 TITANS",
		flavor = "The big ones have a price on them. Collect.",
	},
	{
		id = "w_banked",
		kind = "goldBanked",
		target = 2000,
		title = "BANK 2,000 GOLD IN BAGS",
		flavor = "Fill the cases. All of them.",
	},
	{
		id = "w_wave20",
		kind = "wave",
		target = 20,
		title = "REACH WAVE 20",
		flavor = "Twenty waves. I'll buy the first round.",
	},
	{
		id = "w_kills",
		kind = "kill",
		target = 1000,
		title = "KILL 1,000 ENEMIES",
		flavor = "A thousand. Count them if you want.",
	},
} :: { Job }

JobPool.ById = {} :: { [string]: Job }
for _, list in { JobPool.Daily, JobPool.Bounty } do
	for _, j in list do
		JobPool.ById[j.id] = j
	end
end

return JobPool
