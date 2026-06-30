# Ironvow — Godot 4.3 port

This is the engine port of Ironvow, started so the game can ship to **Steam,
the App Store and Google Play** (native exports the HTML5 build can't produce).

## Open / run
- Install **Godot 4.3** (standard, not .NET).
- Open this `godot/` folder as a project (`project.godot`), press **F5**.
- Headless smoke test (CI-friendly):
  `godot --headless --path godot -- --selftest`
  → prints a `[SELFTEST]` line (player HP, level, enemies, kills, anim ok).

## What's in the foundation slice
- **Player** (`scripts/Player.gd`) — movement, 8-direction facing, and the
  animation state machine (idle/walk/attack/hurt) ported from `js/game.js`,
  driving the **PixelLab sprite art** (`assets/anim/<class>/<state>/<dir>/`,
  W/NW/SW mirrored from E/NE/SE).
- **Auto-attack** — fires projectiles at the nearest foe on cooldown.
- **Enemies** (`scripts/Enemy.gd`) — swarm/chase + contact damage, HP scaling.
- **Gems** (`scripts/Gem.gd`) — XP/gold pickups that drift to the player.
- **Spawn director** (`scripts/Main.gd`) — ramping spawn interval.
- **Floor** — the PixelLab dungeon-stone tile, tiled across the world.
- **Input** — touch joystick + WASD/arrows.
- **HUD** — level, timer, HP bar.
- **GameData** (`scripts/GameData.gd`, autoload) — all six class stat blocks and
  the animation manifest, ported from `js/classes.js`.

## Not yet ported (next phases) — see ../PORTING.md
Weapons/abilities, level-up cards, bosses (Champion/Warden), the other enemy
archetypes, enemy/boss sprite art, audio, menus (title/class-select/shop/
achievements), meta-progression + save, and torch lighting. The HTML5 build in
the repo root remains the reference for all of these.

## Asset note
`assets/` here is a copy of the repo's `../assets/`. The Godot project is the
source of truth for art going forward; regenerate via PixelLab as before.
