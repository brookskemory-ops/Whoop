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

# HUD
var _lbl_level: Label
var _lbl_time: Label
var _hp_fill: ColorRect
var _hp_w := 200.0
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

# Level-up flow
var _pending_levels := 0
var _leveling := false
var _auto_pick := false
var _level_ui: CanvasLayer

# Headless self-test movement override
var _testing := false
var _test_dir := Vector2.ZERO

func _ready() -> void:
	randomize()
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

func _begin_run(class_id: String, weapon_id: String) -> void:
	_clear_menu()
	_clear_run()

	_player = Player.new()
	_player.setup(class_id, weapon_id)
	_player.died.connect(_on_player_died)
	_player.leveled_up.connect(_on_level_up)
	_world.add_child(_player)

	_camera = Camera2D.new()
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = 8.0
	_player.add_child(_camera)
	_camera.make_current()

	elapsed = 0.0; run_gold = 0.0; run_kills = 0; _spawn_timer = 0.0
	_boss = null; _next_mini = 0; _final_spawned = false
	_banner_text = ""; _banner_timer = 0.0
	_state = "playing"

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
	dim.color = Color(0.06, 0.05, 0.04, 1.0); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_ui.add_child(dim)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(20, 50); scroll.custom_minimum_size = Vector2(440, 700)
	_menu_ui.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(420, 0)
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)
	return vbox

func _show_title() -> void:
	var vbox := _menu_base()
	var title := Label.new(); title.text = "IRONVOW"; vbox.add_child(title)
	var stats := Label.new()
	stats.text = "Best time: %d:%02d   Gold: %d" % [int(GameSave.best_time) / 60, int(GameSave.best_time) % 60, GameSave.gold]
	vbox.add_child(stats)
	var start_btn := Button.new(); start_btn.text = "Start Run"; start_btn.custom_minimum_size = Vector2(400, 56)
	start_btn.pressed.connect(_show_class_select)
	vbox.add_child(start_btn)
	var shop_btn := Button.new(); shop_btn.text = "Armory"; shop_btn.custom_minimum_size = Vector2(400, 48)
	shop_btn.pressed.connect(_show_shop)
	vbox.add_child(shop_btn)
	var ach_btn := Button.new(); ach_btn.text = "Achievements"; ach_btn.custom_minimum_size = Vector2(400, 48)
	ach_btn.pressed.connect(_show_achievements)
	vbox.add_child(ach_btn)

func _show_class_select() -> void:
	var vbox := _menu_base()
	var hdr := Label.new(); hdr.text = "Choose your class"; vbox.add_child(hdr)
	for cid in GameData.CLASSES:
		var c: Dictionary = GameData.CLASSES[cid]
		var unlocked := GameSave.class_unlocked(cid)
		var b := Button.new()
		b.custom_minimum_size = Vector2(400, 56)
		b.text = "%s\n%s" % [c["name"] if unlocked else "🔒 %s — %s" % [c["name"], _lock_text(c["unlock"])], c["blurb"] if unlocked else ""]
		if cid == _selected_class:
			b.modulate = Color(1.25, 1.25, 0.95)
		b.pressed.connect(_pick_class.bind(cid))
		vbox.add_child(b)

	var weapon_hdr := Label.new(); weapon_hdr.text = "Weapon:"; vbox.add_child(weapon_hdr)
	var cls: Dictionary = GameData.CLASSES[_selected_class]
	for wid in cls["weapons"]:
		var w: Dictionary = GameData.WEAPON_META[wid]
		var wun := GameSave.weapon_unlocked(wid)
		var wb := Button.new()
		wb.custom_minimum_size = Vector2(400, 44)
		wb.text = w["name"] if wun else "🔒 %s" % w["name"]
		if wid == _selected_weapon:
			wb.modulate = Color(1.25, 1.25, 0.95)
		wb.pressed.connect(_pick_weapon.bind(wid))
		vbox.add_child(wb)
	var detail := Label.new()
	detail.text = GameData.WEAPON_META[_selected_weapon]["desc"]
	vbox.add_child(detail)

	var begin_btn := Button.new(); begin_btn.text = "Begin"; begin_btn.custom_minimum_size = Vector2(400, 56)
	begin_btn.disabled = not (GameSave.class_unlocked(_selected_class) and GameSave.weapon_unlocked(_selected_weapon))
	begin_btn.pressed.connect(_begin_run.bind(_selected_class, _selected_weapon))
	vbox.add_child(begin_btn)
	var back_btn := Button.new(); back_btn.text = "Back"; back_btn.custom_minimum_size = Vector2(400, 44)
	back_btn.pressed.connect(_show_title)
	vbox.add_child(back_btn)

func _pick_class(cid: String) -> void:
	_selected_class = cid
	_selected_weapon = GameData.CLASSES[cid]["weapon"]
	_show_class_select()

func _pick_weapon(wid: String) -> void:
	_selected_weapon = wid
	_show_class_select()

func _lock_text(u: Dictionary) -> String:
	match u["type"]:
		"gold": return "Buy for %d gold" % int(u["cost"])
		"achievement": return GameData.achievement_by_id(u["achievement"])["name"]
	return "Locked"

func _show_shop() -> void:
	var vbox := _menu_base()
	var gold_lbl := Label.new(); gold_lbl.text = "Gold: %d" % GameSave.gold; vbox.add_child(gold_lbl)

	var upg_hdr := Label.new(); upg_hdr.text = "Permanent Upgrades"; vbox.add_child(upg_hdr)
	for t in GameData.UPGRADE_TRACKS:
		var id: String = t["id"]
		var lvl: int = int(GameSave.upgrades.get(id, 0))
		var maxed: bool = lvl >= int(t["max"])
		var cost := GameData.upgrade_cost(id, lvl)
		var row := Button.new()
		row.custom_minimum_size = Vector2(400, 52)
		row.disabled = maxed or GameSave.gold < cost
		row.text = "%s  Lv %d/%d — %s\n%s" % [t["name"], lvl, t["max"], GameData.upgrade_desc(id, lvl), ("MAX" if maxed else "%d g" % cost)]
		row.pressed.connect(_buy_upgrade.bind(id))
		vbox.add_child(row)

	var unl_hdr := Label.new(); unl_hdr.text = "Unlocks"; vbox.add_child(unl_hdr)
	for cid in GameData.CLASSES:
		var c: Dictionary = GameData.CLASSES[cid]
		if c["unlock"]["type"] == "gold" and not GameSave.class_unlocked(cid):
			_shop_unlock_row(vbox, "%s (class)" % c["name"], int(c["unlock"]["cost"]), _buy_class_unlock.bind(cid, int(c["unlock"]["cost"])))
	for wid in GameData.WEAPON_META:
		var w: Dictionary = GameData.WEAPON_META[wid]
		if w["unlock"]["type"] == "gold" and not GameSave.weapon_unlocked(wid):
			_shop_unlock_row(vbox, w["name"], int(w["unlock"]["cost"]), _buy_weapon_unlock.bind(wid, int(w["unlock"]["cost"])))

	var back_btn := Button.new(); back_btn.text = "Back"; back_btn.custom_minimum_size = Vector2(400, 48)
	back_btn.pressed.connect(_show_title)
	vbox.add_child(back_btn)

func _shop_unlock_row(vbox: VBoxContainer, label: String, cost: int, handler: Callable) -> void:
	var b := Button.new()
	b.custom_minimum_size = Vector2(400, 48)
	b.disabled = GameSave.gold < cost
	b.text = "%s — %d g" % [label, cost]
	b.pressed.connect(handler)
	vbox.add_child(b)

func _buy_upgrade(id: String) -> void:
	var lvl: int = int(GameSave.upgrades.get(id, 0))
	var cost := GameData.upgrade_cost(id, lvl)
	if GameSave.gold >= cost:
		GameSave.gold -= cost
		GameSave.upgrades[id] = lvl + 1
		GameSave.save_data()
		_show_shop()

func _buy_class_unlock(cid: String, cost: int) -> void:
	if GameSave.gold >= cost:
		GameSave.gold -= cost
		GameSave.unlocked_classes[cid] = true
		GameSave.save_data()
		_show_shop()

func _buy_weapon_unlock(wid: String, cost: int) -> void:
	if GameSave.gold >= cost:
		GameSave.gold -= cost
		GameSave.unlocked_weapons[wid] = true
		GameSave.save_data()
		_show_shop()

func _show_achievements() -> void:
	var vbox := _menu_base()
	var hdr := Label.new(); hdr.text = "Achievements"; vbox.add_child(hdr)
	for a in GameData.ACHIEVEMENTS:
		var done: bool = bool(GameSave.achievements.get(a["id"], false))
		var row := Label.new()
		row.text = "%s %s\n%s\nUnlocks: %s" % [("✓" if done else "—"), a["name"], a["desc"], a["unlocks"]]
		vbox.add_child(row)
	var back_btn := Button.new(); back_btn.text = "Back"; back_btn.custom_minimum_size = Vector2(400, 48)
	back_btn.pressed.connect(_show_title)
	vbox.add_child(back_btn)

func _return_to_title() -> void:
	if _end_ui:
		_end_ui.queue_free(); _end_ui = null
	get_tree().paused = false
	_clear_run()
	_show_title()

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
		var interval: float = max(0.16, 1.1 - elapsed * 0.01)
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

	_update_hud()

func spawn_boss(key: String) -> void:
	var ang := randf() * TAU
	var dist := maxf(get_viewport_rect().size.x, get_viewport_rect().size.y) * 0.55 + 60.0
	var pos := _player.global_position + Vector2(cos(ang), sin(ang)) * dist
	_boss = add_enemy(key, pos, 1.0 + (elapsed / 60.0) * 0.06)
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
	var e: Node = add_enemy(key, pos, 1.0 + m * 0.35)
	# Occasional elite (ported from js/game.js spawnEnemy).
	if m > 1.0 and randf() < 0.06:
		e.elite = true
		e.hp *= 3.2; e.max_hp = e.hp; e.radius *= 1.3; e.dmg *= 1.4; e.gold *= 4.0; e.xp *= 3.0

func _weighted_archetype(m: float) -> String:
	var choices := [
		["skeleton", 10.0], ["goblin", 3.0 + m], ["ogre", maxf(0.0, m - 0.5)],
		["shooter", maxf(0.0, m - 1.0) * 1.2], ["exploder", maxf(0.0, m - 1.5) * 1.1],
		["splitter", maxf(0.0, m - 2.0)], ["charger", maxf(0.0, m - 2.5)],
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
	var dmg: float = _player.damage * mult
	var crit: bool = opts.get("crit", false)
	for e in get_tree().get_nodes_in_group("enemies"):
		var off: Vector2 = e.global_position - center
		if off.length() <= radius + e.radius:
			e.take_damage(dmg, crit)
			if opts.has("slow"):
				e.apply_slow(opts["slow"])
			if opts.has("knockback"):
				var d := off.length()
				if d > 0.0:
					e.global_position += off / d * opts["knockback"] * 0.06

func spawn_player_projectile(pos: Vector2, vel: Vector2, dmg: float, crit: bool, pierce: int, r: float, col: Color, on_hit := Callable()) -> void:
	var pr := preload("res://scripts/Projectile.gd").new()
	pr.setup(pos, vel, dmg, crit, pierce, r, col, on_hit)
	_world.add_child(pr)

func _trigger_victory() -> void:
	if _state != "playing":
		return
	_state = "won"
	_end_run("Victory!")

# ── Level-up: pick an ability (ported from openLevelUp in js/game.js) ──────────
func _on_level_up() -> void:
	_pending_levels += 1
	if not _leveling:
		_open_level_up()

func _open_level_up() -> void:
	while _pending_levels > 0:
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
	add_child(_level_ui)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_level_ui.add_child(dim)
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.position = Vector2(40, 120); vbox.custom_minimum_size = Vector2(400, 0)
	vbox.add_theme_constant_override("separation", 10)
	_level_ui.add_child(vbox)
	var title := Label.new()
	title.text = "Level %d — choose:" % _player.level
	vbox.add_child(title)
	for opt in opts:
		var def: Dictionary = opt["ability"]
		var b := Button.new()
		var tag := "NEW" if opt["is_new"] else "Rank %d→%d" % [opt["next_rank"] - 1, opt["next_rank"]]
		b.text = "%s  %s [%s]\n%s" % [def["icon"], def["name"], tag, Abilities.describe(def, opt["next_rank"])]
		b.custom_minimum_size = Vector2(400, 56)
		b.pressed.connect(_pick_ability.bind(opt))
		vbox.add_child(b)

func _pick_ability(opt: Dictionary) -> void:
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

# ── HUD ───────────────────────────────────────────────────────────────────────
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_lbl_level = Label.new(); _lbl_level.position = Vector2(12, 8); layer.add_child(_lbl_level)
	_lbl_time = Label.new(); _lbl_time.position = Vector2(380, 8); layer.add_child(_lbl_time)
	var hp_bg := ColorRect.new()
	hp_bg.color = Color(0, 0, 0, 0.5); hp_bg.position = Vector2(12, 34); hp_bg.size = Vector2(_hp_w, 12)
	layer.add_child(hp_bg)
	_hp_fill = ColorRect.new()
	_hp_fill.color = Color("d23b3b"); _hp_fill.position = Vector2(12, 34); _hp_fill.size = Vector2(_hp_w, 12)
	layer.add_child(_hp_fill)
	var ab_btn := Button.new()
	ab_btn.text = "✦"; ab_btn.position = Vector2(390, 720); ab_btn.custom_minimum_size = Vector2(72, 72)
	ab_btn.pressed.connect(func(): if _player: _player.use_movement_ability())
	layer.add_child(ab_btn)

	# Boss health bar (hidden until a boss is present).
	_lbl_boss_name = Label.new(); _lbl_boss_name.position = Vector2(100, 52)
	_lbl_boss_name.visible = false; layer.add_child(_lbl_boss_name)
	_boss_bg = ColorRect.new()
	_boss_bg.color = Color(0, 0, 0, 0.5); _boss_bg.position = Vector2(100, 70); _boss_bg.size = Vector2(_boss_w, 10)
	_boss_bg.visible = false; layer.add_child(_boss_bg)
	_boss_fill = ColorRect.new()
	_boss_fill.color = Color("b14a8a"); _boss_fill.position = Vector2(100, 70); _boss_fill.size = Vector2(_boss_w, 10)
	_boss_fill.visible = false; layer.add_child(_boss_fill)

	# Event banner (mini-boss/final-boss announcements).
	_lbl_banner = Label.new()
	_lbl_banner.position = Vector2(60, 160); _lbl_banner.custom_minimum_size = Vector2(360, 0)
	_lbl_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_banner.visible = false
	layer.add_child(_lbl_banner)

func _update_hud() -> void:
	_lbl_level.text = "Lv %d" % _player.level
	_lbl_time.text = "%d:%02d" % [int(elapsed) / 60, int(elapsed) % 60]
	_hp_fill.size.x = _hp_w * clampf(_player.hp / _player.max_hp, 0.0, 1.0)

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
func _end_run(title: String) -> void:
	get_tree().paused = true
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
	dim.color = Color(0, 0, 0, 0.7); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_ui.add_child(dim)
	var vbox := VBoxContainer.new()
	vbox.position = Vector2(70, 240); vbox.custom_minimum_size = Vector2(340, 0)
	vbox.add_theme_constant_override("separation", 12)
	_end_ui.add_child(vbox)
	var t := Label.new(); t.text = title; vbox.add_child(t)
	var stats := Label.new()
	stats.text = "Time: %d:%02d\nKills: %d\nGold: +%d" % [int(elapsed) / 60, int(elapsed) % 60, run_kills, int(floor(run_gold))]
	vbox.add_child(stats)
	if not fresh.is_empty():
		var lines := ["Unlocked!"]
		for id in fresh:
			var a: Dictionary = GameData.achievement_by_id(id)
			lines.append("%s — %s" % [a["name"], a["unlocks"]])
		var ul := Label.new(); ul.text = "\n".join(lines)
		vbox.add_child(ul)
	var btn := Button.new(); btn.text = "Continue"; btn.custom_minimum_size = Vector2(300, 48)
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
	# Grant one ability per mechanic so every activate() branch runs.
	for aid in ["kn_bash", "kn_slam", "kn_spears", "ar_scatter", "mg_chain", "kn_whirl", "kn_charge", "mg_blink"]:
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
