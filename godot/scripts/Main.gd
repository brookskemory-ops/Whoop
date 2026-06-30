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

func on_final_boss_killed() -> void:
	pass  # victory state — Phase 2

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
	# Force one of every archetype so all AI branches run at least once.
	for key in ["shooter", "exploder", "splitter", "charger", "ogre", "miniboss", "finalboss"]:
		add_enemy(key, _player.global_position + Vector2(randf_range(-180, 180), randf_range(-180, 180)), 1.0)
	var t := 0.0
	while t < 8.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		_test_dir = Vector2(cos(t), sin(t * 0.7))
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
	print("[SELFTEST] elapsed=%.1f hp=%.0f/%.0f level=%d enemies=%d kills=%d gold=%.0f proj=%d gems=%d anim_texture_ok=%s moved=%s" % [
		elapsed, _player.hp, _player.max_hp, _player.level, enemies, run_kills, run_gold,
		projectiles, gems, str(sprite_ok), str(_player.global_position.length() > 1.0)])
	get_tree().quit(0)
