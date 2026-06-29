// ── Ironvow: the 6 playable classes ────────────────────────────────────────
// Each class = base stat tilt + a starter weapon + one unlockable weapon.
// Unlock is either the default (free), a gold cost, or an achievement gate.

const CLASSES = [
  {
    id: 'knight',
    name: 'Knight',
    color: '#c9d1e0',
    blurb: 'Stalwart defender. High HP, sweeping melee arcs.',
    baseStats: { maxHp: 140, speed: 175, damage: 12, crit: 0.03, regen: 0.2 },
    starterWeapon: 'arming_sword',
    weapons: ['arming_sword', 'warhammer'],
    unlock: { type: 'default' },
  },
  {
    id: 'archer',
    name: 'Archer',
    color: '#7bdc8a',
    blurb: 'Ranged marksman. Piercing arrows from afar.',
    baseStats: { maxHp: 90, speed: 195, damage: 11, crit: 0.08, regen: 0 },
    starterWeapon: 'shortbow',
    weapons: ['shortbow', 'crossbow'],
    unlock: { type: 'gold', cost: 150 },
  },
  {
    id: 'mage',
    name: 'Mage',
    color: '#6aa9ff',
    blurb: 'Glass cannon. Explosive area damage, frail.',
    baseStats: { maxHp: 70, speed: 180, damage: 16, crit: 0.05, regen: 0 },
    starterWeapon: 'fireball',
    weapons: ['fireball', 'frost_nova'],
    unlock: { type: 'gold', cost: 250 },
  },
  {
    id: 'rogue',
    name: 'Rogue',
    color: '#e8c14a',
    blurb: 'Swift assassin. Fast, crit-heavy daggers.',
    baseStats: { maxHp: 80, speed: 215, damage: 8, crit: 0.18, regen: 0 },
    starterWeapon: 'daggers',
    weapons: ['daggers', 'fan_of_knives'],
    unlock: { type: 'gold', cost: 200 },
  },
  {
    id: 'cleric',
    name: 'Cleric',
    color: '#f0e6b0',
    blurb: 'Holy support. Sustains through constant regen.',
    baseStats: { maxHp: 100, speed: 180, damage: 10, crit: 0.04, regen: 1.0 },
    starterWeapon: 'holy_bolt',
    weapons: ['holy_bolt', 'censer'],
    unlock: { type: 'achievement', achievement: 'survive_8' },
  },
  {
    id: 'barbarian',
    name: 'Barbarian',
    color: '#e2655a',
    blurb: 'Raging bruiser. Whirling orbital axes.',
    baseStats: { maxHp: 130, speed: 185, damage: 14, crit: 0.06, regen: 0 },
    starterWeapon: 'whirlwind_axe',
    weapons: ['whirlwind_axe', 'throwing_axe'],
    unlock: { type: 'achievement', achievement: 'level_15' },
  },
];

const CLASS_BY_ID = {};
for (const c of CLASSES) CLASS_BY_ID[c.id] = c;

window.CLASSES = CLASSES;
window.CLASS_BY_ID = CLASS_BY_ID;
