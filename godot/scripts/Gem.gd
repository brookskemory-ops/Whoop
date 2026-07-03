extends Node2D
## XP/gold pickup. Drifts toward the player within pickup range, then is
## collected on contact. Rendered as the PixelLab arcane-gem icon with a
## gentle bob + spin so it reads clearly against the floor tiles.

const PICKUP_RANGE := 150.0
var _xp := 1.0
var _gold := 1.0
var radius := 5.0
var _t := randf() * TAU
var _spr: Sprite2D

func setup(pos: Vector2, xp: float, gold: float) -> void:
	global_position = pos
	_xp = xp; _gold = gold

func _ready() -> void:
	_spr = Sprite2D.new()
	_spr.texture = load("res://assets/items/gem.png")
	_spr.scale = Vector2.ONE * 0.9
	add_child(_spr)

func _process(delta: float) -> void:
	_t += delta
	_spr.position.y = sin(_t * 3.0) * 3.0
	_spr.scale.x = 0.9 * (0.8 + 0.2 * cos(_t * 2.2))

	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var player: Player = players[0]
	var to := player.global_position - global_position
	var d := to.length()
	if d < PICKUP_RANGE:
		# Accelerate as it nears so pickups snap in cleanly instead of loitering.
		var pull := 260.0 + (1.0 - d / PICKUP_RANGE) * 340.0
		global_position += to.normalized() * pull * delta
	if d < player.radius() + radius:
		player.gain_xp(_xp * player.fortune_xp)
		var main := get_tree().current_scene
		if main and main.has_method("add_gold"):
			main.add_gold(_gold * player.fortune_gold)
		GameAudio.sfx("pickup")
		Vfx.burst(get_parent(), global_position, Color("4ad6e8"), 6, 110.0, 0.25, 2.0)
		queue_free()
