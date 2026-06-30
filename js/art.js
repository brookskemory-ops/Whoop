// ── Ironvow: hand-authored pixel-art sprites ───────────────────────────────
// Every creature/character/projectile is painted pixel-by-pixel into a tiny
// canvas, then upscaled with smoothing OFF for crisp 16-bit-style art. Sprites
// face "front" and are flipped left/right by the renderer; a 2-frame bob in
// game.js gives them life. The stone floor + eye-glow are unchanged.

const Art = (() => {
  function canvasOf(w, h) { const c = document.createElement('canvas'); c.width = w; c.height = h; return c; }
  function hash2(x, y) { let h = (x * 374761393 + y * 668265263) >>> 0; h = (h ^ (h >>> 13)) * 1274126177 >>> 0; return ((h ^ (h >>> 16)) >>> 0) / 4294967296; }
  function shade(hex, f) { const n = parseInt(hex.slice(1), 16); return `rgb(${Math.round(((n >> 16) & 255) * f)},${Math.round(((n >> 8) & 255) * f)},${Math.round((n & 255) * f)})`; }
  function light(hex, f) { const n = parseInt(hex.slice(1), 16); const m = (v) => Math.min(255, Math.round(v + (255 - v) * f)); return `rgb(${m((n >> 16) & 255)},${m((n >> 8) & 255)},${m(n & 255)})`; }

  // Paint into an N×N grid then upscale to `disp` px. Returns {canvas, cx, cy}.
  function pixel(paint, native, disp) {
    const base = canvasOf(native, native), g = base.getContext('2d');
    const P = {
      set: (x, y, c) => { g.fillStyle = c; g.fillRect(x | 0, y | 0, 1, 1); },
      rect: (x, y, w, h, c) => { g.fillStyle = c; g.fillRect(x | 0, y | 0, w | 0, h | 0); },
      // mirror a column-symmetric pixel: draws at x and (N-1-x)
      sym: (x, y, c, n) => { g.fillStyle = c; g.fillRect(x | 0, y | 0, 1, 1); g.fillRect((n - 1 - x) | 0, y | 0, 1, 1); },
    };
    paint(P, native);
    const out = canvasOf(disp, disp), og = out.getContext('2d');
    og.imageSmoothingEnabled = false;
    og.drawImage(base, 0, 0, disp, disp);
    return { canvas: out, cx: disp / 2, cy: disp / 2 };
  }

  // ── Shared humanoid base for the 6 classes (16×16, front-facing) ───────────
  function humanoid(P, c) {
    const N = 16, S = (x, y, col) => P.sym(x, y, col, N);
    // legs
    P.rect(5, 13, 2, 3, c.legs); P.rect(9, 13, 2, 3, c.legs);
    P.rect(5, 15, 2, 1, '#14110d'); P.rect(9, 15, 2, 1, '#14110d');
    // torso
    P.rect(4, 7, 8, 6, c.body);
    P.rect(4, 11, 8, 2, shade(c.body, 0.7));
    P.rect(4, 7, 8, 1, light(c.body, 0.25));
    // arms
    P.rect(3, 7, 1, 5, c.body); P.rect(12, 7, 1, 5, c.body);
    P.set(3, 12, c.skin); P.set(12, 12, c.skin); // hands
    // head
    P.rect(5, 2, 6, 5, c.head);
    P.rect(5, 2, 6, 1, light(c.head, 0.2));
    // eyes
    P.set(6, 4, c.eye || '#1a1410'); P.set(9, 4, c.eye || '#1a1410');
  }

  const CLASS_PAINT = {
    knight: (P) => {
      humanoid(P, { head: '#c9d1e0', body: '#aab3c6', legs: '#566074', skin: '#d8b48a', eye: '#1a1410' });
      P.rect(7, 0, 2, 2, '#e8c14a');            // plume
      P.rect(5, 4, 6, 1, '#3a3f4a');            // visor slit
      P.rect(13, 3, 1, 8, '#e7edf7'); P.set(13, 2, '#fff'); // sword
      P.rect(2, 7, 2, 4, '#7a4a2a'); P.set(2, 8, '#caa24a'); P.set(3, 9, '#caa24a'); // shield
    },
    archer: (P) => {
      humanoid(P, { head: '#6f5a3a', body: '#5f8f4a', legs: '#3c5a2c', skin: '#d8b48a', eye: '#fff' });
      P.rect(5, 1, 6, 2, '#3c5a2c');            // hood
      P.rect(13, 3, 1, 8, '#8a5a2a'); P.set(12, 3, '#8a5a2a'); P.set(12, 10, '#8a5a2a'); P.set(13, 6, '#e7edf7'); // bow + arrow
    },
    mage: (P) => {
      humanoid(P, { head: '#e8c79a', body: '#5a7fd0', legs: '#3a4f86', skin: '#e8c79a', eye: '#1a1410' });
      P.rect(6, 0, 4, 1, '#3a4f86'); P.rect(5, 1, 6, 1, '#4a63a8'); P.set(7, -0, '#6aa9ff'); // wizard hat
      P.rect(4, 1, 8, 1, '#3a4f86');
      P.rect(12, 2, 1, 9, '#8a5a2a'); P.rect(11, 1, 3, 2, '#7fd0ff'); // staff + orb
    },
    rogue: (P) => {
      humanoid(P, { head: '#caa24a', body: '#8a7430', legs: '#4a3e1c', skin: '#caa24a', eye: '#fff' });
      P.rect(5, 1, 6, 2, '#2a2418');           // hood
      P.rect(4, 5, 8, 1, '#2a2418');           // mask band
      P.set(2, 9, '#e7edf7'); P.set(13, 9, '#e7edf7'); // twin daggers
      P.set(2, 10, '#8a8a8a'); P.set(13, 10, '#8a8a8a');
    },
    cleric: (P) => {
      humanoid(P, { head: '#e8c79a', body: '#efe6b6', legs: '#b8ad7e', skin: '#e8c79a', eye: '#1a1410' });
      P.rect(7, 6, 2, 4, '#d9b25a'); P.rect(6, 7, 4, 1, '#d9b25a'); // chest cross
      P.rect(13, 2, 1, 9, '#cbb06a'); P.rect(12, 2, 3, 1, '#f0e6b0'); P.set(13, 1, '#fff'); // holy staff
    },
    barbarian: (P) => {
      humanoid(P, { head: '#d8a070', body: '#b65a3a', legs: '#6e3a24', skin: '#d8a070', eye: '#1a1410' });
      P.rect(4, 2, 8, 1, '#3a2a1a');           // hair band
      P.set(4, 2, '#d8d0c0'); P.set(11, 2, '#d8d0c0'); // horns
      P.rect(4, 8, 8, 1, '#d8a070');           // bare chest
      P.rect(13, 1, 1, 6, '#8a5a2a'); P.rect(12, 1, 3, 3, '#c9d1e0'); // big axe
    },
  };

  // ── Enemies (16×16) ────────────────────────────────────────────────────────
  function blob(P, c, eye) {
    P.rect(4, 5, 8, 8, c); P.rect(3, 7, 1, 4, c); P.rect(12, 7, 1, 4, c);
    P.rect(4, 12, 8, 1, shade(c, 0.6)); P.rect(4, 5, 8, 1, light(c, 0.25));
    P.set(6, 8, eye); P.set(9, 8, eye);
  }
  const ENEMY_PAINT = {
    skeleton: (P) => {
      P.rect(5, 2, 6, 5, '#e8e4d4'); P.rect(5, 6, 6, 1, '#b8b4a4');     // skull
      P.set(6, 4, '#1a1410'); P.set(9, 4, '#1a1410'); P.set(7, 5, '#1a1410');
      P.rect(5, 8, 6, 5, '#d8d4c2');                                     // ribcage
      P.set(5, 9, '#9a9684'); P.set(10, 9, '#9a9684'); P.set(5, 11, '#9a9684'); P.set(10, 11, '#9a9684');
      P.rect(4, 9, 1, 3, '#d8d4c2'); P.rect(11, 9, 1, 3, '#d8d4c2');     // arms
      P.rect(5, 13, 2, 3, '#c8c4b2'); P.rect(9, 13, 2, 3, '#c8c4b2');    // legs
    },
    goblin: (P) => {
      P.rect(4, 4, 8, 7, '#7bbf63'); P.rect(4, 10, 8, 1, '#4f8a3e');
      P.rect(2, 5, 2, 2, '#7bbf63'); P.rect(12, 5, 2, 2, '#7bbf63');     // big ears
      P.set(6, 6, '#ffe27a'); P.set(9, 6, '#ffe27a'); P.set(6, 7, '#1a1410'); P.set(9, 7, '#1a1410');
      P.set(7, 9, '#fff'); P.set(8, 9, '#fff');                          // fangs
      P.rect(5, 11, 2, 4, '#4f8a3e'); P.rect(9, 11, 2, 4, '#4f8a3e');
    },
    ogre: (P) => {
      P.rect(3, 3, 10, 10, '#9b59b6'); P.rect(3, 11, 10, 2, '#6c3b80');
      P.rect(2, 6, 1, 5, '#9b59b6'); P.rect(13, 6, 1, 5, '#9b59b6');     // arms
      P.set(6, 6, '#ff6a6a'); P.set(9, 6, '#ff6a6a');
      P.rect(6, 6, 1, 1, '#fff'); P.rect(9, 6, 1, 1, '#fff');
      P.set(5, 9, '#fff'); P.set(10, 9, '#fff');                         // tusks
      P.rect(4, 13, 3, 3, '#6c3b80'); P.rect(9, 13, 3, 3, '#6c3b80');
    },
    shooter: (P) => { // hooded blue caster
      P.rect(4, 2, 8, 4, '#3a6bb0'); P.rect(5, 3, 6, 3, '#1a2a4a');      // hood/shadow
      P.set(6, 4, '#9ad0ff'); P.set(9, 4, '#9ad0ff');                    // glowing eyes
      P.rect(4, 6, 8, 7, '#6aa9ff'); P.rect(4, 11, 8, 2, '#3a6bb0');
      P.rect(11, 7, 2, 2, '#cdebff');                                    // casting hand glow
    },
    exploder: (P) => { // round bomb-beast with fuse
      P.rect(4, 5, 8, 8, '#e8893a'); P.rect(3, 7, 1, 4, '#e8893a'); P.rect(12, 7, 1, 4, '#e8893a');
      P.rect(4, 11, 8, 2, '#a65616'); P.rect(4, 5, 8, 1, '#ffb060');
      P.set(6, 8, '#1a1410'); P.set(9, 8, '#1a1410'); P.rect(6, 10, 4, 1, '#7a3a10'); // angry mouth
      P.set(8, 3, '#ffec88'); P.set(8, 2, '#ff5a2a'); P.set(7, 4, '#3a2a1a');         // lit fuse
    },
    splitter: (P) => { // amber slime
      P.rect(3, 7, 10, 6, '#caa24a'); P.rect(4, 5, 8, 2, '#caa24a');
      P.rect(3, 12, 10, 1, '#8a6a22'); P.rect(4, 5, 8, 1, '#e8c878');
      P.set(6, 8, '#1a1410'); P.set(9, 8, '#1a1410');
      P.set(4, 13, '#caa24a'); P.set(8, 13, '#caa24a'); P.set(11, 13, '#caa24a'); // droplets
    },
    charger: (P) => { // horned beast, head lowered
      P.rect(4, 5, 8, 7, '#d05a7a'); P.rect(4, 10, 8, 2, '#8c2f4c');
      P.set(3, 4, '#e8d0d8'); P.set(12, 4, '#e8d0d8'); P.set(2, 3, '#e8d0d8'); P.set(13, 3, '#e8d0d8'); // horns
      P.set(6, 7, '#ffd0dc'); P.set(9, 7, '#ffd0dc');
      P.rect(6, 9, 4, 1, '#fff');                                        // bared teeth
      P.rect(5, 12, 2, 3, '#8c2f4c'); P.rect(9, 12, 2, 3, '#8c2f4c');
    },
  };

  // ── Bosses (16×16, upscaled large) ─────────────────────────────────────────
  const BOSS_PAINT = {
    miniboss: (P) => { // armored purple champion w/ crown
      P.rect(3, 3, 10, 10, '#b14a8a'); P.rect(3, 11, 10, 2, '#6c2754');
      P.rect(4, 1, 8, 2, '#f0c869'); P.set(5, 0, '#f0c869'); P.set(8, 0, '#f0c869'); P.set(10, 0, '#f0c869'); // crown
      P.set(6, 6, '#ffd0f0'); P.set(9, 6, '#ffd0f0'); P.rect(6, 6, 1, 1, '#fff'); P.rect(9, 6, 1, 1, '#fff');
      P.rect(2, 6, 1, 6, '#b14a8a'); P.rect(13, 6, 1, 6, '#b14a8a');
      P.rect(0, 5, 2, 8, '#8a8f9a'); P.rect(14, 4, 2, 9, '#c9d1e0'); // shield + great-blade
      P.rect(4, 13, 3, 3, '#6c2754'); P.rect(9, 13, 3, 3, '#6c2754');
    },
    finalboss: (P) => { // crimson horned warden
      P.rect(3, 3, 10, 10, '#c0341f'); P.rect(3, 11, 10, 2, '#7a160a');
      P.set(2, 2, '#2a0a06'); P.set(3, 1, '#2a0a06'); P.set(13, 2, '#2a0a06'); P.set(12, 1, '#2a0a06'); // horns
      P.rect(2, 1, 2, 2, '#3a140a'); P.rect(12, 1, 2, 2, '#3a140a');
      P.rect(5, 6, 2, 2, '#ffd06a'); P.rect(9, 6, 2, 2, '#ffd06a');  // burning eyes
      P.set(6, 6, '#fff'); P.set(10, 6, '#fff');
      P.rect(5, 10, 6, 1, '#ffd06a'); P.set(6, 11, '#ffd06a'); P.set(9, 11, '#ffd06a'); // grin
      P.rect(0, 5, 2, 8, '#1a1410'); P.rect(14, 5, 2, 8, '#1a1410'); // clawed arms
      P.rect(4, 13, 3, 3, '#7a160a'); P.rect(9, 13, 3, 3, '#7a160a');
    },
  };

  // ── Projectiles / pickups (recoloured by passed `color`) ───────────────────
  function projPaint(shape, color) {
    const tip = light(color, 0.5), dk = shade(color, 0.6);
    return (P) => {
      if (shape === 'arrow' || shape === 'bolt') {
        P.rect(1, 4, 5, 1, dk);                      // shaft (points +x)
        P.rect(6, 3, 2, 3, color); P.set(8, 4, tip); // head
        P.set(0, 3, '#f4f0e0'); P.set(0, 5, '#f4f0e0'); // fletch
      } else if (shape === 'blade') {
        P.rect(2, 4, 4, 1, color); P.set(6, 3, tip); P.set(6, 4, tip); P.set(6, 5, tip); P.rect(1, 4, 1, 1, '#5a4a2a');
      } else if (shape === 'axe') {
        P.rect(3, 3, 1, 3, '#6a4a2a'); P.rect(4, 2, 3, 1, color); P.rect(4, 6, 3, 1, color); P.rect(5, 2, 2, 5, color); P.set(6, 3, tip);
      } else { // orb / fireball
        P.rect(3, 2, 3, 4, color); P.rect(2, 3, 5, 2, color); P.set(4, 3, tip); P.set(3, 2, dk); P.set(5, 5, dk);
      }
    };
  }

  // ── Build caches (display sizes tuned to entity radii) ─────────────────────
  const DISP = {
    knight: 36, archer: 36, mage: 36, rogue: 36, cleric: 36, barbarian: 36,
    skeleton: 30, goblin: 28, ogre: 50, shooter: 32, exploder: 34, splitter: 40, charger: 38,
    miniboss: 90, finalboss: 122,
  };
  const classCache = {}, enemyCache = {}, projCache = {};
  function classSprite(id) { return classCache[id] || (classCache[id] = pixel(CLASS_PAINT[id] || CLASS_PAINT.knight, 16, DISP[id] || 36)); }
  function enemySprite(type) {
    if (enemyCache[type]) return enemyCache[type];
    const paint = ENEMY_PAINT[type] || BOSS_PAINT[type] || ENEMY_PAINT.skeleton;
    return (enemyCache[type] = pixel(paint, 16, DISP[type] || 32));
  }
  function projSprite(color, size, shape) {
    const key = `${color}|${Math.round(size)}|${shape}`;
    if (projCache[key]) return projCache[key];
    const disp = Math.max(12, Math.round(size * 3.4));
    return (projCache[key] = pixel(projPaint(shape || 'orb', color), 9, disp));
  }

  // ── Stone floor (unchanged) ────────────────────────────────────────────────
  const TILE = 128;
  function buildFloorTile() {
    const c = canvasOf(TILE, TILE), g = c.getContext('2d');
    g.fillStyle = '#1b1812'; g.fillRect(0, 0, TILE, TILE);
    const half = TILE / 2;
    for (let sx = 0; sx < 2; sx++) for (let sy = 0; sy < 2; sy++) {
      const x = sx * half, y = sy * half, tone = 28 + Math.floor(hash2(sx + 7, sy + 3) * 18);
      g.fillStyle = `rgb(${tone + 6},${tone + 2},${tone - 4})`; g.fillRect(x + 2, y + 2, half - 4, half - 4);
      g.fillStyle = 'rgba(255,235,200,0.05)'; g.fillRect(x + 2, y + 2, half - 4, 2);
      g.fillStyle = 'rgba(0,0,0,0.35)'; g.fillRect(x + 2, y + half - 4, half - 4, 2);
      g.fillStyle = 'rgba(0,0,0,0.3)'; g.fillRect(x + half - 4, y + 2, 2, half - 4);
    }
    for (let i = 0; i < 360; i++) { const x = Math.floor(hash2(i, 11) * TILE), y = Math.floor(hash2(i, 29) * TILE); g.fillStyle = hash2(i, 47) > 0.5 ? 'rgba(255,240,210,0.05)' : 'rgba(0,0,0,0.22)'; g.fillRect(x, y, 1, 1); }
    return c;
  }
  let floorTile = null, floorPattern = null;
  function floorPatternFor(ctx) { if (!floorTile) floorTile = buildFloorTile(); if (!floorPattern) floorPattern = ctx.createPattern(floorTile, 'repeat'); return floorPattern; }

  let eyeSprite = null;
  function eyeGlow() {
    if (eyeSprite) return eyeSprite;
    const S = 24, c = canvasOf(S, S), g = c.getContext('2d'), cx = S / 2, cy = S / 2;
    const gr = g.createRadialGradient(cx, cy, 0, cx, cy, S / 2);
    gr.addColorStop(0, 'rgba(255,120,90,0.95)'); gr.addColorStop(0.5, 'rgba(255,70,50,0.4)'); gr.addColorStop(1, 'rgba(255,40,30,0)');
    g.fillStyle = gr; g.fillRect(0, 0, S, S);
    return (eyeSprite = c);
  }

  return { classSprite, enemySprite, projSprite, eyeGlow, floorPatternFor };
})();

window.Art = Art;
