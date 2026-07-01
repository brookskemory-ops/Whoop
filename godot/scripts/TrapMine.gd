extends Node2D
## Archer's Explosive Trap: sits armed until a foe wanders within
## trigger_radius, then detonates an AoE burst and self-destructs.

var trigger_radius := 50.0
var blast_radius := 70.0
var dmg := 10.0
var color := Color.WHITE
var _arm_delay := 0.2
var _life := 8.0

func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	if _arm_delay > 0.0:
		_arm_delay -= delta
		queue_redraw()
		return
	for e in get_tree().get_nodes_in_group("enemies"):
		if global_position.distance_to(e.global_position) < trigger_radius:
			_explode()
			return
	queue_redraw()

func _explode() -> void:
	var main := get_tree().current_scene
	if main == null:
		queue_free()
		return
	main.area_damage_amount(global_position, blast_radius, dmg, {"color": color})
	var world := main.get_node("World")
	Vfx.ring(world, global_position, color, blast_radius, 0.3)
	Vfx.burst(world, global_position, color, 16, 200.0, 0.35, 3.5)
	queue_free()

func _draw() -> void:
	draw_circle(Vector2.ZERO, 5.0, color)
	draw_arc(Vector2.ZERO, trigger_radius, 0.0, TAU, 20, Color(color.r, color.g, color.b, 0.35), 1.5)
