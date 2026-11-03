# GHS — Core Loop Prototype

Playable Roblox prototype of the Grand Heist Survival core loop: one room, one enemy type, hitscan guns,
infinite waves, cash, the weapon reel, ground loot, the big crate, the upgrade overlay, the crew call
(side job), three abilities and a heat star meter. Brief 2 adds the staging yard, six objective minigames
as test props, the downed / revive loop, a run start sequence and a run end sequence with an MVP moment
and a summary.

State as of **3 Nov 2026**: all brief 1 acceptance items are in, plus eight playtest rounds of feedback, plus the
brief 2 slices (Round 9 below). Everything on `main` builds clean and is what Studio sees through Rojo. Brief 2 was
built without a Studio playtest in the loop; the first session in Studio is the verification pass (see
"Brief 2 verify list").

## Run it

1. `aftman install` (once) so `rojo`, `stylua` and `luau-lsp` resolve.
2. `rojo serve` in this folder.
3. In Studio: Rojo plugin → Connect. Delete the default `Baseplate` once in edit mode (the server also removes it). Press Play.

Everything the designer tunes lives in `src/shared/Config.lua`. Change a number, Rojo syncs it, play again.
The map is a Rojo-synced model (`src/map/Room.model.json`, regenerate with `lune run tools/genmap.luau`; `lune` is in
`aftman.toml`, and the generator loads Config through `luau.load` with Vector2 / Vector3 stubs).

You spawn in the **staging yard** south of the arena: no enemies, wave bar reads `STAGING`, cash is `StagingCash` so
the buy tiles can be tested. Six minigame props and a tier pad stand along the west wall; the lit floor marker at the
arena door says `START RUN`. Downed / revive lines need Studio's Local Server with 2 players; everything else works solo.

## Controls

| Input | Action |
| --- | --- |
| LMB (hold) | Fire. `HoldToFire` in Config. |
| RMB (hold) | Aim down sights: narrower FOV, camera pulls in, half spread, tighter crosshair, lower sensitivity. `Ads*` in Config. |
| R | Reload. Tube-fed guns (`shellReload` in Weapons, currently the SPAS-12) load one shell per `reloadTime`; firing or R again stops at the current count. |
| Scroll wheel | Zoom. Fully in is first person (character hidden locally); out to `CameraZoomMax`. |
| 1 / 2 | Buy weapon roll / buy upgrade pick (also clickable tiles, left column). |
| Q / E / Z | Turret / barricade / stim. |
| F | Swap with a floor gun (ProximityPrompt). 0.5s cooldown between swaps. In the yard: `START RUN` on the door marker, `OPEN` on a minigame prop, `TIER n` on the pad. |
| F (hold `ReviveHoldSec`) | Revive a downed teammate within `ReviveRadius`. Outranks floor guns: their prompts hide while a downed teammate is in reach. Mobile: a REVIVE hold button appears bottom-center. |
| Esc / X | Cancel an open minigame (counts as `cancel` in the log). |
| ◀ ▶ / A D | Spectating (bled out): cycle living teammates. REVIVE EVERYBODY button bottom-center. |
| E (hold 2s) | Hack the side-job beacon (hack jobs). Capture jobs: stand in the circle for `SideJobCaptureSec`; progress pauses when nobody is inside. Kind is rolled per job from `SideJobKindWeights` (50/50 by default). |
| Esc / X / 2 | Close the upgrade overlay. |
| V | Vote to skip the intermission (or click the VOTES pill). `SkipVoteFraction` / `SkipMinIntermissionSec` in Config. |
| AUTO SKIP pill | Waves roll into each other: once the wave has fully spawned and `AutoSkipWaveSec` (10s) has passed, the next wave starts on top of whatever is left, with no intermission. |
| Ctrl | Toggle the cursor lock so you can click HUD tiles. While unlocked the camera holds still, the character turns to face the cursor and shots go where the cursor is, so you can aim all the way around. Left Alt frees the cursor while held. |
| Backtick | Debug panel: add cash, skip/set wave, pause spawns, kill all, force rarity/tradeoff, drop crate, trigger call, god mode, reset run, start run, skip to run end, down me / down all / revive all, open any minigame, set tier, minigame stats. Mobile: the `DBG` chip top-left. |

Mobile: touch look, pinch to zoom, on-screen fire / ADS toggle / reload / ability buttons, tap the VOTES and AUTO SKIP pills, no hotkeys.
Every minigame is tap or drag only (no double-tap, long-press or keyboard); the revive hold and spectate arrows are buttons.

## What is in the build

**Core loop.** Wave → intermission → wave, enemies spawn from 8 markers, cash per kill, heat stars (0–5, half-star
steps) go up on wave clear and side-job success, down on side-job fail and on being downed. Enemies never collide
with players or each other; stuck enemies detour, then teleport back to the spawn ring. Center banners mark WAVE N,
WAVE N CLEAR and the 3-2-1 countdown; "N LEFT" sits under the heat stars. The intermission can be skipped by vote
(V / VOTES pill, `SkipVoteFraction`), and AUTO SKIP rolls waves into each other `AutoSkipWaveSec` after each one has
fully spawned. Kill chains show a combo counter from x2 with words at tier counts (`ComboTiers`).

**Weapons.** 8 guns with five rarities. Buying a roll plays a reel in the top-center slot, then the gun drops in from
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

**Abilities.** Turret (auto-fires at nearest enemy, 150 HP, 30s), barricade (300 HP wall, 45s), stim (6s move,
fire-rate and reload-speed buff with FOV push). Structures are enemy targets, have HP bars and can be destroyed. Cooldown sweeps on
the ability tiles. Airstrike was removed.

**Crew call / side job.** A call from MARLOW on wave 1 and every 3 waves, kind rolled 50/50 (`SideJobKindWeights`):
"VAULT PING" (hack the terminal, hold E) or "HOLD THE FLOOR" (stand in the circle for `SideJobCaptureSec`; progress
pauses when nobody is inside, a green disc fills on the floor). The dialogue card slides in from the right into the
top-right stack with typewriter text, collapses in place to a timer pill (with a progress bar for capture), and the
result card expands from that pill. A world marker over the beacon shows name, hint, timer and distance; past
`MarkerCompactDistance` it shrinks to a badge. Done within 75s: $600, heat up and a crate drop. Fail: heat down.

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

**Staging yard and the run loop (brief 2).** The map is the arena plus a 120×80 yard on its south wall (`YardWidth`,
`YardDepth`, `DoorWidth`, `PropSpacing`; regenerate the map after changing them). `GameLoop` runs
`Staging → START RUN → Intro (run start sequence) → Wave / Intermission … → RunOver → RunEnd → Summary → Staging`.
In the yard nothing spawns, no crew call, no crate; START RUN wipes yard purchases and starts a fresh run with
`StartingCash`, so the arena plays exactly as Round 8 from WAVE 1. The door stays open; walking back out mid-run is
harmless. After the summary everyone gets a fresh character at the yard spawn. Late joiners mid-run land at the arena spawn.

**Minigames (test props, not wired into jobs yet).** One client module per game under `src/client/Minigames/`, sharing
`Frame.lua` (centered panel `MinigamePanelPct` of the shorter screen edge wide, crew-call frame style, title, hint,
elapsed timer, X / Esc cancel, damage shake, downed = fail, haptics on hits and locks). The server (`Minigames.lua`)
owns the session: the prop's prompt opens it, the client sends done / fail / cancel with its miss count, anything
faster than `MinigameMinSec[name]` is logged as a fail, and every close prints
`minigame <name> tier <n> done in <sec>s, <fails> fails` (or `… fail|cancel <sec>s <misses> misses`). The debug panel's
`Stats` button prints per-game averages. Tier (1–3, `MinigameTier`) is session-wide from the pad or the debug panel:
Lockpick (tap: zone width), Hotwire (drag: wires), Keypad (tap: digits), Arm charges (tap: caps), Safe dial (drag:
numbers), Frequency jam (drag: locks and slider range). Nothing happens on success beyond the green DONE.

**Downed, revive, game over.** 0 HP → `Downed.down`: crawl speed and animation (`DownedAnimationId`), no jump, no
fire / abilities / buys / swaps, enemies drop you from targeting, the health bar becomes a red bleed bar from
`BleedOutSec` with SELF-REVIVE (free, counter) on its right, a red-cross marker with name and seconds over you for
teammates. A standing teammate within `ReviveRadius` holds F for `ReviveHoldSec` (ring on their crosshair and on your
bleed bar, releasing resets) → you stand at `ReviveHPPct` with `ReviveInvulnSec` of invulnerability and a
`REVIVED BY` toast for both. Bleed-out removes the character and opens spectate (camera orbits living teammates, name
and HP top-center, REVIVE EVERYBODY free with a counter: everyone downed or bled out stands up where they fell,
`<NAME> REVIVED THE CREW` center toast). **Run over** when nobody is standing and nobody is still bleeding, so a solo
player bleeds (and can self-revive) before game over, and REVIVE EVERYBODY has a window to matter: enemies freeze and
fade, the lens pulls in and the world desaturates for `RunOverSlowSec` under a `RUN OVER · WAVE N` stamp, then the
run end. Characters are loaded by hand (`Players.CharacterAutoLoads = false`).

**Run start (`IntroSec` 5.0, `RunStartBeats`).** The crew vanishes into the van, the van drives from the yard through
the door and brakes beside the arena spawn (dust ring, shake), the crew steps out in a line in join order facing the
arena, heads recolor to `MaskColors` by line position with a hands-to-face stand-in animation, each player plays a random
pose from `Poses` (kept for the run end, `PoseStagger` apart), the camera pans the line at chest height, pushes in, then
orbits 180° to behind the local player and hands over to the gameplay camera. Input locked, HUD down to the wave bar,
not skippable. The crate drops as control returns.

**Run end (`RunEndBeats`).** Arena cleared, everyone (spectators too) gets a fresh character in the line at the van,
anchored, mask on, cash bag in hand, `KILLS · $CASH` tag over the head. Poses replay, bills rain (`CashRainPerBanked`
× Total Banked, capped at `CashRainMax`, over `CashRainSec`), then a cut to a tight 3/4 orbit (`MvpOrbitSec`) on the
MVP (kills × `MvpKillWeight` + cash collected × `MvpCashWeight` + revives × `MvpReviveWeight`; ties to the earlier
joiner; solo still gets the beat) with a gold MVP stamp, name, the winning stat line, rays, shake and a bigger haptic.
The summary panel slides up over a dim: TOTAL BANKED count-up (`SummaryCountUpSec`), WAVE N, one row per player
(name, pose, kills, cash collected, revives, downs, self-revives, MVP tag), `GOLD +N` (`GoldPerBanked`, display only),
PLAY AGAIN and TO LOBBY with a `SummaryAutoLobbySec` countdown; both return the crew to the yard. Total Banked is the
cash earned during the run (kills, jobs), not the balance.

## Verifying a change

```
stylua src tools
luau-lsp analyze --no-strict-dm-types src   # only SyntaxError lines matter without Roblox defs
rojo build -o build.rbxl
```

Nothing is tested in Studio by the tooling; playtests are manual.

### Brief 2 verify list

The brief 2 code was written and built (`stylua`, `luau-lsp`, `rojo build`) but not yet run in Studio. First session,
in this order; anything that fails is a Config or one-file fix:

1. Spawn in the yard, wave bar `STAGING`, cash $5,000, buy tiles work. Floor labels read from where you stand (if a label
   is upside down, flip the `Yaw = 90` on the label parts in `tools/genmap.luau`).
2. Walk to each prop, `F` opens it, play it to DONE, check the output line and the miss count. Esc cancels. Tier pad
   changes the hint numbers. Device emulator: every game with touch only (Safe dial uses the GUI inset to find the dial
   center; if the dial feels off-center on a device, that is the `GuiService:GetGuiInset()` term in `Safe.lua`).
3. `START RUN`: 5.0s sequence, van drives in, crew steps out, masks, poses, orbit, WAVE 1 banner, control returns
   behind you. Then the arena plays as Round 8.
4. Debug `Down me`: crawl, low camera, bleed bar, SELF-REVIVE. Local Server 2 players: hold F on the downed player
   (ring on both screens), bleed out → spectate, REVIVE EVERYBODY.
5. Debug `Skip to run end` (or die out): RUN OVER stamp, line-up at the van, cash rain, MVP, summary, buttons, 30s auto.
6. Haptics only fire on devices where `HapticService:IsVibrationSupported` is true.

## Layout

See `default.project.json`. `src/shared` → ReplicatedStorage.Shared, `src/server` → ServerScriptService.Server,
`src/client` → StarterPlayerScripts.Client, `src/assets` → ReplicatedStorage.Assets, `src/map` → Workspace.Room.

Server modules: World, Room, Stats, PlayerState, Enemy, Spawner, Combat, Economy, UpgradeShop, WeaponRoll, BigCrate,
CrewCall, Abilities, SkipVote, Staging (yard, door, tier pad, resets), Minigames (sessions, log, stats), Downed
(down / revive / bleed-out / game over), RunStart, RunEnd, Debug, Log; `GameLoop.server.lua` is the entry. All cash, HP,
spawns, rolls, loot, minigame results and revives are server-authoritative; every remote is created in
`src/shared/Remotes.lua`.

Client: ClientState (sync + juice bus + downed / camera mode flags), HUD components under `src/client/HUD` (with
`HUD.setMode` for downed / spectate / cinematic), UpgradeOverlay, WeaponReel, GroundLoot, CrewCallUI, Markers (beacon
billboards), Minigames (Frame + one module per game), DownedUI (bleed bar hooks, revive hold, downed markers), Spectate,
RunStartUI, RunEndUI (sequence cameras, poses, MVP stamp, summary), DebugPanel, Juice (rarity tiers), Camera, Gun, Main.

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

## Open design notes (not built)

- **Brief 2 assumptions to confirm.** A downed player keeps the run alive (self-revive is free), so "all players down"
  is not game over until the last bleed runs out; flip that in `Downed.checkRunOver` if the stamp should land on the
  last knockdown. Robux Self-Revive / Revive Everybody, gold persistence, pose shop and the hub are out of scope; both
  summary buttons do the same thing. Minigames are not wired into side jobs. `RunOverTimeScale` only drives the client
  slow-mo read (lens + desaturation); enemies are frozen and nobody is standing at that point.

- **Dropped weapon handling.** Floor drops are hard to pick up mid-wave and can land behind a moving player.
  Discussed a stash slot (previous gun kept in a second HUD slot with the 30s decay, instant swap key, rolled guns
  fly to hand, deliberate drop for teammates). Parked for now.
- Barricades may die fast to large crowds; stuck detection is coarse; the top-right stack is 320px wide and may
  cramp long dialogue lines.
