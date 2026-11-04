# GHS — Core Loop Prototype

Playable Roblox prototype of the Grand Heist Survival core loop: one room, one enemy type, hitscan guns,
infinite waves, cash, the weapon reel, ground loot, the big crate, the upgrade overlay, the crew call
(side job), three abilities and a heat star meter. Brief 2 adds the staging yard, six objective minigames
as test props, the downed / revive loop, a run start sequence and a run end sequence with an MVP moment
and a summary. Brief 3 turns the yard into the hub: a DataStore profile with Gold, a queue zone with Create Match
and a party-scoped run, a real Gold payout, the customization scene (Weapons / Classes / Avatar) and a downed sidearm.

State as of **4 Nov 2026**: all brief 1 acceptance items are in, plus eight playtest rounds of feedback, the brief 2
slices (Round 9) and six feedback rounds on them (9b–10d below), the brief 3 build (Round 11) with its feedback rounds,
and phase 2 (Round 12: all twelve class abilities live, with the 12b / 12c feedback passes: Adrenaline, Dead Eye pierce,
rarity-colored collections, scroll memory). Everything on `main` builds clean and is what Studio sees through Rojo. The
"Brief 3 verify list" and the "Round 12 verify list" are the walk-throughs for a fresh Studio session.

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
| 1 / 2 | Buy weapon roll / buy upgrade pick (also clickable tiles, left column). |
| Q / E / Z | The equipped class's three abilities, all twelve live (INITIATE barricade / turret / adrenaline, DOC stim shot / med bag / healing turret, SHARPSHOOTER claymore / dead eye / flashbang, TORCH molotov / flame turret / oil drum). Cooldowns in `AbilityCooldown`. |
| F | Swap with a floor gun (ProximityPrompt). 0.5s cooldown between swaps. In the hub: `OPEN` on a station (WEAPONS / CLASSES / AVATAR) or a minigame prop, `TIER n` on the pad. |
| Walk onto the queue pad | Create Match card (party size, map, difficulty, info, CREATE, X). Walking in joins an open party; walking out leaves it. |
| PLAY (hub HUD) | Walks you to the nearest queue zone. Dock tiles WEAPONS · CLASSES · AVATAR open the customization scene; LEAVE (red X) or Esc closes it. |
| F (hold `ReviveHoldSec`) | Revive a downed teammate within `ReviveRadius`. Outranks floor guns: their prompts hide while a downed teammate is in reach. Mobile: a REVIVE hold button appears bottom-center. |
| Esc / X | Cancel an open minigame (counts as `cancel` in the log). |
| ◀ ▶ / A D | Spectating (bled out): cycle living teammates. REVIVE EVERYBODY button bottom-center. |
| F (hold 2s) | Hack the side-job beacon (hack jobs). Capture jobs: stand in the circle for `SideJobCaptureSec`; progress pauses when nobody is inside. Minigame jobs: F opens the game at the beacon. Kind is rolled per job from `SideJobKindWeights` (eight kinds, equal odds by default). |
| Esc / X / 2 | Close the upgrade overlay. |
| V | Vote to skip the intermission (or click the VOTES pill). `SkipVoteFraction` / `SkipMinIntermissionSec` in Config. |
| AUTO SKIP pill | Waves roll into each other: once the wave has fully spawned and `AutoSkipWaveSec` (10s) has passed, the next wave starts on top of whatever is left, with no intermission. |
| Ctrl | In a run: toggle the cursor lock so you can click HUD tiles. While unlocked the camera holds still, the character turns to face the cursor and shots go where the cursor is, so you can aim all the way around. Left Alt frees the cursor while held. In the hub the cursor is always free (RMB drags the camera) and every combat hotkey (fire, 1 / 2, Q / E / Z, V, Ctrl) is off; the server also refuses rolls, upgrades and abilities outside a run. |
| Backtick | Debug panel: add cash, skip/set wave, pause spawns, kill all, force rarity/tradeoff, drop crate, trigger call, god mode, reset run, force queue start, skip to run end, down me / down all / revive all, open any minigame, set tier, minigame stats, +1,000 Gold, unlock all, reset profile. Mobile: the `DBG` chip top-left. |

Mobile: touch look, pinch to zoom, on-screen fire / ADS toggle / reload / ability buttons, tap the VOTES and AUTO SKIP pills, no hotkeys.
Hub HUD on mobile landscape: dock tiles 76×68, PLAY 44px, SHOP and INVITE as icon tiles, queue card at 80%; the
customization panel takes the right 62% with 64px tiles and a 60px dock.
Every minigame is tap or drag only (no double-tap, long-press or keyboard); the revive hold and spectate arrows are buttons.

## What is in the build

**Core loop.** Wave → intermission → wave, enemies spawn from 8 markers, cash per kill, heat stars (0–5, half-star
steps) go up on wave clear and side-job success, down on side-job fail and on being downed. Enemies never collide
with players or each other; stuck enemies detour, then teleport back to the spawn ring. Center banners mark WAVE N,
WAVE N CLEAR and the 3-2-1 countdown; "N LEFT" sits under the heat stars. The intermission can be skipped by vote
(V / VOTES pill, `SkipVoteFraction`), and AUTO SKIP rolls waves into each other `AutoSkipWaveSec` after each one has
fully spawned. Kill chains show a combo counter from x2 with words at tier counts (`ComboTiers`).

**Weapons.** 15 guns across six archetypes (pistol, SMG, rifle, shotgun, sniper, LMG) with five rarities. The SCAR-H is a
3-round burst (`burst` / `burstDelay`; RATE and DPS show the delivered rate) and snipers carry built-in pierce by rarity
(`pierceByRarity`), neither spelled out in the name. Buying a roll plays a reel in the top-center slot, then the gun drops in from
the sky at your feet with a beam and a floor tag. Floor guns live 30s (`GroundWeaponLifetime`), countdown above the
tag, beam fades over the last 10s. Tags show name, DMG per shot ("33x8" for pellets) and RATE, each with a ▲ / ▼
against your held gun. Swapping leaves your old gun where the new one was with a fresh timer. Rarity odds are
bracketed by wave and tuned high for testing; pity floor after 3 non-upgrades. Damage falls off with distance per
archetype (`FalloffByArchetype`; snipers never). Common paper DPS sits at 128–180 across archetypes and rarity
multiplies damage by 1 / 1.3 / 1.7 / 2.3 / 3.0, so a legendary of anything beats an epic of anything. Tube-fed guns
(`shellReload`, the SPAS-12) load one shell at a time and firing stops the reload where it is.

**Big crate.** One drops at the intro (after the first player loads, so you see it land) and one after every
completed side job. `BigCrateWaveInterval = 0` means none per wave. Each crate deals two different weapon types,
both free to take, and the crate closes when both guns are gone or after 30s. Crate body does not collide.

**Upgrades.** 13 gun-focused stats (Damage, FireRate, MagSize, ReloadSpeed, CritChance, HeadshotMult, MoveSpeed,
Accuracy, Pierce, Ricochet, Splash, Multishot, Lifesteal), pick 1 of 3 cards. Each card spins an icon reel at the
top, lands on the stat, then the text reveals. Higher rarity = bigger punch/shake/flash/rays. Tradeoff cards carry
a malus line. A tracker grid inside the overlay shows what you own.

**Abilities.** All four class kits are live (`Abilities.lua`, numbers in Config's Abilities group, growth per
ability level through `AbilityGrowth`). Placeables stand `StructurePlaceDistance` ahead; attackable ones (turret,
barricade, healing turret, flame turret, oil drum) have HP bars and enemies walk to and hit them; a med bag and a
claymore are not targeted. Ground fields (med bag, molotov, the fire a broken drum leaves) act every `FieldTickSec`
on whoever stands in the circle. Thrown abilities (flashbang, molotov) arc `ThrowDistance` over `ThrowFlightSec`.
Self buffs (stim, stim shot, dead eye) share one slot per player; the tile that fired shows the seconds left.
- INITIATE: turret (auto-fires at the nearest enemy, 150 HP, 30s), barricade (300 HP wall, 45s), adrenaline (6s
  move, fire-rate and reload-speed buff with FOV push; no heal. Ability id `stim`, `Adrenaline*` in Config).
- DOC: stim shot (6s fire-rate and reload buff, +40 HP, no move speed), med bag (green circle, heals every standing
  teammate inside `MedBagHealPerSec`, 15s; one quiet `+N` float a second), healing turret (150 HP, beams the hurt
  teammate with the lowest HP share in `HealTurretRange` for `HealTurretBeamHeal` a second, 30s).
- SHARPSHOOTER: claymore (planted, arms after `ClaymoreArmSec`, an enemy inside `ClaymoreTriggerRadius` sets it
  off for `ClaymoreDamage` to everything in `ClaymoreBlastRadius`, 60s), dead eye (8s: weapon damage +25%, move
  +20%, every bullet passes through `DeadEyePierce` more enemies; a fractional pierce like 2.2 is one more enemy
  at 20% damage), flashbang (thrown; every enemy in `FlashRadius` stops and stops swinging for `StunDuration`, head goes white).
- TORCH: molotov (thrown; a fire circle for `MolotovLifetime` that burns `MolotovBurnPerSec` and slows
  `MolotovMoveSlowPct`), flame turret (150 HP, a `FlameTurretRange` stream at `FlameTurretDps`, 30s), oil drum
  (200 HP drum that blocks like a barricade; when enemies break it, not when it expires, it burns for `OilDrumBurnSec`).
Kills by turrets, fields and claymores pay the owner's kill cash. Abilities are free in a run (the Classes tab `$`
is a label). Cooldown sweeps on the ability tiles. Airstrike was removed.

**Crew call / side job.** A call from MARLOW on wave 1 and every `SideJobEveryWaves` (2) waves, kind rolled from
`SideJobKindWeights` (eight kinds, equal odds): "VAULT PING" (hack the terminal, hold E), "HOLD THE FLOOR" (stand in
the circle for `SideJobCaptureSec`; progress pauses when nobody is inside, a green disc fills on the floor), or one of
the six minigames (the beacon carries an OPEN prompt; a validated done finishes the job, fails can retry until the
timer). The dialogue card slides in from the right into the top-right stack with typewriter text, collapses in place to
a timer pill (with a progress bar for capture), and the result card expands from that pill. A world marker over the
beacon shows name, hint, timer and distance; past `MarkerCompactDistance` it shrinks to a badge. Cards hold
`CallHoldSec` (4.5s) before collapsing. If the job is still open at `SideJobReminderPct` (50%) of the window, MARLOW's
card comes back with a reminder line (`Lines.reminder`) and collapses again. Done within 75s: $600,
`SideJobGold` gold per player, heat up and a crate drop. Fail: heat down. A run ending with a job open clears it on
every client.

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
`topWave["TheBank:Normal"]`, `stats { kills, matchesPlayed, goldEarned }`, `pendingPayout`, `version`. A fresh profile
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
- **Classes tab.** `Classes.lua` lists INITIATE (Barricade Q, Turret E, Adrenaline Z: the prototype abilities), DOC (Stim
  Shot, Med Bag, Healing Turret), SHARPSHOOTER (Claymore, Dead Eye, Flashbang) and TORCH (Molotov, Flame Turret, Oil
  Drum) with the GDD copy, in-match `$` price and upgradeable variables. The category pills are the classes (colored
  circle with the initial, name, lock when unowned, ✔ when equipped); below them the selected class's three ability
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
and seconds over you for teammates. A standing teammate within `ReviveRadius` holds F for `ReviveHoldSec` (ring on their crosshair and on your
bleed bar, releasing resets) → you stand at `ReviveHPPct` with `ReviveInvulnSec` of invulnerability and a
`REVIVED BY` toast for both. Bleed-out removes the character and opens spectate (camera orbits living teammates, name
and HP top-center, REVIVE EVERYBODY free with a counter: everyone downed or bled out stands up where they fell,
`<NAME> REVIVED THE CREW` center toast). **Run over** when nobody is standing and nobody is still bleeding, so a solo
player bleeds (and can self-revive) before game over: enemies freeze and fade, the lens pulls in and the world
desaturates under a `RUN OVER · WAVE N` stamp for `RunOverSlowSec + RunOverHoldSec` (5s). Inside that window REVIVE
EVERYBODY still saves the run: the crew stands up, enemies clear and the same wave restarts (SECOND CHANCE); after it
the press is ignored and the run end plays. Characters are loaded by hand (`Players.CharacterAutoLoads = false`).

**Downed sidearm (brief 3).** A downed player keeps shooting: the held gun is stowed server-side (id, rarity, level;
the client remembers its mag per gun uid) and a Common `DownedPistolId` (M1911) at its own Armory level with a full
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
panel slides up over a dim: GOLD EARNED count-up (the GDD payout plus your side job gold, paid into the profile, with
`★ NEW PERSONAL BEST` when the wave beat your top wave), WAVE N, one row per player (name, kills, jobs, cash
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

## Layout

See `default.project.json`. `src/shared` → ReplicatedStorage.Shared, `src/server` → ServerScriptService.Server,
`src/client` → StarterPlayerScripts.Client, `src/assets` → ReplicatedStorage.Assets, `src/map` → Workspace.Room.

Server modules: World (run state, the party, `fireRun`, payout accumulators), Room, Stats, Profiles (DataStore),
PlayerState (per-player run state + profile-derived held / mask / wrap / class), Enemy, Spawner, Combat, Economy,
UpgradeShop, WeaponRoll, BigCrate, CrewCall, Abilities, SkipVote, Hub (yard dressing, stations, tier pad, resets, TOP
WAVE tag), Queue (zones, Create Match, party, countdown, PLAY AGAIN re-form), Meta (unlock / upgrade / equip actions),
Minigames (sessions, log, stats), Downed (down / revive / bleed-out / game over / sidearm), RunStart, RunEnd (payout,
summary), Squad (dummy crew for the sequences), Debug, Log; `GameLoop.server.lua` is the entry. All cash, Gold, HP,
spawns, rolls, loot, minigame results and revives are server-authoritative; every remote is created in
`src/shared/Remotes.lua`. Shared data: Config, Prices, Weapons (with `saleType` and the level math), Classes,
AbilityGrowth, Masks, Wraps, Rarity, Upgrades, Types, Remotes, Signal, CrewCall/Lines.

Client: ClientState (sync + juice bus + downed / camera mode flags + `inHub`), HUD components under `src/client/HUD`
(with `HUD.setMode` for hub / meta / downed / spectate / cinematic and `HubHUD` for the hub layout), QueueUI (Create
Match card, compact party card), MetaScene with `src/client/Meta/` (MetaUI, WeaponsTab, ClassesTab, AvatarTab),
UpgradeOverlay, WeaponReel, GroundLoot, CrewCallUI, Markers (beacon billboards), Minigames (Frame + one module per
game), DownedUI (bleed bar hooks, revive hold, downed markers), Spectate, RunStartUI, RunEndUI (sequence cameras,
poses, MVP stamp, summary), DebugPanel, Juice (rarity tiers), Camera, Gun, Main.

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

## Open design notes (not built)

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
