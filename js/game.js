// ── Ironvow ────────────────────────────────────────────────────────────────
// Medieval survivor-like roguelite. This file wires together input (joystick +
// ability buttons), the class weapon + active abilities, hordes, meta-progression,
// and the look-&-feel layer: procedural sprites, torch lighting, juice, and audio.

(function () {
  const canvas = document.getElementById('game');
  const ctx = canvas.getContext('2d');
  const TAU = Math.PI * 2;
  const SFX = window.GameAudio;

  let W = 0, H = 0, DPR = 1;
  function resize() {
    DPR = Math.min(window.devicePixelRatio || 1, 2);
    W = window.innerWidth; H = window.innerHeight;
    canvas.width = Math.floor(W * DPR); canvas.height = Math.floor(H * DPR);
    canvas.style.width = W + 'px'; canvas.style.height = H + 'px';
    ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
    ctx.imageSmoothingEnabled = false; // crisp pixel-art scaling
  }
  window.addEventListener('resize', resize);
  resize();

  // ── Meta-progression ──────────────────────────────────────────────────────
  const META_KEY = 'ironvow-meta-v1';
  function loadMeta() {
    let m = {};
    try { m = JSON.parse(localStorage.getItem(META_KEY)) || {}; } catch {}
    m.gold = m.gold || 0; m.bestTime = m.bestTime || 0;
    m.unlockedClasses = m.unlockedClasses || { knight: true };
    m.unlockedWeapons = m.unlockedWeapons || {};
    m.achievements = m.achievements || {};
    m.totalKills = m.totalKills || 0; m.classKills = m.classKills || {};
    m.volume = m.volume == null ? 0.7 : m.volume;
    m.muted = !!m.muted;
    m.upgrades = Object.assign({ vigor: 0, might: 0, haste: 0, fortune: 0, revive: 0 }, m.upgrades || {});
    for (const w of WEAPONS) if (w.unlock.type === 'default') m.unlockedWeapons[w.id] = true;
    for (const c of CLASSES) if (c.unlock.type === 'default') m.unlockedClasses[c.id] = true;
    return m;
  }
  function saveMeta() { try { localStorage.setItem(META_KEY, JSON.stringify(meta)); } catch {} }
  let meta = loadMeta();
  const classUnlocked = (c) => !!meta.unlockedClasses[c.id];
  const weaponUnlocked = (w) => !!meta.unlockedWeapons[w.id];

  // ── DOM ───────────────────────────────────────────────────────────────────
  const el = (id) => document.getElementById(id);
  const screens = ['title-screen', 'class-screen', 'shop-screen', 'ach-screen', 'levelup-screen', 'gameover-screen', 'pause-screen', 'settings-screen', 'victory-screen'];
  function showScreen(id) {
    for (const s of screens) el(s).classList.toggle('hidden', s !== id);
    const playing = id === null;
    el('hud').classList.toggle('hidden', !playing);
    el('ability-buttons').classList.toggle('hidden', !playing);
    el('pause-btn').classList.toggle('hidden', !playing);
    if (!playing) el('boss-bar-wrap').classList.add('hidden');
  }

  // ── Run state ─────────────────────────────────────────────────────────────
  let state = 'title';
  let rng, player, enemies, projectiles, enemyProjectiles, gems, particles, effects, floaters;
  let elapsed, spawnTimer, lastTime, runGold, runKills, enemyId;
  let shake = 0, flash = 0, lastBeat = 0, torchFlicker = 0;
  let bossEnemy = null, nextMini = 0, finalSpawned = false, bannerText = '', bannerTimer = 0;
  // Localhost-only fast timeline for testing (inert in production / on Pages).
  const DEV_FAST = (location.hostname === 'localhost' || location.hostname === '127.0.0.1') && new URLSearchParams(location.search).has('fast');
  const WIN_TIME = DEV_FAST ? 12 : 600, MINI_TIMES = DEV_FAST ? [3, 6, 9] : [180, 360, 540];
  let selectedClass = 'knight', selectedWeapon = 'arming_sword';
  const input = { dx: 0, dy: 0 };
  const keys = {};

  const fmtTime = (s) => `${Math.floor(s / 60)}:${Math.floor(s % 60).toString().padStart(2, '0')}`;

  const DEFAULTS = {
    r: 14, hp: 100, maxHp: 100, regen: 0, speed: 190, damage: 10,
    projectileCount: 1, projectileSpeed: 420, projectileSize: 6, pierce: 0,
    crit: 0, critMult: 2, lifesteal: 0, pickupRange: 75,
    aoeMult: 1, thorns: 0, burnOnHit: 0, slowOnHit: false, holyAura: 0,
    level: 1, xp: 0, xpNext: 5, invuln: 0, facing: 0,
  };

  // Permanent meta-upgrade tracks (bought with gold in the Armory).
  const UPGRADE_TRACKS = [
    { id: 'vigor', name: 'Vigor', desc: (l) => `+${l * 20} max HP`, max: 8, cost: (l) => Math.round(40 * Math.pow(1.6, l)) },
    { id: 'might', name: 'Might', desc: (l) => `+${l * 8}% damage`, max: 8, cost: (l) => Math.round(50 * Math.pow(1.6, l)) },
    { id: 'haste', name: 'Haste', desc: (l) => `+${l * 5}% move speed`, max: 6, cost: (l) => Math.round(50 * Math.pow(1.6, l)) },
    { id: 'fortune', name: 'Fortune', desc: (l) => `+${l * 10}% gold, +${l * 8}% XP`, max: 6, cost: (l) => Math.round(60 * Math.pow(1.6, l)) },
    { id: 'revive', name: 'Revive', desc: (l) => `${l} second chance${l === 1 ? '' : 's'} per run`, max: 2, cost: (l) => [300, 800][l] || 9999 },
  ];

  function createPlayer(classId, weaponId) {
    const cls = CLASS_BY_ID[classId];
    const p = Object.assign({}, DEFAULTS, cls.baseStats);
    p.x = 0; p.y = 0; p.classId = classId; p.weaponId = weaponId;
    p.skills = []; p.orbitGroups = []; p.dash = null; p.attackTimer = 0;
    // Apply permanent upgrades.
    const u = meta.upgrades;
    p.maxHp += u.vigor * 20;
    p.damage *= 1 + u.might * 0.08;
    p.speed *= 1 + u.haste * 0.05;
    p.fortuneGold = 1 + u.fortune * 0.10;
    p.fortuneXp = 1 + u.fortune * 0.08;
    p.revives = u.revive;
    const w = WEAPON_BY_ID[weaponId];
    p.attackCooldown = w.cooldown || 0.6; p.hp = p.maxHp;
    if (w.init) w.init(p);
    return p;
  }

  function nearestEnemy(x, y) {
    let best = null, bd = Infinity;
    for (const e of enemies) { const d = (e.x - x) ** 2 + (e.y - y) ** 2; if (d < bd) { bd = d; best = e; } }
    return best;
  }
  function moveDir() { let x = input.dx, y = input.dy; const m = Math.hypot(x, y); return m > 0.1 ? { x: x / m, y: y / m } : { x: 0, y: 0 }; }
  function applyEnemyEffects(e) {
    if (player.burnOnHit) e.burn = { dps: player.burnOnHit, until: elapsed + 3 };
    if (player.slowOnHit) e.slowUntil = elapsed + 1.5;
  }
  function addShake(n) { shake = Math.min(16, shake + n); }

  function makeCtx() {
    return {
      player, rng, enemies, elapsed, moveDir: moveDir(),
      nearest: () => nearestEnemy(player.x, player.y),
      dirToNearest() { const t = nearestEnemy(player.x, player.y); return t ? Math.atan2(t.y - player.y, t.x - player.x) : rng.float() * TAU; },
      spawnProjectile(o) {
        projectiles.push(Object.assign({ x: player.x, y: player.y, vx: 0, vy: 0, r: 6, dmg: player.damage, pierce: player.pierce, life: 1.5, color: '#ffe27a', crit: false, onHit: null, shape: 'orb' }, o));
      },
      areaDamage(x, y, radius, mult, opts = {}) {
        const dmg = player.damage * mult;
        for (const e of enemies) {
          if (e.hp <= 0) continue;
          const dx = e.x - x, dy = e.y - y;
          if (dx * dx + dy * dy <= (radius + e.r) ** 2) {
            damageEnemy(e, dmg, opts.crit); applyEnemyEffects(e);
            if (opts.slow) e.slowUntil = elapsed + opts.slow;
            if (opts.knockback) { const d = Math.hypot(dx, dy) || 1; e.x += (dx / d) * opts.knockback * 0.06; e.y += (dy / d) * opts.knockback * 0.06; }
          }
        }
      },
      damage(e, amt, crit) { if (e && e.hp > 0) damageEnemy(e, amt, crit); },
      addEffect(e) { e.maxLife = e.maxLife || e.life; effects.push(e); },
    };
  }

  function damageEnemy(e, dmg, crit) {
    e.hp -= dmg; e.hitFlash = 0.1;
    particles.push(...burst(e.x, e.y, '#ffffff', 3));
    if (crit) particles.push(...burst(e.x, e.y, '#ffd34d', 4));
    floaters.push({ x: e.x + (rng.float() - 0.5) * 8, y: e.y - e.r, vy: -34, life: 0.7, maxLife: 0.7, text: String(Math.max(1, Math.round(dmg))), crit });
    if (floaters.length > 48) floaters.shift();
    SFX.sfx(crit ? 'crit' : 'hit');
    if (rng.float() < player.lifesteal) player.hp = Math.min(player.maxHp, player.hp + 2);
    if (e.hp <= 0) killEnemy(e);
  }
  function killEnemy(e) {
    if (e.dead) return;
    e.dead = true; runKills++; addShake(e.boss ? 6 : 1.5); SFX.sfx('enemyDie');
    particles.push(...burst(e.x, e.y, e.color, e.boss ? 40 : 12));
    if (window.onEnemyDeath) window.onEnemyDeath(e, makeEnemyCtx());
    if (e === bossEnemy) bossEnemy = null;
    if (e.final) { victory(); return; }
    if (e.boss) { player.hp = Math.min(player.maxHp, player.hp + 25); showBanner('Champion Slain!'); gems.push({ x: e.x, y: e.y, xp: e.xp, gold: e.gold, r: 8 }); }
    else gems.push({ x: e.x, y: e.y, xp: e.xp, gold: e.gold, r: 5 });
  }
  function burst(x, y, color, count) {
    const out = [];
    for (let i = 0; i < count; i++) { const a = rng.float() * TAU, s = 40 + rng.float() * 130; out.push({ x, y, vx: Math.cos(a) * s, vy: Math.sin(a) * s, life: 0.4, color }); }
    return out;
  }

  function startRun(seed) {
    rng = new RNG(seed);
    player = createPlayer(selectedClass, selectedWeapon);
    enemies = []; projectiles = []; enemyProjectiles = []; gems = []; particles = []; effects = []; floaters = [];
    elapsed = 0; spawnTimer = 0; runGold = 0; runKills = 0; enemyId = 0; shake = 0; flash = 0; lastBeat = 0;
    bossEnemy = null; nextMini = 0; finalSpawned = false; bannerText = ''; bannerTimer = 0;
    pendingUnlocks = [];
    state = 'playing'; showScreen(null);
    if (DEV_FAST) window.__player = player; // test-only live-stats seam
    el('seed-label').textContent = `seed: ${seed}`;
    refreshAbilityButtons();
    SFX.ensure(); SFX.startMusic();
    lastTime = performance.now(); requestAnimationFrame(loop);
  }

  const enemyScale = () => 1 + (elapsed / 60) * 0.35;
  const bossScale = () => 1 + (elapsed / 60) * 0.06;

  // Spawn director: archetype mix ramps over the run; occasional elites.
  function spawnEnemy() {
    const ang = rng.float() * TAU, dist = Math.max(W, H) * 0.6 + 40, m = elapsed / 60;
    const key = rng.weighted([
      { value: 'skeleton', weight: 10 },
      { value: 'goblin', weight: 3 + m },
      { value: 'ogre', weight: Math.max(0, m - 0.5) },
      { value: 'shooter', weight: Math.max(0, m - 1) * 1.2 },
      { value: 'exploder', weight: Math.max(0, m - 1.5) * 1.1 },
      { value: 'splitter', weight: Math.max(0, m - 2) },
      { value: 'charger', weight: Math.max(0, m - 2.5) },
    ]);
    const e = makeEnemy(key, player.x + Math.cos(ang) * dist, player.y + Math.sin(ang) * dist, enemyScale());
    if (m > 1 && rng.float() < 0.06) { e.elite = true; e.hp *= 3.2; e.maxHp = e.hp; e.r *= 1.3; e.dmg *= 1.4; e.gold *= 4; e.xp *= 3; }
    e._id = ++enemyId;
    enemies.push(e);
  }

  function spawnBoss(key) {
    const ang = rng.float() * TAU, dist = Math.max(W, H) * 0.55 + 60;
    const e = makeEnemy(key, player.x + Math.cos(ang) * dist, player.y + Math.sin(ang) * dist, bossScale());
    e._id = ++enemyId; enemies.push(e); bossEnemy = e;
    flash = 0.6; addShake(8); SFX.sfx('levelup');
    showBanner(key === 'finalboss' ? 'The Warden Awakens' : 'A Champion Approaches');
  }
  function showBanner(text) { bannerText = text; bannerTimer = 2.6; }

  // Player damage from any source (contact, enemy projectiles, explosions).
  function applyPlayerDamage(amt) {
    if (player.invuln > 0) return;
    player.hp -= amt; player.invuln = 0.6; addShake(7); SFX.sfx('hurt');
    particles.push(...burst(player.x, player.y, '#ff5555', 8));
    if (player.hp <= 0) die();
  }

  // ctx given to enemy AI / death effects.
  function makeEnemyCtx() {
    return {
      player, rng, elapsed,
      hurtPlayer: (amt) => applyPlayerDamage(amt),
      hurtArea: (x, y, r, amt) => { if ((player.x - x) ** 2 + (player.y - y) ** 2 < (r + player.r) ** 2) applyPlayerDamage(amt); },
      spawnEnemyProjectile: (o) => { enemyProjectiles.push(Object.assign({ x: 0, y: 0, vx: 0, vy: 0, r: 6, dmg: 8, color: '#ff7a5a', life: 3 }, o)); },
      addEnemy: (key, x, y) => { const ne = makeEnemy(key, x, y, enemyScale()); ne._id = ++enemyId; enemies.push(ne); },
      addEffect: (e) => { e.maxLife = e.maxLife || e.life; effects.push(e); },
      addShake,
    };
  }

  function ownedRanks() { const m = {}; for (const s of player.skills) m[s.id] = s.rank; return m; }
  function gainXp(amount) {
    player.xp += amount;
    while (player.xp >= player.xpNext) {
      player.xp -= player.xpNext; player.level++;
      player.xpNext = Math.floor(player.xpNext * 1.35 + 3);
      openLevelUp();
    }
  }
  function applyPick(opt) {
    const def = opt.ability;
    let inst = player.skills.find((s) => s.id === def.id);
    if (!inst) { inst = { id: def.id, rank: 0, timer: 0 }; player.skills.push(inst); }
    inst.rank = opt.nextRank;
    if (def.kind === 'orbit') def.sync(player, inst.rank);
    refreshAbilityButtons();
  }
  function openLevelUp() {
    state = 'levelup'; flash = 0.5; SFX.sfx('levelup');
    const choices = rollAbilities(rng, player.classId, ownedRanks(), 5);
    const wrap = el('upgrade-cards'); wrap.innerHTML = '';
    if (choices.length === 0) { player.hp = Math.min(player.maxHp, player.hp + 30); resume(); return; }
    for (const opt of choices) {
      const def = opt.ability;
      const card = document.createElement('button'); card.className = 'card';
      const tag = opt.isNew ? '<span class="new">NEW</span>' : `<span class="rank">Rank ${opt.nextRank - 1} → ${opt.nextRank}</span>`;
      card.innerHTML = `<h3>${def.icon || ''} ${def.name} ${tag}</h3><p>${def.desc(opt.nextRank)}</p><span class="kind">${def.kind === 'movement' ? '✋ tap to use' : def.kind === 'orbit' ? '↻ orbits you' : '⚔ auto'}</span>`;
      card.onclick = () => { SFX.sfx('uiClick'); applyPick(opt); checkRunAchievements(); el('levelup-screen').classList.add('hidden'); resume(); };
      wrap.appendChild(card);
    }
    el('levelup-title').textContent = `Level ${player.level}`;
    el('levelup-screen').classList.remove('hidden');
  }
  function resume() { state = 'playing'; lastTime = performance.now(); requestAnimationFrame(loop); }

  let pendingUnlocks = [];
  function runStats() { return { time: elapsed, level: player.level, totalKills: meta.totalKills + runKills, classKills: Object.assign({}, meta.classKills, { [player.classId]: (meta.classKills[player.classId] || 0) + runKills }) }; }
  function applyUnlock(id) {
    if (id === 'survive_8') meta.unlockedClasses.cleric = true;
    if (id === 'level_15') meta.unlockedClasses.barbarian = true;
    if (id === 'survive_12') meta.unlockedWeapons.frost_nova = true;
    if (id === 'archer_kills_500') meta.unlockedWeapons.crossbow = true;
    if (id === 'kills_1000') meta.gold += 500;
  }
  function checkRunAchievements() {
    const fresh = checkAchievements(runStats(), meta.achievements);
    for (const id of fresh) { meta.achievements[id] = true; applyUnlock(id); pendingUnlocks.push(ACHIEVEMENT_BY_ID[id]); }
    if (fresh.length) saveMeta();
  }

  function revivePlayer() {
    player.revives--;
    player.hp = Math.round(player.maxHp * 0.5);
    player.invuln = 2.5; flash = 0.6; addShake(8); SFX.sfx('levelup');
    showBanner('Second Wind!');
    for (const e of enemies) { // clear out the swarm that just killed you
      const dx = e.x - player.x, dy = e.y - player.y, d = Math.hypot(dx, dy) || 1;
      if (d < 210) { e.x += (dx / d) * 230; e.y += (dy / d) * 230; if (!e.boss) damageEnemy(e, e.maxHp, false); }
    }
  }

  function die() {
    if (player.revives > 0) { revivePlayer(); return; }
    state = 'dead'; SFX.stopMusic();
    meta.gold += Math.floor(runGold); meta.totalKills += runKills;
    meta.classKills[player.classId] = (meta.classKills[player.classId] || 0) + runKills;
    if (elapsed > meta.bestTime) meta.bestTime = elapsed;
    checkRunAchievements(); saveMeta();
    el('over-time').textContent = fmtTime(elapsed);
    el('over-gold').textContent = `+${Math.floor(runGold)} gold · ${runKills} slain`;
    el('over-unlocks').innerHTML = pendingUnlocks.length ? '<b>Unlocked!</b><br>' + pendingUnlocks.map((a) => `${a.name} — ${a.unlocks}`).join('<br>') : '';
    showScreen('gameover-screen');
  }

  function victory() {
    state = 'won'; SFX.stopMusic(); SFX.sfx('levelup');
    meta.gold += Math.floor(runGold); meta.totalKills += runKills;
    meta.classKills[player.classId] = (meta.classKills[player.classId] || 0) + runKills;
    if (elapsed > meta.bestTime) meta.bestTime = elapsed;
    checkRunAchievements(); saveMeta();
    el('win-time').textContent = fmtTime(elapsed);
    el('win-gold').textContent = `+${Math.floor(runGold)} gold · ${runKills} slain`;
    el('win-unlocks').innerHTML = pendingUnlocks.length ? '<b>Unlocked!</b><br>' + pendingUnlocks.map((a) => `${a.name} — ${a.unlocks}`).join('<br>') : '';
    showScreen('victory-screen');
  }

  // ── Update ────────────────────────────────────────────────────────────────
  function update(dt) {
    elapsed += dt;
    const c = makeCtx();
    if (shake > 0) shake = Math.max(0, shake - dt * 36);
    if (flash > 0) flash = Math.max(0, flash - dt * 2);

    // Movement (dash overrides)
    if (player.dash) {
      const d = player.dash;
      player.x += d.vx * dt; player.y += d.vy * dt; d.time -= dt;
      player.facing = Math.atan2(d.vy, d.vx);
      effects.push({ type: 'fade', x: player.x, y: player.y, r: player.r, life: 0.18, maxLife: 0.18, color: d.color });
      if (d.hitMult) for (const e of enemies) { if (e.hp <= 0 || d.hits.has(e._id)) continue; if ((e.x - player.x) ** 2 + (e.y - player.y) ** 2 < (player.r + e.r + 6) ** 2) { d.hits.add(e._id); damageEnemy(e, player.damage * d.hitMult, false); applyEnemyEffects(e); } }
      if (d.time <= 0) player.dash = null;
    } else {
      const md = moveDir();
      player.x += md.x * player.speed * dt; player.y += md.y * player.speed * dt;
    }
    // Facing: aim at nearest foe, else move direction
    const aim = nearestEnemy(player.x, player.y);
    if (aim) player.facing = Math.atan2(aim.y - player.y, aim.x - player.x);
    else { const md = moveDir(); if (md.x || md.y) player.facing = Math.atan2(md.y, md.x); }

    if (player.regen) player.hp = Math.min(player.maxHp, player.hp + player.regen * dt);
    if (player.invuln > 0) player.invuln -= dt;

    // Low-HP heartbeat
    if (player.hp / player.maxHp < 0.3 && elapsed - lastBeat > 0.65) { lastBeat = elapsed; SFX.sfx('heartbeat'); }

    // Class weapon
    const w = WEAPON_BY_ID[player.weaponId];
    if (w.fire && w.type !== 'orbital') {
      player.attackTimer -= dt;
      if (player.attackTimer <= 0) { w.fire(c); SFX.sfx('cast'); player.attackTimer = player.attackCooldown; }
    }

    // Active abilities
    for (const s of player.skills) {
      const def = ABILITIES_BY_ID[s.id];
      if (def.kind === 'attack') { s.timer -= dt; if (s.timer <= 0) { def.activate(c, s.rank); SFX.sfx('cast'); s.timer = def.cooldown(s.rank); } }
      else if (def.kind === 'movement') { if (s.timer > 0) s.timer -= dt; }
    }

    // Spawn director (normal spawns pause during the final boss)
    if (!(bossEnemy && bossEnemy.final)) {
      spawnTimer -= dt;
      const interval = Math.max(0.16, 1.1 - elapsed * 0.01);
      if (spawnTimer <= 0) { spawnEnemy(); spawnTimer = interval; }
    }
    while (nextMini < MINI_TIMES.length && elapsed >= MINI_TIMES[nextMini]) { spawnBoss('miniboss'); nextMini++; }
    if (!finalSpawned && elapsed >= WIN_TIME) { spawnBoss('finalboss'); finalSpawned = true; }
    if (bannerTimer > 0) bannerTimer -= dt;

    for (const p of projectiles) { p.x += p.vx * dt; p.y += p.vy * dt; p.life -= dt; }
    for (const p of enemyProjectiles) {
      p.x += p.vx * dt; p.y += p.vy * dt; p.life -= dt;
      if (p.life > 0 && player.invuln <= 0 && (p.x - player.x) ** 2 + (p.y - player.y) ** 2 < (p.r + player.r) ** 2) { applyPlayerDamage(p.dmg); p.life = 0; if (state !== 'playing') return; }
    }

    // Orbit groups
    for (const g of player.orbitGroups) {
      while (g.orbs.length < g.count) g.orbs.push({ angle: rng.float() * TAU, hits: {} });
      while (g.orbs.length > g.count) g.orbs.pop();
      const n = g.orbs.length;
      for (let i = 0; i < n; i++) {
        const orb = g.orbs[i]; orb.angle += g.speed * dt;
        const a = orb.angle + (i * TAU) / n;
        orb.x = player.x + Math.cos(a) * g.dist; orb.y = player.y + Math.sin(a) * g.dist;
        for (const e of enemies) {
          if (e.hp <= 0) continue;
          if ((e.x - orb.x) ** 2 + (e.y - orb.y) ** 2 < (g.r + e.r) ** 2) {
            const last = orb.hits[e._id] || -1;
            if (elapsed - last > 0.35) { orb.hits[e._id] = elapsed; const cr = rng.float() < player.crit; damageEnemy(e, player.damage * g.mult * (cr ? player.critMult : 1), cr); applyEnemyEffects(e); }
          }
        }
      }
    }

    // Enemies (behavior driven by archetype AI)
    const ectx = makeEnemyCtx();
    for (const e of enemies) {
      if (e.hp <= 0) continue;
      tickEnemyAI(e, ectx, dt);
      if (e.hitFlash > 0) e.hitFlash -= dt;
      if (e.burn && e.burn.until > elapsed) { e.hp -= e.burn.dps * dt; if (e.hp <= 0) { killEnemy(e); continue; } }
      if (e.hp <= 0) { killEnemy(e); continue; } // e.g. exploder self-detonation
      if ((e.x - player.x) ** 2 + (e.y - player.y) ** 2 < (e.r + player.r) ** 2 && player.invuln <= 0) {
        if (player.thorns) damageEnemy(e, player.thorns, false);
        applyPlayerDamage(e.dmg);
        if (state !== 'playing') return;
      }
    }

    // Projectiles ↔ enemies
    for (const p of projectiles) {
      if (p.life <= 0) continue;
      for (const e of enemies) {
        if (e.hp <= 0) continue;
        if ((e.x - p.x) ** 2 + (e.y - p.y) ** 2 < (e.r + p.r) ** 2) {
          damageEnemy(e, p.dmg, p.crit); applyEnemyEffects(e);
          if (p.onHit) p.onHit(p.x, p.y, c);
          if (p.pierce > 0) p.pierce--; else p.life = 0;
          if (p.life <= 0) break;
        }
      }
    }

    // Gems
    for (const g of gems) {
      const d2 = (g.x - player.x) ** 2 + (g.y - player.y) ** 2;
      if (d2 < player.pickupRange ** 2) { const a = Math.atan2(player.y - g.y, player.x - g.x); g.x += Math.cos(a) * 340 * dt; g.y += Math.sin(a) * 340 * dt; }
      if (d2 < (player.r + 7) ** 2) { g.collected = true; runGold += g.gold * player.fortuneGold; SFX.sfx('pickup'); effects.push({ type: 'ring', x: player.x, y: player.y, r: 4, maxR: 22, life: 0.25, maxLife: 0.25, color: '#4ad6e8' }); gainXp(g.xp * player.fortuneXp); }
    }

    for (const pt of particles) { pt.x += pt.vx * dt; pt.y += pt.vy * dt; pt.life -= dt; }
    for (const ef of effects) ef.life -= dt;
    for (const f of floaters) { f.y += f.vy * dt; f.vy += 30 * dt; f.life -= dt; }

    projectiles = projectiles.filter((p) => p.life > 0);
    enemyProjectiles = enemyProjectiles.filter((p) => p.life > 0);
    enemies = enemies.filter((e) => e.hp > 0 && !e.dead);
    gems = gems.filter((g) => !g.collected);
    particles = particles.filter((p) => p.life > 0);
    effects = effects.filter((e) => e.life > 0);
    floaters = floaters.filter((f) => f.life > 0);

    el('level-text').textContent = `Lv ${player.level}`;
    el('timer').textContent = fmtTime(elapsed);
    el('hp-bar').style.width = `${Math.max(0, (player.hp / player.maxHp) * 100)}%`;
    el('xp-bar').style.width = `${(player.xp / player.xpNext) * 100}%`;
    el('revive-pip').textContent = player.revives > 0 ? `♥ ${player.revives}` : '';
    if (bossEnemy && bossEnemy.hp > 0) {
      el('boss-bar-wrap').classList.remove('hidden');
      el('boss-name').textContent = bossEnemy.final ? 'The Warden' : 'Champion';
      el('boss-bar').style.width = `${Math.max(0, (bossEnemy.hp / bossEnemy.maxHp) * 100)}%`;
    } else el('boss-bar-wrap').classList.add('hidden');
    updateAbilityButtons();
  }

  // ── Render ────────────────────────────────────────────────────────────────
  function blit(spr, x, y, angle, scale) {
    ctx.save(); ctx.translate(x, y); if (angle) ctx.rotate(angle); if (scale && scale !== 1) ctx.scale(scale, scale);
    ctx.drawImage(spr.canvas, -spr.cx, -spr.cy); ctx.restore();
  }
  // Pixel-art draw: flip to face, subtle 2-frame idle bob, no rotation.
  function drawSprite(spr, x, y, faceLeft, id) {
    const bob = (Math.floor(elapsed * 5 + (id || 0)) % 2) ? -1.5 : 0;
    ctx.save(); ctx.translate(x, y + bob); if (faceLeft) ctx.scale(-1, 1);
    ctx.drawImage(spr.canvas, -spr.cx, -spr.cy); ctx.restore();
  }
  function render() {
    torchFlicker = Math.sin(elapsed * 9) * 5 + Math.sin(elapsed * 23) * 3;
    const litR = Math.max(245, Math.min(W, H) * 0.6) + torchFlicker;
    const sx = shake ? (Math.random() - 0.5) * shake : 0, sy = shake ? (Math.random() - 0.5) * shake : 0;
    const camX = player.x - W / 2 + sx, camY = player.y - H / 2 + sy;

    ctx.fillStyle = '#15130f'; ctx.fillRect(0, 0, W, H);
    ctx.imageSmoothingEnabled = false;
    ctx.save(); ctx.translate(-camX, -camY);

    // Floor texture
    ctx.fillStyle = Art.floorPatternFor(ctx);
    ctx.fillRect(camX, camY, W, H);

    // Gems
    for (const g of gems) { blit(Art.projSprite('#4ad6e8', g.r, 'orb'), g.x, g.y, 0); }

    // Effects under units
    for (const ef of effects) {
      const al = Math.max(0, ef.life / ef.maxLife); ctx.globalAlpha = al;
      if (ef.type === 'ring') { const t = 1 - al; ctx.strokeStyle = ef.color; ctx.lineWidth = 3; ctx.beginPath(); ctx.arc(ef.x, ef.y, ef.r + (ef.maxR - ef.r) * t, 0, TAU); ctx.stroke(); }
      else if (ef.type === 'line') { ctx.strokeStyle = ef.color; ctx.lineWidth = 3; ctx.beginPath(); ctx.moveTo(ef.x1, ef.y1); ctx.lineTo(ef.x2, ef.y2); ctx.stroke(); }
      else if (ef.type === 'fade') { ctx.fillStyle = ef.color; ctx.globalAlpha = al * 0.4; ctx.beginPath(); ctx.arc(ef.x, ef.y, ef.r, 0, TAU); ctx.fill(); }
    }
    ctx.globalAlpha = 1;

    // Enemies — full sprite if lit, otherwise saved for eye-glow pass
    const darkEnemies = [];
    for (const e of enemies) {
      const d = Math.hypot(e.x - player.x, e.y - player.y);
      if (d > litR * 1.04) { darkEnemies.push(e); continue; }
      drawSprite(Art.enemySprite(e.type), e.x, e.y, player.x < e.x, e._id);
      if (e.hitFlash > 0) { ctx.globalAlpha = e.hitFlash * 6; ctx.fillStyle = '#fff'; ctx.beginPath(); ctx.arc(e.x, e.y, e.r, 0, TAU); ctx.fill(); ctx.globalAlpha = 1; }
      if (e.elite) { ctx.strokeStyle = 'rgba(255,210,90,0.85)'; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(e.x, e.y, e.r + 4, 0, TAU); ctx.stroke(); }
      if (e.telegraph) { ctx.strokeStyle = 'rgba(255,80,60,0.9)'; ctx.lineWidth = 3; ctx.beginPath(); ctx.arc(e.x, e.y, e.r + 6 + Math.sin(elapsed * 30) * 3, 0, TAU); ctx.stroke(); }
    }

    // Projectiles (player + enemy)
    for (const p of projectiles) blit(Art.projSprite(p.color, p.r, p.shape), p.x, p.y, Math.atan2(p.vy, p.vx));
    for (const p of enemyProjectiles) blit(Art.projSprite(p.color, p.r, 'orb'), p.x, p.y, 0);

    // Orbitals
    for (const g of player.orbitGroups) for (const orb of g.orbs) { if (orb.x == null) continue; blit(Art.projSprite(g.color, g.r * 0.8, 'orb'), orb.x, orb.y, 0); }

    // Particles
    for (const pt of particles) { ctx.globalAlpha = Math.max(0, pt.life / 0.4); ctx.fillStyle = pt.color; ctx.fillRect(pt.x - 2, pt.y - 2, 4, 4); }
    ctx.globalAlpha = 1;

    // Damage numbers
    ctx.textAlign = 'center';
    for (const f of floaters) {
      ctx.globalAlpha = Math.min(1, f.life / 0.4);
      ctx.font = `bold ${f.crit ? 20 : 13}px Trebuchet MS, sans-serif`;
      ctx.fillStyle = f.crit ? '#ffd34d' : '#fff';
      ctx.strokeStyle = 'rgba(0,0,0,0.6)'; ctx.lineWidth = 3;
      ctx.strokeText(f.text, f.x, f.y); ctx.fillText(f.text, f.x, f.y);
    }
    ctx.globalAlpha = 1; ctx.textAlign = 'left';

    // Player
    if (!(player.invuln > 0 && Math.floor(elapsed * 20) % 2)) drawSprite(Art.classSprite(player.classId), player.x, player.y, Math.cos(player.facing) < 0, 0);

    ctx.restore();

    // ── Torch lighting overlay (screen space) ─────────────────────────────────
    const cx = W / 2 - sx, cy = H / 2 - sy;
    const grd = ctx.createRadialGradient(cx, cy, 50, cx, cy, litR);
    grd.addColorStop(0, 'rgba(10,8,6,0)'); grd.addColorStop(0.55, 'rgba(10,8,6,0.12)'); grd.addColorStop(0.85, 'rgba(9,7,5,0.62)'); grd.addColorStop(1, 'rgba(7,6,4,0.97)');
    ctx.fillStyle = grd; ctx.fillRect(0, 0, W, H);

    // Glowing eyes for enemies in the dark
    if (darkEnemies.length) {
      ctx.globalCompositeOperation = 'lighter';
      const eye = Art.eyeGlow();
      for (const e of darkEnemies) {
        const ex = e.x - camX, ey = e.y - camY;
        const px = Math.cos(e.facing + Math.PI / 2), py = Math.sin(e.facing + Math.PI / 2);
        const off = e.r * 0.35;
        ctx.drawImage(eye, ex + px * off - 12, ey + py * off - 12);
        ctx.drawImage(eye, ex - px * off - 12, ey - py * off - 12);
      }
      ctx.globalCompositeOperation = 'source-over';
    }

    // Low-HP danger vignette
    const hpFrac = player.hp / player.maxHp;
    if (hpFrac < 0.3) {
      const pulse = 0.35 + Math.sin(elapsed * 7) * 0.15;
      const a = ((0.3 - hpFrac) / 0.3) * pulse;
      const vg = ctx.createRadialGradient(W / 2, H / 2, H * 0.25, W / 2, H / 2, H * 0.62);
      vg.addColorStop(0, 'rgba(170,20,20,0)'); vg.addColorStop(1, `rgba(150,10,10,${a})`);
      ctx.fillStyle = vg; ctx.fillRect(0, 0, W, H);
    }

    // Level-up / pickup flash
    if (flash > 0) { ctx.fillStyle = `rgba(255,250,230,${Math.min(0.5, flash) * 0.5})`; ctx.fillRect(0, 0, W, H); }

    // Boss / event banner
    if (bannerTimer > 0) {
      ctx.globalAlpha = Math.min(1, bannerTimer / 0.5);
      ctx.textAlign = 'center'; ctx.font = 'bold 26px Trebuchet MS, sans-serif';
      ctx.fillStyle = '#f0c869'; ctx.strokeStyle = 'rgba(0,0,0,0.7)'; ctx.lineWidth = 4;
      const by = H * 0.22;
      ctx.strokeText(bannerText, W / 2, by); ctx.fillText(bannerText, W / 2, by);
      ctx.textAlign = 'left'; ctx.globalAlpha = 1;
    }

    // Joystick
    if (joy.active) {
      ctx.globalAlpha = 0.85; ctx.strokeStyle = 'rgba(240,200,105,0.5)'; ctx.lineWidth = 3;
      ctx.beginPath(); ctx.arc(joy.bx, joy.by, 50, 0, TAU); ctx.stroke();
      ctx.fillStyle = 'rgba(240,200,105,0.6)'; ctx.beginPath(); ctx.arc(joy.nx, joy.ny, 24, 0, TAU); ctx.fill();
      ctx.globalAlpha = 1;
    }
  }

  function loop(now) {
    if (state !== 'playing') return;
    const dt = Math.min(0.05, (now - lastTime) / 1000); lastTime = now;
    const steps = DEV_FAST ? (window.__ironSteps | 0) : 0; // test-only fast-forward
    if (steps > 1) { for (let i = 0; i < steps && state === 'playing'; i++) update(0.05); }
    else update(dt);
    if (state === 'playing') { render(); requestAnimationFrame(loop); }
    else if (state === 'levelup' || state === 'paused') render();
  }

  // ── Movement-ability buttons ──────────────────────────────────────────────
  let abilityButtons = [];
  function refreshAbilityButtons() {
    const wrap = el('ability-buttons'); wrap.innerHTML = ''; abilityButtons = [];
    if (!player) return;
    for (const s of player.skills) {
      const def = ABILITIES_BY_ID[s.id];
      if (def.kind !== 'movement') continue;
      const btn = document.createElement('button'); btn.className = 'ability-btn';
      btn.innerHTML = `<span class="ab-cd"></span><span class="ab-icon">${def.icon}</span>`;
      btn.addEventListener('pointerdown', (ev) => { ev.preventDefault(); ev.stopPropagation(); if (state !== 'playing' || s.timer > 0) return; def.activate(makeCtx(), s.rank); SFX.sfx('cast'); s.timer = def.cooldown(s.rank); });
      wrap.appendChild(btn); abilityButtons.push({ btn, skill: s, def });
    }
  }
  function updateAbilityButtons() {
    for (const a of abilityButtons) {
      const cd = a.def.cooldown(a.skill.rank);
      const frac = a.skill.timer > 0 ? a.skill.timer / cd : 0;
      a.btn.style.setProperty('--cd', frac); a.btn.classList.toggle('ready', frac === 0);
    }
  }

  // ── Joystick + keyboard ───────────────────────────────────────────────────
  const joy = { active: false, id: null, bx: 0, by: 0, nx: 0, ny: 0 };
  function setJoy(t) {
    const dx = t.clientX - joy.bx, dy = t.clientY - joy.by, max = 50, d = Math.hypot(dx, dy) || 1, cl = Math.min(d, max);
    joy.nx = joy.bx + (dx / d) * cl; joy.ny = joy.by + (dy / d) * cl; input.dx = dx / max; input.dy = dy / max;
  }
  canvas.addEventListener('touchstart', (e) => { e.preventDefault(); for (const t of e.changedTouches) if (joy.id === null) { joy.id = t.identifier; joy.active = true; joy.bx = t.clientX; joy.by = t.clientY; setJoy(t); } }, { passive: false });
  canvas.addEventListener('touchmove', (e) => { e.preventDefault(); for (const t of e.changedTouches) if (t.identifier === joy.id) setJoy(t); }, { passive: false });
  function endTouch(e) { for (const t of e.changedTouches) if (t.identifier === joy.id) { joy.id = null; joy.active = false; input.dx = input.dy = 0; } }
  canvas.addEventListener('touchend', (e) => { e.preventDefault(); endTouch(e); }, { passive: false });
  canvas.addEventListener('touchcancel', (e) => { e.preventDefault(); endTouch(e); }, { passive: false });
  canvas.addEventListener('mousedown', (e) => { joy.active = true; joy.id = 'mouse'; joy.bx = e.clientX; joy.by = e.clientY; setJoy(e); });
  window.addEventListener('mousemove', (e) => { if (joy.id === 'mouse') setJoy(e); });
  window.addEventListener('mouseup', () => { if (joy.id === 'mouse') { joy.id = null; joy.active = false; input.dx = input.dy = 0; } });

  window.addEventListener('keydown', (e) => {
    keys[e.key.toLowerCase()] = true;
    if (e.key === ' ' && state === 'playing') { const s = player.skills.find((x) => ABILITIES_BY_ID[x.id].kind === 'movement'); if (s && s.timer <= 0) { const def = ABILITIES_BY_ID[s.id]; def.activate(makeCtx(), s.rank); SFX.sfx('cast'); s.timer = def.cooldown(s.rank); } }
    if (e.key === 'Escape' && (state === 'playing' || state === 'paused')) togglePause();
  });
  window.addEventListener('keyup', (e) => { keys[e.key.toLowerCase()] = false; });
  function pollKeys() {
    if (state === 'playing' && joy.id === null) {
      const kx = (keys['d'] || keys['arrowright'] ? 1 : 0) - (keys['a'] || keys['arrowleft'] ? 1 : 0);
      const ky = (keys['s'] || keys['arrowdown'] ? 1 : 0) - (keys['w'] || keys['arrowup'] ? 1 : 0);
      if (kx || ky) { input.dx = kx; input.dy = ky; } else if (!joy.active) { input.dx = input.dy = 0; }
    }
    requestAnimationFrame(pollKeys);
  }
  pollKeys();

  // Resume the AudioContext on the first interaction (autoplay policy).
  function firstGesture() { SFX.ensure(); window.removeEventListener('pointerdown', firstGesture); window.removeEventListener('keydown', firstGesture); }
  window.addEventListener('pointerdown', firstGesture); window.addEventListener('keydown', firstGesture);

  // ── Pause ─────────────────────────────────────────────────────────────────
  function togglePause() {
    if (state === 'playing') { state = 'paused'; showScreen('pause-screen'); }
    else if (state === 'paused') { showScreen(null); resume(); }
  }

  // ── Menus ─────────────────────────────────────────────────────────────────
  function refreshTitle() { el('best-time').textContent = fmtTime(meta.bestTime); el('total-gold').textContent = meta.gold; }

  function buildClassSelect() {
    const grid = el('class-grid'); grid.innerHTML = '';
    for (const c of CLASSES) {
      const unlocked = classUnlocked(c);
      const div = document.createElement('button');
      div.className = 'class-card' + (unlocked ? '' : ' locked') + (selectedClass === c.id ? ' selected' : '');
      div.style.setProperty('--accent', c.color);
      div.innerHTML = `<h3>${c.name}</h3><p>${unlocked ? c.blurb : lockText(c.unlock)}</p>`;
      if (unlocked) div.onclick = () => { SFX.sfx('uiClick'); selectedClass = c.id; selectedWeapon = c.starterWeapon; buildClassSelect(); };
      grid.appendChild(div);
    }
    const cls = CLASS_BY_ID[selectedClass], wr = el('weapon-row');
    wr.innerHTML = '<span class="label">Weapon:</span>';
    for (const wid of cls.weapons) {
      const w = WEAPON_BY_ID[wid], unlocked = weaponUnlocked(w);
      const b = document.createElement('button');
      b.className = 'weapon-chip' + (selectedWeapon === wid ? ' selected' : '') + (unlocked ? '' : ' locked');
      b.textContent = unlocked ? w.name : `🔒 ${w.name}`;
      if (unlocked) b.onclick = () => { SFX.sfx('uiClick'); selectedWeapon = wid; buildClassSelect(); };
      wr.appendChild(b);
    }
    el('class-detail').textContent = WEAPON_BY_ID[selectedWeapon].desc;
  }
  function lockText(u) { if (u.type === 'gold') return `🔒 Buy for ${u.cost} gold`; if (u.type === 'achievement') return `🔒 ${ACHIEVEMENT_BY_ID[u.achievement].name}`; return 'Locked'; }

  function shopRow(list, label, sub, costText, can, onBuy) {
    const row = document.createElement('div'); row.className = 'shop-row';
    row.innerHTML = `<span><b>${label}</b>${sub ? `<br><span class="muted">${sub}</span>` : ''}</span>`;
    const b = document.createElement('button'); b.className = 'btn small' + (can ? ' primary' : '');
    b.textContent = costText; b.disabled = !can; b.onclick = onBuy;
    row.appendChild(b); list.appendChild(row);
  }
  function shopHead(list, text) { const h = document.createElement('div'); h.className = 'shop-head'; h.textContent = text; list.appendChild(h); }

  function buildShop() {
    el('shop-gold').textContent = `Gold: ${meta.gold}`;
    const list = el('shop-list'); list.innerHTML = '';

    // Permanent upgrades
    shopHead(list, 'Permanent Upgrades');
    for (const t of UPGRADE_TRACKS) {
      const lvl = meta.upgrades[t.id], maxed = lvl >= t.max, cost = t.cost(lvl), can = !maxed && meta.gold >= cost;
      shopRow(list, t.name, `Lv ${lvl}/${t.max} · ${t.desc(lvl)}`, maxed ? 'MAX' : `${cost} g`, can, () => {
        if (!maxed && meta.gold >= cost) { meta.gold -= cost; meta.upgrades[t.id]++; SFX.sfx('purchase'); saveMeta(); buildShop(); refreshTitle(); }
      });
    }

    // Unlocks (classes + weapons)
    const items = [];
    for (const c of CLASSES) if (c.unlock.type === 'gold' && !classUnlocked(c)) items.push({ name: `${c.name} (class)`, cost: c.unlock.cost, buy: () => { meta.unlockedClasses[c.id] = true; } });
    for (const w of WEAPONS) if (w.unlock.type === 'gold' && !weaponUnlocked(w)) items.push({ name: `${w.name} (${CLASS_BY_ID[w.classId].name})`, cost: w.unlock.cost, buy: () => { meta.unlockedWeapons[w.id] = true; } });
    if (items.length) {
      shopHead(list, 'Unlocks');
      for (const it of items) {
        const can = meta.gold >= it.cost;
        shopRow(list, it.name, '', `${it.cost} g`, can, () => { if (meta.gold >= it.cost) { meta.gold -= it.cost; it.buy(); SFX.sfx('purchase'); saveMeta(); buildShop(); refreshTitle(); } });
      }
    }
  }

  function buildAchievements() {
    const list = el('ach-list'); list.innerHTML = '';
    for (const a of ACHIEVEMENTS) {
      const done = !!meta.achievements[a.id];
      const row = document.createElement('div'); row.className = 'ach-row' + (done ? ' done' : '');
      row.innerHTML = `<div><b>${done ? '✓ ' : ''}${a.name}</b><br><span class="muted">${a.desc}</span></div><span class="unlocks">${a.unlocks}</span>`;
      list.appendChild(row);
    }
  }

  // Volume controls (shared by pause + settings)
  function wireVolume(sliderId, muteId) {
    const sl = el(sliderId), mb = el(muteId);
    sl.value = String(Math.round(meta.volume * 100));
    const syncMute = () => { mb.textContent = meta.muted ? '🔇 Muted' : '🔊 Sound On'; };
    syncMute();
    sl.oninput = () => { meta.volume = sl.value / 100; SFX.setVolume(meta.volume); saveMeta(); };
    mb.onclick = () => { meta.muted = !meta.muted; SFX.setMuted(meta.muted); syncMute(); saveMeta(); SFX.sfx('uiClick'); };
  }

  const clk = (fn) => () => { SFX.sfx('uiClick'); fn(); };
  el('start-btn').onclick = clk(() => { el('begin-btn').dataset.daily = ''; buildClassSelect(); showScreen('class-screen'); });
  el('daily-btn').onclick = clk(() => { el('begin-btn').dataset.daily = '1'; buildClassSelect(); showScreen('class-screen'); });
  el('shop-btn').onclick = clk(() => { buildShop(); showScreen('shop-screen'); });
  el('ach-btn').onclick = clk(() => { buildAchievements(); showScreen('ach-screen'); });
  el('settings-btn').onclick = clk(() => { wireVolume('vol-slider2', 'mute-btn2'); showScreen('settings-screen'); });
  el('settings-back-btn').onclick = clk(() => showScreen('title-screen'));
  el('shop-back-btn').onclick = clk(() => { refreshTitle(); showScreen('title-screen'); });
  el('ach-back-btn').onclick = clk(() => showScreen('title-screen'));
  el('class-back-btn').onclick = clk(() => showScreen('title-screen'));
  el('begin-btn').onclick = clk(() => { const daily = el('begin-btn').dataset.daily === '1'; startRun(daily ? dailySeed() : `run-${Date.now()}`); });
  el('restart-btn').onclick = clk(() => { refreshTitle(); showScreen('title-screen'); });
  el('win-continue-btn').onclick = clk(() => { refreshTitle(); showScreen('title-screen'); });
  el('pause-btn').onclick = () => { SFX.sfx('uiClick'); togglePause(); };
  el('resume-btn').onclick = () => { SFX.sfx('uiClick'); showScreen(null); resume(); };
  el('quit-btn').onclick = clk(() => { state = 'title'; SFX.stopMusic(); refreshTitle(); showScreen('title-screen'); });

  SFX.config(meta.volume, meta.muted);
  wireVolume('vol-slider', 'mute-btn');
  refreshTitle();
  showScreen('title-screen');
})();
