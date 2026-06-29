// Seeded RNG — the foundation of replayability.
// Same seed => same dungeon, enemies, and loot. Enables shareable seeds + daily runs.

// Hash a string seed into a 32-bit integer (xmur3).
function hashSeed(str) {
  let h = 1779033703 ^ str.length;
  for (let i = 0; i < str.length; i++) {
    h = Math.imul(h ^ str.charCodeAt(i), 3432918353);
    h = (h << 13) | (h >>> 19);
  }
  return function () {
    h = Math.imul(h ^ (h >>> 16), 2246822507);
    h = Math.imul(h ^ (h >>> 13), 3266489909);
    return (h ^= h >>> 16) >>> 0;
  };
}

// Mulberry32 PRNG — fast, deterministic, good enough for a game.
function mulberry32(a) {
  return function () {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

class RNG {
  constructor(seedStr) {
    this.seedStr = String(seedStr);
    const seedFn = hashSeed(this.seedStr);
    this._next = mulberry32(seedFn());
  }
  // float in [0, 1)
  float() {
    return this._next();
  }
  // int in [min, max] inclusive
  int(min, max) {
    return min + Math.floor(this._next() * (max - min + 1));
  }
  // random element of an array
  pick(arr) {
    return arr[Math.floor(this._next() * arr.length)];
  }
  // true with probability p
  chance(p) {
    return this._next() < p;
  }
  // weighted pick: items = [{ value, weight }]
  weighted(items) {
    let total = 0;
    for (const it of items) total += it.weight;
    let r = this._next() * total;
    for (const it of items) {
      r -= it.weight;
      if (r <= 0) return it.value;
    }
    return items[items.length - 1].value;
  }
}

// Today's date as a deterministic seed for the "Daily Run".
function dailySeed() {
  const d = new Date();
  return `daily-${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`;
}

window.RNG = RNG;
window.dailySeed = dailySeed;
