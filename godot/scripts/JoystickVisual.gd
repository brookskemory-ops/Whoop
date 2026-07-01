extends Control
## Touch joystick ring + knob, ported from the `if (joy.active) {...}` draw
## block in js/game.js's render(). Positions are screen-space pixels (same
## space as the touch/mouse events Main tracks), so this sits in the HUD
## CanvasLayer and needs no camera-space conversion.

const RADIUS := 50.0
const KNOB_RADIUS := 24.0

var active := false
var base := Vector2.ZERO
var knob := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if not active:
		return
	draw_arc(base, RADIUS, 0.0, TAU, 32, Color(0.94, 0.78, 0.41, 0.5), 3.0, true)
	draw_circle(knob, KNOB_RADIUS, Color(0.94, 0.78, 0.41, 0.6))
