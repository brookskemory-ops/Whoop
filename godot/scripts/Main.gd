extends Node2D
## Run controller: menus (title/class-select/shop/achievements), the world
## (floor, player, camera), spawning, input, the HUD, and meta-progression —
## ported from js/game.js. Audio + lighting are not yet ported.

const DEFAULT_TEST_CLASS := "knight"

var _selected_class := "knight"
var _selected_weapon := "arming_sword"
var _menu_ui: CanvasLayer

var _win_time := 600.0
var _mini_times := [180.0, 360.0, 540.0]

var elapsed := 0.0
var run_gold := 0.0
var run_kills := 0
var _spawn_timer := 0.0
var _state := "playing"   # playing | dead | won

var _world: Node2D
var _player: Player
var _camera: Camera2D

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
var _boss_bg: ColorRect
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
	else:
		_show_title()

func _has_flag(name: String) -> bool:
	return name in OS.get_cmdline_args() or name in OS.get_cmdline_user_args()

func _build_world() -> void:
	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)

	# Floor: one huge repeating Sprite2D using the PixelLab dungeon-stone tile.
	var floor_spr := Sprite2D.new()
	floor_spr.texture = load("res://assets/map/floor.png")
	floor_spr.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	floor_spr.region_enabled = true
	floor_spr.region_rect = Rect2(-500000, -500000, 1000000, 1000000)
	floor_spr.scale = Vector2(2, 2)
	floor_spr.z_index = -100
	_world.add_child(floor_spr)

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
	_shake = minf(16.0, _shake + n)

func _begin_run(class_id: String, weapon_id: String) -> void:
	_clear_menu()
	_clear_run()

	_player = Player.new()
	_player.setup(class_id, weapon_id)
	_player.died.connect(_on_player_died)
	_player.leveled_up.connect(_on_level_up)
	_world.add_child(_player)

	_camera = Camera2D.new()
	_camera.position_smoothing_enabled = false   # instant 1:1 follow, matching js/game.js's camX/camY
	_player.add_child(_camera)
	_camera.make_current()

	elapsed = 0.0; run_gold = 0.0; run_kills = 0; _spawn_timer = 0.0
	_boss = null; _next_mini = 0; _final_spawned = false
	_banner_text = ""; _banner_timer = 0.0
	_ability_header_sig = ""
	_last_beat = 0.0; _shake = 0.0; _flash = 0.0
	_state = "playing"
	GameAudio.start_music()

func _clear_run() -> void:
	# Free everything spawned during the run (player/enemies/gems/projectiles),
	# but leave the floor (a plain, scriptless Sprite2D) in place.
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

func _menu_base() -> VBoxContainer:
	_clear_menu()
	_menu_ui = CanvasLayer.new()
	_menu_ui.layer = 10
	add_child(_menu_ui)
	var dim := ColorRect.new()
	dim.color = UiTheme.BG; dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_ui.add_child(dim)
	var scroll := ScrollContainer.new()
	scroll.theme = _ui_theme
	scroll.position = Vector2(20, 90); scroll.custom_minimum_size = Vector2(440, 660)
	_menu_ui.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(420, 0)
	vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(vbox)
	return vbox

func _show_title() -> void:
	var vbox := _menu_base()
	var title := Label.new(); title.text = "IRONVOW"; title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_title(title, 44)
	vbox.add_child(title)
	var tagline := Label.new(); tagline.text = "Hold the line. Forge your legend."
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_muted(tagline, 14)
	vbox.add_child(tagline)
	vbox.add_child(_spacer(18))

	var start_btn := _make_button("New Run", true)
	start_btn.pressed.connect(func(): GameAudio.sfx("uiClick"); _show_class_select())
	vbox.add_child(start_btn)
	var shop_btn := _make_button("Armory (Shop)")
	shop_btn.pressed.connect(func(): GameAudio.sfx("uiClick"); _show_shop())
	vbox.add_child(shop_btn)
	var ach_btn := _make_button("Deeds (Achievements)")
	ach_btn.pressed.connect(func(): GameAudio.sfx("uiClick"); _show_achievements())
	vbox.add_child(ach_btn)
	var settings_btn := _make_button("Settings")
	settings_btn.pressed.connect(func(): GameAudio.sfx("uiClick"); _show_settings(_show_title))
	vbox.add_child(settings_btn)

	vbox.add_child(_spacer(10))
	var stats := Label.new()
	stats.text = "Best: %d:%02d    Gold: %d" % [int(GameSave.best_time) / 60, int(GameSave.best_time) % 60, GameSave.gold]
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_muted(stats, 14)
	vbox.add_child(stats)

func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

func _make_button(text: String, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(400, 52)
	b.theme = _ui_theme
	if primary:
		b.theme_type_variation = "PrimaryButton"
	return b

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
		b.custom_minimum_size = Vector2(196, 84)
		b.text = ""
		UiTheme.accent_button_style(b, accent, cid == _selected_class)
		b.pressed.connect(_pick_class.bind(cid))

		var inner := VBoxContainer.new()
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.set_anchors_preset(Control.PRESET_FULL_RECT)
		inner.offset_left = 14; inner.offset_top = 10
		inner.offset_right = -14; inner.offset_bottom = -10
		inner.add_theme_constant_override("separation", 3)
		b.add_child(inner)

		var name_lbl := Label.new()
		name_lbl.text = c["name"]
		name_lbl.add_theme_color_override("font_color", accent if unlocked else UiTheme.MUTED)
		name_lbl.add_theme_font_size_override("font_size", 18)
		inner.add_child(name_lbl)

		var blurb_lbl := Label.new()
		blurb_lbl.text = c["blurb"] if unlocked else ("(Locked) %s" % _lock_text(c["unlock"]))
		blurb_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		UiTheme.style_muted(blurb_lbl, 12)
		inner.add_child(blurb_lbl)

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
		wb.custom_minimum_size = Vector2(190, 44)
		wb.text = w["name"] if wun else "(Locked) %s" % w["name"]
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
	var begin_btn := _make_button("Begin", true)
	begin_btn.disabled = not (GameSave.class_unlocked(_selected_class) and GameSave.weapon_unlocked(_selected_weapon))
	begin_btn.pressed.connect(func(): GameAudio.sfx("uiClick"); _begin_run(_selected_class, _selected_weapon))
	vbox.add_child(begin_btn)

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

	var upg_hdr := Label.new(); upg_hdr.text = "PERMANENT UPGRADES"
	UiTheme.style_heading(upg_hdr, UiTheme.GOLD_BRIGHT, 13)
	vbox.add_child(upg_hdr)
	for t in GameData.UPGRADE_TRACKS:
		var id: String = t["id"]
		var lvl: int = int(GameSave.upgrades.get(id, 0))
		var maxed: bool = lvl >= int(t["max"])
		var cost := GameData.upgrade_cost(id, lvl)
		var row := _make_button("")
		row.custom_minimum_size = Vector2(400, 56)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.disabled = maxed or GameSave.gold < cost
		row.text = "%s   Lv %d/%d — %s\n%s" % [t["name"], lvl, t["max"], GameData.upgrade_desc(id, lvl), ("MAX" if maxed else "%d gold" % cost)]
		row.pressed.connect(_buy_upgrade.bind(id))
		vbox.add_child(row)

	var unl_hdr := Label.new(); unl_hdr.text = "UNLOCKS"
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
	var b := _make_button("%s — %d gold" % [label, cost])
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.disabled = GameSave.gold < cost
	b.pressed.connect(handler)
	vbox.add_child(b)

func _buy_upgrade(id: String) -> void:
	var lvl: int = int(GameSave.upgrades.get(id, 0))
	var cost := GameData.upgrade_cost(id, lvl)
	if GameSave.gold >= cost:
		GameSave.gold -= cost
		GameSave.upgrades[id] = lvl + 1
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
	var hdr := Label.new(); hdr.text = "Deeds"; hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_title(hdr, 22)
	vbox.add_child(hdr)
	vbox.add_child(_spacer(6))
	for a in GameData.ACHIEVEMENTS:
		var done: bool = bool(GameSave.achievements.get(a["id"], false))
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", UiTheme.panel_style())
		var inner := VBoxContainer.new()
		panel.add_child(inner)
		var title_row := Label.new()
		title_row.text = ("✓ " if done else "") + a["name"]
		UiTheme.style_heading(title_row, UiTheme.GOLD_BRIGHT if done else UiTheme.INK, 16)
		inner.add_child(title_row)
		var desc := Label.new(); desc.text = a["desc"]
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD
		UiTheme.style_muted(desc, 13)
		inner.add_child(desc)
		var unlocks := Label.new(); unlocks.text = "Unlocks: %s" % a["unlocks"]
		UiTheme.style_heading(unlocks, UiTheme.GOLD, 12)
		inner.add_child(unlocks)
		vbox.add_child(panel)
	vbox.add_child(_spacer(10))
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
	_pause_ui = CanvasLayer.new()
	_pause_ui.process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_ui.layer = 10
	add_child(_pause_ui)
	var dim := ColorRect.new()
	dim.color = Color(10.0 / 255, 8.0 / 255, 6.0 / 255, 0.85); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_ui.add_child(dim)
	var vbox := VBoxContainer.new()
	vbox.theme = _ui_theme
	vbox.position = Vector2(45, 300); vbox.custom_minimum_size = Vector2(300, 0)
	vbox.add_theme_constant_override("separation", 12)
	_pause_ui.add_child(vbox)
	var hdr := Label.new(); hdr.text = "Paused"; hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_title(hdr, 26)
	vbox.add_child(hdr)
	vbox.add_child(_spacer(8))
	var resume_btn := _make_button("Resume", true)
	resume_btn.pressed.connect(func(): GameAudio.sfx("uiClick"); _resume_from_pause())
	vbox.add_child(resume_btn)
	var settings_btn := _make_button("Settings")
	settings_btn.pressed.connect(func(): GameAudio.sfx("uiClick"); _show_settings(_show_pause))
	vbox.add_child(settings_btn)
	var quit_btn := _make_button("Quit to Title")
	quit_btn.pressed.connect(func(): GameAudio.sfx("uiClick"); _quit_run())
	vbox.add_child(quit_btn)

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
	var layer := CanvasLayer.new()
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.layer = 10
	add_child(layer)
	_settings_ui = layer
	var dim := ColorRect.new()
	dim.color = UiTheme.BG; dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var vbox := VBoxContainer.new()
	vbox.theme = _ui_theme
	vbox.position = Vector2(40, 260); vbox.custom_minimum_size = Vector2(400, 0)
	vbox.add_theme_constant_override("separation", 14)
	layer.add_child(vbox)
	var hdr := Label.new(); hdr.text = "Settings"; hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_title(hdr, 26)
	vbox.add_child(hdr)
	vbox.add_child(_spacer(8))
	var vol_lbl := Label.new(); vol_lbl.text = "Volume"
	UiTheme.style_muted(vol_lbl, 14)
	vbox.add_child(vol_lbl)
	var slider := HSlider.new()
	slider.theme = _ui_theme
	slider.min_value = 0; slider.max_value = 100; slider.step = 1
	slider.value = GameSave.volume * 100.0
	slider.custom_minimum_size = Vector2(380, 32)
	slider.value_changed.connect(_on_volume_changed)
	vbox.add_child(slider)
	var mute_btn := _make_button("Muted" if GameSave.muted else "Sound On")
	mute_btn.pressed.connect(_toggle_mute.bind(mute_btn))
	vbox.add_child(mute_btn)
	vbox.add_child(_spacer(8))
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
		var interval: float = max(0.22, 1.4 - elapsed * 0.008)
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

	_camera.offset = Vector2(randf_range(-0.5, 0.5), randf_range(-0.5, 0.5)) * _shake if _shake > 0.0 else Vector2.ZERO

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
	var ang := randf() * TAU
	var dist := maxf(get_viewport_rect().size.x, get_viewport_rect().size.y) * 0.55 + 60.0
	var pos := _player.global_position + Vector2(cos(ang), sin(ang)) * dist
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
	var ang := randf() * TAU
	var dist := maxf(get_viewport_rect().size.x, get_viewport_rect().size.y) * 0.6 + 40.0
	var pos := _player.global_position + Vector2(cos(ang), sin(ang)) * dist
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
	area_damage_amount(center, radius, _player.damage * mult, opts)

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
		get_tree().paused = true
		_build_level_cards(opts)
		return
	_leveling = false
	get_tree().paused = false

func _build_level_cards(opts: Array) -> void:
	_level_ui = CanvasLayer.new()
	_level_ui.process_mode = Node.PROCESS_MODE_ALWAYS
	_level_ui.layer = 10
	add_child(_level_ui)
	var dim := ColorRect.new()
	dim.color = Color(10.0 / 255, 8.0 / 255, 6.0 / 255, 0.82); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_level_ui.add_child(dim)
	var vbox := VBoxContainer.new()
	vbox.theme = _ui_theme
	vbox.position = Vector2(30, 160); vbox.custom_minimum_size = Vector2(330, 0)
	vbox.add_theme_constant_override("separation", 10)
	_level_ui.add_child(vbox)
	var title := Label.new()
	title.text = "Level %d" % _player.level
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_title(title, 28)
	vbox.add_child(title)
	vbox.add_child(_spacer(8))
	for opt in opts:
		var def: Dictionary = opt["ability"]
		var b := Button.new()
		b.theme = _ui_theme
		b.text = ""
		b.custom_minimum_size = Vector2(330, 68)
		UiTheme.accent_button_style(b, UiTheme.GOLD if opt["is_new"] else UiTheme.XP_COLOR, false)
		b.pressed.connect(_pick_ability.bind(opt))
		vbox.add_child(b)

		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.set_anchors_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 12; row.offset_top = 8; row.offset_right = -12; row.offset_bottom = -8
		row.add_theme_constant_override("separation", 10)
		b.add_child(row)

		var icon := TextureRect.new()
		var icon_path := "res://assets/icons/abilities/%s.png" % def.get("icon_key", def["mech"])
		if ResourceLoader.exists(icon_path):
			icon.texture = load(icon_path)
		icon.modulate = Color(def["color"])
		icon.custom_minimum_size = Vector2(36, 36)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)

		var text_col := VBoxContainer.new()
		text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text_col)
		var tag := "NEW" if opt["is_new"] else "Rank %d -> %d" % [opt["next_rank"] - 1, opt["next_rank"]]
		var name_lbl := Label.new()
		name_lbl.text = "%s  [%s]" % [def["name"], tag]
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		UiTheme.style_heading(name_lbl, UiTheme.GOLD_BRIGHT if opt["is_new"] else UiTheme.XP_COLOR, 15)
		text_col.add_child(name_lbl)
		var desc_lbl := Label.new()
		desc_lbl.text = Abilities.describe(def, opt["next_rank"])
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		UiTheme.style_muted(desc_lbl, 12)
		text_col.add_child(desc_lbl)

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

	_lbl_level = Label.new(); _lbl_level.position = Vector2(12, 8)
	UiTheme.style_heading(_lbl_level, UiTheme.INK, 18)
	layer.add_child(_lbl_level)
	_lbl_time = Label.new(); _lbl_time.position = Vector2(340, 8)
	UiTheme.style_heading(_lbl_time, UiTheme.GOLD_BRIGHT, 18)
	layer.add_child(_lbl_time)

	_lbl_gold = Label.new(); _lbl_gold.position = Vector2(12, 27)
	UiTheme.style_heading(_lbl_gold, UiTheme.GOLD_BRIGHT, 14)
	layer.add_child(_lbl_gold)

	var hp_bg := Panel.new()
	hp_bg.add_theme_stylebox_override("panel", _bar_bg_style())
	hp_bg.position = Vector2(12, 46); hp_bg.size = Vector2(_hp_w, 12)
	layer.add_child(hp_bg)
	_hp_fill = ColorRect.new()
	_hp_fill.color = UiTheme.HP_COLOR; _hp_fill.position = Vector2(13, 47); _hp_fill.size = Vector2(_hp_w - 2, 10)
	layer.add_child(_hp_fill)

	var xp_bg := Panel.new()
	xp_bg.add_theme_stylebox_override("panel", _bar_bg_style())
	xp_bg.position = Vector2(12, 60); xp_bg.size = Vector2(_xp_w, 6)
	layer.add_child(xp_bg)
	_xp_fill = ColorRect.new()
	_xp_fill.color = UiTheme.XP_COLOR; _xp_fill.position = Vector2(13, 61); _xp_fill.size = Vector2(_xp_w - 2, 4)
	layer.add_child(_xp_fill)

	# Ability header: icon + rank badge per currently-owned ability, refreshed
	# from _update_hud() whenever the owned-abilities signature changes.
	_ability_header = HFlowContainer.new()
	_ability_header.position = Vector2(12, 72); _ability_header.custom_minimum_size = Vector2(380, 0)
	_ability_header.add_theme_constant_override("h_separation", 4)
	_ability_header.add_theme_constant_override("v_separation", 4)
	layer.add_child(_ability_header)

	var ab_btn := _make_button("*")
	ab_btn.position = Vector2(390, 712); ab_btn.custom_minimum_size = Vector2(72, 72)
	ab_btn.add_theme_font_size_override("font_size", 26)
	ab_btn.pressed.connect(func(): if _player: _player.use_movement_ability())
	layer.add_child(ab_btn)
	var pause_btn := _make_button("||")
	pause_btn.position = Vector2(426, 4); pause_btn.custom_minimum_size = Vector2(48, 32)
	pause_btn.pressed.connect(func(): GameAudio.sfx("uiClick"); _open_pause())
	layer.add_child(pause_btn)

	# Boss health bar (hidden until a boss is present).
	_lbl_boss_name = Label.new(); _lbl_boss_name.position = Vector2(100, 108)
	UiTheme.style_heading(_lbl_boss_name, UiTheme.MUTED, 13)
	_lbl_boss_name.visible = false; layer.add_child(_lbl_boss_name)
	_boss_bg = ColorRect.new()
	_boss_bg.color = Color(0, 0, 0, 0.5); _boss_bg.position = Vector2(100, 128); _boss_bg.size = Vector2(_boss_w, 10)
	_boss_bg.visible = false; layer.add_child(_boss_bg)
	_boss_fill = ColorRect.new()
	_boss_fill.color = Color("b14a8a"); _boss_fill.position = Vector2(100, 128); _boss_fill.size = Vector2(_boss_w, 10)
	_boss_fill.visible = false; layer.add_child(_boss_fill)

	# Event banner (mini-boss/final-boss announcements).
	_lbl_banner = Label.new()
	_lbl_banner.position = Vector2(30, 160); _lbl_banner.custom_minimum_size = Vector2(420, 0)
	_lbl_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_title(_lbl_banner, 24)
	_lbl_banner.visible = false
	layer.add_child(_lbl_banner)

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
	_hp_fill.size.x = _hp_w * clampf(_player.hp / _player.max_hp, 0.0, 1.0)
	_xp_fill.size.x = _xp_w * clampf(_player.xp / _player.xp_next, 0.0, 1.0)

	var sig := ""
	for s in _player.skills: sig += "%s:%d," % [s["id"], s["rank"]]
	if sig != _ability_header_sig:
		_ability_header_sig = sig
		_refresh_ability_header()

	var boss_live: bool = _boss != null and is_instance_valid(_boss) and _boss.hp > 0.0
	_boss_bg.visible = boss_live; _boss_fill.visible = boss_live; _lbl_boss_name.visible = boss_live
	if boss_live:
		_lbl_boss_name.text = "The Warden" if _boss.is_final else "Champion"
		_boss_fill.size.x = _boss_w * clampf(_boss.hp / _boss.max_hp, 0.0, 1.0)

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
	get_tree().paused = true
	GameAudio.stop_music()
	if won:
		GameAudio.sfx("levelup")
	var fresh := _check_run_achievements()
	GameSave.gold += int(floor(run_gold))
	GameSave.total_kills += run_kills
	GameSave.class_kills[_player.cls_id] = int(GameSave.class_kills.get(_player.cls_id, 0)) + run_kills
	if elapsed > GameSave.best_time:
		GameSave.best_time = elapsed
	GameSave.save_data()
	_show_end_screen(title, fresh)

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

func _show_end_screen(title: String, fresh: Array) -> void:
	_end_ui = CanvasLayer.new()
	_end_ui.process_mode = Node.PROCESS_MODE_ALWAYS
	_end_ui.layer = 10
	add_child(_end_ui)
	var dim := ColorRect.new()
	dim.color = Color(10.0 / 255, 8.0 / 255, 6.0 / 255, 0.85); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_ui.add_child(dim)
	var vbox := VBoxContainer.new()
	vbox.theme = _ui_theme
	vbox.position = Vector2(45, 260); vbox.custom_minimum_size = Vector2(300, 0)
	vbox.add_theme_constant_override("separation", 12)
	_end_ui.add_child(vbox)
	var t := Label.new(); t.text = title; t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_title(t, 30)
	vbox.add_child(t)
	vbox.add_child(_spacer(8))
	var stats := Label.new()
	stats.text = "Time: %d:%02d\nKills: %d\nGold: +%d" % [int(elapsed) / 60, int(elapsed) % 60, run_kills, int(floor(run_gold))]
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_muted(stats, 15)
	vbox.add_child(stats)
	if not fresh.is_empty():
		vbox.add_child(_spacer(6))
		var lines := ["Unlocked!"]
		for id in fresh:
			var a: Dictionary = GameData.achievement_by_id(id)
			lines.append("%s — %s" % [a["name"], a["unlocks"]])
		var ul := Label.new(); ul.text = "\n".join(lines)
		ul.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UiTheme.style_heading(ul, UiTheme.GOLD_BRIGHT, 14)
		vbox.add_child(ul)
	vbox.add_child(_spacer(8))
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
	var sprite_ok := _player.get_child(0) is Sprite2D and _player.get_child(0).texture != null
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
