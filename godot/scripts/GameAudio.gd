extends Node
## Procedurally synthesized SFX + ambient music — no audio files, ported from
## js/audio.js. Each one-shot SFX is baked into a small in-memory 16-bit WAV at
## call time (oscillator + exponential envelope, or faded/high-passed noise,
## mirroring tone()/noise()); music loops a baked drone bed plus sparse
## scheduled motif notes. Autoloaded as `GameAudio`.

const MIX_RATE := 44100
const SCALE := [146.83, 155.56, 174.61, 196.0, 220.0, 233.08]   # D minor-ish, low
const POOL_SIZE := 8

var volume := 0.7
var muted := false

var _sfx_players: Array = []
var _next_player := 0
var _music_player: AudioStreamPlayer
var _motif_player: AudioStreamPlayer
var _music_timer: Timer
var _music_on := false

func _ready() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_sfx_players.append(p)
	_music_player = AudioStreamPlayer.new(); add_child(_music_player)
	_motif_player = AudioStreamPlayer.new(); add_child(_motif_player)
	_music_timer = Timer.new(); _music_timer.one_shot = true
	_music_timer.timeout.connect(_schedule_motif)
	add_child(_music_timer)
	_apply_volume()

func config(v: float, m: bool) -> void:
	volume = clampf(v, 0.0, 1.0); muted = m; _apply_volume()

func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0); _apply_volume()

func set_muted(m: bool) -> void:
	muted = m; _apply_volume()

func _apply_volume() -> void:
	var db: float = -80.0 if (muted or volume <= 0.0) else linear_to_db(volume)
	for p in _sfx_players:
		p.volume_db = db
	_music_player.volume_db = db - 6.0
	_motif_player.volume_db = db - 6.0

# ── One-shot SFX (ported from the sfx() switch in js/audio.js) ─────────────────
func sfx(name: String) -> void:
	var sr := MIX_RATE
	var samples := PackedFloat32Array()
	samples.resize(int(0.4 * sr))
	match name:
		"hit": _add_noise(samples, sr, 0.0, 0.05, 0.18, 1200.0)
		"crit":
			_add_noise(samples, sr, 0.0, 0.06, 0.25, 900.0)
			_add_tone(samples, sr, 880.0, 0.0, 0.08, "square", 0.12)
		"enemyDie":
			_add_tone(samples, sr, 220.0, 0.0, 0.18, "sawtooth", 0.16)
			_add_tone(samples, sr, 110.0, 0.02, 0.2, "sine", 0.12)
		"pickup":
			_add_tone(samples, sr, 660.0, 0.0, 0.08, "triangle", 0.12)
			_add_tone(samples, sr, 990.0, 0.05, 0.08, "triangle", 0.1)
		"levelup":
			var freqs := [523.0, 659.0, 784.0, 1046.0]
			for i in freqs.size():
				_add_tone(samples, sr, freqs[i], i * 0.07, 0.2, "triangle", 0.14)
		"hurt":
			_add_tone(samples, sr, 160.0, 0.0, 0.18, "sawtooth", 0.2)
			_add_noise(samples, sr, 0.0, 0.1, 0.12, 300.0)
		"cast":
			_add_tone(samples, sr, 300.0, 0.0, 0.12, "sine", 0.08)
			_add_tone(samples, sr, 600.0, 0.02, 0.1, "sine", 0.06)
		"uiClick": _add_tone(samples, sr, 440.0, 0.0, 0.05, "square", 0.08)
		"purchase":
			_add_tone(samples, sr, 784.0, 0.0, 0.1, "triangle", 0.14)
			_add_tone(samples, sr, 1175.0, 0.08, 0.12, "triangle", 0.12)
		"heartbeat": _add_tone(samples, sr, 70.0, 0.0, 0.16, "sine", 0.3)
		_: return
	var p: AudioStreamPlayer = _sfx_players[_next_player]
	_next_player = (_next_player + 1) % POOL_SIZE
	p.stream = _to_stream(samples, sr, false)
	p.play()

# ── Dark-ambient music: drone bed + sparse motif notes ──────────────────────────
func start_music() -> void:
	if _music_on:
		return
	_music_on = true
	_music_player.stream = _bake_drone_loop()
	_music_player.play()
	_schedule_motif()

func stop_music() -> void:
	_music_on = false
	_music_player.stop()
	_motif_player.stop()
	_music_timer.stop()

func _schedule_motif() -> void:
	if not _music_on:
		return
	if randf() < 0.6:
		var f: float = SCALE[randi() % SCALE.size()] * (2.0 if randf() < 0.3 else 1.0)
		_motif_player.stream = _bake_motif_note(f)
		_motif_player.play()
	_music_timer.start(2.6 + randf() * 2.6)

func _bake_drone_loop() -> AudioStreamWAV:
	var sr := MIX_RATE
	var n := int(12.0 * sr)
	var samples := PackedFloat32Array()
	samples.resize(n)
	# Three sustained drones with slow LFO amplitude wobble (ported from drone()).
	var drones := [
		{"freq": 73.42, "type": "sine", "gain": 0.10, "lfo": 0.08},
		{"freq": 110.0, "type": "sine", "gain": 0.07, "lfo": 0.10},
		{"freq": 146.83, "type": "triangle", "gain": 0.04, "lfo": 0.07},
	]
	for d in drones:
		var freq: float = d["freq"]; var type: String = d["type"]
		var gain: float = d["gain"]; var lfo_hz: float = d["lfo"]
		for i in n:
			var t := float(i) / sr
			var wobble := 0.4 + 0.6 * (0.5 + 0.5 * sin(TAU * lfo_hz * t))
			samples[i] += _waveform(type, freq * t) * gain * wobble
	return _to_stream(samples, sr, true)

func _bake_motif_note(freq: float) -> AudioStreamWAV:
	var sr := MIX_RATE
	var dur := 3.6
	var n := int(dur * sr)
	var samples := PackedFloat32Array()
	samples.resize(n)
	for i in n:
		var t := float(i) / sr
		var env: float
		if t < 0.8:
			env = lerpf(0.0001, 0.05, t / 0.8)
		else:
			var k: float = (t - 0.8) / 2.7
			env = 0.05 * pow(0.0001 / 0.05, clampf(k, 0.0, 1.0))
		samples[i] = _waveform("triangle", freq * t) * env
	return _to_stream(samples, sr, false)

# ── Synthesis helpers (ported from tone()/noise() in js/audio.js) ──────────────
func _waveform(type: String, x: float) -> float:
	var f: float = fmod(x, 1.0)
	if f < 0.0:
		f += 1.0
	match type:
		"square": return 1.0 if f < 0.5 else -1.0
		"sawtooth": return 2.0 * f - 1.0
		"triangle": return 4.0 * absf(f - 0.5) - 1.0
	return sin(TAU * x)

func _envelope(t: float, dur: float, gain: float) -> float:
	var attack := 0.008
	if t >= dur:
		return 0.0
	if t < attack:
		return 0.0001 * pow(gain / 0.0001, t / attack)
	var k: float = (t - attack) / maxf(dur - attack, 0.0001)
	return gain * pow(0.0001 / gain, clampf(k, 0.0, 1.0))

func _add_tone(samples: PackedFloat32Array, sr: int, freq: float, t_offset: float, dur: float, type: String, gain: float) -> void:
	var start_i := int(t_offset * sr)
	var n := int(dur * sr) + 1
	for i in n:
		var idx := start_i + i
		if idx < 0 or idx >= samples.size():
			continue
		var t := float(i) / sr
		samples[idx] += _waveform(type, freq * t) * _envelope(t, dur, gain)

func _add_noise(samples: PackedFloat32Array, sr: int, t_offset: float, dur: float, gain: float, hp_cutoff: float) -> void:
	var start_i := int(t_offset * sr)
	var n := int(dur * sr)
	var raw := PackedFloat32Array()
	raw.resize(n)
	for i in n:
		raw[i] = (randf() * 2.0 - 1.0) * (1.0 - float(i) / n)
	if hp_cutoff > 0.0 and n > 1:
		var rc: float = 1.0 / (TAU * hp_cutoff)
		var dt: float = 1.0 / sr
		var alpha: float = rc / (rc + dt)
		var prev_in := 0.0
		var prev_out := 0.0
		for i in n:
			var x: float = raw[i]
			var y: float = alpha * (prev_out + x - prev_in)
			prev_in = x; prev_out = y
			raw[i] = y
	for i in n:
		var idx := start_i + i
		if idx < 0 or idx >= samples.size():
			continue
		samples[idx] += raw[i] * gain

func _to_stream(samples: PackedFloat32Array, sr: int, loop: bool) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sr
	stream.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v: int = clampi(int(samples[i] * 32767.0), -32768, 32767)
		bytes.encode_s16(i * 2, v)
	stream.data = bytes
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = samples.size()
	return stream
