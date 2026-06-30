extends Node2D
## Run controller: builds the world (floor, player, camera), drives spawning,
## input (touch joystick + keyboard) and the HUD. Foundation slice ported from
## js/game.js — menus, abilities, bosses and meta-progression come in later phases.

const SELECTED_CLASS := "knight"
const WIN_TIME := 600.0

var elapsed := 0.0
var run_gold := 0.0
var run_kills := 0
var _spawn_timer := 0.0

var _world: Node2D
var _player: Player
var _camera: Camera2D

# HUD
var _lbl_level: Label
var _lbl_time: Label
var _hp_fill: ColorRect
var _hp_w := 200.0

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
	_build_world()
	_build_hud()
	_start_run()
	if "--selftest" in OS.get_cmdline_user_args() or "--selftest" in OS.get_cmdline_args():
		_run_selftest()

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

func _start_run() -> void:
	_player = Player.new()
	_player.setup(SELECTED_CLASS)
	_player.died.connect(_on_player_died)
	_player.leveled_up.connect(_on_level_up)
	_world.add_child(_player)

	_camera = Camera2D.new()
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = 8.0
	_player.add_child(_camera)
	_camera.make_current()

	elapsed = 0.0; run_gold = 0.0; run_kills = 0; _spawn_timer = 0.0

func add_gold(amount: float) -> void:
	run_gold += amount

func add_kill() -> void:
	run_kills += 1

func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	elapsed += delta
	_player.move_dir = _test_dir if _testing else _read_input()

	# Spawn director: interval tightens over the run (ported from js/game.js).
	_spawn_timer -= delta
	var interval: float = max(0.16, 1.1 - elapsed * 0.01)
	if _spawn_timer <= 0.0:
		_spawn_enemy()
		_spawn_timer = interval

	_update_hud()

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

func on_final_boss_killed() -> void:
	pass  # victory state — Phase 2

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

func _update_hud() -> void:
	_lbl_level.text = "Lv %d" % _player.level
	_lbl_time.text = "%d:%02d" % [int(elapsed) / 60, int(elapsed) % 60]
	_hp_fill.size.x = _hp_w * clampf(_player.hp / _player.max_hp, 0.0, 1.0)

func _on_player_died() -> void:
	# Foundation: just restart the run. Game-over screen + meta come later.
	for c in _world.get_children():
		c.queue_free()
	call_deferred("_build_world")
	call_deferred("_start_run")

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
