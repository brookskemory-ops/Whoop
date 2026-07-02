extends Node2D
## Floating combat text, spawned once per hit from Enemy.take_damage() so
## every damage source (weapon, ability, orbit, burn/DoT) shows feedback
## through a single chokepoint.

var _t := 0.0
var _life := 0.6
var _rise := 34.0
var _pop := 1.0

func setup(amount: float, crit: bool) -> void:
	var lbl := Label.new()
	lbl.text = str(maxi(1, roundi(amount)))
	lbl.add_theme_font_override("font", UiTheme.body_font())
	lbl.add_theme_font_size_override("font_size", 24 if crit else 15)
	lbl.add_theme_color_override("font_color", UiTheme.GOLD_BRIGHT if crit else Color("ece3cf"))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("outline_size", 4 if crit else 3)
	add_child(lbl)
	position += Vector2(randf_range(-8.0, 8.0), -4.0)
	if crit:
		_rise = 46.0
		_pop = 1.7   # crits punch in from larger scale

func _process(delta: float) -> void:
	_t += delta
	if _t >= _life:
		queue_free()
		return
	position.y -= _rise * delta
	_pop = move_toward(_pop, 1.0, delta * 6.0)
	scale = Vector2.ONE * _pop
	modulate.a = 1.0 - clampf((_t - 0.3) / (_life - 0.3), 0.0, 1.0)
