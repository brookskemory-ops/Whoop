// ── Ironvow: enemy & boss archetypes ───────────────────────────────────────
// Data-driven foes. Each has a `kind` whose behavior is implemented in
// tickEnemyAI(e, ctx, dt); some have an onEnemyDeath(e, ctx) effect. The game
// provides ctx: { player, rng, elapsed, hurtPlayer, hurtArea, spawnEnemyProjectile,
// addEnemy, addEffect, addShake }.

(function () {
  const TAU = Math.PI * 2;

  // base stats. `type` is the Art sprite key; `kind` is the behavior.
  const ENEMY_BASE = {
    skeleton: { kind: 'chaser', type: 'skeleton', r: 12, hp: 18, speed: 70, dmg: 8, color: '#d6d3c4', gold: 1, xp: 1 },
    goblin: { kind: 'chaser', type: 'goblin', r: 10, hp: 12, speed: 132, dmg: 6, color: '#7bbf63', gold: 1, xp: 1 },
    ogre: { kind: 'chaser', type: 'ogre', r: 20, hp: 70, speed: 48, dmg: 16, color: '#9b59b6', gold: 3, xp: 3 },
    shooter: { kind: 'shooter', type: 'shooter', r: 12, hp: 24, speed: 64, dmg: 7, color: '#6aa9ff', gold: 2, xp: 2 },
    exploder: { kind: 'exploder', type: 'exploder', r: 13, hp: 20, speed: 118, dmg: 20, color: '#e8893a', gold: 2, xp: 2 },
    splitter: { kind: 'splitter', type: 'splitter', r: 16, hp: 42, speed: 66, dmg: 9, color: '#caa24a', gold: 2, xp: 2 },
    charger: { kind: 'charger', type: 'charger', r: 15, hp: 46, speed: 60, dmg: 20, color: '#d05a7a', gold: 3, xp: 3 },
    spawnling: { kind: 'chaser', type: 'goblin', r: 7, hp: 7, speed: 150, dmg: 5, color: '#caa24a', gold: 0, xp: 1 },
    miniboss: { kind: 'miniboss', type: 'miniboss', r: 34, hp: 700, speed: 44, dmg: 18, color: '#b14a8a', gold: 25, xp: 8, boss: true },
    finalboss: { kind: 'finalboss', type: 'finalboss', r: 48, hp: 2600, speed: 40, dmg: 24, color: '#c0341f', gold: 120, xp: 10, boss: true, final: true },
  };

  function makeEnemy(key, x, y, scale) {
    const b = ENEMY_BASE[key]; scale = scale || 1;
    const hp = b.hp * scale;
    return {
      kind: b.kind, type: b.type, x, y, r: b.r, hp, maxHp: hp, speed: b.speed, dmg: b.dmg,
      color: b.color, gold: b.gold, xp: b.xp, boss: !!b.boss, final: !!b.final,
      hitFlash: 0, slowUntil: 0, burn: null, facing: 0, telegraph: false,
    };
  }

  // helpers
  function aim(e, p) { return Math.atan2(p.y - e.y, p.x - e.x); }
  function dist(e, p) { return Math.hypot(p.x - e.x, p.y - e.y); }
  function step(e, ang, sp, dt) { e.x += Math.cos(ang) * sp * dt; e.y += Math.sin(ang) * sp * dt; }
  function fireAt(e, ctx, sp, dmg, color, spread) {
    const a = aim(e, ctx.player) + (spread ? (ctx.rng.float() - 0.5) * spread : 0);
    ctx.spawnEnemyProjectile({ x: e.x, y: e.y, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp, r: 6, dmg, color, life: 3.5 });
  }
  function radialBurst(e, ctx, n, sp, dmg, color, phase) {
    for (let i = 0; i < n; i++) {
      const a = (i / n) * TAU + (phase || 0);
      ctx.spawnEnemyProjectile({ x: e.x, y: e.y, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp, r: 7, dmg, color, life: 4 });
    }
  }

  function tickEnemyAI(e, ctx, dt) {
    const p = ctx.player, slow = e.slowUntil > ctx.elapsed ? 0.5 : 1;
    const a = aim(e, p); e.facing = a;
    const d = dist(e, p);
    switch (e.kind) {
      case 'chaser':
        step(e, a, e.speed * slow, dt);
        break;

      case 'shooter': {
        if (d > 280) step(e, a, e.speed * slow, dt);
        else if (d < 210) step(e, a + Math.PI, e.speed * slow, dt); // back away
        else step(e, a + Math.PI / 2, e.speed * 0.5 * slow, dt);    // strafe
        e.shoot = (e.shoot || 1.2) - dt;
        if (e.shoot <= 0 && d < 460) { fireAt(e, ctx, 200, e.dmg, '#9ad0ff', 0); e.shoot = 1.7; }
        break;
      }

      case 'exploder':
        step(e, a, e.speed * slow, dt);
        if (d < e.r + p.r + 2) { e.detonate = true; e.hp = 0; } // killEnemy → onEnemyDeath explosion
        break;

      case 'splitter':
        step(e, a, e.speed * slow, dt);
        break;

      case 'charger': {
        e.cs = e.cs || 'chase';
        if (e.cs === 'chase') { step(e, a, e.speed * slow, dt); if (d < 320) { e.cs = 'wind'; e.ct = 0.7; e.telegraph = true; } }
        else if (e.cs === 'wind') { e.ct -= dt; if (e.ct <= 0) { e.cvx = Math.cos(a) * 440; e.cvy = Math.sin(a) * 440; e.cs = 'charge'; e.ct = 0.5; e.telegraph = false; } }
        else if (e.cs === 'charge') { e.x += e.cvx * dt; e.y += e.cvy * dt; e.ct -= dt; if (e.ct <= 0) { e.cs = 'cool'; e.ct = 1.1; } }
        else { e.ct -= dt; if (e.ct <= 0) e.cs = 'chase'; }
        break;
      }

      case 'miniboss': {
        if (d > 90) step(e, a, e.speed * slow, dt);
        e.atk = (e.atk || 2) - dt;
        if (e.atk <= 0) { radialBurst(e, ctx, 12, 150, e.dmg * 0.55, '#ff7ad0', e.phase || 0); e.phase = (e.phase || 0) + 0.4; e.atk = 2.6; ctx.addShake(3); }
        break;
      }

      case 'finalboss': {
        if (d > 110) step(e, a, e.speed * slow, dt);
        e.atk = (e.atk || 1.5) - dt;
        if (e.atk <= 0) {
          e.ap = (e.ap || 0) + 1;
          if (e.ap % 2 === 0) radialBurst(e, ctx, 16, 165, e.dmg * 0.5, '#ff6a5a', e.phase = (e.phase || 0) + 0.3);
          else for (let i = 0; i < 3; i++) ctx.addEnemy('spawnling', e.x + (ctx.rng.float() - 0.5) * 50, e.y + (ctx.rng.float() - 0.5) * 50);
          e.atk = 2.2; ctx.addShake(4);
        }
        break;
      }
    }
  }

  function onEnemyDeath(e, ctx) {
    if (e.kind === 'exploder') {
      ctx.hurtArea(e.x, e.y, 64, e.dmg);
      ctx.addEffect({ type: 'ring', x: e.x, y: e.y, r: 6, maxR: 64, life: 0.3, maxLife: 0.3, color: '#ff7a2a' });
      ctx.addShake(4);
    } else if (e.kind === 'splitter') {
      for (let i = 0; i < 3; i++) { const a = (i / 3) * TAU; ctx.addEnemy('spawnling', e.x + Math.cos(a) * 16, e.y + Math.sin(a) * 16); }
    }
  }

  window.ENEMY_BASE = ENEMY_BASE;
  window.makeEnemy = makeEnemy;
  window.tickEnemyAI = tickEnemyAI;
  window.onEnemyDeath = onEnemyDeath;
})();
