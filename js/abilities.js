// ── Ironvow: per-class ability pools ───────────────────────────────────────
// Each class has 10 abilities. All 10 are always eligible during a run; on each
// level-up the game rolls 5 of them as choices (pick 1). Abilities stack up to
// `maxLevel`, after which they drop out of future rolls.
//
// apply(p) applies a single rank. Effects that depend on orbital weapons guard on
// `p.orbital` so they no-op harmlessly when that class isn't using one.

function A(id, name, desc, classId, maxLevel, apply) {
  return { id, name, desc, classId, maxLevel, apply };
}

const ABILITIES = [
  // ── Knight ────────────────────────────────────────────────────────────────
  A('kn_bulwark', 'Bulwark', '+30 max HP (heal 30)', 'knight', 5, (p) => { p.maxHp += 30; p.hp += 30; }),
  A('kn_ironwill', 'Iron Will', '+0.6 HP regen / sec', 'knight', 5, (p) => { p.regen += 0.6; }),
  A('kn_heavy', 'Heavy Blows', '+20% damage', 'knight', 8, (p) => { p.damage *= 1.2; }),
  A('kn_broad', 'Broad Sweep', '+12% weapon size', 'knight', 5, (p) => { p.projectileSize *= 1.12; }),
  A('kn_riposte', 'Riposte', '+5% crit chance', 'knight', 5, (p) => { p.crit += 0.05; }),
  A('kn_tireless', 'Tireless', '+15% attack speed', 'knight', 5, (p) => { p.attackCooldown *= 0.87; }),
  A('kn_greaves', 'Greaves', '+10% move speed', 'knight', 5, (p) => { p.speed *= 1.1; }),
  A('kn_thorns', 'Thorns', 'Reflect +6 contact damage', 'knight', 5, (p) => { p.thorns += 6; }),
  A('kn_secondwind', 'Second Wind', '+4% lifesteal', 'knight', 5, (p) => { p.lifesteal += 0.04; }),
  A('kn_juggernaut', 'Juggernaut', '+1 pierce', 'knight', 3, (p) => { p.pierce += 1; }),

  // ── Archer ─────────────────────────────────────────────────────────────────
  A('ar_eagle', 'Eagle Eye', '+20% damage', 'archer', 8, (p) => { p.damage *= 1.2; }),
  A('ar_quiver', 'Quiver', '+1 projectile', 'archer', 4, (p) => { p.projectileCount += 1; }),
  A('ar_bodkin', 'Bodkin Points', '+1 pierce', 'archer', 5, (p) => { p.pierce += 1; }),
  A('ar_fleet', 'Fleet Foot', '+12% move speed', 'archer', 5, (p) => { p.speed *= 1.12; }),
  A('ar_deadeye', 'Deadeye', '+7% crit chance', 'archer', 6, (p) => { p.crit += 0.07; }),
  A('ar_rapid', 'Rapid Draw', '+18% attack speed', 'archer', 6, (p) => { p.attackCooldown *= 0.82; }),
  A('ar_longshot', 'Longshot', '+25% projectile speed', 'archer', 5, (p) => { p.projectileSpeed *= 1.25; }),
  A('ar_barbed', 'Barbed Arrows', 'Hits inflict burn', 'archer', 3, (p) => { p.burnOnHit += 4; }),
  A('ar_hawkeye', 'Hawkeye', '+40% pickup range', 'archer', 3, (p) => { p.pickupRange *= 1.4; }),
  A('ar_vital', 'Vital Strike', '+0.5x crit damage', 'archer', 3, (p) => { p.critMult += 0.5; }),

  // ── Mage ─────────────────────────────────────────────────────────────────
  A('mg_pyro', 'Pyromania', '+25% damage', 'mage', 8, (p) => { p.damage *= 1.25; }),
  A('mg_wildfire', 'Wildfire', '+35% blast radius', 'mage', 5, (p) => { p.aoeMult *= 1.35; }),
  A('mg_cinders', 'Cinders', 'Hits inflict burn', 'mage', 4, (p) => { p.burnOnHit += 6; }),
  A('mg_surge', 'Arcane Surge', '+18% attack speed', 'mage', 6, (p) => { p.attackCooldown *= 0.82; }),
  A('mg_shield', 'Mana Shield', '+25 max HP (heal 25)', 'mage', 4, (p) => { p.maxHp += 25; p.hp += 25; }),
  A('mg_farcast', 'Far Cast', '+25% projectile speed', 'mage', 4, (p) => { p.projectileSpeed *= 1.25; }),
  A('mg_twincast', 'Twin Cast', '+1 projectile', 'mage', 3, (p) => { p.projectileCount += 1; }),
  A('mg_frostbite', 'Frostbite', 'Hits slow enemies', 'mage', 1, (p) => { p.slowOnHit = true; }),
  A('mg_focus', 'Focus', '+8% crit chance', 'mage', 5, (p) => { p.crit += 0.08; }),
  A('mg_meteoric', 'Meteoric', '+30% projectile size', 'mage', 4, (p) => { p.projectileSize *= 1.3; }),

  // ── Rogue ─────────────────────────────────────────────────────────────────
  A('rg_twinfang', 'Twin Fang', '+1 projectile', 'rogue', 4, (p) => { p.projectileCount += 1; }),
  A('rg_backstab', 'Backstab', '+9% crit chance', 'rogue', 6, (p) => { p.crit += 0.09; }),
  A('rg_lethality', 'Lethality', '+0.5x crit damage', 'rogue', 4, (p) => { p.critMult += 0.5; }),
  A('rg_fleet', 'Fleet', '+14% move speed', 'rogue', 5, (p) => { p.speed *= 1.14; }),
  A('rg_frenzy', 'Frenzy', '+20% attack speed', 'rogue', 6, (p) => { p.attackCooldown *= 0.8; }),
  A('rg_venom', 'Venom', 'Hits inflict poison', 'rogue', 4, (p) => { p.burnOnHit += 5; }),
  A('rg_sharp', 'Sharpened', '+18% damage', 'rogue', 8, (p) => { p.damage *= 1.18; }),
  A('rg_shadow', 'Shadowstep', '+25% projectile speed', 'rogue', 4, (p) => { p.projectileSpeed *= 1.25; }),
  A('rg_blood', 'Bloodthirst', '+5% lifesteal', 'rogue', 5, (p) => { p.lifesteal += 0.05; }),
  A('rg_vital', 'Vitality', '+20 max HP (heal 20)', 'rogue', 4, (p) => { p.maxHp += 20; p.hp += 20; }),

  // ── Cleric ─────────────────────────────────────────────────────────────────
  A('cl_devotion', 'Devotion', '+1.0 HP regen / sec', 'cleric', 6, (p) => { p.regen += 1.0; }),
  A('cl_radiance', 'Radiance', '+20% damage', 'cleric', 8, (p) => { p.damage *= 1.2; }),
  A('cl_sanctify', 'Sanctify', '+1 projectile', 'cleric', 3, (p) => { p.projectileCount += 1; }),
  A('cl_blessed', 'Blessed', '+6% lifesteal', 'cleric', 5, (p) => { p.lifesteal += 0.06; }),
  A('cl_aegis', 'Aegis', '+30 max HP (heal 30)', 'cleric', 5, (p) => { p.maxHp += 30; p.hp += 30; }),
  A('cl_zeal', 'Zeal', '+15% attack speed', 'cleric', 5, (p) => { p.attackCooldown *= 0.87; }),
  A('cl_smite', 'Smite', '+8% crit chance', 'cleric', 5, (p) => { p.crit += 0.08; }),
  A('cl_consecrate', 'Consecrate', 'Aura scorches nearby foes', 'cleric', 4, (p) => { p.holyAura += 8; }),
  A('cl_purity', 'Purity', '+35% pickup range', 'cleric', 3, (p) => { p.pickupRange *= 1.35; }),
  A('cl_grace', 'Grace', '+10% move speed', 'cleric', 4, (p) => { p.speed *= 1.1; }),

  // ── Barbarian ──────────────────────────────────────────────────────────────
  A('bb_rage', 'Rage', '+22% damage', 'barbarian', 8, (p) => { p.damage *= 1.22; }),
  A('bb_cyclone', 'Twin Cyclone', '+1 orbital axe', 'barbarian', 3, (p) => { if (p.orbital) p.orbital.count += 1; }),
  A('bb_bloodlust', 'Bloodlust', '+6% lifesteal', 'barbarian', 5, (p) => { p.lifesteal += 0.06; }),
  A('bb_hide', 'Thick Hide', '+35 max HP (heal 35)', 'barbarian', 5, (p) => { p.maxHp += 35; p.hp += 35; }),
  A('bb_frenzied', 'Frenzied', '+18% attack & spin speed', 'barbarian', 5, (p) => { p.attackCooldown *= 0.85; if (p.orbital) p.orbital.speed *= 1.18; }),
  A('bb_reckless', 'Reckless', '+8% crit chance', 'barbarian', 5, (p) => { p.crit += 0.08; }),
  A('bb_wide', 'Wide Swing', '+15% orbital reach', 'barbarian', 4, (p) => { if (p.orbital) p.orbital.dist *= 1.15; }),
  A('bb_heavyaxe', 'Heavy Axe', '+20% orbital size', 'barbarian', 4, (p) => { if (p.orbital) p.orbital.r *= 1.2; }),
  A('bb_unstoppable', 'Unstoppable', '+1 pierce', 'barbarian', 4, (p) => { p.pierce += 1; }),
  A('bb_warcry', 'Warcry', '+10% move speed', 'barbarian', 4, (p) => { p.speed *= 1.1; }),
];

const ABILITIES_BY_CLASS = {};
for (const ab of ABILITIES) {
  (ABILITIES_BY_CLASS[ab.classId] ||= []).push(ab);
}

// Roll `n` distinct abilities for a level-up: from the class's pool, excluding any
// already at max rank. `owned` maps abilityId -> current rank.
function rollAbilities(rng, classId, owned, n = 5) {
  const pool = (ABILITIES_BY_CLASS[classId] || []).filter(
    (ab) => (owned[ab.id] || 0) < ab.maxLevel
  );
  const out = [];
  for (let i = 0; i < n && pool.length; i++) {
    out.push(pool.splice(rng.int(0, pool.length - 1), 1)[0]);
  }
  return out;
}

window.ABILITIES = ABILITIES;
window.ABILITIES_BY_CLASS = ABILITIES_BY_CLASS;
window.rollAbilities = rollAbilities;
