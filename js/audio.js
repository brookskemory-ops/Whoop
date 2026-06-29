// ── Ironvow: synthesized audio ─────────────────────────────────────────────
// All sound is generated with WebAudio (no files). Dark-ambient music loop + SFX.
// Everything is wrapped so a missing/blocked AudioContext can never crash the game.

const Audio = (() => {
  let ctx = null, master = null, sfxBus = null, musicBus = null;
  let started = false, muted = false, volume = 0.7;
  let musicTimer = null, musicOn = false;

  function ensure() {
    if (ctx) { if (ctx.state === 'suspended') ctx.resume().catch(() => {}); return ctx; }
    try {
      const AC = window.AudioContext || window.webkitAudioContext;
      if (!AC) return null;
      ctx = new AC();
      master = ctx.createGain(); master.gain.value = muted ? 0 : volume; master.connect(ctx.destination);
      sfxBus = ctx.createGain(); sfxBus.gain.value = 0.9; sfxBus.connect(master);
      musicBus = ctx.createGain(); musicBus.gain.value = 0.5; musicBus.connect(master);
      started = true;
    } catch { ctx = null; }
    return ctx;
  }

  function setVolume(v) { volume = Math.max(0, Math.min(1, v)); if (master && !muted) master.gain.value = volume; }
  function setMuted(m) { muted = !!m; if (master) master.gain.value = muted ? 0 : volume; }
  function getVolume() { return volume; }
  function isMuted() { return muted; }
  function config(v, m) { if (typeof v === 'number') volume = v; muted = !!m; if (master) master.gain.value = muted ? 0 : volume; }

  // tiny envelope helper
  function tone(freq, t0, dur, type, gain, bus) {
    if (!ctx) return;
    const o = ctx.createOscillator(), g = ctx.createGain();
    o.type = type || 'sine'; o.frequency.setValueAtTime(freq, t0);
    g.gain.setValueAtTime(0.0001, t0);
    g.gain.exponentialRampToValueAtTime(gain, t0 + 0.008);
    g.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
    o.connect(g); g.connect(bus || sfxBus); o.start(t0); o.stop(t0 + dur + 0.02);
    return o;
  }
  function noise(t0, dur, gain, hp) {
    if (!ctx) return;
    const n = Math.floor(ctx.sampleRate * dur), buf = ctx.createBuffer(1, n, ctx.sampleRate), d = buf.getChannelData(0);
    for (let i = 0; i < n; i++) d[i] = (Math.random() * 2 - 1) * (1 - i / n);
    const src = ctx.createBufferSource(); src.buffer = buf;
    const g = ctx.createGain(); g.gain.value = gain;
    let node = src;
    if (hp) { const f = ctx.createBiquadFilter(); f.type = 'highpass'; f.frequency.value = hp; node.connect(f); node = f; }
    node.connect(g); g.connect(sfxBus); src.start(t0); src.stop(t0 + dur);
  }

  function sfx(name) {
    if (!ensure()) return;
    const t = ctx.currentTime;
    switch (name) {
      case 'hit': noise(t, 0.05, 0.18, 1200); break;
      case 'crit': noise(t, 0.06, 0.25, 900); tone(880, t, 0.08, 'square', 0.12); break;
      case 'enemyDie': tone(220, t, 0.18, 'sawtooth', 0.16); tone(110, t + 0.02, 0.2, 'sine', 0.12); break;
      case 'pickup': tone(660, t, 0.08, 'triangle', 0.12); tone(990, t + 0.05, 0.08, 'triangle', 0.1); break;
      case 'levelup': [523, 659, 784, 1046].forEach((f, i) => tone(f, t + i * 0.07, 0.2, 'triangle', 0.14)); break;
      case 'hurt': tone(160, t, 0.18, 'sawtooth', 0.2); noise(t, 0.1, 0.12, 300); break;
      case 'cast': tone(300, t, 0.12, 'sine', 0.08); tone(600, t + 0.02, 0.1, 'sine', 0.06); break;
      case 'uiClick': tone(440, t, 0.05, 'square', 0.08); break;
      case 'purchase': tone(784, t, 0.1, 'triangle', 0.14); tone(1175, t + 0.08, 0.12, 'triangle', 0.12); break;
      case 'heartbeat': tone(70, t, 0.16, 'sine', 0.3); break;
    }
  }

  // ── Dark-ambient music: detuned drones + a slow, sparse menacing motif ──────
  const SCALE = [146.83, 155.56, 174.61, 196.0, 220.0, 233.08]; // D minor-ish, low
  function startMusic() {
    if (!ensure() || musicOn) return;
    musicOn = true;
    // Sustained drones (kept running; gain swells handled by scheduler).
    drone(73.42, 'sine', 0.10);   // D2
    drone(110.0, 'sine', 0.07);   // A2
    drone(146.83, 'triangle', 0.04); // D3
    schedule();
  }
  function drone(freq, type, gain) {
    if (!ctx) return;
    const o = ctx.createOscillator(), g = ctx.createGain(), lfo = ctx.createOscillator(), lg = ctx.createGain();
    o.type = type; o.frequency.value = freq;
    o.detune.value = (Math.random() - 0.5) * 8;
    g.gain.value = gain;
    lfo.frequency.value = 0.06 + Math.random() * 0.05; lg.gain.value = gain * 0.6;
    lfo.connect(lg); lg.connect(g.gain); lfo.start();
    o.connect(g); g.connect(musicBus); o.start();
    droneNodes.push(o, lfo);
  }
  const droneNodes = [];
  function schedule() {
    if (!musicOn || !ctx) return;
    // Occasional sparse note from the scale, with a long soft envelope.
    if (Math.random() < 0.6) {
      const f = SCALE[Math.floor(Math.random() * SCALE.length)] * (Math.random() < 0.3 ? 2 : 1);
      const o = ctx.createOscillator(), g = ctx.createGain(), t = ctx.currentTime;
      o.type = 'triangle'; o.frequency.value = f;
      g.gain.setValueAtTime(0.0001, t);
      g.gain.exponentialRampToValueAtTime(0.05, t + 0.8);
      g.gain.exponentialRampToValueAtTime(0.0001, t + 3.5);
      o.connect(g); g.connect(musicBus); o.start(t); o.stop(t + 3.6);
    }
    musicTimer = setTimeout(schedule, 2600 + Math.random() * 2600);
  }
  function stopMusic() {
    musicOn = false;
    if (musicTimer) { clearTimeout(musicTimer); musicTimer = null; }
    for (const n of droneNodes) { try { n.stop(); } catch {} }
    droneNodes.length = 0;
  }

  return { ensure, sfx, startMusic, stopMusic, setVolume, setMuted, getVolume, isMuted, config };
})();

window.GameAudio = Audio;
