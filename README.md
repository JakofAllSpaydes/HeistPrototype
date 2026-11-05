# GHS — Core Loop Prototype

Playable Roblox prototype of the Grand Heist Survival core loop: one room, one enemy type, hitscan guns,
infinite waves, cash, the weapon reel, ground loot, the big crate, the upgrade overlay, the crew call
(side job), three abilities and a heat star meter. Brief 2 adds the staging yard, six objective minigames
as test props, the downed / revive loop, a run start sequence and a run end sequence with an MVP moment
and a summary. Brief 3 turns the yard into the hub: a DataStore profile with Gold, a queue zone with Create Match
and a party-scoped run, a real Gold payout, the customization scene (Weapons / Classes / Avatar) and a downed sidearm.
Brief 4 grows the one enemy into a seven-archetype roster with elites, adds TITAN every ten waves behind a cutscene,
replaces the event heat meter with the GDD's pace meter, adds cash and gold bags with a team Banked total and the
vault job, an account level with XP per run, and an in-run scoreboard. Brief 5 moves weapons onto the crate's own
reel, gives upgrades elements and utility stats with wave-scaled income, adds real revive bars and ally callouts,
reworks INITIATE and adds ENGINEER, adds weapon and class mastery with mid-run tier-ups, makes the vault job
impossible to miss, and adds a dealer break after every boss wave and a vote to pause.

State as of **4 Nov 2026**: all brief 1 acceptance items are in, plus eight playtest rounds of feedback, the brief 2
slices (Round 9) and six feedback rounds on them (9b–10d below), the brief 3 build (Round 11) with its feedback rounds,
phase 2 (Round 12: all twelve class abilities live, with the 12b / 12c feedback passes), the Round 13 multiplayer pass
(revive pauses the bleed, teammates' tracers and shot sounds, busy tags, everyone votes to skip, mags live with the gun,
ragdolls and hit sparks), the brief 4 build (Round 14: roster, boss, heat as pace, bags, vault, level, scoreboard) and
the brief 5 build (Round 15: crate reel, elements, revive bars, ENGINEER, mastery, dealer, pause).
Everything on `main` builds clean and is what Studio sees through Rojo. The "Brief 3 verify list", the "Round 12 verify
list", the "Round 13 verify list", the "Brief 4 verify list" and the "Brief 5 verify list" are the walk-throughs for a
fresh Studio session; briefs 4 and 5 have not been run in Studio yet.

## Run it

1. `aftman install` (once) so `rojo`, `stylua` and `luau-lsp` resolve.
2. `rojo serve` in this folder.
3. In Studio: Rojo plugin → Connect. Delete the default `Baseplate` once in edit mode (the server also removes it). Press Play.

Everything the designer tunes lives in `src/shared/Config.lua`. Change a number, Rojo syncs it, play again.
The map is a Rojo-synced model (`src/map/Room.model.json`, regenerate with `lune run tools/genmap.luau`; `lune` is in
`aftman.toml`, and the generator loads Config through `luau.load` with Vector2 / Vector3 stubs).

You spawn in the **hub** (the yard south of the arena) with the hub HUD, 10,000 Gold on a fresh profile, the M1911 as
starter, INITIATE equipped and the plain mask. Profiles need `Enable Studio Access to API Services` on the place
(Game Settings → Security); without it the server warns once and keeps an in-memory profile for the session. Walk onto
the blue queue pad in front of the arena door (or press PLAY) to create a match. The three customization stations stand
along the west wall, the six minigame props and the tier pad along the east wall. Party and downed / revive lines need
Studio's Local Server with 2–4 players; everything else works solo.

## Controls

| Input | Action |
| --- | --- |
| LMB (hold) | Fire. `HoldToFire` in Config. |
| RMB (hold) | Aim down sights: narrower FOV, camera pulls in, half spread, tighter crosshair, lower sensitivity. `Ads*` in Config. With the cursor unlocked (Ctrl) it only pulls in a little and dragging rotates the camera. |
| R | Reload. Tube-fed guns (`shellReload` in Weapons, currently the SPAS-12) load one shell per `reloadTime`; firing or R again stops at the current count. |
| Scroll wheel | Zoom. Fully in is first person (character hidden locally); out to `CameraZoomMax`. |
| 1 | Buy an upgrade pick (also the clickable tile, left column). Weapons come only from gun crates. |
| F on a gun crate | `OPEN` (a `GUN CRATE` tag over it): every roll the crate holds plays back to back on the reel above it, seen by everyone, and each gun ejects onto the floor beside it as loot anyone can take. |
| Q / E / Z | The equipped class's three abilities, all fifteen live (INITIATE frag / adrenaline / claymore, ENGINEER turret / barricade / overclock, DOC stim shot / med bag / healing turret, SHARPSHOOTER eagle vision / dead eye / flashbang, TORCH molotov / flame turret / oil drum). Cooldowns in `AbilityCooldown` (less ABILITY COOLDOWN). Thrown ones (frag, molotov, flashbang) land at the cursor's floor point up to `ThrowMaxRange`; placeables stand `StructurePlaceDistance` ahead. A `x2` on a tile is a second charge (INITIATE mastery II). |
| P | Vote to pause (in a wave, the intermission or the dealer break; solo pauses at once). Also on the dealer card and the scoreboard. RESUME on the overlay (anyone). |
| T / V / F at the dealer | During the dealer break: T teleports you to the stall (as often as you like), V votes to skip the break, F buys the stand or prop whose panel is open. Mobile: the card's buttons and the panel's BUY. |
| F | Swap with a floor gun (ProximityPrompt). 0.5s cooldown between swaps. In the hub: `OPEN` on a station (WEAPONS / CLASSES / AVATAR) or a minigame prop, `TIER n` on the pad. |
| F (hold `BagCollectSec`) | `COLLECT` a cash bag (match cash to everyone) or `BANK` a gold bag (ticks the team's `◆ BANKED` row). Teammates see `GRABBING` over your head. |
| F at the vault door | `CRACK` the vault while CRACK THE VAULT is the open side job: opens the Safe dial at the wave bracket's tier. |
| Tab (hold) | The scoreboard: WAVE · TIME · stars · BANKED · CASH and one row per member in MVP order; the game keeps running behind it. Mobile: tap the wave bar (the `≡` chip beside N LEFT), tap again or anywhere outside to close. |
| Walk onto the queue pad | Create Match card (party size, map, difficulty, info, CREATE, X). Walking in joins an open party; walking out leaves it. |
| PLAY (hub HUD) | Walks you to the nearest queue zone. Dock tiles WEAPONS · CLASSES · AVATAR open the customization scene; LEAVE (red X) or Esc closes it. |
| F (hold `ReviveHoldSec`) | Revive a downed teammate within `ReviveRadius`. Their bleed timer stands still while you hold (`RevivePausesBleed`); letting go resumes it. Outranks floor guns: their prompts hide while a downed teammate is in reach. Mobile: a REVIVE hold button appears bottom-center. |
| Esc / X | Cancel an open minigame (counts as `cancel` in the log). |
| ◀ ▶ / A D | Spectating (bled out): cycle living teammates. REVIVE EVERYBODY button bottom-center. |
| F (hold 2s) | Hack the side-job beacon (hack jobs). Capture jobs: stand in the circle for `SideJobCaptureSec`; progress pauses when nobody is inside. Minigame jobs: F opens the game at the beacon. Kind is rolled per job from `SideJobKindWeights` (eight kinds, equal odds by default). |
| Esc / X / 2 | Close the upgrade overlay. |
| V | Vote to skip the intermission (or click the VOTES pill). Everyone in the party has to vote (`SkipVoteFraction` = 1; `SkipMinIntermissionSec` is the floor). |
| AUTO SKIP pill | Waves roll into each other: once the wave has fully spawned and `AutoSkipWaveSec` (10s) has passed, the next wave starts on top of whatever is left, with no intermission. |
| Ctrl | In a run: toggle the cursor lock so you can click HUD tiles. While unlocked the camera holds still, the character turns to face the cursor and shots go where the cursor is, so you can aim all the way around. Left Alt frees the cursor while held. In the hub the cursor is always free (RMB drags the camera) and every combat hotkey (fire, 1 / 2, Q / E / Z, V, Ctrl) is off; the server also refuses rolls, upgrades and abilities outside a run. |
| Backtick | Debug panel: add cash, skip/set wave, pause spawns, kill all, force rarity/tradeoff, drop crate, trigger call, god mode, reset run, force queue start, skip to run end, down me / down all / revive all, open any minigame, set tier, Stats (minigame averages and the run's heat clear / par ratios), +1,000 Gold, unlock all, reset profile, +500 XP / set level / reset daily, spawn any archetype (ELITE toggle), spawn boss, cash / gold bag, open vault, set heat, gas vault, Loot Rush, force element card, +100 mastery (held gun and class), open dealer, pause / resume. Mobile: the `DBG` chip top-left. |

Mobile: touch look, pinch to zoom, on-screen fire / ADS toggle / reload / ability buttons, tap the VOTES and AUTO SKIP pills, no hotkeys.
Hub HUD on mobile landscape: dock tiles 76×68, PLAY 44px, SHOP and INVITE as icon tiles, queue card at 80%; the
customization panel takes the right 62% with 64px tiles and a 60px dock.
Every minigame is tap or drag only (no double-tap, long-press or keyboard); the revive hold and spectate arrows are buttons.

## What is in the build

**Core loop.** Wave → intermission → wave, enemies spawn from 8 markers weighted toward the crew, cash per kill by
archetype, heat stars (0–5, half-star steps) scored per wave as a pace meter (below). Enemies never collide with
players or each other; stuck enemies detour, then teleport back to the spawn ring. Center banners mark WAVE N,
WAVE N CLEAR and the 3-2-1 countdown; "N LEFT" sits under the heat stars. The intermission can be skipped by vote
(V / VOTES pill; every player in the party must vote, `SkipVoteFraction` = 1), and AUTO SKIP rolls waves into each
other `AutoSkipWaveSec` after each one has fully spawned once everyone has it on. Kill chains show a combo counter
from x2 with words at tier counts (`ComboTiers`).

**Enemy roster (brief 4).** `Config.Enemies` is one row per archetype (hp, speed, dmg, range, cooldown, scale, color,
cash, attack); `Enemies.lua` reads it and does the scaling: `FinalHp = BaseHp × (1 + HpWaveMult)^(wave − 1) × (1 +
HpPerPlayerMult × (players − 1)) × DiffHpMult`, `FinalDamage = BaseDamage × (1 + DamageWaveMult)^(wave − 1) ×
DiffDamageMult`; player count never changes spawn counts. `Enemy.lua` is the base (rig from `Enemies/Rig.lua`,
targeting, movement with the stuck detour, damage / flinch / kill / ragdoll, stun and slow) and hands each enemy a
brain from `src/server/Enemies/` every heartbeat through one `api` of helpers: Henchman and Runner (`Melee`: walk at
the nearest player or the placeable in the way, hit on reach; the Runner sprints at 22 with a shrill wail), Shooter
(`Shooter`: advances to range with line of sight, holds, fires every cooldown at `ShooterHitChance`; a miss cracks a
tracer past you, muzzle flash on every shot, losing line of sight walks again), Marksman (`Marksman`: paints a red laser
on the nearest visible player for `MarksmanAimSec`, the line locks, the shot goes down it and only hits a player still
inside `MarksmanHitRadius` of it; a stun cancels the aim), Boomer (`Boomer`: runs at the nearest placeable within
`BoomerPlaceableSearch`, else the nearest player; in range it stops, beeps rising and its belly swells for `BoomerFuseSec`,
then `BoomerDamage` to players and `BoomerPlaceableMult` × to placeables in `BoomerRadius`; killed by damage it still
bursts at `BoomerDeathRadiusMult`), Grenadier (`Grenadier`: holds at range, lobs a shell: a red circle grows on the floor
from nothing to `GrenadierRadius` over `GrenadierTelegraphSec` while the shell arcs in, then the burst and a
`GrenadierFireSec` fire patch at `GrenadierFireDps`), Heavy (`Heavy`: slow, walks at the nearest player, stomps
placeables in its path for `HeavyPlaceableMult` ×, a hit throws you `HeavyKnockback` studs (your client applies it),
its two plates fly off at `HeavyPlateHpPcts` with a crunch). Shared rules: blocked by a placeable → hit it until it
breaks; retarget every `RetargetInterval`. Enemy hazards (`Enemies/Hazards.lua`): blasts that hurt players and
placeables, fire patches that burn players (`FieldTickSec`), the red telegraph discs (`TelegraphTransparency`).
Composition: `Config.Composition` rows apply from `WaveMin` until the next row, weights rolled per enemy at spawn (the
brackets are compressed so everything shows by wave 12; at `HeatShiftStars`+ the active row shifts `HeatBracketShift`
down). Spawning: each spawn picks a marker by proximity to the crew (within `NearRange` × `NearWeightMult`, up to
`FarRange` × 1, beyond × `FarWeightMult`), caps at `MaxActiveEnemies` (100) with the rest of the budget queued and
backfilled at once; every wave logs its composition. Silhouettes: scale and body color per row, a lean body, a belly, a
backpack, a wide body with plates, a gun with a muzzle; the head stays the red neon hitbox. No enemy uses job blue,
door amber or the bag colors.

**Elites.** Rolled at spawn at `HeatElitePerStar × max(0, stars − 1)` for any archetype but the Heavy and the boss:
`EliteHpMult` HP, `EliteCashMult` cash, `EliteScale`, a body-colored PointLight + Highlight and an `ELITE` tag.

**Hit and kill feedback.** Every bullet that lands on an enemy pops a white flinch flash on every client (the server
stamps `FlinchAt`, at most once per `FlinchAnimRate`; it never moves the enemy or stops its feet — `EnemyHitKnockback`
is the Round 13 shove, 0 by default), with a small spark burst at the impact (`HitSparks`) next to the damage number and
hit flash. A player kill knocks the body over instead of shrinking it: the Humanoid goes, the parts become a loose body
in the `Corpse` collision group (rests on the room only, never under a player's feet, bullets pass through it), thrown
along the killing shot with a hop and a tumble (`RagdollImpulse` / `RagdollLift` / `RagdollSpin`); a headshot kill pops
the head off (`RagdollHeadPop`). How far it flies depends on what killed it: the gun sets the base
(`RagdollForceByArchetype`: shotgun 2.8x, sniper 2.4x, LMG 1.5x, rifle 1.3x, pistol 1x, SMG 0.8x), damage past the
remaining HP adds up to `RagdollOverkillMax` more, and `RagdollVariance` jitters every throw. Explosions (claymore, a
Splash upgrade kill) throw bodies outward from the blast center with their own numbers (`RagdollBlast*`, falling to
`RagdollBlastEdge` at the radius). Fire fields, the flame turret and turret rounds only slump the body
(`RagdollTickForce`) and never flinch it. Bodies lie `RagdollLifetime` (2s), fade over `RagdollFadeSec` and go; at most
`ActiveRagdolls` (8) are on the floor at once, past that a kill shrinks out as before (`RagdollEnabled = false` turns
the whole thing off). Kills by the run clear, a fall or the cap shrink out. A bigger red burst (`KillSparks`) marks the
kill for the shooter. Kill cash is the archetype's `cash` row × the wave multiplier (`CashWaveMult`) × elite × the heat cash multiplier ×
CASH GAIN.

**Heat as pace (brief 4, `Heat.lua`).** The event meter is gone. Heat is a team meter, 0–5 in half stars, from
`HeatStart` (0), no decay, scored once per wave when the last enemy tagged with that wave dies (so AUTO SKIP overlap
counts against par on purpose): par = `ParTimeBase + ParTimePerEnemy × budget` (boss waves add `BossParBonusSec` on the
regular budget); clear ≤ `FastClearPct` × par → `HeatFastClear` (+1), ≤ par → `HeatParClear` (+0.5), > `SlowClearMult`
× par → `HeatSlowClear` (−0.5); AUTO SKIP active during the wave `HeatAutoSkip`; each side job done in the wave
`HeatJob`, each that expired `HeatJobFail`; downs `HeatDowned` each, capped at `HeatDownedMax`; a boss kill
`HeatBossKill` at once. Each component lands as its own small `+0.5 FAST CLEAR` / `−0.5 DOWNED` float beside the stars
(the changed star pops; the big HEAT UP label, flash and toast are gone). Effects at S stars: cash × (1 +
`HeatCashPerStar` × S), elite chance `HeatElitePerStar` × max(0, S − 1), spawn interval × (1 − `HeatSpawnPerStar` × S),
the bracket shift at `HeatShiftStars`. Every wave end prints `wave N clear 42.1s par 58.0s heat +0.5 → 2.5 (fast)`;
the debug Stats button prints the run's clear / par ratios so `ParTimePerEnemy` can be set from real runs. The summary
shows the final stars next to the wave. A debug skip or the run ending leaves the open wave unscored.

**Bags (brief 4, `Bags.lua`, spots in `BagSpots.lua`).** Two kinds, same interaction: a green duffel with a `$` pays
`CashBagBase × (1 + CashBagPerWave × wave)` match cash to every member; a gold case adds `GoldBagValue × (1 +
GoldBagPerWave × wave)` to the team's Banked total (`◆ N BANKED` row under the cash row, ticks on collect). Hold F
`BagCollectSec` to collect (`GRABBING` over your head), the bag pops in a money burst and a `<NAME> GRABBED $300` /
`<NAME> BANKED ◆ 40` toast. `CashBagsPerWave` (1) and `GoldBagsPerWave` (0.5: fractions carry, so every other wave)
spawn at every wave start on free arena spots weighted away from the crew (`BagFarMult` beyond `BagFarDistance`,
`BagNearMult` within `BagNearDistance`; gold bags keep `GoldBagMinDistance` when any spot allows it), up to
`MaxActiveBags`; bursts (the boss body, the vault, the debug Loot Rush) bypass the cap; `BAGS DROPPED · 1 CASH · 1
GOLD` toasts the drop. Bags persist until collected or the run ends; their beacons read through walls as markers with
a `$` / `◆` badge far away. At the summary the banked total and the run payout are one GOLD BANKED number that lands
in `profile.gold`; `stats.bagsCollected`, `stats.goldBanked` accumulate and `topBanked["TheBank:Normal"]` gets a
`★ NEW BEST BANKED` callout.

**The vault job (brief 4, `VaultJob.lua`).** A 24×24 vault closet behind a heavy sliding door on the arena's north wall
(`VaultSize`, `VaultDoorWidth`; the door frame is its amber beacon, a `VAULT` sign above, lights and a gas emitter in
the ceiling, `VaultBagSpots` spots inside). CRACK THE VAULT is a side job kind (`vault` in `SideJobKindWeights`, from
`VaultJobMinWave`, once per run when `VaultJobOnce`): MARLOW calls it, the frame turns job blue, the usual job timer
runs and F at the door opens the Safe dial at the wave bracket's tier (fails retry until the timer; expiry fails the job
as usual and the vault can be redrawn). Done: `WE'RE IN`, the door slides up, the lights snap on, `VaultBurstCash` cash
and `VaultBurstGold` gold bags drop onto the spots, `VAULT OPEN`, the side job pays as usual (no crate for this kind),
and the pill reads `VAULT · 0:60` from `VaultOpenSec`. `VaultGasWarnSec` before the end: alarm, red strobe inside,
MARLOW's `Gas! Get out!` card, the pill goes red. At zero: gas (fog, a green screen tint for anyone inside,
`VaultGasDps` until they step out, no stacking), the bags left inside fizzle, and the door closes only once nobody is in
the room; sealed, the frame goes grey and it never reopens this run. Enemies walk in like anywhere else. The shell
(call → interact → reward → timed room → consequence) is what door objectives reuse on the real map. Debug: `Open
vault`, `Gas vault`.

**Boss waves and TITAN (brief 4, `Boss.lua`, `Bosses/Titan.lua`).** Every `BossWaveInterval` (10) waves. The
intermission ends in a `BossCutsceneSec` cutscene (`BossCutsceneBeats`): the game pauses (no brains, players
invulnerable and input-locked, AUTO SKIP ignored), MARLOW's `Heavy response inbound. Big one.` in the crew-call slot
and a low shot of the entrance wall (the marker farthest from the crew); the wall blows (debris, flash, shake) and TITAN
steps through at `TitanScale` with a stomp per step; the barrels spin and the camera pushes in on the gun while
`TITAN · HEAVY RESPONSE` slams in bottom-third; the camera snaps back and the boss bar slides in under the wave bar;
the wave starts with `BossWaveBudgetPct` of the normal budget. TITAN: `TitanHp` × the wave HP scaling × the player
count multiplier, `TitanSpeed`, a contact hit for `TitanMeleeDmg` with `TitanKnockback`, placeables in its path break,
no flinch, four plates, a through-wall marker (red Highlight and a name / distance tag) and the bar (name, HP number,
phase pips at 100 / 66 / 33). Abilities one at a time, picked by cooldown and range: Sweep (barrels spin
`TitanSweepSpinSec`, `TitanSweepSpinSecP2` from phase 2, with a rising whine and a faint cone on the floor, then a beam
swings `TitanSweepArc` over `TitanSweepSec` doing `TitanSweepDps` to players in it with line of sight and to
placeables), Charge (a red line on the floor to a locked player for `TitanChargeTelegraphSec`, then a run down it at
`TitanChargeSpeedMult` that breaks placeables, hits the first player for `TitanChargeDmg` with `TitanChargeKnockback`,
and stops at a wall with a `TitanStaggerSec` stagger taking `TitanStaggerDmgMult`), Volley (`TitanVolleyCount` red
circles grow on the nearest player positions over `TitanVolleyTelegraphSec`, then Grenadier blasts with fire). Phase 2
at 66%: plates 1–2 fall, faster spin. Phase 3 at 33%: plates 3–4 fall and `TitanCallInCount` Henchmen from the nearest
marker every `TitanCallInSec`. Kill: heat `HeatBossKill`, `TitanCashBurst` to everyone, `BossBagBurst` bags round the
body, a boss crate with a guaranteed Legendary of a random owned gun plus `BossCrateCount − 1` normal deals, half a
second of slow-mo, a `TITAN DOWN` stamp, the bar flashes and drops. Kills by abilities count for the owner. A second boss
id drops into `Boss.registry` and `Config.BossId` without touching the shell.

**Account level (brief 4, `Progression.lua`, `LevelRewards.lua`).** `profile.level`, `profile.xp`, `profile.lastHeistDay`.
XP per run, per player, on the summary write: `XpPerWave × waves cleared + XpPerKill × kills + XpPerJob × jobs +
XpPerBoss × boss kills + XpSurvivedPerMin × minutes survived`, × `XpFirstHeistMult` on the first completed run of a
UTC day. Curve `XpToLevel(n) = XpCurveBase × n ^ XpCurvePow`, no cap, overflow carries so one run can level several
times. Every level pays `LevelGold`; milestones 5 / 10 / 25 / 50 grant a mask (`LevelRewards.Milestones`); `pass_token`
and `emote` exist as kinds with no handler. Summary: after the Gold count-up the XP row slides in under the header
(`LV 7` left, `LV 8` right, the bar fills over `XpFillSec` with the number counting, a level crossed flashes gold, bumps
both labels and pops `LEVEL 8 · +100 GOLD · BLUE VISOR`; `FIRST HEIST OF THE DAY ×2` under the bar when it applies).
Level shows on the hub tag (`LV 7 · TOP WAVE 14 ★`), the party card, the summary rows and the scoreboard; lifetime XP in
`stats.xp`. Debug: `+500 XP`, `Set level`, `Reset daily`.

**Scoreboard and time survived (brief 4, `Roster.lua`, `Scoreboard.lua`).** The server rebuilds the roster every
`RosterSyncSec` into `StateSync.roster`. Hold Tab (mobile: tap the wave bar; the `≡` chip beside N LEFT is the hint, tap
again or outside to close): a translucent panel, the game runs behind it; header `WAVE N · TIME 12:34 · stars ·
◆ BANKED 240 · $ CASH 3,120`; one row per member in MVP order: level and class circle, state dot (standing / downed /
spectating), kills, cash, bags, jobs, downs, revives, MVP score, your own row highlighted. Time survived runs from the
WAVE 1 banner, pauses for the boss cutscene and the run-over window, shows on the scoreboard and the summary next to
WAVE N (`WAVE 14 · 18:52 · ★ 2.5`), and lands in `stats.timeSurvived` and `topTime["TheBank:Normal"]`.

**Teammates' shots.** The server hands every other player in the run the end points of each bullet (`RemoteShot`):
their client draws the same tracer from that gun's muzzle and plays the shot sound at the gun, 3D and quieter with
distance (`RemoteShotVolume`, `RemoteShotRange`, pitch per archetype from `ShotPitchByArchetype`, which the local shot
uses too). No damage numbers or hitmarkers for anyone but the shooter. `RemoteTracers = false` turns it off.

**Busy tags.** A small blue pill over a teammate's head says what they are doing: LOCKPICK / KEYPAD / … while a
minigame is open for them (yard props or a minigame job), HACKING while they hold the hack prompt, CAPTURING while
they stand in the capture circle (`PlayerBusy` events from Minigames and CrewCall; `PlayerTags.lua`, `BusyTagOffset`).
Never shown over yourself.

**Weapons.** 15 guns across six archetypes (pistol, SMG, rifle, shotgun, sniper, LMG) with five rarities. The SCAR-H is a
3-round burst (`burst` / `burstDelay`; RATE and DPS show the delivered rate) and snipers carry built-in pierce by rarity
(`pierceByRarity`), neither spelled out in the name. Guns come only from arms crates (below): the reel plays over the
crate and the gun ejects beside it with a beam and a floor tag. Floor guns live 30s (`GroundWeaponLifetime`), countdown above the
tag, beam fades over the last 10s. Tags show name, DMG per shot ("33x8" for pellets) and RATE, each with a ▲ / ▼
against your held gun. Swapping leaves your old gun where the new one was with a fresh timer. Rarity odds are
bracketed by wave and tuned high for testing; pity floor (per player, on the roller) after 3 non-upgrades. Damage falls off with distance per
archetype (`FalloffByArchetype`; snipers never). Common paper DPS sits at 128–180 across archetypes and rarity
multiplies damage by 1 / 1.3 / 1.7 / 2.3 / 3.0, so a legendary of anything beats an epic of anything. Tube-fed guns
(`shellReload`, the SPAS-12) load one shell at a time and firing stops the reload where it is.

**Arms crate (brief 5, `BigCrate.lua`, `CrateReelUI.lua`, timing in `CrateReel.lua`).** The only in-run weapon source.
One drops at the intro, one after every completed side job (not the vault), one on TITAN's body (its first roll a
guaranteed Legendary) and one per ARMS DROP at the dealer; `BigCrateWaveInterval = 0` means none per wave. It lands
closed with party size + `CrateRollsExtra` rolls and a `GUN CRATE` tag with a countdown. F (`OPEN`) by any member
plays every roll back to back: a billboard over the crate, seen by everyone, carries the original weapon reel (a row of
gun icons in rarity frames sliding under a gold marker for `RollDurationSec`, 3D ticks rising in pitch, the result line
with DMG and RATE, the rarity juice), holds `RollLandHoldSec` (+`RollHighTierHoldSec` from Epic), and the gun arcs out to a free spot
`CrateDropRadius` away as ordinary floor loot (distinct weapon types per crate while the party's owned pool lasts).
Rarity: the wave bracket's odds, the crate floor `BigCrateRarityFloorByBracket`, the roller's pity. The prompt is gone
while a roll plays; the crate closes at 0 rolls or after `CrateLifetimeSec`, and floor guns keep their own timers. The
NEW WEAPON tile, hotkey 1 and the weapon price are gone.

**Upgrades.** Pick 1 of 3 cards (and the dealer's stands) from three categories drawn by `CategoryWeights` (gun 60 /
element 25 / utility 15) before the stat: 13 gun stats (Damage, FireRate, MagSize, ReloadSpeed, CritChance, HeadshotMult,
MoveSpeed, Accuracy, Pierce, Ricochet, Splash, Multishot, Lifesteal); three elements that go on every shot, on
every enemy the shot hits (`Elements.lua`; look in `StatusFx.lua`): INCENDIARY (burn `IncendiaryDps` for
`IncendiaryBurnSec`, orange tint and embers), CRYO (slow `CryoSlowPct` for `CryoSlowSec`, `CryoStacksToFreeze` procs
in that window freeze for `CryoFreezeSec`, blue tint, frost shards, ice), CONCUSSIVE (a `ConcussiveStuds` slide along
the shot and a `ConcussiveStunSec` interrupt, Heavy / boss `ConcussiveHeavyMult` and the boss is never interrupted,
a white ring); every hit applies the held elements; the first take is 100% power, later takes add the card's percent (burn DPS and
tick rate `IncendiaryTickRatePerPower`, slow / freeze, knockback; CONCUSSIVE interrupts at most every
`ConcussiveInterruptSec`); and utility: ABILITY COOLDOWN (capped `AbilityCooldownCap`), ABILITY POWER (ability damage,
heal, placeable HP) and CASH GAIN (kills, bags, job payouts; it replaced Greed). Each card spins an icon reel at the top,
lands on the stat, then the text reveals. Higher rarity = bigger punch/shake/flash/rays. Tradeoff cards (`TradeoffChance`,
halved in brief 5) carry a malus line; never on an element card, and the malus never lands on an element or CASH GAIN.
The tracker grid shows counts for gun stats, the power for elements (`130%`) and the total for utility (`-12%`).
Income: kill cash = archetype cash × (1 + `CashWaveMult` × (wave − 1)) × elite × heat × CASH GAIN; every wave end prints
`[GHS Income] wave N cash earned X upgrades bought Y (name)` and debug Stats adds upgrades per player per wave
(target 1–1.5 through wave 20).

**Abilities.** All five class kits are live (`Abilities.lua`, numbers in Config's Abilities group, growth per
ability level through `AbilityGrowth`). Placeables stand `StructurePlaceDistance` ahead; attackable ones (turret,
barricade, healing turret, flame turret, oil drum) have HP bars and enemies walk to and hit them; a med bag and a
claymore are not targeted. Ground fields (med bag, molotov, the fire a broken drum leaves) act every `FieldTickSec`
on whoever stands in the circle. Thrown abilities (flashbang, molotov) arc `ThrowDistance` over `ThrowFlightSec`.
Self buffs (stim, stim shot, dead eye) share one slot per player; the tile that fired shows the seconds left.
- INITIATE: frag (thrown to the cursor, goes off the moment it lands: `FragDamage` to everything in `FragRadius`),
  adrenaline (6s move, fire-rate and reload-speed buff with FOV push; no heal. Ability id `stim`, `Adrenaline*` in
  Config), claymore (below, moved here from SHARPSHOOTER with its level).
- ENGINEER (brief 5): turret (auto-fires at the nearest enemy, 150 HP, 30s), barricade (300 HP wall, 45s), overclock
  (`OverclockSec`: every friendly placeable fires / heals `OverclockRateMult` ×, a med bag heals faster, barricades
  carry an `OverclockShieldHp` shield that soaks hits first; placeables glow amber; placeables put down during it join).
- DOC: stim shot (6s fire-rate and reload buff, +40 HP, no move speed), med bag (green circle, heals every standing
  teammate inside `MedBagHealPerSec`, 15s; one quiet `+N` float a second), healing turret (150 HP, beams the hurt
  teammate with the lowest HP share in `HealTurretRange` for `HealTurretBeamHeal` a second, 30s).
- Claymore (INITIATE's Z): planted, arms after `ClaymoreArmSec`, an enemy inside `ClaymoreTriggerRadius` sets it
  off for `ClaymoreDamage` to everything in `ClaymoreBlastRadius`, 60s.
- SHARPSHOOTER: eagle vision (brief 5: every enemy within `EagleEyeRadius` glows red through walls for `EagleEyeSec` and
  takes `EagleEyeBonusPct` more from any source), dead eye (8s: weapon damage +25%, move
  +20%, every bullet passes through `DeadEyePierce` more enemies; a fractional pierce like 2.2 is one more enemy
  at 20% damage), flashbang (thrown; every enemy in `FlashRadius` stops and stops swinging for `StunDuration`, head goes white).
- TORCH: molotov (thrown; a fire circle for `MolotovLifetime` that burns `MolotovBurnPerSec` and slows
  `MolotovMoveSlowPct`), flame turret (150 HP, a `FlameTurretRange` stream at `FlameTurretDps`, 30s), oil drum
  (200 HP drum that blocks like a barricade; when enemies break it, not when it expires, it burns for `OilDrumBurnSec`).
Kills by turrets, fields and claymores pay the owner's kill cash. Abilities are free in a run (the Classes tab `$`
is a label). Cooldown sweeps on the ability tiles. Airstrike was removed. Abilities hold charges (one each; INITIATE
mastery II gives Frag and Claymore a second, `x2` on the tile), recharged one cooldown at a time.

**Mastery (brief 5, `Mastery.lua`, copy and tier math in `MasteryCopy.lua`).** `profile.mastery.weapons[id].xp` and
`.classes[id].xp` (+ lifetime `stats.weaponMasteryXp` / `classMasteryXp`). XP lands the moment it is earned: per gun
kill `MasteryXpPerKill` (elite `MasteryXpPerEliteKill`, boss `MasteryXpPerBossKill`), per wave played
`MasteryXpPerWave` (boss waves `MasteryXpPerBossWave`). Tiers at `WeaponMasteryTiers` unlock the `MasteryWrapIds` wraps
on that gun (Gunmetal / Gold / Black-Red: never sold, apply only on the gun that earned them); tiers at
`ClassMasteryTiers` turn on the class passives, always on while the class is equipped: INITIATE (Adrenaline heals
`StimMasteryHealPct`; +`MasteryExtraCharges` Frag / Claymore charge; kills during Adrenaline extend it `StimExtendSec`
up to `StimExtendCap`), ENGINEER (placeables +`EngineerPlaceablePct` HP and fire rate; idle placeables regen
`FieldRepairPct` / s with no enemy in `FieldRepairRange`; Overclock also gives every crew gun `CrewOverclock*`), DOC
(med bag radius and healing turret range +`DocReachPct`; downed or bled-out allies inside stand up on their own over
`AutoReviveSec`; the med bag heals `FieldHospitalHealMult` × over `FieldHospitalRadiusMult` × and allies inside deal
+`FieldHospitalDmgPct`), SHARPSHOOTER (headshots +`SharpHeadshotAdd`; snipers and pistols reload `MarksmanKitReloadPct`
faster and Eagle Vision +`MarksmanKitEagleEyePct`; headshots during Dead Eye put a round back and trim
`DeadEyeHeadshotCdr`), TORCH (burns tick `TorchBurnRateMult` × faster; runs start with INCENDIARY; burning kills trim
`BackdraftCdr` off the Molotov). A tier crossed mid-run applies at once and drops the MasteryUp card under the wave bar
(emblem, rays, sting, `AK-47 · MASTERY II`, the reward; `MasteryUI.lua`, `MasteryPopSec`). Weapon tiles and class pills
in the customization scene carry a bar with three pips and a tooltip; the summary shows the MASTERY line and the
run's tier-ups.

**Dealer break (brief 5, `Dealer.lua`, `DealerUI.lua`).** After every boss wave is cleared: state `Dealer` for
`DealerSec` (no spawns, heat frozen, the clock only stops for a pause), MARLOW's `DealerLine`, a Part stall with an
idling DEALER at `DealerStallPosition`, the top-center card (`DEALER · 1:30`, TELEPORT TO DEALER any number of times, unanimous SKIP). Per-player stock: `DealerStock` stands from the pick-3 generator priced `ShopPriceByTier` × the
upgrade escalation (each buy counts as an upgrade bought), drawn by each client on the same table; ARMS DROP
(`ShopCratePrice`, a crate at the stall), HEAL ALL (`ShopHealPrice`), REROLL (`ShopRerollPrice`, doubling). The nearest
stand or prop within `ShopReadRadius` opens a panel with the effect lines current → new; F (or BUY) buys.

**Pause (brief 5, `Pause.lua`, `PauseUI.lua`).** VOTE TO PAUSE (P, the PAUSE pill on the wave bar, the scoreboard) in a wave, the
intermission or the dealer break; unanimous, solo at once, one per `PauseCooldownWaves`. Frozen: enemies, damage,
movement and fire, and every timer (bleed, floor guns, crates, side jobs, the vault, the dealer, ability lifetimes and
cooldowns, spawns, the heat clock, the intermission, the run clock). `PAUSED · names` with the time left and two votes:
VOTE TO EXTEND (+`PauseExtendSec`, as often as everyone agrees) and VOTE TO RESUME (everyone; solo at once); it resumes
by itself at `PauseMaxSec` (5 min, plus extensions) after a `PauseCountdownSec` countdown. No limit on how often. Modules join through `Pause.active`, `Pause.delay`,
`Pause.onTick` and `Pause.onResume`.

**Crew call / side job.** A call from MARLOW on wave 1 and every `SideJobEveryWaves` (2) waves, kind rolled from
`SideJobKindWeights` (equal odds; the Safe dial is weighted 0 since it is the vault's own beat): "VAULT PING" (hack
the terminal, hold F), "HOLD THE FLOOR" (stand in the circle for `SideJobCaptureSec`; progress pauses when nobody is
inside, a green disc fills on the floor), one of the minigames (the beacon carries an OPEN prompt; a validated done
finishes the job, fails can retry until the timer), or CRACK THE VAULT (above; forced every `VaultJobEveryWaves`
waves, otherwise drawn only when the vault can be). The dialogue card slides in from the right into
the top-right stack with typewriter text, collapses in place to a timer pill (with a progress bar for capture), and the
result card expands from that pill. A world marker over the beacon shows name, hint, timer and distance; past
`MarkerCompactDistance` it shrinks to a badge. Cards hold `CallHoldSec` (4.5s) before collapsing. If the job is still
open at `SideJobReminderPct` (50%) of the window, MARLOW's card comes back with a reminder line (`Lines.reminder`) and
collapses again. Done within 75s: $600, `SideJobGold` gold per player, a crate drop and `HeatJob` at the wave's end.
Fail: `HeatJobFail` at the wave's end. A run ending with a job open clears it on every client.

**HUD.** Built in code from `src/client/UI/Theme.lua`, scaled manually from a 760px basis. Wave bar with heat stars,
N LEFT, AUTO SKIP and VOTES pills (top-center), transient center toasts for wave/heat/crate/vote events, top-right
stack for the side job, buy column on the left, ability column on the right, bottom-center health + held slot
(DMG + RATE, DPS delta float on change), ammo with reload ring on the crosshair, hit markers, damage numbers, kill
pops, combo counter, cash floats, hurt vignette, spawn puffs, pickup rings. Upgrade cards show icon reel, name,
percent and stat only; rarity is the card colour.

**Camera.** Right-shoulder third person; scroll / pinch zooms between `CameraZoomMax` and first person (character
hidden locally). RMB (mobile: ADS toggle) aims: narrower FOV, camera pulls in, half spread, tighter crosshair. Ctrl
unlocks the cursor: the camera holds, the character turns to face the cursor, the crosshair rides it and shots go there.
Downed drops the pivot to `DownedCameraHeight`; spectate and the two sequences take the camera over (`ClientState.cameraMode`).

**Hub and the run loop (brief 3).** The map is the arena plus a 120×80 yard on its south wall (`YardWidth`,
`YardDepth`, `DoorWidth`, `QueueZoneSize`, `StationSpacing`, `PropSpacing`; regenerate the map after changing them).
The yard is the hub: spawn at the center facing the arena door (the van parks beside the spawn and only appears in the
start animation), one queue zone (`QueueZoneCount` zones; a 16×16 blue pad
with a gate frame and a billboard) in front of the door, three stations along the west wall (gun rack `WEAPONS`,
podium `CLASSES`, mask wall `AVATAR`; `F` opens the customization scene on that tab), the minigame props and the tier
pad along the east wall. `GameLoop` runs `Hub → Queue start → Intro (run start) → Wave / Intermission … → RunOver →
RunEnd → Summary → Hub`. In the hub nothing spawns, no crew call, no crate, no cash; the hub HUD hides the buy
column, abilities, wave bar, health, ammo and held slot (`HUD.setMode("hub")`). `MatchMode = "local"`: the party plays
in this server's arena. The party, not the server, is the run's player set: run-scoped events (`World.fireRun`) and the
line-ups go to members only, non-members stay in the hub with the hub HUD, and late joiners always land in the hub.

**Hub HUD.** PLAY top-center (green; teleports you onto the nearest open pad, where the Create Party card opens),
SHOP icon tile left-center (amber, `Shop` placeholder), Gold pill bottom-left with `+` (placeholder) and INVITE
FRIENDS under it (does nothing), the dock bottom-center (WEAPONS · CLASSES · AVATAR as 92px icon tiles with labels
under them, reference style), BOOSTS bottom-right (icon chips: a stub `◆ +50%` chip with a countdown from `StubBoostSec`,
two empty), the compact queue card under PLAY while in a party, and a `TOP WAVE N ★` billboard with the class icon
above every character in the hub. Top-left stays empty for server chat.

**Queue zone and Create Match (`Queue.lua` / `QueueUI.lua`, GDD_7 Hub → Queue Zones minus the teleport).** Walk into an
empty zone (or press PLAY) → the Create Party card (reference layout: blue header bar with X, Select Map thumbnails
with COMING SOON fillers, Difficulty segment with HARD / NIGHTMARE disabled and a bonus row showing `DiffGoldMult` and
your top wave, Party size 1–`MaxPartySize` segment, a row of purple boost chips that toast `PHASE 4`, CREATE PARTY;
movement is locked while it is open; X cancels and steps you out). CREATE locks the settings and makes you the owner;
the billboard shows map · difficulty, one slot per party size
and the countdown; members see the same card compact under PLAY. Others join by walking in (`<NAME> JOINED THE PARTY
(2/4)` on the billboard and member HUDs), leave by walking out; a full party starts at once, a party of 1 starts on
CREATE, otherwise `QueueCountdownSec` (15) from creation; the owner leaving passes ownership to the next member; an
empty zone resets. Start → every member goes through the run start into the arena; the zone reads `MATCH IN
PROGRESS` and refuses entry until the run ends (local-mode rule, noted in code). PLAY AGAIN on the summary re-forms the
same party on the pad with the same settings and a fresh countdown (a full party starts again by itself); TO LOBBY
(or the 30s auto) returns the party to the hub spawn and reopens the zone. Debug `Force queue start` starts your
open party now, or a party of just you.

**Profiles (`Profiles.lua`, DataStore `GHS_Profiles_v1`).** Loaded on join before the character spawns; session cache
per player; `UpdateAsync` with 3 tries and 1 / 2 / 4s backoff; written on every purchase / equip (debounced
`ProfileSaveDebounceSec`), on the run payout, on leave and every `ProfileAutosaveSec`; a failed payout write stays in
`pendingPayout` and retries in the hub; an advisory session lock key per player. Without API access the module falls
back to an in-memory profile and warns once. Shape: `gold`, `weapons[id] = { level, wrap }` (presence = owned),
`starterWeaponId`, `classes { owned, equipped }`, `abilities[id] = level`, `masks { owned, equipped }`, `wraps.owned`,
`topWave["TheBank:Normal"]`, `topBanked`, `topTime`, `level`, `xp`, `lastHeistDay`, `stats { kills, matchesPlayed,
goldEarned, bagsCollected, goldBanked, xp, timeSurvived }`, `pendingPayout`, `version`. A fresh profile
has `StartingGold` (10,000), one gun of each archetype at level 0 (`Weapons.DefaultOwned`: M1911, UZI, AK-47,
SPAS-12, AWP, M249; older stores are topped up on load), the M1911 as starter, INITIATE and the plain mask. `Prices.lua` is the only
price file (`weaponUnlock`, `weaponUpgrade`, `class`, `ability`, `mask`, `wrap`, all 100). The whole profile rides in
`StateSync.profile` so every screen reads from one place. Hat, hair and face accessories are removed on join; the
equipped mask (head recolor plus a visor or bandana Part welded to the head) shows in the hub and the run.

**Payout (GDD_7).** At the summary each party member earns `GoldEarned = (Σ over cleared waves of (GoldPerWaveBase +
GoldPerWaveAdd × (wave − 1)) + GoldPerObjective × side jobs) × DiffGoldMult` plus their `SideJobGold` per job, paid once
into the profile (it accumulates across REVIVE EVERYBODY saves; players who left earn nothing). `topWave` updates when
the run beat it with a `★ NEW PERSONAL BEST` callout on the summary; lifetime kills, matches and gold accumulate. The
summary's GOLD EARNED headline is this number, and the hub Gold row shows the new balance on return.

**Customization scene (`MetaScene.lua`, `src/client/Meta/`).** Opened from a dock tile or a station prompt on that
tab. Movement is hard-locked while it is open (controls off, root anchored locally, walk speed 0; the same lock holds
the Create Party card, which instead closes when you walk off the pad). The scene drives the camera itself every
frame (`MetaCameraTweenSec` ease): it stands `MetaCameraDistance` (7.5) in front of the character and
`MetaCameraSideShare` of that to the character's left, `MetaCameraHeight` up, aiming `MetaCameraAim` (1.6 studs)
below the character's center, so the avatar fills the left third with its head near the top of the frame, facing the
camera and playing the equipped class's idle (`ClassIdleAnimationId`); the hub HUD hides and the TOP WAVE billboard is
kept off every frame. Dragging on the avatar side of the screen (not on the panel, dock, gold pill or strips) turns
the avatar round (`MetaDragSensitivity`). The Gold pill and the dock (LEAVE · WEAPONS · CLASSES · AVATAR, 96px tiles)
sit bottom-left and read the balance on open. All three tabs share one format
(reference board): a panel on the right
58% (62% on mobile) with a blue header bar (title, red X), filter pills, OWNED / UNOWNED section bars over colored
tiles 4 per row (name on top, icon, a `LV n` / `◆ 100` / `CRATE` / `EVENT` pill at the bottom, a white frame on the
selection) and a detail column (big image well, name, sub-line, stat rows with `current » next` in green, flat green
/ pink / blue buttons). The Gold pill and the dock (LEAVE red X · WEAPONS · CLASSES · AVATAR as icon tiles with
labels) sit bottom-left and never hide, so every sub-view can be left. Selections preview live on the character
(wrap color on the gun's grip, mask, class idle); nothing is saved until a purchase or equip. Toasts bottom-center
(`<name> unlocked and equipped!`: every unlock equips itself, weapons as starter, wraps on the gun they were bought from,
classes and masks at once; `Not enough Gold!`, `<name> equipped as Starter!`, `<name> equipped!`) with celebratory / error /
click sounds. All actions go through one RemoteFunction (`Meta`) that validates against the profile, charges Gold
and marks the profile dirty.

- **Weapons tab.** Filter pills ALL · PISTOL · SMG · RIFLE · SHOTGUN · SNIPER · LMG plus a working search box. All
  15 real guns are Direct sale; four showcase guns (`Weapons.Showcase`: Exogun and StormLinker as CRATE, Railcaster
  and Hornet as EVENT) render in UNOWNED with their label and can never be unlocked, rolled or dealt. Tiles are
  colored by archetype with `LV n` on owned and a `STARTER` tag on the equipped one. Detail: name, firing mode,
  `LV n` or `LOCKED`, DPS · Damage · Rate · Mag Size · Reload at the current level with `» next` in green when owned;
  UNLOCK (green), VIEW CRATE (placeholder) or EVENT ONLY (disabled); owned: UPGRADE (green), EQUIP STARTER (blue) /
  EQUIPPED AS STARTER, CUSTOMIZE (pink).
  Level math lives in `Weapons.atLevel` and `Stats`: damage × (1 + `UpgDmgPct` × level), mag × (1 + `UpgMagPct` ×
  level), reload ÷ (1 + `UpgReloadPct` × level), fire rate × (1 + `UpgFireRatePct` × level), applied before rarity
  and in-run upgrades everywhere the gun appears (starter, rolls, crate deals, floor tags via the gun's `Level` /
  `RateMult` attributes). Upgrade cost = `upgBaseCost` × `RarityUpgCostMult` ^ level. The starter spawns at Common at
  its level; the in-run roll pool is the owned set and the crate pool is the union of the party's owned sets (each gun
  at the highest owner level). CUSTOMIZE hides the panel, the dock and the gold pill and centers the camera on the
  gun (`MetaWrapZoomDistance`) with a category strip bottom-center (BACK · SKIN locked · WRAP · CHARM locked); WRAP
  shows the wraps row: a Back tile, a
  None swatch, the six wraps (`Wraps.lua`) with a lock and a `◆ 100` tag over the selection when unowned, a ✔ on the
  applied one, previewed live, BUY / APPLY / REMOVE WRAP on the right. A wrap is a Color3 on the gun's grip part
  (`HeldGunWrap`) in the hub and in-run.
- **Classes tab.** `Classes.lua` lists, in carousel order, INITIATE (Frag Q, Adrenaline E, Claymore Z), ENGINEER (Turret
  Q, Barricade E, Overclock Z), DOC (Stim Shot, Med Bag, Healing Turret), SHARPSHOOTER (Eagle Vision, Dead Eye, Flashbang) and
  TORCH (Molotov, Flame Turret, Oil Drum) with the GDD copy, in-match `$` price and upgradeable variables. The category
  pills are the classes (colored circle with the class glyph — ENGINEER's 🔧 — name, lock when unowned, ✔ when
  equipped, the mastery bar along the bottom); below them the selected class's three ability
  rows, and the detail column (class well, name, EQUIPPED / UNLOCKED / LOCKED, the three hotkey rows, EQUIP / UNLOCK
  in green); the preview plays the selected class's idle. One row per ability: icon with the

  `$` price, name and hotkey, description, stats as `current > next` and UPGRADE · ◆ 100 (greyed `NOT UNLOCKED` on an
  unowned class). EQUIP sets `profile.classes.equipped`; the in-run ability tiles rebuild with that class's three
  abilities (Q / E / Z in order). All twelve abilities work in a run (Round 12).
  Ability levels (`profile.abilities[id]`) persist across class switches, no cap; stat at level = base × (1 +
  `GrowthPct` × level) from `AbilityGrowth.lua` (`AbilityGrowthPct` 0.1 everywhere). Every `vars` entry on the tab
  is the number the ability really uses in-run, at that level.
- **Avatar tab.** Category pills MASKS · SQUAD · MVP. Masks: eight in `Masks.lua` (name, color, `type` Head / Face,
  `rarity`, shape visor / bandana / none for the geometry, `saleType`), OWNED then UNOWNED rarity-colored tiles 4 per
  row with the weapons tab's tile rules, live preview on the character, and the detail column (rarity well with the
  mask color on the icon, name, type · rarity · sale, EQUIP / UNLOCK / VIEW CRATE / EVENT ONLY); the
  equipped mask is applied by the server (`PlayerState.applyMask`) on every character: in the hub, in the line-ups
  and in the run. SQUAD and MVP: emotes from `Emotes.lua` (default R15 animations stand in; `slot` squad or mvp,
  `saleType`, `Prices.emote`). The SQUAD emote is the pose the player strikes in the run start and run end line-ups
  (`profile.emotes.squad`, carried in the roster as `poseAnim` / `poseHold`; dummies still roll `Poses`); the MVP
  emote is the flex played alone under the MVP stamp (`profile.emotes.mvp`, `mvpAnim`). Tapping a tile plays the
  emote on the avatar, the detail has a ▶ PREVIEW, and EQUIP / UNLOCK set it. Unlocks auto-equip.

**Minigames.** Six games, played from the yard props for testing and from side job beacons in the arena. One client
module per game under `src/client/Minigames/`, sharing `Frame.lua` (centered panel `MinigamePanelPct` of the shorter
screen edge wide, crew-call frame style, title, hint, elapsed timer, X / Esc cancel, damage shake, downed = fail,
haptics on hits and locks, closes as a cancel past `MinigameCloseDistance` from the prop). On DONE or FAILED the gun
and camera come back that frame and the panel slides off over `MinigameExitSec`. The server (`Minigames.lua`) owns
the session: the prompt opens it, the client sends done / fail / cancel with its miss count, anything faster than
`MinigameMinSec[name]` is logged as a fail, and every close prints
`minigame <name> tier <n> done in <sec>s, <fails> fails` (or `… fail|cancel <sec>s <misses> misses`). The debug panel's
`Stats` button prints per-game averages. Tier (1–3, `MinigameTier`) is session-wide from the pad or the debug panel:
Lockpick (tap: zone width and points needed), Hotwire (drag: wires), Keypad (tap: digits; typing early hides the
code), Arm charges (tap: caps), Safe dial (drag: numbers), Frequency jam (drag: locks and slider range).

**Downed, revive, game over.** 0 HP → `Downed.down`: crawl speed and animation (`DownedAnimationId`), no jump, no
abilities / buys / swaps, enemies drop you from targeting, the health bar becomes a red bleed bar from
`BleedOutSec` (15s) with GIVE UP (bleed out now) and SELF-REVIVE (free, counter) above it, a red-cross marker with name
and seconds over you for teammates. A standing teammate within `ReviveRadius` holds F for `ReviveHoldSec` (brief 5:
a centered bar under their crosshair, `REVIVING NAME` with the seconds left, ticking every `ReviveTickSec`, green
`REVIVED` on completion, a red snap-back on release, the crosshair ring kept; your bleed bar gains a green second fill
with `NAME IS REVIVING YOU` and your marker shows the same fill to the party; the bleed timer stands still for the
length of the hold, `RevivePausesBleed`, and the marker's seconds turn green) → you stand at `ReviveHPPct` with
`ReviveInvulnSec` of invulnerability, a green pulse, the camera easing up from the floor and a `REVIVED BY` toast for
both. Ally callouts (`Callouts.lua`): downed, revived and bled-out players radio a line with their Roblox headshot to
teammates (`CalloutSec`, red frame; Revive Everybody gold to all), queued behind MARLOW and the boss cutscene. Bleed-out removes the character and opens spectate (camera orbits living teammates, name
and HP top-center, REVIVE EVERYBODY free with a counter: everyone downed or bled out stands up where they fell,
`<NAME> REVIVED THE CREW` center toast). **Run over** when nobody is standing and nobody is still bleeding, so a solo
player bleeds (and can self-revive) before game over: enemies freeze and fade, the lens pulls in and the world
desaturates under a `RUN OVER · WAVE N` stamp for `RunOverSlowSec + RunOverHoldSec` (5s). Inside that window REVIVE
EVERYBODY still saves the run: the crew stands up, enemies clear and the same wave restarts (SECOND CHANCE); after it
the press is ignored and the run end plays. Characters are loaded by hand (`Players.CharacterAutoLoads = false`).

**Mags live with the gun (Round 13).** The server never simulates ammo, but it keeps the count with the gun: every
shot carries the rounds left (`FireShot`'s fourth argument) and every reload reports it (`AmmoReport`), stored on the
held record (`Held.mag`). A swap writes it on the floor gun (`Mag` attribute) and reads the new gun's; a stow keeps it
on the stowed record. The client loads a mag only when the gun uid changes: a fresh roll or crate gun is full, a floor
pickup or the gun you get back after a revive has what it had, whoever used it last.

**Downed sidearm (brief 3).** A downed player keeps shooting: the held gun is stowed server-side (id, rarity, level,
mag) and a Common `DownedPistolId` (M1911) at its own Armory level with a full
mag takes its place; spread × `DownedSpreadMult` (1.5), damage and in-run upgrades apply as normal. The held slot
shows the pistol with a red `SIDEARM` tag, the crosshair and ammo stay, ADS is off, reload works, the crawl animation
is unchanged. Any revive hands the stowed gun back exactly as it was (same uid, same mag); bleed-out drops it where
you fell as ground loot with the normal lifetime so a teammate can recover it. `DownedCanShoot = false` restores the
Round 9 no-fire rule.

**Run start (`IntroSec` 5.0, `RunStartBeats`).** The crew (players plus dummy crew up to `SquadSize`, 4.5 studs apart)
vanishes into the van; a chase cam follows the van from the yard through the door until it brakes beside the arena spawn
(dust ring, shake); the crew steps out in a line in join order facing the arena, heads recolor to the equipped mask
color (dummies use `MaskColors`) with a hands-to-face stand-in animation, each player plays their equipped SQUAD emote
(dummies a random pose from `Poses`; kept for the run end,
`PoseStagger` apart) while one slow pan runs from the crew member farthest from you to you and pushes in; then the
camera orbits 180° to behind you and hands over to the gameplay camera. Input locked, HUD down to the wave bar, not
skippable. The dummies vanish and the van drives off and is removed (`VanExitSec`) as control returns; the crate drops.

**Run end (`RunEndBeats` 0.6 / 1.4 / 4.0 / 7.0).** Arena cleared, everyone (spectators too) gets a fresh character in
the line, anchored, mask on, cash bag in hand, `KILLS · $CASH` tag over the head; dummy crew fill the line to
`SquadSize` with plausible rows under the best real player. One slow pan along the whole team with the poses and the
bill rain (`CashRainPerBanked` × Total Banked, capped at `CashRainMax`, over `CashRainSec`) inside it, then a cut to a
3/4 orbit (`MvpOrbitSec`) on the MVP (kills × `MvpKillWeight` + cash collected × `MvpCashWeight` + revives ×
`MvpReviveWeight`; ties to the earlier joiner; solo still gets the beat) with the rest of the crew hidden, the MVP's
equipped MVP emote (`MvpAnimationId` for dummies), a gold MVP stamp, name, the winning stat line, rays, shake and a bigger haptic. The summary
panel slides up over a dim: one GOLD BANKED count-up (the team's gold bags plus the GDD payout plus your side job
gold, all of it into the profile), `★ NEW PERSONAL BEST WAVE` / `★ NEW BEST BANKED` callouts, `WAVE N · TIME ·
★ stars`, the level card above the panel, one row per player (level and name, kills, jobs, cash
collected, downs, revives, MVP tag, NEW BEST), PLAY AGAIN and TO LOBBY with a `SummaryAutoLobbySec` countdown. TO
LOBBY returns the party to the hub spawn; PLAY AGAIN re-forms the party on the queue pad and starts the countdown.

## Verifying a change

```
stylua src tools
luau-lsp analyze --no-strict-dm-types src   # only SyntaxError lines matter without Roblox defs
rojo build -o build.rbxl
```

Nothing is tested in Studio by the tooling; playtests are manual.

### Brief 3 verify list

The brief 3 code was written and built (`stylua`, `luau-lsp`, `rojo build`) but not yet run in Studio. Turn on
`Enable Studio Access to API Services` first (otherwise profiles stay in memory and the rejoin line cannot pass).
Solo pass first, then a 2-player Local Server; anything that fails is a Config or one-file fix:

1. Fresh join: hub HUD only (no buy column, abilities, wave bar, health or ammo), Gold 10,000 bottom-left, `TOP WAVE 0
   ★` with the INITIATE circle over your head, no hat / face accessories, plain mask. Output shows `[GHS Profile]
   <name> loaded … (new)`. Backtick → `+1,000 Gold` bumps the row; `Reset profile` puts it back. If the floor labels
   by the stations or props read upside down, flip the `Yaw` on the label parts in `tools/genmap.luau`.
2. PLAY teleports you onto the pad and the Create Party card opens (you can still walk; walking off the pad closes
   it). X steps you out and closes it. CREATE with size 1
   starts at once; with size 2+ the billboard shows slots and `STARTING IN 15`, the compact card sits under PLAY.
   Local Server: a second player walking in joins (`JOINED THE PARTY (2/4)` toast on both HUDs and the billboard),
   walking out leaves, the creator leaving hands ownership over (★ on the card), everyone out resets the zone. Full
   party → immediate start.
3. Start: the party goes through the van sequence into the arena with the starter at Common; a player not in the
   party keeps the hub HUD and the billboard reads `MATCH IN PROGRESS` (walking on pushes them off). Buy a roll with
   one gun owned → it is always that gun; `Unlock all` then a roll / crate → only owned guns, floor tags show the
   leveled DMG / RATE.
4. Summary: GOLD EARNED = `20 + 25 + …` per cleared wave + 50 per side job (+5 per job per player); `★ NEW PERSONAL
   BEST` on a first run; TO LOBBY → hub Gold row shows the new balance and the tag shows the new top wave; PLAY AGAIN →
   the party lands on the pad with a fresh countdown. Rejoin (leave and re-enter Play) → Gold, top wave, owned items
   restored.
5. Customization: dock tile or station `F` opens the scene on that tab; you cannot move, the camera eases to the
   avatar on the left with its head near the top, no TOP WAVE tag, the Gold pill reads the balance, dragging on the
   avatar turns it. Weapons: unlock (toast `… unlocked and equipped!`, Gold −100, STARTER tag moves), `Not enough
   Gold!` when short (reset profile and spend down, or set `StartingGold` 0), UPGRADE raises LV and the green
   `» next` values, CUSTOMIZE hides the panel and dock and zooms on the gun, WRAP opens the swatch row, a wrap
   previews on the grip, BUY applies it, Back tiles climb out, and the grip keeps the color in the next run. Classes:
   the DOC pill → UNLOCK equips it, the in-run tiles read STIM SHOT / MED BAG / HEALING TURRET and each fires (see
   the Round 12 verify list); per-ability UPGRADE raises LV and the `» next` line; INITIATE's barricade HP / turret
   damage / stim heal grow in-run. Avatar: MASKS previews the mask on your head and `◆ 100` buys and wears it in the hub and
   the run; SQUAD and MVP tiles play the emote on the avatar when tapped, EQUIP sets it, and the next run start /
   run end line-up plays your SQUAD pose while the MVP beat plays your MVP flex. LEAVE, the X and Esc return to the
   hub view.
6. Sidearm: debug `Down me` holding a high-rarity rifle → the slot reads M1911 · COMMON · SIDEARM, you can fire and
   reload while crawling (no ADS), the crosshair stays; `Revive all` → the rifle is back with the ammo it had;
   `Down me` then GIVE UP → the rifle lies on the floor with a 30s tag.
7. Side job: let a job sit until half its window is gone → MARLOW's card comes back with the reminder line and
   collapses to the pill again with the timer intact. Hotwire: release a wire just beside the right socket → it
   still connects.
8. Mobile (device emulator, landscape): hub dock tiles 64px, PLAY 44px, SHOP / INVITE icons, the queue card at
   80%, the scene panel at 62% with 64px tiles and a 64px dock; every tap works with touch only.

### Brief 4 verify list

The brief 4 code was written and built (`stylua`, `luau-lsp`, `rojo build`) but not yet run in Studio. Regenerate
nothing: the map with the vault is committed (`src/map/Room.model.json`). Solo to wave 12 first, then a 2-player
Local Server through one boss; anything that fails is a Config or one-file fix:

1. Wave 1–3: Henchmen (grey) and from wave 2 Runners (pale, lean, fast, a wail as they close); from wave 3 Grenadiers
   (olive, a backpack): a shell arcs at you and a red circle grows under it, then a burst and a 3s fire patch that
   hurts you standing in it. Every wave end prints `[GHS Wave] Wave N composition (bracket B): …` and `[GHS Heat] wave
   N clear 42.1s par 58.0s heat +0.5 → 0.5 (fast)`. The stars start empty and `+1 FAST CLEAR` / `+0.5 PAR` floats beside
   them; getting downed adds a `−0.5 DOWNED` float at that wave's end; a side job `+0.5 JOB`. No HEAT UP toast.
2. Wave 4+: Shooters (dark blue, a gun) stop at range and fire orange tracers with a flash, roughly half land (the rest
   crack past your ear); Boomers (orange, a belly) run at your turret or barricade, stop, beep rising and swell, then
   burst (orange ring; a turret in it takes 4×); killing one mid-run still bursts smaller. Wave 5+: a Heavy (black,
   wide, slow) shrugs off flinch, stomps a barricade in its path, knocks you back on a hit, loses a chest plate at 66%
   and the shoulder plate at 33% (each with a crunch and chips). Wave 6+: Marksmen (dark red, a long gun) paint a red
   laser on you for 1.5s; step out of the line and the shot misses, stay and it hits for 15.
3. Hits: a white pop on the enemy, no shove, no feet stop; kills ragdoll as before but 8 at most and fade after 2s.
   Cash per kill differs by archetype (15 Henchman … 60 Heavy) and grows with the stars. `Set heat` 4 from the debug
   panel: the next wave's composition line shows the bracket one row down, spawns come faster, and ELITE-tagged glowing
   enemies (×2.5 HP, ×3 cash, bigger) appear.
4. Bags: at each wave start `BAGS DROPPED · 2 CASH · 1 GOLD` and green / gold columns with `CASH BAG` / `GOLD BAG`
   markers (a `$` / `◆` badge far away), never next to you. Hold F on a cash bag: it pops, everyone's cash row jumps,
   `<NAME> GRABBED $187`; a gold bag: `◆ 27 BANKED` ticks bottom-left, `<NAME> BANKED ◆ 27`. Bags left alone stay
   through the next waves; with 6 up no more drop at wave start (`Cash bag` from the debug panel still does).
5. Vault: from wave 3 the side job can be CRACK THE VAULT: MARLOW's line, the vault door frame on the north wall turns
   blue, the marker points at it; F at the door opens the Safe dial (tier from the wave bracket); fail → F again; done →
   `WE'RE IN`, the door slides up, lights on, 10 bags on the floor inside, `VAULT OPEN`, the top-right pill reads
   `VAULT · 0:59`. With 10s left: alarm, red strobe, MARLOW's `GAS` card, the pill red. At 0: green fog, standing
   inside tints the screen green and hurts 8/s, stepping out stops it at once, the bags inside fizzle; the door closes
   only after you leave and the frame goes grey. The job never draws again that run. `Open vault` / `Gas vault` on the
   debug panel skip the dial / the timer.
6. Wave 10: after the countdown the HUD drops, MARLOW's `Heavy response inbound. Big one.` card, a low shot of the far
   wall; the wall blows and TITAN (huge, dark, a minigun) walks in with stomps; the camera pushes in on the gun with the
   `TITAN · HEAVY RESPONSE` card; the camera snaps back, the red bar with three pips slides in under the wave bar, a
   red outline on TITAN reads through pillars with `TITAN · 70m`, the wave starts with a few regular enemies. You cannot
   move or shoot during the 4s and nothing hurts you.
7. TITAN: walks at you, a hit for 35 throws you back; your barricade in its path just breaks. Sweep: barrels whine with
   a red cone on the floor, then a wide beam swings across; standing in it drains 40/s. Charge: a red line to you, then a
   run at 3×; standing on the line costs 50 and a throw; a pillar or wall stops it with a crunch and it stands still 1.5s
   taking 1.5×. Volley: four red circles on the crew, then four bursts with fire. At 66% the chest and back plates fly
   off and the second pip goes dark; at 33% the shoulder pads go and four Henchmen arrive at the nearest marker every
   12s. Kill: slow-mo, `TITAN DOWN`, `+$600` on everyone, six bags round the body, a crate on the body with one
   Legendary, `+1 BOSS` beside the stars; the wave end logs the boss wave with a par that includes `BossParBonusSec`.
8. Summary: `GOLD BANKED ◆ N` counts up (bags plus the payout plus jobs, one number), `WAVE N · 12:34 · ★ 2.5`
   with the time survived, then the level card drops in above the panel (emblem, `LV 1 ROOKIE`, `+N XP` counting
   in green on the right, the bar reading `350 / 400 XP`); cross a level (use `+500 XP` before a run, or a long run)
   and it flashes, reads `LV 2`, pops `LEVEL 2 · +100 GOLD` above the card and keeps filling; `FIRST HEIST OF THE
   DAY ×2` under the gain on the first run of the day (then `Reset daily` to see it again). Rows read `LV 2 NAME`.
   Back in the hub the same card sits above the Gold pill bottom-left with the new level and bar, the tag reads
   `LV 2 · TOP WAVE 12 ★`, the Gold row includes the banked total and the level reward, and the party card lists
   `LV 2 NAME`. Rejoin: level, XP and the daily flag hold (API access on). The card never shows in a run.
9. Scoreboard: hold Tab in a run: `WAVE 5 · TIME 3:12 · ★★ · ◆ BANKED 54 · $ CASH 2,340`, your row highlighted with
   level, class circle, green dot, kills, cash, bags, jobs, downs, revives, MVP score, updating every second; release
   closes it; shooting keeps working while it is up. Mobile: tap the wave bar (the `≡` chip), tap outside to close.
   Two players: rows in MVP order, a downed teammate's dot goes red, a bled-out one grey.
10. Mobile (device emulator, landscape): the boss bar and the scoreboard fit the width, the red telegraph circles read
    at phone size, `DBG` chip → the spawn rows work with touch.
11. Debug `Stats` prints the minigame averages and then `[GHS Heat] clear / par this run:` with one line per wave and
    the mean ratio.

### Brief 5 verify list

Written and built (`stylua`, `luau-lsp`, `rojo build`), not yet run in Studio. Solo through one boss first, then a
2-player Local Server with a pause and a dealer visit:

1. Crates: the left column is NEW UPGRADE only and 1 does nothing. The intro crate lands closed with `2 ROLLS LEFT`
   (solo; party size + `CrateRollsExtra`) and a seconds countdown over it. F → the tag hides and a card above the crate
   cycles six gun icons with rarity frames (0.6s each, the last two slower), ticks rising in pitch from the crate; it
   lands with a punch (rays from Epic, the sting on a Legendary), holds, drops into the crate and the gun arcs out to a
   free spot about 6 studs away with its beam and floor tag. A second player sees the same reel and can take the gun.
   The prompt is gone while a roll plays; the tag reads `1 ROLL LEFT`; the crate closes after its last roll or 45s
   (`CrateLifetimeSec`), and guns on the floor keep their own 30s timers. Boss crate: its first roll is a Legendary.
   Force rarity from the debug panel applies to your next crate roll.
2. Upgrades: pick-3 cards now include INCENDIARY / CRYO / CONCUSSIVE (orange `Element` on the debug panel forces
   one), ABILITY COOLDOWN, ABILITY POWER and CASH GAIN (no Greed). Take INCENDIARY: the tracker tile reads `15%`;
   roughly one shot in seven sets a target orange with embers and it burns for 3s (small numbers, kill cash to you).
   CRYO: tinted blue and slower with a shard crackle; three procs inside 2s freeze it ice-blue for 1s (no walking, no
   swings). CONCUSSIVE: a white ring and the enemy slides back about 8 studs (a Heavy or TITAN half that; TITAN keeps
   attacking). Take one again: the chance on the tile goes up. ABILITY COOLDOWN shows `-8%` on its tile and the ability
   sweeps get shorter; ABILITY POWER raises turret / barricade HP and heals; CASH GAIN raises kill, bag and job cash.
   Tradeoff cards are rarer and never on an element card; a malus never lands on an element or CASH GAIN. Kill cash
   grows 10% a wave (`CashWaveMult`); every wave end prints `[GHS Income] wave N cash earned X upgrades bought Y
   (name)` and debug `Stats` adds the run's upgrades per player per wave.
3. Revive (2 players; `Down me` on one): the reviver holding F sees a bar under the crosshair, `REVIVING NAME 2.4s`,
   filling over 3s with a tick every 0.5s; letting go turns it red and it snaps back; finishing flashes green with
   `REVIVED`. The downed player's red bleed bar gains a green fill matching it and reads `NAME IS REVIVING YOU`; the
   marker over their head shows the same fill to everyone; on the stand-up their bar pulses green, the camera eases
   up from the floor and `REVIVED BY NAME` toasts as before. Callouts: getting downed sends your teammates (never you) a
   red card in the top-right with your Roblox headshot, your name and `I'M DOWN, HELP!` (or another line, never the
   same twice in a row) for 2.5s; revived → `Thanks, I owe you.` / `Back in it.`; bled out → `I'm out. Finish the job.`;
   REVIVE EVERYBODY → a gold `NAME brought everyone back.` to everyone. A callout waits while MARLOW's card is up and
   during the boss cutscene.
4. Classes: the Classes tab reads INITIATE → ENGINEER (orange, a 🔧) → DOC → SHARPSHOOTER → TORCH, each ◆ 100.
   INITIATE: Q Frag (thrown to the cursor, blinks red for 1s, then a 9-stud blast for 120 that throws bodies out),
   E Adrenaline, Z Claymore. ENGINEER: Q Turret, E Barricade, Z Overclock (every turret / healing turret / flame turret
   on the floor glows amber and fires 1.5× for 8s, a med bag heals faster, every barricade gets a 150 shield that soaks
   hits first and goes with the glow; the Z tile counts the 8s down). SHARPSHOOTER: Q Eagle Vision (`◉`: a red ring sweeps
   out 60 studs and every enemy in it glows red through walls for 6s and takes +25% from bullets, turrets, fire and
   blasts), E Dead Eye, Z Flashbang. A profile that leveled the SHARPSHOOTER claymore has that level on INITIATE's Z;
   Eagle Vision starts at LV 0. UPGRADE on the tab raises Frag DMG, Overclock RATE / SHIELD and Eagle Vision BONUS / RADIUS.
5. Mastery: every owned weapon tile and owned class pill in the customization scene carries a thin green bar with
   three diamond pips; hovering lists the tiers (`✔ I GUNMETAL WRAP · 100 kills`, `· II TRIAGE · Your heals revive
   downed allies`). In a run, debug `+100 mastery` (or 100 kills with one gun): the moment a tier is crossed a card
   drops in under the wave bar with a spinning diamond emblem, rays and the sting: `WEAPON MASTERY · AK-47 ·
   MASTERY I · GUNMETAL WRAP UNLOCKED` (gun) or `CLASS MASTERY · ENGINEER · MASTERY I · REINFORCED` (class); the
   class passive is on from that second (placeables put down after it have +20% HP, etc.). Several tier-ups queue.
   Summary: `MASTERY   AK-47 +31 · ENGINEER +12` between the level card and the panel, and after the XP fill each
   tier crossed this run pops above the card. CUSTOMIZE → WRAP shows Gunmetal / Gold / Black-Red with `MASTERY I`
   / `II` / `III` labels; they apply only on the gun that earned them and can never be bought. Passives to spot-check
   (set a high tier with the debug button before a run): INITIATE Adrenaline heals 25%, Frag and Claymore show `x2`
   and hold two charges, kills during Adrenaline stretch its timer; ENGINEER placeables mend when nothing is near,
   Overclock speeds every crew gun; DOC med bag is wider, a downed teammate standing in it gets up on their own
   (`MED BAG IS REVIVING YOU`), allies inside hit harder; SHARPSHOOTER headshots hit harder, snipers / pistols reload
   faster, headshots during Dead Eye refill the mag; TORCH fire ticks twice as fast, runs start with INCENDIARY 15%,
   burning kills shave the Molotov cooldown.
6. Vault (wave 5 forces it): with MARLOW's call and the pill, a big amber `VAULT JOB` stamps the center for 1.5s;
   the vault door pulses amber with a glow until the dial is cracked; the job beacon is twice the normal size, amber,
   with a spinning diamond on top, and keeps its full name / timer / distance box at any range (no badge); a strip of
   amber chevrons runs along the floor from where the crew stood to the door, lighting in a wave toward it, for 10s.
   Hold Tab: the header ends in amber `· VAULT OPEN` until the vault seals (or the job fails).
7. Dealer (clear wave 10's TITAN, or debug `Open dealer` in an intermission): the wave bar reads DEALER, MARLOW's
   `Dealer's set up by the van…` card, a stall rises out of the floor south of the center (table, crates, a lamp, the
   DEALER rig idling behind it) and the top-center card reads `DEALER · 1:30` with TELEPORT TO DEALER [T] (once; it
   then reads TELEPORT USED), SKIP 0/1 [V] and VOTE TO PAUSE [P]. Eight upright cards stand on the table (stat initials
   in the tier color, a green price); the ammo crate, medkit and dice cup carry ARMS DROP $800, HEAL ALL $300 and
   REROLL $150 tags. Walk up: the nearest one opens a panel (`HONED · UNCOMMON · DAMAGE`, `DAMAGE +15% → +37%`,
   price, F BUY). F: the upgrade lands at once (toast, tracker), the card disappears and the other prices rise; short
   of cash the panel shakes and the price goes red. ARMS DROP drops a crate beside the stall; HEAL ALL fills every
   member; REROLL deals eight new cards and the next reroll costs $300. Nothing spawns; at 0:00 or once everyone has
   voted SKIP the stall sinks away and the normal intermission and next wave follow. A second player sees their own
   eight cards on the same table.
8. Pause: P (or the dealer card, or the scoreboard's VOTE PAUSE): solo pauses at once; with two players the first vote
   toasts `NAME VOTED TO PAUSE · 1/2` and the second pauses. Everything stops: enemies stand, nobody takes damage, you
   cannot move or fire, the bleed bar, floor gun and crate countdowns, the job pill, the vault pill, the dealer timer,
   cooldown sweeps and turret lifetimes all hold. `PAUSED` and the names over a dim with RESUME (anyone); left alone,
   `RESUMING IN 10` counts down from 2:50 and it resumes at 3:00. After it the wave's par and TIME on the scoreboard
   do not include the pause. A second pause is refused for 5 waves (the dealer button reads `PAUSE IN N WAVES`).
   Debug `Pause / resume` skips the vote.
9. Debug row (brief 5): `Element` (orange, next pick-3 holds an element), `+100 mastery`, `Open dealer`, `Pause /
   resume`. Mobile (device emulator, landscape): the crate reel card and its `N ROLLS LEFT` tag read from across the
   arena, the revive bar and its label are thumb-readable under the crosshair, the dealer card fits the width with three
   tappable buttons, the shop panel's BUY works by touch, and RESUME on the pause overlay is a big target. Mastery cards
   and ally callouts fit at phone size.
10. Round 15b (feedback on the brief 5 build; where it differs from the items above, this wins): the upgrade tile is
    key 1. A crate reads `GUN CRATE`; one F plays every roll back to back on the old sliding reel above the crate, each
    gun lands on the floor beside it (never on the lid; it cannot be grabbed mid-arc). Frag goes off on landing.
    Elements apply on every shot: INCENDIARY burns, CRYO slows (ten hits in 2s freeze), CONCUSSIVE nudges back ~1.5
    studs; a second take shows `130%`+ on the tile and burns harder and faster, slows and shoves more. Placeables never
    block you (enemies still stop at them). Ability tiles: a used charge starts the cooldown at once and the sweep shows
    (lighter while a charge is left); during Dead Eye / Overclock / Eagle Vision the cooldown drains under the gold
    timer; a BACKDRAFT / OVERDRIVE trim pops `-0.1s` / `-0.2s` on the tile. Wave bar: VOTES sits under AUTO SKIP on the
    left, PAUSE n/m on the right (P). Dealer: three tables in a half circle round the DEALER, cards are UI only and on
    top, TELEPORT works every time, the card has TELEPORT and SKIP. Vault: the beacon is the normal size again (amber),
    the chevrons stay. Classes tab: the detail column shows MASTERY with the waves to the next tier, a bar and three
    tier cards (earned gold, next green); ENGINEER is a plain `E`; SHARPSHOOTER's Q is Eagle Vision (`EGV`). Weapons
    tab: owned tiles read `M1911  LV 1` in the top bar over the mastery bar (STARTER at the bottom), the detail shows
    the mode · rarity · level beside the name and a MASTERY bar under it, and the three mastery wraps carry a MASTERY tag.

## Layout

See `default.project.json`. `src/shared` → ReplicatedStorage.Shared, `src/server` → ServerScriptService.Server,
`src/client` → StarterPlayerScripts.Client, `src/assets` → ReplicatedStorage.Assets, `src/map` → Workspace.Room.

Server modules: World (run state, the party, `fireRun`, payout accumulators, heat effects, the run clock, the boss
view and the roster), Room (map refs including `Room.vault`), Stats, Profiles (DataStore), PlayerState (per-player run
state + profile-derived held / mask / wrap / class), Enemy (base) with `Enemies/` (Rig, Hazards, Ranged, Melee, Shooter,
Marksman, Boomer, Grenadier, Heavy), Spawner (brackets, proximity markers, cap, elites), Heat (pace meter), Bags,
VaultJob, Boss with `Bosses/Titan`, Progression (XP, level, rewards), Roster (scoreboard rows), Combat, Economy,
UpgradeShop (`generate(state, wave, count)`, `applyCard`), WeaponRoll, BigCrate (`drop(at, { legendary })`, rolls),
Elements (element procs and statuses), Mastery (XP, tiers, kill passives), Dealer (the break, stall, stock), Pause
(the freeze and its hooks), CrewCall (the vault kind), Abilities, SkipVote,
Hub (yard dressing, stations, tier pad, resets, the LV · TOP WAVE tag), Queue (zones, Create Match, party, countdown,
PLAY AGAIN re-form), Meta (unlock / upgrade / equip actions), Minigames (sessions, log, stats, a tier override), Downed
(down / revive / bleed-out / game over / sidearm), RunStart, RunEnd (payout, XP award, summary), Squad (dummy crew for
the sequences), Debug, Log; `GameLoop.server.lua` is the entry. All cash, Gold, HP, spawns, rolls, loot, minigame
results, bags, XP and revives are server-authoritative; every remote is created in `src/shared/Remotes.lua`. Shared
data: Config, Prices, Weapons (with `saleType` and the level math), Enemies (roster rows, scaling, brackets), BagSpots,
LevelRewards, Classes, AbilityGrowth, Masks, Wraps, Rarity, Upgrades, Types, Remotes, Signal, CrewCall/Lines, CrateReel
(reel timing), Callouts (ally lines), MasteryCopy (mastery copy and tier math).

Client: ClientState (sync + juice bus + downed / camera mode flags + `inHub`), HUD components under `src/client/HUD`
(with `HUD.setMode` for hub / meta / downed / spectate / cinematic / boss and `HubHUD` for the hub layout; `BossBar`
under the wave bar; `Currency` with the Banked row), QueueUI (Create Match card, compact party card), MetaScene with
`src/client/Meta/` (MetaUI with the mastery bar, WeaponsTab, ClassesTab, AvatarTab), UpgradeOverlay, CrateReelUI (crate
tags and the reel), StatusFx (element looks, Eagle Vision marks), MasteryUI (the tier-up card), DealerUI (dealer card, stands,
shop panels), PauseUI (the overlay), GroundLoot, CrewCallUI (job cards, the vault pill, MARLOW's line cards, ally
callouts), Markers (beacon, bag and vault billboards, the vault chevrons), Minigames (Frame + one module
per game), DownedUI (bleed bar hooks, revive hold, downed markers), PlayerTags (busy tags over teammates), Spectate,
RunStartUI, RunEndUI (sequence cameras, poses, MVP stamp, summary with the XP row), BossCutscene, Scoreboard,
DebugPanel, Juice (rarity tiers), Camera, Gun, Main.

## Changelog (playtest rounds)

- **Round 1** — unstick enemies, no player collision, bigger UI, hold to fire, Ctrl camera lock, more starting cash.
- **Round 2** — top-center reel with gun drop-in, hackable side jobs with crate reward, 30s floor timers, bigger upgrade magnitudes, gun-only stats.
- **Round 3** — side-job pill top-right, arms drop as a transient toast, slot roll on upgrade cards, rarity-scaled juice.
- **Round 4** — six new upgrades (Accuracy, Pierce, Ricochet, Splash, Multishot, Lifesteal), live heat stars, crew-call card slide/collapse, crates close with their guns.
- **Round 5** — abilities (turret, barricade, stim), whole-card spin, 2s reel, reload ring, DPS display.
- **Round 6 (2 Nov)** — crate no longer collides, higher rarity odds, distinct crate weapons, icon reel on cards with text on land, DPS only, quieter death/destruction sounds, juice pass (affordable pop, low ammo and HP pulses, spawn puffs, pickup rings, wave-start flash), 0.5s swap cooldown.
- **Round 7 (3 Nov)** — scroll / pinch zoom with first person at the inner limit, RMB / mobile-toggle ADS (FOV, spread, crosshair, sensitivity), melee stub removed from the HUD.
- **Round 7b (3 Nov, feedback pass)** — real skip vote (V / pill, toasts, min intermission), AUTO SKIP rolls waves into each other 10s in, center WAVE N / WAVE CLEAR banners and 3-2-1 countdown ticks, N LEFT enemy counter, world marker over the side job beacon (timer, distance), ARMS DROP count / closed toasts, crew call typewriter with portrait bob, beacon result ring, upgrade toast with running total and tradeoff malus, DPS delta float on the weapon slot, floor gun tags show ▲ / ▼ vs the held gun, buy tile breathes while rolling, pick-3 panel drop-in, multi-kill counter that climbs every kill with words at tier counts (x5 NICE → x30 GODLIKE), stim also speeds reloads, upgrade cards lose the rarity pill and TAKE hint.
- **Round 8 (3 Nov)** — capture point side job (stand in the circle, fill disc + marker bar + pill bar, 10% ticks), job kind rolled 50/50, unlocked cursor turns the character, aims the gun and carries the crosshair while the camera holds, damage falloff by archetype (`FalloffByArchetype`: SMG / shotgun close, rifle mid, pistol short, sniper never), weapon DPS pass (common paper DPS 128–180 across archetypes, rifles down from 220–234) and rarity multipliers raised to 1 / 1.3 / 1.7 / 2.3 / 3.0 so a legendary of anything beats an epic of anything, beacon marker shrinks to a badge past `MarkerCompactDistance`, floor tags / weapon slot / reel show DMG per shot ("33x8" for pellets) and RATE as two rows, each with its own ▲ / ▼ against the held gun instead of one DPS number, tube-fed shell-by-shell reload with fire-to-cancel (SPAS-12).

- **Round 9 (3 Nov, brief 2)** — staging yard south of the arena with the run start door, van, six minigame props and
  a tier pad; `Staging` state (no spawns, `STAGING` bar, `StagingCash`); run loop Staging → run → RUN OVER → run end →
  summary → yard. Six minigames behind one shared frame (Lockpick, Hotwire, Keypad, Arm charges, Safe dial, Frequency
  jam), server-owned results with `MinigameMinSec`, one log line per close and session stats. Downed (crawl, bleed bar,
  SELF-REVIVE, markers), hold-F revive with rings, bleed-out spectate, REVIVE EVERYBODY, run over when nobody is standing
  or bleeding (freeze + fade, slow-mo tint, RUN OVER stamp). Run start drive-in with masks, poses and the camera orbit;
  run end line-up with bags and head tags, cash rain, MVP stamp and orbit, summary panel with count-ups, rows and
  PLAY AGAIN / TO LOBBY (30s auto). Debug: start run, skip to run end, down me / all, revive all, open any minigame,
  tier, stats; `DBG` chip on mobile. Characters are loaded by hand. Config gains the Staging, Minigames, Downed, Run
  start and Run end groups.

- **Round 9b (3 Nov, feedback)** — cursor unlocked: ADS only pulls in a little (`AdsFovMultUnlocked`,
  `AdsZoomMultUnlocked`) and holding RMB drags the camera round like default Roblox; Lockpick needs 3 / 4 / 5 points by
  tier (`LockpickTargetByTier`); the capture marker no longer pops on every percent tick, only on stepping in or out;
  bleed-out is 15s with GIVE UP and SELF-REVIVE side by side above the bar; the RUN OVER red screen runs its course
  (`RunOverHoldSec`) before the run end cutscene; the summary leads with GOLD EARNED (cash stays in the rows, no
  self-revive column); the van is put away in the yard and only appears in the start animation (drives off and is
  removed over `VanExitSec`); the start and end line-ups fill up to `SquadSize` (4) with dummy crew (default R15 rigs
  with masks, poses, bags, tags and plausible summary rows under the best real player).

- **Round 9c (3 Nov, feedback)** — a minigame panel closes as a cancel when you walk past `MinigameCloseDistance`
  from its prop; the summary's POSE column is now JOBS (side jobs + minigames completed this run, both tracked per
  player); the run start push-in goes from the team shot to a tight shot of the local player, then the orbit widens
  from there into the gameplay camera; the run end is longer (`RunEndBeats` 0.6 / 1.4 / 4.0 / 7.0): one slow pan along
  the whole team for 4s with poses and the cash rain inside it, then a 3s MVP beat (`MvpOrbitSec` 2.5).

- **Round 10 (3 Nov, feedback)** — the six minigames are side job kinds now (`SideJobKindWeights`, equal odds with
  hack and capture): the beacon carries an OPEN prompt, a validated done finishes the job, fails can retry until the
  timer. Side jobs clear on every client when the run ends (`CallCleared`). The run-over screen is a 5s window
  (`RunOverSlowSec + RunOverHoldSec`) where REVIVE EVERYBODY really saves the run: the crew stands up, enemies clear
  and the same wave restarts (SECOND CHANCE banner); presses after the window are ignored, and the spectate button
  counts the window down. Summary columns read kills / jobs / cash / downs / revives. ARMS DROP CLOSED and N LEFT
  toasts are gone. Reload is a two-click sound. Seven new guns: Desert Eagle, P90, SCAR-H, Sawed-Off, Barrett M82 and
  the first LMGs, M249 and RPK (new `LMG` falloff). Camera pass on both sequences: the run start door shot sits
  higher, then one slow pan from the crew member farthest from you to you that pushes in as it lands and orbits into
  the gameplay camera; the run end pan and MVP shots sit at head height with the whole body in frame, the rest of the
  crew is hidden for the MVP beat and the MVP plays `MvpAnimationId` instead of their pose.

- **Round 10b (3 Nov, feedback)** — SCAR-H is a 3-round burst (`burst` / `burstDelay` on the weapon; RATE and DPS
  show the delivered rate, tags and the slot say `3-BURST`); Sawed-Off reloads in 0.6s; snipers carry built-in pierce
  by rarity (`pierceByRarity` 1 / 1 / 2 / 3 / 4, shown as `PIERCE n`); side jobs pay `SideJobGold` per player on top
  of the cash (card, pill, toast and the HUD gold row show it; the summary headline is your own gold: banked share
  plus job gold); PLAY AGAIN starts the next run from the yard by itself; the run start opens on a chase cam that
  follows the van through the door; the keypad takes input the moment you type (hides the code early); the crew line
  stands 4.5 studs apart; both floors sit at `FloorTop` 0.5.

- **Round 10c (3 Nov, feedback)** — pierce and burst are no longer spelled out in weapon names; a finished minigame
  hands the gun and camera back the same frame and slides the panel off over `MinigameExitSec`; side jobs every 2 waves.
- **Round 10d (3 Nov, feedback)** — F is the interact key on side job beacons too (was E); floor tags compare DMG and
  RATE at display precision so an identical gun reads even, not ▲; with `StragglerHighlightCount` (5) or fewer enemies
  left the survivors glow red through walls (client Highlights). Sawed-Off fires both barrels back to back (rate 2.8,
  dmg 17; the 2-shell mag is the limiter). Downed or bled-out players cannot interact: every ProximityPrompt hides on
  their client and the server refuses minigames, hacks and START RUN from them.

- **Round 11 (3 Nov, brief 3)** — the yard is the hub (planning table, queue pad with gate and billboard, three
  stations on the west wall, props and tier pad moved east, no START RUN marker); `Staging` → `Hub`, state `Hub`.
  Profiles over DataStore (`Profiles.lua`, `GHS_Profiles_v1`, retry / backoff / debounce / autosave / pending payout /
  in-memory fallback), `Prices.lua`, accessories stripped on join, masks (`Masks.lua`) worn in the hub and the run.
  Hub HUD (`HubHUD.lua`: PLAY, SHOP placeholder, Gold row + INVITE, dock, BOOSTS, queue card slot, TOP WAVE billboard).
  Queue zone and Create Match (`Queue.lua` / `QueueUI.lua`): party, countdown, join / leave / ownership, MATCH IN
  PROGRESS, PLAY AGAIN re-forms the party. The party is the run's player set (`World.party`, `World.fireRun`,
  `World.runAudience`): run events, line-ups, skip votes, crate sizes and enemy targeting are party-scoped; late joiners
  land in the hub. GDD payout into the profile with top wave and lifetime stats, `★ NEW PERSONAL BEST`. Customization
  scene (`MetaScene.lua`, `Meta/`): fixed camera, dock with LEAVE, Gold and SHOP chrome, live preview, toasts;
  Weapons tab (grid, detail, unlock / upgrade / equip starter, wraps sub-panel), Classes tab (carousel, ability rows,
  unlock / equip / upgrade; in-run tiles follow the class; nine stubs), Avatar tab (masks). Armory level math in
  `Weapons.atLevel` / `Stats` applied to the starter, rolls, crates and floor tags; owned-only roll and crate pools;
  `AbilityGrowth` on barricade HP, turret damage / HP and stim heal / fire rate / reload. Downed sidearm (stow, M1911
  at Common, spread ×1.5, SIDEARM tag, restore on revive, drop on bleed-out). Debug: force queue start, +1,000 Gold,
  unlock all, reset profile. Config gains the Hub, Queue, Meta and Payout groups; `StagingCash` and `GoldPerBanked`
  are gone. Built and linted, not yet run in Studio (see the Brief 3 verify list).
- **Round 11b–11f (4 Nov, feedback on brief 3)** — menus to the reference boards (right panel with header bar,
  pills, tiles 4 per row, detail column; Create Party card; icon dock; boost chips with a countdown); movement
  hard-locked in the scene; combat hotkeys and buys off in the hub; default-owned gun per archetype and showcase
  Crate / Event guns; customize = center zoom with a category strip and the wraps row (Back tile); class pills;
  unlocks auto-equip; Hotwire drops snap to the nearest socket; scene camera driven per frame, offset to the
  character's left, closer (`MetaCameraDistance` 5.5) with drag-to-rotate and the TOP WAVE tag hidden; bigger hub
  dock tiles; the planning table is gone; crew call cards hold 4.5s and a half-time reminder card returns while a
  job is open; Avatar tab gains SQUAD and MVP emote categories (`Emotes.lua`) that the line-ups and the MVP beat use.
- **Round 11g–11i (4 Nov, feedback)** — scene camera pulled back to 7.5 and aimed `MetaCameraAim` below the
  character's center so the head sits near the top of the frame; the scene's dock and gold pill grew to fill the
  corner and the gold reads on open; the TOP WAVE tag stays hidden every frame in the scene; `Prices.emote` (its
  absence had broken the SQUAD / MVP grids after the owned tiles); the dock and gold pill hide on both customize
  layers so nothing overlaps the strip.
- **Round 12 (4 Nov, phase 2: the nine class abilities)** — DOC, SHARPSHOOTER and TORCH kits are live; the
  `STUB · PHASE 2` toast, greyed tiles and the `live` flag are gone. `Abilities.lua` rebuilt around one structure
  registry (attackable or not, per-kind ticks), ground fields on a `FieldTickSec` clock and an arcing throw. Enemies
  gain stun (`Enemy.stun`: stand still, no swings, white head) and slow (`Enemy.slow`: walk speed multiplier, the
  stronger wins). The stim-only buff is a general self buff (`buffId` / `buffUntil`, `PlayerState.buffFor`) and
  `Stats.Buffs` carries a damage multiplier for Dead Eye. Cooldowns moved into one `AbilityCooldown` table (the three
  `*Cooldown` keys are gone); every Classes tab number now comes from Config. New juice: `AbilityBeam` (heal /
  flame), `Blast` (claymore / flashbang / fire landing) and `Heal` (small green float); `StructurePlaced` takes a
  color and radius. Built and linted, not yet run in Studio.

  **Round 12 verify list.** Unlock DOC, start a run: Q heals 40 and the tile counts 6s down gold; E drops a green
  circle with a bag, standing in it while hurt floats `+8` a second; Z plants a green turret that beams the hurt
  teammate (solo: yourself when under full HP) with `+3` floats, enemies attack it. SHARPSHOOTER: Q plants a box
  with a red light that detonates 1s+ after an enemy walks within 5 studs (red ring, big numbers, kill cash); E
  shows bigger damage numbers and faster movement for 8s; Z throws a grey ball 12 studs ahead that bursts white and
  freezes everything within 12 studs for 3s (white heads, no swings). TORCH: Q throws a burning ball that leaves a
  fire circle for 8s (enemies inside slow and take `15` ticks); E plants a red turret with a pilot flame that streams
  orange at anything within 14 studs; Z plants a drum enemies attack, and when they break it the floor burns for 6s
  (an expired drum does not burn). Per-ability UPGRADE on the Classes tab raises the number used in-run.
- **Round 12b (4 Nov, feedback on phase 2)** — the placeables crashed on `Enum.Surface` (now `Enum.SurfaceType`),
  which is why no DOC / SHARPSHOOTER / TORCH placeable or throw fired; INITIATE's stim is **Adrenaline** (fire rate,
  reload, move; no heal; id `stim`, Config `Adrenaline*`), DOC's stim shot keeps the heal; Dead Eye adds
  `DeadEyePierce` bullet pierce (`Stats.Buffs.pierceAdd`). Weapons carry an Armory `rarity` (`Weapons.ArmoryRarity`)
  and masks a `rarity`: tiles, wells and the detail line are colored by rarity, not archetype or mask color (the
  mask's own color moves to the icon). Showcase guns carry placeholder base stats so a locked card reads like a
  real one. Masks show `type` (Head / Face, the UGC accessory category) instead of shape; the emote detail drops
  the Plays / Hold rows. A fifth greyed FUTURE pill ends the class row (toasts `MORE CLASSES COMING`). Walking off
  the pad with the Create Party card open now closes it (the server reset without sending the creator the cleared
  view).
- **Round 12c (4 Nov, feedback)** — the grids keep their scroll offset across refreshes (selecting a tile no longer
  jumps to the top; `MetaUI.columns` remembers it per tab / category). Fractional pierce is real in `Combat`: the
  whole part is full-damage enemies, the fraction is one more enemy at that share of the damage (Dead Eye LV 1 =
  2.2 → two full, one at 20%), so the `» next` on the Classes tab means what it says. Emotes carry a rarity
  (`Emotes.Rarity`): rarity-colored tiles and well, the slot color on the icon, a RARITY row in the detail. Buying
  or equipping an emote re-renders the tab at once (the handlers never marked the state dirty, and the scene's
  profile stamp ignored emotes, so even the 2s resend did not redraw it).
- **Round 13 (4 Nov, multiplayer feedback)** — a revive hold freezes the target's bleed timer (`Downed` pushes
  `bleedEndsAt` forward each frame of the hold and sends it with `ReviveProgress`; the bleed bar and the marker follow,
  the marker's seconds go green; `RevivePausesBleed`). Teammates' shots are visible and audible: `Combat` returns where
  each bullet stopped and sends `RemoteShot` to everyone else in the run; `WorldFx` draws the tracer from that gun's
  muzzle and plays the shot sound at the gun in 3D (`RemoteTracers`, `RemoteShotVolume`, `RemoteShotRange`; the
  per-archetype pitch moved to `ShotPitchByArchetype`). Busy tags over teammates (`PlayerTags.lua`): LOCKPICK / … while
  a minigame is open, HACKING on the hack hold, CAPTURING inside the circle (`PlayerBusy` from `Minigames` and
  `CrewCall`, copy in `Lines.busyTag`). Skip votes need everyone (`SkipVoteFraction` 0.5 → 1; AUTO SKIP needs everyone
  too). Mags follow the gun instead of the client's per-uid memory: shots and reloads report the count, the server keeps
  it on the held record, writes it on a dropped floor gun and reads it back on pickup, so a swapped-away gun comes back
  with what it had and a fresh gun is always full (the old client memory survived run resets, where uids restart, so a
  new gun could inherit a stale count). Enemies ragdoll on a player kill (server physics, `Corpse` collision group, head
  pop on headshot, capped at `RagdollMaxActive`, fade and remove after `RagdollSec`), flinch and get shoved on every hit
  (`EnemyHitKnockback`, `EnemyHitFlinchSec`, `EnemyFlinchCooldownSec`), impact sparks on hits and a red burst on kills
  (`HitSparks`, `KillSparks`). Built without a Studio playtest.

  **Round 13 verify list.** Two clients (or one plus `Down me` from the debug panel on a second Studio player): down
  one, hold F on them: the bleed seconds on their marker and bar stop and turn green, let go and they tick again from
  where they were. From the second client, watch the first fire: a tracer leaves their gun on every shot and the shot
  sound comes from where they stand, quieter far away; no numbers over their targets. Open a yard prop or a minigame
  job on one client: the other sees `LOCKPICK` (etc.) over their head until the panel closes; hold the hack prompt:
  `HACKING`; stand in a capture circle: `CAPTURING`. Intermission with two players: VOTES reads 0/2 and one vote does
  not skip. Fire a shotgun down to 3, swap to a floor SMG: the SMG is full; swap back: the shotgun shows 3. Get downed
  with a half mag, revive: the same count. Kill an enemy: it drops and tumbles along the shot, bodies never block you,
  bullets pass through them, they fade after ~2.5s; a headshot kill sends the head flying; with 12 bodies down the
  13th shrinks out. Every hit nudges the enemy and sparks; `Kill all` shrinks them out instead.
- **Round 13b (4 Nov, feedback)** — ragdolls vary by what killed the enemy. `Enemy.Hit` carries `force`, `blast`,
  `blastT` and `tick`; `Enemy.damage` works out the overkill (damage past the remaining HP over max HP) and
  `throwStrength` turns the gun's `RagdollForceByArchetype` base, the overkill bonus (`RagdollOverkillMax`) and
  `RagdollVariance` into impulse, lift and spin. Blasts (claymore, Splash kills) use `RagdollBlast*`, strongest at the
  center and `RagdollBlastEdge` at the rim, thrown outward from the blast. Abilities' ticks (fields, flame turret,
  turret rounds) pass `tick`: a `RagdollTickForce` slump and no flinch, so a fire field no longer holds an enemy's
  feet every `EnemyFlinchCooldownSec`. Verify: a pistol kill tips the body; a shotgun blast up close flings it a good
  way; a sniper headshot on a fresh enemy sends body and head flying; a claymore scatters the group outward, the
  closest the furthest; an enemy that dies in a molotov field just slumps.

- **Round 14 (4 Nov, brief 4)** — the enemy roster (`Config.Enemies` + `Enemies.lua`; `Enemy.lua` as a base with
  per-archetype brains in `src/server/Enemies/`: Melee, Shooter, Marksman, Boomer, Grenadier, Heavy; `Rig.lua` builds
  the silhouettes, `Hazards.lua` the blasts, fire patches and telegraphs), the GDD scaling formulas, compressed
  composition brackets, proximity-weighted markers, the 100 cap with a queue, elites, a flinch pop that never moves an
  enemy (the Round 13 shove is `EnemyHitKnockback` 0), `ActiveRagdolls` 8 / `RagdollLifetime` 2, kill cash per
  archetype. Heat as pace (`Heat.lua`: par per wave, clear time to the last tagged death, fast / par / slow, AUTO SKIP,
  jobs, capped downs, boss kill; small floats with reasons beside the stars; the event meter and HEAT UP toasts are
  gone; `HeatStart` 0; the Stats print). Bags (`Bags.lua`, `BagSpots.lua`; Banked row; TOTAL BANKED headline, payout
  and `topBanked`). The vault closet on the north wall (map regenerated; `Room.vault`) and CRACK THE VAULT
  (`VaultJob.lua`). Boss waves (`Boss.lua` shell, cutscene, `Bosses/Titan.lua`, `HUD/BossBar`, `BossCutscene`).
  Account level (`Progression.lua`, `LevelRewards.lua`; XP bar on the summary; LV on the hub tag, the party card, rows).
  Scoreboard (`Roster.lua`, `Scoreboard.lua`; Tab / wave-bar tap; the core player list is off) and time survived
  (`World.survivedSec`, `topTime`, `stats.timeSurvived`). `BigCrate.drop` takes `{ legendary, count }`;
  `Minigames.open` takes a `tier`; `Markers.add` takes a badge glyph; new juice events `EnemyShot`, `EnemyLaser`,
  `BoomerFuse`, `EnemyLob`, `PlateOff`, `Knockback`, `BagSpawned` / `BagCollected` / `BagFizzled` / `BagsDropped`,
  `VaultOpen` / `VaultGas` / `VaultSealed` / `VaultGasTint`, `BossCutscene` / `BossWallBlow` / `BossSweepSpin` /
  `BossSweep` / `BossCharge` / `BossStagger` / `BossVolley` / `BossCallIn` / `BossPhase` / `BossDown`, `CrewLine`,
  `ToggleScoreboard`. Config gains the Enemies, Elites, Heat-as-pace, Bags, Vault, Progression and Boss groups
  (`EnemyHP` / `EnemyDmg` / `EnemyWalkSpeed` / `RetargetSec` / `CashPerKill` / `HeatWaveClear` / `HeatSideJob*` are
  gone). Built and linted, not yet run in Studio (see the Brief 4 verify list).

- **Round 14b (4 Nov, feedback on brief 4)** — the level is its own card (`HUD/LevelCard.lua`, reference board:
  emblem, `LV 19` and a rank name from `LevelRewards.Ranks`, `+47 XP` in green, a bar reading `993 / 3,110 XP`):
  it floats above the summary panel instead of sitting inside it, and the hub HUD shows it above the Gold pill
  (not in gameplay). Enemy speed and damage cut a third across the roster and TITAN (`Config.Enemies` rows,
  `TitanSpeed` / `TitanMeleeDmg` / `TitanChargeDmg` / `TitanSweepDps`; the brief's numbers are in the comments).
  The Grenadier's circle grows over 2.0s (`GrenadierTelegraphSec`). The boss telegraphs are the damage areas: the
  sweep a filled fan of the arc, the charge a rectangle `TitanChargeHitRadius` either side out to the overrun.
  Bags collect in 0.5s. The vault job is forced at every `VaultJobEveryWaves` (5) wave for testing and a sealed vault
  resets for the next draw (`VaultJobOnce` false). Point-blank shots: an enemy standing in you is inside the ray's
  start, so a bullet first hits the nearest enemy within `PointBlankRange` and `PointBlankAngle` of the aim. A
  Boomer killed by damage leaves a bigger circle growing where it fell (`BoomerDeathRadiusMult` 1.3 ×, over
  `BoomerDeathFuseSec` 0.6) before the burst. Thrown abilities (molotov, flashbang) land at the cursor's floor point
  up to `ThrowMaxRange` from the player (`UseAbility` carries the aim point); placeables still stand in front.

- **Round 14c (4 Nov, feedback)** — the hub level card is the Gold pill's width (compact) so the three bottom-left
  pieces line up; bags halved (`CashBagsPerWave` 1, `GoldBagsPerWave` 0.5 with fractional carry); the boss's bag ring
  is `BossBagBurstRadius` 18 so it clears the crate; the charge runs at `TitanChargeSpeedMult` 6; the Safe dial is
  out of the side job rotation (`SideJobKindWeights.Safe` 0); the summary leads with one GOLD BANKED number (the
  banked bags plus the run payout plus side job gold: `Row.goldTotal`) instead of TOTAL BANKED over GOLD EARNED, and
  the level card follows one count-up.

- **Round 15 (4 Nov, brief 5)** — one commit per build step. (1) The crate is the only weapon source: closed with
  party + `CrateRollsExtra` rolls, F plays the reel on a billboard above it for everyone (`CrateReelUI`, shared
  `CrateReel` timing), the gun ejects to a free spot `CrateDropRadius` out; the NEW WEAPON tile, hotkey 1, `WeaponReel`,
  `BuyWeapon` / `TakeCrateWeapon` and the weapon price keys are gone. (2) Upgrade categories by `CategoryWeights`;
  INCENDIARY / CRYO / CONCUSSIVE (`Elements.lua`, `StatusFx.lua`); ABILITY COOLDOWN / ABILITY POWER / CASH GAIN (Greed
  gone); halved tradeoffs never on elements; `CashWaveMult`; the per-wave income log and Stats line; tracker badges.
  (3) Revive bars for the reviver and the downed player (the ring is gone), the marker fill, camera ease on stand-up;
  ally callouts with headshots. (4) INITIATE Frag / Adrenaline / Claymore, ENGINEER Turret / Barricade / Overclock,
  SHARPSHOOTER Eagle Vision / Dead Eye / Flashbang; carousel order; class glyphs; profile v2. (5) Weapon and class mastery
  with all fifteen passives, mastery wraps, tile bars, the summary line, ability charges; per the designer's note XP
  writes live and a tier crossed mid-run applies at once with a rank-up card (`MasteryUI`). (6) The vault draw: VAULT JOB
  stamp, pulsing door, 2× diamond beacon that never compacts, floor chevrons, VAULT OPEN on the scoreboard. (7) The
  dealer break (`Dealer.lua`, `DealerUI.lua`) and VOTE TO PAUSE (`Pause.lua`, `PauseUI.lua`). (8) Debug: force element,
  +100 mastery, open dealer, pause / resume; mobile sizes for the reel, revive bar, dealer card / panels and the pause
  overlay. Config gains the Crates, Upgrades, Classes, Mastery, Vault, Dealer, Pause and Callouts keys. Built and linted,
  not yet run in Studio (see the Brief 5 verify list).

- **Round 15b (4 Nov, feedback on brief 5)** — Classes tab detail: class mastery (bar + three tier cards) replaces the KIT
  rows, the pill bars are gone; plain glyphs (ENGINEER `E`, Eagle Vision `EGV`; Eagle Eye renamed Eagle Vision, id kept).
  Frag has no fuse. The crate is back to the original sliding reel (`RollDurationSec` / `RollLandHoldSec` /
  `RollHighTierHoldSec` / `RollEjectSec` / `CrateRollGapSec`; the `CrateReel*` step keys are gone), on the billboard,
  with every roll chained from one F and a `GUN CRATE` tag; guns always rest on the floor (swap drops at floor height,
  `Landing` blocks mid-arc pickup). Upgrade hotkey 1. Dealer: `DealerArcRadius` / `DealerTableAngles` /
  `DealerPerTable` half circle, no stand parts, AlwaysOnTop cards, unlimited teleport, the pause button moved to the
  wave bar (VOTES under AUTO SKIP, PAUSE pill on the right). Vault beacon back to normal (`VaultBeaconScale` gone).
  Charges show their recharge; buff tiles show the running cooldown; `CooldownTrim` pops. Elements always apply
  (`*Chance` and `ElementPowerByTier` gone; power = the stat total / 100; `IncendiaryTickRatePerPower`, `CryoSlowCap`,
  `ConcussiveInterruptSec`; lower base numbers). Placeables sit in a `Structure` collision group (no player
  collision). Weapons tab: LV in the tile top bar (`nameTag`, `noPill`), the info line beside the name, a MASTERY bar
  in the detail, MASTERY tags on mastery wraps (`sourceTag`, where EVENT tags go later).

- **Round 15c (4 Nov, feedback)** — the mastery panel is one shared `MetaUI.masteryPanel` (title and diamonds in a
  list, `NEXT · UNLOCK SKIN`, the X / Y count inside a taller bar). Weapons detail: the info line centers on the
  name, a shorter well, EQUIP and CUSTOMIZE share one row (`EQUIP` / `EQUIPPED`), so nothing runs off the panel.
  Pause: no cooldown (`PauseCooldownWaves` gone), 5 minutes (`PauseMaxSec` 300) with VOTE TO EXTEND
  (`PauseExtendSec`, stacks) and VOTE TO RESUME, both unanimous. Elements read as ammo: Fire / Ice / Impact Ammo
  (`FIR` / `ICE` / `IMP`); a new one shows `NEW · BURN ON EVERY SHOT`, later takes `+30% BURN` / `SLOW` / `IMPACT`
  (`Upgrades.cardTexts`, `effectLine`, `effectName`; the dealer and the tracker tooltip the same).

- **Round 15d (4 Nov, feedback)** — the gun crate rolls faster (`RollDurationSec` 1.2, `RollLandHoldSec` 0.35,
  `RollEjectSec` 0.25, `CrateRollGapSec` 0.15), the reel panel is `CrateReelScale` 0.8 of the old size, and it has more
  juice: opening (`CrateOpened`) bursts gold out of the lid with a floor ring, a light flash, the thump and a shake that
  fades with distance (`CrateOpenShake`, `CrateFxRange`); every gun (`CrateEject`) kicks the lid and bursts in its rarity
  color with a ring and a whoosh, Epic and up bigger with a column of light and twice the shake (`CrateEjectShake`).

- **Round 15e (4 Nov, feedback)** — elements go on every bullet that lands, not once per trigger pull, so a full
  shotgun blast applies them pellet by pellet: Fire Ammo stacks (`IncendiaryMaxStacks` 5, `IncendiaryDps` 3 per stack),
  Ice Ammo builds toward the freeze per pellet, Impact Ammo shoves per pellet (`ConcussiveStuds` 1.0). Slowed enemies
  read clearer: a deeper blue tint (55%, frozen 75%) and bigger, brighter frost flakes.

- **Round 15f (4 Nov, feedback)** — the dealer card lives in the top-right stack like a crew call: the DEALER phones
  in first (`DealerLine` on the call card, `SHOP OPEN`), and when that card has held (`CallHoldSec`) a compact card
  slides in under it with `DEALER · 1:30`, TELEPORT [T] and SKIP n/m [V]; it slides out when the break ends. Nothing
  sits top-center any more.

- **Round 15g (4 Nov, feedback)** — no freeze lock: TITAN never freezes and takes `CryoBossSlowMult` (half) of Ice
  Ammo's slow; any other enemy freezes at most once per `CryoFreezeCooldownSec` (3s). Impact Ammo already never
  interrupts the boss.

- **Round 15h (4 Nov, feedback)** — the vault's Safe dial is more lenient: a wider hot range (`SafeHotRange` 6,
  `SafeWarmRange` 18), a shorter hold (`SafeLockSec` 0.3) that survives a brief wobble (`SafeHotGraceSec` 0.2), backing up
  near the number never reads WRONG WAY and elsewhere only after `SafeWrongWayDeg` 40, and the vault caps the dial at
  tier 2 (`VaultSafeTierMax`, three numbers).

## Open design notes (not built)

- **Brief 5 assumptions to confirm.** Elements (Round 15e) apply on every bullet that lands (each pellet and pierced enemy;
  ricochet / splash not). CONCUSSIVE never interrupts TITAN and interrupts anyone else at most every
  `ConcussiveInterruptSec` (every shot would otherwise lock enemies out of attacking); TITAN takes half the knockback. Mastery XP is written to the profile as it is
  earned (so a tier can apply mid-run, the designer's ask) instead of at the summary; leaving mid-run keeps it. Mastery
  wraps are generic (one Gunmetal / Gold / Black-Red set, `MasteryWrapIds`) but owned per gun. TRIAGE revives a bled-out
  ally whose body lies inside the med bag / turret range. Fire fields and the flame turret mark enemies as burning
  (the look and BACKDRAFT), but only INCENDIARY burns tick on their own. The dealer's stand purchases count as upgrades
  bought (they raise the next prices, pick-3 included), REROLL replaces all eight stands, ARMS DROP and HEAL ALL can be
  bought more than once. AUTO SKIP rolling a boss wave into the next skips the dealer (the wave was not cleared). Pause
  freezes Boomer death fuses and Titan ability timers only approximately (they run on brain clocks); nobody takes damage
  while paused, so nothing lands. The dealer stall stands at `DealerStallPosition` near the center (the brief names both
  the spawn zone and the center).

- **Brief 4 assumptions to confirm.** Jobs and downs score at the end of the wave they happen in (one float each),
  not the moment they happen; a job that expires costs `HeatJobFail` the same way. The boss's `TitanHp` scales by the
  wave HP formula and the player count like any enemy (≈11,000 solo at wave 10). The Grenadier's fire patch burns
  players at `GrenadierFireDps` (the brief gives no number). Milestone masks are the existing visors (blue / gold /
  purple / chrome). The boss wave's regular enemies come from the normal brackets at `BossWaveBudgetPct`. "Loot Rush"
  on the debug panel is a bag burst round the player (the brief names it without defining it). The through-wall boss
  marker is a client Highlight plus a head tag rather than a Markers billboard. Enemy telegraphs are server Parts, so
  phone legibility is a transparency knob (`TelegraphTransparency`) rather than a per-device size.
- **Brief 3 assumptions to confirm.** The crate pool is the union of the party's owned guns, each at its highest
  owner level (a shared drop cannot be per-profile). INITIATE's hotkey order follows the GDD class table (Q barricade,
  E turret, Z stim), which swaps Q / E from Round 9. INITIATE's stim does not heal (Round 12b); DOC's stim shot carries the heal
  exists. Walking into a zone while someone else has the Create Match card open waits on the pad and joins on CREATE.
  The session lock is advisory (logged and taken over), not a hard refusal.
- **Brief 2 assumptions to confirm.** A downed player keeps the run alive (self-revive is free), so "all players down"
  is not game over until the last bleed runs out; flip that in `Downed.checkRunOver` if the stamp should land on the
  last knockdown. Robux Self-Revive / Revive Everybody and the pose shop are out of scope. `RunOverTimeScale` only
  drives the client slow-mo read (lens + desaturation); enemies are frozen and nobody is standing at that point.

- **Dropped weapon handling.** Floor drops are hard to pick up mid-wave and can land behind a moving player.
  Discussed a stash slot (previous gun kept in a second HUD slot with the 30s decay, instant swap key, rolled guns
  fly to hand, deliberate drop for teammates). Parked for now.
- Barricades may die fast to large crowds; stuck detection is coarse; the top-right stack is 320px wide and may
  cramp long dialogue lines.
