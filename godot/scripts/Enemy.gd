extends CharacterBody2D
## Swarm enemy: chases the player and deals contact damage. Drawn as a simple
## shape for now (enemy sprite art is a later phase). HP scales with run time.

var hp := 20.0
var max_hp := 20.0
var move_speed := 62.0
var dmg := 8.0
var radius := 12.0
var xp := 1.0
var gold := 1.0
var _color := Color("b8b8b8")
var _hit_flash := 0.0

func setup(scale_mult: float) -> void:
	hp = 20.0 * scale_mult
	max_hp = hp
	dmg = 8.0
	radius = 12.0
	add_to_group("enemies")

func _physics_process(delta: float) -> void:
	if _hit_flash > 0.0:
		_hit_flash -= delta
		queue_redraw()
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var player: Player = players[0]
	var to := player.global_position - global_position
	velocity = to.normalized() * move_speed
	move_and_slide()
	if to.length() < radius + 14.0:
		player.take_damage(dmg)

func take_damage(amount: float, _crit: bool = false) -> void:
	hp -= amount
	_hit_flash = 0.1
	queue_redraw()
	if hp <= 0.0:
		_die()

func _die() -> void:
	var main := get_tree().current_scene
	if main and main.has_method("add_kill"):
		main.add_kill()
	var gem := preload("res://scripts/Gem.gd").new()
	gem.setup(global_position, xp, gold)
	get_parent().add_child(gem)
	queue_free()

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, _color)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 20, Color("2a2622"), 2.0)
	if _hit_flash > 0.0:
		draw_circle(Vector2.ZERO, radius, Color(1, 1, 1, _hit_flash * 6.0))
