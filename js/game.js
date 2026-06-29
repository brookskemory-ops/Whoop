// ── Ironvow ────────────────────────────────────────────────────────────────
// A medieval survivor-like roguelite: one-thumb movement, auto-attacking class
// weapons, escalating hordes, in-run ability picks, and meta-progression.

(function () {
  const canvas = document.getElementById('game');
  const ctx = canvas.getContext('2d');

  // ── Canvas sizing (crisp on high-DPI phones) ──────────────────────────────
  let W = 0, H = 0, DPR = 1;
  function resize() {
    DPR = Math.min(window.devicePixelRatio || 1, 2);
    W = window.innerWidth; H = window.innerHeight;
    canvas.width = Math.floor(W * DPR);
    canvas.height = Math.floor(H * DPR);
    canvas.style.width = W + 'px';
    canvas.style.height = H + 'px';
    ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
  }
  window.addEventListener('resize', resize);
  resize();

  // ── Persistent meta-progression ───────────────────────────────────────────
  const META_KEY = 'ironvow-meta-v1';
  function loadMeta() {
    let m = {};
    try { m = JSON.parse(localStorage.getItem(META_KEY)) || {}; } catch {}
    m.gold = m.gold || 0;
    m.bestTime = m.bestTime || 0;
    m.unlockedClasses = m.unlockedClasses || { knight: true };
    m.unlockedWeapons = m.unlockedWeapons || {};
    m.achievements = m.achievements || {};
    m.totalKills = m.totalKills || 0;
    m.classKills = m.classKills || {};
    // Default weapons are always available.
    for (const w of WEAPONS) if (w.unlock.type === 'default') m.unlockedWeapons[w.id] = true;
    for (const c of CLASSES) if (c.unlock.type === 'default') m.unlockedClasses[c.id] = true;
    return m;
  }
  function saveMeta() { try { localStorage.setItem(META_KEY, JSON.stringify(meta)); } catch {} }
  let meta = loadMeta();

  function classUnlocked(c) { return !!meta.unlockedClasses[c.id]; }
  function weaponUnlocked(w) { return !!meta.unlockedWeapons[w.id]; }

  // ── DOM ───────────────────────────────────────────────────────────────────
  const el = (id) => document.getElementById(id);
  const screens = ['title-screen', 'class-screen', 'shop-screen', 'ach-screen',
    'levelup-screen', 'gameover-screen'];
  function showScreen(id) {
    for (const s of screens) el(s).classList.toggle('hidden', s !== id);
    el('hud').classList.toggle('hidden', id !== null);
  }

  // ── Run state ─────────────────────────────────────────────────────────────
  let state = 'title';
  let rng, player, enemies, projectiles, gems, particles, effects, orbitals;
  let elapsed, spawnTimer, lastTime, runGold, runKills, seedStr;
  let selectedClass = 'knight', selectedWeapon = 'arming_sword';
  const input = { dx: 0, dy: 0 };
  const keys = {};

  function fmtTime(s) {
    const m = Math.floor(s / 60), sec = Math.floor(s % 60);
    return `${m}:${sec.toString().padStart(2, '0')}`;
  }

  const DEFAULTS = {
    r: 14, hp: 100, maxHp: 100, regen: 0, speed: 190, damage: 10,
    projectileCount: 1, projectileSpeed: 420, projectileSize: 6, pierce: 0,
    crit: 0, critMult: 2, lifesteal: 0, pickupRange: 75,
    aoeMult: 1, thorns: 0, burnOnHit: 0, slowOnHit: false, holyAura: 0,
    level: 1, xp: 0, xpNext: 5, invuln: 0,
  };

  function createPlayer(classId, weaponId) {
    const cls = CLASS_BY_ID[classId];
    const p = Object.assign({}, DEFAULTS, cls.baseStats);
    p.x = 0; p.y = 0;
    p.classId = classId; p.weaponId = weaponId;
    p.abilities = {};
    p.orbital = null;
    p.attackTimer = 0;
    const w = WEAPON_BY_ID[weaponId];
    p.attackCooldown = w.cooldown || 0.6;
    p.hp = p.maxHp;
    if (w.init) w.init(p);
    return p;
  }

  // ── Weapon ctx API ────────────────────────────────────────────────────────
  function nearestEnemy(x, y) {
    let best = null, bd = Infinity;
    for (const e of enemies) {
      const d = (e.x - x) ** 2 + (e.y - y) ** 2;
      if (d < bd) { bd = d; best = e; }
    }
    return best;
  }
  function applyEnemyEffects(e) {
    if (player.burnOnHit) e.burn = { dps: player.burnOnHit, until: elapsed + 3 };
    if (player.slowOnHit) e.slowUntil = elapsed + 1.5;
  }
  function makeCtx() {
    return {
      player, rng,
      nearest: () => nearestEnemy(player.x, player.y),
      dirToNearest() {
        const t = nearestEnemy(player.x, player.y);
        return t ? Math.atan2(t.y - player.y, t.x - player.x) : rng.float() * Math.PI * 2;
      },
      spawnProjectile(o) {
        projectiles.push(Object.assign({
          x: player.x, y: player.y, vx: 0, vy: 0, r: 6, dmg: player.damage,
          pierce: player.pierce, life: 1.5, color: '#ffe27a', crit: false, onHit: null, spin: false, rot: 0,
        }, o));
      },
      areaDamage(x, y, radius, mult, opts = {}) {
        const dmg = player.damage * mult;
        for (const e of enemies) {
          if (e.hp <= 0) continue;
          const dx = e.x - x, dy = e.y - y;
          if (dx * dx + dy * dy <= (radius + e.r) ** 2) {
            damageEnemy(e, dmg, opts.crit, x, y);
            applyEnemyEffects(e);
            if (opts.slow) e.slowUntil = elapsed + opts.slow;
            if (opts.knockback) {
              const d = Math.hypot(dx, dy) || 1;
              e.x += (dx / d) * opts.knockback * 0.06;
              e.y += (dy / d) * opts.knockback * 0.06;
            }
          }
        }
      },
      addEffect(e) { effects.push(e); },
    };
  }

  function damageEnemy(e, dmg, crit, fromX, fromY) {
    e.hp -= dmg;
    e.hitFlash = 0.1;
    particles.push(...burst(e.x, e.y, '#ffffff', 3));
    if (crit) particles.push(...burst(e.x, e.y, '#ffd34d', 4));
    if (rng.float() < player.lifesteal) player.hp = Math.min(player.maxHp, player.hp + 2);
    if (e.hp <= 0) killEnemy(e);
  }

  function killEnemy(e) {
    e.dead = true;
    runKills++;
    particles.push(...burst(e.x, e.y, e.color, 12));
    gems.push({ x: e.x, y: e.y, xp: e.xp, gold: e.gold, r: 5 });
  }

  function burst(x, y, color, count) {
    const out = [];
    for (let i = 0; i < count; i++) {
      const a = rng.float() * Math.PI * 2, s = 40 + rng.float() * 130;
      out.push({ x, y, vx: Math.cos(a) * s, vy: Math.sin(a) * s, life: 0.4, color });
    }
    return out;
  }

  // ── Start a run ───────────────────────────────────────────────────────────
  function startRun(seed) {
    seedStr = seed;
    rng = new RNG(seed);
    player = createPlayer(selectedClass, selectedWeapon);
    enemies = []; projectiles = []; gems = []; particles = []; effects = []; orbitals = [];
    elapsed = 0; spawnTimer = 0; runGold = 0; runKills = 0;
    state = 'playing';
    showScreen(null);
    el('seed-label').textContent = `seed: ${seed}`;
    syncOrbitals();
    lastTime = performance.now();
    requestAnimationFrame(loop);
  }

  // Keep the orbital ring matching player.orbital.count (abilities can grow it).
  function syncOrbitals() {
    if (!player.orbital) { orbitals = []; return; }
    const n = player.orbital.count;
    while (orbitals.length < n) orbitals.push({ angle: (Math.PI * 2 * orbitals.length) / n, hits: {} });
    while (orbitals.length > n) orbitals.pop();
  }

  // ── Enemies ───────────────────────────────────────────────────────────────
  function spawnEnemy() {
    const ang = rng.float() * Math.PI * 2;
    const dist = Math.max(W, H) * 0.6 + 40;
    const minutes = elapsed / 60;
    const tier = rng.weighted([
      { value: 'skeleton', weight: 10 },
      { value: 'goblin', weight: 3 + minutes },
      { value: 'ogre', weight: minutes },
    ]);
    const base = {
      skeleton: { r: 12, hp: 18, speed: 70, dmg: 8, color: '#d6d3c4', gold: 1, xp: 1 },
      goblin: { r: 10, hp: 12, speed: 132, dmg: 6, color: '#7bbf63', gold: 1, xp: 1 },
      ogre: { r: 20, hp: 70, speed: 48, dmg: 16, color: '#9b59b6', gold: 3, xp: 3 },
    }[tier];
    const scale = 1 + minutes * 0.35;
    enemies.push({
      x: player.x + Math.cos(ang) * dist, y: player.y + Math.sin(ang) * dist,
      r: base.r, hp: base.hp * scale, maxHp: base.hp * scale, speed: base.speed,
      dmg: base.dmg, color: base.color, gold: base.gold, xp: base.xp,
      hitFlash: 0, slowUntil: 0, burn: null,
    });
  }

  // ── Leveling & abilities ──────────────────────────────────────────────────
  function gainXp(amount) {
    player.xp += amount;
    while (player.xp >= player.xpNext) {
      player.xp -= player.xpNext;
      player.level++;
      player.xpNext = Math.floor(player.xpNext * 1.35 + 3);
      openLevelUp();
    }
  }

  function openLevelUp() {
    state = 'levelup';
    const choices = rollAbilities(rng, player.classId, player.abilities, 5);
    const wrap = el('upgrade-cards');
    wrap.innerHTML = '';
    if (choices.length === 0) {
      // Fully maxed — grant a small heal instead of stalling.
      player.hp = Math.min(player.maxHp, player.hp + 30);
      state = 'playing'; lastTime = performance.now(); requestAnimationFrame(loop); return;
    }
    for (const ab of choices) {
      const rank = player.abilities[ab.id] || 0;
      const card = document.createElement('button');
      card.className = 'card';
      card.innerHTML = `<h3>${ab.name}</h3><p>${ab.desc}</p>` +
        `<span class="rank">${rank > 0 ? `Rank ${rank} → ${rank + 1}` : 'New'} · max ${ab.maxLevel}</span>`;
      card.onclick = () => {
        ab.apply(player);
        player.abilities[ab.id] = rank + 1;
        syncOrbitals();
        checkRunAchievements();
        el('levelup-screen').classList.add('hidden');
        state = 'playing'; lastTime = performance.now(); requestAnimationFrame(loop);
      };
      wrap.appendChild(card);
    }
    el('levelup-title').textContent = `Level ${player.level}`;
    el('levelup-screen').classList.remove('hidden');
  }

  // ── Achievements ──────────────────────────────────────────────────────────
  function runStats() {
    return {
      time: elapsed, level: player.level,
      totalKills: meta.totalKills + runKills,
      classKills: Object.assign({}, meta.classKills,
        { [player.classId]: (meta.classKills[player.classId] || 0) + runKills }),
    };
  }
  let pendingUnlocks = [];
  function applyUnlock(id) {
    // Map achievements to the thing they unlock.
    if (id === 'survive_8') meta.unlockedClasses.cleric = true;
    if (id === 'level_15') meta.unlockedClasses.barbarian = true;
    if (id === 'survive_12') meta.unlockedWeapons.frost_nova = true;
    if (id === 'archer_kills_500') meta.unlockedWeapons.crossbow = true;
    if (id === 'kills_1000') meta.gold += 500;
  }
  function checkRunAchievements() {
    const fresh = checkAchievements(runStats(), meta.achievements);
    for (const id of fresh) {
      meta.achievements[id] = true;
      applyUnlock(id);
      pendingUnlocks.push(ACHIEVEMENT_BY_ID[id]);
    }
    if (fresh.length) saveMeta();
  }

  function die() {
    state = 'dead';
    meta.gold += runGold;
    meta.totalKills += runKills;
    meta.classKills[player.classId] = (meta.classKills[player.classId] || 0) + runKills;
    if (elapsed > meta.bestTime) meta.bestTime = elapsed;
    checkRunAchievements();
    saveMeta();
    el('over-time').textContent = fmtTime(elapsed);
    el('over-gold').textContent = `+${runGold} gold · ${runKills} slain`;
    const ul = el('over-unlocks');
    ul.innerHTML = pendingUnlocks.length
      ? '<b>Unlocked!</b><br>' + pendingUnlocks.map((a) => `${a.name} — ${a.unlocks}`).join('<br>')
      : '';
    pendingUnlocks = [];
    showScreen('gameover-screen');
  }

  // ── Update ────────────────────────────────────────────────────────────────
  function update(dt) {
    elapsed += dt;

    // Movement
    let mx = input.dx, my = input.dy;
    const mag = Math.hypot(mx, my);
    if (mag > 0.1) { mx /= mag; my /= mag; } else { mx = my = 0; }
    player.x += mx * player.speed * dt;
    player.y += my * player.speed * dt;

    if (player.regen) player.hp = Math.min(player.maxHp, player.hp + player.regen * dt);
    if (player.invuln > 0) player.invuln -= dt;

    // Cleric holy aura
    if (player.holyAura) {
      for (const e of enemies) {
        if ((e.x - player.x) ** 2 + (e.y - player.y) ** 2 < 95 ** 2) {
          damageEnemy(e, player.holyAura * dt, false);
        }
      }
    }

    // Weapon fire (projectile / melee / nova)
    const w = WEAPON_BY_ID[player.weaponId];
    if (w.fire && w.type !== 'orbital') {
      player.attackTimer -= dt;
      if (player.attackTimer <= 0) { w.fire(makeCtx()); player.attackTimer = player.attackCooldown; }
    }

    // Spawning ramps up over time
    spawnTimer -= dt;
    const interval = Math.max(0.16, 1.1 - elapsed * 0.01);
    if (spawnTimer <= 0) { spawnEnemy(); spawnTimer = interval; }

    // Projectiles
    for (const p of projectiles) {
      p.x += p.vx * dt; p.y += p.vy * dt; p.life -= dt;
      if (p.spin) p.rot += dt * 14;
    }

    // Orbitals (whirlwind axe / censer)
    if (player.orbital && orbitals.length) {
      const o = player.orbital;
      for (let i = 0; i < orbitals.length; i++) {
        const orb = orbitals[i];
        orb.angle += o.speed * dt;
        orb.x = player.x + Math.cos(orb.angle + (i * Math.PI * 2) / orbitals.length) * o.dist;
        orb.y = player.y + Math.sin(orb.angle + (i * Math.PI * 2) / orbitals.length) * o.dist;
        for (const e of enemies) {
          if (e.hp <= 0) continue;
          if ((e.x - orb.x) ** 2 + (e.y - orb.y) ** 2 < (o.r + e.r) ** 2) {
            const last = orb.hits[e._id] || -1;
            if (elapsed - last > 0.35) { // hit cooldown per enemy
              orb.hits[e._id ||= Math.random()] = elapsed;
              const cr = rng.float() < player.crit;
              damageEnemy(e, player.damage * o.mult * (cr ? player.critMult : 1), cr);
              applyEnemyEffects(e);
            }
          }
        }
      }
    }

    // Enemies chase + contact damage + status effects
    for (const e of enemies) {
      if (e.hp <= 0) continue;
      const slowed = e.slowUntil > elapsed ? 0.5 : 1;
      const a = Math.atan2(player.y - e.y, player.x - e.x);
      e.x += Math.cos(a) * e.speed * slowed * dt;
      e.y += Math.sin(a) * e.speed * slowed * dt;
      if (e.hitFlash > 0) e.hitFlash -= dt;
      if (e.burn && e.burn.until > elapsed) {
        e.hp -= e.burn.dps * dt;
        if (e.hp <= 0) { killEnemy(e); continue; }
      }
      const rr = (e.r + player.r) ** 2;
      if ((e.x - player.x) ** 2 + (e.y - player.y) ** 2 < rr && player.invuln <= 0) {
        player.hp -= e.dmg; player.invuln = 0.6;
        if (player.thorns) damageEnemy(e, player.thorns, false);
        particles.push(...burst(player.x, player.y, '#ff5555', 8));
        if (player.hp <= 0) { die(); return; }
      }
    }

    // Projectile ↔ enemy
    for (const p of projectiles) {
      if (p.life <= 0) continue;
      for (const e of enemies) {
        if (e.hp <= 0) continue;
        if ((e.x - p.x) ** 2 + (e.y - p.y) ** 2 < (e.r + p.r) ** 2) {
          damageEnemy(e, p.dmg, p.crit);
          applyEnemyEffects(e);
          if (p.onHit) p.onHit(p.x, p.y, makeCtx());
          if (p.pierce > 0) p.pierce--; else p.life = 0;
          if (p.life <= 0) break;
        }
      }
    }

    // Gems magnetize then collect
    for (const g of gems) {
      const d2 = (g.x - player.x) ** 2 + (g.y - player.y) ** 2;
      if (d2 < player.pickupRange ** 2) {
        const a = Math.atan2(player.y - g.y, player.x - g.x);
        g.x += Math.cos(a) * 340 * dt; g.y += Math.sin(a) * 340 * dt;
      }
      if (d2 < (player.r + 7) ** 2) { g.collected = true; runGold += g.gold; gainXp(g.xp); }
    }

    for (const pt of particles) { pt.x += pt.vx * dt; pt.y += pt.vy * dt; pt.life -= dt; }
    for (const ef of effects) ef.life -= dt;

    projectiles = projectiles.filter((p) => p.life > 0);
    enemies = enemies.filter((e) => e.hp > 0 && !e.dead);
    gems = gems.filter((g) => !g.collected);
    particles = particles.filter((p) => p.life > 0);
    effects = effects.filter((e) => e.life > 0);

    // HUD
    el('level-text').textContent = `Lv ${player.level}`;
    el('timer').textContent = fmtTime(elapsed);
    el('hp-bar').style.width = `${Math.max(0, (player.hp / player.maxHp) * 100)}%`;
    el('xp-bar').style.width = `${(player.xp / player.xpNext) * 100}%`;
  }

  // ── Render ────────────────────────────────────────────────────────────────
  function render() {
    ctx.fillStyle = '#15130f';
    ctx.fillRect(0, 0, W, H);
    const camX = player.x - W / 2, camY = player.y - H / 2;
    ctx.save();
    ctx.translate(-camX, -camY);

    // Floor grid
    ctx.strokeStyle = 'rgba(255,225,170,0.05)';
    ctx.lineWidth = 1;
    const grid = 60;
    const sx = Math.floor(camX / grid) * grid, sy = Math.floor(camY / grid) * grid;
    ctx.beginPath();
    for (let x = sx; x < camX + W + grid; x += grid) { ctx.moveTo(x, camY); ctx.lineTo(x, camY + H); }
    for (let y = sy; y < camY + H + grid; y += grid) { ctx.moveTo(camX, y); ctx.lineTo(camX + W, y); }
    ctx.stroke();

    // Gems
    ctx.fillStyle = '#4ad6e8';
    for (const g of gems) { ctx.beginPath(); ctx.arc(g.x, g.y, g.r, 0, Math.PI * 2); ctx.fill(); }

    // Effects (rings + melee swings)
    for (const ef of effects) {
      ctx.globalAlpha = Math.max(0, ef.life / (ef.maxLife || 0.3));
      if (ef.type === 'ring') {
        const t = 1 - ef.life / 0.3;
        ctx.strokeStyle = ef.color; ctx.lineWidth = 3;
        ctx.beginPath(); ctx.arc(ef.x, ef.y, ef.r + (ef.maxR - ef.r) * t, 0, Math.PI * 2); ctx.stroke();
      } else if (ef.type === 'swing') {
        ctx.strokeStyle = ef.color; ctx.lineWidth = 5;
        ctx.beginPath(); ctx.arc(ef.x, ef.y, ef.range, ef.angle - 0.9, ef.angle + 0.9); ctx.stroke();
      }
    }
    ctx.globalAlpha = 1;

    // Particles
    for (const pt of particles) {
      ctx.globalAlpha = Math.max(0, pt.life / 0.4);
      ctx.fillStyle = pt.color; ctx.fillRect(pt.x - 2, pt.y - 2, 4, 4);
    }
    ctx.globalAlpha = 1;

    // Enemies
    for (const e of enemies) {
      ctx.fillStyle = e.hitFlash > 0 ? '#fff' : (e.slowUntil > elapsed ? '#9fd8ff' : e.color);
      ctx.beginPath(); ctx.arc(e.x, e.y, e.r, 0, Math.PI * 2); ctx.fill();
    }

    // Projectiles
    for (const p of projectiles) {
      ctx.fillStyle = p.color;
      ctx.beginPath(); ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2); ctx.fill();
    }

    // Orbitals
    if (player.orbital) {
      ctx.fillStyle = player.orbital.color;
      for (const orb of orbitals) {
        if (orb.x == null) continue;
        ctx.beginPath(); ctx.arc(orb.x, orb.y, player.orbital.r, 0, Math.PI * 2); ctx.fill();
      }
    }

    // Cleric aura
    if (player.holyAura) {
      ctx.strokeStyle = 'rgba(255,243,196,0.25)'; ctx.lineWidth = 2;
      ctx.beginPath(); ctx.arc(player.x, player.y, 95, 0, Math.PI * 2); ctx.stroke();
    }

    // Player
    if (!(player.invuln > 0 && Math.floor(elapsed * 20) % 2)) {
      ctx.fillStyle = CLASS_BY_ID[player.classId].color;
      ctx.beginPath(); ctx.arc(player.x, player.y, player.r, 0, Math.PI * 2); ctx.fill();
      ctx.strokeStyle = 'rgba(0,0,0,0.4)'; ctx.lineWidth = 2; ctx.stroke();
    }
    ctx.restore();
  }

  // ── Loop ──────────────────────────────────────────────────────────────────
  function loop(now) {
    if (state !== 'playing') return;
    const dt = Math.min(0.05, (now - lastTime) / 1000);
    lastTime = now;
    update(dt);
    if (state === 'playing') { render(); requestAnimationFrame(loop); }
    else if (state === 'levelup') render();
  }

  // ── Input ─────────────────────────────────────────────────────────────────
  let touchOrigin = null;
  function dirFromTouch(t) {
    if (!touchOrigin) return;
    const dx = t.clientX - touchOrigin.x, dy = t.clientY - touchOrigin.y, max = 60;
    input.dx = Math.max(-1, Math.min(1, dx / max));
    input.dy = Math.max(-1, Math.min(1, dy / max));
  }
  canvas.addEventListener('touchstart', (e) => {
    e.preventDefault(); const t = e.changedTouches[0];
    touchOrigin = { x: t.clientX, y: t.clientY }; dirFromTouch(t);
  }, { passive: false });
  canvas.addEventListener('touchmove', (e) => { e.preventDefault(); dirFromTouch(e.changedTouches[0]); }, { passive: false });
  canvas.addEventListener('touchend', (e) => { e.preventDefault(); touchOrigin = null; input.dx = input.dy = 0; }, { passive: false });

  window.addEventListener('keydown', (e) => { keys[e.key.toLowerCase()] = true; });
  window.addEventListener('keyup', (e) => { keys[e.key.toLowerCase()] = false; });
  function pollKeys() {
    if (state === 'playing') {
      input.dx = (keys['d'] || keys['arrowright'] ? 1 : 0) - (keys['a'] || keys['arrowleft'] ? 1 : 0);
      input.dy = (keys['s'] || keys['arrowdown'] ? 1 : 0) - (keys['w'] || keys['arrowup'] ? 1 : 0);
    }
    requestAnimationFrame(pollKeys);
  }
  pollKeys();

  // ── Screens: title / class select / shop / achievements ───────────────────
  function refreshTitle() {
    el('best-time').textContent = fmtTime(meta.bestTime);
    el('total-gold').textContent = meta.gold;
  }

  function buildClassSelect() {
    const grid = el('class-grid');
    grid.innerHTML = '';
    for (const c of CLASSES) {
      const unlocked = classUnlocked(c);
      const div = document.createElement('button');
      div.className = 'class-card' + (unlocked ? '' : ' locked') + (selectedClass === c.id ? ' selected' : '');
      div.style.setProperty('--accent', c.color);
      div.innerHTML = `<h3>${c.name}</h3><p>${unlocked ? c.blurb : lockText(c.unlock)}</p>`;
      if (unlocked) div.onclick = () => { selectedClass = c.id; selectedWeapon = c.starterWeapon; buildClassSelect(); };
      grid.appendChild(div);
    }
    // Weapon toggle for the selected class
    const cls = CLASS_BY_ID[selectedClass];
    const wr = el('weapon-row');
    wr.innerHTML = '<span class="label">Weapon:</span>';
    for (const wid of cls.weapons) {
      const w = WEAPON_BY_ID[wid];
      const unlocked = weaponUnlocked(w);
      const b = document.createElement('button');
      b.className = 'weapon-chip' + (selectedWeapon === wid ? ' selected' : '') + (unlocked ? '' : ' locked');
      b.textContent = unlocked ? w.name : `🔒 ${w.name}`;
      if (unlocked) b.onclick = () => { selectedWeapon = wid; buildClassSelect(); };
      wr.appendChild(b);
    }
    el('class-detail').textContent = WEAPON_BY_ID[selectedWeapon].desc;
  }

  function lockText(unlock) {
    if (unlock.type === 'gold') return `🔒 Buy for ${unlock.cost} gold`;
    if (unlock.type === 'achievement') return `🔒 ${ACHIEVEMENT_BY_ID[unlock.achievement].name}`;
    return 'Locked';
  }

  function buildShop() {
    el('shop-gold').textContent = `Gold: ${meta.gold}`;
    const list = el('shop-list');
    list.innerHTML = '';
    const items = [];
    for (const c of CLASSES) if (c.unlock.type === 'gold' && !classUnlocked(c))
      items.push({ name: `${c.name} (class)`, cost: c.unlock.cost, buy: () => { meta.unlockedClasses[c.id] = true; } });
    for (const w of WEAPONS) if (w.unlock.type === 'gold' && !weaponUnlocked(w))
      items.push({ name: `${w.name} (${CLASS_BY_ID[w.classId].name})`, cost: w.unlock.cost, buy: () => { meta.unlockedWeapons[w.id] = true; } });
    if (items.length === 0) { list.innerHTML = '<p class="muted">Everything purchasable is unlocked. Earn the rest via achievements.</p>'; return; }
    for (const it of items) {
      const row = document.createElement('div');
      row.className = 'shop-row';
      const can = meta.gold >= it.cost;
      row.innerHTML = `<span>${it.name}</span>`;
      const b = document.createElement('button');
      b.className = 'btn small' + (can ? ' primary' : '');
      b.textContent = `${it.cost} g`;
      b.disabled = !can;
      b.onclick = () => { if (meta.gold >= it.cost) { meta.gold -= it.cost; it.buy(); saveMeta(); buildShop(); refreshTitle(); } };
      row.appendChild(b);
      list.appendChild(row);
    }
  }

  function buildAchievements() {
    const list = el('ach-list');
    list.innerHTML = '';
    for (const a of ACHIEVEMENTS) {
      const done = !!meta.achievements[a.id];
      const row = document.createElement('div');
      row.className = 'ach-row' + (done ? ' done' : '');
      row.innerHTML = `<div><b>${done ? '✓ ' : ''}${a.name}</b><br><span class="muted">${a.desc}</span></div>` +
        `<span class="unlocks">${a.unlocks}</span>`;
      list.appendChild(row);
    }
  }

  // ── Wire buttons ──────────────────────────────────────────────────────────
  el('start-btn').onclick = () => { buildClassSelect(); showScreen('class-screen'); };
  el('daily-btn').onclick = () => { buildClassSelect(); showScreen('class-screen'); el('begin-btn').dataset.daily = '1'; };
  el('shop-btn').onclick = () => { buildShop(); showScreen('shop-screen'); };
  el('ach-btn').onclick = () => { buildAchievements(); showScreen('ach-screen'); };
  el('shop-back-btn').onclick = () => { refreshTitle(); showScreen('title-screen'); };
  el('ach-back-btn').onclick = () => showScreen('title-screen');
  el('class-back-btn').onclick = () => { el('begin-btn').dataset.daily = ''; showScreen('title-screen'); };
  el('begin-btn').onclick = () => {
    const daily = el('begin-btn').dataset.daily === '1';
    el('begin-btn').dataset.daily = '';
    startRun(daily ? dailySeed() : `run-${Date.now()}`);
  };
  el('restart-btn').onclick = () => { refreshTitle(); showScreen('title-screen'); };

  refreshTitle();
  showScreen('title-screen');
})();
