extends Node2D
## Player projectile: travels in a straight line, damages the first enemy it
## touches. (Pierce/onHit effects from the JS weapons come in a later phase.)

var _vel := Vector2.ZERO
var _dmg := 10.0
var _crit := false
var _life := 1.5
var radius := 6.0

func setup(pos: Vector2, vel: Vector2, dmg: float, crit: bool) -> void:
	global_position = pos
	_vel = vel; _dmg = dmg; _crit = crit

func _process(delta: float) -> void:
	global_position += _vel * delta
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	for e in get_tree().get_nodes_in_group("enemies"):
		if global_position.distance_to(e.global_position) < radius + e.radius:
			e.take_damage(_dmg, _crit)
			queue_free()
			return

func _draw() -> void:
	var c := Color("ffd34d") if _crit else Color("ffe27a")
	draw_circle(Vector2.ZERO, radius, c)
