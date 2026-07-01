extends Node2D
## Archer's Bombardment: a growing warning ring that detonates into an
## AoE strike after a short delay, giving enemies (and the player) a
## beat to react before the arrows land.

var radius := 75.0
var dmg := 10.0
var delay := 0.8
var color := Color.WHITE
var _t := 0.0

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if _t >= delay:
		var main := get_tree().current_scene
		if main:
			main.area_damage_amount(global_position, radius, dmg, {"color": color})
			var world := main.get_node("World")
			Vfx.ring(world, global_position, color, radius, 0.3)
			Vfx.burst(world, global_position, color, 16, 200.0, 0.35, 3.5)
		queue_free()

func _draw() -> void:
	var f := _t / delay
	draw_arc(Vector2.ZERO, radius * (0.3 + 0.7 * f), 0.0, TAU, 24, Color(color.r, color.g, color.b, 0.15 + 0.5 * f), 2.0)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 24, Color(color.r, color.g, color.b, 0.5), 1.0)
