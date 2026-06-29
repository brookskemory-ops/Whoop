// ── Ironvow: active ability skills ─────────────────────────────────────────
// Abilities are real actions, not stat boosts. Three kinds:
//   - attack   : auto-fires on its own cooldown. activate(ctx, rank) performs it.
//   - orbit    : a persistent spinning ring. sync(player, rank) (re)builds its group.
//   - movement : MANUAL — triggered by an on-screen button. activate(ctx, rank).
// Every ability has ranks; a level-up either grants a new ability (rank 1) or ranks
// up one you own. `cooldown(rank)` and the effect both scale with rank.
//
// ctx provides: player, rng, enemies, elapsed, nearest(), dirToNearest(),
//   spawnProjectile(o), areaDamage(x,y,radius,mult,opts), damage(enemy,amt,crit),
//   addEffect(e), orbitGroup(key).

const lerp = (a, b, t) => a + (b - a) * t;

// ── Reusable mechanics (parameterised so many abilities share rendering/logic) ──
function novaSkill(o) {
  return {
    id: o.id, name: o.name, classId: o.classId, kind: 'attack', icon: o.icon || '✸', maxRank: o.maxRank,
    cooldown: (r) => Math.max(o.cdMin || 1, o.cd - (o.cdStep || 0) * (r - 1)),
    desc: (r) => `${o.flavor} — ${Math.round((o.dmg + (o.dmgStep || 0) * (r - 1)) * 100)}% dmg, ${Math.round(o.rad + (o.radStep || 0) * (r - 1))} radius`,
    activate(ctx, r) {
      const p = ctx.player, rad = o.rad + (o.radStep || 0) * (r - 1), mult = o.dmg + (o.dmgStep || 0) * (r - 1);
      ctx.areaDamage(p.x, p.y, rad, mult, { color: o.color, slow: o.slow, knockback: o.knock });
      ctx.addEffect({ type: 'ring', x: p.x, y: p.y, r: 6, maxR: rad, life: 0.3, color: o.color });
      if (o.heal) p.hp = Math.min(p.maxHp, p.hp + o.heal);
    },
  };
}
function slamSkill(o) { // targeted AoE on the nearest enemy cluster
  return {
    id: o.id, name: o.name, classId: o.classId, kind: 'attack', icon: o.icon || '☄', maxRank: o.maxRank,
    cooldown: (r) => Math.max(o.cdMin || 1, o.cd - (o.cdStep || 0) * (r - 1)),
    desc: (r) => `${o.flavor} — ${Math.round((o.dmg + (o.dmgStep || 0) * (r - 1)) * 100)}% dmg, ${Math.round(o.rad + (o.radStep || 0) * (r - 1))} radius`,
    activate(ctx, r) {
      const t = ctx.nearest(); if (!t) return;
      const rad = o.rad + (o.radStep || 0) * (r - 1), mult = o.dmg + (o.dmgStep || 0) * (r - 1);
      ctx.areaDamage(t.x, t.y, rad, mult, { color: o.color, slow: o.slow, knockback: o.knock });
      ctx.addEffect({ type: 'ring', x: t.x, y: t.y, r: 6, maxR: rad, life: 0.32, color: o.color });
    },
  };
}
function volleySkill(o) { // spread of projectiles toward the nearest enemy
  return {
    id: o.id, name: o.name, classId: o.classId, kind: 'attack', icon: o.icon || '➹', maxRank: o.maxRank,
    cooldown: (r) => Math.max(o.cdMin || 0.6, o.cd - (o.cdStep || 0) * (r - 1)),
    desc: (r) => `${o.flavor} — ${o.count + (o.countStep || 1) * (r - 1)} projectiles`,
    activate(ctx, r) {
      const p = ctx.player, base = ctx.dirToNearest(), n = o.count + (o.countStep || 1) * (r - 1);
      const spread = o.spread || 0.6;
      for (let i = 0; i < n; i++) {
        const a = base + (n === 1 ? 0 : (i - (n - 1) / 2) * (spread / n));
        ctx.spawnProjectile({
          vx: Math.cos(a) * (o.speed || 460), vy: Math.sin(a) * (o.speed || 460),
          dmg: p.damage * (o.dmg || 0.8), pierce: o.pierce || 0, r: o.size || 6, color: o.color, shape: o.shape || 'orb',
        });
      }
    },
  };
}
function radialSkill(o) { // projectiles in all directions
  return {
    id: o.id, name: o.name, classId: o.classId, kind: 'attack', icon: o.icon || '✺', maxRank: o.maxRank,
    cooldown: (r) => Math.max(o.cdMin || 1.2, o.cd - (o.cdStep || 0) * (r - 1)),
    desc: (r) => `${o.flavor} — ${o.count + (o.countStep || 2) * (r - 1)} bolts outward`,
    activate(ctx, r) {
      const p = ctx.player, n = o.count + (o.countStep || 2) * (r - 1);
      for (let i = 0; i < n; i++) {
        const a = (i / n) * Math.PI * 2;
        ctx.spawnProjectile({
          vx: Math.cos(a) * (o.speed || 380), vy: Math.sin(a) * (o.speed || 380),
          dmg: p.damage * (o.dmg || 0.7), pierce: o.pierce || 0, r: o.size || 6, color: o.color, shape: o.shape || 'orb',
        });
      }
    },
  };
}
function chainSkill(o) { // bolt that leaps between nearby enemies
  return {
    id: o.id, name: o.name, classId: o.classId, kind: 'attack', icon: o.icon || '⚡', maxRank: o.maxRank,
    cooldown: (r) => Math.max(o.cdMin || 1.2, o.cd - (o.cdStep || 0) * (r - 1)),
    desc: (r) => `${o.flavor} — leaps to ${o.targets + (o.targetStep || 1) * (r - 1)} foes`,
    activate(ctx, r) {
      const p = ctx.player, hops = o.targets + (o.targetStep || 1) * (r - 1), seen = new Set();
      let from = { x: p.x, y: p.y };
      for (let i = 0; i < hops; i++) {
        let best = null, bd = Infinity;
        for (const e of ctx.enemies) {
          if (e.hp <= 0 || seen.has(e)) continue;
          const d = (e.x - from.x) ** 2 + (e.y - from.y) ** 2;
          if (d < bd) { bd = d; best = e; }
        }
        if (!best) break;
        seen.add(best);
        ctx.damage(best, p.damage * (o.dmg || 1.1), false);
        ctx.addEffect({ type: 'line', x1: from.x, y1: from.y, x2: best.x, y2: best.y, life: 0.16, color: o.color });
        from = best;
      }
    },
  };
}
function orbitSkill(o) { // persistent spinning ring
  return {
    id: o.id, name: o.name, classId: o.classId, kind: 'orbit', icon: o.icon || '✦', maxRank: o.maxRank,
    desc: (r) => `${o.flavor} — ${o.count + (o.countStep || 1) * (r - 1)} orbiting, ${Math.round((o.dmg + (o.dmgStep || 0) * (r - 1)) * 100)}% dmg`,
    sync(p, r) {
      const g = p.orbitGroups.find((x) => x.key === o.id) || (() => { const ng = { key: o.id, orbs: [] }; p.orbitGroups.push(ng); return ng; })();
      g.count = o.count + (o.countStep || 1) * (r - 1);
      g.mult = o.dmg + (o.dmgStep || 0) * (r - 1);
      g.dist = o.dist || 70; g.speed = o.speed || 2.8; g.r = o.size || 14; g.color = o.color;
    },
  };
}
function dashSkill(o) { // manual burst movement (+ optional contact damage)
  return {
    id: o.id, name: o.name, classId: o.classId, kind: 'movement', icon: o.icon || '»', maxRank: o.maxRank,
    cooldown: (r) => Math.max(o.cdMin || 1.5, o.cd - (o.cdStep || 0) * (r - 1)),
    desc: (r) => `${o.flavor} — ${Math.round(o.dist + (o.distStep || 0) * (r - 1))} dist` + (o.dmg ? `, ${Math.round((o.dmg + (o.dmgStep || 0) * (r - 1)) * 100)}% dmg` : ''),
    activate(ctx, r) {
      const p = ctx.player;
      let dx = ctx.moveDir.x, dy = ctx.moveDir.y;
      if (dx === 0 && dy === 0) { const a = ctx.dirToNearest(); dx = Math.cos(a); dy = Math.sin(a); }
      const mag = Math.hypot(dx, dy) || 1; dx /= mag; dy /= mag;
      const dist = o.dist + (o.distStep || 0) * (r - 1), dur = 0.16;
      p.dash = { vx: (dx * dist) / dur, vy: (dy * dist) / dur, time: dur, hitMult: o.dmg ? o.dmg + (o.dmgStep || 0) * (r - 1) : 0, color: o.color, hits: new Set() };
      p.invuln = Math.max(p.invuln, 0.3);
    },
  };
}
function blinkSkill(o) { // manual teleport away from danger
  return {
    id: o.id, name: o.name, classId: o.classId, kind: 'movement', icon: o.icon || '✷', maxRank: o.maxRank,
    cooldown: (r) => Math.max(o.cdMin || 2, o.cd - (o.cdStep || 0) * (r - 1)),
    desc: (r) => `${o.flavor} — blink ${Math.round(o.dist + (o.distStep || 0) * (r - 1))} away`,
    activate(ctx, r) {
      const p = ctx.player, t = ctx.nearest();
      const dist = o.dist + (o.distStep || 0) * (r - 1);
      let a;
      if (t) a = Math.atan2(p.y - t.y, p.x - t.x); // away from nearest foe
      else if (ctx.moveDir.x || ctx.moveDir.y) a = Math.atan2(ctx.moveDir.y, ctx.moveDir.x);
      else a = ctx.rng.float() * Math.PI * 2;
      ctx.addEffect({ type: 'ring', x: p.x, y: p.y, r: 6, maxR: 30, life: 0.2, color: o.color });
      p.x += Math.cos(a) * dist; p.y += Math.sin(a) * dist;
      p.invuln = Math.max(p.invuln, 0.4);
      ctx.addEffect({ type: 'ring', x: p.x, y: p.y, r: 6, maxR: 30, life: 0.2, color: o.color });
    },
  };
}

// ── Per-class ability pools ─────────────────────────────────────────────────
const ABILITIES = [
  // Knight — defensive melee
  novaSkill({ id: 'kn_bash', name: 'Shield Bash', classId: 'knight', maxRank: 5, icon: '🛡', flavor: 'Knock foes back around you', cd: 2.2, cdStep: 0.15, rad: 70, radStep: 12, dmg: 1.2, dmgStep: 0.4, knock: 200, color: '#dfe7f5' }),
  orbitSkill({ id: 'kn_whirl', name: 'Whirling Blades', classId: 'knight', maxRank: 5, icon: '⚔', flavor: 'Swords orbit you', count: 2, countStep: 1, dmg: 0.5, dmgStep: 0.12, dist: 70, speed: 3, size: 13, color: '#cdd6e6' }),
  volleySkill({ id: 'kn_spears', name: 'Spear Throw', classId: 'knight', maxRank: 5, icon: '🗡', flavor: 'Hurl spears', cd: 1.6, cdStep: 0.1, count: 1, countStep: 1, dmg: 1.0, pierce: 2, size: 7, color: '#cdd6e6', shape: 'blade' }),
  slamSkill({ id: 'kn_slam', name: 'Ground Slam', classId: 'knight', maxRank: 5, icon: '💥', flavor: 'Shatter the earth', cd: 3, cdStep: 0.2, rad: 80, radStep: 14, dmg: 1.6, dmgStep: 0.5, knock: 140, color: '#b9c2d6' }),
  novaSkill({ id: 'kn_valor', name: 'Valor Pulse', classId: 'knight', maxRank: 5, icon: '✚', flavor: 'Holy pulse heals you', cd: 4, cdStep: 0.2, rad: 90, radStep: 10, dmg: 0.8, dmgStep: 0.25, heal: 12, color: '#f5e9b0' }),
  dashSkill({ id: 'kn_charge', name: 'Valor Dash', classId: 'knight', maxRank: 5, icon: '»', flavor: 'Charge, trampling foes', cd: 4, cdStep: 0.3, dist: 150, distStep: 25, dmg: 1.0, dmgStep: 0.4, color: '#dfe7f5' }),

  // Archer — ranged
  volleySkill({ id: 'ar_multi', name: 'Multishot', classId: 'archer', maxRank: 6, icon: '➶', flavor: 'Fan of arrows', cd: 1.3, cdStep: 0.08, count: 3, countStep: 1, dmg: 0.7, pierce: 1, size: 5, color: '#cdeccd', shape: 'arrow' }),
  slamSkill({ id: 'ar_rain', name: 'Arrow Rain', classId: 'archer', maxRank: 5, icon: '🌧', flavor: 'Arrows fall from above', cd: 2.8, cdStep: 0.2, rad: 75, radStep: 14, dmg: 1.2, dmgStep: 0.4, color: '#bfe0bf' }),
  chainSkill({ id: 'ar_ricochet', name: 'Ricochet', classId: 'archer', maxRank: 6, icon: '⤺', flavor: 'Arrow bounces foe to foe', cd: 1.6, cdStep: 0.1, targets: 2, targetStep: 1, dmg: 0.9, color: '#cdeccd' }),
  radialSkill({ id: 'ar_scatter', name: 'Scattershot', classId: 'archer', maxRank: 5, icon: '✺', flavor: 'Arrows burst outward', cd: 2.4, cdStep: 0.15, count: 6, countStep: 2, dmg: 0.6, pierce: 1, size: 5, color: '#cdeccd', shape: 'arrow' }),
  volleySkill({ id: 'ar_power', name: 'Power Shot', classId: 'archer', maxRank: 5, icon: '➳', flavor: 'Heavy piercing arrow', cd: 1.8, cdStep: 0.12, count: 1, countStep: 0, dmg: 2.4, pierce: 6, size: 9, speed: 600, color: '#a9e6b4', shape: 'arrow' }),
  dashSkill({ id: 'ar_roll', name: 'Dodge Roll', classId: 'archer', maxRank: 5, icon: '»', flavor: 'Nimble evasive roll', cd: 2.5, cdStep: 0.25, dist: 130, distStep: 18, color: '#cdeccd' }),

  // Mage — elemental AoE
  novaSkill({ id: 'mg_firenova', name: 'Fire Nova', classId: 'mage', maxRank: 6, icon: '🔥', flavor: 'Erupt in flame', cd: 2, cdStep: 0.12, rad: 90, radStep: 14, dmg: 1.0, dmgStep: 0.35, color: '#ff7a2a' }),
  slamSkill({ id: 'mg_meteor', name: 'Meteor', classId: 'mage', maxRank: 5, icon: '☄', flavor: 'Call down a meteor', cd: 3, cdStep: 0.2, rad: 95, radStep: 16, dmg: 2.0, dmgStep: 0.6, color: '#ff9a4a' }),
  radialSkill({ id: 'mg_frostring', name: 'Frost Ring', classId: 'mage', maxRank: 5, icon: '❄', flavor: 'Chilling bolts outward', cd: 2.4, cdStep: 0.15, count: 8, countStep: 2, dmg: 0.6, size: 6, color: '#7fd0ff' }),
  chainSkill({ id: 'mg_chain', name: 'Chain Lightning', classId: 'mage', maxRank: 6, icon: '⚡', flavor: 'Lightning arcs between foes', cd: 1.8, cdStep: 0.12, targets: 3, targetStep: 1, dmg: 1.1, color: '#bfe6ff' }),
  orbitSkill({ id: 'mg_orbs', name: 'Arcane Orbs', classId: 'mage', maxRank: 5, icon: '✦', flavor: 'Orbs circle you', count: 2, countStep: 1, dmg: 0.5, dmgStep: 0.12, dist: 76, speed: 2.6, size: 12, color: '#6aa9ff' }),
  blinkSkill({ id: 'mg_blink', name: 'Blink', classId: 'mage', maxRank: 5, icon: '✷', flavor: 'Teleport from danger', cd: 3.5, cdStep: 0.3, dist: 150, distStep: 20, color: '#6aa9ff' }),

  // Rogue — fast & tricky
  volleySkill({ id: 'rg_fan', name: 'Fan of Knives', classId: 'rogue', maxRank: 6, icon: '🔪', flavor: 'Spray of knives', cd: 1.1, cdStep: 0.07, count: 3, countStep: 1, dmg: 0.6, size: 5, spread: 0.9, color: '#f4dd8a', shape: 'blade' }),
  slamSkill({ id: 'rg_poison', name: 'Poison Cloud', classId: 'rogue', maxRank: 5, icon: '☠', flavor: 'Choking venom', cd: 2.6, cdStep: 0.18, rad: 80, radStep: 14, dmg: 1.0, dmgStep: 0.35, slow: 1.0, color: '#9bd34a' }),
  orbitSkill({ id: 'rg_knives', name: 'Whirling Knives', classId: 'rogue', maxRank: 5, icon: '✦', flavor: 'Knives orbit you', count: 3, countStep: 1, dmg: 0.45, dmgStep: 0.1, dist: 60, speed: 4, size: 10, color: '#f4dd8a' }),
  radialSkill({ id: 'rg_burst', name: 'Knife Storm', classId: 'rogue', maxRank: 5, icon: '✺', flavor: 'Knives in all directions', cd: 2.2, cdStep: 0.14, count: 7, countStep: 2, dmg: 0.55, size: 5, color: '#f4dd8a', shape: 'blade' }),
  dashSkill({ id: 'rg_shadow', name: 'Shadow Dash', classId: 'rogue', maxRank: 6, icon: '»', flavor: 'Slip through foes, cutting them', cd: 2, cdStep: 0.2, dist: 150, distStep: 16, dmg: 1.2, dmgStep: 0.35, color: '#cdb0ff' }),
  blinkSkill({ id: 'rg_smoke', name: 'Smoke Step', classId: 'rogue', maxRank: 5, icon: '✷', flavor: 'Vanish in smoke', cd: 3, cdStep: 0.3, dist: 140, distStep: 18, color: '#b0b0c0' }),

  // Cleric — holy support
  novaSkill({ id: 'cl_holynova', name: 'Holy Nova', classId: 'cleric', maxRank: 6, icon: '✨', flavor: 'Burst of light, heals you', cd: 2.2, cdStep: 0.13, rad: 90, radStep: 12, dmg: 1.0, dmgStep: 0.3, heal: 10, color: '#fff3c4' }),
  slamSkill({ id: 'cl_smite', name: 'Smite', classId: 'cleric', maxRank: 5, icon: '⚡', flavor: 'Pillar of holy fire', cd: 2.6, cdStep: 0.18, rad: 80, radStep: 14, dmg: 1.8, dmgStep: 0.5, color: '#fff3c4' }),
  orbitSkill({ id: 'cl_censers', name: 'Censers', classId: 'cleric', maxRank: 5, icon: '✦', flavor: 'Holy flames orbit you', count: 2, countStep: 1, dmg: 0.5, dmgStep: 0.12, dist: 74, speed: 2.6, size: 13, color: '#fff3c4' }),
  volleySkill({ id: 'cl_bolts', name: 'Holy Bolts', classId: 'cleric', maxRank: 5, icon: '➹', flavor: 'Bolts of light', cd: 1.5, cdStep: 0.1, count: 2, countStep: 1, dmg: 0.9, pierce: 1, size: 6, color: '#fff3c4', shape: 'bolt' }),
  chainSkill({ id: 'cl_judgment', name: 'Judgment', classId: 'cleric', maxRank: 5, icon: '✟', flavor: 'Light leaps between foes', cd: 2, cdStep: 0.13, targets: 3, targetStep: 1, dmg: 1.0, color: '#fff3c4' }),
  dashSkill({ id: 'cl_sancdash', name: 'Sanctified Dash', classId: 'cleric', maxRank: 5, icon: '»', flavor: 'Dash on wings of light', cd: 3, cdStep: 0.3, dist: 140, distStep: 18, color: '#fff3c4' }),

  // Barbarian — raging melee
  orbitSkill({ id: 'bb_whirlwind', name: 'Whirlwind', classId: 'barbarian', maxRank: 6, icon: '🪓', flavor: 'Axes whirl about you', count: 2, countStep: 1, dmg: 0.55, dmgStep: 0.12, dist: 66, speed: 3.4, size: 16, color: '#e2655a' }),
  novaSkill({ id: 'bb_cleave', name: 'Cleave', classId: 'barbarian', maxRank: 5, icon: '⚔', flavor: 'Brutal sweeping cleave', cd: 1.8, cdStep: 0.12, rad: 80, radStep: 12, dmg: 1.3, dmgStep: 0.4, knock: 120, color: '#e89a8a' }),
  volleySkill({ id: 'bb_axes', name: 'Axe Throw', classId: 'barbarian', maxRank: 5, icon: '🪃', flavor: 'Hurl heavy axes', cd: 1.6, cdStep: 0.1, count: 1, countStep: 1, dmg: 1.6, pierce: 3, size: 9, speed: 380, color: '#d98c5a', shape: 'axe' }),
  slamSkill({ id: 'bb_quake', name: 'Earthquake', classId: 'barbarian', maxRank: 5, icon: '💥', flavor: 'The ground erupts', cd: 3, cdStep: 0.2, rad: 100, radStep: 16, dmg: 1.7, dmgStep: 0.5, knock: 160, color: '#c08050' }),
  dashSkill({ id: 'bb_rush', name: 'Battle Rush', classId: 'barbarian', maxRank: 6, icon: '»', flavor: 'Charge, smashing through ranks', cd: 2.5, cdStep: 0.2, dist: 160, distStep: 20, dmg: 1.4, dmgStep: 0.4, color: '#e2655a' }),
  slamSkill({ id: 'bb_leap', name: 'Leap Slam', classId: 'barbarian', maxRank: 5, icon: '☄', flavor: 'Crash down on the nearest foe', cd: 3.2, cdStep: 0.22, rad: 90, radStep: 16, dmg: 2.0, dmgStep: 0.6, knock: 180, color: '#e89a8a' }),
];

const ABILITIES_BY_ID = {};
const ABILITIES_BY_CLASS = {};
for (const ab of ABILITIES) {
  ABILITIES_BY_ID[ab.id] = ab;
  (ABILITIES_BY_CLASS[ab.classId] ||= []).push(ab);
}

// Roll `n` level-up options for a class. Each option is a NEW ability (rank 1) or a
// RANK-UP of one already owned (excludes maxed). `owned` maps abilityId -> rank.
function rollAbilities(rng, classId, owned, n = 5) {
  const pool = (ABILITIES_BY_CLASS[classId] || [])
    .filter((ab) => (owned[ab.id] || 0) < ab.maxRank)
    .map((ab) => {
      const cur = owned[ab.id] || 0;
      return { ability: ab, isNew: cur === 0, nextRank: cur + 1 };
    });
  const out = [];
  for (let i = 0; i < n && pool.length; i++) out.push(pool.splice(rng.int(0, pool.length - 1), 1)[0]);
  return out;
}

window.ABILITIES = ABILITIES;
window.ABILITIES_BY_ID = ABILITIES_BY_ID;
window.ABILITIES_BY_CLASS = ABILITIES_BY_CLASS;
window.rollAbilities = rollAbilities;
