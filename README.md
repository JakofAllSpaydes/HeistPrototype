# GHS — Core Loop Prototype

Playable Roblox prototype of the Grand Heist Survival core loop: one room, one enemy, one hitscan gun,
infinite waves, cash, the weapon reel, ground loot, the big crate, the upgrade overlay and the crew call.

## Run it

1. `aftman install` (once) so `rojo` resolves.
2. `rojo serve` in this folder.
3. In Studio: Rojo plugin → Connect. Press Play.

Everything the designer tunes lives in `src/shared/Config.lua`. Change a number, Rojo syncs it, play again.
Debug panel: press backtick in game. Ctrl toggles the camera lock so you can click HUD tiles; Left Alt frees the mouse while held.

## Layout

See `default.project.json`. `src/shared` → ReplicatedStorage.Shared, `src/server` → ServerScriptService.Server,
`src/client` → StarterPlayerScripts.Client, `src/assets` → ReplicatedStorage.Assets.
