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

### Phase 1 — Combat content (DONE)
- `js/enemies.js` → `Enemy.gd` + `EnemyProjectile.gd`: all archetypes
  (chaser/shooter/exploder/splitter/charger + miniboss/finalboss AI), enemy
  projectiles, split/explode deaths, slow/burn, elites, weighted spawns.
- `js/weapons.js` → `Weapons.gd`: all 12 weapons (melee/projectile/nova/orbital)
  wired to the class starter weapon; combat ctx helpers on `Main`.
- `js/abilities.js` → `Abilities.gd`: 36 ranked abilities across 8 mechanics
  (nova/slam/volley/radial/chain/orbit/dash/blink), the level-up card UI with
  pause + pick, attack auto-fire, keyed orbit sync, dash + blink movement, and a
  movement-ability button. Headless self-test exercises every weapon, every
  enemy archetype and every ability mechanic with no errors.

### Phase 2 — Bosses & run structure (DONE)
- Boss timeline in `Main.gd`: mini-bosses ("Champion") at 180/360/540s, the
  final boss ("The Warden") at 600s; normal spawns pause during the final boss
  fight, matching `js/game.js`. `--fast` (or the `--bosstest` self-test) shrinks
  this to 3/6/9s + 12s for quick iteration.
- Boss health bar + event banners (mini-boss/final-boss announcements) on the HUD.
- Win/lose flow: a `playing | dead | won` run state, pausing the tree and
  showing an end screen (time/kills/gold + Restart) on either death or
  defeating the Warden — ported from `die()`/`victory()`. Killing a mini-boss
  heals the player +25 HP and shows "Champion Slain!"; the final boss has no
  gem drop and ends the run immediately on death, matching the JS exactly.
- Validated headlessly: `--bosstest` runs the fast timeline end-to-end (all 3
  mini-bosses + the final boss spawn on schedule, killing the Warden flips the
  state to "won"); `--deathtest` verifies lethal damage pauses with the death
  screen and Restart returns to a fresh full-HP run. No script errors.

### Phase 3a — Meta-progression, save & menus (DONE)
- `GameSave.gd` (autoload): persistent gold/best-time/unlocks/achievements/
  total+per-class kills/upgrade levels, JSON round-tripped through Godot's
  `user://` directory — replaces `localStorage`/`loadMeta`/`saveMeta`. Verified
  to survive both an in-process reload and a real separate process launch.
- `js/achievements.js` → `GameData.ACHIEVEMENTS` + `check_achievements()`; run
  end (death or victory) checks and applies fresh unlocks, shown on the end
  screen, exactly mirroring `checkRunAchievements()`/`applyUnlock()`.
- Permanent Armory upgrades (`UPGRADE_TRACKS`: Vigor/Might/Haste/Fortune/
  Revive) ported to `GameData` + applied in `Player.setup()`, matching
  `createPlayer()`'s upgrade math; Fortune's gold/XP multipliers applied on
  gem pickup.
- Second-chance **Revive** (ported from `revivePlayer()`): consumes a charge,
  heals to 50%, knocks back + damages the surrounding swarm.
- Menus built in `Main.gd` (CanvasLayer + Controls, matching the level-up/end
  -screen pattern): **Title** (best time/gold, Start Run/Armory/Achievements),
  **Class select** (locked/unlocked classes + per-class weapon choice, ported
  from `buildClassSelect`), **Armory/Shop** (buy upgrades + gold-gated class/
  weapon unlocks, ported from `buildShop`), **Achievements** list. A run now
  starts from class-select (`Begin`) instead of auto-starting; the end screen's
  Continue returns to the title screen rather than instantly restarting,
  matching the JS screen flow.
- Validated headlessly: `--selftest`/`--bosstest` unchanged; `--deathtest`
  extended to verify GameSave persists through death → end screen → Continue →
  title → a fresh Begin, including a save-file round trip and cross-process
  gold accumulation. No script errors.

### Phase 3b — Audio (DONE)
- `GameAudio.gd` (autoload): fully procedural, no audio files — ported from
  `js/audio.js`'s WebAudio oscillator/noise synthesis. One-shot SFX (hit/crit/
  enemyDie/pickup/levelup/hurt/cast/uiClick/purchase/heartbeat) are baked into
  small in-memory 16-bit `AudioStreamWAV` buffers on demand (oscillator
  waveform + exponential envelope ported from `tone()`; faded + one-pole-
  high-passed white noise ported from `noise()`) and played from a pooled
  `AudioStreamPlayer`s. Music is a 12s looping drone bed (3 detuned sine/
  triangle tones with slow LFO gain wobble, ported from `drone()`) plus sparse
  scheduled triangle motif notes on a `Timer` (ported from `schedule()`).
- Wired at every JS call site: weapon/ability/movement-ability fire → `cast`;
  `Enemy.take_damage()` → `hit`/`crit` (burn ticks correctly bypass this,
  matching the JS's direct-hp-subtract burn path); enemy death → `enemyDie`;
  player damage → `hurt`; gem pickup → `pickup`; level-up trigger → `levelup`
  (boss spawn + revive also use `levelup`, matching `spawnBoss()`/
  `revivePlayer()`); low-HP pulse → `heartbeat`; menu nav/picks → `uiClick`;
  successful Armory purchases → `purchase`; music starts on `_begin_run`,
  stops (+ a `levelup` sting on victory) in `_end_run`.
- Validated headlessly: `--audiotest` bakes a tone+noise burst directly and
  confirms the PCM is non-silent and within range, exercises every named
  `sfx()` call through the real public API, and confirms the music drone
  actually plays. `--selftest`/`--bosstest`/`--deathtest` still pass clean
  with audio now firing throughout (no script errors, no audio-driver issues
  running `--headless`).

### Phase 3c — Lighting, juice & pause (DONE)
- **Torch lighting**: a `CanvasModulate` darkens the world; a `PointLight2D`
  ("torch") follows the player, using a runtime-generated radial
  `GradientTexture2D` (no image asset needed) — ported from the
  `torchFlicker`/`litR` radial-gradient overlay in `render()`. Both
  `CanvasModulate` and the light only affect the base canvas, leaving
  HUD/menu `CanvasLayer`s unaffected, matching the JS's canvas-vs-DOM split.
- **Screen shake**: `add_shake()` (capped at 16, decaying at `dt*36`) applied
  as random `Camera2D.offset` jitter, wired at every JS `addShake()` site —
  enemy kills (boss vs. normal), player hurt, boss spawn, revive, exploder
  death explosion, and miniboss/finalboss attack ticks (ported from
  `js/enemies.js`'s `ctx.addShake`).
- **Level-up/pickup flash** and **low-HP pulsing vignette** (transparent-
  center-to-red `GradientTexture2D`, alpha-modulated by the JS's pulse
  formula), both on the HUD `CanvasLayer` so they sit above the world but
  below the DOM-equivalent HUD text.
- **Pause + Settings**: an in-run Pause button + Escape-to-open (closing is
  via the always-processing Resume button, since Godot's default pause
  cascade stops `_input` once `get_tree().paused` — matching the JS's own
  render-freeze-while-paused behavior) — Resume / Settings / **Quit to
  Title** (ported from `quit-btn`: abandons the run with *no* gold/kills/
  achievements persisted, unlike a completed death/victory). Settings
  (volume slider + mute) is shared between the title screen and pause menu,
  persisted to `GameSave` (`volume`/`muted` now round-trip through the save
  file, matching `loadMeta`/`saveMeta`).
- Validated headlessly: `--pausetest` exercises pause → settings → volume/
  mute change + disk round-trip → back → resume → a second pause → quit
  (confirming the run's gold is *not* persisted on quit). All five self-tests
  (`selftest`/`bosstest`/`deathtest`/`audiotest`/`pausetest`) pass with no
  script errors.

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
| `localStorage` meta | `scripts/GameSave.gd` autoload + `user://` JSON (done) |
| DOM screens | `CanvasLayer` + `Control`s built in `Main.gd` (done) |
| `js/audio.js` (WebAudio) | `scripts/GameAudio.gd` autoload + baked `AudioStreamWAV` (done) |
