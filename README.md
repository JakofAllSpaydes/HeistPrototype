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
impossible to miss, and adds a dealer break after every boss wave and a vote to pause. Brief 6 adds the monetization
front end against a fake Robux balance: a premium store scene (FEATURED bundles, CRATES with a full opening scene,
BOOSTS, VIP, GOLD), revive tokens, a battle pass with its own scene, daily Jobs and a weekly bounty on MARLOW's board,
and the in-run upsells. Nothing touches real Robux; one module per side (`Purchases.lua`, `PurchaseSheet.lua`) is
where `MarketplaceService` goes later.
Brief 7 adds THE BANK as map 2 beside the arena: a builder-made bank with seven zones that open on door objectives,
the vault job on its real wheel door with a tunnel ring, spawn boxes that follow the crew and `PathfindingService`
navigation on every map.
Brief 8 replaces the generated yard with a builder-made warehouse hub: four queue pads with four independent parties
(runs on different maps play at the same time on one server), the three customization booths with mannequins in your
own loadout, MARLOW's board on the wall, the van leaving through a roll-up garage on run start, and a walled training
range where the helicopter bay was.
Brief 9 adds the Skill Web: a hex web of 90 one-time account perks bought with Gold from the hub's SKILLS tile
(six branches, five rings around START), small account-wide stats that stack on the Armory and apply in every run
and the range.
Brief 10 adds retention: a 28-day login streak claimed from a modal on the first hub entry of each fake day (a lost
streak can be restored for fake Robux), one daily crate on a glowing podium on the hall's west side that a finished match
unlocks (its tier from your level, guns and masks from the normal pool, the first one a gun), and the PLAY line that
surfaces the first run of the day (the daily crate and the existing ×2 XP).
Brief 11 makes the game playable on a controller end to end: the pad's combat map and right-stick camera with its own
aim assist tier and rumble, a glyph for the current device on every prompt and hint, every screen walkable with an
amber selection ring, the seven minigames on a pad, sprint on PC / pad / phone with the fire-always-wins rule, a
CONTROLS sheet (the INPUT settings; no button opens it for now, Round 28c). The HUD keeps the PC layout and size on a pad (Round 28b).

State as of **8 Nov 2026 (Round 28)**: all brief 1 acceptance items are in, plus eight playtest rounds of feedback, the brief 2
slices (Round 9) and six feedback rounds on them (9b–10d below), the brief 3 build (Round 11) with its feedback rounds,
phase 2 (Round 12: all twelve class abilities live, with the 12b / 12c feedback passes), the Round 13 multiplayer pass
(revive pauses the bleed, teammates' tracers and shot sounds, busy tags, everyone votes to skip, mags live with the gun,
ragdolls and hit sparks), the brief 4 build (Round 14: roster, boss, heat as pace, bags, vault, level, scoreboard) and
the brief 5 build (Round 15: crate reel, elements, revive bars, ENGINEER, mastery, dealer, pause) with its feedback
rounds 15b–15m, the Round 16 / 16b feedback passes, and the brief 6 build (Round 17: fake purchase flow, store,
crates, boosts, VIP, battle pass, Jobs; one commit per build step) with its feedback rounds 17b / 17c and 18–18d,
and the brief 7 build (Round 19: THE BANK, doors, the vault ring, spawn boxes, pathfinding; one commit per step)
with its feedback rounds 19b, 19c (the building alarms, zone gas and the bolt cutter), 19d (the audio pass and
soundtrack, the alarm job as a minigame, no street jobs once inside, the vault stairwell chains D5, lockdown gas) and
19e (feedback on 19d: continuous run music, new run tracks, no explosion clip, a lootbox sound set, zone gas from
wave 10), 19f (the glass offices as mini vaults), 19g (door waves 2 / 5 / 8 / 12, the door guide), the weapon art
pass (stand-in gun models, a procedural hold / aim / fire / reload animation, 3D viewport icons for guns and
cosmetics, drawn pictograms for abilities, classes, boosts and upgrades) and 19h (feedback on it: the gun-only
CUSTOMIZE close-up, the upgrade pick sound, no minigame twice in a row, no hold-to-HACK job, the crate reel on a
screen overlay, softer kill sounds, the door guide up until the door opens), 19i (a minigame solved as you walk off still counts), 19j and 19k (the upgrade pick sound, now Jack's own pick), 19l (particles on picking an upgrade), 19m (the premium scene sets moved under the arena so the pass lights up at once) 19n (the hub nameplate: level badge, name, class block, best wave) and 19o (the game-wide style pass: Oswald / Builder Sans, sharp corners, bigger text, fuller HUD tiles; seen by Jack in Studio), and the
brief 8 build (Round 20: the warehouse hub, concurrent runs, the departure beat, the training range; one commit per
step), then Rounds 20b–20u from Jack's first plays of it (the load fixes, walk-in booths, R15 dummies, the range HUD,
a clean customization shot, hub walk speed, the place's own lighting, the pass stage spotlight, the van cutscene,
doors taking the objective slot, smaller pad boards, MARLOW at his board, the upper doors gone from THE BANK, and map
dressing as a Workspace file: `Workspace.Hub.Dressing`, and minigame anti-cheat floors a fast player clears), then
Round 25 (8 Nov, unplayed: E interacts and abilities are Q / F / Z, defense upgrades with ARMOR, EXPLOSIVE synergies, teammate markers, shared-crate pools, named hub booth keepers, the BANK vault gas fix; see the changelog), before it
Round 21 (8 Nov; Jack confirmed the gun switch in Studio, the rest is unplayed: two gun slots, the run clock from night, smaller SHOP / JOBS windows, the hub player list,
wave-scaled dealer prices and leaving warnings, the vault stairwell shot fix, stragglers warped in, a front door that
opens itself when you're already inside, every SQUAD / MVP emote playing), then
Round 22 (8 Nov; Jack's mobile-play feedback: premium shop 5% bigger, enemy catch-up warp distances pushed out,
vault job forced after stairwell unlock, the left joystick no longer rotating the camera, a SWAP weapon button on
mobile; 22b: cash duffel and gold briefcase bag models built from bricks, flying currency icons on pickup with more
sparks and camera shake, smooth banked-gold countup with a +N toast, camera raycast excludes the Enemies folder so
bodies don't zoom the lens in),
Round 23 (8 Nov; juice / SFX / polish pass: buff aura as rising particles instead of a point light, outline-only
Highlight while a self-buff runs, per-buff activation sounds (Dead Eye whoosh, Overclock rising whoosh, Stim/StimShot
upgrade chime), Eagle Eye bullet-whiz ping, throw launch whoosh, pitched-down gunshot boom for frag/claymore/molotov
explosions, flashbang pop, buff-end sound, structure placement thump, door-hold buildup ticks (chain snip / generic
click rising in pitch), chain door break as snip + crunch, bigger door-open shake and amber blast ring, explosive
chain-link scatter with spin, faster panel-door swing, softer enemy Neon-red heads, bigger/shinier bag models,
taller/more-transparent beacon beams, weapon-swap micro-shake, kill micro-shake, hit camera shake, removed duplicate
legendary sound from AbilityColumn on buff start),
Round 24 (8 Nov; Jack's second mobile pass, built unplayed: touch turns the hub camera, multi-touch move + look + fire,
FIRE doubles as a look stick, mobile buttons 30% bigger with FIRE / ADS left of jump, a touch band around the
minigame panel and a gentler Safe dial, Meta drag-rotate direction fixed, and gun aim assist for touch / gamepad),
Rounds 24b–24ag (8 Nov; Jack's play-feedback rounds, built unplayed unless noted: stacked side job + door pills, cutscenes
hide markers, a first-person viewmodel (arms, gun, ADS down real iron sights / red dot / holo / ACOG / medium / sniper
scope with zoom, reload, swap draw, sway), muzzle-attached tracers, mobile landscape lock and look-while-moving fix, the
EXPLOSIVE (RPG-7, M32, Cluster Launcher, TNT) and ELEMENTAL (Flamethrower, Cryo Sprayer, Arc Gun, Plasma Gun)
weapon types, eight more guns and the four showcase guns made real, per-gun receiver shapes and silhouettes, icon
category tiles, favourites (weapons and avatar), two starter slots, soft-capped weapon and ability levels, a Shift sprint
prototype, faint mouse aim assist, a centred camera when the cursor is unlocked, and the Railcaster beam hitting real
body parts), then
Round 26 (8 Nov: the brief 9 build, the Skill Web; one commit per step, built unplayed) with Jack's feedback
rounds 26b (a compact sheet, branch-coloured hexes, the web growing as you buy, varied costs, centring, plain effect
lines) and 26c (START bought first, UNLOCK SKILLS, the unlock sequence), then
Round 27 (8 Nov: the brief 10 build, retention: the login streak, the daily crate podium, the PLAY line; one commit per
step, built unplayed) and Jack's feedback rounds 27b–27i (seen in Studio): the streak modal every session in the house
look with one centred row, one action and the paid skip, streak crates as weekly-tier daily crates; the podium moved
into view where the drums stood, glowing, with an overhead CTA, its sheet in every state with BUY 1; the summary
unlock card, the hub guide and MARLOW's nudge; the glowing first-run bar under PLAY; a wider daily pool; the crate
scene's HUD and lighting fixes and the eased camera out of the podium view; and the brief 11 build (Round 28, one
commit per step, step 2 swept once on a DualSense at checkpoint 1): the controller end to end, device glyphs,
screens on Roblox's own selection, the minigames on a pad, sprint everywhere, CONTROLS (Round 28b: the custom ring and
the pad HUD scale taken back out).
Everything on `main` builds clean and is what Studio sees through Rojo. The "Brief 3 verify list", the "Round 12 verify
list", the "Round 13 verify list", the "Brief 4 verify list", the "Brief 5 verify list", the "Brief 6 verify list", the "Brief 7 verify list", the "Brief 8 verify list", the
"Brief 9 verify list", the "Brief 10 verify list" and the "Brief 11 verify list" are the walk-throughs for a fresh Studio session. Brief 5 has been played in Studio by the designer through the 15b–15m feedback rounds (which is
where those changes came from); the full verify lists have not been walked end to end.

## Run it

1. `aftman install` (once) so `rojo`, `stylua` and `luau-lsp` resolve.
2. `rojo serve` in this folder.
3. In Studio: Rojo plugin → Connect. Delete the default `Baseplate` once in edit mode (the server also removes it). Press Play.
   Brief 8 adds `Workspace.Hub` to `default.project.json`: restart `rojo serve` once after pulling it (a running serve
   keeps the old tree).

Everything the designer tunes lives in `src/shared/Config.lua`. Change a number, Rojo syncs it, play again.
The map is a Rojo-synced model (`src/map/Room.model.json`, regenerate with `lune run tools/genmap.luau`; `lune` is in
`aftman.toml`, and the generator loads Config through `luau.load` with Vector2 / Vector3 stubs).
THE BANK (brief 7) is `src/map/Bank.rbxm` (geometry, `lune run tools/importbank.luau <place>` made it) plus
`src/map/Bank.nodes.model.json` (the nodes). `lune run tools/genbanknodes.luau` wrote the first node set and is not
run again; after moving nodes in Studio, save `Workspace.Bank.Nodes` as `.rbxmx` and run
`lune run tools/exportnodes.luau Nodes.rbxmx`.
The hub (brief 8) is `src/map/Hub.rbxm` (`lune run tools/importhub.luau <place>`; Studio's zstd saves go through
`node tools/rbxl-uncompress.js <in.rbxl> <out.rbxl>` first) plus `src/map/Hub.nodes.model.json` (written once by
`lune run tools/genhubnodes.luau`). After moving hub nodes, save `Workspace.Hub.Nodes` as `.rbxmx` and run
`lune run tools/exportnodes.luau Nodes.rbxmx hub` (a whole `.rbxlx` place exports both maps).
Brief 10: `lune run tools/importhub.luau drop` re-applies `Config.HubImportDropAt` (models dropped by name and position)
to the baked `Hub.rbxm` (it dropped the two drums in front of the loading platform), and `lune run tools/genhubnodes.luau append`
adds node types the hub nodes file lacks without touching the dragged ones (it added `DailyCrate`).

You spawn in the **hub** (the warehouse, baked at `HubOrigin` (0, 0, 1000)) on the floor star facing the four yellow
queue pads, with the hub HUD, 10,000 Gold on a fresh profile, the M1911 as starter, INITIATE equipped and the plain
mask, plus (brief 6) a fake `R$ 100,000` balance and 3 revive tokens. MARLOW's job board is the bulletin board on the
north wall between pads 2 and 3. Profiles need `Enable Studio Access to API Services` on the place (Game Settings →
Security); without it the server warns once and keeps an in-memory profile for the session. Walk onto any pad (or
press PLAY) to create a match. The WEAPONS booth is on the west wall, CLASSES on the east, AVATAR on the south behind
the spawn; the van waits in the north-east garage; the north-west door opens onto the training range with the
dummies, the seven minigame props and the tier pad. Party and downed / revive lines need Studio's Local Server with
2–4 players; everything else works solo.

## Controls

| Input | Action |
| --- | --- |
| LMB (hold) | Fire. `HoldToFire` in Config. |
| RMB (hold) | Aim down sights: narrower FOV, camera pulls in, half spread, tighter crosshair, lower sensitivity. `Ads*` in Config. With the cursor unlocked (Ctrl) it only pulls in a little and dragging rotates the camera. |
| R | Reload. Tube-fed guns (`shellReload` in Weapons, currently the SPAS-12) load one shell per `reloadTime`; firing or R again stops at the current count. |
| Scroll wheel | Zoom. Fully in is first person (character hidden locally); out to `CameraZoomMax`. |
| 1 | Switch guns (Round 21): you carry two. You start with one; a gun picked up with the second slot empty goes there and you switch to it, and with both full a pickup replaces the gun in your hands. The square chip right of the weapon slot shows the other gun (tap it on mobile). `WeaponSlots` / `WeaponSwitchSec` in Config. |
| 2 | Buy an upgrade pick (also the clickable tile, left column; was 1). Weapons come only from gun crates. |
| E on a gun crate | `OPEN` (a `GUN CRATE` tag over it): every roll the crate holds plays back to back on the reel above it, seen by everyone, and each gun ejects onto the floor beside it as loot anyone can take. |
| Q / F / Z | The equipped class's three abilities, all fifteen live (INITIATE frag / adrenaline / claymore, ENGINEER turret / barricade / overclock, DOC stim shot / med bag / healing turret, SHARPSHOOTER eagle vision / dead eye / flashbang, TORCH molotov / flame turret / oil drum). Cooldowns in `AbilityCooldown` (less ABILITY COOLDOWN). Thrown ones (frag, molotov, flashbang) land where the cursor points up to `ThrowMaxRange` (100), locking on and homing to the enemy under the cursor (or the one the camera ray just missed, or the one nearest the point: `ThrowAssist*`); placeables stand `StructurePlaceDistance` ahead. A `x2` on a tile is a second charge (INITIATE mastery II). |
| P | Vote to pause (in a wave, the intermission or the dealer break; solo pauses at once). Also on the dealer card and the scoreboard. RESUME on the overlay (anyone). |
| T / V / E at the dealer | During the dealer break: T teleports you to the stall (as often as you like), V votes to skip the break, E buys the stand or prop whose panel is open (Round 25: the stand you look at; a floor gun you look at more squarely takes E instead, `InteractDistWeight`). Mobile: the card's buttons and the panel's BUY. |
| E | Swap with a floor gun (ProximityPrompt). Round 25: E is the interact key everywhere and abilities moved to Q / F / Z (`InteractKey`, `AbilityKeys`). 0.5s cooldown between swaps. In the hub: `OPEN` at MARLOW's board (the booths open by walking onto their orange half-circle, no prompt); in the range `OPEN` on a minigame prop, `TIER n` on the tier pad. |
| (walk into the range) | Brief 8: the north-west door of the warehouse. Inside you are armed with your starter gun (fire, reload, ADS, abilities, Ctrl camera lock) and the HUD switches to the range layout; walking out stows it. Nothing pays or scores. `R` at a dummy's sign (`RESET`) zeroes its `DMG · DPS · HS` tag. |
| (walk up to a bag) | No button: stand within `BagStartRadius` of a cash or gold bag and it fills over `BagChannelSec`, then it is yours (cash to everyone / the team's `◆ BANKED` row). Teammates see `GRABBING` over your head. |
| E at the vault door | `CRACK` the vault while CRACK THE VAULT is the open side job: opens the Safe dial at the wave bracket's tier. |
| Tab (hub) | Roblox's own player list with LEVEL and BEST WAVE leaderstats (Round 21). |
| Tab (hold, in a run) | The scoreboard: WAVE · TIME · stars · BANKED · CASH and one row per member in MVP order; the game keeps running behind it. Mobile: tap the wave bar (the `≡` chip beside N LEFT), tap again or anywhere outside to close. |
| Walk onto a queue pad | Create Match card (party size, map, difficulty, info, CREATE, X). Walking in joins an open party; walking out leaves it. Brief 8: four pads, one party each; a pad whose party is in a run refuses entry; a party whose map is busy waits on its pad (`MAP BUSY · <name> IS INSIDE`). |
| PLAY (hub HUD) | Walks you to the nearest open pad (no party, or a party with room). Dock tiles WEAPONS · CLASSES · AVATAR open the customization scene; LEAVE (red X) or Esc closes it. |
| SHOP tile / Gold + (hub HUD) | Brief 6: the store window over a dark dim, scrolled to FEATURED (the Gold + scrolls to GOLD). The rail on the left (FEATURED · CRATES · BOOSTS · VIP · GOLD) scrolls the one page to that section; LEAVE, Esc or a tap outside the window closes it (Esc closes an open detail sheet first). A red dot on the SHOP tile means banked crate opens or the VIP gift wait; the tile then opens on that section. VIEW CRATE / VIEW BUNDLE / VIEW VIP on customization tiles open it on that item. |
| SKILLS tile (hub HUD, under SHOP) | Brief 9: the Skill Web scene. Drag to pan (mouse, touch, right stick), scroll / pinch / triggers to zoom, double-tap the backdrop to recentre on START. Tap a hex → its sheet docks right; BUY there (never a single tap). Esc / BACK / B closes the sheet, then the scene. The red badge counts nodes you can buy right now. Hub only (hidden in runs and the range). |
| PASS / JOBS (hub HUD, right-center) | The battle pass scene and the JOBS board. E at MARLOW's corkboard (`OPEN`) opens the board too; VIEW PASS on a PASS item opens the pass; CLAIM IN PASS on the summary takes you back to the hub first and opens it there (Round 19c). Esc / LEAVE / BACK closes either. |
| $ + (match HUD cash row) | Brief 6: the cash-pack sheet (+$5,000 / +$20,000 / +$100,000 for fake Robux); the game keeps running behind it. Short of cash at the dealer, the same sheet opens (REROLL offers the R$ RESTOCK). |
| E (hold `ReviveHoldSec`) | Revive a downed teammate within `ReviveRadius`. Their bleed timer stands still while you hold (`RevivePausesBleed`); letting go resumes it. Outranks floor guns: their prompts hide while a downed teammate is in reach. Mobile: a REVIVE hold button appears bottom-center. |
| Esc / X | Cancel an open minigame (counts as `cancel` in the log). |
| ◀ ▶ / A D | Spectating (bled out): cycle living teammates. REVIVE EVERYBODY button bottom-center. |
| E (hold 2s) | Hack the side-job beacon (hack jobs). Capture jobs: stand in the circle for `SideJobCaptureSec`; progress pauses when nobody is inside. Minigame jobs: E opens the game at the beacon. Kind is rolled per job from `SideJobKindWeights` (eight kinds, equal odds by default). |
| Esc / X / 2 | Close the upgrade overlay. |
| V | AUTO SKIP on / off, any time in a run (Round 28d; it also votes to skip the intermission). Click the VOTES pill to vote just this intermission. Everyone in the party has to vote (`SkipVoteFraction` = 1; `SkipMinIntermissionSec` is the floor). |
| AUTO SKIP pill | Waves roll into each other: once the wave has fully spawned and `AutoSkipWaveSec` (10s) has passed, the next wave starts on top of whatever is left, with no intermission. |
| Ctrl | In a run: toggle the cursor lock so you can click HUD tiles (the chip above the ammo reads CAMERA LOCKED / CAMERA FREE). While unlocked the camera holds still, the character turns to face the cursor and shots go where the cursor is, so you can aim all the way around. Left Alt frees the cursor while held. In the hub the cursor is always free (RMB drags the camera) and every combat hotkey (fire, 1 / 2, Q / F / Z, V, Ctrl) is off; the server also refuses rolls, upgrades and abilities outside a run. |
| Backtick | Debug panel (brief 8 adds HUB: To hub / To range, Reset dummies, Open garage (the departure beat with nobody in the van), Force pad 1–4, Spawn at range (the archetype row, ELITE, Range boss); brief 7 adds MAP: Show nodes with per-type toggles, Recompute nodes, Teleport to zone, Open D1–D4, Close all doors, Open / Gas / Seal vault, Spawn at a chosen box (with the archetype row and ELITE), Pin the crew zone / AUTO, Path debug; Stats adds the MAP block; Round 18 adds NO COOLDOWNS and SYNERGY, which forces a qualifying synergy card into the next pick-3; brief 6 adds MONETIZATION: set R$, set tokens, +10 free Arms / Mask opens, +1 fake day, +1,000 pass XP, reset jobs, the purchase log readout; Force rarity also lands on the next crate open): add cash, skip/set wave, pause spawns, kill all, force rarity/tradeoff, drop crate, trigger call, god mode, reset run, force queue start, skip to run end, down me / down all / revive all, open any minigame, set tier, Stats (minigame averages and the run's heat clear / par ratios), +1,000 Gold, unlock all, reset profile, +500 XP / set level / reset daily, spawn any archetype (ELITE toggle), spawn boss, cash / gold bag, open vault, set heat, gas vault, Loot Rush, force element card, +100 mastery (held gun and class), open dealer, pause / resume. Mobile: the `DBG` chip top-left. |

Mobile: touch look, pinch to zoom, on-screen fire / ADS toggle / reload / ability buttons, tap the VOTES and AUTO SKIP pills, no hotkeys.
Round 28e: POV (left of the weapon slots) cycles normal / far over the shoulder / first person like the pad's R3; a drag
that starts on any HUD button (ADS, SWAP, abilities, gun slots) still turns the camera; on phones Roblox's top-bar row
collapses to its menu button (`MobileTopbarHidden`, chat goes with it).
Round 24b–ag: the game holds landscape (LandscapeSensor, also set on StarterGui in default.project.json); touch look is
polled per finger and a pinch only counts with both fingers right of the stick, so move + look + fire work together.
PC (Round 24aa prototype): hold **Shift** while moving to sprint (SprintSpeedMult, gun away: no fire, no ADS). Charge
weapons (Plasma Gun, Railcaster): hold fire to charge (the crosshair ring fills), release to fire; a held plasma beam
follows the cursor. First person (zoom all the way in) shows a viewmodel; aiming an optic zooms and draws its reticle.
Round 24: FIRE / ADS sit left of Roblox's jump button, FIRE is also a look stick (hold to shoot, slide to aim), every HUD
button is `MobileButtonScale` (1.3) bigger, and aim assist pulls toward the torso (crosshair held up = the head).
Hub HUD on mobile landscape: dock tiles 76×68, PLAY 44px, SHOP and INVITE as icon tiles, queue card at 80%; the
customization panel takes the right 62% with 64px tiles and a 60px dock.
Every minigame is tap or drag only (no double-tap, long-press or keyboard); the revive hold and spectate arrows are buttons.

**Controller (Brief 11).** A DualSense (or any pad) plays the whole game; glyphs follow the device you last touched
(PlayStation shapes by default). The map is `Config.GamepadMap`.

| Button | In a run | In the hub |
| --- | --- | --- |
| R2 | Fire (hold for auto; charge guns hold and release) | |
| L2 | Aim (hold) | |
| □ | Reload (tap). While a prompt is up (or a downed teammate is in reach): hold = the prompt / revive. At an open dealer panel: buy | The prompt |
| △ | Swap guns | |
| ✕ | Jump | Jump; selects in screens |
| L1 / R1 / ○ | Abilities 1 / 2 / 3 (checkpoint 1: ability 3 moved off R3) | L1 / R1: small categories in screens; ○: back |
| R3 | Camera view: normal → fully out over the shoulder → first person → normal | |
| L3 | Sprint (a toggle: any direction, until you stop, click again, or fire / aim / cast) | Sprint |
| D-pad ↑ | Buy the upgrade pick; at the dealer break: teleport | |
| D-pad ← | Vote to pause (P) | |
| D-pad → | AUTO SKIP on / off (V; between waves it is also your skip vote); at the dealer: skip the break | |
| Create | Scoreboard: tap opens / closes (the selection sits on VOTE PAUSE), hold peeks | Enter / leave the HUD selection (PLAY first) |
| Options | Roblox's menu (reserved) | Roblox's menu |
| Right stick | Look (dead zone, curve, edge acceleration; ADS slower) | Look |

In every screen (Roblox's own selection, moving to the button directly above / below / beside): D-pad / left stick move
it, ✕ presses and the selection stays where it was, ○ backs out. On a two-level screen L2 / R2 swap the big categories
and L1 / R1 the small ones (customization: WEAPONS / CLASSES / AVATAR, then the weapon types / classes / avatar
categories); a one-level screen swaps its tabs with L1 / R1 and pages long lists with L2 / R2. Minigames have their own
pad lines (shown in the game's hint line); the left stick keeps walking during them.
Sprint (Brief 11): Shift (hold), L3 (a toggle), or push the phone's thumbstick through its ring (or a tap
button, or off). Fire always wins: any shot, ADS, ability, interact or swap ends the sprint and happens at once; sprint
then needs a fresh Shift / L3 / thumb pump.

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
HpPerPlayerMult × (players − 1)) × hpMult`, `FinalDamage = BaseDamage × (1 + DamageWaveMult)^(wave − 1) ×
dmgMult` (the run's `QueueDifficulties` row); player count never changes spawn counts. `Enemy.lua` is the base (rig from `Enemies/Rig.lua`,
targeting, movement with the stuck detour, damage / flinch / kill / ragdoll, stun and slow) and hands each enemy a
brain from `src/server/Enemies/` every heartbeat through one `api` of helpers: Henchman and Runner (`Melee`: walk at
the nearest player or the placeable in the way, hit on reach; the Runner sprints at 22 with a shrill wail),
Marksman (`Marksman`: paints a red laser
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
GoldBagPerWave × wave)` to the team's Banked total (`◆ N BANKED` row under the cash row, ticks on collect). No
button (round 18): standing within `BagStartRadius` of a bag claims it and a ring of ticks over it fills over
`BagChannelSec` while the bag glows and slides toward you (`GRABBING` over your head for teammates); it stays yours
until you step past `BagKeepRadius`. Full, the bag shoots into you and pops in a money burst with a `<NAME> GRABBED
$300` / `<NAME> BANKED ◆ 40` toast, and the next bag in reach starts at once (the one with fill first, else the
nearest); bags started within `BagStreakWindowSec` of the last fill `BagStreakMult` faster each, down to
`BagStreakMinMult`. A bag you leave keeps its fill `BagHoldSec`, then drains `BagDrainPerSec`; a bag someone is
filling is skipped by everyone else. `CashBagsPerWave` (1) and `GoldBagsPerWave` (0.5: fractions carry, so every other wave)
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
Level shows as the badge on the hub nameplate (Round 19n), the party card, the summary rows and the scoreboard; lifetime XP in
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

**Gun models and animation (art pass, `GunModels.lua`, `GunAnim.client.lua`).** Every gun the game shows (held,
floor, store, crate, icons) comes from one procedural builder: a per-gun spec on top of its kind (pistol, SMG, rifle,
bullpup, shotgun, sniper, LMG) picks receiver, handguard, barrel, stock, mag (stick, banana, drum, belt box, top,
tube, in the grip), sight (irons, red dot, scope, carry handle) and action (slide, bolt, pump, lever, break, charging
handle), so the AK reads wood and banana mag, the M4 tube stock and red dot, the P90 a top mag, the Barrett a brake
and bipod. Rarity colours strips on the receiver (neon from Epic); the wrap paints the furniture (every `Wrap` part).
`GunModelScale` sizes them all. The held gun hangs off the right hand on a `GunJoint` Motor6D (a hand-carry rest pose,
which is what the hub and store mannequins show); floor guns lie on their side on the old invisible handle Part.
In a run every client poses every crew member procedurally (no uploaded animations): a stance per kind
(`GunPoses`: where the butt / grip / sight line sits for hip and aimed, the chest twist), aim pitch toward the cursor
(teammates' pitch, ADS and reload state ride on character attributes via `Remotes.GunPose`), two-bone IK putting the
right hand on the grip and the left on the foregrip (R15, Motor6D or the AnimationConstraint avatar joints; R6 swings
the arms straight), recoil springs (`GunRecoil`), the slide (locked back on empty), pump / bolt / lever cycling with
ejected brass or shells, mag reloads (the mag drops, a fresh one comes from the belt pouch and seats on
`ReloadSeatShare`, the charging handle on an empty reload), shell-by-shell loading, the break-action opening, a
muzzle flash with a light. Any Action-priority track except the class idles (the downed crawl, line-up poses, emotes)
and the hub hand the arms back. A character it cannot pose prints one `[GunAnim] can't pose …` line with its joints.

**Icons (art pass).** Weapons, masks and wraps show live 3D ViewportFrame icons of the real models
(`UI/ModelIcon.lua`: auto-framed, a slow sway on hover, dim / locked states, `ModelIcon*` in Config) on the Weapons
and Avatar tabs, store and pass cards, the crate reel and the HUD weapon slot. Abilities, class emblems, boosts,
upgrade stats and the hub dock draw pictograms built from frames (`UI/Icons.lua`, keyed by the existing ids; an
unknown id falls back to its old text).

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

**Upgrades.** Pick 1 of 3 cards (and the dealer's stands) from four categories drawn by `CategoryWeights` (gun 50 /
element 15 / defense 15 / utility 10; Round 25 added defense: Max HP, HP Regen and ARMOR, flat shield points over HP that
refill `ArmorRegenDelay` after the last hit at `ArmorRegenPctPerSec`, the thin bar on the HP bar) before the stat: 13 gun stats (Damage, FireRate, MagSize, ReloadSpeed, CritChance, HeadshotMult,
MoveSpeed, Accuracy, Pierce, Ricochet, Splash, Multishot, Lifesteal); three ammo types that go on every bullet that lands, each
shotgun pellet included (`Elements.lua`, ids Incendiary / Cryo / Concussive; look in `StatusFx.lua`): Fire Ammo (a burn
that stacks per hit up to `IncendiaryMaxStacks`, `IncendiaryDps` per stack for `IncendiaryBurnSec`, orange tint and
embers), Ice Ammo (slow `CryoSlowPct` for `CryoSlowSec`, cap `CryoSlowCap`; `CryoStacksToFreeze` hits in that window
freeze for `CryoFreezeSec`, at most once per `CryoFreezeCooldownSec`; deep blue tint, frost flakes, ice; the boss takes
`CryoBossSlowMult` and never freezes), Stun Ammo (named Impact before Round 21; stat id `Concussive`; a `ConcussiveStuds` shove per bullet and a `ConcussiveStunSec`
interrupt at most every `ConcussiveInterruptSec`, Heavy / boss `ConcussiveHeavyMult`, the boss never interrupted, a
white ring); the first take is 100% power (cards read `NEW · BURN ON EVERY SHOT`), later takes add the card's percent
(`+30% BURN`: burn DPS and tick rate `IncendiaryTickRatePerPower`, slow / freeze, knockback); and utility: ABILITY COOLDOWN (capped `AbilityCooldownCap`), ABILITY POWER (ability damage,
heal, placeable HP) and CASH GAIN (kills, bags, job payouts; it replaced Greed). Each card spins an icon reel at the top,
lands on the stat, then the text reveals. Higher rarity = bigger punch/shake/flash/rays. Tradeoff cards (`TradeoffChance`,
halved in brief 5) carry a malus line; never on an element card, and the malus never lands on an element or CASH GAIN.
The tracker grid shows counts for gun stats, the power for elements (`130%`) and the total for utility (`-12%`).
Income: kill cash = archetype cash × (1 + `CashWaveMult` × (wave − 1)) × elite × heat × CASH GAIN; every wave end prints
`[GHS Income] wave N cash earned X upgrades bought Y (name)` and debug Stats adds upgrades per player per wave
(target 1–1.5 through wave 20).

**Abilities.** All five class kits are live (`Abilities.lua`, numbers in Config's Abilities group, growth per
ability level through `AbilityGrowth`). Placeables stand `StructurePlaceDistance` ahead (0: where you stand, Round 18b); attackable ones (turret,
barricade, healing turret, flame turret, oil drum) have HP bars and enemies walk to and hit them; a med bag and a
claymore are not targeted. Ground fields (med bag, molotov, the fire a broken drum leaves) act every `FieldTickSec`
on whoever stands in the circle. Thrown abilities (frag, flashbang, molotov) land at the cursor up to `ThrowMaxRange` (100), arcing higher with
distance (`ThrowArcPerStud`) over `ThrowFlightSec`, longer past `ThrowFlightRefStuds`. Placeables sit in the
`Structure` collision group: enemies stop at them, players walk through.
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
  walks `EagleEyeSlowPct` slower, capped `EagleEyeSlowCap`, the boss `EagleEyeBossSlowMult` of it; Round 16 replaced the damage bonus), dead eye (8s: weapon damage +25%, spread
  `DeadEyeAccuracyPct` (50%) tighter (Round 19c; was move +20%), every bullet passes through `DeadEyePierce` more enemies; a fractional pierce like 2.2 is one more enemy
  at 20% damage), flashbang (thrown; every enemy in `FlashRadius` stops and stops swinging for `StunDuration`, head goes white).
- Friendly fields (molotov, burst oil drum) burn `AllyFireColor` blue with a solid segmented rim (`AllyFieldRim*`, the med
  bag's green field too), so they never read as the enemies' orange, rimless fire.
- TORCH: molotov (thrown; a fire circle for `MolotovLifetime` that burns `MolotovBurnPerSec` and slows
  `MolotovMoveSlowPct`), flame turret (150 HP, a `FlameTurretRange` stream at `FlameTurretDps`, 30s), oil drum
  (200 HP drum that blocks like a barricade; when enemies break it, not when it expires, it burns for `OilDrumBurnSec`).
Kills by turrets, fields and claymores pay the owner's kill cash. Abilities are free in a run (the Classes tab `$`
is a label). Cooldown sweeps on the ability tiles. Airstrike was removed. Abilities hold charges (one each; INITIATE
mastery II gives Frag and Claymore a second, `x2` on the tile), recharged one cooldown at a time from the first
use; a spare charge recharging shows a gold bar on the tile instead of the dark sweep, and every clock change floats on
the tile (`+0.5s`, `-0.2s`, `-8% CD`).

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
faster; headshots during Dead Eye put a round back and trim
`DeadEyeHeadshotCdr`), TORCH (burns tick `TorchBurnRateMult` × faster; runs start with Fire Ammo; burning kills trim
`BackdraftCdr` off the Molotov). A tier crossed mid-run applies at once and drops the MasteryUp card under the wave bar
(emblem, rays, sting, `AK-47 · MASTERY II`, the reward; `MasteryUI.lua`, `MasteryPopSec`). Weapon tiles carry a bar with
three pips; the Weapons and Classes detail columns show the shared mastery panel (`MetaUI.masteryPanel`) and the Classes
tab three tier cards; the summary shows the MASTERY line and the
run's tier-ups.

**Dealer break (brief 5, `Dealer.lua`, `DealerUI.lua`).** After every boss wave is cleared: state `Dealer` for
`DealerSec` (no spawns, heat frozen, the clock only stops for a pause), the DEALER phones in (`DealerLine` on the call card), then
a compact card in the top-right stack (`DEALER · 1:30`, TELEPORT any number of times, unanimous SKIP); a stall of three
tables in a half circle (`DealerArcRadius`, `DealerTableAngles`, `DealerPerTable`) round an idling DEALER at
`DealerStallPosition`. Per-player stock: `DealerStock` stands from the pick-3 generator priced as a share of your own
UPGRADE price (Round 25: `DealerCardPriceShare` by tier, the first two each break at `DealerFirstBuyDiscount`; each buy
counts as an upgrade bought), drawn by each client as always-on-top small upgrade cards (icon, big number, price pill) on the same tables; ARMS DROP
(`ShopCratePrice`, a crate at the stall), HEAL ALL (`ShopHealPrice`), REROLL (`ShopRerollPrice`, doubling). The nearest
stand within `ShopReadRadius` swaps its small card for the full pick-3 card on the same spot (`UI/CardFace.lua`,
`DealerCardWidth`; screen-space, so always in front of the other stands) with the effect lines current → new and a
price bar; a prop opens a small panel. F (or BUY) buys.

**Pause (brief 5, `Pause.lua`, `PauseUI.lua`).** VOTE TO PAUSE (P, the PAUSE pill on the wave bar, the scoreboard) in a wave, the
intermission or the dealer break; unanimous, solo at once. Frozen: enemies, damage,
movement and fire, and every timer (bleed, floor guns, crates, side jobs, the vault, the dealer, ability lifetimes and
cooldowns, spawns, the heat clock, the intermission, the run clock). `PAUSED · names` with the time left and two votes:
VOTE TO EXTEND (+`PauseExtendSec`, as often as everyone agrees) and VOTE TO RESUME (everyone; solo at once); it resumes
by itself at `PauseMaxSec` (5 min, plus extensions) after a `PauseCountdownSec` countdown. No limit on how often. Modules join through `Pause.active`, `Pause.delay`,
`Pause.onTick` and `Pause.onResume`.

**Monetization (brief 6).** Every purchase is fake and every one succeeds against `profile.fakeRobux`. Timers that
would be live-ops (season, FEATURED rotation, VIP renewal, Job resets) run on the player's **fake clock**: real UTC plus
`profile.clockOffset` (`Clock.lua`; the debug `+1 day` moves it). Robux prices live in the data files, never in logic:
`Products.lua` (the catalog every real product id maps onto later) is built from `Crates`, `Bundles`, `GoldPacks`,
`BoostDefs`, `ReviveTokenPacks`, `CashPacks` and the pass keys in Config. Every item sold or dropped is new: eight crate
guns with their own silhouettes and accent colors (`Weapons.Look`: MAC-10, Skorpion, AUG, PS90, FAL, Model 1887, Mosin,
1911 Gold), eight crate masks plus VIP / bundle / pass masks on new shapes (`MaskShapes.lua`: goggles, skull, halfmask,
mono, horns, helmet, crown, hood), bundle and pass wraps (`Wraps` now carry rarity, saleType and a material; the Legendary
pass wraps glow), and bundle / VIP / pass poses whose ids live in `Poses.lua` (public Roblox emotes standing in).

- **Fake purchase flow (`Purchases.lua`, `PurchaseSheet.lua`).** One server entry point (`Remotes.Purchase`) and one
  client sheet modeled on the Roblox prompt: item art, name, `R$ price`, `Buy for R$ <price>` (green) and Cancel; confirm
  → a `PurchaseProcessingSec` spinner → the server checks, debits, grants through the kind's handler and writes the
  profile → `<item> purchased!` with a chime and sparks, or a decline. Short of Robux the button reads `Not enough Robux`
  and GET ROBUX sits under it (adds `FakeRobuxTopUp`). The same sheet runs in a run and freezes nothing. Every purchase
  prints `[GHS Purchase] purchase <id> R$<price> balance <after> (<name>, hub | in-run wave N · context)` and lands in
  `profile.purchases`; the debug `Buy log` prints the readout with totals per product.
- **Store window (`Store/StoreScene.lua`, Round 17b).** An overlay window over a dark dim (not a scene), clear of the
  Roblox top bar like every brief 6 screen (`Fx.topInset`). Header: SHOP, Gold with +, LEAVE (Round 18: no R$ balance; a tap outside the window closes it). The
  tabs are a rail on the left (red dot = claimable / new) and the store is one scrolling page of sections in rail order:
  a tab scrolls to the start of its section and the rail's highlight follows the scroll, so nothing is ever hidden. The
  window scales and slides in with an overshoot, cards cascade in 40ms apart. The style bar lives in `Store/Fx.lua` (glow, rays, UI particles, hover lift /
  press scale / disabled dim, count-ups, the store's sound set, haptics) and `Store/Card.lua` (the card with every state:
  rarity glow, dark body, light edge, art on a pedestal with an idle bob, price pill, ribbons, OWNED check).
- **FEATURED (`Bundles.lua`, `DailyShop.lua`, `FeaturedTab.lua`, Round 17c).** One wide featured bundle (it rotates
  every `FeaturedRotationSec` on the fake clock; a VIEW BUNDLE link shows the linked one) with every item laid out on the
  bar (`CLASS + WEAPON + …`, owned ones marked), the `-X%` against buying them apart, WORTH vs the price and BUY right on
  it: no detail sheet and no owned discount (owned items are skipped). Under it the DAILY ITEMS: `DailyShopItems` (6)
  single items from the crate pools and past events, drawn per fake UTC day the same for everyone and sold one by one
  (`DailyShop.PriceByRarity`, products `item_<kind>_<id>`; the server refuses an owned item or one that left the shop).
  Both carry a framed `LEAVING IN hh:mm:ss` countdown. Buying a bundle grants everything not owned in one write and
  plays the stacked reveal (`Store/Reveal.lua`, `BundleRevealStagger` apart). STARTER HEIST (TORCH, FAL,
  2,000 Gold, 5 tokens, 1 Arms open) R$ 399; THE MARKSMAN SET (SHARPSHOOTER, Mosin, Ghillie Hood, Salute, the Woodland
  wrap on the Mosin, 5,000 Gold, 10 tokens) R$ 1,299; HIGH ROLLER (10 + 10 crate opens, a 24h POWER boost, 25 tokens)
  R$ 1,999.
- **GOLD (`GoldPacks.lua`).** Six packs in a 3 × 2 grid, the art filling each card, BEST VALUE on the cheapest Gold;
  buying flies Gold into the header, which counts up.
- **Crates (`Crates.lua`, `CrateOpen.lua`, `CratesTab.lua`, `CrateScene.lua`).** ARMS CRATE (the eight guns, weights
  40 / 30 / 18 / 9 / 3, R$ 129 / 299 / 799) and MASK CRATE (the eight masks, 45 / 28 / 17 / 8 / 2, R$ 99 / 249 / 699). The
  server resolves every open before any animation: rarity by weight (`Crates.odds`, the same table the ODDS panel prints
  with the exact items and `[Legal copy: TBA]`), Epic+ forced on the `CratePity`-th open since the last one (the card
  reads `EPIC+ GUARANTEED IN N`), an item uniformly inside the rarity; an owned item pays `DupeGoldByTier` Gold and
  `DupeMasteryByTier` mastery (the gun's own; a mask's goes to the equipped class). Bundle and pass crate rewards bank as
  free opens (`profile.crateOpens`, OPEN FREE ×N). The opening plays on the CRATE ROOM: the crate drops onto the pedestal,
  rattles for `CrateOpenSec` with rising ticks while its seams glow in the rolled rarity (the telegraph), the lid blows
  with a flash, a shake and the tier's stinger, the item rises on a beam and turns, rays by tier, sparks on Epic+, a
  `CrateLegendarySlowSec` slow motion and sting on Legendary, then the name card (rarity, name, NEW or `DUPLICATE · +◆ N
  · +N mastery`). ×1 ends on CONFIRM; ×N on NEXT or `CrateAutoNextSec`, SKIP from the first reveal jumps to the summary
  grid (rarity frames, dupes, Gold and mastery totals, OPEN AGAIN, DONE). Paid crates never feel LUCKY.
- **Boosts (`BoostDefs.lua`, `Boosts.lua`, `BoostsTab.lua`, `HUD/BoostChips.lua`).** POWER (+`PowerBoostPct` weapon
  and ability damage, also element burns), CASH (+`CashBoostPct` match cash from kills, cash bags and job payouts) and
  LUCKY (in-run rarity rolls, gun crates and upgrade card tiers, read the wave bracket `LuckyWeightShift` rows up),
  30m / 2h / 24h, real-time from purchase, buying an active one extends it. Applied where the value is
  computed (`PlayerState.computed`, the ability and burn damage calls, `Rarity.roll`). Chips (glyph, label, mm:ss) in the
  hub's BOOSTS corner (the `+` steps aside while any boost or VIP chip is up: tapping a chip opens the store) and in a
  run bottom-left, just above the cash row; a chip pulses in its
  last `BoostChipWarnSec` and pops out with a toast on expiry. Gold, XP, pass XP and paid crates are never boosted.
- **Revive tokens (`ReviveTokenPacks.lua`).** `profile.reviveTokens` (fresh: `ReviveTokensStart`). SELF-REVIVE spends
  `SelfReviveTokens`, REVIVE EVERYBODY `ReviveAllTokensPerPlayer` × the party size, both on the press (the SECOND CHANCE
  press too); the buttons show the cost and your count. At zero the button reads GET TOKENS and opens the sheet on the
  5-pack; the bleed keeps running, except inside the SECOND CHANCE window, which holds while any member has a sheet up
  (`RunOverHold`). Packs 5 / 25 / 100 on the BOOSTS tab and the hub's `×N` token chip in BOOSTS; a token chip by the health bar in runs.
- **VIP (`Vip.lua`, `VipTab.lua`).** A fake monthly subscription (`VipPrice`, renewing every `VipPeriodDays` on the fake
  clock, charged again on each renewal; a short balance lapses it). Subscribing grants the VIP Gold Trim mask and the
  Stadium / Big Tilt poses (kept for good, listed in the Locker's OWNED / UNOWNED like everything else), `VipMonthlyTokens` tokens now and per renewal;
  while active: the VIP gold tag on the hub name tag, the party card, the scoreboard, the summary rows (with a pulsing gold
  frame) and crew callouts, a permanent +`VipCashPct` CASH chip in runs (stacks with CASH), the `VipDailyGold` gift chip
  on the hub HUD once per fake UTC day, and the VIP mask's sparkles. CANCEL (fake) keeps
  the cosmetics and stops the perks; a lapsed player sees WELCOME BACK.
- **Battle pass (`PassSeason.lua`, `Pass.lua`, `Pass/PassScene.lua`).** `SeasonLengthDays` seasons from
  `SeasonEpochUtc` on the fake clock (two defined, then they cycle), `PassLevels` levels of `PassXpPerLevel`. Lanes FREE
  (something every level), PREMIUM (`PassPremiumPrice`), PREMIUM+ (`PassPremiumPlusPrice`, includes PREMIUM; from
  PREMIUM it costs the difference) with the hero cosmetics at 10 / 20 / 30. A cell is claimable once its level is reached
  and its lane owned, so a tier bought later unlocks every level already reached (CLAIM ALL). Pass XP: `PassXpPerWave`
  per wave cleared + `PassXpPerBoss` per boss kill at the summary, plus Job rewards; overflow carries; past the last level
  the track keeps going as BONUS levels cycling `PassSeason.Bonus` (Round 18c). Skips ×1 / ×5 / ×10 at `PassSkipPrice` each, any tier. Season end
  auto-claims owned lanes and shows SEASON OVER on the next open. The scene runs on its own PASS STAGE: the season banner
  (level badge, XP bar, ENDS IN, skips) top-left, the premium sell card left, the selected reward in 3D (on the
  mannequin for cosmetics, turning on the pedestal otherwise) with its card (rarity, REQUIRES PREMIUM / UNLOCKS AT LEVEL
  N, CLAIM), the track along the bottom (Round 17c: `PassPageLevels` (4) levels at a time, each a LEVEL band over three
  equal tiles FREE · PREMIUM · PREMIUM+ side by side; the heroes at 10 / 20 / 30 wear a gold HERO frame; lit diamonds,
  claimable pulse, claimed check, padlock, BACK / NEXT, GO TO CURRENT LEVEL). The sell card leads with the chase: the
  level 30 hero big with rays and the 10 / 20 ones beside it (tap to see one in 3D; the stage opens on the level 30
  hero), then GET PREMIUM / GET PREMIUM+ and CLAIM ALL bottom-right. The hub HUD PASS button
  shows the level, a ring of dots for the progress and a red dot when a cell waits; the summary has a PASS XP bar after
  the account XP bar with CLAIM IN PASS.
- **Jobs (`JobPool.lua`, `Jobs.lua`, `RunEvents.lua`, `Jobs/JobBoard.lua`).** Three dailies a fake UTC day (no two of a
  kind; a class Job only for a class you own) and one bounty a week (Monday). Progress comes from the run event bus
  (kills by archetype, elites, headshots, bags, gold banked, best wave, side jobs, vaults, minigames, boss kills for the
  party, revives, the class a run finished as, kills by weapon archetype) and persists until the reset; a quarter crossed
  in a run toasts (`JOB · KILL 60 RUNNERS 30 / 60`) and the scoreboard footer lists the dailies. CLAIM pays
  `DailyXp` / `DailyGold` / `DailyPassXp` (the bounty `WeeklyXp` / `WeeklyGold` / `WeeklyPassXp` / `WeeklyTokens`); one
  Round 19c: the small R in the corner of any unfinished sheet rerolls that Job (`JobFreeRerollsPerDay`, 1, free a fake day,
  then the fake-Robux REFRESH sheet); a claimed Job can be refreshed for fake Robux (`JobPool.RefreshPrice`: NEW JOB R$ 49, NEW BOUNTY R$ 99,
  product `job_refresh_*`) into a fresh one of a kind the board does not have. The rewards show as big icon tiles (XP,
  Gold, pass XP, tokens) and the header frames the countdowns (`NEW JOBS IN hh:mm:ss`, `BOUNTY RESETS IN 2D 16H 42M`).
  The board: the camera pushes onto MARLOW's corkboard (`JobBoardPosition`, a
  beacon that pulses until today's board is opened), header with both reset clocks, three pinned paper dailies filling the board (MARLOW's
  line, progress, rewards, CLAIM), the WANTED bounty poster, a DONE stamp that slams on, claimed
  stubs, CLAIM ALL. MARLOW announces a new board (`JobAnnounceLine`) on the first hub entry after a reset. The summary
  lists the Jobs that moved; a finished one reads `JOB DONE · CLAIM AT THE BOARD` and opens it.
- **In-run upsells.** The cash `+` (cash packs), GET TOKENS (pulses with `TokenNudgeSec` of bleed left and no tokens),
  the token sheet offered to the first bled-out player when nobody in the crew can pay for REVIVE EVERYBODY, the
  dealer's R$ RESTOCK and the cash sheet when short at the stall. Each is a nudge or a button, never a blocking popup.
- **Customization tabs.** Crate, bundle, VIP and pass items show `CRATE` / `BUNDLE` / `VIP` / `PASS` (and `EVENT`) on
  owned and unowned tiles and wraps, with VIEW CRATE / VIEW BUNDLE / VIEW VIP / VIEW PASS deep links (the FAL, the Mosin
  and bundle classes link to their bundle as well). Only Direct items are Gold-priced.

**Crew call / side job.** A call from MARLOW on wave 1 and every `SideJobEveryWaves` (2) waves, kind rolled from
`SideJobKindWeights` (equal odds; the Safe dial is weighted 0 since it is the vault's own beat): "VAULT PING" (hack
the terminal, hold F), "HOLD THE FLOOR" (stand in the circle for `SideJobCaptureSec`; progress pauses when nobody is
inside, a green disc fills on the floor), one of the minigames (the beacon carries an OPEN prompt; a validated done
finishes the job, fails can retry until the timer; Round 19c adds Cut, CUT THE CHAIN), SILENCE THE ALARM (Round 19c:
every alarm in the building rings and strobes and the horn plays until someone shuts the ALARM PANEL off; Round 19d:
F at the panel opens one of `AlarmJobMinigames` (Round 19e: Keypad, Freq, Charges, Hotwire), a random pick per job
named on the card's second line; expiry silences it without the pay; THE BANK's first side job of a run is always
SILENCE THE ALARM on the Keypad: `BankFirstJobKind` / `BankFirstJobGame`), or CRACK THE VAULT (above; forced every `VaultJobEveryWaves`
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
SHOP icon tile left-center (amber, the store window), PASS and JOBS stacked right-center to mirror it, Gold pill
bottom-left with `+` (the store's GOLD tab) and INVITE FRIENDS under it (does nothing), the dock bottom-center (WEAPONS ·
CLASSES · AVATAR as 92px icon tiles with labels under them, reference style), BOOSTS bottom-right (the live boost chips,
VIP's CASH chip and daily gift, the revive token chip reading `×N` where a timer would be, a `+` into the BOOSTS tab), the compact queue card under PLAY
while in a party, and the nameplate above every character in the hub (Round 19n, `Nameplates.lua`): the level badge (the level
card's emblem with the number in it) over the plate's left end, the name in caps with a gold VIP tag, `★ WAVE 14 · BANK`
under it, and a class-coloured block with the class pictogram on the right. The Roblox name hides under it.
Top-left stays empty for server chat.

**Queue zone and Create Match (`Queue.lua` / `QueueUI.lua`, GDD_7 Hub → Queue Zones minus the teleport).** Walk into an
empty zone (or press PLAY) → the Create Party card (reference layout: blue header bar with X, Select Map thumbnails
with COMING SOON fillers, Difficulty segment NORMAL / HARD / NIGHTMARE (each a `QueueDifficulties` row: enemy `hpMult`, `dmgMult`, wave size
`budgetMult`, Gold `goldMult`) and a bonus row showing the chosen row's Gold and enemy multipliers and your top wave on it, Party size 1–`MaxPartySize` segment, a row of purple boost chips that toast `PHASE 4`, CREATE PARTY;
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
goldEarned, bagsCollected, goldBanked, xp, timeSurvived }`, `pendingPayout`, `version`; v3 (brief 6, migrated from v2
with the fresh defaults) adds `fakeRobux`, `reviveTokens`, `boosts[id] = { expiresAt }`, `vip { active, since,
renewsAt, ever }`, `vipGiftDay`, `pass { season, level, xp, tier, claimed["L7"], seasonOver }`, `jobs { dailyResetDay,
weeklyResetWeek, daily, bounty, rerollUsed, announcedDay, boardSeenDay }`, `cratePity`, `crateOpens`, `purchases`
and `clockOffset`; v5 (brief 9) adds `skills { owned, seen }`; v6 (brief 10) adds `streak { day, lastClaimDay,
vipRestoreDay, vipRestoresUsed }` and `dailyCrate { unlockedDay, claimedDay, everOpened, rerollsToday, rerollDay }`
(a v5 profile starts the streak at day 1 today with the crate locked today). A fresh profile
has `StartingGold` (10,000), one gun of each archetype at level 0 (`Weapons.DefaultOwned`: M1911, UZI, AK-47,
SPAS-12, AWP, M249; older stores are topped up on load), the M1911 as starter, INITIATE and the plain mask. `Prices.lua` is the only
price file (`weaponUnlock`, `weaponUpgrade`, `class`, `ability`, `mask`, `wrap`, all 100). The whole profile rides in
`StateSync.profile` so every screen reads from one place. Hat, hair and face accessories are removed on join; the
equipped mask (head recolor plus a visor or bandana Part welded to the head) shows in the hub and the run.

**Payout (GDD_7).** At the summary each party member earns `GoldEarned = (Σ over cleared waves of (GoldPerWaveBase +
GoldPerWaveAdd × (wave − 1)) + GoldPerObjective × side jobs) × goldMult` (the difficulty's) plus their `SideJobGold` per job, paid once
into the profile (it accumulates across REVIVE EVERYBODY saves; players who left earn nothing). `topWave` updates when
the run beat it with a `★ NEW PERSONAL BEST` callout on the summary; lifetime kills, matches and gold accumulate. The
summary's GOLD EARNED headline is this number, and the hub Gold row shows the new balance on return.

**Customization scene (`MetaScene.lua`, `src/client/Meta/`).** Opened from a dock tile or a station prompt on that
tab. Movement is hard-locked while it is open (controls off, root anchored locally, walk speed 0; the same lock holds
the Create Party card, which instead closes when you walk off the pad). The scene drives the camera itself every
frame (`MetaCameraTweenSec` ease): it stands `MetaCameraDistance` (7.5) in front of the character and
`MetaCameraSideShare` of that to the character's left, `MetaCameraHeight` up, aiming `MetaCameraAim` (1.6 studs)
below the character's center, so the avatar fills the left third with its head near the top of the frame, facing the
camera and playing the equipped class's idle (`ClassIdleAnimationId`); the hub HUD hides and your own nameplate is
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

**Minigames.** Seven games, played from the yard props for testing and from side job beacons in the arena. One client
module per game under `src/client/Minigames/`, sharing `Frame.lua` (centered panel `MinigamePanelPct` of the shorter
screen edge wide, crew-call frame style, title, hint, elapsed timer, X / Esc cancel, damage shake, downed = fail,
haptics on hits and locks, closes as a cancel past `MinigameCloseDistance` from the prop). On DONE or FAILED the gun
and camera come back that frame and the panel slides off over `MinigameExitSec`. The server (`Minigames.lua`) owns
the session: the prompt opens it, the client sends done / fail / cancel with its miss count, anything faster than
`MinigameMinSec[name]` is logged as a fail, and every close prints
`minigame <name> tier <n> done in <sec>s, <fails> fails` (or `… fail|cancel <sec>s <misses> misses`). The debug panel's
`Stats` button prints per-game averages. Tier (1–3, `MinigameTier`) is session-wide from the tier pad (brief 8: in the range) or the debug panel:
Lockpick (tap: zone width and points needed), Hotwire (drag: wires; a COLORBLIND toggle on the panel, saved to the
account as `options.hotwireSymbols` via `SetOption`, swaps to the Okabe-Ito palette and letters each wire and socket),
Keypad (tap: digits; typing early hides the code), Arm charges (tap: caps), Safe dial (drag: numbers; a number only
counts when reached turning the asked way, and tumbler clicks rise near it: `SafeTick*`), Frequency jam (drag: locks
and slider range; the slider spans a fixed band round `FreqCenter`, targets move, a lock drops the hold). Round 19c: Bolt cutter (`Cut`, hold and release: hold to squeeze, let go with the needle in the green band to cut a
link, squeeze to the top and it slips; links `CutLinksByTier`, band `CutBandByTier`, faster per link) on D2's chains and
the CUT THE CHAIN side job.

**Downed, revive, game over.** 0 HP → `Downed.down`: crawl speed and animation (`DownedAnimationId`), no jump, no
abilities / buys / swaps, enemies drop you from targeting, the health bar becomes a red bleed bar from
`BleedOutSec` (15s) with GIVE UP (bleed out now) and SELF-REVIVE (brief 6: spends a revive token; GET TOKENS at zero)
above it, a red-cross marker with name
and seconds over you for teammates. A standing teammate within `ReviveRadius` holds F for `ReviveHoldSec` (brief 5:
a centered bar under their crosshair, `REVIVING NAME` with the seconds left, ticking every `ReviveTickSec`, green
`REVIVED` on completion, a red snap-back on release, the crosshair ring kept; your bleed bar gains a green second fill
with `NAME IS REVIVING YOU` and your marker shows the same fill to the party; the bleed timer stands still for the
length of the hold, `RevivePausesBleed`, and the marker's seconds turn green) → you stand at `ReviveHPPct` with
`ReviveInvulnSec` of invulnerability, a green pulse, the camera easing up from the floor and a `REVIVED BY` toast for
both. Ally callouts (`Callouts.lua`, sent by `AllyCallout.lua`): downed, revived and bled-out players radio a line with their
Roblox headshot to teammates (`CalloutSec`, red frame; Revive Everybody gold to all), and (Round 16) gold lines for the
boss's last hit, a Legendary from a crate, a `CalloutMultiKill`+ frag or claymore and a mastery tier; all queued
behind MARLOW and the boss cutscene. A finished side job's NICE WORK card is the completer's (headshot, name,
`doneByText`); NPC cards (MARLOW, DEALER) show a dummy avatar bust (`Lines.portraits`), also the fallback for a
missing headshot. Bleed-out removes the character and opens spectate (camera orbits living teammates, name
and HP top-center, REVIVE EVERYBODY (brief 6: one token per party member) stands everyone downed or bled out up where they fell,
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

**THE BANK (brief 7).** A second map beside the arena (the arena stays exactly as it was, as the test map). The
builder's place is `src/map/Bank.rbxm` (Rojo: `Workspace.Bank.Geometry`), baked at `BankOrigin` (0, 0, -1000) so it
never overlaps the arena or the yard, even in edit mode; changing `BankOrigin` moves the whole model at load. Its
nodes are invisible parts in `src/map/Bank.nodes.model.json` (`Workspace.Bank.Nodes`, one subfolder per type, each part
tagged `GHS_<Type>`): zones, doors, spawn boxes, bag spots, job spots, boss walls, dealer spots, the van, the lineup, the
hatch and the vault room, with their numbers as Attributes. `MapLoader` reads the parts at load (one `[GHS Map]` line
per node, one `[GHS Map] ERROR` per bad reference; a map with errors still loads unless `MapLoaderStrict`) and hands
THE BANK to `Room.forMap("TheBank")`, the per-map view every module now reads (the arena's markers are point-sized
spawn boxes in zone `arena`, its spots, pillars, closet vault and dealer position wrap the same way). `Ground.lua` gives
the floor under a point: bags, crates, discs, fire, bodies, guns, the dealer stall and placeables land on the floor
they are over (the street is y 0.5, the lobby 5.5, the mezzanine 36.5, the vault level -37.5, the tunnel -24.5).

- **Zones.** Street (grass, road, steps, side pavements), Lobby, Upper floor, Back of bank (passages, teller area,
  side halls, cross corridor), Vault stairs (both stairwells and the landing room), Vault, Tunnel (server room, ramp,
  ladder, the hatch top). The crew zone (most standing players, ties deeper) is recomputed every `CrewZoneSyncSec`,
  logged `[GHS Zone] wave N crew <zone> for <sec>` on each change and shown on the scoreboard header (`WAVE 7 · LOBBY`).
  The zone graph is each Zone node's `Links` attribute (`lobby@D1`: neighbour and gate).
- **Doors.** `Doors.lua` dresses every Door node from its Size and `DoorStyle` under `Workspace.Bank.DoorProps`:
  D1 front doors (panel), D2 stair chains (both stairs), D3 shutters (both passages under the stairs plus a grille over
  the teller counter: they open the back only), D5 stairwell chains (Round 19d: across both vault stairwell heads,
  their `SideDepth` walls fencing the railings down the opening), D4 the asset's wheel door onto the vault and its
  server door; each has an invisible blocker (a
  `Door` PathfindingModifier), a sign `UNLOCKS · WAVE N` (`DoorSignText`; D4 `UNLOCKS · VAULT JOB`), an amber ▲ beacon
  through walls and a LOCKED prompt. Trigger waves `DoorTriggerWave` (Round 19g: D1 2, D2 5, D3 8, D5 12; D4 is the vault draw; the config overrides the
  nodes' own TriggerWave). In the
  intermission before its wave a door rides the crew call as kind `door`: MARLOW's line, blue beacons, the guide (Round 19g:
  floor chevrons from every standing player re-planned every `DoorGuideRefreshSec` for `DoorGuideSec` or until it
  opens, the loud beacon, a blue ▲ at the screen edge while the door is off screen), the pill `OPEN THE BANK` with an ∞ clock. It supersedes that wave's side-job draw and keeps
  the slot until done; a ticking job finishes first; doors due together queue by Priority. Hold F at either part of a
  group for `InteractTime` (`OPENING · 2.1s` bar for the holder, `OPENING` tag for the crew; the fill keeps
  `DoorHoldSec` after a release). Done: the prop breaks (chain falls, shutter rolls up, doors swing, the wheel spins and
  swings), flash and `DoorOpenShake`, `DoorOpenCashReward` to everyone, the opener's NICE WORK card and
  `<NAME> OPENED THE <LABEL>`, HeatJob at the wave end, a Jobs count, `ZoneOpenCashBags` / `ZoneOpenGoldBags` on the
  opened zone's spots, and its boxes and spots come on. `[GHS Door] <group> trigger wave N` / `opened wave N by <name> t=`.
- **The glass offices (Round 19f, `Offices.lua`).** Four rooms behind blinds walls with a double glass door (the
  pair off the back corridor, the pair at either end of the upper floor) are Office nodes: a room volume `<id>`
  (`Label`, `Zone`) and its door box `<id>_door`; at load every geometry part inside the door box is the door (2
  leaves, handles, frame bars, closers) and the wall's blinds mesh (it hangs across the doorway) goes with it. RAID
  THE OFFICE is a side job kind (`SideJobKindWeights.office`, from `OfficeMinWave`, only for an office in an open zone
  that is not cooling down): MARLOW names the office and how the door goes, the beacon stands `OfficeFrontStuds`
  outside its door, and F opens one of `OfficeMinigames` (Lockpick, Hotwire, Charges, Cut). Done: the job pays as
  usual and the office blows open (the door and blinds vanish, glass shards fly out, a thump and a shake),
  `OfficeCashBags` + `OfficeGoldBags` drop across its floor and a marker at the door counts `OfficeOpenSec`; then
  the room's alarm rings `OfficeGasWarnSec` (marker red, `OFFICE GAS IN 8s · GET OUT`), gas fills it for
  `OfficeGasSec` (`OfficeGasDps`, the gas tint), and it seals: anyone inside lands `OfficeEjectStuds` outside the
  door, the bags left inside fizzle, door and blinds come back, and the office is drawable again
  `OfficeCooldownWaves` later. A job that runs out frees its office. `[GHS Office] …`.
- **Lockdown gas (Round 19d, `ZoneGas.lua` mode force).** A called door still shut `DoorForceAfterWaves` (2) waves
  after the wave it was called for (D1 called for wave 2 → wave 4) floods the building: `DoorForceDelaySec` into the
  wave the alarms ring and the toast counts `LOCKDOWN · GAS IN 10s · OPEN THE BANK`, then green gas fills every open
  zone except the ones that door opens (never the vault or the tunnel) at `DoorForceGasDps`, until the door is open
  plus `DoorForceLingerSec`. The whole time: floor chevrons re-planned from every standing player to the door every
  `DoorForceArrowEverySec`, the door's loud beacon, a red pinned line under the pill (`OPEN THE BANK` /
  `ONLY CLEAN AIR IS PAST THE LOBBY`) and a blue ▲ at the screen edge whenever the door is off screen
  (`LockdownUI.lua`). It waits out boss waves and the vault window, and a running zone gas yields to it.
  `[GHS Zone] lockdown …`.
- **The vault on THE BANK.** CRACK THE VAULT keeps its shell. It is drawn only once D5 has opened the stairwells (Round 19d; D3 before); F at
  the wheel door opens the Safe dial; the wheel spins `VaultWheelSpinSec`, the vault and server doors swing in over
  `VaultDoorSwingSec`, the room's lights come on, the burst drops on the vault room's spots, the hatch opens (and stays
  open: `HatchOneWayAfterSeal`) with a blue TUNNEL beacon, the pill reads `TUNNEL OPEN` (`VaultPillTunnelText`) and the
  tunnel's boxes and spots come on: the map is a ring for `VaultOpenSec`. Gas and the seal use the VaultRoom volume
  (the gassed room carries the `VaultGas` path cost); the seal closes both doors only when nobody is inside.
  `[GHS Vault] window used <sec> exit <stairs|tunnel|none> <name>` per member.
- **Spawning.** Boxes are on when their `RequiresDoor` is open (the vault's vent only while it is open, the hatch box
  once the hatch has opened), allow the rolled archetype and do not stand inside the crew's zone
  (`SpawnNeverInCrewZone`; a box behind a fence or a window stands outside every zone, so it feeds its zone while the
  crew holds it). Weight = `Weight` × proximity × `ZoneDistanceMult` ^ hops from the crew zone along the open graph. A
  point in plain sight of a player inside `SpawnLosBuffer` re-rolls once; elites take the least-used box
  (`EliteLeastUsedBox`). `[GHS Spawn] wave N box <name> contact <sec>` per box per wave, `WARN no eligible box`.
- **Pathfinding** (`EnemyPath.lua`, every map). Direct within `DirectRange` with a clear walk (the arena is nearly
  always this), else `PathfindingService` with `RepathDistance` / `RepathSec` re-plans, a `PathComputesPerSec` budget,
  routes shared per zone pair for `PathCacheSec`, `PathAgent` sizes per archetype, placeables as a `Structure` cost
  (`PathStructureCost`), the ladder as a `PathfindingLink` that lifts enemies over `LadderClimbSec` (players climb the
  truss), stuck → sidestep at `StuckSec` → own spawn box at `StuckTeleportSec`, three failed computes → direct for
  `PathFailDirectSec`. TITAN's wide agent keeps it out of doorways it does not fit: it holds at the opening and Volleys.
  `[GHS Path] wave N computes/s fail stuck teleports`. `PathfindingEnabled` false is the Round 18d walk.
- **Per zone.** Bags trickle onto open zones' spots (`BagOtherZoneMult` outside the crew zone, Gold spots for gold);
  side jobs draw a spot in an open zone and roll their kind from its `Pool` (`JobOtherZoneMult`), never in a
  `SideJobOutsideZones` zone (the street) once any zone inside the bank is open (Round 19d); TITAN blows the crew
  zone's BossWall (the farthest when it has several; none → the nearest zone's); the dealer stall stands on the crew
  zone's DealerSpot, opening along its facing; crates without a spot land on a free spot in the crew zone.
- **Card, runs, profile.** The Create Match map row lists ARENA and THE BANK (`Maps.lua`; `DefaultMap` THE BANK, colour
  tiles until thumbnails land, 88 × 64 swiping tiles on a phone) and the party's pick shows on the queue board, the
  compact card and the summary. A run on THE BANK drives the van in to the Van node on the grass, lines the crew up
  facing the bank and ends on the Lineup node (the camera shots turn with the line); members return to the hub spawn.
  Records are `<mapId>:<difficulty>`; profile v4 moved the old `TheBank:*` (the arena's placeholder id) to `Arena:*`.
  The hub nameplate shows the best top wave across maps with the map's short name (`★ WAVE 14 · BANK`).
- **Audio (Round 19d, every map).** Sound effects play through an SFX SoundGroup and the soundtrack through a Music
  one (`SfxVolume`, `MusicVolume`). `UI.sound` / `UI.soundAt` level each `Theme.Sounds` key (`SfxGain`), spread its
  pitch a little (`SfxPitchJitter`) and cap copies of one clip at `SfxMaxVoices`. Real library clips (ProSoundEffects
  and Roblox's UI pack, all checked public) for the gunshot, mag out / mag seated (`ReloadSeatShare` through the
  reload), cash register / coin jingle on bags, a body thud under kills, glass on a window, a gas hiss, the alarm
  buzzer, the shutter roll, a bullet whiz on a near miss (Round 19e: no explosion or chain-crash clip anywhere; blasts
  and doors keep the soft bass thump); `swoosh.wav` (blocked by Roblox, so every swap was silent) is a Roblox whoosh.
  The lootbox (Round 19e): a rising swell and coins as the crate pops, a prize-wheel clicker climbing as the reel
  slows, a bell-ding arpeggio with one note per rarity tier on the land (a falling shimmer from Rare, wind chimes from
  Epic, the victory sting on Legendary) and a pop as the gun flies out; the store's crate scene and reveals share the
  arpeggio, the clicker and the pop (`Store/Fx.lua`). `Music.lua` follows the run: hub, run (Round 19e: one track
  carries on through waves, intermissions, the dealer, alarms and gas; effects play over it), boss (TITAN alive, the
  one deliberate shift), summary, silence on the run-over stamp; tracks from `MusicTracks` (APM library music, the run
  list in the lobby tracks' nu-jazz / funk vein) crossfade over `MusicFadeSec`, resume within `MusicResumeSec`, move
  to another track when one plays through, and duck to `MusicDuck` under the boss cutscene. Every clip is preloaded at
  join.

**The warehouse hub (brief 8).** The generated yard is gone; the hub is the builder's warehouse, `src/map/Hub.rbxm`
(`Workspace.Hub.Geometry`, `tools/importhub.luau`: the helicopter dropped by `HubImportDrop`, the rigs' Animate
scripts stripped, the parked van named `Van`, everything moved so the floor star sits on `HubOrigin`), plus its
nodes (`src/map/Hub.nodes.model.json` → `Workspace.Hub.Nodes`, the brief 7 spec: Spawn, QueuePads ×4, Stations ×3,
Board, Van, GarageDoor, RangeDoor, Range, Dummies ×3, PropSpots ×7, TierPad; brief 10 adds DailyCrate). `HubMap.lua` reads them (one
`[GHS Map] hub …` line each, `ERROR` lines for a broken one) into `Room.forMap("Hub")`; debug Show nodes draws
them (Range is a volume, off by default like Zones). The arena is a standalone room now (no yard, no door): its
`Workspace.Room.Nodes` hold a Van (`DriveIn` 50) and a Lineup node just inside the south wall.
- **Concurrent runs (`Runs.lua`, `Run/`).** Every run-scoped server module lives in `src/server/Run/`; `Runs` clones
  that folder once per live map at startup (`Run_Arena`, `Run_TheBank`), so each map has its own World, spawner,
  heat, bags, boss, dealer, pause, doors, vault and run loop (`Run/Main`, the old GameLoop body). The `Run/` template
  is the hub slot (World.state Hub forever; the range runs there). `RemoteRouter` + `Run/SlotRemotes` send each
  client call to the player's slot (the one whose party holds them, else the hub); `PlayerState` syncs each player
  from their own run's World; run events, line-ups, votes, the pause and the scoreboard go to that party only. Shared
  modules (profiles, store, pass, Jobs, Hub, Queue, PlayerState) stay single. Runs on different maps overlap freely;
  the same map is capped by `MapInstancesPerMap` (1: the geometry is one copy; above 1 is logged and capped).
- **Four queue pads (`Queue.lua`).** One party per pad (the Round 11 zone logic per pad): the billboard over each
  pad's back edge reads `PAD 2 · THE BANK · NORMAL`, the slots, the countdown, then `MATCH IN PROGRESS · WAVE 7`
  (the run's wave). A party whose map is busy waits on its pad with `MapBusyText` (`MAP BUSY · <name> IS INSIDE`)
  and starts the moment the map frees (`MapBusyAutoStart`; false: its countdown restarts). The party card under
  PLAY and the join toasts name the pad; PLAY AGAIN re-forms the party on its pad. Logs: `[GHS Queue] pad N create
  <map> <difficulty> owner <name>` / `start` / `busy-wait` / `reset`.
- **Booths, board, garage.** OPEN at each booth's counter edge (the Station node) opens the customization scene on
  that tab. Round 25: each booth is kept by a named R15 NPC the server builds from an avatar (`BoothNpcs`: DUKE the
  gunsmith, SABLE the trainer, NOVA the stylist; Hub.buildBoothNpc), with MARLOW sharing their tag: a close-range
  plate that fades with distance (`BoothNpcTagFadeNear` / `Far`) and hides behind menus (BoothMannequins.lua). MARLOW's board is the
  warehouse's bulletin board (the Board node): a beacon strip over it pulses until today's board is seen, F (OPEN)
  opens the Jobs board with the camera push. The garage and the range door are roll-up shutters the hub builds in the
  asset's openings (the garage down, the range up: `RangeDoorOpen`; the RANGE prompt at the door is only a sign).
- **Run start from the hub (`Hub.depart`).** `HubDepartSec` (2.5) before the map's drive-in: the party fades into the
  asset's van in the garage, the shutter rolls up (everyone in the hub hears it), the van pulls out `HubVanDriveStuds`
  with a dust ring under a short chase cam (party only), then the cut to the map's own drive-in (`IntroSec` and
  `RunStartBeats` now count from the cut). The map's van is a copy of the hub van riding in `DriveIn` /
  `VanDriveInStuds` from behind the map's Van node. The garage rolls back down `GarageCloseSec` after the van has gone
  and the van is parked again; two parties leaving close together keep the door up. Run end: TO LOBBY lands on the
  star, PLAY AGAIN on the pad.
- **The training range (`Run/Range.lua`, the hub slot).** Step over the bay's threshold (the Range node) and the server
  arms you: the starter gun at Common at its Armory level with a full mag, all three abilities (`RangeAbilities`);
  the HUD goes to the range layout (`HUD.setMode("range")`: held slot, ammo, crosshair, hit markers, the camera lock,
  the ability column, the mobile fire / ADS / reload buttons; no buy column, wave bar, heat, cash, Banked or boost
  chips). Step out: the gun is stowed, your placeables and fields go, HP refills. Nothing in the range scores (the hub
  slot pays no cash, counts no kills, feeds no Jobs or mastery) and nothing reaches a hub player outside it. Three
  dummies at the far end face the door (Enemy rigs flagged `dummy`: every hit flinches, sparks, shows its number and
  the element statuses; they never die, move or attack), each with `DMG 1,240 · DPS 312 · HS 40%` over it (total
  since reset, DPS over `RangeDpsWindowSec`, headshot share of bullet hits) and a RESET prompt (R) on its sign. The
  middle one is the plated sponge (`DummyHeavyPlates`, elite look): plates fly off at the Heavy's shares of
  `DummyHp` and regrow `DummyPlateRegrowSec` after the last one fell. The seven minigame props and the tier pad stand
  along the bay's north and south walls and work as before. Debug Spawn at range puts in a moving target that only
  goes for players in the range, is pulled back if it wanders out and is cleared when the range empties. Logs:
  `[GHS Range] <name> enter / leave / reset dummy N`.

**The Skill Web (brief 9; `Skills.lua`, `SkillLayout.lua`, `SkillService.lua`, `client/Skills/SkillScene.lua`).**
Horizontal progression beside the Armory: 90 one-time nodes bought with Gold (never R$) on a regular hex grid of
91 hexes, START at the centre (Round 26c: START is bought first, `SkillStartCost`, UNLOCK SKILLS, and its purchase
plays the web's unlock sequence) and five rings (6 / 12 / 18 / 24 / 30). Six branches clockwise from the top, each a
60° wedge holding N nodes in ring N (15 a branch): DAMAGE · SURVIVAL · SPEED · CASH · LUCK · ARSENAL.
`SkillLayout` places every node deterministically (axial coordinates; wedge k owns 60k..60k+60° clockwise from
straight up, a ring's cells in the wedge sorted by angle, slot j takes cell j); positions are never hand-authored and
the server validates adjacency from the same table. The node values are `Config.SkillNodes` (per branch, per ring,
in slot order, `{ stat, value }`); ids (`<branch>_<stat>_<n>`, e.g. `damage_crit_2`), names (CRIT CHANCE II, a numeral
only when the stat repeats in its branch), pictograms and the effect line come from `Skills.lua`. A node can be
bought when one of its six hex neighbours is owned (START counts; seams between wedges are real neighbours) and the
Gold covers its cost: the ring's `SkillCostByRing` base (500 · 1,500 · 4,000 · 10,000 · 25,000) x the stat's
`SkillCostByStat` weight x `SkillCostRepeatStep` per earlier node of that stat in the branch, rounded (Round 26b: ring 1
runs 350–650, so the choices are never all equal; about 1.2M for the whole web). Nothing is a rule
change: `Skills.modifiers(owned)` folds the owned set into one flat table that the run start (`Hub.beginRun`) and
the range entry arm on the player (`PlayerState.armSkills`, logged `[GHS Skills] <id> applied <stat> <value>` per
node and `[GHS Skills] <player> applied N nodes (run start): damage +9% hp +16% …`); the hub runs on zeros. The
hooks read one field each: damage, type damage, mag %, flat rounds and reload add to the Armory level's own
multipliers in `Weapons.atLevel` (so the weapon card, DPS and floor-gun tags show them); max HP, move speed, regen,
crit and headshot sit under the run's upgrade multipliers (`Stats.compute`); ELITE / BOSS DAMAGE on every gun and
ability hit on an elite / TITAN (`Combat.dealDamage`, `Abilities.hitEnemy`); ABILITY DAMAGE on ability hits;
COOLDOWN on the ability base before the run's ABILITY COOLDOWN; TOUGHNESS before armor soaks; ARMOR flat points
(full at the run start like a new card) with ARMOR RECOVERY on the refill delay; REVIVE SPEED on the reviver's hold;
LAST STAND on the bleed-out; QUICK HANDS on door holds (server) and the side job HACK prompt (each client shortens
its own prompt: `QuickHandsBase`); MAGNET / FAST HANDS on the bag start reach and fill; BAG VALUE on each member's
cash-bag share; SEED MONEY on the starting cash; HAGGLE on every dealer price; FENCE on the banked Gold this player is
paid; CARD / DEALER / CRATE LUCK move `LuckOddsStep` (3%) of the tier weights per node off the lowest tier with
weight onto the higher tiers that have some (`Rarity.applyLuck`: the pick-3, the dealer's stock, the in-run gun
crate; never the store's crates). Profile v5 stores `skills = { owned, seen }` (START implicit; a respec is a
wipe). `SkillService`: `Remotes.SkillBuy(id)` validates (known, not owned, adjacent, Gold, hub only, rate
`SkillBuyRateSec`), charges through `Profiles.tryCharge` like an Armory level, logs `[GHS Economy] <player> spent N
gold on skill <id>` and replies with the owned set and balance; `SkillSeen(ids)` records the pulse-once set.
The scene: a full-screen overlay over the blurred hub (the hub HUD and your nameplate hidden, movement locked):
SKILL WEB and the branch legend top-left (the hovered / selected branch lit; pictograms only under 720 px wide), the
Gold pill top-right (its + opens the store's GOLD), BACK bottom-left. Hexes are drawn from frames (three rotated
bars each, an edge layer and a fill): owned = the bright branch colour with lit white edges to owned neighbours;
affordable = a dark shade of the branch colour (the type reads without the text), the price in the Gold style, a slow
edge pulse; short = the same with a red price, no pulse; two steps out = a dim grey hex with ? (it never lights the
legend); anything farther is hidden, so the web grows as you buy (Round 26b). START is a larger gold hex with
the star. A hex that became affordable since the last visit pulses once on open (`SkillNewPulseSec`). Pan by drag
(mouse, touch, right stick), zoom by scroll / pinch / triggers between `SkillZoomMin` (never above "the whole web
fits") and `SkillZoomMax`; it opens centred on START at `SkillOpenZoom` (all the way in; a hex is `SkillHexPx`
wide at zoom 1, at least 56 px on a phone); double-tap the backdrop to recentre on START. Tap a hex → it glides to the
centre of the space beside the sheet, and the sheet docks right as a compact card (Round 26b; vertically centred,
bottom-right on a phone at 40% of the width): branch tag and RING N, the pictogram well (dark branch shade, bright once
owned) beside the name and a plain-language effect line, then BUY with the price on it / NOT ENOUGH GOLD · NEED N
MORE (the store's refusal tick on a tap) / OWNED / LOCKED · UNLOCK A NEIGHBOUR. LUCK lines say what gets rarer and
where (pick-3 cards, the in-run dealer, in-run gun crates; never the SHOP's crates). BUY → the hex wipes in with the loot
ding and a small burst, the edges to owned neighbours light one by one, the newly revealed neighbours pop in, the Gold
counts down, the sheet flips to OWNED and stays up; a refused buy shakes the Gold pill. Breadcrumbs: the SKILLS tile
(directly under SHOP, hub only) wears a red badge with the number of nodes affordable right now; it pulses once on
the first hub entry while you own only START, and MARLOW's daily announce card adds "Planning board's open. Spend
some Gold on yourself." (`Lines.skillsIntro`) while the web is empty; the summary adds `N SKILLS AFFORDABLE` under
the Gold gain once the count-up lands. `SkillsEnabled` false hides the tile and zeroes every modifier. Debug (PROFILE
group): Unlock all skills, Reset skills, +10,000 Gold, Grant (a branch row, then ring 1–5: the ring's first unowned
node of that branch); Stats prints the owned count per branch and the modifier table.

**Retention (brief 10; `Streak.lua`, `DailyCrate.lua`, `StreakTrack.lua`, `Catalog.lua`, `client/Retention/`).** Two
retention pieces that do not overlap: something to collect on arrival (the login streak) and something to earn by
playing (the daily crate), plus the PLAY line that surfaces the first run of the day. Both run on the brief 6 fake
clock (`Clock.day(Clock.fake(os.time(), profile))`), never real time, so the debug `+1 day` tests everything; the
FIRST HEIST OF THE DAY ×2 XP (`profile.lastHeistDay`, Progression) moved onto the same fake day.
- **The login streak.** A 28-day track in four 7-day sets (`Config.StreakRewards`, a list of rewards per day); Round
  27d: day 1 is a crate and a crate comes every 2-3 days, and every crate is the daily crate (guns + masks from
  `Catalog.dailyPool`, the same crate scene) at the week's tier, rising like the level bands
  (`StreakCrateTierByWeek`: week 1 BASIC, 2 GOLD, 3 DIAMOND, 4 ELITE; `DailyCrate.rollStreak`); day 7 / 14 / 21 / 28
  are the big ones (a RARE+ daily crate, 1,000 pass XP + 1,000 Gold, an EPIC+ daily crate, an EPIC+ daily crate +
  1,500 Gold); after day 28 the next claim is `StreakLoopFrom` (22), so week 4 keeps paying. `streak.day` is the
  track position, `streak.lastClaimDay` the fake day of the last claim: claimed today → nothing; claimed yesterday →
  the next day; never → day 1; older → lost. The modal (`StreakModal.lua`) opens on the first hub entry of a fake day
  (on join, back from a run, or when the fake day turns while you stand in the hub) before anything else, and (Round
  27b) once at the start of every session even with nothing to claim (`StreakOpenEverySession`): MARLOW's announce
  waits on the server (`Jobs.hold`) and plays once the day is claimed, the SKILLS first-time pulse waits on the
  client. Round 27c look: the house's premium window (near-black panel, sharp corners, condensed caps, a gold edge)
  in the reference's format: DAILY STREAK with a small IN A ROW counter (`streak.count`) in the header, then one wide
  row of reward cards (`DAY N`, the reward's art big, the amount: `300`, `×2`, `RARE+`, `30M`); claimed days dimmed
  under a green tick; today with a gold edge, a soft breathing glow and a TODAY tab; the big days gold-tinted with a
  gold edge; day 28's Gold as a chip. The current day (tomorrow, once today is claimed) is always in the centre. The
  row runs from the start of this week to its end plus `StreakPeekDays` (3, fogged), then a MORE card (no infinite
  list); drag it sideways with the mouse or a finger (the wheel does nothing; a soft give at the ends); after a claim
  or a skip it glides to centre the new day. CLAIM under the row. An unclaimed day cannot be dismissed (the X, Esc and B
  claim; movement is locked and the dim takes every tap). A claim dings and ticks today's card with a burst; a crate
  reward rolls on the server (`CrateOpen.open` with the reward's `floor`) and opens in the crate room inside the
  claim (nothing is banked); then the row re-renders on the claimed view: today ticked and tomorrow's card lit green
  with its countdown on the top edge (`21H 06M 12S`) and GET IT NOW · R$ 29 (`StreakSkipPrice`, product
  `streak_skip`, `StreakSkipsPerDay`, 0 = always offered): it claims tomorrow's reward now and steps the track and the count on (today
  stays claimed, so tomorrow's claim is the day after). With no skip left the button is the countdown; the X
  closes. Gold, pass XP and the CASH boost land on the profile (the Gold pill and the boost chips show them). Lost:
  STREAK LOST on a darker panel, today's card red with a RESTORE tag (the day today's claim would have been),
  `RESTORE · R$ 49` (`StreakRestorePrice`, product `streak_restore`; keeps the day and the count and claims it) and
  START OVER (Round 27g: resets the streak; the row rolls back to day 1, waiting for CLAIM); VIP: `RESTORE · FREE` (`VipStreakRestores` per `VipStreakRestoreDays` fake days), then
  the price. Nothing about the streak sits on the HUD. Logs: `[GHS Streak] <name> day N claim, M in a row` / `lost at
  N` / `restore paid` / `restore vip` / `reset` / `skip paid day N`. `StreakEnabled` false: no modal.
- **The daily crate podium.** Round 27b: in plain view from the star, on the hall floor in front of the loading
  platform on the west side (where the red and blue drums stood; `Config.HubImportDropAt` drops them; the shelving
  by the range door is back): the `DailyCrate` node, facing the star, (the pedestal's volume, movable like any hub node) and a stand `Hub.lua` builds from it
  (pedestal, gold trim, a spot lamp, a slanted plaque, the E prompt; `DailyCratePodiumScale`). The crate on it is
  drawn by each client for its own state (`DailyPodium.lua`; the server publishes the player attributes
  `DailyCrate` / `DailyCrateTier` / `DailyCrateFirst`): the store's crate model in the tier's colours. Round 27b: it is
  lit in every state (the spot, the neon trim, the seams breathing, a neon glow on the floor, sparkles round the crate)
  and wears a header + CTA overhead, a constant size on screen and drawn over everything within 160 studs: the tier
  colour's DAILY CRATE, the tier word, a state pill and a bobbing chevron (hidden under the podium's own camera
  shot). **Locked**: lid shut, a chain across the front with a padlock, the pill amber `PLAY A MATCH TO UNLOCK`, plaque `PLAY A MATCH TO UNLOCK`, prompt PLAY A
  MATCH (E toasts the same line). **Ready**: no chain, the lid half open, a glow from inside, a tall beacon column in
  the tier colour seen through walls (`DailyCrateBeamHeight`), the lootbox chimes idling quietly within
  `DailyCrateIdleRange`, sparkles thick, the pill green and breathing `OPEN NOW!`, plaque `DAILY CRATE · READY`, prompt
  OPEN. **Claimed**: lid shut, the spot warm, the glow low, the pill `NEW CRATE IN 6H 12M` (no chevron), plaque
  `BACK TOMORROW`, prompt `ROLL AGAIN · R$ 79`. Any run that reaches a summary (any map, any wave, solo, carried)
  sets `dailyCrate.unlockedDay` for every member; back on the star the chain snaps off with a clink and the beam
  lights. The state resets to locked at the fake-day boundary; an unopened crate is gone (`expired unopened`).
- **The sheet in every state (Round 27c).** E at the podium (VIEW, or OPEN when ready) opens the sheet whatever the
  state: DAILY CRATE in the tier's colour, the crate beside its state (amber PLAY A MATCH TO UNLOCK, green READY, or a
  ticking `NEW CRATE IN 21H 06M 12S`), the pool line, the six best items of your band framed in their rarity, the odds
  row; then OPEN, BUY 1 · R$ 99 while locked (`DailyCrateBuyPrice`, product `dailycrate_buy`: one roll from your band,
  first-gun rule included, the day's free crate untouched) or ROLL AGAIN · R$ 79 once claimed. No tier word over the
  crate or on the plaque; the plaque and the CTA count down instead of BACK TOMORROW; the CTA is about half its first
  size.
- **Can't miss it (Round 27c).** The summary: when the run unlocked the crate, a card slides in on the left a beat
  after the panel (the crate in its tier colours, DAILY CRATE / UNLOCKED, TAP TO OPEN); tapping it is TO LOBBY and the
  podium sheet opens by itself `DailyCrateArrivalOpenSec` after you land. In the hub, while the crate is ready: a
  trail of glowing gold chevrons flows along the floor from you to the podium (`DailyCrateGuideSpacing`, stopping
  `DailyCrateGuideNear` short), a gold arrow sits on the screen edge whenever the podium is off screen, and
  MARLOW's card says `DailyCrateMarlowLine` (titled MARLOW · DAILY CRATE) `DailyCrateNudgeSec` after you land, once a
  fake day a session (not after a tap on the summary card). All of it goes the moment the crate is opened.
- **Opening.** E at the ready podium → the camera pushes onto the podium (`CameraShots.daily`, the JOBS board's 0.6 s
  push) and the compact sheet docks right (`DailySheet.lua`, the Skill Web's card; bottom-right at 40% on a phone):
  the tier tag and LV, the crate art, `GOLD DAILY CRATE`, `GUNS + MASKS · YOUR LEVEL BAND`, `FIRST ONE'S A GUN`
  while it applies, the odds row (a chip per rarity in its colour), OPEN, BACK. OPEN → `Remotes.DailyCrateOpen`: the
  server rolls, grants (normal dupe Gold and mastery) and marks the day claimed → the existing crate scene plays (the
  drop, the rattle, the lid, the reveal) → the camera comes back to the podium, now claimed, and lets go. The tier
  comes only from the level (`DailyCrateTierByLevel`: 1–10 BASIC, 11–25 GOLD, 26–50 DIAMOND, 51+ ELITE), each a
  rarity-weight row in `DailyCrateTierOdds` with its colours and word. The pool is `Catalog.dailyPool()`: every gun
  and mask whose `saleType` is Direct (no Crate / Event / Bundle / VIP / Pass item) minus the plain mask
  (Round 27d: the default gun of each category is in too, so Common is 7 wide; 36 items: 31 guns, 5 masks); rarities the pool lacks weigh nothing. The first daily crate a profile ever opens
  rolls from the guns only (`DailyCrateFirstIsGun`); every later open, a first-day reroll included, from the mix.
  ROLL AGAIN at the claimed podium (`DailyCrateRerollEnabled`, `DailyCrateRerollPrice`, product
  `dailycrate_reroll`, `DailyCrateRerollMaxPerDay` 0 = unlimited) goes through the purchase sheet, plays the scene
  again from the same tier and the mixed pool, and leaves the podium claimed. Logs: `[GHS Daily] <name> unlocked day
  N` / `opened <tier> level N -> <item> <rarity>` / `reroll paid` / `expired unopened`.
- **First run of the day.** While today's first run has not reached its summary, (Round 27e) an urgent glowing bar
  under PLAY (a bright amber gradient with the crate pictogram, a pulsing glow, a light sweep and a slow breath; the
  party card steps down under it) reads `PLAY A MATCH · DAILY CRATE · ×2 XP` (phone: `DAILY CRATE · ×2 XP`; `PlayRibbon.lua`) and the
  Create Match card carries the same glowing bar under its map row (`MatchCardLine.lua`). Each player reads their own
  profile, so in a party only the member who has not run today sees it. The summary is unchanged (`FIRST HEIST OF THE
  DAY ×2`). `DailyCrateEnabled` false: no podium state, no PLAY line.
- **Debug** (MONETIZATION group, under `+1 day`): Set streak day (the next claim lands on it, the modal opens),
  Break streak (two days since the last claim: STREAK LOST), Unlock daily crate, Reset daily crate (locked, never
  opened: the first-gun rule is live again), Force tier AUTO / BASIC / GOLD / DIAMOND / ELITE; Set level (PROFILE)
  moves the band; Stats prints `[GHS Streak]` and `[GHS Daily]` state lines. Force rarity also lands on the next daily
  roll.

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

1. Fresh join: hub HUD only (no buy column, abilities, wave bar, health or ammo), Gold 10,000 bottom-left, the nameplate
   over your head (badge 1, your name, INITIATE in its colour, the INITIATE block), no hat / face accessories, plain mask. Output shows `[GHS Profile]
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
   avatar on the left with its head near the top, no nameplate, the Gold pill reads the balance, dragging on the
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
2. Wave 4+: Boomers (orange, a belly) run at your turret or barricade, stop, beep rising and swell, then
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
   Back in the hub the same card sits above the Gold pill bottom-left with the new level and bar, the nameplate
   reads badge 2 and `★ WAVE 12`, the Gold row includes the banked total and the level reward, and the party card lists
   `LV 2 NAME`. Rejoin: level, XP and the daily flag hold (API access on). The card never shows in a run.
9. Scoreboard: hold Tab in a run: `WAVE 5 · TIME 3:12 · ★★ · ◆ BANKED 54 · $ CASH 2,340`, your row highlighted with
   level, class circle, green dot, kills, cash, bags, jobs, downs, revives, MVP score, updating every second; release
   closes it; shooting keeps working while it is up. Mobile: tap the wave bar (the `≡` chip), tap outside to close.
   Two players: rows in MVP order, a downed teammate's dot goes red, a bled-out one grey.
10. Round 16: no Shooters anywhere in the roster. A frag / molotov / flashbang with the cursor on an enemy (or just
    missing it, even at head height) lands on it and follows it in the air. The molotov burns blue with a solid blue rim (the Grenadier's fire stays orange, rimless);
    the med bag's green field has the rim too. Eagle Vision marks and slows (no damage bonus; MARKSMAN'S KIT is reload only). The camera chip above
    the ammo reads CTRL · CAMERA LOCKED / CAMERA FREE (gold). The Safe dial only counts a number reached turning the
    asked way (coming in from the far side reads WRONG WAY) and clicks louder and higher near each number. Freq: each
    new target sits somewhere else on the slider, and a lock drops your hold. Hotwire: the original colors; the COLORBLIND toggle swaps to
    the colorblind-safe palette with A–F badges, live, and is still on next session. Dealer stands are small upgrade
    cards (icon, big number, price pill); walking up swaps the small card for the pick-3 card with a price bar on the
    same spot. Create Party: HARD / NIGHTMARE are live, the blue highlight follows the pick and the bonus row too.
    Side jobs: the NICE WORK card shows whoever finished it (headshot, name, their own line); MARLOW / DEALER cards
    show a dummy avatar bust instead of the empty portrait. Teammates get gold callouts for the boss's last hit, a
    Legendary out of a crate, a 5+ kill frag or claymore and a mastery tier. In a 2-player run, the gun your teammate drops shows YOUR level's numbers
    on its tag and the reel, and picking it up gives you your own level of it.
11. Mobile (device emulator, landscape): the boss bar and the scoreboard fit the width, the red telegraph circles read
    at phone size, `DBG` chip → the spawn rows work with touch.
11. Debug `Stats` prints the minigame averages and then `[GHS Heat] clear / par this run:` with one line per wave and
    the mean ratio.

### Brief 5 verify list

Written and built (`stylua`, `luau-lsp`, `rojo build`) through Round 16b, not yet run in Studio. Solo through one boss
first, then a 2-player Local Server with a pause and a dealer visit:

1. Gun crates: the left column is NEW UPGRADE only (key 1). The intro crate lands closed with a `GUN CRATE` tag and a
   countdown. One F: a gold burst out of the lid, a floor ring, a thump and a shake; then every roll plays back to
   back on the original sliding reel (80% size) above the crate, ~2s each, seen by everyone, ticks rising in pitch,
   the result line with DMG and RATE, rays from Epic, the sting on a Legendary. Each gun kicks the lid, bursts in its
   rarity color (Epic+: a light column) and arcs to a free floor spot ~6 studs out; it cannot be grabbed mid-arc and
   nothing ever rests on the lid (a swap always drops at floor height). The crate closes after its last roll or 45s;
   the boss crate's first roll is a Legendary; Force rarity applies to the opener's next roll.
2. Upgrades: cards now include Fire / Ice / Impact Ammo (orange `Element` on the debug panel forces one), ABILITY
   COOLDOWN, ABILITY POWER and CASH GAIN. A new ammo card reads `NEW` over `BURN ON EVERY SHOT`; later ones `+30%`
   over `BURN` / `SLOW` / `IMPACT`; the tracker tile shows the power (`100%`, `130%`). Every bullet that lands applies
   it, each shotgun pellet too: Fire stacks a burn up to 5 (orange, embers), Ice slows (deep blue, big frost flakes)
   and ten hits in 2s freeze for 0.8s at most once per 3s, Impact shoves ~1 stud per bullet with a white ring and
   interrupts at most every 1.5s. TITAN takes half the slow and knockback, never freezes and is never interrupted.
   Tradeoffs are rarer and never on ammo; kill cash grows 10% a wave; each wave end prints `[GHS Income] wave N cash
   earned X upgrades bought Y (name)`; debug `Stats` adds upgrades per player per wave.
3. Revive (2 players; `Down me` on one): the reviver sees `REVIVING NAME 2.4s` under the crosshair with a tick every
   0.5s, a red snap-back on release, a green `REVIVED`; the downed player's bleed bar gains a green fill with `NAME IS
   REVIVING YOU`, the head marker the same fill; the stand-up pulses green and the camera eases up. Callouts: downed /
   revived / bled-out players send teammates a red card with their headshot (Revive Everybody: gold, to everyone),
   waiting behind MARLOW and the boss cutscene.
4. Classes tab: INITIATE → ENGINEER (`E`) → DOC → SHARPSHOOTER → TORCH. The detail column shows MASTERY with the waves
   inside the bar and three tier cards (earned gold, next green). INITIATE: Q Frag (thrown to the cursor up to 100
   studs, a higher arc the further it goes, bursts on landing for 120 in 9 studs), E Adrenaline, Z Claymore. ENGINEER:
   Q Turret, E Barricade, Z Overclock (placeables glow amber and work 1.5× for 8s, barricades get a 150 shield).
   SHARPSHOOTER: Q Eagle Vision (`EGV`: enemies within 60 studs glow red through walls for 6s and walk 35% slower), E Dead Eye,
   Z Flashbang. Players walk through every placeable; enemies stop at them.
5. Ability tiles: a used charge starts its cooldown at once; with a spare charge still in hand the tile stays gold and a
   thin gold bar along its bottom fills toward the next charge (`+1` when it lands); at zero charges the dark sweep
   shows; during a buff the cooldown drains under the gold timer. Floats: `+0.5s` on Adrenaline per kill (Adrenaline
   Junkie), `-0.1s` / `-0.2s` for Backdraft / Overdrive, `-8% CD` on all three tiles when ABILITY COOLDOWN is taken.
6. Mastery: debug `+100 mastery` (or kills with one gun) in a run: the moment a tier is crossed a rank-up card drops
   under the wave bar (`WEAPON MASTERY · AK-47 · MASTERY I · GUNMETAL WRAP UNLOCKED`), the passive on from that second.
   Weapons tab: owned tiles read `NAME  LV n` over the mastery bar (STARTER at the bottom); the detail shows mode ·
   rarity · level beside the name, the MASTERY panel (`NEXT · UNLOCK SKIN`, kills inside the bar), and EQUIP +
   CUSTOMIZE on one row; the mastery wraps carry a MASTERY tag and apply only on the gun that earned them. Summary:
   the MASTERY line and each tier crossed this run. Spot-check the passives listed under Mastery above.
7. Vault (wave 5 forces it): MARLOW's call, a big amber `VAULT JOB` stamp, the door pulsing amber, the normal-size
   amber beacon and a chevron strip along the floor from the crew to the door for 10s; the Safe dial asks for 3 / 4 / 5
   numbers by bracket but forgives overshoot corrections and short wobbles; Tab shows `· VAULT OPEN`. When it seals,
   anything placed inside is destroyed.
8. Dealer (clear wave 10's TITAN, or debug `Open dealer` in an intermission): the wave bar reads DEALER; the DEALER
   phones in on the top-right call card (`SHOP OPEN`), then a compact card takes its place there with `DEALER · 1:30`,
   TELEPORT [T] (any number of times) and SKIP n/m [V]. Three tables stand in a half circle round the DEALER with your
   own eight cards on top as UI (stat initials, tier color, price) and ARMS DROP / HEAL ALL / REROLL tags past the ends.
   Walk up: the nearest opens one panel (`BURN +100% → +130%` for ammo), F or BUY buys, short of cash it shakes red; no
   leftover panels anywhere. Break ends on the timer or a unanimous SKIP.
9. Pause: P or the PAUSE n/m pill on the wave bar (skip VOTES now sit under AUTO SKIP) or the scoreboard. Solo pauses at
   once, a party when everyone votes; no limit on how often. Everything freezes (enemies, damage, movement, fire, every
   timer). The overlay shows `RESUMES IN 4:59` and VOTE TO EXTEND (+5 min, stacks) / VOTE TO RESUME with counts, both
   unanimous; it resumes by itself at the end after a 10s red countdown; par and TIME leave the pause out. Debug
   `Pause / resume` skips the vote.
10. Mobile (device emulator, landscape): the crate reel and tag, the revive bar, the top-right dealer card, the shop
    panel's BUY, the pause buttons and the mastery cards all read and tap at phone size.

### Brief 6 verify list

Written and built (`stylua`, `luau-lsp`, `rojo build`) step by step, not yet run in Studio. The done-line: one solo
session that buys one of everything, opens ×1 / ×3 / ×10 of each crate, levels the pass, claims a daily, subscribes and
cancels VIP, and rejoins to find it all kept (API access on). Verify the `Poses.lua` ids load (a failed one leaves the
mannequin in its idle; the output shows the load error).

1. Fresh profile: the hub's BOOSTS corner shows the token chip (`×3`) and the `+`, PASS (LV 1) and JOBS sit
   right-center with red dots; a few seconds in MARLOW's card slides in top-right (`New jobs on the board…`) and his
   corkboard's beacon pulses. Output: `[GHS Jobs] … new dailies`, `[GHS Profile] … v2 -> v3` on an old profile.
2. SHOP: the window over a dim, below the Roblox top bar, header with Gold (no R$); the rail scrolls to each
   section and follows your own scrolling; cards cascade, hover lifts / brightens, buttons grow on hover and squash on
   press (none ever move away), sounds on every tap. LEAVE / Esc / a tap outside return to the hub (fake R$: the debug panel’s set R$, or GET ROBUX on the sheet when you are short).
3. GOLD: six packs, BEST VALUE on RESERVE; buy one → the sheet (spinner 0.6s) → `… purchased!`, Gold flies into the
   header and counts up; the output prints the purchase line.
4. FEATURED: one wide bundle bar with every item inline, -X%, WORTH and BUY, and `LEAVING IN hh:mm:ss` ticking; buy
   it → the stacked reveal and everything lands (the MARKSMAN SET: the Mosin with the Woodland wrap in the Armory,
   SHARPSHOOTER in Crew, the hood and the pose in the Locker, Gold +5,000, tokens +10); owned items are marked and
   skipped at the same price. Under it six DAILY ITEMS with their own countdown; buy one → a mini reveal and OWNED on its
   card; debug `+1 day` draws a new six.
5. CRATES: each card shows the strip, ODDS (percentages that sum to 100, the items, `[Legal copy: TBA]`) and `EPIC+
   GUARANTEED IN 10`. OPEN 1 → straight into the crate room: rattle, seams in the rarity color, the lid, the item on its
   beam, the name card, CONFIRM back to CRATES. OPEN 10 → ten in a row with NEXT / auto-advance, SKIP from the first
   reveal → the summary grid with dupes and totals, OPEN AGAIN / DONE. Within 10 opens an Epic+ always lands; dupes say
   `DUPLICATE · +◆ N · +N mastery`. Debug `Force rarity L` then OPEN 1: the Legendary slow motion. New guns hold with
   their own silhouette; new masks wear in the hub and the run.
6. BOOSTS: buy POWER 30m → a chip in BOOSTS with a timer and `ACTIVE · 29:59` on the card (EXTEND adds 30m). In a run:
   the chip sits bottom-left above the cash, damage numbers are ~20% higher (POWER), kill cash 50% higher (CASH), crates roll
   higher (LUCKY). The summary's Gold and XP are unchanged.
7. Tokens: debug `Down me` → SELF-REVIVE shows `1 TOKEN · YOU HAVE 3` and stands you up; `Set tkn` 0 then down →
   GET TOKENS → the sheet; buy → the button is armed. Solo: give up → bleed out → REVIVE EVERYBODY (1 token) inside the
   RUN OVER window → second chance; at zero tokens the sheet opens and the window holds while it is up.
8. Cash +: in a run the sheet lists three packs; buying adds the cash with the usual float. At the dealer, REROLL without
   the cash opens the R$ RESTOCK sheet.
9. VIP: SUBSCRIBE → the gold tag over your head, on the party card, scoreboard, summary row (pulsing frame) and
   callouts; the VIP chip in BOOSTS; the GFT chip pays 200 Gold once a day; the VIP mask and poses in the Locker's OWNED; +10 tokens. Debug
   `+1 day` × 30 → a renewal charges R$ 399 and pays 10 tokens. CANCEL → perks gone, cosmetics stay, WELCOME BACK.
10. Pass: PASS opens the stage; claim level 1 FREE; `+1,000 pass` levels up (the banner, the HUD ring); GET PREMIUM →
    every reached PREMIUM tile (beside the FREE one under each LEVEL band) pulses, CLAIM ALL claims them in a mini reveal; SKIP ×5; PREMIUM+ from PREMIUM costs the
    difference; the stage opens on the level 30 hero, the chase card shows all three heroes (tap one to see it in 3D)
    and the track marks them HERO. Finish a run → the summary's
    PASS XP bar fills (40 a wave, 200 a boss) and CLAIM IN PASS opens the scene. Debug `+1 day` until the season ends →
    SEASON OVER on the next open and season 2 (COLD CASE).
11. Jobs: JOBS / F at the board → the camera pushes onto the corkboard; the dailies show progress; play a run → JOB
    toasts at each quarter, the scoreboard Job cards, the summary ticks; a finished one gets the DONE stamp at the board,
    CLAIM pays XP + Gold + pass XP (big reward tiles); a claimed card offers NEW JOB · R$ 49 (the bounty NEW BOUNTY ·
    R$ 99) for a fresh one; the header timers tick (`16:42:05`, `2D 16H 42M`). Debug `Reset jobs` draws a new board.
12. Rejoin: balance, tokens, boosts with their time left, VIP, pass level and claims, Job progress, banked crate opens
    and pity are all where they were. Debug `Buy log` prints every purchase with totals.
13. Mobile (device emulator, landscape): the store tab strip scrolls, every card and button taps, the crate scene is full
    screen with 56px SKIP / NEXT, the pass track and the job board fit.

### Brief 7 verify list

Written and built (`stylua`, `luau-lsp`, `rojo build`) one commit per step, not yet run in Studio: the nodes were
authored from the geometry offline, so the first pass is a node review. Done-line: one solo run and one 2-player Local
Server run on THE BANK from the hub to a summary, through every door, one vault window, one TITAN.

1. Nodes: in edit mode every node is a translucent box in its type colour with a label (select `Workspace.Bank` in
   the Explorer and press F to fly there; zones are Locked so clicks reach the nodes inside them, pick a zone in the
   Explorer). In Play they are hidden; debug MAP > `Show nodes` draws them (zones are off by default: toggle `Zones`). Every node draws in its type
   colour with `TAG · name · key attributes`; the output has one `[GHS Map]` line per node and no `ERROR`. Review the
   D2 chains (placed at the stair tops, between the newel posts), the D3 shutters and counter grille, the spawn boxes
   and the boss walls against the building. To move one: stop, select it under `Workspace.Bank.Nodes` in edit mode,
   drag, then select `Workspace.Bank.Nodes` > Save to File as `Nodes.rbxmx` and run
   `lune run tools/exportnodes.luau Nodes.rbxmx`. In a play session, `Recompute nodes` re-reads after a drag.
2. Arena unchanged: Create Match > ARENA > a run plays as before (markers, closet vault, bag spots); the nameplate reads
   `★ WAVE N · ARENA` once a top wave lands there. A pre-brief-7 profile logs `[GHS Profile] v3 -> v4: … TheBank:* -> Arena:*`.
3. Card: ARENA and THE BANK tiles plus COMING SOON; THE BANK is picked by default; the board and the compact card read
   `THE BANK · NORMAL`; the summary header names the map; PLAY AGAIN keeps it.
4. Run start: the van drives onto the grass, the crew steps out facing the bank and the camera hands back facing it
   too, no free crate (Round 19c), WAVE 1 on the street. Spawns come
   from behind the fence ends; the scoreboard header reads `· STREET`; amber ▲ beacons and signs on every door.
5. Doors: only the next unlock has a beacon (later doors keep their signs). The intermission before wave 2 → MARLOW
   `Front doors. Make some noise.`, blue beacons, chevrons along the walking route to the doors, the pill
   `OPEN THE BANK` with ∞, no side job that wave; F at the doors (BREACH) opens the Charges minigame → done: the doors
   swing and fade, the asset's door leaves vanish, flash and shake, +$400 each, your card,
   `<NAME> OPENED THE FRONT DOORS`, 3 cash + 1 gold bag in the lobby, `[GHS Door] D1 opened …`. D3 (wave 8) is a hold
   at either part (RAISE; release: the bar keeps its fill 2 s); D2 (wave 5) is the bolt cutter at either chain (CUT,
   Round 19c); the chevrons for D2 climb the stairs to the chains at the top; the counter grille rolls up with the shutters. D5 (wave 12,
   Round 19d) is the bolt cutter at either stairwell head; the back opens with D3 but the stairwells stay chained (no
   hopping the railings). Debug `Open D1..D3 / D5 / D4` and `Close all` to jump.
6. Pathfinding: debug `Pin LOBBY` + `Spawn at:` a box + an archetype; enemies take the stairs, both passages, the
   stairwells; `Path debug` draws their routes (red when stuck). With the vault open, spawn at `tunnel_far`: they climb
   the ladder (lifted) to the pavement. A barricade across a passage: they route round it, or hit it when it is the
   only way. `[GHS Path]` per wave.
7. Vault (D3 open, wave 10 or debug `Open vault`): `Vault's at the bottom of the stairwell…`, F at the wheel → Safe
   dial → `WE'RE IN`, the wheel spins, both doors swing, the burst, the pill `TUNNEL OPEN`, the hatch lid swings up with a
   blue TUNNEL beacon; the vault's back wall (the server door was painted on it) is gone for the window. Walk the ring
   vault → server room → tunnel → ladder → street. Gas at 10 s left; the doors close
   only once nobody is in the room (step in as they shut → you are put outside); the alarms ring with the gas warning; `[GHS Vault] window used … exit tunnel <you>`; the hatch stays open.
8. TITAN (wave 10): the wall blows on the crew zone's boss wall (the street: the west fence end) and it walks in; lead it
   into the building: it follows through openings it fits, otherwise holds and Volleys.
9. Dealer after the boss: the stall stands on the crew zone's dealer spot (the grass, the lobby under the stairs, the
   corridor, the landing), facing the right way; TELEPORT lands in front of it.
9b. Round 19b: enemies walk up the stairs without hopping each step and through the street barriers (players cannot);
    one far off for 6 s reappears closer on its route out of sight (`[GHS Path] … catch-ups N`); shoot a bank window →
    it shatters and stays open; no bags spawn outside the bank.
9c. Round 19c: the crew faces the bank when the camera hands back; no free crate on THE BANK (the arena keeps it);
    shoot a window anywhere (not just the middle) → the glass, the frame bars and the pane go together and you can walk
    and shoot through; the strip behind the bank is fenced off at both back corners; enemies far away catch up to at
    least `CatchUpMinPlayerDistance` (55) from everyone and never in view; a crowd stays spread out (no stacked
    enemies); walk into the vault door as it seals → you land outside; grab the last vault bag → the CLEAN IT OUT
    marker goes. D2's chains open the bolt cutter (hold, let go in the green; over-squeeze slips). Debug MAP row:
    `Zone gas` (alarms + `GAS IN THE LOBBY · 10s · MOVE`, then green gas in the zone, `LOBBY CLEAR` after 25 s; stand
    in it → tint and damage), `Alarm job` (fixtures strobe red, the horn and a faint red screen edge until the panel
    is shut off: Round 19d, a minigame), `Cut job`. A whole heat star gained rings the alarms for 3 s. Jobs board: R on an unfinished sheet swaps
    it (free once a day, then the R$ sheet). The summary's CLAIM IN PASS → hub → the pass opens.
9d. Round 19d / 19e: music from the hub on (a crossfade at Create Match into a run track that keeps playing through
    waves, intermissions, the dealer, alarms and gas → boss for TITAN, ducked under its cutscene, the run track picking
    up after → silence on the stamp → summary); the gunshot, reload (out, then seated late), bag cash / coins, kill
    thud, window glass, gas hiss, alarm buzzer, the shutter roll and a whiz on a Marksman miss; no explosion clip on
    blasts, the breach or the bolt cutter (each link is a snip); tapping a gun in Weapons is a click only; shoot the
    teller glass → it shatters and you can hop the counter; the weapon type beside the gun's name on the HUD card,
    floor tags and the crate result; a crate: swell + coins, clicker
    climbing, a rarity arpeggio (shimmer from Rare, chimes from Epic), a pop on the eject; zone gas never before wave
    10; full-auto never stacks into mush. `Alarm job`: F at the panel opens a minigame (the card
    names it: Keypad, Freq, Charges or Hotwire) and done silences the building; on THE BANK the wave 1 job is always
    the alarm on the Keypad. After D1 opens, no side job beacon on the street. D3 opens the back but
    not the stairwells; D5 is called before wave 12 and the vault job only draws once it is open (the first forced vault is wave 15). Lockdown: leave D1
    shut through waves 2 and 3 → wave 4, 8 s in, `LOCKDOWN · GAS IN 10s`, then gas on the street (tint, damage)
    with chevrons from you to the doors every 8 s, the red line under the pill and the edge arrow when you look away;
    open the doors → the lobby is clean, `AIR CLEARING` 6 s later. Debug MAP row `Lockdown` runs it on the called
    door now.
9f. Round 19f: the offices: Show nodes draws four OFFICE rooms and their `_door` boxes over the glass doors (the
    output has `[GHS Office] office_back_w: 11 door parts, 1 blinds` per office, no WARN). Open D3 (debug), then
    debug MAP `Office job` → MARLOW `The WEST BACK OFFICE is locked up tight…` with the minigame's line, the beacon
    outside a back office door; F → the minigame (Lockpick / Hotwire / Charges / Cut) → done: the job's card, the
    door shatters away with the blinds, 6 cash + 2 gold bags inside (solo), the amber marker counts 30 s → red
    `GAS · GET OUT` with the alarm (the building's fixtures and the horn) for 8 s → gas 6 s (tint, damage) → sealed:
    stand inside and you land outside the door, leftover bags fizzle, the door and blinds are back. `Open office`
    blows the nearest one with no job. The upper pair need D2.
9g. Art pass: every gun in Weapons, the crate reel and on the floor is its own model (AK wood and banana mag, P90 top
    mag, Barrett brake and bipod, the sawed-off's two barrels); the rarity strips glow from Epic; a wrap paints the
    grip / handguard / stock. In a run the arms hold the gun (rifles shouldered with the chest turned, pistols
    two-handed), the gun follows the cursor up and down, RMB raises it to the cheek; firing kicks it with a flash and
    brass (pistol slides cycle and lock back on empty, the SPAS pumps, the AWP / Mosin bolt, the 1887 levers); R drops
    the mag, the left hand fetches one from the belt and seats it on the click; the SPAS loads shell by shell and the
    sawed-off breaks open. A teammate (2-player Local Server) shows the same, aim pitch and reloads included. No
    `[GunAnim] can't pose` line in the output. Icons: Weapons / Avatar tiles, store cards and the HUD slot show the
    3D models; ability wells, class circles, boost chips and upgrade cards show pictograms.
9h. Round 19h: CUSTOMIZE on a gun → the avatar disappears, the gun alone spins in side-on (muzzle left), drag turns
    it, a wrap paints it, BACK brings the avatar back. Picking an upgrade card plays `sfx_menu_upgrade` (Round 19k) at pitch 1, not a snap, with a burst of chips off
    the card (more per tier), sparkles trailing the icon to the tracker and a pop where it lands (Round 19l). Two
    alarm jobs in a row never use the same minigame (nor two of any job type); no HACK-hold terminal jobs, door
    shutters still hold F. The crate reel shows gun models (it now draws on a screen overlay that follows the crate).
    A kill is a light tick and a soft thud. A called door's chevrons, loud beacon and edge arrow stay until it opens.
    Round 19i: solve a minigame and walk off on the last input → it still stamps DONE and pays; walk off mid-game →
    TOO FAR, then the cancel after `MinigameWalkAwayGraceSec` (step back in range within it and it stays open).
    Round 19m: open the battle pass, the store and a crate from the hub → each set is lit from the first frame (no
    fade-up over a few seconds).
    Round 19n: in the hub every character wears the nameplate: the level badge with the number in it, the name in caps
    (+ the gold VIP tag), `★ WAVE N · MAP` (the class name before a first wave), the class block on the right, a class
    tint and underline; no Roblox name over it. `+500 XP` to a new level pops the badge; switching class recolours it;
    CUSTOMIZE hides your own plate; a run hides every plate in the party and the Roblox names come back.
    Round 19o: every screen uses Oswald caps for headings / numbers and Builder Sans for body text, at least as big as
    the old LuckiestGuy / Gotham text; panels, cards, pills and buttons have tight 4px corners (dots and dials stay
    round); text outlines are thin. In a run the ability / buy tiles (80x90) are filled by the icon with the name
    sized to the width (`UPGRADE`, not NEW UPGRADE), bigger hotkey / price / cooldown text, larger boost timers and
    controls hint. Server signs (hub floor labels, queue board, dealer, doors, bags, vault, elite tag, podium) match.
10. Logs and stats: `[GHS Zone]`, `[GHS Spawn] … contact`, debug Stats prints the MAP block (zone times, doors, contact
    per box, path budget).
11. Mobile (emulator, landscape): the map tiles swipe, door signs and the `UNLOCKS · WAVE N` beacons read, the door
    prompt holds with a touch, the truss climbs with touch, the debug MAP group sits in the DBG panel.

### Brief 8 verify list

Written and built (`stylua`, `luau-lsp`, `rojo build`) one commit per step, not yet run in Studio. Restart `rojo serve`
first (the project tree gained `Workspace.Hub`). Done-line: a fresh join lands in the warehouse; two parties on two
pads run the arena and THE BANK at the same time on a 2-player Local Server and both come back to the hub; a solo
player shoots every owned gun at a dummy in the range and plays every test prop there.

1. Nodes: in edit mode `Workspace.Hub.Nodes` shows every node as a translucent box (select `Workspace.Hub`, F to fly
   there). Check the pads on the yellow squares, the booth prompts on the stage fronts, the board on the corkboard,
   the van node inside the garage (nose to the door), the garage and range door boxes in the openings, the dummies at
   the west end of the bay, the props along its north wall and the tier pad by its south wall. Drag, save the Nodes
   folder as `.rbxmx`, `lune run tools/exportnodes.luau Nodes.rbxmx hub`. The output has `[GHS Map] hub …` lines,
   `[GHS Runs] 2 run slots: Arena, TheBank`, `[GHS Queue] 4 queue pads`, `[GHS Range] 3 dummies` and no `ERROR`.
2. Fresh join: on the star facing the pads, hub HUD, `[GHS Profile] … loaded`, the nameplate, the board's beacon
   pulsing on the north wall, hub music. No yard, no arena door, no `Baseplate`.
3. Pads: PLAY walks you onto the nearest open pad; walking onto any pad opens Create Match for it; the billboard reads
   `PAD N · MAP · DIFFICULTY`, the countdown, then `MATCH IN PROGRESS · WAVE N` while its party plays; walking onto a
   pad in progress pushes you off. Local Server, 2 players: P1 creates THE BANK on pad 1 (party of 1), P2 creates the
   ARENA on pad 3 → both runs play at once (`[GHS Queue] pad 1 start TheBank`, `pad 3 start Arena`); each sees only
   its own wave bar, banners, scoreboard and pause. P2 creates THE BANK while P1 is inside → `MAP BUSY · P1 IS
   INSIDE` and `busy-wait`; it starts the moment P1's summary closes.
4. Booths: F (OPEN) at each booth's front opens the scene on its tab; each booth's rig wears your mask, plays your
   class idle and holds your starter gun (equip another mask / class / gun → it re-dresses); P2 sees their own.
5. Board: F at the bulletin board opens the Jobs board with the camera push onto it; JOBS on the HUD does the same.
6. Run start: the party fades, the garage shutter rolls up with the shutter sound, the van pulls out under a chase cam,
   cut to THE BANK's (or the arena's: in through the room's south strip, braking by the line) drive-in; a player in the
   hub sees the van leave and the door come down 3 s later, the van back in place. Run end: TO LOBBY → the star.
7. Range: walk through the north-west door → armed (held slot, ammo, crosshair, abilities, CAMERA LOCKED chip; no buy
   column, wave bar, cash or heat), `[GHS Range] <name> enter`; shoot a dummy → numbers, flinch, `DMG · DPS · HS`;
   headshots on the red head raise HS; the middle dummy's plates fly
   off and come back 5 s later; R at a sign zeroes it (`reset dummy N`); Q / E / Z work, placeables vanish when you
   walk out; walk out → the gun stowed, the hub HUD back, `leave`. The seven props and the tier pad open as before.
   Debug HUB: To range, Spawn at range (Henchman, ELITE, Range boss) → it chases you inside only; Kill all clears it.
8. Debug HUB: To hub / To range, Reset dummies, Open garage, Force pad N (an open party on that pad starts now).
9. Mobile (emulator, landscape): pads, booths, the board and the RANGE sign prompt with a tap; the fire / ADS / reload
   and ability buttons appear only inside the range.

### Brief 9 verify list

Written and built (`stylua`, `luau-lsp`, `rojo build`) one commit per step, not yet run in Studio. Done-line: a
fresh profile opens the web from the hub HUD, buys its way from the centre to a ring-5 node in one branch with debug
Gold, every bought node measurably changes a run (or a range dummy), and the web, badge and summary line read on a
phone in landscape.

1. Rejoin an existing profile → `[GHS Profile] v4 -> v5` once (not on the next join). A fresh profile: the SKILLS
   tile under SHOP with a red `1` badge (START), its edge pulses white once; MARLOW's first card of the day adds the
   Skill Web line.
2. SKILLS → the web over the blurred hub: no hub HUD, no nameplate over you, you can't walk; START in dark gold at
   the centre, zoomed in, priced ◆ 250 and pulsing, six grey ? hexes round it, no legend rows. Tap START → the sheet
   (THE WEB, star, START, UNLOCK SKILLS, BUY ◆ 250). BUY → the flash and gold rings, SKILL WEB UNLOCKED, the six
   ring-1 hexes turn over clockwise in dark branch shades (prices 350–650) as the legend fills, then twelve ? hexes
   fade in; `[GHS Economy] … spent 250 gold on skill START`. Esc / BACK
   closes; the hub HUD, nameplate and walking come back.
3. Drag pans, scroll zooms around the cursor (out until the whole web fits, in to 1.6x), double-tap empty space eases
   back to START. A drag that ends on a hex does not open its sheet.
4. Tap DAMAGE I → it glides to the centre beside a compact sheet (DAMAGE tag, RING 1, skull, +3% damage with every
   gun, BUY ◆ 650). BUY → the hex turns bright red with a wipe, ding and burst, a lit edge to START, CRIT CHANCE I /
   HEADSHOT I reveal, a new ? ring appears, Gold counts 10,000 → 9,350, the sheet says OWNED;
   `[GHS Economy] … spent 650 gold on skill damage_damage_1`. Rejoin → still owned.
5. Debug +10,000 Gold a few times and buy DAMAGE II → III → IV (or any path to ring 5) in one branch; a ring-2 hex in
   SURVIVAL is reachable from DAMAGE ring 2 across the seam. A node you can't afford: red price, BUY dimmed with NOT
   ENOUGH GOLD (the refusal tick); a ? hex: ???, LOCKED · UNLOCK A NEIGHBOUR.
6. Range: walk in → `[GHS Skills] damage_damage_1 applied damagePct 3%` … and the summary line; the weapon card's
   DMG is 3% higher than before the buy, a dummy's numbers match; walk out → back to zeros. A buy while in the range
   applies at once.
7. Run start: the same log lines once per player; HP bar max (MAX HP), the weapon card (DAMAGE, ARSENAL type
   damage / mags), cash at the start (SEED MONEY), dealer prices (HAGGLE), pick-3 / dealer / crate tiers (LUCK: Unlock
   all skills then compare a few pick-3 rolls at wave 1), bag pickup reach and fill (MAGNET / FAST HANDS), cash floats
   on a cash bag (BAG VALUE), the summary's Gold (FENCE: `… + N banked (team M)`), revive hold and bleed-out
   (REVIVE SPEED / LAST STAND on a 2-player Local Server), door holds on THE BANK and the HACK prompt (QUICK HANDS).
8. The summary: with nodes affordable after the payout, `N SKILLS AFFORDABLE` fades in under GOLD BANKED once the
   count-up lands; back in the hub the badge shows the same N.
9. Debug PROFILE: Unlock all skills (the badge goes, the web fills), Reset skills (back to START), Grant (pick a
   branch, then a ring), Stats (`[GHS Skills] <you> owned: DAMAGE 15/15 …` and the modifier table).
10. Phone (emulator, landscape): the whole web fits at minimum zoom, pinch zooms, one finger pans, hexes ≥ 56 px at
    zoom 1, the legend is pictograms only under 720 px wide, the sheet docks right at 40% with BUY bottom-right and
    the tapped hex eases left out from under it; the badge and the summary line read.
11. Armory levels, the store, the pass and Jobs behave as before.

### Brief 10 verify list

Written and built (`stylua`, `luau-lsp`, `rojo build`) one commit per step, not yet run in Studio. Done-line: with the
fake clock, one profile claims five streak days in a row, misses one and restores it for fake Robux; on a fresh
profile the podium is locked, one match unlocks it, the first open is a gun, the second day's open can be a mask, ROLL
AGAIN works; all of it on a phone in landscape. Rojo serve: no tree change (the podium node is in the existing hub
nodes file), a running serve picks everything up.

1. Rejoin an existing profile → `[GHS Profile] v5 -> v6` once. About a second after the hub loads the streak modal
   opens before anything else: the dark panel, DAILY STREAK with 0 IN A ROW, the card row DAY 1–10 then MORE
   (8–10 fading), DAY 1 lifted with TODAY and a breathing glow, CLAIM; you can't walk, nothing behind it takes a tap.
   CLAIM → a ding, a burst, DAY 1 ticks, the IN A ROW counter punches to 1, the row glides to DAY 2 (green, its countdown on top) and the
   button becomes GET IT NOW · R$ 29; Gold +300; `[GHS Streak] <you> day 1 claim, 1 in a row`. X closes; MARLOW's
   card follows. Rejoin the same day: the modal opens again on the claimed view (X closes it).
2. GET IT NOW → the purchase sheet → buy → DAY 2's reward lands, the calendar reads 2, DAY 3 lights with the
   countdown and the button reads `NEXT IN …` (one skip a day); `[GHS Streak] <you> skip paid day 2`. Debug `+1 day`
   → within a few seconds the modal re-renders on DAY 3 to claim (day 3 is a BASIC daily crate: CLAIM → the crate room plays it →
   back on the modal's claimed view). Claim days 4–5 the same way (the X and Esc claim too); day 5 puts the CASH chip
   in BOOSTS.
3. `+1 day` twice (or Break streak) → STREAK LOST on the darker panel, DAY 6 red with RESTORE, `RESTORE · R$ 49` and
   START OVER; `[GHS Streak] <you> lost at 6`. RESTORE → the purchase sheet → buy → day 6 claimed, the calendar
   keeps counting (`restore paid`, `day 6 claim (restore), 6 in a row`). Break again and START OVER → day 1, the
   calendar at 1 (`reset`). With VIP (store, fake): `RESTORE · FREE`, it claims without a sheet, the next break shows
   the price.
4. Set streak day 7 → the gold DAY 7 card with rays, a RARE+ BASIC daily crate (Rare or better). Set streak day 28 → an EPIC+
   open and the +1,500 chip; `+1 day` → DAY 22 (week 4 again; the row shows 22–28 then three more and MORE).
5. The podium: from the star, look left past the WEAPONS wall toward the loading platform: where the two drums stood
   there is a lit pedestal with a sparkling, chained crate, a glow on the floor and DAILY CRATE / BASIC / an amber
   `PLAY A MATCH TO UNLOCK` pill with a bobbing chevron overhead; the shelving by the range door is back. E reads PLAY A
   MATCH and toasts it.
6. Fresh profile (Reset profile): PLAY wears the amber `PLAY A MATCH · DAILY CRATE · ×2 XP` ribbon; the Create Match
   card shows the same line under the maps. Play any match to the summary (debug Skip to run end is fine):
   `FIRST HEIST OF THE DAY ×2` on the summary, `[GHS Daily] <you> unlocked day N`. TO LOBBY → on the star the chain
   snaps off with a clink, the lid opens halfway, the glow and the beacon column come on (the column shows through
   walls), the ribbon and the card line are gone.
7. (Round 27c: the summary also slides in DAILY CRATE / UNLOCKED on the left; tap it → the hub, then the sheet opens
   by itself. Not tapped: gold chevrons flow from you to the podium, an edge arrow when it is off screen, MARLOW's
   DAILY CRATE card after a few seconds; all gone once opened. E at a locked or claimed podium opens the sheet too:
   contents, odds, BUY 1 · R$ 99 / ROLL AGAIN and a ticking countdown.) Walk up: the quiet chimes start inside ~40
   studs. E (OPEN) → the camera pushes onto the podium, the sheet docks
   right: BASIC tag, LV 1, the crate, `GUNS + MASKS · YOUR LEVEL BAND`, `FIRST ONE'S A GUN`, the odds chips, OPEN.
   OPEN → the crate scene → a gun → CONFIRM → the camera is back on the podium (now claimed, `BACK TOMORROW`) and lets
   go; `[GHS Daily] <you> opened basic level 1 -> <gun> <rarity> (first: gun)`.
8. E again → the sheet with `ROLL AGAIN · R$ 79` → the purchase sheet → the scene again (guns or masks), still
   claimed; `[GHS Daily] <you> reroll paid` and the purchase log line.
9. `+1 day` → the podium is locked again (the ribbon is back). Unlock daily crate → open: masks can drop now. Set level
   12 → the crate turns GOLD (gold trim, GOLD tag); Force tier ELITE / AUTO. Leave a crate unopened and `+1 day` →
   `expired unopened`.
10. Two players (Local Server): one claims the crate; the other still sees theirs locked or ready. A party where one
    has run today: only the other sees the PLAY ribbon.
11. Phone (emulator, landscape): the streak modal fits under the top bar with CLAIM a full-width button at the bottom,
    tiles and words readable; the podium prompt reads; the sheet docks bottom-right with OPEN under the thumb.
12. The van, the garage and the departure beat play as before; the range still arms you at its door.

### Brief 11 verify list

Written and built (`stylua`, `luau-lsp`, `rojo build`, `lune run tests/input.spec.luau`: 259 checks) one commit per
step; step 2 was swept once on a DualSense (checkpoint 1), the rest not yet run in Studio. Done-line: one full session
on the pad, mouse and keyboard untouched, then a phone session that sprints and shoots without ever being stuck unable
to fire. Rojo serve: new client and shared modules only, a running serve picks them up. Keep the Input monitor up
(debug INPUT) for the first pass.

1. Join with the pad in hand → `[GHS Input] device gamepad`; no cursor. Touch the mouse → `device keyboard` and every
   chip turns back into its key within a second; the pad again → the glyphs return.
2. The hub: Create (Roblox's own toggle) → Roblox's selection highlight lands on PLAY; D-pad / left stick walk SHOP,
   SKILLS, PASS, JOBS, the dock; ✕ opens; Create again leaves it. (The DualSense touchpad click does nothing: Roblox
   does not report it.)
3. Every screen: open it with ✕ and walk it (down from a chip goes to the button directly under it); ✕ on UPGRADE keeps
   the selection on UPGRADE; ○ backs out (a sheet first, then the screen); customization: L2 / R2 the booths, L1 / R1
   the weapon types / classes / avatar categories; L1 / R1 swap the store tabs and the pass pages. Streak modal lands on CLAIM, the daily
   crate sheet on OPEN NOW, the summary on PLAY AGAIN, bleeding out on REVIVE EVERYBODY; the selection never leaves the open screen for the HUD behind.
   The Skill Web: the selection hops hex to hex, each hex opens its sheet and the view glides to it; ✕ buys it; ○
   closes the sheet (the selection stays on that hex), ○ again leaves the web; right stick pans, triggers zoom. A screen with nothing to select logs
   `[GHS Nav] WARN`.
4. No CONTROLS button in the hub or the scoreboard (the sheet is parked, Round 28c). No prompt at the range door.
5. A run: R2 fires, L2 aims, □ reloads, △ swaps, L1 / R1 / ○ cast, R3 cycles the camera view three ways, D-pad ↑ buys
   the upgrade pick, ← votes pause, → toggles AUTO SKIP (at the dealer it skips the break, ↑ teleports and □ buys
   the open stand), hip fire on the pad gets a noticeable pull, Create taps the scoreboard open (the selection sits on VOTE PAUSE)
   and taps it shut; held, it peeks. The ability tiles, the swap chip, the upgrade tile, the ammo hint (□ RELOAD,
   L1 R1 ○ ABILITIES, R3 VIEW), the wave bar's → AUTO SKIP / ← TO PAUSE and the dealer card read the pad's glyphs.
6. Prompts on a pad: the drawn box with □, the object line and the action, the hold bar filling (doors, beacons, bags,
   the revive hold reads HOLD □ · REVIVE). On the keyboard they are Roblox's own again.
7. Sprint, PC: hold Shift → `» SPRINT` by the ammo, a wider FOV, no crosshair; click → the shot goes out at once and
   the sprint ends (`[GHS Input] sprint engage keyboard 1.20s ended-by fire`); still holding Shift, no sprint until
   it is pressed again. Pad: L3 → a tick rumble; it holds strafing and backing up; let the stick rest → `ended-by stick`;
   L3 again → `ended-by key`; R2 mid-sprint fires at once.
   Debug Sprint log on screen toasts each one.
8. Minigames (X opens at the prop): Lockpick ✕ / R2 on the mark with a tick as the pin enters the zone; Hotwire ↑ ↓
   (or the right stick) pick, ✕ grab, ↑ ↓ along the sockets, ✕ drop, a shock rumble on a wrong pair, △ COLORBLIND; Keypad and Charges walk
   the keys / caps with a gold cursor on the D-pad, ✕ presses (Keypad ○ takes back a digit); Safe dial at tiers 1, 2 and 3 with the
   right stick, ✕ locks a hot number (if tier 3 feels wrong, `SafeDialPadMode = "dpad"`); Freq: the right stick slides slowly
   (D-pad ← → nudge), R2 holds; Cut R2 depth is the pressure. ○ leaves any game; the left stick walks the whole time. Debug Stats prints a line per game per device.
9. The HUD on a pad is the PC HUD at the PC size, with glyphs; switching device never rebuilds it.
10. A phone and a pad in one 2-player Local Server: the phone keeps its layout and buttons; push the thumbstick through
    its ring and hold → the faint arc, then sprint with the » SPRINT mark over the stick; FIRE ends it and shoots at
    once; pump the thumb back inside the ring to sprint again. The pad player sees glyphs, the phone player none.

### Round 28e–28f verify list

Built and checked with `stylua`, `luau-lsp`, `rojo build` and `lune run tests/input.spec.luau`; in Studio Jack
confirmed scoped tracers show again (28e) and the white hit flash (28f); the rest is not yet played.

1. Phone (emulator, landscape), hub: no SWAP button on the hub HUD even with two guns; only the Roblox menu button top-left.
2. A run on the phone: FIRE is a little smaller, SWAP is round, POV sits left of the weapon slots and its three pips
   follow each tap (normal → far → first person → normal). Press ADS and keep dragging: ADS toggles and the camera
   turns; the same from SWAP, an ability tile or the gap above FIRE. Hip look is a touch faster, ADS look unchanged.
3. Aim assist (phone): strafe past an enemy with the look thumb still: the crosshair stays on it. Hold ADS with a
   resting thumb: small twitches keep the target; a deliberate swipe away lets go.
4. Open the pick-3 on the phone: the stick still walks and a drag outside the cards still turns the camera; a card taps.
5. ENGINEER: Overclock → your own gun fires and reloads faster for the window (Stats / the RPM readout), back after.
6. Shop crates ×1 and ×10: SKIP shows as the crate lands; SKIP on ×1 → the summary with one card; a ×1 that plays out
   shows CONFIRM with no SKIP.
7. Battle pass: GO TO CURRENT LEVEL only shows on a page that does not hold your level.
8. Skill Web: affordable hexes carry a red ! badge; ones you can't afford have grey names. Effect lines say "weapons".
9. Weapons / Classes / Avatar: Gold + opens the store on GOLD. Store: a tap on empty space inside the window keeps it
   open; a tap on the dim outside closes it.
10. First person, ADS through an ACOG / medium scope / sniper scope: a thin tracer leaves the barrel under the sight.
11. A fast gun on an enemy: a white body flash per hit plus the occasional white flinch pop, never red.

## Layout

See `default.project.json`. `src/shared` → ReplicatedStorage.Shared, `src/server` → ServerScriptService.Server,
`src/client` → StarterPlayerScripts.Client, `src/assets` → ReplicatedStorage.Assets, `src/map` → Workspace.Room
(`Room.model.json`, with the arena's Van / Lineup nodes) and Workspace.Bank (`Bank.rbxm` as Geometry,
`Bank.nodes.model.json` as Nodes); brief 8 adds Workspace.Hub (`Hub.rbxm` as Geometry, `Hub.nodes.model.json` as
Nodes). Brief 8: `src/server/Run/` holds every run-scoped module and is cloned per map at startup (`Runs.lua`); the
shared modules (below, unmarked) sit in `src/server/`: GameLoop (the entry), Runs, RemoteRouter, HubMap, Hub, Queue,
PlayerState, Profiles, Economy, RunEvents, Purchases, Grants, Shop, CrateOpen, Boosts, Vip, Pass, Jobs, Meta,
Progression, Stats, Log, brief 9's SkillService, and brief 10's Streak and DailyCrate. `Run/` also has Main (a slot's loop), Slot (its id and map), SlotRemotes and Range.

Server modules: World (run state, the party, `fireRun`, payout accumulators, heat effects, the run clock, the boss
view and the roster), Room (map refs including `Room.vault`), Stats, Profiles (DataStore), PlayerState (per-player run
state + profile-derived held / mask / wrap / class), Enemy (base) with `Enemies/` (Rig, Hazards, Ranged, Melee,
Marksman, Boomer, Grenadier, Heavy), Spawner (brackets, proximity markers, cap, elites), Heat (pace meter), Bags,
VaultJob, Boss with `Bosses/Titan`, Progression (XP, level, rewards), Roster (scoreboard rows), Combat, Economy,
UpgradeShop (`generate(state, wave, count)`, `applyCard`), WeaponRoll, BigCrate (`drop(at, { legendary })`, rolls),
Elements (element procs and statuses), Mastery (XP, tiers, kill passives), Dealer (the break, stall, stock), Pause
(the freeze and its hooks), CrewCall (the vault kind), Abilities, SkipVote, and brief 6: Purchases (the fake purchase
entry point and kind registry), Grants (applies rewards, dupes), Shop (Remotes.Shop actions, bundles, boosts), CrateOpen,
Boosts, Vip, Pass, Jobs, RunEvents (the run event bus), and brief 7: MapLoader (THE BANK's nodes, zones, the crew zone, the hatch
and ladder link), Doors (door props, objectives, zone gates, the vault site), EnemyPath (pathfinding),
Hub (brief 8: the warehouse: spawn, booth prompts and rig tags, the board, the shutters, the van and the departure beat, the range props and tier pad, the nameplate attributes), Queue (the four pads, Create Match, one party per pad, countdown, MAP BUSY,
PLAY AGAIN re-form), Meta (unlock / upgrade / equip actions), Minigames (sessions, log, stats, a tier override), Downed
(down / revive / bleed-out / game over / sidearm), AllyCallout (teammate radio lines), RunStart, RunEnd (payout, XP award, summary), Squad (dummy crew for
the sequences), Debug, Log; `GameLoop.server.lua` is the entry. All cash, Gold, HP, spawns, rolls, loot, minigame
results, bags, XP and revives are server-authoritative; every remote is created in `src/shared/Remotes.lua`. Shared
data: Config, Prices, Weapons (with `saleType` and the level math), Enemies (roster rows, scaling, brackets), BagSpots,
LevelRewards, Classes, AbilityGrowth, Masks, Wraps, Rarity, Upgrades, Types, Remotes, Signal, CrewCall/Lines, CrateReel
(reel timing), Callouts (ally lines), MasteryCopy (mastery copy and tier math), and brief 6: Products, Rewards,
Crates, Bundles, GoldPacks, BoostDefs, CashPacks, ReviveTokenPacks, PassSeason, JobPool, Clock (the fake clock),
MaskShapes, Poses, and brief 7: Maps (the map rows), Ground (the floor under a point), and brief 9: Skills (the web's node defs,
neighbours, affordability, `modifiers`), SkillLayout (the hex grid), and brief 10: StreakTrack (the streak's day math
and reward copy), Catalog (the daily crate's pool).

Client: ClientState (sync + juice bus + downed / camera mode flags + `inHub`), HUD components under `src/client/HUD`
(with `HUD.setMode` for hub / meta / downed / spectate / cinematic / boss and `HubHUD` for the hub layout; `BossBar`
under the wave bar; `Currency` with the Banked row), QueueUI (Create Match card, compact party card), MetaScene with
`src/client/Meta/` (MetaUI with the mastery bar, WeaponsTab, ClassesTab, AvatarTab), UpgradeOverlay, CrateReelUI (crate
tags and the reel), StatusFx (element looks, Eagle Vision marks), MasteryUI (the tier-up card), DealerUI (dealer card, stands,
shop panels; `UI/CardFace.lua` is the upgrade card look it shares with UpgradeOverlay), PauseUI (the overlay), GroundLoot, CrewCallUI (job cards, the vault pill, MARLOW's line cards, ally
callouts), Markers (beacon, bag and vault billboards, the vault chevrons), Minigames (Frame + one module
per game), DownedUI (bleed bar hooks, revive hold, downed markers), PlayerTags (busy tags over teammates), Nameplates (the hub nameplate), Spectate,
RunStartUI, RunEndUI (sequence cameras, poses, MVP stamp, summary with the XP row), BossCutscene, Scoreboard,
DebugPanel, Juice (rarity tiers), Camera, Gun, Main. Brief 6: PurchaseSheet, `src/client/Store/` (StoreScene, Fx,
Card, ItemArt, Sets, Models, Reveal, FeaturedTab, CratesTab, BoostsTab, VipTab, GoldTab, CrateScene),
`src/client/Pass/` (PassScene, PassSummary), `src/client/Jobs/` (JobBoard, JobSummary), HUD/BoostChips. Brief 7:
NodeOverlay (debug Show nodes and Path debug), DoorUI (the door hold bar and the open beat). Round 19d: Music (the
soundtrack), LockdownUI (the lockdown line and edge arrow). Brief 8: BoothMannequins. Brief 9: `src/client/Skills/SkillScene.lua`. Brief 10: `src/client/Retention/` (StreakModal, DailyPodium, DailySheet,
PlayRibbon, MatchCardLine, Round 27c's DailyGuide and SummaryCrateCard) and CameraShots (named camera frames on hub objects). Tools: `genmap.luau`,
`importbank.luau`, `genbanknodes.luau`, `importhub.luau`, `genhubnodes.luau`, `exportnodes.luau`, `nodestyle.luau`,
`rbxl-uncompress.js` (node).

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

- **Round 15i (4 Nov, feedback)** — when the vault seals, every placeable and ground field inside it is destroyed
  (`Abilities.clearWhere(Room.insideVault)`), so a turret left behind the door is no longer out of every enemy's reach.

- **Round 15j (4 Nov, feedback)** — ability tiles: a spare charge recharging while one is still in hand no longer
  looks like a full cooldown: the tile stays lit gold with a thin gold bar along its bottom filling toward the next
  charge and its seconds; the dark sweep only shows at zero charges; a returning charge pops `+1`. Every clock change
  floats on the tile: `+0.5s` gold when ADRENALINE JUNKIE extends Adrenaline (`AbilityExtend`), `-0.1s` / `-0.2s` for
  BACKDRAFT / OVERDRIVE trims, and `-8% CD` on all three tiles when ABILITY COOLDOWN is taken.

- **Round 15k (5 Nov, feedback)** — thrown abilities (frag, molotov, flashbang) reach twice as far (`ThrowMaxRange`
  52, was 26); longer throws arc higher (`ThrowArcPerStud`) and take proportionally longer past `ThrowFlightRefStuds`.

- **Round 15l (5 Nov, feedback)** — with the dial more lenient, the Safe asks for more: `SafeNumbersByTier` 3 / 4 / 5
  (was 2 / 3 / 4), and the vault follows the wave bracket through all three tiers again (`VaultSafeTierMax` 3).

- **Round 15m (5 Nov, feedback)** — `ThrowMaxRange` 100; `ThrowFlightRefStuds` 45 so a full-range throw flies about
  1.3s.

- **Round 16 (5 Nov, feedback)** — the Shooter archetype is cut (unavoidable chip damage, no counterplay; its weight
  went to the rest of each bracket). Thrown abilities aim-assist: the enemy nearest the aim point within
  `ThrowAssistRadius` 14 becomes the target and the throw homes on it in flight. Eagle Vision marks and slows
  (`EagleEyeSlowPct` 35%, capped `EagleEyeSlowCap`, the boss `EagleEyeBossSlowMult` of it; MARKSMAN'S KIT +10%)
  instead of the damage bonus. Friendly fields (molotov, burst oil drum) burn `AllyFireColor` blue with a segmented
  solid rim (`AllyFieldRim*`; the med bag gets the rim too). The camera lock state sits above the ammo (CTRL chip +
  CAMERA LOCKED / FREE). Safe dial: a number only counts when reached turning the asked way (entering its warm range
  from the far side keeps it cold), and every number crossed in the warm range clicks (`SafeTickPitch` /
  `SafeTickVolume`) with a thunk on the hot range. Freq: the slider spans a fixed band round `FreqCenter` so each
  target lands somewhere new (it used to sit at the same slider spot every time), and a lock releases the drag.
  Hotwire: Okabe-Ito palette plus a SYMBOLS toggle saved to the account (`profile.options.hotwireSymbols` through the
  new `SetOption` remote). Dealer stands are mini upgrade cards and the stand panel is the pick-3 card
  (`UI/CardFace.lua`, shared with UpgradeOverlay) with a price bar. Difficulty is live: `QueueDifficulties` rows carry
  `hpMult` / `dmgMult` / `budgetMult` / `goldMult` (NORMAL 1 / HARD / NIGHTMARE), the Create Party bonus row follows
  the pick. Floor guns carry only id + rarity: tags and the crate reel show the viewer's own Armory level and damage
  upgrades (`ClientState.gunAsMine`), and picking one up gives you your own level of it.

- **Round 16b (5 Nov, feedback)** — Hotwire keeps its original colors; the toggle is COLORBLIND and swaps to the
  Okabe-Ito palette plus the letters, repainting live. MARKSMAN'S KIT is reload speed only (Eagle Vision's slow no
  longer grows with it). The Create Party segments move their highlight to the pick. The dealer's big card replaces
  the stand's small card in place (anchored to its bottom edge) instead of floating above it. Aim assist uses what the
  cursor is on: the client sends the camera ray's origin and the hit part with the aim point, and the server locks the
  enemy under the cursor, else the one within `ThrowAssistRayStuds` of the camera ray (a head-height near miss that
  carried on to the wall), else the one nearest the hit point. Ally callouts moved to `AllyCallout.lua` and gained
  gold teammate moments (`bossKill`, `legendary`, `multiKill` at `CalloutMultiKill` 5, `masteryUp`); a finished side
  job's card is the completer's (`CallEnd.by` / `doneByText`). NPC portraits are a dummy avatar bust in a
  ViewportFrame colored per `Lines.portraits` (also the fallback when a player headshot is empty). The expanded dealer
  card is a ScreenGui that follows the stand on screen, so the nearer small cards (AlwaysOnTop billboards sort by
  distance) never cover it.

- **Round 17 (5 Nov, brief 6)** — the monetization front end, one commit per build step, against a fake Robux balance.
  (1) `Purchases.lua` / `PurchaseSheet.lua` and `Products.lua`, profile v3, revive tokens on SELF-REVIVE / REVIVE
  EVERYBODY with GET TOKENS and the SECOND CHANCE hold, the cash `+`, the new content (crate guns with silhouettes,
  masks on `MaskShapes`, wraps with materials, poses in `Poses.lua`), boost effects wired at the computation points.
  (2) The store scene on a private showroom set with the mannequin, header, tabs, entrance motion, the card component
  and the style kit. (3) GOLD and FEATURED with bundles, owned discount and the stacked reveal. (4) Crates: the roll,
  pity, dupes, odds panel, the opening scene with ×1 / ×N / SKIP / summary, tags and deep links on the customization
  tabs. (5) BOOSTS and the chips on both HUDs (the stub chip and `StubBoostSec` are gone); VIP with every perk, the
  dealer's greeting and R$ RESTOCK. (6) The battle pass: server, scene, HUD button, summary bar, season end. (7) Jobs:
  the run event bus, MARLOW's corkboard, the board screen, announce, toasts, summary ticks, scoreboard footer.
  (8) Debug additions, the purchase log readout, mobile fit, this README.
- **Round 17b (5 Nov, feedback on brief 6)** — buttons never move on hover any more (a plain button grows 4% instead;
  the old lift tweened buttons placed after creation off to the corner, which is how LEAVE / CONFIRM vanished and left
  you stuck); every brief 6 screen keeps clear of the Roblox top bar (`Fx.topInset`). The store is an overlay window with
  a left rail and one scrolling page (no showroom, no mannequin). The pass track is one row: a card per level, FREE
  large with PREMIUM / PREMIUM+ under it, and the layout moved down. Jobs: the three dailies fill the board, REROLL is
  gone (`JobRerollsPerDay` dropped). Revive tokens sit in the hub's BOOSTS corner as `×N`; PASS / JOBS moved to the
  right-center. VIP items no longer get their own Locker row. Crate dupe mastery tier-ups pop after that item's reveal
  (the server defers them into the results). A level skip no longer errors (the check missed its product argument), and
  a purchase check that errors now logs and shows its error instead of "the server did not answer".

- **Round 17c (5 Nov, feedback on brief 6)** — FEATURED is one wide bundle bar with its contents inline and BUY on it
  (no detail sheet, no owned discount, `BundleOwnedDiscount` dropped) over six daily single items from crates and past
  events (`DailyShop.lua`), both with `LEAVING IN hh:mm:ss`. Cards lose the empty pedestal bar, their art fills the well,
  sub lines sit under the title at a readable size; GOLD drops the shelf and the per-100 line; the crate art grows into
  the space under OPEN 1 / 3 / 10; REVIVE TOKENS · OWNED: N heads the token packs; LUCKY gets a 24 HR. VIP loses the
  dealer's greeting. Pass: four levels a page, three equal tiles under a LEVEL band, no lane legend or status line, HERO
  frames, the chase sell card, the stage opens on the level 30 hero. Jobs: reward icon tiles, a paid REFRESH on claimed
  Jobs, framed ticking timers. Hub: the `+` boost chip hides while a boost runs; in a run the chips sit above the cash.
  The crate's lid is a soft lootbox pop (a rising chime arpeggio and a sparkle) instead of a bang; the rattle, landing
  thump, flash and shake are all quieter. The debug panel caps at the screen height and scrolls.

- **Round 18 (7 Nov, feedback on brief 6)** — Pass tiles name their state in a footer strip: CLAIM (green, pulsing rim,
  halo, bobbing art, sparks on claim), CLAIMED (dimmed, a big check), LOCKED (padlock, lane color) and LV n (owned, not
  reached); a level with something waiting turns its band green; the detail card's pill matches (READY TO CLAIM /
  CLAIMED / LOCKED · PREMIUM / LV n · N XP TO GO) and a locked reward offers UNLOCK PREMIUM right there. The JOBS board
  is reprinted: cream paper with dark ink, eyebrows on ink tape, a real inset progress bar, DONE / PAID stamps, a big
  CLAIM above the rewards pinned to the card bottom, a drawn MARLOW bust on the poster and the announce card
  (`JobBoardStaggerSec`, `JobBarFillSec`, `JobStampSec`, `JobClaimPulseSec`). Reward reveals close on a tap anywhere
  (a first tap lands any cards still flying; no DONE button). The shop drops the R$ balance, closes on a tap outside the
  window, moves the bundle's LEAVING IN onto the FEATURED title row (it covered the price), adds REROLL on DAILY ITEMS
  (`DailyShopRerollPrice` R$ 25, a fresh per-profile draw for the day, `profile.dailyReroll`), sorts owned dailies last,
  quiets owned cards and keeps card titles on one line. The hub SHOP tile gets a red-dot breadcrumb for banked crate
  opens or the VIP gift and opens on that section. The Create Party boosts row is live (POWER / CASH / LUCKY open their
  duration sheet and show a running timer; REVIVE TOKENS shows `×N` and opens the packs). Boost chips (hub and match)
  are the glyph and the timer only. Locker tile tags (CRATE / VIP / ...) sit under the name instead of over it. Nine
  conditional "synergy" upgrades enter the pick-3 and the dealer only when they apply, at `SynergyChance` per slot with
  a small "FIRE SYNERGY"-style pill: WILDFIRE (Fire Ammo: a burning kill spreads the burn), SHATTER (Ice: bonus damage
  to chilled / frozen), AFTERSHOCK (Impact: a stagger shockwave), ELEMENTAL POWER (any element), and per class
  ACCELERANT (TORCH fire), TURRET DAMAGE (ENGINEER), HEAL POWER (DOC), DEAD EYE TIME (SHARPSHOOTER), BLAST RADIUS
  (INITIATE); conditions are a `requires` table on the stat (`Upgrades.meets`). Debug: NO COOLDOWNS and force SYNERGY.

- **Round 18b (7 Nov)** — Pass tiles drop the text footer: claimable glows green with breathing art and sparks,
  claimed goes dark under a big check, locked is veiled with a padlock, not-reached is dimmed (the lane color runs along
  the bottom edge). JOBS: NEW JOBS IN sits centered over the three dailies. Placeables go down where you stand
  (`StructurePlaceDistance` 0; players walk through them). Bags have no button: standing within `BagStartRadius` fills
  one over `BagChannelSec` and it is collected, the next one in reach starts at once and fills faster in a streak
  (`BagStreak*`); stepping off holds then drains the fill (`BagHoldSec`, `BagDrainPerSec`) and the bag stays yours until
  `BagKeepRadius`, so a pile empties without re-aiming; a world ring of ticks fills over the bag and it flies into you
  (`Client/BagChannel.lua`; `BagCollectSec` dropped). Weapons / Classes / Avatar: equipped is a big drawn check over the
  art plus a green outline (no EQUIPPED text); owned tiles lose source tags, unowned ones show a 3-letter source chip or
  the Gold price; rarity sits on the art box; weapons read "PISTOL · SEMI-AUTO" with the level heading the stats; tapping
  a weapon previews it in your hand (`Meta/GunPreview.lua`, `MetaWeaponPreview`), reverting on leaving the tab;
  scale-only hover and a select pop everywhere (`MetaTileHoverScale`, `MetaSelectPopScale`, `MetaEquipBadgeShare`).

- **Round 18c (7 Nov)** — Customization: the equipped check sits centered on the grid tile's art and nowhere else (the
  side panel loses it, the button is the plain EQUIPPED again); the sub line sits beside the name ("Skorpion  SMG ·
  FULL-AUTO") in all three tabs. The scoreboard shows the dailies and the bounty as small paper cards under the player
  rows (tilted in progress, straight with a green rim and glow when done, faded when claimed; `ScoreJobCardH`,
  `ScoreJobStaggerSec`, `ScoreJobFillSec`). The pass never ends: past `PassLevels` every level is a gold BONUS level
  whose three cells cycle `PassSeason.Bonus` (12 rows of Gold, tokens, crate opens, boosts, mastery), the track always
  shows a page past where you are and skips always fit (`PassOverflowGold` dropped). CRACK THE VAULT's window is
  `VaultJobDurationSec` (150, twice a side job).

- **Round 18d (7 Nov)** — Placeables (turret, barricade, healing turret, claymore, flame turret, oil drum) stand until
  destroyed (their `*Lifetime` keys are 0 = no expiry); the med bag keeps `MedBagLifetime` (15s). They still clear at
  run end and when the vault seals on them.

- **Round 19 (7 Nov) — brief 7 build: THE BANK.** Map 2 beside the arena, one commit per step: `Maps.lua` and
  `Room.forMap` (the arena's markers become spawn boxes; profile v4 moves `TheBank:*` to `Arena:*`; the hub tag's map
  suffix); the Bank import (`importbank.luau`, `genbanknodes.luau`, `exportnodes.luau`), `MapLoader` and debug Show
  nodes; `EnemyPath` pathfinding on every map; THE BANK on the card with the van on the grass, the crew zone, boss walls
  and dealer spots per zone and floor-aware placement (`Ground.lua`); door objectives (`Doors.lua`, kind `door` on the
  crew call); the vault on the wheel door with the server door, the hatch and the tunnel ring; spawn pressure (the
  crew-zone rule, zone hops, the line-of-sight re-roll, least-used boxes for elites, contact logs); debug MAP, the
  mobile pass and this README.

- **Round 19b (7 Nov) — feedback on THE BANK.** Door beacons show only the next unlock (and a called door; closed
  ones within `DoorBeaconRange`), signs stay on every door. Doors open their own way (Door node `Interact`): the
  front doors take a breach charge (the Charges minigame), chains are cut and shutters raised with a hold (CUT /
  RAISE), the vault is its dial. An opened door clears: the generated prop fades, the asset parts named in `Hide`
  vanish, and `HideWall` removes the wall a door is painted on (the vault's back wheel door was art on a solid wall,
  which sealed the server room and the tunnel); swung wheel doors stop colliding. The guide chevrons follow a walking
  route (`GuidePath.lua`: stairs, floors, the ladder) to the near side of the door. No bag spots outside the bank.
  New spawn boxes on the stairwells' corner landings. The street's crowd barriers stop players, not enemies
  (`EnemyPassNames`). Enemies step up stairs and sills (`EnemyStepHeight`: a higher hip with a non-colliding legs
  part) and hop a waypoint well above their feet. Catch-up: an enemy farther than `CatchUpDistance` from its target
  for `CatchUpSec` moves up its own route to a waypoint `CatchUpLead` studs short that no player can see. The bank's
  glass breaks (`Windows.lua`, `BreakableNames`): a player bullet, an enemy shot or a blast shatters a pane and the
  gap stays open; panes are whole again each run. Node labels in Studio and Show nodes read TYPE · name, only within
  60 studs and never through walls.

- **Round 19c (7 Nov) — feedback on THE BANK, part 2.** The vault ejects anyone inside once it seals (walked in as the
  door shut: `VaultEjectStuds`). The gameplay camera picks up facing the line's look (THE BANK's crew faces the
  building). No free intro crate on maps (`BigCrateIntroDropOnMaps`). Windows break as a unit (hit box per pane, the
  glass sheet and bars with it: `WindowGroup*`, `WindowHitboxThickness`). Catch-up lands at least
  `CatchUpMinPlayerDistance` from every standing player, `CatchUpMinGain` ahead, out of sight from the eyes and the
  camera height (`CatchUpCameraLift`); `CatchUpLead` 60. Enemy separation (`EnemySeparation*`): a soft push between
  neighbours, also while they hold. Bags scale with the party (`BagPartyScale`). Jobs: an R on any unfinished sheet
  rerolls it (`JobFreeRerollsPerDay`, then the REFRESH sheet, which now takes unclaimed Jobs too). CLAIM IN PASS on the
  summary sends you to the hub and opens the pass there (`SummaryPassOpenDelaySec`). `SideJobCaptureSec` 10 → 6. Dead
  Eye gives accuracy instead of speed (`DeadEyeAccuracyPct`). The dealer is a quarter cheaper (`ShopPriceByTier`,
  crate, heal, reroll). Fence nodes (new node type `Fences`, `Fence*`) close the strip behind the bank. The CLEAN IT
  OUT marker goes with the last vault bag. Alarms (`Alarms.lua`, `Alarm*`): the asset's alarm fixtures strobe red and
  clients hear the horn with a faint red screen edge during the vault's gas warning, for `AlarmHeatUpSec` on a whole
  heat star, during the new SILENCE THE ALARM side job and the zone gas warning. Zone gas (`ZoneGas.lua`,
  `ZoneGas*`): every 3-5 waves from wave 4 (Round 19e: 10) the crew zone is warned then gassed. New minigame Cut (bolt cutter, `Cut*`)
  on D2's chains and as the CUT THE CHAIN side job; a Cut test prop in the yard.

- **Round 19d (7 Nov) — audio pass, BGM, gas as a push.** SFX polish (`UI.sound` / `UI.soundAt`: SFX and Music
  SoundGroups, `SfxGain`, `SfxPitchJitter`, `SfxMaxVoices`; real library clips for shots, reloads, bags, kills,
  blasts, glass, gas, the alarm, doors and near misses; the blocked `swoosh.wav` replaced; preload at join) and a
  soundtrack (`Music.lua`, `Music*`: hub / calm / combat / boss / danger / summary with crossfades, resume and a
  cutscene duck). SILENCE THE ALARM opens a random minigame from `AlarmJobMinigames` (`AlarmJobHoldSec` dropped).
  No side jobs on the street once a zone inside the bank is open (`SideJobOutsideZones`). New door D5: chains across
  both vault stairwell heads (bolt cutter, wave 9, `SideDepth` railing walls); D3 opens the back only, the stairs
  zone, its boxes, bag spots and the landing job spot wait for D5. Lockdown gas (`DoorForce*`): a door objective left
  shut two waves past its call gasses every zone but the one behind it, with chevrons from every player, the loud
  beacon, a pinned line and a screen-edge arrow until it is open (`LockdownUI.lua`, debug `Lockdown`).

- **Round 19e (7 Nov) — audio feedback.** The music no longer drops between waves or under the alarms: one run track
  (`MusicTracks.run`) carries on through the whole run, only the boss fight and the run end switch (`calm`, `combat`
  and `danger` dropped). The run list is the lobby tracks' vein (Diamond Heist (a) / (c), The Heist (c), Smooth
  Operator, Half Stepper (b)) instead of the chase and ambient cues. The explosion clip is gone from the game (blasts,
  the breach) along with the chain crash on the bolt-cutter doors. The snap on tapping a gun in Weapons is gone. The
  lootbox got a sound set (`loot*` in `Theme.Sounds`, `ding` / `shimmer` / `chimes` / `pop` in `Store/Fx.lua`). Zone
  gas starts from wave 10 (`ZoneGasFirstWave` 4 → 10).
  Second pass: the bank's teller glass shatters like a window (`BreakableGlassSizes`: loose see-through sheets of a
  listed size become windows of their own in `Windows.lua`). The run playlist drops its jazzy / lo-fi cuts (Smooth
  Operator moves to the summary) for Masterstroke (a), Solid Crew (a) and Casino Hustle (a). Each bolt-cutter link is
  a metal snip (`Theme.Sounds.snip`) instead of the collide crash. The weapon type (PISTOL, SMG, RIFLE, ...) sits
  beside the name on the HUD weapon card, the floor gun tags and the crate reel's result (`Weapons.typeName`). Door
  waves spread out: D1 3, D3 7, D2 11, D5 14. THE BANK's first side job (wave 1, on the street) is always SILENCE THE
  ALARM on the Keypad (`BankFirstJobKind`, `BankFirstJobGame`); the alarm's pool is Keypad, Freq, Charges, Hotwire.

- **Round 19g (7 Nov) — zone waves and the door guide.** Door waves: front doors 2, upper floor (D2) 5, back of the
  ground floor (D3) 8, the vault stairwells (D5) 12. A door called for the first time guides the crew there:
  chevrons from every standing player re-planned every `DoorGuideRefreshSec` (5) for `DoorGuideSec` (20) or until it
  opens, the loud beacon for as long, and the lockdown's screen-edge arrow (`LockdownUI.lua`, event `DoorGuide`)
  whenever the door is off screen (`DoorPingDuration` dropped).

- **Round 19f (7 Nov) — the glass offices.** The four empty offices are a mini vault: RAID THE OFFICE (side job kind
  `office`) plays one of Lockpick / Hotwire / Charges / Cut at the door, the door and blinds blow away, bags drop
  inside, then alarm, gas, eject and reset (`Offices.lua`, `Office*`, new node type `Offices` with tag `GHS_Office`
  registered in genbanknodes / exportnodes / nodestyle / NodeOverlay, `Bags.fizzleIn`, debug `Office job` /
  `Open office`).

- **Art pass (7 Nov) — stand-in weapon art and icons.** `GunModels.lua` builds every gun (held, floor, store and crate
  models, icons) from a per-gun spec; the held gun rides a `GunJoint` Motor6D on the right hand and floor guns lie on
  their side on the invisible handle. `GunAnim.client.lua` poses every crew member's arms and gun procedurally:
  stances per kind (`GunPoses`), aim pitch, two-bone IK onto the grip and foregrip, recoil springs (`GunRecoil`),
  slide / pump / bolt / lever cycling, mag and shell reloads, muzzle flash and casings (`Gun*` in Config; teammates'
  state through the new `GunPose` remote and character attributes). 3D viewport icons for weapons, masks and wraps
  (`UI/ModelIcon.lua`, `ModelIcon*`) and frame-drawn pictograms for abilities, class emblems, boosts, upgrade stats
  and the dock (`UI/Icons.lua`). The wrap preview and the store mannequin paint every Wrap part (`GunModels.paint` /
  `snapshot` / `restore`); `HeldGunWrap` is gone.

- **Round 19h (7 Nov) — feedback on the art pass.** CUSTOMIZE hides the avatar and shows the gun alone, side-on and
  close, spinning in on open (`MetaGunStage*`, `MetaGunSpin*`; framing pulled back twice, pad 1.95). Picking an
  upgrade plays `Theme.Sounds.upgrade` (ProSoundEffects synth power-up rise, `UpgradeTakeVolume`). No minigame twice
  in a row: side jobs skip the last minigame overall and the last for their type (alarm, office, plain). The
  hold-to-HACK side job is out (`SideJobKindWeights.hack` 0); door shutters keep their hold. The gun pose now finds
  AnimationConstraint avatar joints and R6 rigs and ignores the looping class idles (it was not posing in play). The
  crate reel draws on a ScreenGui that follows the crate (ViewportFrame models don't render in a BillboardGui).
  Kill sounds: a UI bright click tick and a soft body-fall thud (`KillBodyVolume`) instead of the collide crash and
  Body Hits 8. A called door's guide stays up until it opens (`DoorGuideSec` 0).

- **Round 19i (7 Nov) — minigames finish as you walk off.** Each game plays a short success beat (up to 0.35 s)
  before it reports DONE; walking past `MinigameCloseDistance` during it closed the panel as a cancel and the DONE was
  dropped. The walk-away cancel now waits `MinigameWalkAwayGraceSec` (0.75) out of range (back in range resets it).

- **Round 19j (7 Nov) — upgrade pick sound.** The quiet riser is replaced by a bright power-up hit (ProSoundEffects
  Power Up Sweeteners 10, `Theme.Sounds.upgrade`) with the sparkle bell on top (`upgradeDing`), at a fixed volume
  (`UpgradeTakeVolume` 0.9, `UpgradeTakeDingVolume` 0.55) and natural pitch lifted per tier (`UpgradeTakePitchStep`)
  instead of the tier juice's pitch (0.7 on a common card) and volume.

- **Round 19k (7 Nov) — upgrade pick sound, take three.** The 19j hit was too shrill: the pick plays the designer's
  chosen clip (`sfx_menu_upgrade`, 85188753846582) alone at pitch 1 and `UpgradeTakeVolume` 0.5 (the bell layer and
  `UpgradeTakeDingVolume` / `UpgradeTakePitchStep` dropped).

- **Round 19l (7 Nov) — upgrade pick particles.** `Juice.sparks`: GUI chips (squares, slivers, dots) with gravity,
  drag, spin and a late fade, a shockwave ring and a glow, on their own top ScreenGui (`JuiceFxDisplayOrder`) so they
  outlive the overlay. Picking an upgrade bursts them off the card (`UpgradeFxSparkBase` + `UpgradeFxSparkPerTier` ×
  tier), trails sparkles behind the flying icon and pops at the tracker tile (`UpgradeFx*`).

- **Round 19m (7 Nov) — premium sets light up at once.** The showroom, crate room and pass stage moved from 3000+
  studs out (where their local lights took seconds to come up after the camera jumped there) into a row of sealed
  rooms under the arena floor (`PremiumSetsOrigin`, `PremiumSetsSpacing`), and `Sets.lua` builds all three at startup.

- **Round 19n (7 Nov) — the hub nameplate.** The one-line `LV 7 · TOP WAVE 14 ★ BANK` billboard became a
  client-drawn plate (`Nameplates.lua`): the level badge (the level card's emblem, chevron over the number, so no
  LV text) overlapping a near-black plate, the name in Oswald caps with a gold VIP tag, `★ WAVE 14 · BANK` under it
  (the class name before a first wave), a full-height class-coloured block with the class pictogram, a class tint
  from the left and a fading class underline. `Hub.refreshTag` now only publishes Player attributes (`Plate`,
  `PlateLevel`, `PlateTop`, `PlateMap`, `PlateClass`, `PlateVip`); the Roblox name hides locally under a plate.
  `NameplateOffset`, `NameplateHeight` (everything scales from it), `NameplateMaxDistance`, `NameplateShowSelf`.

- **Round 19o (7 Nov) — game-wide style pass.** Fonts are Font objects in `shared/Fonts.lua` (display Oswald Bold,
  body Builder Sans Bold, mono Roboto Mono), read as `Theme.Fonts` and set with `FontFace =` (a codemod moved ~330
  `Font =` sites; server signs require `Shared.Fonts`). The UI kit does the rest: `UI.corner` caps radii at
  `Theme.Corner` (4) except a full round on an offset-sized square; `UI.stroke` caps text outlines at
  `Theme.TextStrokeMax`; every TextLabel / TextButton from `UI.new` keeps display text in caps (rich-text tags kept)
  and multiplies its TextSize by `Theme.TextScale` per font (display 1.3, body 1.25, mono 1.15) so the narrower faces
  read at least as big as before (attribute `FixedTextSize` opts out; the nameplate does). Panels darkened
  (`bg` 0B0B0F, `panel` 15151A, `panel2` 1F1F26). HUD tiles (`Tile.lua`): the icon well fills the tile, the name is
  TextScaled up to 21, larger hotkey chip / price pill; ability column cooldown 30, charge pill, floats, BUY /
  class headers 20, boost timers, controls hint and camera chips up; `Theme.Desktop.tile` 80x90; the buy tile reads
  UPGRADE. Readability first: Jack rejected the first pass for tiny text.

- **Round 20 (7 Nov) — brief 8 build: the warehouse hub.** One commit per step. (1) Concurrent runs: `src/server/Run/`
  cloned per map by `Runs.lua`, client calls routed by `RemoteRouter` / `Run/SlotRemotes`, per-player sync from the
  player's own World, four independent pad parties with the MAP BUSY wait (`MapInstancesPerMap`, `MapBusyAutoStart`,
  `MapBusyText`). (2) The warehouse imported (`importhub.luau`, `HubOrigin`, `HubImportDrop`) with its first node set
  (`genhubnodes.luau`), `HubMap.lua` → `Room.forMap("Hub")`, spawn on the star, the pads, booth prompts, the board,
  the shutters; `exportnodes` serves both maps, Show nodes draws the hub. (3) The yard goes (`genmap`, the arena's
  Van / Lineup nodes, removed `YardWidth`, `YardDepth`, `DoorWidth`, `StationSpacing`, `PropSpacing`,
  `QueueZoneSize`, `QueueZoneCount`, `JobBoardPosition`), the departure beat (`HubDepartSec`, `GarageCloseSec`,
  `HubDoorRollSec`, `HubVanDriveStuds`, `VanDriveInStuds`), the arrival van as a copy of the hub van, the booth
  mannequins (`BoothMannequin`), the props and tier pad on their nodes. (4) The training range (`Run/Range.lua`:
  arming, `HUD.setMode("range")`, `ClientState.combatOff`, no scoring in the hub slot, immortal dummies with the
  readout and RESET, the plated dummy; `RangeAbilities`, `DummyCount`, `DummyScale`, `DummyHp`, `DummyHeavyPlates`,
  `DummyPlateRegrowSec`, `RangeDpsWindowSec`). (5) Debug HUB group, the RANGE sign prompt, README.

- **Round 20b (7 Nov) — first look at the hub.** The server stopped on load (TITAN's module still required `Log` / `PlayerState` / `Economy` from `Run/`; and the run modules waited on `Workspace.Effects` before anything made it), so nothing in the hub worked: both fixed. The builder's invisible collidable panels in the garage and range doorways are made passable at load (`[GHS Map] hub … invisible blocker`). Walking onto a booth's orange half-circle opens the customization scene on its tab (`BoothWalkIn`; the Station nodes now cover the half-circles; F still works). The range dummies are default R15 rigs (the plated one with a chest and a shoulder plate).

- **Round 20t (7 Nov) — hub dressing lives in Workspace.** Placed props are a real file now: `src/map/Hub.dressing.rbxmx` → `Workspace.Hub.Dressing` (visible and editable in edit mode). The range streetlight moved there (no longer built at runtime; its RangeLamp* Config keys are gone: edit the lamp and its SpotLight in Studio). To keep edits: select `Workspace.Hub.Dressing` > Save to File over `src/map/Hub.dressing.rbxmx` (restart `rojo serve` once for the new tree entry).

- **Round 20u (7 Nov) — minigame floors.** A tier 1 Keypad solved in 1.48 s (server clock, from the open) was failed by the 1.5 s `MinigameMinSec` floor, so the alarm job had to be redone. The floors are halved or less (Keypad 0.6, Freq 0.5, Cut 0.4, Safe 1, the others 0.7): still faster than a person plays.

- **Round 21 (8 Nov) — Jack's feedback list.** Jack confirmed the gun switch (after the ContextActionService fix) and asked for its gear sound; the rest is built unplayed. Two gun slots: you start with one, a pickup with the second slot empty goes there and you switch to it, with both full a pickup replaces the gun in your hands; key 1 (or tapping the new chip right of the weapon slot) switches, UPGRADE moved to 2 (`WeaponSlots`, `WeaponSwitchSec`; the mobile reload button moved right of the chip). Day / night: wave 1 at 20:00, every wave half an hour later, eased in as the wave starts; each client drives its own Lighting since runs share a server, the hub keeps the place's clock (`RunClock*`, client/DayNight.lua). The premium SHOP window and the JOBS board take 80% of the screen each way, text unchanged (`PremiumWindowScale`). Job reroll is a labelled REROLL button instead of a round R. Daily items sort highest rarity first (owned still last). Tab in the hub shows Roblox's player list with LEVEL / BEST WAVE leaderstats (Hub.lua); in a run Tab is still the scoreboard. Dealer: cards cost `ShopPriceByTier` x (1 + `DealerCardWaveMult` x (wave - 1)) x `DealerBuyStepMult` ^ cards bought this break instead of riding `UpgradePriceMult` ^ upgrades bought (wave 10: $416 / $2.9k for tier 1 / 5, was about $3.7k / $26k at 13 upgrades); ARMS DROP, HEAL ALL and REROLL scale by (1 + `DealerPropWaveMult` x (wave - 1)) (wave 10: $2.8k / $1k / $506); red DEALER LEAVES IN 15S / 5S toasts and a card punch (`DealerWarnSec`). A dealer card still counts toward the UPGRADE tile's escalation. THE BANK vault stairwells: an invisible, non-colliding basement light slab at y -0.5 under the whole ground floor still caught raycasts, so shots up the stairs stopped on it; MapLoader now turns CanQuery off on fully transparent non-colliding geometry without decals. Stragglers: an enemy more than `CatchUpFloorDelta` (10) studs above / below its target counts as far, the catch-up clock runs in every steer mode (one with no route used to stand still), and one still stranded after `StragglerWarpSec` (14) warps to a hidden spawn point near the crew (Spawner installs `EnemyPath.relocate`; `[GHS Path]` counts warps). A door job that comes up while a standing crew member is already inside a zone it opens (in through a shot-out window) opens at once, credited to them (`DoorOpensIfCrewInside`). SQUAD / MVP emotes: Salute, Stadium, Big Tilt, Shrug, Hello and Call Out used avatar-shop emote item ids, which never load as animations ("AnimationClip loaded is not valid" in the Studio logs), so they did nothing; Poses.lua now holds the Animation ids inside those items. Shuffle and Victory were copies of Groove and Cheer and got their own clips (Roblox Shuffle, Power Blast). Every emote plays at Action2 (`RunStartUI.EMOTE_PRIORITY`) so it no longer blends half-strength with the class idle at Action, the Avatar tab stops the previous preview first, and every emote clip is preloaded. Key 1 is bound through ContextActionService at high priority (it did nothing in the first play), and the server logs every switch request and why one was ignored (`[GHS Swap]`). Element cards on a first take read the element itself ("BURN" over "ON EVERY SHOT") instead of "NEW". Impact Ammo is now Stun Ammo on every card, tile and tracker (`STN`, effect STUN); the stat id `Concussive` is unchanged. The gun switch plays layered gear foley (`WeaponSwitchSounds`: Machine Gun Bolt 2 over Gun From Holster 1, ProSoundEffects; more candidates listed beside it) instead of the UI whoosh.

- **Round 24 (8 Nov) — mobile pass 2 + aim assist.** Built unplayed. Touch never turned the hub camera (touch drags waited on RMB while the cursor was free, which it always is in the hub): touch now turns it everywhere unless a menu blocks. A camera touch is vetted once, when it begins (right of `TouchCameraStartX`, not on GUI), then ignores `gameProcessed`, so the stick, FIRE and a look drag all work at once; the FIRE touch joins `ClientState.cameraTouches` and is released globally, so FIRE doubles as a look stick. `MobileButtonScale` (1.3): MobileControls sizes, `UI.mobileGrow` on the ability / buy columns and BottomCenter, `hubS` for every hub size and offset. FIRE / ADS / SWAP moved left of and above Roblox's jump button. Minigames: a mobile-only `host.zone` band behind the panel (`MinigameTouchEdgePct` / `MinigameTouchTopPct`) is an extra handle for Safe, Cut, Lockpick and Freq (`Frame.press` / `Frame.drag` take a handle list); Safe turns `SafeTouchGain` per finger degree. Meta / CUSTOMIZE drag-rotate direction flipped. Aim assist (new; only throws had one): Camera.client pulls toward the nearest enemy's torso inside `AimAssistConeDeg` / `AimAssistAdsConeDeg`, to its head when the crosshair sits above `AimAssistHeadBias` of the torso→head span on screen (with hysteresis), stronger while firing / ADS, with look friction near the target; touch / gamepad only unless `AimAssistMouse`.

- **Rounds 24b–24ag (8 Nov) — Jack's feedback rounds after Round 24.** Built unplayed unless noted.
  *Objectives / HUD:* doors have their own CrewCall slot (`DoorSupersedesSideJob` false), so a door no longer ends the side job; CrewCallUI keeps one box per slot (door / job / vault / line) stacked top-right; Markers key the job beacon by call id. World markers hide while `cameraMode` is cinematic. Hub RMB only drags (no ADS outside the range). The Weapons filter row is equal-width icon tiles (`MetaUI.iconPills`), a category switch selects its first owned gun, the detail well is shorter, and non-Gold items show a source badge (`MetaUI.wellSource`: crate / event / bundle / VIP / pass). Favourites: a heart on every gun / mask / emote tile, saved to `profile.favorites` (guns by id, `mask:` / `emote:` keys), sorted first (rarity high→low) with the rest low→high; a FAVORITES tile (weapons) and a FAV toggle (avatar). Two starter slots (`profile.starterWeaponId2`): EQUIP fills slot 2, with both full a popup picks the slot; runs and the range start with both. Premium store text is `MobileStoreTextScale` bigger on mobile.
  *Mobile:* landscape lock (client + StarterGui property — restart rojo after the project change); touch look polls each finger's live Position (the stick ate InputChanged) and ignores pinches that involve the stick thumb (that pinch froze look); FIRE / ADS / SWAP sit higher and diagonal round FIRE (`MobileFireRight` / `MobileFireUp`); `TouchSensitivity` 0.009.
  *First person:* FirstPersonView.client.lua draws a camera-locked viewmodel (a fresh GunModels build painted like the real gun, at `FirstPersonGunScale`) with forearms; the real body hides and its particles / lights switch off. Hip pose converges on the crosshair (`FirstPersonConverge`); ADS puts the sight line on the crosshair at a per-kind `FirstPersonAdsRelief`; sightless guns aim low and centred (`FirstPersonBareAdsGrip`); parts behind the sight that rise into the sight line fade when aimed. Per-kind recoil kick / flip (`FirstPersonRecoil`) plus a camera punch (`CameraRecoilDeg`), reload (mag out / in, shell nods), swap draw (`FirstPersonDrawSec`), empty pumping arms in the hub and while sprinting, steady eye with `FirstPersonBobKeep`. Crosshair hides when aiming an iron sight; optics draw their reticle (red dot, holo ring, ACOG chevron, medium / sniper crosshair) and magnify (`AcogFovMult`, `MediumScopeFovMult`, `ScopeFovMult` with the dark scope ring). Tracers (Tracer.lua) start on the muzzle attachment in every view (first person: pinned in camera space at the shot).
  *Guns:* iron sights rebuilt after real ones (pistol notch + dots, ghost ring + M front post, shotgun bead, carry ring) on a shared sight line (`SightY` / `SightZ`); optics: tube red dot, holo, ACOG, medium, sniper glass (snipers only), mixed across every type; muzzle devices, rail teeth, charging handles, two-tone receivers, inset panels; per-gun receiver silhouettes (`body`: stepped / humped / tapered / round / boxy / tall, which lift the sights clear) and an iconic-shape pass per gun (Desert Eagle profile, AK gas tube and sight tower, M4 A-frame, SPAS shield, 1887 lever loop, bolt rifles' full wood and bands...). New guns: Python, M93R, AA-12, M870, SVD, Kar98k, PKM, MG42; the Exogun / StormLinker / Railcaster / Hornet showcase guns are real (Crate / Event sale, debug UNLOCK ALL; energy tracers, a charged rail, a burst pistol). Weapon levels: damage +6%/level, mag / reload / fire rate soft-capped (`UpgSoftCap`, `UpgSoftScale`).
  *EXPLOSIVE / ELEMENTAL (Run/SpecialFire.lua, Weapons `mode`):* projectile guns fly server parts — RPG-7 on contact, M32 0.25 s fuse (direct hit = at once), Cluster Launcher 0.5 s then bomblets, TNT thrown with a 1 s fuse; lobs are solved onto the crosshair point (`LobMaxTargetStuds`) and roll after landing (`bounce`, `GrenadeRollKeep`). Flamethrower / Cryo Sprayer hit a cone each tick (burn / chill via `Elements.burn` / `Elements.chillOn`), the Arc Gun chains lightning, the Plasma Caster charges a long piercing beam (charge = width + hold time + ticks, steered by the cursor via `BeamAim`); ElementFx.client.lua draws jets, arcs and beams. Beams hit by a sphere swept against the enemies' real parts (heads and limbs count; headshot multiplier); Round 24ah: any part of the beam overlapping the head is a headshot, not only a first contact on it.
  *Aim / camera / abilities:* aim assist lets go when you pull off a target (`AimAssistPullAwayMult`, `AimAssistReleaseSec`) and a faint version runs on mouse (`AimAssistMouseScale`); an unlocked cursor centres the camera (`CameraCenterRate`); ability ranges, slows, durations and buff percentages soft-cap (`AbilitySoftCapBy`, `AbilitySoftCap`: Eagle Eye up to 3x, the rest 2x), damage / heal / HP stay linear. Swap with 1 works in the range.


- **Round 25 (8 Nov) — Jack's feedback rounds after 24ah.** Built unplayed.
  *Guns:* M93R full auto (15 dmg at 9/s). The Plasma Caster reads Plasma Gun (id kept) and is Legendary; its full-charge beam is half as wide. Aimed first-person tracers start off-axis in camera space, zoom-aware and widening with distance, so they read through sights and scopes (`FirstPersonAdsTracer*`). TNT leaves from hand height (`startDrop`) and an out-of-reach lob throws along the aim pitch plus a loft instead of 45° (`LobFallback*`). Iron sights: the rear notch / ears / ring no longer fade as "behind the sight" blockers (the pistol post floated over the slide).
  *First person:* eye `FirstPersonEyeLift` (0.9) above the head; against a wall the eye eases back and the gun lowers (`FirstPersonWall*`); RMB still held when a sprint ends puts you back in ADS.
  *Upgrades:* EXPLOSIVE synergies (Demolition, and Blast Radius widened) offered with an Explosive gun, Splash or INITIATE, raising Explosive guns, Splash kill blasts, Frag and Claymore; Elemental Power also comes with an Elemental gun and raises its damage (Upgrades `requires` gained archetype / owns / anyOf, `tag`). Ability Power now amplifies buffs, durations and radii (`AbilityPower*Share`). Defense category (above).
  *Run:* the shared crate's first roll draws from guns every member owns, each later roll from one member's own pool in turn. The dealer revives the downed / bled-out crew (`DealerRevivesCrew`) and prices cards off your UPGRADE price. Gas toasts show only near the gas (`GasToastNearStuds`). THE BANK vault gas never ended (VaultJob.init returned before its Heartbeat on maps without the arena closet); it now seals once nobody standing is inside or after `VaultGasMaxSec`. Bags, crates and ejected guns move out of walls / out-of-zone spots (`Ground.clearSpot`, `LootClear*`, a `WARN` log names bad bag spots); spawns re-roll points outside their box's zone or height or inside geometry (`[GHS Spawn] WARN box`). Loot / job beacon columns stop at the ceiling (`Ground.ceiling`). Teammate markers at any range with an edge arrow (TeammateMarkers.lua, `TeammateMarker*`).
  *Meta / UI:* a tile tap re-styles in place and rebuilds only the detail card (no viewport blink); grid and category viewports hold still; detail headings in the display face; successful upgrades / unlocks / buys burst off the button (`MetaSuccessSparks`); the class detail drops the ability list; equipping into slot 2 re-renders at once.
- **Round 26 (8 Nov) — the brief 9 build: the Skill Web.** Built unplayed, one commit per step. Step 1: `Skills.lua` /
  `SkillLayout.lua` (90 nodes from `Config.SkillNodes` on a five-ring hex web), profile v5 (`skills.owned / seen`),
  `SkillService` (SkillBuy / SkillSeen, debug unlock / reset / grant, the stats print), `PlayerState.armSkills` at
  the run start and range entry, and every hook (Weapons.atLevel's skill bonus, Stats.compute, Combat / Abilities
  elite-boss-ability damage, armor / toughness / regen, cooldowns, revive / bleed-out, door / hack holds, bags, seed
  money, haggle, fence, `Rarity.applyLuck` for the pick-3, dealer and gun crate). Step 2: the SkillScene (blurred
  overlay, hex canvas with pan / zoom / pinch, states, lit edges, the sheet, the buy beat) and the SKILLS tile under
  SHOP; new pictograms (skills, star, die, arsenal, crown, boss, hand, moneybag, magnet, goldbar). Step 3: the tile's
  count badge and first-time pulse, the summary's `N SKILLS AFFORDABLE`, MARLOW's intro line, the pulse-once
  `seen` set. Step 4: the phone pass (56 px hexes, the 40% sheet with a thumb-sized BUY, the legend collapse, store
  text scale, the tapped hex eased out from under the sheet) and this README.
- **Round 26b (8 Nov) — Skill Web feedback.** Unplayed. The sheet is a compact card (no more full-height column):
  the well sits beside the name and effect line and the price rides on BUY. Revealed hexes wear a dark shade of their
  branch colour and go bright and saturated when owned; ? hexes stay grey and never light the legend. Hexes past the ?
  ring are hidden, so the web grows as you progress. Costs vary inside a ring (`SkillCostByStat` weights,
  `SkillCostRepeatStep`, tidy rounding; an optional third field on a `SkillNodes` entry overrides the weight). The
  web opens centred on START zoomed all the way in (`SkillOpenZoom`), and a tapped hex glides to the centre of the
  space beside the sheet. Every effect line rewritten in plain words; LUCK reads "+3% odds of rarer upgrade cards when
  you buy a pick-3 in a run" / "… at the in-run dealer" / "… guns from in-run gun crates (not SHOP crates)".
- **Round 26c (8 Nov) — START is bought too.** Unplayed. START costs `SkillStartCost` (250) and its effect is UNLOCK
  SKILLS. Before it is bought the web is START (priced, pulsing) with the six ring-1 hexes as ? around it, nothing
  farther, and an empty legend; a fresh profile's SKILLS badge reads 1. Buying it plays the unlock: START ignites (a
  warm flash, two gold shockwave rings, the rising ding stinger), SKILL WEB UNLOCKED drops in under the top bar with a
  one-line hint, the six ring-1 hexes turn over clockwise from DAMAGE in their branch colours with a burst and a rising
  ding each while that branch's legend row appears, then the next ? ring fades in. `START` is now stored in
  `skills.owned`; a profile that already owned nodes gets START on load (no version bump). Debug Unlock all / Grant
  open the web too.
- **Round 27i (8 Nov) — leaving the podium view.** Unplayed. Leaving the daily crate's zoomed-in view eases the camera back to the gameplay camera over 0.45 s (`CameraShots.release`) instead of snapping; the snap read as the hub's lights going off for half a second while the engine re-lit after the camera jump. The podium sheet loses its BACK button (the X, Esc / B and a tap off it close it).
- **Round 27h (8 Nov) — the PLAY bar.** Unplayed. The first-run bar under PLAY is as wide as PLAY (its icon and words shrink about the centre to fit, `PlayRibbon.build` fit scale), and a tap on it is a tap on PLAY (onto the nearest open pad and into Create Party).
- **Round 27g (8 Nov) — START OVER, the camera after a crate, the bar, Reset daily.** Unplayed. START OVER on a lost streak no longer pays out day 1: it resets the streak (day, count, last claim) and the modal rolls its row back to day 1 waiting for CLAIM. After a daily crate opens, control comes back under the crate scene's black (it held the podium shot for about 2 s). The first-run bar's light sweep sat in the bar's list layout as a block on the left; the icon and words now have their own centred row. Debug Reset daily (x2 + crate) resets the x2 XP flag and the daily crate together (locked, never opened), so the first run of the day can be tested end to end.
- **Round 27f (8 Nov) — podium fixes.** Unplayed. The spot over the daily crate podium no longer shows its lamp housing (a dark block floating in mid-air; the light stays). The podium prompt waits for the prompt to replicate and re-applies its words every second, so a claimed crate reads VIEW instead of the server default OPEN.
- **Round 27e (8 Nov) — one streak action, the HUD under crate scenes, the first-run bar.** Unplayed. The streak
  window has one action button at the bottom centre (CLAIM when today is claimable, GET DAY N NOW · R$ 29 when not;
  a lost streak keeps RESTORE and START OVER) and the free countdown moved into the header beside IN A ROW. Every
  crate scene hides the HUD while it plays and puts it back after (the streak's crates opened over the hub HUD). The
  first-run line is a glowing amber bar under PLAY (no longer over its top edge) and the same bar on the Create Match
  card: amber gradient, crate pictogram, pulsing glow, light sweep, slow breath.
- **Round 27d (8 Nov) — the daily pool, streak crates, a richer streak window.** Unplayed. The daily pool takes the
  default gun of each category (Common goes from 3 items to 7, so no one Common keeps coming back); the 27c
  unowned-first / no-repeat logic is gone (a plain uniform pick inside the rarity). The streak track gives a crate on
  day 1 and every 2-3 days, and every streak crate is the daily crate at the week's tier (`StreakCrateTierByWeek`:
  BASIC, GOLD, DIAMOND, ELITE), not the paid Arms / Mask crates. The streak window: a graded panel with a warm glow
  under the header and a gift mark; cards tinted by what they hold (the daily crate in its tier's colour, Gold amber,
  the CASH boost green, pass XP orange) with a halo behind the art and the amount in that colour; a solid band across
  each card's top (gold TODAY, green with tomorrow's countdown, DAY N otherwise) instead of the small tab; the row
  never scrolls past its ends (no gap on the left early in a week); once today is claimed the bottom reads FREE IN
  <countdown> beside GET DAY N NOW · R$ 29, offered every time (`StreakSkipsPerDay` 0).
- **Round 27c (8 Nov) — streak look, the sheet everywhere, can't-miss-it, fair rolls.** Unplayed. The streak modal
  goes back to the house look (dark panel, gold edge, condensed caps) keeping the format: a small IN A ROW counter in
  the header instead of the big calendar, a wider row with the current day always centred, drag to scroll (no wheel),
  a glide to the new day after a claim or skip, bare countdowns. The podium sheet opens in every state (contents strip,
  odds, a ticking countdown, BUY 1 · R$ 99 while locked: product `dailycrate_buy`); E reads VIEW / OPEN. The floating
  CTA is about half the size with no tier word; plaque and CTA count down instead of BACK TOMORROW. The run summary
  shows a DAILY CRATE UNLOCKED card on the left (tap: to the lobby, the sheet opens on landing); the hub adds a
  flowing floor chevron trail, an edge arrow and MARLOW's nudge while the crate is ready. (Round 27d: the
  same-rarity unowned-first / no-repeat rule was taken back out.) The crate scene's exit holds its black
  `CrateExitHoldSec` (0.7 s) after the world's lighting comes back, so the hub no longer shows with its lights "off"
  for a second (the scene swaps the lighting to daytime and the engine re-lights the hub on the way back).
- **Round 27b (8 Nov) — streak modal redesign, the podium moved.** Unplayed. The streak modal opens once every
  session even with nothing to claim (`StreakOpenEverySession`) and sells GET IT NOW · R$ 29 (product `streak_skip`,
  `StreakSkipPrice`, `StreakSkipsPerDay`: tomorrow's reward now); it is redrawn in the reference's layout: gradient
  panel, big DAILY STREAK, a calendar with the days in a row (new `streak.count`), one sideways row of big reward
  cards to the end of the week plus `StreakPeekDays` and a MORE card (the week 2–4 rows, the reward line and most words
  are gone); after a claim it stays up on the claimed view (tomorrow's countdown and the skip). The shelving by the
  range door is back; the podium stands where the red and blue drums were (`HubImportDropAt` now drops the drums;
  the `DailyCrate` node moved and faces the star), lit in every state with sparkles, a floor glow and an overhead
  DAILY CRATE header with a state pill (PLAY A MATCH TO UNLOCK / OPEN NOW! / NEW CRATE IN …) and a bobbing chevron.
- **Round 27 (8 Nov) — the brief 10 build: retention.** Built unplayed, one commit per step. Step 1: profile v6,
  `Streak.lua` (the fake-clock day math, CLAIM / START OVER / the VIP restore, the paid RESTORE as product
  `streak_restore`), `StreakTrack.lua`, `Config.StreakRewards`, the modal (`client/Retention/StreakModal.lua`),
  MARLOW's announce held behind it (`Jobs.hold`), crate rarity floors (`CrateOpen.open(..., floor)`), FIRST HEIST OF
  THE DAY on the fake clock, debug Set streak day / Break streak. Step 2: the boxed shelving dropped from `Hub.rbxm`
  (`HubImportDropAt`, `importhub.luau drop`), the `DailyCrate` node (`genhubnodes.luau append`; registered in
  exportnodes, nodestyle and the node overlay), the stand built by `Hub.lua`, `CameraShots.daily`. Step 3:
  `DailyCrate.lua` (unlock at the summary, tiers by level, `Catalog.dailyPool`, the first-gun rule, OPEN, ROLL
  AGAIN as product `dailycrate_reroll`), the daily tiers as lookup-only crates (`Crates.dailyId`), `DailyPodium.lua`
  and `DailySheet.lua`. Step 4: the PLAY ribbon and the Create Match line. Step 5: the daily-crate debug rows, the
  phone pass (full-width streak card, the store's mobile text factor) and this README.

- **Round 28 (8 Nov) — the brief 11 build: the input pass.** Built one commit per step (step 2 first), played by Jack
  once at the step 2 checkpoint; the rest unplayed. Step 2: `GamepadMap.lua` (shared, pure: the map, the router with
  the X rule and Create tap / hold, the look math, the device tracker), `Input.lua` (the pad into the keyboard's
  paths, the device with its 0.75 s hold, `[GHS Input] device` / `assist … hits N/N`), the right stick in
  `Camera.client` (no cursor, no Ctrl mode on a pad), `AimAssistScale` per device, `Haptics.lua`, the Input monitor,
  the debug INPUT group, `settings.input` on the profile with `Remotes.SetInputSetting`, `tests/input.spec.luau`.
  Checkpoint 1 (Jack on the DualSense): there is no settings screen, so Create is the scoreboard (tap toggles, hold
  peeks); ability 3 felt wrong on R3, so after weighing three layouts the abilities sit on L1 / R1 / ○ and R3 cycles
  the camera view (normal → fully out → first person); D-pad ↑ buys the upgrade pick (teleport at the dealer); the
  hub leaves Create to the HUD selection toggle; pad aim assist 0.6 → 0.75; every key label shows the pad's glyph.
  Step 1: `shared/Glyphs.lua`, `InputGlyphs.lua` (drawn chips: □ ○ ✕ △ shapes, shoulder / trigger / stick caps, a
  D-pad cross with the pressed arm lit, key caps; hidden on touch), `Hint.lua`, `PadPrompt.lua` (prompts in a drawn
  Custom style with the glyph on a pad only); the ability / upgrade / swap chips, the ammo hint, the dealer card and
  stands, the revive line, the wave bar, the scoreboard, the pick-3 line, the class hotkeys and the server's HOLD E
  lines all follow the device. Step 3: `shared/SprintRule.lua` and `Sprint.lua` (Shift / L3 / touch push-through,
  hold or toggle, the re-arm and the fire cooldown; the server ends a sprint on a shot instead of dropping the shot;
  the FOV push, no crosshair, the SPRINT mark; `[GHS Input] sprint engage …`). Step 4: `GamepadNav.lua` (contexts from
  the screens' block / movement-lock reasons, geometry walk in `shared/NavMath.lua`, A = Roblox's activation of the
  selection, B = each screen's back, L1 / R1 tabs, L2 / R2 page), `SelectionRing.lua`, the hub HUD toggle, the Skill
  Web hex cursor, the CONTROLS sheet (`InputSettingsSheet.lua`), debug Show nav, `[GHS Nav]` logs. Step 5: the
  minigame pad layer in `Minigames/Frame.lua` and the seven mappings, `SafeDialPadMode`, the Stats device split.
  Step 6: `UiScaleGamepad` (HUD, prompts, minigame panels), `SafeAreaPct` (the HUD on a pad), the hover audit (the
  mastery and pick-3 tips and the model icons also answer to the pad's selection), this README.
- **Round 28b (8 Nov) — console fixes after the first pad pass.** Screens use Roblox's own gamepad selection again
  (its highlight, movement and ✕): the custom ring and the custom D-pad walk are gone, and `GuiService.AutoSelectGuiEnabled`
  is no longer switched off (that was why Create showed no selection while the pad stopped moving the character).
  GamepadNav now only picks the first button when a screen opens, keeps the selection inside it, starts Roblox's hub
  toggle on PLAY and keeps L1 / R1 tabs and L2 / R2 paging. The pad HUD scale and safe area are out: the safe-area
  frame broke the hub / match HUD switch (the wave bar's floating HUB showed in the hub), and any pad press after the
  keyboard rebuilt the HUD into that state (the R2 "swap"). The pad HUD is the PC HUD at PC size. L3 sprint is always a
  toggle that holds in any direction (`SprintPadStopGraceSec` 0.3 before a resting stick ends it); the SPRINT · PAD
  setting is gone.
- **Round 28c (8 Nov) — console pass 2.** D-pad ← votes pause and → votes skip (↓ is free; the dealer's D-pad
  stand walk is gone, walk to a stand to browse); □ buys at an open dealer panel (its line already showed □). The
  selection moves to the geometric neighbour (GamepadNav points Roblox's NextSelection* at it: the button directly
  below wins over a nearer diagonal) and stays where it was after a press rebuilds the screen. Customization: L2 / R2
  the booths, L1 / R1 the weapon types / classes / avatar categories. Skill Web: landing on a hex opens it, ✕ buys,
  ○ closes and stays. The summary starts on PLAY AGAIN (its guis are walked together), bleeding out on REVIVE
  EVERYBODY. Minigames leave the left stick to walking: Hotwire and Freq moved to the right stick (Freq at a slow rate,
  `FreqPadSpeed`, with D-pad nudges), Keypad and Charges have their own D-pad cursor. Hip fire on a pad has its own
  assist cone and pull (`AimAssistGamepadHipConeDeg` / `AimAssistGamepadHipPull`). The CONTROLS buttons and the range
  door's prompt are gone.
- **Round 28d (8 Nov) — Freq speed, crate confirm, AUTO SKIP.** The Freq needle on the right stick is twice as
  fast (`FreqPadSpeed` 0.35 → 0.7). The crate scene pushes its own selection context, so NEXT / CONFIRM / DONE come
  up selected on a pad wherever the crate was opened (store, daily podium, streak claim); a screen's marked next step
  (NavDefault) now wins when the old selection disappears. V and D-pad → toggle AUTO SKIP in every phase of a run
  (they only voted in an intermission before; AUTO SKIP is also the intermission vote); at the dealer they still skip
  the break.
- **Round 28e (9 Nov) — mobile, aim assist and meta feedback.** Mobile HUD: SWAP is round and only shows with the gun
  controls (never on the hub HUD); FIRE draws at `MobileFireScale` (0.9) around the same centre; a POV button left of
  the weapon slots fires the pad's CameraCycle (three pips show `ClientState.cameraView`). The HUD ScreenGui carries
  `TouchLookThrough`, so a touch that starts on one of its buttons still becomes a camera touch (Camera.client
  `looksThrough`); ADS toggles on press. Touch hip look x `TouchHipSensitivityMult` (1.2). The pick-3 overlay on touch
  only blocks look through `lookBlocked()` and its dim is not Active, so the stick and look work around the cards.
  Phones hide Roblox's top-bar row (`MobileTopbarHidden`; its light look follows the player's Roblox theme and can't
  be restyled). Aim assist: tracking follows the target's drift across the screen (`AimAssistTrack` 0.7 /
  `AimAssistAdsTrack` 0.9, keeps the offset, never drags onto a target), stronger pull (7 / 12) and friction (0.5 hip,
  `AimAssistAdsFriction` 0.35 inside `AimAssistAdsFrictionDeg` 7), and a pull-away must add up past
  `AimAssistReleaseDeg` (1.5°, draining at `AimAssistReleaseDrain`) before it lets go. ENGINEER's Overclock also
  speeds the caster's own gun (`OverclockSelfGunShare` of the RATE bonus on fire rate and reload; with CREW OVERCLOCK
  the larger applies). Crates: SKIP from the first drop, ×1 included (a skipped ×1 lands on the summary). Battle pass:
  GO TO CURRENT LEVEL hides while the current level is on the page. Skill Web: a red ! breadcrumb on affordable hexes,
  grey names on short ones; generic damage / elite / boss / crate luck / elemental lines say "weapons". Meta Gold +
  opens the store on GOLD. The store closes only on a tap outside its window (the tap position decides; on touch the
  window let taps on its empty space through to the dim). Scoped tracers: Roblox draws no beams behind a Glass part,
  so the first-person viewmodel's lenses are SmoothPlastic.
- **Round 28f (9 Nov) — tracer origin, hit flash.** An aimed first-person tracer starts on the viewmodel's muzzle
  (pinned in camera space like hip fire; `FirstPersonAdsTracerStart` is only the fallback) and widens far less
  (0.04–0.15 studs; it drew a wedge beside the crosshair). The per-hit body flash is `HitFlashColor` (white, was red)
  for `HitFlashSec` (0.08); the throttled white flinch pop is unchanged. (A single held white Highlight was tried and
  dropped: flat and washed out under fast fire.)

## Open design notes (not built)

- **Brief 11 notes and deviations (Round 28, mostly unplayed).** There is no settings screen in the game: the INPUT
  page is its own CONTROLS sheet (parked since Round 28c: no button opens it), and Options / Start stays Roblox's
  menu, so "Options opens settings" and "Menu holds the scoreboard" became Create = the scoreboard (Jack's call at
  checkpoint 1). The abilities sit on L1 / R1 / ○ and R3 is the camera view cycle (checkpoint 1); ○ is still back in
  every screen because a screen turns the combat map off. MARLOW's cards time out on their own as before: ○ in a run is
  ability 3, so "B dismisses" is not wired. `InputDevice` is `ClientState.inputDevice` with `ClientState.DeviceChanged`
  (no separate module). Glyph style "auto" is PlayStation unless Roblox names the pad's ✕ as Cross; Roblox does not
  report the pad model reliably. Roblox does not report the DualSense touchpad click, so it does nothing. Screens use Roblox's own selection (Round 28b) rather than per-screen groups; the customization scene has two levels (L2 / R2
  booths, L1 / R1 their categories); the store's tabs and the pass pages are on L1 / R1. A tapped-open scoreboard is a screen (the pad
  sits on VOTE PAUSE and the character stops); a held peek stays in play. At the dealer you walk to a stand to browse (Round 28c took out
  the D-pad stand walk). Round 28b took out the 10-foot scale (`UiScaleGamepad`) and the HUD safe area
  (`SafeAreaPct`): the pad keeps the PC sizes. Touch push-through measures the raw touch against Roblox's own
  thumbstick ring (read from `TouchGui` when it can be, else `SprintTouchRingPx`): Roblox's knob cannot be restyled,
  so the sprint mark rides above the thumbstick instead of on the knob. The Safe dial's A locks a hot number at once
  (holding in the hot range still locks too); the Cut trigger reads the depth held 0.15 s before the release.

- **Brief 10 notes and deviations (Round 27, unplayed).** The first-run flag the brief calls `stats.firstRunDay` is
  `profile.lastHeistDay` (Progression), and the summary line reads `FIRST HEIST OF THE DAY ×2` as before; it was on
  real UTC and now uses the fake day, so `+1 day` resets it with the crate and the ribbon. Streak crate rewards roll and
  open in the crate room on claim rather than as banked `crateOpens` (the brief's "nothing is banked" wins over "a
  tagged free open"); the week 1 / 2 single opens open the same way. The day 7 crate is `floor = 3` (Common and
  Uncommon removed, so it really is RARE+; the brief said "Common removed"); weeks 3 and 4's unnamed "2 free opens"
  are 2 Arms and 2 Mask opens. The "1-run BOOST" is a 30-minute CASH boost (boosts are timed; there is no per-run
  boost, and CASH is +50% here, not +25%). "STREAK LOST · DAY 12" names the day today's claim would have been, and a
  restore claims that day. The X / Esc / B on a lost streak mean START OVER (the no-dismiss rule): an accidental Esc
  costs the streak, so this may want a confirm. VIP's restores count in a window (`vipRestoreDay` +
  `vipRestoresUsed`, an extra field so `VipStreakRestores` above 1 works). There is no pass first-time pulse to queue;
  the SKILLS first-time pulse waits instead. MARLOW's card plays 1.5 s after the claim (8 s when the claim opened a
  crate). The catalog already tags every item's source as `saleType`, so the pool filters on it (no new `source`
  field): Direct guns and masks, the default guns included (Round 27d), minus the plain mask. Only five Direct masks exist (one Epic), so masks are
  a small share of the mix. The podium's stand is built at run time by `Hub.lua` from the node, as the brief says, not
  a `Hub.dressing.rbxmx` prop: move the `DailyCrate` node in Studio (and `DailyCratePodiumScale`) to place it. The
  builder's props are unnamed `Model`s of plain parts, so `HubImportDrop` (name matching) cannot find them: a
  positional twin, `HubImportDropAt`, does, and was applied to the baked `Hub.rbxm` (the builder's place is not in the
  repo); Round 27b points it at the two drums instead of the shelving. Round 27b: a paid skip counts as a day in a
  row (the calendar), and the overhead CTA is a BillboardGui drawn over walls at a constant screen size. "Through walls" is an AlwaysOnTop `Highlight` on the beacon column; the idle swell is the lootbox wind
  chimes looped quietly as a 3D sound. CameraShots is a new client module (there was none). The debug rows sit in the
  MONETIZATION group (there is no META group). None of this was seen on a screen: expect size, colour and placement
  passes.

- **Brief 9 notes and deviations (Round 26, unplayed).** Round 26b: the brief's "about 300k" did not match its own
  ring costs (6 × (500 + 2 × 1,500 + 3 × 4,000 + 4 × 10,000 + 5 × 25,000) is about 1.08M); with the stat weights the
  web is about 1.2M. Cost is no longer by ring only (Jack's call). The canvas is a plain Frame with a UIScale, not a
  `CanvasGroup`: a CanvasGroup bigger than the screen renders into a capped texture (blurry when zoomed) and
  re-renders on every pan step. Hexes are frames (three rotated bars for the edge, three for the fill), so a faint
  hex is an edge with a backdrop-coloured fill. Stacking: damage / type damage / mag / reload add to the Armory
  level's own multipliers (the brief's order); HP, move speed, regen, crit and headshot have no Armory stat, so they
  sit on the base under the run's upgrade multipliers; COOLDOWN multiplies the base before (and outside the cap of)
  the run's ABILITY COOLDOWN. ELITE / BOSS DAMAGE apply to every gun and ability hit on an elite / TITAN (splash and
  ricochet included); ABILITY DAMAGE to ability hits only (not heals or placeable HP). BAG VALUE raises cash bags (each
  member's own share); gold bags are FENCE, which raises the banked Gold this player is paid (the team's banked total
  and the best-banked record stay the raw total). QUICK HANDS: door holds on the server and the side job HACK prompt
  shortened on each client (the server never times a prompt hold); minigames, revives and the bag fill are not
  touched (REVIVE SPEED and FAST HANDS are their own nodes). The Gold spend goes through `Profiles.tryCharge` like
  an Armory level and logs `[GHS Economy]`; the purchase readout (the fake-R$ log) does not list it. A buy is
  refused in a run; in the range it applies at once. The badge is a red circle with the count (the pass's dot has no
  number); the first-time pulse is the tile's edge breathing white for 2.4 s once per session while you own only
  START (the pass has no first-time pulse to copy). `seen` keeps every node seen affordable on an open, so a node
  that drops out of reach and comes back does not pulse again. The summary line says `1 SKILL AFFORDABLE` in the
  singular. Ids use the stat key in lower case (`survival_maxhp_1`, `arsenal_explosiveammo_1`). Debug Grant takes
  the ring's first unowned node of the branch. The SKILLS tile hides in the range like the other hub-only tiles
  (SHOP stays there). The web was never seen on a screen: expect size, colour and text-fit passes.

- **Brief 8 notes and deviations (Round 20, unplayed).** The hub's nodes were authored from the asset read in Lune
  (no Studio look), so expect drags. North is −Z in the warehouse: the pads and the board are on the north wall, the
  garage opening is in the east wall (the brief's "north-east corner"), the range door in the west wall. The asset's
  openings have no door panel, so the garage and range "roll-up doors" are shutters the hub builds (GarageDoor /
  RangeDoor `Mesh` is empty: set it to a model name to use an asset part instead). The van was parked straddling the
  garage opening; its node moves it fully inside, nose to the door, so the shutter can close. The dummies stand at the
  far (west) end of the bay facing the door rather than on the striped pad by the door (that pad is the firing
  line); the props stand along the bay's north wall, the tier pad by its south wall. Seven PropSpots (the seven
  minigames, Cut included), not eight. Shutters and the van move on the server (everyone sees them) rather than as a
  client-side animation. The arena's drive-in now uses a Van node inside the room (`DriveIn` 50) since there is no door
  to drive through. `IntroSec` counts from the cut, so a run start is `HubDepartSec` longer. `MapInstancesPerMap`
  above 1 is capped (the geometry is one copy). Range enemies are pulled back to the bay's centre when they wander
  out (no PathfindingModifier wall). The booth mannequins are copies of your character (the store's mannequin way),
  so the arms are not posed on the gun. The 105 CollectionService tags in the builder's place were dropped on import
  (Lune cannot read them; nothing reads them). The Lighting of the builder's place (5 children) is not imported.

- **Round 19f notes.** The office nodes were placed from the asset's geometry (the glass walls at z 63 and x ±77.3,
  the dividing wall at x 0, the carpet floors), not seen in Studio; a dry run of the door rule against `Bank.rbxm`
  finds 11 door parts and the blinds for each. The blinds mesh spans the whole glass wall, so the wall's blinds go up
  while the office is open (the glass sheets either side stay solid). The back offices stand outside every zone
  volume (their zone is the back by attribute; a player inside counts as the nearest zone). The office's alarm rings
  the whole building's fixtures (Alarms.lua has no per-room fixtures), under its own source per office.
- **Round 19d notes.** The music and the new clips were picked from Roblox's library by title and checked public and
  approved through the toolbox API, but never heard: expect level and taste swaps (every id is one line in
  `MusicTracks` or `Theme.Sounds`, every level a `SfxGain` / `MusicVolume` number). There is no music volume toggle in
  the UI yet. D5's chains sit on the top step line (bank z 53.6, between the railings) read from the geometry; the
  railing walls stand `SideDepth` (39) studs down each opening and stop at 8 studs above the floor. The lockdown counts
  waves from the wave a door was called for, gasses zones by volume (a player outside every volume counts as gassed),
  pays nothing extra and never lowers a door's own reward; downed players take no gas damage (as before).

- **Round 19c notes.** Windows: the builder's pane mesh only collides along its centre strip and a separate see-through
  glass sheet sits in front of it; each pane now carries an invisible hit box and breaks with its own model (the bars)
  and every see-through part inside its box. The frame trim (`window wall seam`) stays. Zone gas is THE BANK only, never
  the vault or the tunnel, and waits for a second open zone (no gas before D1 opens), a non-boss wave and no vault
  window. Enemies ignore the gas. The alarm job's panel can stand at any job spot (it ignores pools); CUT THE CHAIN
  only draws at spots whose pool names `cut` (the electrical panel and the server room) or the arena pillars. Bag
  counts scale with the party (`BagPartyScale` 0.5 per extra member) for every source: the trickle and its cap, the
  vault, doors, the boss burst and debug Loot Rush. Enemy separation is steering only (no physics), so a doorway still
  lets a crowd through.

- **Round 19b notes.** The D2 chains stay at the stair tops (the guide now walks you up the stairs to them); drag
  them to the feet in Studio if wanted. Breakable glass is the builder's `bankwindow` panes only; ground-floor sills sit
  about 7 studs above the pavement outside, so a broken window is a way out and a firing line more than a way in.
  Catch-up moves enemies along their own planned route only, never into a spot a player can see.
- **Brief 7 assumptions and deviations to confirm.** The nodes were authored from the geometry offline (plans rendered
  from the place file), never seen in Studio: expect to drag some. The D2 chains sit at the stair tops on the mezzanine
  (between the newel posts, the one spot the geometry gave exactly) rather than the stair feet; move them in Studio.
  The 4-stud teller counter is a hop between the lobby and the back, so D3 has a third part, a grille over the counter
  (it opens with the shutters). The server door is the asset's second wheel door, animated (style `wheel`), not a
  generated panel; the server room's own wheel door onto the tunnel is dressing, swung open at load (`TriggerWave` -1).
  The brief's box zones follow where boxes stand: `SpawnNeverInCrewZone` tests the zone volume a box stands in, so the
  street boxes behind the fences feed the street while the crew holds it; `lobby_front` stands on the steps (street).
  The bank's windows are glass, so the `*_win` boxes stand in the bay alcoves inside (outside every zone volume) and
  `back_service` in the back corner of the side hall. The zone graph is a new Zone attribute `Links`
  (`neighbour@gate`); hatch-gated edges open with the hatch. `hatch_yard` stands beside the hatch inside the tunnel's
  hatch-top volume. Zone volumes put the stairs entirely in the lobby (a player on them counts as LOBBY). TITAN's wall
  blow hides nothing in the asset (the debris and the boss stepping in are the beat). TITAN's phase-3 Henchmen come in
  round it on THE BANK. The run end lines up on the Lineup node; the van backs out the way it came. The pill's second
  line is its right-hand label (`TUNNEL OPEN`). Lune 0.8.9 cannot read Studio's zstd binary saves or newer XML
  property types, hence the Nodes-only `.rbxmx` export; `importbank.luau` needs an uncompressed place (this import was
  made from a decompressed copy). The rojo node file is `Bank.nodes.model.json` (a plain `.json` would sync as a
  ModuleScript). Config can hold a CFrame now (`BankOrigin`; the lune tools stub it). The builder place's Lighting and
  MaterialService variants are not imported. Map thumbnails are `[IMG: TBA]`; `EnemyClimbAnimationId` is `[TBA]` (empty
  plays none).

- **Brief 6 assumptions to confirm.** The design canvas reference boards were not available to the build, so the look
  follows the style bar list. Pass levels start at 1 with level 1's cells claimable at once. Boost timers use the real
  clock (the fake clock never expires them); VIP renewals, seasons, FEATURED and Job resets use the fake clock. A VIP
  renewal charges the fake balance again and lapses when it is short. Pass and crate items you already own convert to
  Gold and mastery like crate dupes; bundle items you own are skipped (their share is already off the price). A mask
  dupe's mastery goes to the equipped class. The FEATURED rotation re-orders the three bundles (there are only three).
  Revive Everybody's party size is the party, not the number down. The bounty's gold banked and boss kills count for
  the whole party; kills, headshots and revives for the player. Headshots count bullets that hit the head, not kills.
  VIP poses are equippable as SQUAD / MVP poses (the hub has no emote button). Token packs are their own kind
  (`tokens`); `revive_self` / `revive_all` are not products since revives spend banked tokens. The paid crates' ARMS
  pool includes a `PS90` because the Direct `P90` already exists. Real catalog animation ids are unverified stand-ins.

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
