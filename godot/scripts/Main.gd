extends Node2D
## Run controller: menus (title/class-select/shop/achievements), the world
## (floor, player, camera), spawning, input, the HUD, and meta-progression —
## ported from js/game.js. Audio + lighting are not yet ported.

const DEFAULT_TEST_CLASS := "knight"

var _selected_class := "knight"
var _selected_weapon := "arming_sword"
var _selected_stage := "forest"   # both default to always-unlocked picks
var _selected_tier := "tier1"
var _menu_ui: CanvasLayer

var _win_time := 600.0
var _mini_times := [180.0, 360.0, 540.0]

var elapsed := 0.0
var run_gold := 0.0
var run_kills := 0
var _spawn_timer := 0.0
var _state := "playing"   # playing | dead | won

var _world: Node2D
var _stage_root: Node2D
var _player: Player
var _camera: Camera2D
var _active_stage: Dictionary
var _active_tier: Dictionary
var _obstacles: Array = []   # [{"pos": Vector2, "radius": float}, ...] for the active stage

# Boss timeline (ported from spawnBoss/MINI_TIMES/WIN_TIME in js/game.js)
var _boss: Node = null
var _next_mini := 0
var _final_spawned := false
var _banner_text := ""
var _banner_timer := 0.0
var _end_ui: CanvasLayer
var _last_beat := 0.0   # low-HP heartbeat sfx throttle

# Juice: screen shake, level-up/pickup flash, torch lighting, low-HP vignette.
var _shake := 0.0
var _hitstop_end_ms := 0
var _hitstop_cd_ms := 0        # real-time gate: no new freeze until past this
const HITSTOP_GAP_MS := 90     # forced recovery window between freezes
var _flash := 0.0
var _torch_overlay: TextureRect
var _flash_overlay: ColorRect
var _vignette: TextureRect
const _TORCH_BASE_RADIUS := 288.0

# Pause + settings
var _pause_ui: CanvasLayer
var _settings_ui: CanvasLayer

# HUD
var _lbl_level: Label
var _lbl_time: Label
var _lbl_gold: Label
var _hp_fill: ColorRect
var _hp_w := 200.0
var _xp_fill: ColorRect
var _xp_w := 200.0
var _ability_header: Control
var _ability_header_sig := ""
var _boss_bar: Control
var _boss_fill: ColorRect
var _lbl_boss_name: Label
var _boss_w := 280.0
var _lbl_banner: Label

# Touch / mouse joystick
var _joy_active := false
var _joy_id := -1
var _joy_base := Vector2.ZERO
var _joy_vec := Vector2.ZERO
var _joy_visual: Control

# Level-up flow
var _pending_levels := 0
var _leveling := false
var _auto_pick := false
var _level_ui: CanvasLayer

# Headless self-test movement override
var _testing := false
var _test_dir := Vector2.ZERO

var _ui_theme: Theme

func _ready() -> void:
	randomize()
	_ui_theme = UiTheme.build()
	GameAudio.config(GameSave.volume, GameSave.muted)
	if _has_flag("--fast") or _has_flag("--bosstest"):
		_win_time = 12.0
		_mini_times = [3.0, 6.0, 9.0]
	_build_world()
	_build_hud()
	if _has_flag("--selftest"):
		_begin_run(DEFAULT_TEST_CLASS, "")
		_run_selftest()
	elif _has_flag("--bosstest"):
		_begin_run(DEFAULT_TEST_CLASS, "")
		_run_bosstest()
	elif _has_flag("--deathtest"):
		_begin_run(DEFAULT_TEST_CLASS, "")
		_run_deathtest()
	elif _has_flag("--audiotest"):
		_run_audiotest()
	elif _has_flag("--pausetest"):
		_begin_run(DEFAULT_TEST_CLASS, "")
		_run_pausetest()
	elif _has_flag("--stagetest"):
		_run_stagetest()
	elif _has_flag("--shoptest"):
		_run_shoptest()
	elif _has_flag("--progresstest"):
		_run_progresstest()
	elif _has_flag("--juicetest"):
		_run_juicetest()
	elif _has_flag("--buildtest"):
		_run_buildtest()
	else:
		_show_title()

func _has_flag(name: String) -> bool:
	return name in OS.get_cmdline_args() or name in OS.get_cmdline_user_args()

func _build_world() -> void:
	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)

# Rebuilds the bounded, stage-themed ground + scattered obstacles for a run.
# _stage_root is managed explicitly here (not by _clear_run()'s generic
# has-a-script sweep) so the map persists across the run and only resets
# when a new run actually begins.
func _rebuild_stage(stage: Dictionary) -> void:
	if _stage_root:
		_stage_root.queue_free()
	_stage_root = Node2D.new()
	_stage_root.name = "Stage"
	_world.add_child(_stage_root)

	var map_builder := preload("res://scripts/MapBuilder.gd")
	var ground: TileMap = map_builder.build_ground(stage)
	_stage_root.add_child(ground)
	_stage_root.add_child(map_builder.build_walls(stage))

	var textures: Array = []
	for path in stage["obstacle_textures"]:
		textures.append(load(path))
	_obstacles = map_builder.scatter_obstacles(_stage_root, stage, textures)

	# Per-stage lighting: the torch-darkness overlay is a dungeon mood effect;
	# on the bright forest it'd render a sunny meadow as a black cave and hide
	# the arena/obstacles, so only torch-lit stages get it.
	if _torch_overlay:
		_torch_overlay.visible = stage.get("lighting", "torch") == "torch"

# Clamps a candidate spawn position inside the active stage's bounds and,
# if it lands inside an obstacle, resamples the angle a few times before
# giving up and returning the clamped-but-possibly-overlapping position.
func _find_spawn_pos(origin: Vector2, dist: float) -> Vector2:
	var half: Vector2 = _active_stage.get("bounds", Vector2(100000, 100000)) * 0.5 - Vector2(80, 80)
	var pos := Vector2.ZERO
	for i in 8:
		var ang := randf() * TAU
		pos = origin + Vector2(cos(ang), sin(ang)) * dist
		pos.x = clampf(pos.x, -half.x, half.x)
		pos.y = clampf(pos.y, -half.y, half.y)
		if not _pos_blocked(pos):
			break
	return pos

func _pos_blocked(pos: Vector2) -> bool:
	for o in _obstacles:
		if pos.distance_to(o["pos"]) < o["radius"] + 24.0:
			return true
	return false

func _make_radial_gradient_texture(size: Vector2, c0: Color, c1: Color) -> GradientTexture2D:
	return _make_multistop_gradient_texture(size, [0.0, 1.0], [c0, c1], 0.5)

# Multi-stop radial gradient texture (used for the torch-darkness overlay,
# which needs the JS's exact 4-stop falloff). `fill_to_dist` is the UV
# distance (from center) at which the gradient reaches its last stop; beyond
# that, the texture stays clamped at the last color — same as a canvas radial
# gradient. A texture much larger than fill_to_dist*2 gives comfortable
# constant-color coverage past the gradient's "active" radius.
func _make_multistop_gradient_texture(size: Vector2, offsets: Array, colors: Array, fill_to_dist: float) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = int(size.x)
	tex.height = int(size.y)
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5 + fill_to_dist, 0.5)
	return tex

func add_shake(n: float) -> void:
	_shake = minf(20.0, _shake + n)

# Brief impact freeze ("hit-stop"): dips the global time scale for a few real
# milliseconds; restored from _process against the real clock. Rate-limited by a
# real-time cooldown so a stream of crits can't keep re-triggering (and thereby
# pinning) the freeze — each dip must fully recover before the next can start.
# `force` bypasses the cooldown for rare big moments (boss-kill finisher). Skipped
# during headless tests so it never perturbs their timing.
func hitstop(dur: float, scale: float = 0.02, force: bool = false) -> void:
	if _testing:
		return
	var now := Time.get_ticks_msec()
	if not force and now < _hitstop_cd_ms:
		return
	_hitstop_end_ms = now + int(dur * 1000.0)
	_hitstop_cd_ms = _hitstop_end_ms + HITSTOP_GAP_MS
	Engine.time_scale = scale

# Force real time back to normal — called at any transition that pauses/leaves a
# run, so an in-flight freeze can never survive it (belt-and-suspenders).
func _clear_hitstop() -> void:
	_hitstop_end_ms = 0
	_hitstop_cd_ms = 0
	Engine.time_scale = 1.0

# Full-screen white impact flash (boss kills / big moments).
func impact_flash(v: float) -> void:
	_flash = maxf(_flash, v)

func _begin_run(class_id: String, weapon_id: String, stage_id: String = "forest", tier_id: String = "tier1") -> void:
	_clear_menu()
	_clear_run()
	_clear_hitstop()

	_active_stage = GameData.stage_by_id(stage_id)
	if _active_stage.is_empty():
		_active_stage = GameData.STAGES[0]
	_active_tier = GameData.difficulty_by_id(tier_id)
	if _active_tier.is_empty():
		_active_tier = GameData.DIFFICULTIES[0]
	_rebuild_stage(_active_stage)

	_player = Player.new()
	_player.setup(class_id, weapon_id)
	_player.died.connect(_on_player_died)
	_player.leveled_up.connect(_on_level_up)
	_world.add_child(_player)

	_camera = Camera2D.new()
	_camera.position_smoothing_enabled = false   # instant 1:1 follow, matching js/game.js's camX/camY
	var half: Vector2 = _active_stage["bounds"] * 0.5
	_camera.limit_left = int(-half.x); _camera.limit_right = int(half.x)
	_camera.limit_top = int(-half.y); _camera.limit_bottom = int(half.y)
	_player.add_child(_camera)
	_camera.make_current()

	elapsed = 0.0; run_gold = 0.0; run_kills = 0; _spawn_timer = 0.0
	_boss = null; _next_mini = 0; _final_spawned = false
	_banner_text = ""; _banner_timer = 0.0
	# Force-clear the header now: a fresh player's skills list is also empty,
	# so resetting the sig to "" alone wouldn't trigger the change-detection
	# in _update_hud() (it'd compare "" against "" and see "no change"),
	# leaving the previous run's ability badges stuck on screen.
	_ability_header_sig = ""
	_refresh_ability_header()
	_last_beat = 0.0; _shake = 0.0; _flash = 0.0
	_state = "playing"
	GameAudio.start_music()

func _clear_run() -> void:
	# Free everything spawned during the run (player/enemies/gems/projectiles).
	# _stage_root (the ground TileMap + obstacles) is a plain, scriptless
	# Node2D so this sweep leaves it alone — it's rebuilt explicitly by
	# _rebuild_stage() at the start of the next _begin_run().
	if _world:
		for c in _world.get_children():
			if c.get_script() != null:
				c.queue_free()
	_player = null
	_camera = null
	_boss = null

# ── Menus (title / class-select / shop / achievements) ─────────────────────────
func _clear_menu() -> void:
	if _menu_ui:
		_menu_ui.queue_free(); _menu_ui = null

func _menu_base(centered: bool = false) -> VBoxContainer:
	_clear_menu()
	var o := Ui.overlay(self, _ui_theme, false, centered)
	_menu_ui = o["layer"]
	return o["column"]

func _show_title() -> void:
	var vbox := _menu_base()
	_add_title_embers()

	var crest := TextureRect.new()
	crest.texture = load("res://assets/ui/crest.png")
	crest.custom_minimum_size = Vector2(0, 120)
	crest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	vbox.add_child(crest)

	var title := Label.new(); title.text = "IRONVOW"; title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_title(title, 52)
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	vbox.add_child(title)
	var tagline := Label.new(); tagline.text = "~ Hold the line. Forge your legend. ~"
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_muted(tagline, 14)
	vbox.add_child(tagline)
	vbox.add_child(_spacer(18))

	var start_btn := _make_button("New Run", true)
	start_btn.icon = load("res://assets/ui/icon_newrun.png")
	start_btn.pressed.connect(func(): GameAudio.sfx("uiClick"); _show_class_select())
	vbox.add_child(start_btn)
	var shop_btn := _make_button("Armory")
	shop_btn.icon = load("res://assets/ui/icon_armory.png")
	shop_btn.pressed.connect(func(): GameAudio.sfx("uiClick"); _show_shop())
	vbox.add_child(shop_btn)
	var ach_btn := _make_button("Deeds")
	ach_btn.icon = load("res://assets/ui/icon_deeds.png")
	ach_btn.pressed.connect(func(): GameAudio.sfx("uiClick"); _show_achievements())
	vbox.add_child(ach_btn)
	var settings_btn := _make_button("Settings")
	settings_btn.icon = load("res://assets/ui/icon_settings.png")
	settings_btn.pressed.connect(func(): GameAudio.sfx("uiClick"); _show_settings(_show_title))
	vbox.add_child(settings_btn)

	vbox.add_child(_spacer(10))
	var stats := Label.new()
	stats.text = "Best: %d:%02d    Gold: %d" % [int(GameSave.best_time) / 60, int(GameSave.best_time) % 60, GameSave.gold]
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_muted(stats, 14)
	vbox.add_child(stats)

# Slow, sparse embers drifting up behind the title menu for ambience.
func _add_title_embers() -> void:
	var p := CPUParticles2D.new()
	p.amount = 26
	p.lifetime = 6.0
	p.position = Vector2(240, 820)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(240, 20)
	p.direction = Vector2(0, -1)
	p.spread = 18.0
	p.gravity = Vector2(0, -8)
	p.initial_velocity_min = 12.0
	p.initial_velocity_max = 34.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.5
	p.color = Color(0.95, 0.72, 0.32, 0.6)
	p.self_modulate = Color(1, 1, 1, 0.7)
	_menu_ui.add_child(p)

func _spacer(h: int) -> Control:
	return Ui.spacer(h)

func _make_button(text: String, primary: bool = false) -> Button:
	# Thin wrapper over Ui.button so legacy call sites keep working; theme is
	# inherited from the scaffold root, so no per-button theme needed.
	return Ui.button(text, "", primary)

func _show_class_select() -> void:
	var vbox := _menu_base()
	var hdr := Label.new(); hdr.text = "Choose Your Champion"; hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_title(hdr, 22)
	vbox.add_child(hdr)
	vbox.add_child(_spacer(6))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(grid)
	for cid in GameData.AVAILABLE_CLASSES:
		var c: Dictionary = GameData.CLASSES[cid]
		var unlocked := GameSave.class_unlocked(cid)
		var accent := Color(c["color"])
		var b := Button.new()
		b.theme = _ui_theme
		b.custom_minimum_size = Vector2(196, 112)
		b.text = ""
		UiTheme.accent_button_style(b, accent, cid == _selected_class)
		b.pressed.connect(_pick_class.bind(cid))

		var inner := HBoxContainer.new()
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.set_anchors_preset(Control.PRESET_FULL_RECT)
		inner.offset_left = 10; inner.offset_top = 8
		inner.offset_right = -10; inner.offset_bottom = -8
		inner.add_theme_constant_override("separation", 6)
		b.add_child(inner)

		# Class portrait: the idle-facing sprite frame, so the card art matches
		# the in-game champion exactly. Dimmed to a silhouette when locked.
		var portrait := TextureRect.new()
		var frame_path := "res://assets/anim/%s/idle/south/frame_000.png" % cid
		if ResourceLoader.exists(frame_path):
			portrait.texture = load(frame_path)
		portrait.custom_minimum_size = Vector2(52, 0)
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.modulate = Color(1, 1, 1) if unlocked else Color(0.2, 0.18, 0.22, 0.9)
		inner.add_child(portrait)

		var text_col := VBoxContainer.new()
		text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text_col.add_theme_constant_override("separation", 3)
		inner.add_child(text_col)

		var name_lbl := Label.new()
		name_lbl.text = c["name"]
		name_lbl.clip_text = true
		UiTheme.style_heading(name_lbl, accent if unlocked else UiTheme.MUTED, 16)
		text_col.add_child(name_lbl)

		var blurb_lbl := Label.new()
		blurb_lbl.text = c["blurb"] if unlocked else ("(Locked) %s" % _lock_text(c["unlock"]))
		blurb_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		blurb_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiTheme.style_muted(blurb_lbl, 11)
		text_col.add_child(blurb_lbl)

		grid.add_child(b)

	vbox.add_child(_spacer(10))
	var weapon_hdr := Label.new(); weapon_hdr.text = "Weapon:"
	UiTheme.style_muted(weapon_hdr, 14)
	vbox.add_child(weapon_hdr)
	var chip_row := HBoxContainer.new()
	chip_row.add_theme_constant_override("separation", 8)
	vbox.add_child(chip_row)
	var cls: Dictionary = GameData.CLASSES[_selected_class]
	for wid in cls["weapons"]:
		var w: Dictionary = GameData.WEAPON_META[wid]
		var wun := GameSave.weapon_unlocked(wid)
		var wb := Button.new()
		wb.theme = _ui_theme
		wb.custom_minimum_size = Vector2(190, 52)
		wb.add_theme_font_size_override("font_size", 13)
		wb.clip_text = true
		wb.text = w["name"] if wun else "%s (locked)" % w["name"]
		if wid == _selected_weapon and wun:
			wb.theme_type_variation = "PrimaryButton"
		wb.disabled = not wun
		wb.pressed.connect(_pick_weapon.bind(wid))
		chip_row.add_child(wb)
	var detail := Label.new()
	detail.text = GameData.WEAPON_META[_selected_weapon]["desc"]
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD
	UiTheme.style_muted(detail, 13)
	vbox.add_child(detail)

	vbox.add_child(_spacer(10))
	var back_btn := _make_button("Back")
	back_btn.pressed.connect(func(): GameAudio.sfx("uiClick"); _show_title())
	vbox.add_child(back_btn)
	var next_btn := _make_button("Next", true)
	next_btn.disabled = not (GameSave.class_unlocked(_selected_class) and GameSave.weapon_unlocked(_selected_weapon))
	next_btn.pressed.connect(func(): GameAudio.sfx("uiClick"); _show_trial_select())
	vbox.add_child(next_btn)

func _pick_class(cid: String) -> void:
	GameAudio.sfx("uiClick")
	_selected_class = cid
	_selected_weapon = GameData.CLASSES[cid]["weapon"]
	_show_class_select()

func _pick_weapon(wid: String) -> void:
	if not GameSave.weapon_unlocked(wid):
		return
	GameAudio.sfx("uiClick")
	_selected_weapon = wid
	_show_class_select()

func _lock_text(u: Dictionary) -> String:
	match u["type"]:
		"gold": return "Buy for %d gold" % int(u["cost"])
		"achievement": return GameData.achievement_by_id(u["achievement"])["name"]
	return "Locked"

# ── Choose Your Trial: pick the stage (Realm) + difficulty (Oath) ──────────────
func _show_trial_select() -> void:
	# Clamp selection to what's actually unlocked (forest/tier1 always are).
	if not GameSave.stage_unlocked(_selected_stage):
		_selected_stage = "forest"
	if not GameSave.tier_unlocked(_selected_tier):
		_selected_tier = "tier1"

	var vbox := _menu_base()
	var hdr := Label.new(); hdr.text = "Choose Your Trial"; hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_title(hdr, 22)
	vbox.add_child(hdr)

	var realm_hdr := Label.new(); realm_hdr.text = "Realm"
	UiTheme.style_heading(realm_hdr, UiTheme.GOLD_BRIGHT, 14)
	vbox.add_child(realm_hdr)
	for stage in GameData.STAGES:
		var sid: String = stage["id"]
		var unlocked := GameSave.stage_unlocked(sid)
		var card := Button.new()
		card.theme = _ui_theme
		card.custom_minimum_size = Vector2(0, 70)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.disabled = not unlocked
		UiTheme.accent_button_style(card, UiTheme.GOLD, unlocked and sid == _selected_stage)
		if unlocked:
			card.pressed.connect(func(): GameAudio.sfx("uiClick"); _selected_stage = sid; _show_trial_select())
		var col := VBoxContainer.new()
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.set_anchors_preset(Control.PRESET_FULL_RECT)
		col.offset_left = 14; col.offset_right = -14; col.offset_top = 8; col.offset_bottom = 8
		col.add_theme_constant_override("separation", 2)
		card.add_child(col)
		var name_lbl := Label.new()
		name_lbl.text = stage["name"]
		name_lbl.clip_text = true
		UiTheme.style_heading(name_lbl, UiTheme.GOLD_BRIGHT if unlocked else UiTheme.MUTED, 16)
		col.add_child(name_lbl)
		var sub := Label.new()
		if unlocked:
			sub.text = stage.get("blurb", "")
		else:
			var prev: Dictionary = GameData.stage_by_id(stage["unlock"].get("stage", ""))
			sub.text = "Locked — clear %s first" % prev.get("name", "the previous realm")
		sub.clip_text = true
		UiTheme.style_muted(sub, 12)
		col.add_child(sub)
		vbox.add_child(card)

	vbox.add_child(_spacer(Ui.SP_S))
	var oath_hdr := Label.new(); oath_hdr.text = "Oath"
	UiTheme.style_heading(oath_hdr, UiTheme.GOLD_BRIGHT, 14)
	vbox.add_child(oath_hdr)
	var tier_row := HBoxContainer.new()
	tier_row.add_theme_constant_override("separation", 6)
	vbox.add_child(tier_row)
	for tier in GameData.DIFFICULTIES:
		var tid: String = tier["id"]
		var tun := GameSave.tier_unlocked(tid)
		var chip := Button.new()
		chip.theme = _ui_theme
		chip.custom_minimum_size = Vector2(0, 46)
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.clip_text = true
		chip.add_theme_font_size_override("font_size", 13)
		chip.text = tier["name"] if tun else "Locked"
		chip.disabled = not tun
		if tun and tid == _selected_tier:
			chip.theme_type_variation = "PrimaryButton"
		if tun:
			chip.pressed.connect(func(): GameAudio.sfx("uiClick"); _selected_tier = tid; _show_trial_select())
		tier_row.add_child(chip)
	var summary := Label.new()
	summary.text = _tier_summary(GameData.difficulty_by_id(_selected_tier))
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_muted(summary, 13)
	vbox.add_child(summary)
	if not GameSave.tier_unlocked(GameData.DIFFICULTIES[GameData.DIFFICULTIES.size() - 1]["id"]):
		var hint := Label.new()
		hint.text = "Clear every realm at your current Oath to swear a harder one."
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UiTheme.style_muted(hint, 11)
		vbox.add_child(hint)

	vbox.add_child(_spacer(Ui.SP_M))
	var back_btn := _make_button("Back")
	back_btn.pressed.connect(func(): GameAudio.sfx("uiClick"); _show_class_select())
	vbox.add_child(back_btn)
	var begin_btn := _make_button("Begin", true)
	begin_btn.pressed.connect(func(): GameAudio.sfx("uiClick"); _begin_run(_selected_class, _selected_weapon, _selected_stage, _selected_tier))
	vbox.add_child(begin_btn)

func _tier_summary(tier: Dictionary) -> String:
	if tier.is_empty():
		return ""
	var hp := int(round((float(tier.get("hp_mult", 1.0)) - 1.0) * 100.0))
	var dmg := int(round((float(tier.get("dmg_mult", 1.0)) - 1.0) * 100.0))
	var sp := int(round((float(tier.get("spawn_mult", 1.0)) - 1.0) * 100.0))
	var s := "Baseline threat."
	if hp > 0 or dmg > 0 or sp > 0:
		s = "Enemies +%d%% HP, +%d%% damage, +%d%% spawns." % [hp, dmg, sp]
	var ue: Array = tier.get("unlocks_enemy", [])
	if not ue.is_empty():
		var names := []
		for k in ue:
			names.append(str(k).capitalize() + "s")
		s += "  " + " & ".join(names) + " stalk this Oath."
	return s

func _show_shop() -> void:
	var vbox := _menu_base()
	var hdr := Label.new(); hdr.text = "Armory"; hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_title(hdr, 22)
	vbox.add_child(hdr)
	var gold_row := HBoxContainer.new()
	gold_row.alignment = BoxContainer.ALIGNMENT_CENTER
	gold_row.add_theme_constant_override("separation", 6)
	vbox.add_child(gold_row)
	var coin_icon := TextureRect.new()
	coin_icon.texture = load("res://assets/items/coin.png")
	coin_icon.custom_minimum_size = Vector2(18, 18)
	coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	gold_row.add_child(coin_icon)
	var gold_lbl := Label.new(); gold_lbl.text = "Gold: %d" % GameSave.gold
	UiTheme.style_heading(gold_lbl, UiTheme.GOLD_BRIGHT, 16)
	gold_row.add_child(gold_lbl)
	vbox.add_child(_spacer(8))

	# Upgrades are per-character — a small class-picker row lets the player
	# choose whose track they're viewing/buying (defaults to last-selected).
	var upg_hdr := Label.new(); upg_hdr.text = "Permanent Upgrades"
	UiTheme.style_heading(upg_hdr, UiTheme.GOLD_BRIGHT, 13)
	vbox.add_child(upg_hdr)
	var class_row := HBoxContainer.new()
	class_row.add_theme_constant_override("separation", 6)
	vbox.add_child(class_row)
	for cid in GameData.AVAILABLE_CLASSES:
		var cdef: Dictionary = GameData.CLASSES[cid]
		var cb := Button.new()
		cb.theme = _ui_theme
		cb.text = cdef["name"]
		cb.custom_minimum_size = Vector2(0, 36)
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiTheme.accent_button_style(cb, Color(cdef["color"]), cid == _selected_class)
		cb.pressed.connect(func(): GameAudio.sfx("uiClick"); _selected_class = cid; _show_shop())
		class_row.add_child(cb)
	var scope_lbl := Label.new()
	scope_lbl.text = "Upgrades below apply to the %s only." % GameData.CLASSES[_selected_class]["name"]
	UiTheme.style_muted(scope_lbl, 12)
	vbox.add_child(scope_lbl)
	vbox.add_child(_spacer(6))
	for t in GameData.UPGRADE_TRACKS:
		var id: String = t["id"]
		var lvl: int = GameSave.get_class_upgrade(_selected_class, id)
		var maxed: bool = lvl >= int(t["max"])
		var cost := GameData.upgrade_cost(id, lvl)
		var detail := "Lv %d/%d  ·  %s" % [lvl, int(t["max"]), GameData.upgrade_desc(id, lvl)]
		var value := "Maxed" if maxed else "%d g" % cost
		var row := Ui.stat_row(t["name"], detail, value, not (maxed or GameSave.gold < cost))
		row.pressed.connect(_buy_upgrade.bind(id))
		vbox.add_child(row)

	var unl_hdr := Label.new(); unl_hdr.text = "Unlocks"
	UiTheme.style_heading(unl_hdr, UiTheme.GOLD_BRIGHT, 13)
	vbox.add_child(unl_hdr)
	var any_unlocks := false
	for cid in GameData.CLASSES:
		var c: Dictionary = GameData.CLASSES[cid]
		if c["unlock"]["type"] == "gold" and not GameSave.class_unlocked(cid):
			any_unlocks = true
			_shop_unlock_row(vbox, "%s (class)" % c["name"], int(c["unlock"]["cost"]), _buy_class_unlock.bind(cid, int(c["unlock"]["cost"])))
	for wid in GameData.WEAPON_META:
		var w: Dictionary = GameData.WEAPON_META[wid]
		if w["unlock"]["type"] == "gold" and not GameSave.weapon_unlocked(wid):
			any_unlocks = true
			_shop_unlock_row(vbox, w["name"], int(w["unlock"]["cost"]), _buy_weapon_unlock.bind(wid, int(w["unlock"]["cost"])))
	if not any_unlocks:
		var none_lbl := Label.new(); none_lbl.text = "Everything gold can buy is unlocked."
		UiTheme.style_muted(none_lbl)
		vbox.add_child(none_lbl)

	vbox.add_child(_spacer(10))
	var back_btn := _make_button("Back")
	back_btn.pressed.connect(func(): GameAudio.sfx("uiClick"); _show_title())
	vbox.add_child(back_btn)

func _shop_unlock_row(vbox: VBoxContainer, label: String, cost: int, handler: Callable) -> void:
	var b := Ui.stat_row(label, "", "%d g" % cost, GameSave.gold >= cost)
	b.pressed.connect(handler)
	vbox.add_child(b)

func _buy_upgrade(id: String) -> void:
	var lvl: int = GameSave.get_class_upgrade(_selected_class, id)
	var cost := GameData.upgrade_cost(id, lvl)
	if GameSave.gold >= cost:
		GameSave.gold -= cost
		GameSave.set_class_upgrade(_selected_class, id, lvl + 1)
		GameAudio.sfx("purchase")
		GameSave.save_data()
		_show_shop()

func _buy_class_unlock(cid: String, cost: int) -> void:
	if GameSave.gold >= cost:
		GameSave.gold -= cost
		GameSave.unlocked_classes[cid] = true
		GameAudio.sfx("purchase")
		GameSave.save_data()
		_show_shop()

func _buy_weapon_unlock(wid: String, cost: int) -> void:
	if GameSave.gold >= cost:
		GameSave.gold -= cost
		GameSave.unlocked_weapons[wid] = true
		GameAudio.sfx("purchase")
		GameSave.save_data()
		_show_shop()

func _show_achievements() -> void:
	var vbox := _menu_base()
	vbox.add_child(Ui.header("Deeds", Ui.H1))
	for a in GameData.ACHIEVEMENTS:
		var done: bool = bool(GameSave.achievements.get(a["id"], false))
		var card := Ui.panel()
		var col: VBoxContainer = card["column"]
		var title_row := Label.new()
		title_row.text = ("✓ " if done else "") + a["name"]
		UiTheme.style_heading(title_row, UiTheme.GOLD_BRIGHT if done else UiTheme.INK, 16)
		col.add_child(title_row)
		col.add_child(Ui.body(a["desc"], Ui.SMALL))
		var unlocks := Label.new(); unlocks.text = "Unlocks: %s" % a["unlocks"]
		UiTheme.style_heading(unlocks, UiTheme.GOLD, 12)
		col.add_child(unlocks)
		vbox.add_child(card["panel"])
	vbox.add_child(_spacer(Ui.SP_S))
	var back_btn := _make_button("Back")
	back_btn.pressed.connect(func(): GameAudio.sfx("uiClick"); _show_title())
	vbox.add_child(back_btn)

func _return_to_title() -> void:
	GameAudio.sfx("uiClick")
	if _end_ui:
		_end_ui.queue_free(); _end_ui = null
	get_tree().paused = false
	_clear_run()
	_show_title()

# ── Pause + Settings (ported from togglePause()/pause-screen/settings-screen
# in js/game.js) ────────────────────────────────────────────────────────────
func _open_pause() -> void:
	if _state != "playing" or get_tree().paused:
		return
	get_tree().paused = true
	_show_pause()

func _show_pause() -> void:
	if _pause_ui:
		_pause_ui.queue_free(); _pause_ui = null
	var vbox := _dialog("Paused", 300)
	_pause_ui = _dialog_layer
	var resume_btn := _make_button("Resume", true)
	resume_btn.pressed.connect(func(): GameAudio.sfx("uiClick"); _resume_from_pause())
	vbox.add_child(resume_btn)
	var settings_btn := _make_button("Settings")
	settings_btn.pressed.connect(func(): GameAudio.sfx("uiClick"); _show_settings(_show_pause))
	vbox.add_child(settings_btn)
	var quit_btn := _make_button("Quit to Title")
	quit_btn.pressed.connect(func(): GameAudio.sfx("uiClick"); _quit_run())
	vbox.add_child(quit_btn)

# Builds a centered dialog overlay (backdrop + ornate panel + Cinzel title) and
# returns the content column to fill. The created CanvasLayer is stashed in
# _dialog_layer for the caller to assign to its own _pause_ui/_settings_ui/etc.
var _dialog_layer: CanvasLayer
func _dialog(title: String, min_w: int) -> VBoxContainer:
	var o := Ui.overlay(self, _ui_theme, true, true)
	_dialog_layer = o["layer"]
	var p := Ui.panel(true)
	o["column"].add_child(p["panel"])
	var col: VBoxContainer = p["column"]
	col.custom_minimum_size = Vector2(min_w, 0)
	col.add_theme_constant_override("separation", Ui.SP_M)
	col.add_child(Ui.header(title, Ui.H1))
	col.add_child(Ui.spacer(Ui.SP_S))
	return col

func _resume_from_pause() -> void:
	if _pause_ui:
		_pause_ui.queue_free(); _pause_ui = null
	get_tree().paused = false

# Abandons the run without persisting gold/kills/achievements (ported from
# quit-btn in js/game.js, distinct from _return_to_title which only follows a
# completed run where _end_run already saved everything).
func _quit_run() -> void:
	GameAudio.stop_music()
	if _pause_ui:
		_pause_ui.queue_free(); _pause_ui = null
	get_tree().paused = false
	_clear_run()
	_show_title()

func _show_settings(return_fn: Callable) -> void:
	_clear_menu()
	if _pause_ui:
		_pause_ui.queue_free(); _pause_ui = null
	if _settings_ui:
		_settings_ui.queue_free(); _settings_ui = null
	var vbox := _dialog("Settings", 340)
	var layer := _dialog_layer
	_settings_ui = layer
	var vol_lbl := Label.new(); vol_lbl.text = "Volume"
	UiTheme.style_muted(vol_lbl, Ui.BODY)
	vbox.add_child(vol_lbl)
	var slider := HSlider.new()
	slider.min_value = 0; slider.max_value = 100; slider.step = 1
	slider.value = GameSave.volume * 100.0
	slider.custom_minimum_size = Vector2(0, 32)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(_on_volume_changed)
	vbox.add_child(slider)
	var mute_btn := _make_button("Muted" if GameSave.muted else "Sound On")
	mute_btn.pressed.connect(_toggle_mute.bind(mute_btn))
	vbox.add_child(mute_btn)
	vbox.add_child(_spacer(Ui.SP_S))
	var back_btn := _make_button("Back")
	back_btn.pressed.connect(func():
		GameAudio.sfx("uiClick")
		if _settings_ui == layer:
			layer.queue_free(); _settings_ui = null
		return_fn.call())
	vbox.add_child(back_btn)

func _on_volume_changed(v: float) -> void:
	GameSave.volume = v / 100.0
	GameAudio.set_volume(GameSave.volume)
	GameSave.save_data()

func _toggle_mute(btn: Button) -> void:
	GameSave.muted = not GameSave.muted
	GameAudio.set_muted(GameSave.muted)
	GameSave.save_data()
	GameAudio.sfx("uiClick")
	btn.text = "Muted" if GameSave.muted else "Sound On"

func add_gold(amount: float) -> void:
	run_gold += amount

func add_kill() -> void:
	run_kills += 1

func _process(delta: float) -> void:
	# Real-clock hit-stop recovery — runs before any early-out and reads the real
	# clock (not the frozen game delta), so time_scale always returns to 1.0.
	if _hitstop_end_ms > 0 and Time.get_ticks_msec() >= _hitstop_end_ms:
		Engine.time_scale = 1.0
		_hitstop_end_ms = 0
	if _player == null or not is_instance_valid(_player):
		return
	if _state != "playing":
		return
	elapsed += delta
	_player.move_dir = _test_dir if _testing else _read_input()

	# Spawn director: interval tightens over the run; normal spawns pause during
	# the final boss fight (ported from js/game.js).
	var boss_active_final: bool = _boss != null and is_instance_valid(_boss) and _boss.is_final
	if not boss_active_final:
		_spawn_timer -= delta
		# Softened from max(0.16, 1.1 - elapsed*0.01): starts slower (1.4s vs
		# 1.1s) and takes ~2.5min instead of ~1.5min to reach a (slower) floor.
		# Higher difficulty tiers tighten the interval (spawn_mult > 1).
		var interval: float = max(0.22, 1.4 - elapsed * 0.008) / float(_active_tier.get("spawn_mult", 1.0))
		if _spawn_timer <= 0.0:
			_spawn_enemy()
			_spawn_timer = interval

	# Boss timeline: mini-bosses at fixed times, the final boss at _win_time.
	while _next_mini < _mini_times.size() and elapsed >= _mini_times[_next_mini]:
		spawn_boss("miniboss")
		_next_mini += 1
	if not _final_spawned and elapsed >= _win_time:
		spawn_boss("finalboss")
		_final_spawned = true

	if _banner_timer > 0.0:
		_banner_timer -= delta

	# Low-HP heartbeat pulse (ported from js/game.js).
	if _player.hp / _player.max_hp < 0.3 and elapsed - _last_beat > 0.65:
		_last_beat = elapsed
		GameAudio.sfx("heartbeat")

	_update_visuals(delta)
	_update_hud()

# Screen shake, torch flicker, level-up/pickup flash, low-HP vignette — ported
# from the shake/flash/torchFlicker/litR/vignette block in js/game.js's
# update()+render().
func _update_visuals(delta: float) -> void:
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 36.0)
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 2.0)

	_camera.offset = Vector2(randf_range(-0.8, 0.8), randf_range(-0.8, 0.8)) * _shake if _shake > 0.0 else Vector2.ZERO

	# Torch flicker only matters on stages that actually use the overlay
	# (see per-stage lighting in _rebuild_stage).
	if _torch_overlay.visible:
		var torch_flicker := sin(elapsed * 9.0) * 5.0 + sin(elapsed * 23.0) * 3.0
		var lit_r := maxf(245.0, minf(get_viewport_rect().size.x, get_viewport_rect().size.y) * 0.6) + torch_flicker
		# The player is always at screen-center (instant 1:1 camera follow), so the
		# overlay's fixed screen-center position never needs updating — only scale
		# reproduces the flicker.
		_torch_overlay.scale = Vector2.ONE * (lit_r / _TORCH_BASE_RADIUS)

	_flash_overlay.color.a = minf(0.5, _flash) * 0.5

	var hp_frac := _player.hp / _player.max_hp
	if hp_frac < 0.3:
		var pulse := 0.35 + sin(elapsed * 7.0) * 0.15
		_vignette.modulate.a = clampf(((0.3 - hp_frac) / 0.3) * pulse, 0.0, 1.0)
	else:
		_vignette.modulate.a = 0.0

func spawn_boss(key: String) -> void:
	var dist := maxf(get_viewport_rect().size.x, get_viewport_rect().size.y) * 0.55 + 60.0
	var pos := _find_spawn_pos(_player.global_position, dist)
	_boss = add_enemy(key, pos, 1.0 + (elapsed / 60.0) * 0.06)
	_flash = 0.6
	add_shake(8.0)
	GameAudio.sfx("levelup")
	Vfx.ring(_world, pos, Color("ff6a5a") if key == "finalboss" else Color("b14a8a"), 90.0, 0.6)
	_show_banner("The Warden Awakens" if key == "finalboss" else "A Champion Approaches")

func _show_banner(text: String) -> void:
	_banner_text = text
	_banner_timer = 2.6

func on_boss_killed(e: Node) -> void:
	if _boss == e:
		_boss = null
	if e.is_final:
		_trigger_victory()
	else:
		_player.hp = min(_player.max_hp, _player.hp + 25.0)
		_show_banner("Champion Slain!")

func _spawn_enemy() -> void:
	var m := elapsed / 60.0
	var key := _weighted_archetype(m)
	var dist := maxf(get_viewport_rect().size.x, get_viewport_rect().size.y) * 0.6 + 40.0
	var pos := _find_spawn_pos(_player.global_position, dist)
	var e: Node = add_enemy(key, pos, 1.0 + m * 0.25)
	# Occasional elite (ported from js/game.js spawnEnemy). Softened: starts
	# later (1.5min vs 1min) and less often (4.5% vs 6%).
	if m > 1.5 and randf() < 0.045:
		e.elite = true
		e.hp *= 3.2; e.max_hp = e.hp; e.radius *= 1.3; e.dmg *= 1.4; e.gold *= 4.0; e.xp *= 3.0

func _weighted_archetype(m: float) -> String:
	# Tougher archetypes are pushed back slightly so the opening stretch
	# stays skeletons/goblins a bit longer before shooters/exploders/etc. mix in.
	var choices := [
		["skeleton", 10.0], ["goblin", 3.0 + m], ["ogre", maxf(0.0, m - 0.8)],
		["shooter", maxf(0.0, m - 1.3) * 1.2], ["exploder", maxf(0.0, m - 1.8) * 1.1],
		["splitter", maxf(0.0, m - 2.3)], ["charger", maxf(0.0, m - 2.8)],
	]
	# Roster gate: chargers/splitters only stalk tiers that unlock them, so lower
	# difficulties stay a gentler mix (not just weaker numbers).
	var gated := ["charger", "splitter"]
	var allowed: Array = _active_tier.get("unlocks_enemy", [])
	for c in choices:
		if gated.has(c[0]) and not allowed.has(c[0]):
			c[1] = 0.0
	var total := 0.0
	for c in choices: total += c[1]
	var roll := randf() * total
	for c in choices:
		roll -= c[1]
		if roll <= 0.0:
			return c[0]
	return "skeleton"

# ── Combat ctx the enemies/projectiles call back into ─────────────────────────
func add_enemy(key: String, pos: Vector2, scale_mult: float) -> Node:
	var e := preload("res://scripts/Enemy.gd").new()
	e.setup(key, scale_mult)
	# Difficulty tier scales enemy durability + damage on top of the in-run ramp
	# (applies to bosses too, since they spawn through here).
	e.hp *= float(_active_tier.get("hp_mult", 1.0)); e.max_hp = e.hp
	e.dmg *= float(_active_tier.get("dmg_mult", 1.0))
	e.global_position = pos
	_world.add_child(e)
	return e

func spawn_enemy_projectile(pos: Vector2, vel: Vector2, dmg: float, col: Color) -> void:
	var pr := preload("res://scripts/EnemyProjectile.gd").new()
	pr.setup(pos, vel, dmg, col)
	_world.add_child(pr)

func hurt_area(pos: Vector2, r: float, amount: float) -> void:
	if _player and _player.global_position.distance_to(pos) < r + _player.radius():
		_player.take_damage(amount)

# Weapon/ability combat ctx (ported from makeCtx in js/game.js).
func nearest_enemy_to(pos: Vector2) -> Node2D:
	var best: Node2D = null
	var bd := INF
	for e in get_tree().get_nodes_in_group("enemies"):
		var d: float = pos.distance_squared_to(e.global_position)
		if d < bd:
			bd = d; best = e
	return best

func dir_to_nearest(pos: Vector2) -> float:
	var t := nearest_enemy_to(pos)
	return (t.global_position - pos).angle() if t != null else randf() * TAU

func area_damage(center: Vector2, radius: float, mult: float, opts: Dictionary) -> void:
	# Reach passive: the player's area multiplier widens direct-cast blasts.
	area_damage_amount(center, radius * _player.aoe_mult, _player.damage * mult, opts)

## Same as area_damage() but takes an absolute damage amount instead of a
## multiplier on the player's damage stat — used by abilities that deal
## damage from a spawned object (traps, zones, telegraphed strikes) where
## the amount was already computed at cast time.
func area_damage_amount(center: Vector2, radius: float, dmg: float, opts: Dictionary) -> void:
	var crit: bool = opts.get("crit", false)
	for e in get_tree().get_nodes_in_group("enemies"):
		var off: Vector2 = e.global_position - center
		if off.length() <= radius + e.radius:
			e.take_damage(dmg, crit)
			if opts.has("slow"):
				e.apply_slow(opts["slow"])
			if opts.has("burn_dps"):
				e.apply_burn(opts["burn_dps"], opts.get("burn_time", 2.0))
			if opts.has("knockback"):
				var d := off.length()
				if d > 0.0:
					e.global_position += off / d * opts["knockback"] * 0.06

## Instant line hitscan (Knight's Spear Impale, Mage's Arcane Beam) — damages
## every foe within `width`/2 of the segment from origin along dir for length.
func line_damage(origin: Vector2, dir: Vector2, length: float, width: float, dmg: float, opts: Dictionary) -> void:
	var d := dir.normalized()
	# Reach passive widens (and slightly lengthens) piercing lines too.
	width *= _player.aoe_mult
	length *= 1.0 + (_player.aoe_mult - 1.0) * 0.5
	var crit: bool = opts.get("crit", false)
	for e in get_tree().get_nodes_in_group("enemies"):
		var off: Vector2 = e.global_position - origin
		var along := off.dot(d)
		if along < -e.radius or along > length + e.radius:
			continue
		var perp := (off - d * along).length()
		if perp <= width * 0.5 + e.radius:
			e.take_damage(dmg, crit)
			if opts.has("slow"):
				e.apply_slow(opts["slow"])
	if opts.has("color"):
		var world := get_node("World")
		Vfx.chain_link(world, origin, origin + d * length, opts["color"], opts.get("vfx_width", 4.0), 0.15)

## Knight's Taunt Roar — pulls nearby foes toward origin and marks them so
## all subsequent damage they take (from anything) is multiplied.
func pull_and_mark(origin: Vector2, radius: float, pull_speed: float, mark_mult: float, mark_dur: float) -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		var off: Vector2 = origin - e.global_position
		var d := off.length()
		if d <= radius and d > 4.0:
			e.global_position += off / d * pull_speed * 0.06
		if d <= radius:
			e.marked_until = elapsed + mark_dur
			e.marked_mult = mark_mult

func spawn_trap(pos: Vector2, trigger_radius: float, blast_radius: float, dmg: float, color: Color) -> void:
	var t := preload("res://scripts/TrapMine.gd").new()
	t.global_position = pos
	t.trigger_radius = trigger_radius; t.blast_radius = blast_radius; t.dmg = dmg; t.color = color
	_world.add_child(t)

func spawn_zone(pos: Vector2, radius: float, dps: float, duration: float, color: Color) -> void:
	var z := preload("res://scripts/DamageZone.gd").new()
	z.global_position = pos
	z.radius = radius; z.dps = dps; z.duration = duration; z.color = color
	_world.add_child(z)

func spawn_homing(pos: Vector2, dir: Vector2, speed: float, dmg: float, crit: bool, r: float, color: Color, slow: float = 0.0) -> void:
	var h := preload("res://scripts/HomingProjectile.gd").new()
	h.setup(pos, dir, speed, dmg, crit, r, color, slow)
	_world.add_child(h)

func spawn_bounce(pos: Vector2, vel: Vector2, dmg: float, crit: bool, bounces: int, r: float, color: Color) -> void:
	var b := preload("res://scripts/BounceProjectile.gd").new()
	b.setup(pos, vel, dmg, crit, bounces, r, color)
	_world.add_child(b)

func spawn_telegraph(pos: Vector2, radius: float, dmg: float, delay: float, color: Color) -> void:
	var s := preload("res://scripts/TelegraphStrike.gd").new()
	s.global_position = pos
	s.radius = radius; s.dmg = dmg; s.delay = delay; s.color = color
	_world.add_child(s)

func spawn_player_projectile(pos: Vector2, vel: Vector2, dmg: float, crit: bool, pierce: int, r: float, col: Color, on_hit := Callable()) -> void:
	var pr := preload("res://scripts/Projectile.gd").new()
	pr.setup(pos, vel, dmg, crit, pierce, r, col, on_hit)
	_world.add_child(pr)

func _trigger_victory() -> void:
	if _state != "playing":
		return
	_state = "won"
	_end_run("Victory!", true)

# ── Level-up: pick an ability (ported from openLevelUp in js/game.js) ──────────
func _on_level_up() -> void:
	_pending_levels += 1
	if not _leveling:
		_open_level_up()

func _open_level_up() -> void:
	while _pending_levels > 0:
		_flash = 0.5
		GameAudio.sfx("levelup")
		Vfx.ring(_world, _player.global_position, UiTheme.GOLD_BRIGHT, 70.0, 0.45)
		var opts := Abilities.roll(_player.cls_id, _player.owned_ranks(), 5)
		if opts.is_empty():
			_player.hp = min(_player.max_hp, _player.hp + 30.0)
			_pending_levels -= 1
			continue
		if _auto_pick:
			_player.apply_pick(opts[0])
			_pending_levels -= 1
			continue
		_leveling = true
		_clear_hitstop()   # never freeze time while the (paused) card UI is up
		get_tree().paused = true
		_build_level_cards(opts)
		return
	_leveling = false
	get_tree().paused = false

func _build_level_cards(opts: Array) -> void:
	var o := Ui.overlay(self, _ui_theme, true, false)   # scrollable: never clip cards
	_level_ui = o["layer"]
	var p := Ui.panel(true)
	o["column"].add_child(p["panel"])
	var vbox: VBoxContainer = p["column"]
	vbox.add_theme_constant_override("separation", Ui.SP_M)
	vbox.add_child(Ui.header("Level Up", Ui.H1))
	vbox.add_child(Ui.body("Level %d" % _player.level, Ui.SMALL, true))
	for opt in opts:
		vbox.add_child(_level_card(opt))

# One ability choice, built as a content-sized accent panel with a transparent
# click target on top — so the card grows to fit the description (short or long)
# instead of clipping it inside a fixed-height button.
func _level_card(opt: Dictionary) -> Control:
	var def: Dictionary = opt["ability"]
	var is_new: bool = opt["is_new"]
	var is_evo: bool = opt.get("is_evo", false)
	var is_keystone: bool = opt.get("is_keystone", false)
	var accent: Color
	if is_evo:
		accent = UiTheme.GOLD_BRIGHT
	elif is_keystone:
		accent = Color(def["color"])   # themed accent (fire = orange, movement = green)
	elif is_new:
		accent = UiTheme.GOLD
	else:
		accent = UiTheme.XP_COLOR
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(UiTheme.STONE2.r, UiTheme.STONE2.g, UiTheme.STONE2.b, 0.92)
	cs.border_color = accent
	cs.set_border_width_all(1)
	cs.set_corner_radius_all(6)
	cs.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", cs)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	var icon := TextureRect.new()
	var icon_path := "res://assets/icons/abilities/%s.png" % def.get("icon_key", def["mech"])
	if ResourceLoader.exists(icon_path):
		icon.texture = load(icon_path)
	icon.modulate = Color(def["color"])
	icon.custom_minimum_size = Vector2(36, 36)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)

	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override("separation", 2)
	row.add_child(text_col)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 6)
	text_col.add_child(title_row)
	var name_lbl := Label.new()
	name_lbl.text = def["name"]
	UiTheme.style_heading(name_lbl, accent, 15)
	title_row.add_child(name_lbl)
	var tag_lbl := Label.new()
	if is_evo:
		tag_lbl.text = "Evolved"
	elif is_keystone:
		tag_lbl.text = "Keystone"
	elif is_new:
		tag_lbl.text = "New"
	else:
		tag_lbl.text = "Rank %d → %d" % [opt["next_rank"] - 1, opt["next_rank"]]
	tag_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiTheme.style_muted(tag_lbl, 11)
	title_row.add_child(tag_lbl)
	var desc_lbl := Label.new()
	desc_lbl.text = Abilities.describe(def, opt["next_rank"])
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	UiTheme.style_muted(desc_lbl, 12)
	text_col.add_child(desc_lbl)

	var hit := Button.new()
	hit.set_anchors_preset(Control.PRESET_FULL_RECT)
	for s in ["normal", "hover", "pressed", "focus", "disabled"]:
		hit.add_theme_stylebox_override(s, StyleBoxEmpty.new())
	hit.pressed.connect(_pick_ability.bind(opt))
	card.add_child(hit)
	return card

func _pick_ability(opt: Dictionary) -> void:
	GameAudio.sfx("uiClick")
	_player.apply_pick(opt)
	if _level_ui: _level_ui.queue_free(); _level_ui = null
	_pending_levels -= 1
	_open_level_up()

# ── Input: touch joystick (falls back to mouse) + WASD/arrows ─────────────────
func _read_input() -> Vector2:
	if _joy_active:
		return _joy_vec
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): v.x += 1
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): v.x -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): v.y += 1
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): v.y -= 1
	return v

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and not _joy_active:
			_joy_active = true; _joy_id = event.index; _joy_base = event.position; _joy_vec = Vector2.ZERO
		elif not event.pressed and event.index == _joy_id:
			_joy_active = false; _joy_id = -1; _joy_vec = Vector2.ZERO
	elif event is InputEventScreenDrag and event.index == _joy_id:
		_joy_vec = (event.position - _joy_base) / 50.0
	elif event is InputEventMouseButton:
		if event.pressed:
			_joy_active = true; _joy_base = event.position; _joy_vec = Vector2.ZERO
		else:
			_joy_active = false; _joy_vec = Vector2.ZERO
	elif event is InputEventMouseMotion and _joy_active:
		_joy_vec = (event.position - _joy_base) / 50.0
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_SPACE:
		if _player: _player.use_movement_ability()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		# Only opens pause: once paused, Main._input() stops firing (default
		# PROCESS_MODE_PAUSABLE), so closing is via the always-on-mode Resume
		# button inside _pause_ui — matching js/game.js's Escape/pause-btn split.
		if _state == "playing" and not get_tree().paused:
			_open_pause()
	_sync_joy_visual()

# Mirrors the joystick ring/knob onto JoystickVisual (ported from the
# `if (joy.active) {...}` draw block in js/game.js's render()); the knob is
# clamped to the ring radius exactly like the JS's `cl = min(d, max)`.
func _sync_joy_visual() -> void:
	if not _joy_visual:
		return
	_joy_visual.active = _joy_active
	_joy_visual.base = _joy_base
	_joy_visual.knob = _joy_base + (_joy_vec * 50.0).limit_length(50.0)

# ── HUD ───────────────────────────────────────────────────────────────────────
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	# Torch darkness: a dark radial gradient drawn ON TOP of the fully-rendered
	# world (never multiplicatively hides anything under it, unlike
	# CanvasModulate) — ported from the torchFlicker/litR radial-gradient
	# overlay in js/game.js's render(). Colors/stops match the JS exactly.
	# fill_to_dist=0.15 on a 1920px-wide texture puts the gradient's outer stop
	# at 0.15*1920 = 288px = _TORCH_BASE_RADIUS from center at scale 1.0; the
	# rest of the 1920px extent (well past any phone screen's corner distance)
	# stays clamped at the fully-dark outer color, exactly like a canvas
	# radial gradient. Scaling the whole rect at runtime (cheap, no texture
	# regen) reproduces the torchFlicker radius wobble.
	_torch_overlay = TextureRect.new()
	_torch_overlay.texture = _make_multistop_gradient_texture(
		Vector2(1920, 1920),
		[0.0, 0.55, 0.85, 1.0],
		[Color(10.0 / 255, 8.0 / 255, 6.0 / 255, 0.0), Color(10.0 / 255, 8.0 / 255, 6.0 / 255, 0.12),
		 Color(9.0 / 255, 7.0 / 255, 5.0 / 255, 0.62), Color(7.0 / 255, 6.0 / 255, 4.0 / 255, 0.97)],
		0.15)
	_torch_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_torch_overlay.size = Vector2(1920, 1920)
	_torch_overlay.pivot_offset = Vector2(960, 960)
	_torch_overlay.position = Vector2(240, 400) - Vector2(960, 960)
	layer.add_child(_torch_overlay)

	_joy_visual = preload("res://scripts/JoystickVisual.gd").new()
	layer.add_child(_joy_visual)

	# Low-HP vignette (behind the flash/HUD, above the game world).
	_vignette = TextureRect.new()
	_vignette.texture = _make_radial_gradient_texture(Vector2(480, 800), Color(0.667, 0.078, 0.078, 0.0), Color(0.588, 0.039, 0.039, 1.0))
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.modulate.a = 0.0
	layer.add_child(_vignette)

	# Level-up / pickup flash.
	_flash_overlay = ColorRect.new()
	_flash_overlay.color = Color(1.0, 0.98, 0.9, 0.0)
	_flash_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_flash_overlay)

	# HUD is laid out with anchored corner clusters (no hardcoded coordinates):
	# top-left = level/gold/HP/XP/abilities, top-right = time+pause,
	# bottom-right = movement ability, top-center = boss bar + banner.
	var topleft := VBoxContainer.new()
	topleft.set_anchors_preset(Control.PRESET_TOP_LEFT)
	topleft.offset_left = 10; topleft.offset_top = 8
	topleft.add_theme_constant_override("separation", 4)
	topleft.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(topleft)

	_lbl_level = Label.new()
	_lbl_level.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.style_heading(_lbl_level, UiTheme.INK, 18)
	topleft.add_child(_lbl_level)
	_lbl_gold = Label.new()
	_lbl_gold.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.style_heading(_lbl_gold, UiTheme.GOLD_BRIGHT, 14)
	topleft.add_child(_lbl_gold)

	var hp := Ui.framed_bar(UiTheme.HP_COLOR, _hp_w, 14)
	_hp_fill = hp["fill"]
	topleft.add_child(hp["root"])
	var xp := Ui.framed_bar(UiTheme.XP_COLOR, _xp_w, 8)
	_xp_fill = xp["fill"]
	topleft.add_child(xp["root"])

	# Ability header: icon + rank badge per owned ability (refreshed on change).
	_ability_header = HFlowContainer.new()
	_ability_header.custom_minimum_size = Vector2(_hp_w, 0)
	_ability_header.add_theme_constant_override("h_separation", 4)
	_ability_header.add_theme_constant_override("v_separation", 4)
	topleft.add_child(_ability_header)

	var topright := HBoxContainer.new()
	topright.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	topright.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	topright.offset_top = 6; topright.offset_right = -10
	topright.add_theme_constant_override("separation", 8)
	layer.add_child(topright)
	_lbl_time = Label.new()
	UiTheme.style_heading(_lbl_time, UiTheme.GOLD_BRIGHT, 18)
	topright.add_child(_lbl_time)
	var pause_btn := Ui.button("||", "", false, 34)
	pause_btn.custom_minimum_size = Vector2(48, 34)
	pause_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	pause_btn.pressed.connect(func(): GameAudio.sfx("uiClick"); _open_pause())
	topright.add_child(pause_btn)

	var ab_btn := Ui.button("*", "", false, 72)
	ab_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ab_btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ab_btn.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ab_btn.custom_minimum_size = Vector2(72, 72)
	ab_btn.offset_right = -12; ab_btn.offset_bottom = -12
	ab_btn.add_theme_font_size_override("font_size", 26)
	ab_btn.pressed.connect(func(): if _player: _player.use_movement_ability())
	layer.add_child(ab_btn)

	var topcenter := VBoxContainer.new()
	topcenter.set_anchors_preset(Control.PRESET_CENTER_TOP)
	topcenter.grow_horizontal = Control.GROW_DIRECTION_BOTH
	topcenter.offset_top = 92
	topcenter.alignment = BoxContainer.ALIGNMENT_CENTER
	topcenter.add_theme_constant_override("separation", 4)
	topcenter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(topcenter)
	_lbl_boss_name = Label.new()
	_lbl_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_boss_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.style_heading(_lbl_boss_name, UiTheme.MUTED, 13)
	_lbl_boss_name.visible = false
	topcenter.add_child(_lbl_boss_name)
	var boss := Ui.framed_bar(Color("b14a8a"), _boss_w, 12)
	_boss_bar = boss["root"]; _boss_fill = boss["fill"]
	_boss_bar.visible = false
	topcenter.add_child(_boss_bar)
	_lbl_banner = Label.new()
	_lbl_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lbl_banner.autowrap_mode = TextServer.AUTOWRAP_WORD
	_lbl_banner.custom_minimum_size = Vector2(440, 0)
	UiTheme.style_title(_lbl_banner, 24)
	_lbl_banner.visible = false
	topcenter.add_child(_lbl_banner)

func _bar_bg_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0.55)
	s.set_corner_radius_all(6)
	return s

func _badge_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(UiTheme.STONE2.r, UiTheme.STONE2.g, UiTheme.STONE2.b, 0.85)
	s.border_color = UiTheme.BORDER
	s.set_border_width_all(1)
	s.set_corner_radius_all(5)
	s.content_margin_left = 4; s.content_margin_right = 5
	s.content_margin_top = 2; s.content_margin_bottom = 2
	return s

func _refresh_ability_header() -> void:
	for c in _ability_header.get_children():
		c.queue_free()
	for s in _player.skills:
		var def := Abilities.by_id(s["id"])
		var badge := PanelContainer.new()
		badge.add_theme_stylebox_override("panel", _badge_style())
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 3)
		badge.add_child(row)
		var icon := TextureRect.new()
		var icon_path := "res://assets/icons/abilities/%s.png" % def.get("icon_key", def["mech"])
		if ResourceLoader.exists(icon_path):
			icon.texture = load(icon_path)
		icon.modulate = Color(def["color"])
		icon.custom_minimum_size = Vector2(16, 16)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		var lbl := Label.new()
		lbl.text = "%d" % s["rank"]
		UiTheme.style_muted(lbl, 11)
		row.add_child(lbl)
		_ability_header.add_child(badge)

func _update_hud() -> void:
	_lbl_level.text = "Lv %d" % _player.level
	_lbl_time.text = "%d:%02d" % [int(elapsed) / 60, int(elapsed) % 60]
	_lbl_gold.text = "Gold: %d" % int(floor(run_gold))
	_hp_fill.size.x = (_hp_w - 4.0) * clampf(_player.hp / _player.max_hp, 0.0, 1.0)
	_xp_fill.size.x = (_xp_w - 4.0) * clampf(_player.xp / _player.xp_next, 0.0, 1.0)

	var sig := ""
	for s in _player.skills: sig += "%s:%d," % [s["id"], s["rank"]]
	if sig != _ability_header_sig:
		_ability_header_sig = sig
		_refresh_ability_header()

	var boss_live: bool = _boss != null and is_instance_valid(_boss) and _boss.hp > 0.0
	_boss_bar.visible = boss_live; _lbl_boss_name.visible = boss_live
	if boss_live:
		_lbl_boss_name.text = "The Warden" if _boss.is_final else "Champion"
		_boss_fill.size.x = (_boss_w - 4.0) * clampf(_boss.hp / _boss.max_hp, 0.0, 1.0)

	_lbl_banner.visible = _banner_timer > 0.0
	if _banner_timer > 0.0:
		_lbl_banner.text = _banner_text
		_lbl_banner.modulate.a = clampf(_banner_timer / 0.5, 0.0, 1.0)

func _on_player_died() -> void:
	if _state != "playing":
		return
	if _try_revive():
		return
	Vfx.burst(_world, _player.global_position, Color("c0473f"), 20, 180.0, 0.6, 4.0)
	_state = "dead"
	_end_run("You Died")

# Second-chance revive (ported from revivePlayer in js/game.js): consumes a
# Revive charge, heals to half, and shoves back (and damages) the nearby swarm.
func _try_revive() -> bool:
	if _player.revives <= 0:
		return false
	_player.revives -= 1
	_player.hp = roundf(_player.max_hp * 0.5)
	_player.invuln = 2.5
	_flash = 0.6
	add_shake(8.0)
	GameAudio.sfx("levelup")
	Vfx.ring(_world, _player.global_position, UiTheme.GOLD_BRIGHT, 220.0, 0.5)
	_show_banner("Second Wind!")
	for e in get_tree().get_nodes_in_group("enemies"):
		var off: Vector2 = e.global_position - _player.global_position
		var d := off.length()
		if d < 210.0:
			var dir: Vector2 = off / maxf(d, 1.0)
			e.global_position += dir * 230.0
			if not e.is_boss:
				e.take_damage(e.max_hp, false)
	return true

# Persists run results to GameSave (ported from the shared tail of die()/
# victory() in js/game.js) and shows the death/victory screen.
func _end_run(title: String, won: bool = false) -> void:
	_clear_hitstop()
	get_tree().paused = true
	GameAudio.stop_music()
	if won:
		GameAudio.sfx("levelup")
	var fresh := _check_run_achievements()
	# Winning clears the stage at the chosen tier; surface anything it unlocks.
	var unlock_lines: Array = []
	if won:
		var before_stage := {}
		for s in GameData.STAGES:
			before_stage[s["id"]] = GameSave.stage_unlocked(s["id"])
		var before_tier: String = GameSave.unlocked_tier
		GameSave.mark_stage_cleared(_active_stage["id"], _active_tier["id"])
		for s in GameData.STAGES:
			if not before_stage[s["id"]] and GameSave.stage_unlocked(s["id"]):
				unlock_lines.append("New Realm — %s" % s["name"])
		if GameSave.unlocked_tier != before_tier:
			unlock_lines.append("New Oath — %s" % GameData.difficulty_by_id(GameSave.unlocked_tier).get("name", ""))
	GameSave.gold += int(floor(run_gold))
	GameSave.total_kills += run_kills
	GameSave.class_kills[_player.cls_id] = int(GameSave.class_kills.get(_player.cls_id, 0)) + run_kills
	if elapsed > GameSave.best_time:
		GameSave.best_time = elapsed
	GameSave.save_data()
	_show_end_screen(title, fresh, unlock_lines)

func _check_run_achievements() -> Array:
	var merged_kills: Dictionary = GameSave.class_kills.duplicate()
	merged_kills[_player.cls_id] = int(merged_kills.get(_player.cls_id, 0)) + run_kills
	var stats := {
		"time": elapsed, "level": float(_player.level),
		"total_kills": float(GameSave.total_kills + run_kills),
		"class_kills": merged_kills,
	}
	var fresh: Array = GameData.check_achievements(stats, GameSave.achievements)
	for id in fresh:
		GameSave.achievements[id] = true
		GameSave.apply_unlock(id)
	return fresh

func _show_end_screen(title: String, fresh: Array, unlock_lines: Array = []) -> void:
	var won := title == "Victory!"
	var o := Ui.overlay(self, _ui_theme, true, true)
	_end_ui = o["layer"]
	var p := Ui.panel(true)
	o["column"].add_child(p["panel"])
	var vbox: VBoxContainer = p["column"]
	vbox.custom_minimum_size = Vector2(300, 0)
	vbox.add_theme_constant_override("separation", Ui.SP_M)
	if won:
		var crest := TextureRect.new()
		crest.texture = load("res://assets/ui/crest.png")
		crest.custom_minimum_size = Vector2(0, 84)
		crest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		vbox.add_child(crest)
	vbox.add_child(Ui.header(title, Ui.H1, UiTheme.GOLD_BRIGHT if won else UiTheme.HP_COLOR))
	vbox.add_child(_spacer(Ui.SP_S))
	var stats := Label.new()
	stats.text = "Time: %d:%02d\nKills: %d\nGold: +%d" % [int(elapsed) / 60, int(elapsed) % 60, run_kills, int(floor(run_gold))]
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_muted(stats, Ui.BODY)
	vbox.add_child(stats)
	if not unlock_lines.is_empty():
		vbox.add_child(_spacer(Ui.SP_S))
		var ol := Label.new(); ol.text = "\n".join(unlock_lines)
		ol.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UiTheme.style_heading(ol, UiTheme.GOLD_BRIGHT, 15)
		vbox.add_child(ol)
	if not fresh.is_empty():
		vbox.add_child(_spacer(Ui.SP_S))
		var lines := ["Unlocked!"]
		for id in fresh:
			var a: Dictionary = GameData.achievement_by_id(id)
			lines.append("%s — %s" % [a["name"], a["unlocks"]])
		var ul := Label.new(); ul.text = "\n".join(lines)
		ul.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UiTheme.style_heading(ul, UiTheme.GOLD_BRIGHT, 14)
		vbox.add_child(ul)
	vbox.add_child(_spacer(Ui.SP_S))
	var btn := _make_button("Continue", true)
	btn.pressed.connect(_return_to_title)
	vbox.add_child(btn)

# ── Headless self-test ────────────────────────────────────────────────────────
func _run_selftest() -> void:
	# Drive the player in a slow circle so combat/animation actually exercise.
	_testing = true
	_auto_pick = true   # auto-pick level-up cards (no UI in headless)
	# Force one of every archetype so all AI branches run at least once.
	for key in ["shooter", "exploder", "splitter", "charger", "ogre", "miniboss", "finalboss"]:
		add_enemy(key, _player.global_position + Vector2(randf_range(-180, 180), randf_range(-180, 180)), 1.0)
	# Grant every Knight/Archer/Mage ability so all activate() branches run
	# (abilities are class-agnostic in code — any def works on any player).
	for aid in ["kn_bash", "kn_slam", "kn_lance", "kn_taunt", "kn_barrier", "kn_whirl", "kn_charge", "kn_step",
			"ar_multi", "ar_snipe", "ar_trap", "ar_mark", "ar_bombard", "ar_ricochet", "ar_retreat", "ar_focus",
			"mg_firenova", "mg_meteor", "mg_cinder", "mg_frostbolt", "mg_chain", "mg_beam", "mg_surge", "mg_shield"]:
		_player.apply_pick({"ability": Abilities.by_id(aid), "next_rank": 1, "is_new": true})
	# Fire every weapon once so all four patterns (melee/projectile/nova/orbital) run.
	for wid in GameData.WEAPON_META:
		if GameData.WEAPON_META[wid]["type"] == "orbital":
			Weapons.init_weapon(wid, _player)
		else:
			_player.weapon_id = wid
			Weapons.fire(wid, _player, self)
	var t := 0.0
	var next_ability := 1.0
	while t < 8.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		_test_dir = Vector2(cos(t), sin(t * 0.7))
		if t > next_ability:
			_player.use_movement_ability()
			next_ability += 1.5
	var enemies := get_tree().get_nodes_in_group("enemies").size()
	var projectiles := 0
	for c in _world.get_children():
		if c.get_script() == preload("res://scripts/Projectile.gd"):
			projectiles += 1
	var gems := 0
	for c in _world.get_children():
		if c.get_script() == preload("res://scripts/Gem.gd"):
			gems += 1
	# The player now has a CollisionShape2D child too, so find the sprite by
	# type rather than assuming a fixed child index.
	var sprite_ok := false
	for c in _player.get_children():
		if c is Sprite2D and c.texture != null:
			sprite_ok = true
			break
	print("[SELFTEST] elapsed=%.1f hp=%.0f/%.0f level=%d enemies=%d kills=%d gold=%.0f proj=%d gems=%d skills=%d anim_texture_ok=%s moved=%s" % [
		elapsed, _player.hp, _player.max_hp, _player.level, enemies, run_kills, run_gold,
		projectiles, gems, _player.skills.size(), str(sprite_ok), str(_player.global_position.length() > 1.0)])
	get_tree().quit(0)

# Drives the (fast) boss timeline end to end: mini-bosses -> final boss -> victory.
func _run_bosstest() -> void:
	_testing = true
	_auto_pick = true
	var t := 0.0
	while t < 13.0 and _state == "playing":
		await get_tree().process_frame
		t += get_process_delta_time()
		_test_dir = Vector2(cos(t * 0.5), sin(t * 0.3))
		# Burst down whatever boss is currently up so the timeline advances
		# within the test budget instead of waiting out a real boss fight.
		if _boss != null and is_instance_valid(_boss):
			_boss.take_damage(400.0, false)
	print("[BOSSTEST] elapsed=%.1f state=%s minis_spawned=%d kills=%d gold=%.0f" % [
		t, _state, _next_mini, run_kills, run_gold])
	get_tree().quit(0)

# Verifies the full death/game-over loop: lethal damage -> "dead" state +
# paused end screen -> Continue returns to the title -> a fresh run begins
# clean. Also exercises GameSave persistence (gold/best_time/total_kills).
func _run_deathtest() -> void:
	await get_tree().process_frame
	run_gold = 42.0
	_player.take_damage(999999.0)
	await get_tree().process_frame
	var dead_ok := _state == "dead" and get_tree().paused and _end_ui != null
	var saved_ok := GameSave.gold >= 42 and GameSave.total_kills >= 0
	# Round-trip the save file itself (simulates relaunching the game).
	var gold_before_reload := GameSave.gold
	GameSave.load_data()
	var reload_ok := GameSave.gold == gold_before_reload
	_return_to_title()
	await get_tree().process_frame
	var title_ok := _menu_ui != null and not get_tree().paused and _player == null
	_begin_run(DEFAULT_TEST_CLASS, "")
	await get_tree().process_frame
	var restart_ok := _state == "playing" and _player != null and is_instance_valid(_player) and _player.hp == _player.max_hp
	print("[DEATHTEST] dead_ok=%s saved_ok=%s reload_ok=%s title_ok=%s restart_ok=%s gold=%d" % [
		str(dead_ok), str(saved_ok), str(reload_ok), str(title_ok), str(restart_ok), GameSave.gold])
	get_tree().quit(0)

# Sanity-checks the procedural audio synthesis: bakes a tone + noise burst
# directly and confirms the PCM isn't silent/clipped, then exercises every
# named sfx() + the music drone/motif bake through the real public API.
func _run_audiotest() -> void:
	var sr := GameAudio.MIX_RATE
	var samples := PackedFloat32Array(); samples.resize(int(0.4 * sr))
	GameAudio._add_tone(samples, sr, 440.0, 0.0, 0.05, "square", 0.08)
	GameAudio._add_noise(samples, sr, 0.1, 0.05, 0.18, 1200.0)
	var peak := 0.0
	var sumsq := 0.0
	for v in samples:
		peak = maxf(peak, absf(v))
		sumsq += v * v
	var rms := sqrt(sumsq / samples.size())

	for name in ["hit", "crit", "enemyDie", "pickup", "levelup", "hurt", "cast", "uiClick", "purchase", "heartbeat"]:
		GameAudio.sfx(name)
	GameAudio.start_music()
	await get_tree().create_timer(0.3).timeout
	var drone_ok := GameAudio._music_player.stream != null and GameAudio._music_player.playing
	GameAudio.stop_music()

	print("[AUDIOTEST] peak=%.4f rms=%.6f nonsilent=%s in_range=%s drone_ok=%s" % [
		peak, rms, str(peak > 0.001), str(peak <= 1.0), str(drone_ok)])
	get_tree().quit(0)

# Verifies per-class upgrade independence: buying an upgrade for one class must
# not leak into another (regression guard for the old migration that seeded
# every class identically and made the shop look like it applied to all).
func _run_shoptest() -> void:
	GameSave.class_upgrades = {}
	GameSave.set_class_upgrade("knight", "vigor", 3)   # +3 * 20 = +60 max HP
	var kn := Player.new(); kn.setup("knight", "")
	var ar := Player.new(); ar.setup("archer", "")
	var kn_base: float = GameData.CLASSES["knight"]["max_hp"]
	var ar_base: float = GameData.CLASSES["archer"]["max_hp"]
	var kn_hp := kn.max_hp
	var ar_hp := ar.max_hp
	kn.free(); ar.free()
	var knight_boosted := is_equal_approx(kn_hp, kn_base + 60.0)
	var archer_unaffected := is_equal_approx(ar_hp, ar_base)
	# A save with no per-class data must not cross-seed classes on load.
	GameSave.class_upgrades = {}
	GameSave.load_data()
	var no_cross_seed := GameSave.class_upgrades.is_empty()
	print("[SHOPTEST] knight_hp=%.0f(base %.0f) archer_hp=%.0f(base %.0f) knight_boosted=%s archer_unaffected=%s no_cross_seed=%s" % [
		kn_hp, kn_base, ar_hp, ar_base, str(knight_boosted), str(archer_unaffected), str(no_cross_seed)])
	get_tree().quit(0)

# Verifies the stage/difficulty progression loop: unlock gating, tier
# advancement, tier stat-scaling, and the tier roster gate.
func _run_progresstest() -> void:
	GameSave.stage_clears = {}
	GameSave.unlocked_tier = "tier1"
	var dungeon_locked_init := not GameSave.stage_unlocked("dungeon")
	GameSave.mark_stage_cleared("forest", "tier1")
	var dungeon_unlocked := GameSave.stage_unlocked("dungeon")
	GameSave.mark_stage_cleared("dungeon", "tier1")   # all stages cleared @ tier1
	var tier2_unlocked := GameSave.tier_unlocked("tier2")
	# Stat scaling: same archetype is tougher under tier3 than tier1.
	_active_tier = GameData.difficulty_by_id("tier1")
	var e1 := add_enemy("skeleton", Vector2.ZERO, 1.0)
	var hp1: float = e1.hp; var dmg1: float = e1.dmg
	_active_tier = GameData.difficulty_by_id("tier3")
	var e3 := add_enemy("skeleton", Vector2(40, 0), 1.0)
	var scaled: bool = e3.hp > hp1 and e3.dmg > dmg1
	# Roster gate: chargers never appear at tier1, do at tier3.
	_active_tier = GameData.difficulty_by_id("tier1")
	var t1_charger := false
	for i in 500:
		if _weighted_archetype(6.0) == "charger": t1_charger = true; break
	_active_tier = GameData.difficulty_by_id("tier3")
	var t3_charger := false
	for i in 500:
		if _weighted_archetype(6.0) == "charger": t3_charger = true; break
	print("[PROGRESSTEST] dungeon_locked_init=%s dungeon_unlocked=%s tier2_unlocked=%s scaled=%s t1_charger=%s t3_charger=%s" % [
		str(dungeon_locked_init), str(dungeon_unlocked), str(tier2_unlocked), str(scaled), str(t1_charger), str(t3_charger)])
	get_tree().quit(0)

# Verifies the combat-juice plumbing: hit-stop is inert under _testing, actually
# dips + restores Engine.time_scale otherwise, knockback displaces an enemy, and
# take_damage (normal/crit/boss) runs cleanly and spawns feedback.
func _run_juicetest() -> void:
	_testing = true
	var before := Engine.time_scale
	hitstop(0.1, 0.02)
	var testing_noop := is_equal_approx(Engine.time_scale, before)
	_testing = false
	hitstop(0.05, 0.02)
	var dipped := Engine.time_scale < 0.5
	await get_tree().create_timer(0.14, true, false, true).timeout
	var restored := is_equal_approx(Engine.time_scale, 1.0)
	# Regression for the crit slow-mo bug: a burst of hit-stops (crit spam) must
	# not pin time_scale — the cooldown gate + _process restore recover it.
	# Reset first so the burst's first dip is independent of the prior cooldown.
	_clear_hitstop()
	for i in 40:
		hitstop(0.04, 0.02)
	var burst_dipped := Engine.time_scale < 0.5
	await get_tree().create_timer(0.3, true, false, true).timeout
	var burst_restored := is_equal_approx(Engine.time_scale, 1.0)
	_testing = true   # keep hit-stop inert for the rest of the checks
	_active_tier = GameData.difficulty_by_id("tier1")
	var e := add_enemy("skeleton", Vector2(100, 0), 1.0)
	e.apply_knockback(Vector2.RIGHT, 300.0)
	var kb_set: bool = e._knockback.length() > 100.0
	var world := get_node("World")
	var before_children := world.get_child_count()
	e.take_damage(5.0, false)
	add_enemy("skeleton", Vector2(120, 0), 1.0).take_damage(5.0, true)
	add_enemy("miniboss", Vector2(200, 0), 1.0).take_damage(5.0, false)
	await get_tree().process_frame
	var feedback_ok := world.get_child_count() > before_children
	print("[JUICETEST] testing_noop=%s dipped=%s restored=%s burst_dipped=%s burst_restored=%s kb_set=%s feedback_ok=%s time_scale=%.2f" % [
		str(testing_noop), str(dipped), str(restored), str(burst_dipped), str(burst_restored), str(kb_set), str(feedback_ok), Engine.time_scale])
	get_tree().quit(0)

# Verifies build-variety plumbing: the level-up roll mixes abilities + passives
# under the passive cap, each passive moves the matching Player stat in the right
# direction, and the Reach passive's aoe_mult actually widens area_damage.
func _run_buildtest() -> void:
	_testing = true
	_begin_run(DEFAULT_TEST_CLASS, "", "forest", "tier1")
	await get_tree().process_frame

	# 1) Roll composition: passives are present but capped, abilities still fill.
	var opts := Abilities.roll("knight", {}, 5, 2)
	var n_pass := 0
	for o in opts:
		if o["ability"]["mech"] == "stat": n_pass += 1
	var cap_ok: bool = opts.size() == 5 and n_pass <= 2 and n_pass >= 1

	# 2) Each passive moves its stat the right way (one incremental pick).
	var b_dmg := _player.damage
	var b_cd := _player.cooldown_mult
	var b_aoe := _player.aoe_mult
	var b_crit := _player.crit
	var b_cmult := _player.crit_mult
	var b_move := _player.move_speed
	var b_hp := _player.max_hp
	var b_xp := _player.fortune_xp
	var b_gold := _player.fortune_gold
	for ps in Abilities.passives():
		_player.apply_pick({"ability": ps, "is_new": true, "next_rank": 1})
	var stats_ok: bool = _player.damage > b_dmg and _player.cooldown_mult < b_cd \
		and _player.aoe_mult > b_aoe and _player.crit > b_crit and _player.crit_mult > b_cmult \
		and _player.move_speed > b_move and _player.max_hp > b_hp \
		and _player.fortune_xp > b_xp and _player.fortune_gold > b_gold

	# 3) Reach: an enemy just outside the base blast radius (accounting for the
	#    enemy's own radius) is spared at neutral aoe_mult but struck once boosted.
	var center := _player.global_position
	var far := add_enemy("skeleton", center, 1.0)
	var off_d: float = 50.0 + far.radius + 8.0   # base 50+r misses by 8; 65+r hits
	far.global_position = center + Vector2(off_d, 0.0)
	_player.aoe_mult = 1.0
	area_damage(center, 50.0, 1.0, {})           # 50+r < off_d → miss
	var missed_at_1: bool = is_equal_approx(far.hp, far.max_hp)
	_player.aoe_mult = 1.3
	area_damage(center, 50.0, 1.0, {})           # 65+r > off_d → hit
	var hit_at_boost: bool = far.hp < far.max_hp

	# 4) Evolution: with the base ability maxed and its passive at threshold, a
	#    golden evo card is offered; applying it swaps the base skill for the evo.
	var owned := {"kn_whirl": 5, "ps_might": 3}
	var evo_offered := false
	var evo_opt := {}
	for o in Abilities.roll("knight", owned, 8, 2):
		if o.get("is_evo", false) and o["ability"]["id"] == "kn_whirl_evo":
			evo_offered = true; evo_opt = o
	# Not offered before the pairing is met (base not maxed).
	var evo_gated := true
	for o in Abilities.roll("knight", {"kn_whirl": 2, "ps_might": 3}, 8, 2):
		if o.get("is_evo", false): evo_gated = false
	_player.apply_pick({"ability": Abilities.by_id("kn_whirl"), "is_new": true, "next_rank": 5})
	if not evo_opt.is_empty():
		_player.apply_pick(evo_opt)
	var has_evo := false
	var base_gone := true
	for s in _player.skills:
		if s["id"] == "kn_whirl_evo": has_evo = true
		if s["id"] == "kn_whirl": base_gone = false
	var evo_ok: bool = evo_offered and evo_gated and has_evo and base_gone

	# 5) Keystone gating: Kindling absent with only a non-fire ability owned,
	#    present once a fire ability is owned.
	var ks_gated := true
	for o in Abilities.roll("mage", {"mg_frostbolt": 1}, 8, 2):
		if o.get("is_keystone", false) and o["ability"]["id"] == "ks_kindling": ks_gated = false
	var ks_opt := {}
	for o in Abilities.roll("mage", {"mg_firenova": 1}, 8, 2):
		if o.get("is_keystone", false) and o["ability"]["id"] == "ks_kindling": ks_opt = o
	# Kindling effect: a fire ability now ignites an enemy that has no innate burn.
	if not ks_opt.is_empty(): _player.apply_pick(ks_opt)
	var kindling_set: bool = _player.fire_burn_bonus > 0.0
	var burn_target := add_enemy("skeleton", _player.global_position + Vector2(20, 0), 1.0)
	Abilities.activate(Abilities.by_id("mg_firenova"), _player, self, 1)
	var burn_applied: bool = burn_target.burn_until > elapsed

	# 6) Momentum: offered with a movement ability owned; sets movement_nova; the
	#    on-arrival nova (fired at the pre-dash position) damages a nearby enemy.
	var mo_opt := {}
	for o in Abilities.roll("knight", {"kn_charge": 1}, 8, 2):
		if o.get("is_keystone", false) and o["ability"]["id"] == "ks_momentum": mo_opt = o
	if not mo_opt.is_empty(): _player.apply_pick(mo_opt)
	var momentum_set: bool = _player.movement_nova > 0.0
	_player.apply_pick({"ability": Abilities.by_id("kn_charge"), "is_new": true, "next_rank": 1})
	for s in _player.skills:
		if s["id"] == "kn_charge": s["timer"] = 0.0
	var mo_target := add_enemy("skeleton", _player.global_position + Vector2(12, 0), 1.0)
	var mo_hp0: float = mo_target.hp
	_player.use_movement_ability()
	var momentum_hit: bool = mo_target.hp < mo_hp0

	# 7) The second-wave evolution gates on its own pairing (base maxed + passive).
	var slam_evo_offered := false
	for o in Abilities.roll("knight", {"kn_slam": 5, "ps_reach": 3}, 8, 2):
		if o.get("is_evo", false) and o["ability"]["id"] == "kn_slam_evo": slam_evo_offered = true

	var keystone_ok: bool = ks_gated and not ks_opt.is_empty() and kindling_set and burn_applied \
		and momentum_set and momentum_hit
	print("[BUILDTEST] cap_ok=%s passives=%d stats_ok=%s reach_miss=%s reach_hit=%s evo_ok=%s keystone_ok=%s evo2_ok=%s cd_mult=%.2f" % [
		str(cap_ok), n_pass, str(stats_ok), str(missed_at_1), str(hit_at_boost), str(evo_ok),
		str(keystone_ok), str(slam_evo_offered), _player.cooldown_mult])
	get_tree().quit(0)

# Verifies each stage's bounded arena: camera limits match stage bounds,
# obstacles were scattered, and sampled spawn positions land inside bounds
# and (mostly) clear of obstacles.
func _run_stagetest() -> void:
	for stage in GameData.STAGES:
		_begin_run(DEFAULT_TEST_CLASS, "", stage["id"], "tier1")
		await get_tree().process_frame
		var half: Vector2 = stage["bounds"] * 0.5
		var limits_ok := _camera.limit_left == int(-half.x) and _camera.limit_right == int(half.x) \
			and _camera.limit_top == int(-half.y) and _camera.limit_bottom == int(half.y)
		var ground_ok := _stage_root != null and _stage_root.get_child_count() > 0
		var walls_ok := _stage_root.get_node_or_null("Walls") != null
		var torch_ok: bool = _torch_overlay.visible == (stage.get("lighting", "torch") == "torch")
		var spawn_in_bounds := true
		var spawn_clear := true
		for i in 30:
			var pos := _find_spawn_pos(_player.global_position, 400.0)
			if absf(pos.x) > half.x + 1.0 or absf(pos.y) > half.y + 1.0:
				spawn_in_bounds = false
			if _pos_blocked(pos):
				spawn_clear = false
		# Place the player near the corner, then drive it hard into the walls and
		# confirm the perimeter actually contains it (the real regression guard
		# for the collision-shape fix — without shapes the body walks off-map).
		_player.global_position = Vector2(half.x - 60.0, half.y - 60.0)
		_testing = true
		_test_dir = Vector2(1, 1)
		for i in 150:
			await get_tree().physics_frame
		var contained := _player.global_position.x <= half.x + 40.0 and _player.global_position.y <= half.y + 40.0
		_testing = false; _test_dir = Vector2.ZERO
		_player.global_position = Vector2.ZERO
		print("[STAGETEST] stage=%s limits_ok=%s ground_ok=%s walls_ok=%s torch_ok=%s obstacles=%d spawn_in_bounds=%s spawn_clear=%s contained=%s" % [
			stage["id"], str(limits_ok), str(ground_ok), str(walls_ok), str(torch_ok), _obstacles.size(), str(spawn_in_bounds), str(spawn_clear), str(contained)])
	get_tree().quit(0)

# Verifies pause -> settings (volume/mute, persisted) -> back -> resume, then
# a second pause -> Quit to Title, confirming the quit path abandons the run
# (no gold persisted) unlike the death/victory end-run path.
func _run_pausetest() -> void:
	await get_tree().process_frame
	run_gold = 77.0
	_open_pause()
	await get_tree().process_frame
	var pause_ok := get_tree().paused and _pause_ui != null

	_show_settings(_show_pause)
	await get_tree().process_frame
	var settings_ok := _settings_ui != null and get_tree().paused
	var muted_before := GameSave.muted
	_on_volume_changed(40.0)
	_toggle_mute(Button.new())
	var vol_ok := is_equal_approx(GameSave.volume, 0.4) and GameSave.muted != muted_before
	var muted_after_toggle := GameSave.muted
	GameSave.load_data()
	var settings_reload_ok := is_equal_approx(GameSave.volume, 0.4) and GameSave.muted == muted_after_toggle
	var gold_before_settle := GameSave.gold

	if _settings_ui:
		_settings_ui.queue_free(); _settings_ui = null
	_show_pause()
	await get_tree().process_frame
	var back_to_pause_ok := _pause_ui != null and get_tree().paused

	_resume_from_pause()
	await get_tree().process_frame
	var resume_ok := not get_tree().paused and _pause_ui == null and _state == "playing"

	_open_pause()
	await get_tree().process_frame
	_quit_run()
	await get_tree().process_frame
	var quit_ok := _player == null and not get_tree().paused and _menu_ui != null and GameSave.gold == gold_before_settle

	print("[PAUSETEST] pause_ok=%s settings_ok=%s vol_ok=%s settings_reload_ok=%s back_to_pause_ok=%s resume_ok=%s quit_ok=%s" % [
		str(pause_ok), str(settings_ok), str(vol_ok), str(settings_reload_ok), str(back_to_pause_ok), str(resume_ok), str(quit_ok)])
	get_tree().quit(0)
