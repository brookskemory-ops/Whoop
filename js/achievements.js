// ── Ironvow: achievements ──────────────────────────────────────────────────
// Milestone unlocks. `test(stats)` is checked during a run (level-up) and at run
// end. `stats` carries per-run + cumulative figures. Returns true once earned.
// Some achievements gate classes/weapons (see classes.js / weapons.js `unlock`).

const ACHIEVEMENTS = [
  {
    id: 'survive_8', name: 'Hold the Line', desc: 'Survive 8:00 in a single run.',
    unlocks: 'Cleric (class)',
    test: (s) => s.time >= 8 * 60,
  },
  {
    id: 'level_15', name: 'Seasoned', desc: 'Reach level 15 in a single run.',
    unlocks: 'Barbarian (class)',
    test: (s) => s.level >= 15,
  },
  {
    id: 'survive_12', name: 'Unbroken', desc: 'Survive 12:00 in a single run.',
    unlocks: 'Frost Nova (Mage weapon)',
    test: (s) => s.time >= 12 * 60,
  },
  {
    id: 'archer_kills_500', name: 'Fletcher', desc: 'Slay 500 foes as the Archer (lifetime).',
    unlocks: 'Crossbow (Archer weapon)',
    test: (s) => (s.classKills.archer || 0) >= 500,
  },
  {
    id: 'kills_1000', name: 'Reaper', desc: 'Slay 1000 foes (lifetime).',
    unlocks: '500 bonus gold',
    test: (s) => s.totalKills >= 1000,
  },
];

const ACHIEVEMENT_BY_ID = {};
for (const a of ACHIEVEMENTS) ACHIEVEMENT_BY_ID[a.id] = a;

// Returns array of newly-earned achievement ids given current stats and the set of
// already-earned ids.
function checkAchievements(stats, earned) {
  const fresh = [];
  for (const a of ACHIEVEMENTS) {
    if (!earned[a.id] && a.test(stats)) fresh.push(a.id);
  }
  return fresh;
}

window.ACHIEVEMENTS = ACHIEVEMENTS;
window.ACHIEVEMENT_BY_ID = ACHIEVEMENT_BY_ID;
window.checkAchievements = checkAchievements;
