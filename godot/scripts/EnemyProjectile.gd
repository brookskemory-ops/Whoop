extends Node2D
## Enemy projectile (shooter/boss bursts). Travels straight; damages the player
## on contact. Ported from the enemyProjectiles loop in js/game.js.

var _vel := Vector2.ZERO
var _dmg := 8.0
var _color := Color("ff7a5a")
var _life := 3.5
var radius := 6.0

func setup(pos: Vector2, vel: Vector2, dmg: float, col: Color) -> void:
	global_position = pos
	_vel = vel; _dmg = dmg; _color = col

func _process(delta: float) -> void:
	global_position += _vel * delta
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var p: Player = players[0]
	if global_position.distance_to(p.global_position) < radius + p.radius():
		p.take_damage(_dmg)
		queue_free()

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius * 2.0, Color(_color.r, _color.g, _color.b, 0.25))
	draw_circle(Vector2.ZERO, radius, _color)
	draw_circle(Vector2.ZERO, radius * 0.4, Color(1, 1, 1, 0.7))
