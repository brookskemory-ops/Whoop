extends Node2D
## A single orbiting weapon orb (whirlwind axe / censer). Positioned by the
## Player's orbital tick; just draws itself.

var radius := 14.0
var color := Color("ffffff")

func _ready() -> void:
	queue_redraw()

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius * 1.5, Color(color.r, color.g, color.b, 0.22))
	draw_circle(Vector2.ZERO, radius * 0.8, color)
	draw_circle(Vector2.ZERO, radius * 0.32, Color(1, 1, 1, 0.8))
