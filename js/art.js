// ── Ironvow: procedural art ────────────────────────────────────────────────
// All textures/sprites are drawn in code ONCE into offscreen canvases, then blitted
// each frame (cheap on phones — no per-frame gradients/shadows). Gritty dark-dungeon
// palette. Nothing here is loaded from disk.

const Art = (() => {
  function make(w, h) {
    const c = document.createElement('canvas');
    c.width = w; c.height = h;
    return c;
  }
  // Deterministic value noise so tiles look the same every load.
  function hash2(x, y) {
    let h = (x * 374761393 + y * 668265263) >>> 0;
    h = (h ^ (h >>> 13)) * 1274126177 >>> 0;
    return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
  }

  // ── Floor: a tiling dark-stone slab with grout, speckle and the odd crack ──
  const TILE = 128;
  function buildFloorTile() {
    const c = make(TILE, TILE), g = c.getContext('2d');
    g.fillStyle = '#1b1812'; g.fillRect(0, 0, TILE, TILE);
    // 2x2 stone slabs with bevelled grout
    const half = TILE / 2;
    for (let sx = 0; sx < 2; sx++) for (let sy = 0; sy < 2; sy++) {
      const x = sx * half, y = sy * half;
      const tone = 28 + Math.floor(hash2(sx + 7, sy + 3) * 18);
      g.fillStyle = `rgb(${tone + 6},${tone + 2},${tone - 4})`;
      g.fillRect(x + 2, y + 2, half - 4, half - 4);
      // top/left highlight, bottom/right shadow
      g.fillStyle = 'rgba(255,235,200,0.05)'; g.fillRect(x + 2, y + 2, half - 4, 2);
      g.fillStyle = 'rgba(255,235,200,0.04)'; g.fillRect(x + 2, y + 2, 2, half - 4);
      g.fillStyle = 'rgba(0,0,0,0.35)'; g.fillRect(x + 2, y + half - 4, half - 4, 2);
      g.fillStyle = 'rgba(0,0,0,0.3)'; g.fillRect(x + half - 4, y + 2, 2, half - 4);
    }
    // speckle
    for (let i = 0; i < 360; i++) {
      const x = Math.floor(hash2(i, 11) * TILE), y = Math.floor(hash2(i, 29) * TILE);
      const v = hash2(i, 47);
      g.fillStyle = v > 0.5 ? 'rgba(255,240,210,0.05)' : 'rgba(0,0,0,0.22)';
      g.fillRect(x, y, 1, 1);
    }
    // occasional crack
    if (true) {
      g.strokeStyle = 'rgba(0,0,0,0.4)'; g.lineWidth = 1.5;
      g.beginPath();
      let x = 20, y = 96; g.moveTo(x, y);
      for (let i = 0; i < 6; i++) { x += 8 + hash2(i, 5) * 12; y += (hash2(i, 9) - 0.5) * 16; g.lineTo(x, y); }
      g.stroke();
    }
    return c;
  }
  let floorTile = null, floorPattern = null;
  function floorPatternFor(ctx) {
    if (!floorTile) floorTile = buildFloorTile();
    if (!floorPattern) floorPattern = ctx.createPattern(floorTile, 'repeat');
    return floorPattern;
  }

  // ── Enemy sprites (drawn facing +x; rotated at draw time) ──────────────────
  const enemyCache = {};
  function buildEnemy(type) {
    const defs = {
      skeleton: { r: 12, body: '#d8d4c2', shade: '#9a9684', eye: '#cfeaff' },
      goblin: { r: 11, body: '#7bbf63', shade: '#4f8a3e', eye: '#ffe27a' },
      ogre: { r: 21, body: '#9b59b6', shade: '#6c3b80', eye: '#ff6a6a' },
      shooter: { r: 12, body: '#6aa9ff', shade: '#3a6bb0', eye: '#eaf4ff' },
      exploder: { r: 13, body: '#e8893a', shade: '#a65616', eye: '#fff0c0' },
      splitter: { r: 16, body: '#caa24a', shade: '#8a6a22', eye: '#fff0c0' },
      charger: { r: 15, body: '#d05a7a', shade: '#8c2f4c', eye: '#ffd0dc' },
      miniboss: { r: 34, body: '#b14a8a', shade: '#6c2754', eye: '#ffd0f0' },
      finalboss: { r: 48, body: '#c0341f', shade: '#7a160a', eye: '#ffd06a' },
    };
    const d = defs[type], R = d.r, S = R * 2 + 8, cx = S / 2, cy = S / 2;
    const c = make(S, S), g = c.getContext('2d');
    // body with radial shading
    const grd = g.createRadialGradient(cx - R * 0.3, cy - R * 0.3, R * 0.2, cx, cy, R);
    grd.addColorStop(0, d.body); grd.addColorStop(1, d.shade);
    g.fillStyle = grd; g.beginPath(); g.arc(cx, cy, R, 0, Math.PI * 2); g.fill();
    g.strokeStyle = 'rgba(0,0,0,0.45)'; g.lineWidth = 2; g.stroke();
    // simple facial features near the front (+x side)
    const ex = cx + R * 0.4;
    g.fillStyle = '#0c0a08';
    g.beginPath(); g.arc(ex, cy - R * 0.32, R * 0.22, 0, Math.PI * 2); g.fill();
    g.beginPath(); g.arc(ex, cy + R * 0.32, R * 0.22, 0, Math.PI * 2); g.fill();
    g.fillStyle = d.eye;
    g.beginPath(); g.arc(ex + 0.5, cy - R * 0.32, R * 0.1, 0, Math.PI * 2); g.fill();
    g.beginPath(); g.arc(ex + 0.5, cy + R * 0.32, R * 0.1, 0, Math.PI * 2); g.fill();
    if (type === 'skeleton') { // ribs
      g.strokeStyle = 'rgba(0,0,0,0.25)'; g.lineWidth = 1;
      for (let i = -1; i <= 1; i++) { g.beginPath(); g.arc(cx - R * 0.2, cy, R * 0.55 + i * 3, -0.7, 0.7); g.stroke(); }
    }
    return { canvas: c, cx, cy, R, eyeColor: d.eye };
  }
  function enemySprite(type) { return enemyCache[type] || (enemyCache[type] = buildEnemy(type)); }

  // ── Player class sprites (facing +x) ───────────────────────────────────────
  const classCache = {};
  function buildClass(classId, color) {
    const R = 15, S = R * 2 + 12, cx = S / 2, cy = S / 2;
    const c = make(S, S), g = c.getContext('2d');
    const grd = g.createRadialGradient(cx - R * 0.3, cy - R * 0.3, R * 0.2, cx, cy, R);
    grd.addColorStop(0, '#fdfdfd'); grd.addColorStop(0.25, color); grd.addColorStop(1, shade(color, 0.55));
    g.fillStyle = grd; g.beginPath(); g.arc(cx, cy, R, 0, Math.PI * 2); g.fill();
    g.strokeStyle = 'rgba(0,0,0,0.5)'; g.lineWidth = 2; g.stroke();
    // emblem hint per class, on the front
    g.fillStyle = 'rgba(15,12,8,0.85)'; g.strokeStyle = 'rgba(15,12,8,0.85)'; g.lineWidth = 2.5;
    g.save(); g.translate(cx, cy);
    const fx = R * 0.45;
    if (classId === 'knight') { g.fillRect(fx - 4, -5, 8, 10); } // shield
    else if (classId === 'archer') { g.beginPath(); g.arc(fx, 0, 6, -1.1, 1.1); g.stroke(); } // bow
    else if (classId === 'mage') { g.beginPath(); g.moveTo(fx - 4, 6); g.lineTo(fx, -7); g.lineTo(fx + 4, 6); g.closePath(); g.fill(); } // hat
    else if (classId === 'rogue') { g.beginPath(); g.moveTo(fx - 4, -4); g.lineTo(fx + 5, 0); g.lineTo(fx - 4, 4); g.closePath(); g.fill(); } // dagger
    else if (classId === 'cleric') { g.fillRect(fx - 1.5, -7, 3, 14); g.fillRect(fx - 5, -2, 10, 3); } // cross
    else if (classId === 'barbarian') { g.beginPath(); g.arc(fx + 1, 0, 6, -1.3, 1.3); g.lineWidth = 3; g.stroke(); g.fillRect(fx - 4, -1.5, 6, 3); } // axe
    g.restore();
    return { canvas: c, cx, cy, R };
  }
  function classSprite(classId) {
    if (classCache[classId]) return classCache[classId];
    const cls = window.CLASS_BY_ID[classId];
    return (classCache[classId] = buildClass(classId, cls ? cls.color : '#cccccc'));
  }

  // ── Glowing projectile sprites, cached by color+size+shape ─────────────────
  const projCache = {};
  function buildProj(color, size, shape) {
    const pad = size * 3, S = Math.ceil(size * 6 + pad);
    const c = make(S, S), g = c.getContext('2d'), cx = S / 2, cy = S / 2;
    // glow
    const gr = g.createRadialGradient(cx, cy, 0, cx, cy, size * 2.2);
    gr.addColorStop(0, color); gr.addColorStop(0.4, color + '88'); gr.addColorStop(1, color + '00');
    g.fillStyle = gr; g.beginPath(); g.arc(cx, cy, size * 2.2, 0, Math.PI * 2); g.fill();
    g.fillStyle = color; g.strokeStyle = 'rgba(255,255,255,0.85)'; g.lineWidth = 1;
    if (shape === 'arrow' || shape === 'bolt') {
      g.beginPath(); g.moveTo(cx + size * 2, cy); g.lineTo(cx - size, cy - size); g.lineTo(cx - size * 0.4, cy); g.lineTo(cx - size, cy + size); g.closePath(); g.fill();
    } else if (shape === 'blade') {
      g.beginPath(); g.moveTo(cx + size * 2, cy); g.lineTo(cx - size, cy - size * 1.1); g.lineTo(cx - size, cy + size * 1.1); g.closePath(); g.fill();
    } else if (shape === 'axe') {
      g.beginPath(); g.arc(cx + size * 0.5, cy, size * 1.6, -1.2, 1.2); g.lineWidth = size; g.strokeStyle = color; g.stroke();
    } else { // orb
      g.beginPath(); g.arc(cx, cy, size, 0, Math.PI * 2); g.fill();
      g.fillStyle = 'rgba(255,255,255,0.7)'; g.beginPath(); g.arc(cx - size * 0.3, cy - size * 0.3, size * 0.4, 0, Math.PI * 2); g.fill();
    }
    return { canvas: c, cx, cy };
  }
  function projSprite(color, size, shape) {
    const key = `${color}|${Math.round(size)}|${shape}`;
    return projCache[key] || (projCache[key] = buildProj(color, Math.max(3, size), shape || 'orb'));
  }

  // ── Eye-glow for enemies lurking in darkness ───────────────────────────────
  let eyeSprite = null;
  function eyeGlow() {
    if (eyeSprite) return eyeSprite;
    const S = 24, c = make(S, S), g = c.getContext('2d'), cx = S / 2, cy = S / 2;
    const gr = g.createRadialGradient(cx, cy, 0, cx, cy, S / 2);
    gr.addColorStop(0, 'rgba(255,120,90,0.95)'); gr.addColorStop(0.5, 'rgba(255,70,50,0.4)'); gr.addColorStop(1, 'rgba(255,40,30,0)');
    g.fillStyle = gr; g.fillRect(0, 0, S, S);
    return (eyeSprite = c);
  }

  function shade(hex, f) {
    const n = parseInt(hex.slice(1), 16);
    const r = Math.round(((n >> 16) & 255) * f), gg = Math.round(((n >> 8) & 255) * f), b = Math.round((n & 255) * f);
    return `rgb(${r},${gg},${b})`;
  }

  return { floorPatternFor, enemySprite, classSprite, projSprite, eyeGlow, TILE };
})();

window.Art = Art;
