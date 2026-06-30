# Ironvow — Dev Notes / Session Handoff

Medieval **survivor-like roguelite**, HTML5 Canvas + vanilla JS (no build step).
Branch: `claude/mobile-game-brainstorm-ft3hhf`. Live test link (auto-updates on push):
`https://raw.githack.com/brookskemory-ops/whoop/claude/mobile-game-brainstorm-ft3hhf/index.html`

## Run / test
- Serve: `python3 -m http.server 8137` → `http://localhost:8137`.
- Headless tests: Playwright at `/opt/pw-browsers/chromium`; import it in `.mjs` via
  `import pkg from '/opt/node22/lib/node_modules/playwright/index.js'; const {chromium}=pkg;`.
- Localhost-only dev aids in `js/game.js`: `?fast` (10-min run → 12s; mini-bosses 3/6/9s) and
  `window.__ironSteps=N` (fast-forward substeps); `window.__player` exposed under `?fast`.

## Files
`index.html`, `styles.css`, `js/{rng,classes,weapons,abilities,achievements,enemies,art,audio,game}.js`.
- **classes/weapons/abilities/achievements/enemies** = data-driven game content.
- **art.js** = procedural fallback sprites + floor + the external sprite/animation loaders.
- **game.js** = loop, input (joystick + ability buttons), combat, meta-progression, render.

## Sprite & animation pipeline (important)
Characters can use external pixel-art (PixelLab) over the coded fallbacks:
- **Single override:** `assets/sprites/<key>.png` listed in `assets/sprites/manifest.json`.
- **8-direction rotations:** `assets/sprites/<class>/<dir>.png` (dirs: south, south-east, east,
  north-east, north, north-west, west, south-west); classes listed in `assets/sprites/rotations.json`.
- **Animations:** `assets/anim/<class>/<state>/<dir>/frame_NN.png`; counts in
  `assets/anim/manifest.json` (`{ knight:{ dirs:[...], states:{ idle,walk,attack,special,dash,hurt,death } } }`).
- `art.js`: `loadCharacterArt()` bakes all frames with ONE shared union alpha-bbox per class
  (stable size/feet), `Art.dirSprite(cls,dir)` + `Art.anim(cls,state,dir)` resolve exact dir or
  **mirror** (W/NW/SW ↔ E/NE/SE), `Art.animMeta` gives fps/loop/frame-count.
- `game.js`: 8-way facing via `dirOf(aim)`, player anim state machine
  (`dash > special/attack > hurt > walk > idle`), render = anim → dirSprite → static fallback.

### Status of art
- All 5 uploaded classes (knight/archer/mage/rogue/cleric) have 8-dir **static rotations**.
- All 5 classes now have full **8-direction frame animations** for every state
  (idle/walk/attack/special/dash/hurt/death). Base dirs south/north/east/north-east/
  south-east are baked; west/north-west/south-west mirror them at runtime.
- Barbarian + all enemies/bosses still use coded sprites.

## PixelLab MCP (when available)
Server `pixellab` (`https://api.pixellab.ai/mcp`, HTTP, Bearer token). Tools:
- `create_character` (`description`, `body_type`, `n_directions: 8`, `size`, `proportions`)
- `animate_character` (`character_id`, `template_animation_id` or `action_description`, `frame_count`)
- `get_character` (rotation + animation **download URLs** — no auth needed), `list_characters`,
  `delete_character`, `get_balance`.
**Plan:** per class, `create_character` (8 dir) → `animate_character` for idle/walk/attack/special/
dash/hurt/death (8 dir) → `get_character` → fetch PNGs → restructure into the `assets/` layout above
→ update manifests → verify in headless → push. Detailed per-class animation prompts are in the
chat history / the plan file.

## Roadmap (see /root/.claude/plans/swift-wishing-cat.md if present)
DONE: run structure + bosses + new enemies (timed 10-min victory, mini-bosses, final boss "Warden");
permanent meta-upgrade shop (Vigor/Might/Haste/Fortune + buyable Revive); 16×16 coded pixel art;
external sprite loader; 8-dir characters; **8-dir animations for all 5 player classes**.
PENDING **Phase 3**: balance tuning; first-run tooltips + How-to-Play; installable PWA
(manifest + icons + service worker). Also: barbarian + enemy/boss sprites & animations.
