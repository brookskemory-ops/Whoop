extends Node2D
## Lingering ground-zone hazard (Mage's Cinder Field / Meteor's burning
## crater). Ticks damage to anything standing inside for its duration.

var radius := 60.0
var dps := 5.0
var duration := 3.0
var color := Color.WHITE
var _t := 0.0
var _tick := 0.0

func _process(delta: float) -> void:
	_t += delta
	if _t >= duration:
		queue_free()
		return
	_tick -= delta
	if _tick <= 0.0:
		var main := get_tree().current_scene
		if main:
			main.area_damage_amount(global_position, radius, dps * 0.25, {"color": color})
		_tick = 0.25
	queue_redraw()

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, Color(color.r, color.g, color.b, 0.22))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 24, Color(color.r, color.g, color.b, 0.55), 2.0)
