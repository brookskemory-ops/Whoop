extends Node2D
## Mage's Frost Bolt: a single projectile that curves toward the nearest
## foe over its lifetime and slows on impact.

var _vel := Vector2.ZERO
var _speed := 260.0
var _turn := 500.0
var _dmg := 10.0
var _crit := false
var _life := 3.0
var radius := 7.0
var _color := Color.WHITE
var _slow := 0.0

func setup(pos: Vector2, dir: Vector2, speed: float, dmg: float, crit: bool, r: float, col: Color, slow: float = 0.0) -> void:
	global_position = pos
	_vel = dir.normalized() * speed
	_speed = speed; _dmg = dmg; _crit = crit; radius = r; _color = col; _slow = slow

func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	var target: Node2D = null
	var bd := INF
	for e in get_tree().get_nodes_in_group("enemies"):
		var d := global_position.distance_squared_to(e.global_position)
		if d < bd: bd = d; target = e
	if target:
		var desired := (target.global_position - global_position).normalized() * _speed
		_vel = _vel.move_toward(desired, _turn * delta)
	global_position += _vel * delta
	for e in get_tree().get_nodes_in_group("enemies"):
		if global_position.distance_to(e.global_position) < radius + e.radius:
			e.take_damage(_dmg, _crit)
			if _slow > 0.0: e.apply_slow(_slow)
			queue_free()
			return
	queue_redraw()

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius * 1.8, Color(_color.r, _color.g, _color.b, 0.25))
	draw_circle(Vector2.ZERO, radius, _color)
	draw_circle(Vector2.ZERO, radius * 0.4, Color(1, 1, 1, 0.8))
