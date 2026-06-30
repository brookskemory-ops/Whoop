# Ironvow — Godot 4.3 port

This is the engine port of Ironvow, started so the game can ship to **Steam,
the App Store and Google Play** (native exports the HTML5 build can't produce).

## Open / run
- Install **Godot 4.3** (standard, not .NET).
- Open this `godot/` folder as a project (`project.godot`), press **F5**.
- `--fast` shrinks the boss timeline (12s run, mini-bosses at 3/6/9s) for quick
  manual testing: run the project with that as a command-line argument, or via
  `godot --path godot -- --fast`.
- Headless smoke tests (CI-friendly), each prints one result line and exits.
  All three bypass the menus and start a Knight run directly:
  - `godot --headless --path godot -- --selftest` — core loop (weapons, every
    enemy archetype, every ability mechanic).
  - `godot --headless --path godot -- --bosstest` — fast boss timeline end to
    end (mini-bosses → final boss → victory state).
  - `godot --headless --path godot -- --deathtest` — lethal damage → death
    screen → GameSave persists (incl. a save-file round trip) → Continue →
    title → fresh run.
  - `godot --headless --path godot -- --audiotest` — bakes + sanity-checks the
    procedural SFX PCM and exercises every sfx()/the music drone.

## What's in the project so far
- **Player** (`scripts/Player.gd`) — movement, 8-direction facing, the
  animation state machine (idle/walk/attack/hurt/dash) driving the **PixelLab
  sprite art** (`assets/anim/<class>/<state>/<dir>/`, W/NW/SW mirrored from
  E/NE/SE), the class weapon, orbital groups, and active-ability ticking.
- **Weapons** (`scripts/Weapons.gd`) — all 12 weapons across the four patterns
  (melee/projectile/nova/orbital), ported from `js/weapons.js`.
- **Abilities** (`scripts/Abilities.gd`) — 36 ranked abilities across 8
  mechanics, ported from `js/abilities.js`, plus the level-up card UI.
- **Enemies** (`scripts/Enemy.gd` + `EnemyProjectile.gd`) — all archetypes
  (chaser/shooter/exploder/splitter/charger + miniboss/finalboss AI), ported
  from `js/enemies.js`.
- **Boss timeline & run flow** (`scripts/Main.gd`) — mini-bosses at
  180/360/540s, the final boss ("the Warden") at 600s, boss health bar +
  banners, and a `playing|dead|won` state with a death/victory end screen
  (stats + unlocks + Continue).
- **Gems** (`scripts/Gem.gd`) — XP/gold pickups (Fortune-scaled) that drift to
  the player.
- **Meta-progression & save** (`scripts/GameSave.gd`, autoload) — gold, best
  time, class/weapon unlocks, achievements, lifetime + per-class kills, and
  Armory upgrade levels, persisted to `user://ironvow_save.json`.
- **Menus** (`scripts/Main.gd`) — Title, Class Select (with per-class weapon
  choice), Armory (buy upgrades + unlocks), Achievements. A run starts via
  Class Select → Begin; the end screen's Continue returns to the title.
- **Revive** — a bought Armory upgrade grants second-chance saves on death.
- **Audio** (`scripts/GameAudio.gd`, autoload) — fully procedural SFX + ambient
  music (no audio files), baked into in-memory `AudioStreamWAV`s, ported from
  `js/audio.js`'s WebAudio oscillator/noise synthesis.
- **Spawn director** — ramping spawn interval, paused during the final boss.
- **Floor** — the PixelLab dungeon-stone tile, tiled across the world.
- **Input** — touch joystick + WASD/arrows + a movement-ability button/Space.
- **HUD** — level, timer, HP bar, boss bar, banners.
- **GameData** (`scripts/GameData.gd`, autoload) — class/weapon/enemy stats,
  achievements, upgrade tracks, and the animation manifest.

## Not yet ported (next phases) — see ../PORTING.md
Enemy/boss sprite art, a pause/settings screen, and torch lighting/screen
shake. The HTML5 build in the repo root remains the reference for all of these.

## Asset note
`assets/` here is a copy of the repo's `../assets/`. The Godot project is the
source of truth for art going forward; regenerate via PixelLab as before.
