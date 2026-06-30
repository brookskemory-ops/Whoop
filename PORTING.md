# Ironvow — HTML5 → Godot port plan

Goal: move Ironvow onto **Godot 4.3** so it can ship natively to **Steam,
App Store and Google Play**. The vanilla-JS build in the repo root stays the
playable reference while the engine port is built up phase by phase.

## Why Godot
- Native desktop + mobile + console exports and store packaging.
- Built-in TileMap autotiling (consumes the PixelLab Wang tilesets directly),
  physics/collision, AnimationPlayer, input maps, audio buses.
- The trade-off vs. the JS build is the instant zero-build web workflow; the JS
  build is kept for quick iteration/preview.

## Project location
`godot/` — open with Godot 4.3. See `godot/README.md` to run + smoke-test.
Renderer: GL Compatibility (best for mobile + web). Portrait 480×800,
nearest-neighbour texture filtering for crisp pixel art.

## Status

### Phase 0 — Foundation (DONE)
Runnable core slice, validated headlessly (`--selftest`):
- Player movement + 8-dir animation state machine driving the PixelLab sprites.
- Auto-attack projectiles, swarm enemies + contact damage, gems/XP, HP, regen,
  i-frames, camera follow, ramping spawn director, PixelLab dungeon floor,
  touch+keyboard input, HUD (level/timer/HP), all six class stat blocks.

### Phase 1 — Combat content
- Port `js/weapons.js` (12 weapons: projectile / orbital / nova / beam types).
- Port `js/abilities.js` + the level-up card UI and ability state machine.
- Port the full `js/enemies.js` archetypes (skeleton/goblin/ogre/shooter/
  exploder/splitter/charger) and their AI.

### Phase 2 — Bosses & run structure
- Mini-bosses at 180/360/540s, final boss "The Warden" at 600s, victory state.
- Boss health bar + banners.

### Phase 3 — Meta & UX
- Title / class-select / shop (Armory upgrades) / achievements / pause /
  settings screens (port `js/achievements.js` + the meta logic in `js/game.js`).
- Save system (Godot `user://` JSON, replacing `localStorage`).
- Audio (port `js/audio.js` to an AudioStreamPlayer bus / generated SFX).
- Torch lighting (Light2D / CanvasModulate) + low-HP vignette + screen shake.

### Phase 4 — Art & ship
- Enemy/boss sprite art (PixelLab) replacing the placeholder shapes.
- Convert the floor to a real Wang TileMap (terrain variety + walls) using the
  16-tile sheet already saved in `assets/map/dungeon_tileset.*`.
- Export presets + signing for Steam / App Store / Play; store metadata.

## Mapping cheatsheet (JS → Godot)
| JS | Godot |
|----|-------|
| `js/classes.js` | `scripts/GameData.gd` CLASSES (done) |
| `js/game.js` loop/update | `scripts/Main.gd` + node `_process` |
| `updatePlayerAnim` / `dirOf` | `scripts/Player.gd` + `GameData.dir_of` |
| `Art.floorPatternFor` | tiled `Sprite2D` in `Main._build_world` |
| `localStorage` meta | `user://save.json` (Phase 3) |
| DOM screens | `CanvasLayer` + `Control` scenes (Phase 3) |
| `GameAudio` (WebAudio) | `AudioStreamPlayer` bus (Phase 3) |
