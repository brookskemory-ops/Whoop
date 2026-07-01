extends Node2D
## Expanding, fading ring — spawned by Vfx.ring() for level-ups and boss
## spawn/kill telegraphs.

var color := Color.WHITE
var max_radius := 60.0
var life := 0.4
var _t := 0.0

func _process(delta: float) -> void:
	_t += delta
	if _t >= life:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var f := _t / life
	var r: float = lerp(6.0, max_radius, f)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, Color(color.r, color.g, color.b, color.a * (1.0 - f)), 3.0)
