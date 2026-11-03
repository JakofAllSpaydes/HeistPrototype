# GHS — Core Loop Prototype

Playable Roblox prototype of the Grand Heist Survival core loop: one room, one enemy type, hitscan guns,
infinite waves, cash, the weapon reel, ground loot, the big crate, the upgrade overlay, the crew call
(side job), three abilities and a heat star meter.

State as of **2 Nov 2026**: all brief acceptance items are in, plus five playtest rounds of feedback.
Everything on `main` builds clean and is what Studio sees through Rojo.

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
| 1 / 2 | Buy weapon roll / buy upgrade pick (also clickable tiles, left column). |
| Q / E / Z | Turret / barricade / stim. |
| F | Swap with a floor gun (ProximityPrompt). 0.5s cooldown between swaps. |
| E (hold 2s) | Hack the side-job beacon. |
| Esc / X / 2 | Close the upgrade overlay. |
| Ctrl | Toggle camera lock so you can click HUD tiles. Left Alt frees the mouse while held. |
| Backtick | Debug panel: add cash, skip/set wave, pause spawns, kill all, force rarity/tradeoff, drop crate, trigger call, god mode, reset run. |

Mobile: touch look, on-screen fire/ability buttons, no hotkeys.

## What is in the build

**Core loop.** Wave → intermission → wave, enemies spawn from 8 markers, cash per kill, heat stars (0–5, half-star
steps) go up on wave clear and side-job success, down on side-job fail and on being downed. Enemies never collide
with players or each other; stuck enemies detour, then teleport back to the spawn ring.

**Weapons.** 8 guns with five rarities. Buying a roll plays a reel in the top-center slot, then the gun drops in from
the sky at your feet with a beam and a floor tag. Floor guns live 30s (`GroundWeaponLifetime`), countdown above the
tag, beam fades over the last 10s. Tags show name and DPS, coloured against your held DPS. Swapping leaves your old gun
where the new one was with a fresh timer. Rarity odds are bracketed by wave and tuned high for testing; pity floor
after 3 non-upgrades.

**Big crate.** One drops at the intro (after the first player loads, so you see it land) and one after every
completed side job. `BigCrateWaveInterval = 0` means none per wave. Each crate deals two different weapon types,
both free to take, and the crate closes when both guns are gone or after 30s. Crate body does not collide.

**Upgrades.** 13 gun-focused stats (Damage, FireRate, MagSize, ReloadSpeed, CritChance, HeadshotMult, MoveSpeed,
Accuracy, Pierce, Ricochet, Splash, Multishot, Lifesteal), pick 1 of 3 cards. Each card spins an icon reel at the
top, lands on the stat, then the text reveals. Higher rarity = bigger punch/shake/flash/rays. Tradeoff cards carry
a malus line. A tracker grid inside the overlay shows what you own.

**Abilities.** Turret (auto-fires at nearest enemy, 150 HP, 30s), barricade (300 HP wall, 45s), stim (6s move and
fire-rate buff with FOV push). Structures are enemy targets, have HP bars and can be destroyed. Cooldown sweeps on
the ability tiles. Airstrike was removed.

**Crew call / side job.** "VAULT PING" from MARLOW on wave 1 and every 3 waves. The dialogue card slides in from the
right into the top-right stack, collapses in place to a timer pill, and the result card expands from that pill.
Hack the beacon (hold E) within 75s for $600, heat up and a crate drop. Fail: heat down.

**HUD.** Built in code from `src/client/UI/Theme.lua`, scaled manually from a 760px basis. Wave bar with heat stars
(top-center), transient center toasts for wave/heat/crate/system events, top-right stack for the side job,
buy column on the left, ability column on the right, bottom-center health + held slot (DPS), ammo with reload ring on the
crosshair, hit markers, damage numbers, kill pops, cash floats, hurt vignette, spawn puffs, pickup rings.

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
CrewCall, Abilities, Debug, Log; `GameLoop.server.lua` is the entry. All cash, HP, spawns, rolls and loot are
server-authoritative; every remote is created in `src/shared/Remotes.lua`.

Client: ClientState (sync + juice bus), HUD components under `src/client/HUD`, UpgradeOverlay, WeaponReel,
GroundLoot, CrewCallUI, DebugPanel, Juice (rarity tiers), Camera, Gun, Main.

## Changelog (playtest rounds)

- **Round 1** — unstick enemies, no player collision, bigger UI, hold to fire, Ctrl camera lock, more starting cash.
- **Round 2** — top-center reel with gun drop-in, hackable side jobs with crate reward, 30s floor timers, bigger upgrade magnitudes, gun-only stats.
- **Round 3** — side-job pill top-right, arms drop as a transient toast, slot roll on upgrade cards, rarity-scaled juice.
- **Round 4** — six new upgrades (Accuracy, Pierce, Ricochet, Splash, Multishot, Lifesteal), live heat stars, crew-call card slide/collapse, crates close with their guns.
- **Round 5** — abilities (turret, barricade, stim), whole-card spin, 2s reel, reload ring, DPS display.
- **Round 6 (2 Nov)** — crate no longer collides, higher rarity odds, distinct crate weapons, icon reel on cards with text on land, DPS only, quieter death/destruction sounds, juice pass (affordable pop, low ammo and HP pulses, spawn puffs, pickup rings, wave-start flash), 0.5s swap cooldown.

## Open design notes (not built)

- **Dropped weapon handling.** Floor drops are hard to pick up mid-wave and can land behind a moving player.
  Discussed a stash slot (previous gun kept in a second HUD slot with the 30s decay, instant swap key, rolled guns
  fly to hand, deliberate drop for teammates). Parked for now.
- Barricades may die fast to large crowds; stuck detection is coarse; the top-right stack is 320px wide and may
  cramp long dialogue lines.
