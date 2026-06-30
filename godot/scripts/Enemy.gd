extends CharacterBody2D
## Data-driven enemy. `kind` selects the AI, ported from js/enemies.js
## (tickEnemyAI + onEnemyDeath). Drawn as a shape for now (sprite art is Phase 4).

var kind := "chaser"
var hp := 18.0
var max_hp := 18.0
var base_speed := 70.0
var dmg := 8.0
var radius := 12.0
var xp := 1.0
var gold := 1.0
var color := Color("d6d3c4")
var is_boss := false
var is_final := false
var elite := false

var slow_until := 0.0
var burn_dps := 0.0
var burn_until := 0.0
var facing := 0.0
var telegraph := false
var _hit_flash := 0.0

# Per-kind AI state
var _shoot_t := 1.2
var _charge_state := "chase"
var _ct := 0.0
var _charge_vel := Vector2.ZERO
var _atk := 0.0
var _phase := 0.0
var _ap := 0

func setup(key: String, scale_mult: float) -> void:
	var b: Dictionary = GameData.ENEMY_BASE[key]
	kind = b["kind"]
	radius = b["r"]
	hp = b["hp"] * scale_mult
	max_hp = hp
	base_speed = b["speed"]
	dmg = b["dmg"]
	color = Color(b["color"])
	gold = b["gold"]
	xp = b["xp"]
	is_boss = b.get("boss", false)
	is_final = b.get("final", false)
	add_to_group("enemies")

func _physics_process(delta: float) -> void:
	var main := get_tree().current_scene
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty() or main == null:
		return
	var p: Player = players[0]
	var to := p.global_position - global_position
	var d := to.length()
	var a := to.angle()
	facing = a
	var slow := 0.5 if slow_until > main.elapsed else 1.0
	var dir := Vector2(cos(a), sin(a))

	if _hit_flash > 0.0:
		_hit_flash -= delta
		queue_redraw()
	if burn_until > main.elapsed and burn_dps > 0.0:
		# Burn ticks bypass take_damage()'s sfx/hit-flash (ported from the direct
		# `e.hp -= e.burn.dps * dt` in js/game.js, not damageEnemy()).
		hp -= burn_dps * delta
		if hp <= 0.0:
			_die()
			return

	var vel := Vector2.ZERO
	match kind:
		"chaser":
			vel = dir * base_speed * slow
		"shooter":
			if d > 280.0: vel = dir * base_speed * slow
			elif d < 210.0: vel = -dir * base_speed * slow
			else: vel = dir.orthogonal() * base_speed * 0.5 * slow
			_shoot_t -= delta
			if _shoot_t <= 0.0 and d < 460.0:
				main.spawn_enemy_projectile(global_position, dir * 200.0, dmg, Color("9ad0ff"))
				_shoot_t = 1.7
		"exploder":
			vel = dir * base_speed * slow
			if d < radius + p.radius() + 2.0:
				hp = 0.0
		"splitter":
			vel = dir * base_speed * slow
		"charger":
			match _charge_state:
				"chase":
					vel = dir * base_speed * slow
					if d < 320.0: _charge_state = "wind"; _ct = 0.7; telegraph = true
				"wind":
					_ct -= delta
					if _ct <= 0.0: _charge_vel = dir * 440.0; _charge_state = "charge"; _ct = 0.5; telegraph = false
				"charge":
					vel = _charge_vel; _ct -= delta
					if _ct <= 0.0: _charge_state = "cool"; _ct = 1.1
				_:
					_ct -= delta
					if _ct <= 0.0: _charge_state = "chase"
		"miniboss":
			if d > 90.0: vel = dir * base_speed * slow
			_atk -= delta
			if _atk <= 0.0:
				_radial_burst(main, 12, 150.0, dmg * 0.55, Color("ff7ad0"), _phase)
				_phase += 0.4; _atk = 2.6
		"finalboss":
			if d > 110.0: vel = dir * base_speed * slow
			_atk -= delta
			if _atk <= 0.0:
				_ap += 1
				if _ap % 2 == 0:
					_phase += 0.3
					_radial_burst(main, 16, 165.0, dmg * 0.5, Color("ff6a5a"), _phase)
				else:
					for i in 3:
						main.add_enemy("spawnling", global_position + Vector2(randf_range(-25, 25), randf_range(-25, 25)), 1.0)
				_atk = 2.2

	velocity = vel
	move_and_slide()

	# Contact damage (all kinds).
	if d < radius + p.radius():
		p.take_damage(dmg)

func _radial_burst(main: Node, n: int, sp: float, d: float, col: Color, phase: float) -> void:
	for i in n:
		var ang := (float(i) / n) * TAU + phase
		main.spawn_enemy_projectile(global_position, Vector2(cos(ang), sin(ang)) * sp, d, col)

func apply_slow(seconds: float) -> void:
	var main := get_tree().current_scene
	if main: slow_until = main.elapsed + seconds

func apply_burn(dps: float, seconds: float) -> void:
	var main := get_tree().current_scene
	if main: burn_dps = dps; burn_until = main.elapsed + seconds

func take_damage(amount: float, crit: bool = false) -> void:
	hp -= amount
	_hit_flash = 0.1
	queue_redraw()
	GameAudio.sfx("crit" if crit else "hit")
	if hp <= 0.0:
		_die()

func _die() -> void:
	var main := get_tree().current_scene
	if main == null or not is_instance_valid(self):
		return
	GameAudio.sfx("enemyDie")
	# Death effects (onEnemyDeath in js/enemies.js).
	if kind == "exploder":
		main.hurt_area(global_position, 64.0, dmg)
	elif kind == "splitter":
		for i in 3:
			var ang := (float(i) / 3.0) * TAU
			main.add_enemy("spawnling", global_position + Vector2(cos(ang), sin(ang)) * 16.0, 1.0)
	if main.has_method("add_kill"):
		main.add_kill()
	if is_boss and main.has_method("on_boss_killed"):
		main.on_boss_killed(self)
	if is_final:
		# Ported from killEnemy in js/game.js: the final boss triggers victory
		# and the run ends immediately, with no gem drop.
		queue_free()
		return
	var gem := preload("res://scripts/Gem.gd").new()
	gem.setup(global_position, xp, gold)
	main.get_node("World").add_child(gem)
	queue_free()

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, color)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 24, Color("2a2622"), 2.0)
	if elite:
		draw_arc(Vector2.ZERO, radius + 4.0, 0.0, TAU, 24, Color(1.0, 0.82, 0.35, 0.85), 2.0)
	if telegraph:
		draw_arc(Vector2.ZERO, radius + 6.0, 0.0, TAU, 24, Color(1.0, 0.31, 0.24, 0.9), 3.0)
	if _hit_flash > 0.0:
		draw_circle(Vector2.ZERO, radius, Color(1, 1, 1, _hit_flash * 6.0))
