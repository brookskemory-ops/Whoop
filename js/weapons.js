// ── Ironvow: data-driven weapons ───────────────────────────────────────────
// Every weapon implements one of four patterns via the ctx API the game passes in:
//   - projectile : fire() spawns one or more travelling projectiles
//   - melee      : fire() deals instant area damage in front of the player (a swing)
//   - nova       : fire() deals instant area damage centered on the player
//   - orbital    : init() sets player.orbital; the game maintains a spinning ring
//
// ctx exposes: player, rng, nearest(), spawnProjectile(o), areaDamage(x,y,r,mult,opts),
//              addEffect(e), dirToNearest()

// Roll a crit for the current player; returns a damage multiplier.
function critRoll(ctx) {
  if (ctx.rng.float() < ctx.player.crit) return { mult: ctx.player.critMult, crit: true };
  return { mult: 1, crit: false };
}

const WEAPONS = [
  // ── Knight ────────────────────────────────────────────────────────────────
  {
    id: 'arming_sword', name: 'Arming Sword', classId: 'knight', type: 'melee', cooldown: 0.7,
    unlock: { type: 'default' },
    desc: 'Sweeping arc that strikes all foes in front.',
    fire(ctx) {
      const p = ctx.player;
      const dir = ctx.dirToNearest();
      const range = 56 * p.projectileSize / 6;
      const cx = p.x + Math.cos(dir) * range * 0.5;
      const cy = p.y + Math.sin(dir) * range * 0.5;
      const { mult, crit } = critRoll(ctx);
      ctx.areaDamage(cx, cy, range, 1.5 * mult, { crit, knockback: 90 });
      ctx.addEffect({ type: 'swing', x: p.x, y: p.y, angle: dir, range, life: 0.16, color: '#dfe7f5' });
    },
  },
  {
    id: 'warhammer', name: 'Warhammer', classId: 'knight', type: 'melee', cooldown: 1.3,
    unlock: { type: 'gold', cost: 120 },
    desc: 'Slow, devastating slam with heavy knockback.',
    fire(ctx) {
      const p = ctx.player;
      const dir = ctx.dirToNearest();
      const range = 86 * p.projectileSize / 6;
      const cx = p.x + Math.cos(dir) * range * 0.45;
      const cy = p.y + Math.sin(dir) * range * 0.45;
      const { mult, crit } = critRoll(ctx);
      ctx.areaDamage(cx, cy, range, 2.6 * mult, { crit, knockback: 260 });
      ctx.addEffect({ type: 'ring', x: cx, y: cy, r: 6, maxR: range, life: 0.25, color: '#b9c2d6' });
    },
  },

  // ── Archer ─────────────────────────────────────────────────────────────────
  {
    id: 'shortbow', name: 'Shortbow', classId: 'archer', type: 'projectile', cooldown: 0.6,
    unlock: { type: 'default' },
    desc: 'Fires an arrow that pierces one enemy.',
    fire(ctx) {
      const p = ctx.player;
      const a = ctx.dirToNearest();
      const { mult, crit } = critRoll(ctx);
      ctx.spawnProjectile({
        vx: Math.cos(a) * p.projectileSpeed, vy: Math.sin(a) * p.projectileSpeed,
        dmg: p.damage * mult, crit, pierce: p.pierce + 1, r: p.projectileSize, color: '#cdeccd',
      });
    },
  },
  {
    id: 'crossbow', name: 'Crossbow', classId: 'archer', type: 'projectile', cooldown: 0.35,
    unlock: { type: 'achievement', achievement: 'archer_kills_500' },
    desc: 'Rapid bolts that punch through three foes.',
    fire(ctx) {
      const p = ctx.player;
      const a = ctx.dirToNearest();
      const { mult, crit } = critRoll(ctx);
      ctx.spawnProjectile({
        vx: Math.cos(a) * p.projectileSpeed * 1.25, vy: Math.sin(a) * p.projectileSpeed * 1.25,
        dmg: p.damage * mult, crit, pierce: p.pierce + 3, r: p.projectileSize * 0.9, color: '#a9e6b4',
      });
    },
  },

  // ── Mage ─────────────────────────────────────────────────────────────────
  {
    id: 'fireball', name: 'Fireball', classId: 'mage', type: 'projectile', cooldown: 0.85,
    unlock: { type: 'default' },
    desc: 'Hurls a fireball that bursts on impact.',
    fire(ctx) {
      const p = ctx.player;
      const a = ctx.dirToNearest();
      const { mult, crit } = critRoll(ctx);
      ctx.spawnProjectile({
        vx: Math.cos(a) * p.projectileSpeed * 0.8, vy: Math.sin(a) * p.projectileSpeed * 0.8,
        dmg: p.damage * mult, crit, pierce: 0, r: p.projectileSize * 1.3, color: '#ff9a4a',
        onHit: (hx, hy, c) => {
          c.areaDamage(hx, hy, 60 * p.aoeMult, 0.8, { color: '#ff7a2a' });
          c.addEffect({ type: 'ring', x: hx, y: hy, r: 6, maxR: 60 * p.aoeMult, life: 0.3, color: '#ff7a2a' });
        },
      });
    },
  },
  {
    id: 'frost_nova', name: 'Frost Nova', classId: 'mage', type: 'nova', cooldown: 1.5,
    unlock: { type: 'achievement', achievement: 'survive_12' },
    desc: 'Erupts frost around you, chilling all nearby.',
    fire(ctx) {
      const p = ctx.player;
      const radius = 120 * p.aoeMult;
      const { mult } = critRoll(ctx);
      ctx.areaDamage(p.x, p.y, radius, 0.9 * mult, { slow: 1.5, color: '#7fd0ff' });
      ctx.addEffect({ type: 'ring', x: p.x, y: p.y, r: 6, maxR: radius, life: 0.35, color: '#7fd0ff' });
    },
  },

  // ── Rogue ─────────────────────────────────────────────────────────────────
  {
    id: 'daggers', name: 'Throwing Daggers', classId: 'rogue', type: 'projectile', cooldown: 0.28,
    unlock: { type: 'default' },
    desc: 'Flings rapid daggers with a high crit rate.',
    fire(ctx) {
      const p = ctx.player;
      const a = ctx.dirToNearest() + (ctx.rng.float() - 0.5) * 0.12;
      const { mult, crit } = critRoll(ctx);
      ctx.spawnProjectile({
        vx: Math.cos(a) * p.projectileSpeed * 1.1, vy: Math.sin(a) * p.projectileSpeed * 1.1,
        dmg: p.damage * mult, crit, pierce: p.pierce, r: p.projectileSize * 0.8, color: '#f4dd8a',
      });
    },
  },
  {
    id: 'fan_of_knives', name: 'Fan of Knives', classId: 'rogue', type: 'projectile', cooldown: 0.7,
    unlock: { type: 'gold', cost: 140 },
    desc: 'Throws a spread volley of knives at once.',
    fire(ctx) {
      const p = ctx.player;
      const base = ctx.dirToNearest();
      const n = 4 + p.projectileCount;
      const spread = 0.5;
      for (let i = 0; i < n; i++) {
        const a = base + (i - (n - 1) / 2) * (spread / n);
        const { mult, crit } = critRoll(ctx);
        ctx.spawnProjectile({
          vx: Math.cos(a) * p.projectileSpeed, vy: Math.sin(a) * p.projectileSpeed,
          dmg: p.damage * mult, crit, pierce: p.pierce, r: p.projectileSize * 0.8, color: '#f4dd8a',
        });
      }
    },
  },

  // ── Cleric ─────────────────────────────────────────────────────────────────
  {
    id: 'holy_bolt', name: 'Holy Bolt', classId: 'cleric', type: 'projectile', cooldown: 0.7,
    unlock: { type: 'default' },
    desc: 'Looses a bolt of light; a healing aura sustains you.',
    fire(ctx) {
      const p = ctx.player;
      const a = ctx.dirToNearest();
      const { mult, crit } = critRoll(ctx);
      ctx.spawnProjectile({
        vx: Math.cos(a) * p.projectileSpeed, vy: Math.sin(a) * p.projectileSpeed,
        dmg: p.damage * 1.1 * mult, crit, pierce: p.pierce + 1, r: p.projectileSize, color: '#fff3c4',
      });
    },
  },
  {
    id: 'censer', name: 'Holy Censer', classId: 'cleric', type: 'orbital', cooldown: 0.7,
    unlock: { type: 'gold', cost: 160 },
    desc: 'Censers of holy flame orbit and scorch the unworthy.',
    init(p) { p.orbital = { count: 2, mult: 0.55, dist: 74, speed: 2.4, r: 14, color: '#fff3c4' }; },
    fire() {},
  },

  // ── Barbarian ──────────────────────────────────────────────────────────────
  {
    id: 'whirlwind_axe', name: 'Whirlwind Axe', classId: 'barbarian', type: 'orbital', cooldown: 0.7,
    unlock: { type: 'default' },
    desc: 'Axes whirl around you, cleaving anything close.',
    init(p) { p.orbital = { count: 2, mult: 0.6, dist: 64, speed: 3.0, r: 16, color: '#e2655a' }; },
    fire() {},
  },
  {
    id: 'throwing_axe', name: 'Throwing Axe', classId: 'barbarian', type: 'projectile', cooldown: 0.9,
    unlock: { type: 'gold', cost: 150 },
    desc: 'Lobs a heavy axe that tears through ranks.',
    fire(ctx) {
      const p = ctx.player;
      const a = ctx.dirToNearest();
      const { mult, crit } = critRoll(ctx);
      ctx.spawnProjectile({
        vx: Math.cos(a) * p.projectileSpeed * 0.85, vy: Math.sin(a) * p.projectileSpeed * 0.85,
        dmg: p.damage * 1.8 * mult, crit, pierce: p.pierce + 2, r: p.projectileSize * 1.4, color: '#d98c5a',
        spin: true,
      });
    },
  },
];

const WEAPON_BY_ID = {};
for (const w of WEAPONS) WEAPON_BY_ID[w.id] = w;

window.WEAPONS = WEAPONS;
window.WEAPON_BY_ID = WEAPON_BY_ID;
