extends Node2D
## Archer's Ricochet Shot: a physical projectile that, on hitting a foe,
## redirects toward the next-nearest untouched foe instead of piercing
## straight through (distinct from a chain-mechanic instant zap — this
## actually travels between targets and can miss).

var _vel := Vector2.ZERO
var _dmg := 10.0
var _crit := false
var _bounces := 2
var radius := 6.0
var _color := Color.WHITE
var _life := 3.0
var _hit_ids := {}

func setup(pos: Vector2, vel: Vector2, dmg: float, crit: bool, bounces: int, r: float, col: Color) -> void:
	global_position = pos
	_vel = vel; _dmg = dmg; _crit = crit; _bounces = bounces; radius = r; _color = col

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
			if _bounces <= 0:
				queue_free()
				return
			_bounces -= 1
			var target: Node2D = null
			var bd := INF
			for e2 in get_tree().get_nodes_in_group("enemies"):
				if _hit_ids.has(e2.get_instance_id()): continue
				var d := global_position.distance_squared_to(e2.global_position)
				if d < bd: bd = d; target = e2
			if target == null:
				queue_free()
				return
			_vel = (target.global_position - global_position).normalized() * _vel.length()
			return
	queue_redraw()

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius * 1.8, Color(_color.r, _color.g, _color.b, 0.25))
	draw_circle(Vector2.ZERO, radius, _color)
	draw_circle(Vector2.ZERO, radius * 0.4, Color(1, 1, 1, 0.8))
