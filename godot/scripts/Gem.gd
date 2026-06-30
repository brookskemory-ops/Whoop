extends Node2D
## XP/gold pickup. Drifts toward the player within pickup range, then is
## collected on contact.

const PICKUP_RANGE := 75.0
var _xp := 1.0
var _gold := 1.0
var radius := 5.0

func setup(pos: Vector2, xp: float, gold: float) -> void:
	global_position = pos
	_xp = xp; _gold = gold

func _process(delta: float) -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var player: Player = players[0]
	var to := player.global_position - global_position
	var d := to.length()
	if d < PICKUP_RANGE:
		global_position += to.normalized() * 340.0 * delta
	if d < player_radius(player) + radius:
		player.gain_xp(_xp)
		var main := get_tree().current_scene
		if main and main.has_method("add_gold"):
			main.add_gold(_gold)
		queue_free()

func player_radius(_p: Node2D) -> float:
	return 14.0

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, Color("4ad6e8"))
