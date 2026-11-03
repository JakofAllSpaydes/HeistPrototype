# GHS — Core Loop Prototype

Playable Roblox prototype of the Grand Heist Survival core loop: one room, one enemy type, hitscan guns,
infinite waves, cash, the weapon reel, ground loot, the big crate, the upgrade overlay, the crew call
(side job), three abilities and a heat star meter.

State as of **3 Nov 2026**: all brief acceptance items are in, plus eight playtest rounds of feedback (zoom and ADS,
a feedback / juice pass, skip votes and auto skip, a capture-point side job, damage falloff, a weapon DPS pass and
shell-by-shell reloads). Everything on `main` builds clean and is what Studio sees through Rojo.

## Run it

1. `aftman install` (once) so `rojo`, `stylua` and `luau-lsp` resolve.
2. `rojo serve` in this folder.
3. In Studio: Rojo plugin → Connect. Delete the default `Baseplate` once in edit mode (the server also removes it). Press Play.

Everything the designer tunes lives in `src/shared/Config.lua`. Change a number, Rojo syncs it, play again.
The map is a Rojo-synced model (`src/map/Room.model.json`, regenerate with `lune run tools/genmap.luau`).

## Controls

| Input | Action |
| --- | --- |
| LMB (hold) | Fire. `HoldToFire` in Config. |
| RMB (hold) | Aim down sights: narrower FOV, camera pulls in, half spread, tighter crosshair, lower sensitivity. `Ads*` in Config. |
| R | Reload. Tube-fed guns (`shellReload` in Weapons, currently the SPAS-12) load one shell per `reloadTime`; firing or R again stops at the current count. |
| Scroll wheel | Zoom. Fully in is first person (character hidden locally); out to `CameraZoomMax`. |
| 1 / 2 | Buy weapon roll / buy upgrade pick (also clickable tiles, left column). |
| Q / E / Z | Turret / barricade / stim. |
| F | Swap with a floor gun (ProximityPrompt). 0.5s cooldown between swaps. |
| E (hold 2s) | Hack the side-job beacon (hack jobs). Capture jobs: stand in the circle for `SideJobCaptureSec`; progress pauses when nobody is inside. Kind is rolled per job from `SideJobKindWeights` (50/50 by default). |
| Esc / X / 2 | Close the upgrade overlay. |
| V | Vote to skip the intermission (or click the VOTES pill). `SkipVoteFraction` / `SkipMinIntermissionSec` in Config. |
| AUTO SKIP pill | Waves roll into each other: once the wave has fully spawned and `AutoSkipWaveSec` (10s) has passed, the next wave starts on top of whatever is left, with no intermission. |
| Ctrl | Toggle the cursor lock so you can click HUD tiles. While unlocked the camera holds still, the character turns to face the cursor and shots go where the cursor is, so you can aim all the way around. Left Alt frees the cursor while held. |
| Backtick | Debug panel: add cash, skip/set wave, pause spawns, kill all, force rarity/tradeoff, drop crate, trigger call, god mode, reset run. |

Mobile: touch look, pinch to zoom, on-screen fire / ADS toggle / reload / ability buttons, tap the VOTES and AUTO SKIP pills, no hotkeys.

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

## Verifying a change

```
stylua src tools
luau-lsp analyze --no-strict-dm-types src   # only SyntaxError lines matter without Roblox defs
rojo build -o build.rbxl
```

Nothing is tested in Studio by the tooling; playtests are manual.

## Layout

See `default.project.json`. `src/shared` → ReplicatedStorage.Shared, `src/server` → ServerScriptService.Server,
`src/client` → StarterPlayerScripts.Client, `src/assets` → ReplicatedStorage.Assets, `src/map` → Workspace.Room.

Server modules: World, Room, Stats, PlayerState, Enemy, Spawner, Combat, Economy, UpgradeShop, WeaponRoll, BigCrate,
CrewCall, Abilities, SkipVote, Debug, Log; `GameLoop.server.lua` is the entry. All cash, HP, spawns, rolls and loot are
server-authoritative; every remote is created in `src/shared/Remotes.lua`.

Client: ClientState (sync + juice bus), HUD components under `src/client/HUD`, UpgradeOverlay, WeaponReel,
GroundLoot, CrewCallUI, Markers (crate and beacon billboards), DebugPanel, Juice (rarity tiers), Camera, Gun, Main.

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

## Open design notes (not built)

- **Dropped weapon handling.** Floor drops are hard to pick up mid-wave and can land behind a moving player.
  Discussed a stash slot (previous gun kept in a second HUD slot with the 30s decay, instant swap key, rolled guns
  fly to hand, deliberate drop for teammates). Parked for now.
- Barricades may die fast to large crowds; stuck detection is coarse; the top-right stack is 320px wide and may
  cramp long dialogue lines.
