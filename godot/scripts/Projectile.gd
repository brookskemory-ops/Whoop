extends Node2D
## Player projectile. Supports pierce and an optional on-hit callback (e.g.
## fireball's burst). Ported from the projectiles loop + weapon onHit in the JS.

var _vel := Vector2.ZERO
var _dmg := 10.0
var _crit := false
var _pierce := 0
var _life := 1.5
var radius := 6.0
var _color := Color("ffe27a")
var _on_hit := Callable()
var _hit_ids := {}

func setup(pos: Vector2, vel: Vector2, dmg: float, crit: bool, pierce: int, r: float, col: Color, on_hit := Callable()) -> void:
	global_position = pos
	_vel = vel; _dmg = dmg; _crit = crit; _pierce = pierce; radius = r; _color = col; _on_hit = on_hit

func _process(delta: float) -> void:
	global_position += _vel * delta
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	for e in get_tree().get_nodes_in_group("enemies"):
		var id := e.get_instance_id()
		if _hit_ids.has(id):
			continue
		if global_position.distance_to(e.global_position) < radius + e.radius:
			e.take_damage(_dmg, _crit)
			_hit_ids[id] = true
			if _on_hit.is_valid():
				_on_hit.call(global_position)
			if _pierce > 0:
				_pierce -= 1
			else:
				queue_free()
				return

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, _color)
