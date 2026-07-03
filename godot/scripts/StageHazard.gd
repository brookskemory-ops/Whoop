extends Node2D
## Per-stage environmental hazard, scattered across the arena in _rebuild_stage.
## Two behaviours share one node:
##   "field"    — a persistent patch (forest brambles): anything standing inside
##                takes a light DoT and is slowed. Enemies reuse area_damage_amount
##                + apply_slow; the player takes a soft tick (Player.hazard_tick)
##                so it doesn't fire the full hurt feedback every 0.25 s.
##   "periodic" — a trap plate (dungeon spikes): idle → telegraph → strike → repeat.
##                The strike damages both enemies (area_damage_amount) and the
##                player (hurt_area, which respects i-frames), like an exploder blast.

var mode := "field"                    # "field" | "periodic"
var radius := 64.0
var dps := 6.0                         # field: damage per second inside
var dmg := 22.0                        # periodic: strike damage
var slow_mult := 0.6                   # field: movement multiplier while inside
var color := Color("6a9a4a")
var period := 2.6                      # periodic: full cycle length (s)
var telegraph := 0.6                   # periodic: warning window before the strike

const TICK := 0.25                     # field damage cadence
var _tick := 0.0
var _cy := 0.0                         # periodic cycle timer
var _warning := false
var _flash_t := 0.0                    # brief bright pulse right after a strike

func _process(delta: float) -> void:
	var main := get_tree().current_scene
	if main == null:
		return
	if mode == "field":
		_field(main, delta)
	else:
		_periodic(main, delta)
	queue_redraw()

func _field(main: Node, delta: float) -> void:
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK
	var d := dps * TICK
	# Enemies: reuse the same path DamageZone uses (handles death/gems + slow).
	main.area_damage_amount(global_position, radius, d, {"color": color, "slow": TICK + 0.1})
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		var p = players[0]
		if p.global_position.distance_to(global_position) <= radius + p.radius():
			p.hazard_tick(d)
			p.hazard_slow(slow_mult, TICK + 0.1)

func _periodic(main: Node, delta: float) -> void:
	_cy += delta
	if _flash_t > 0.0:
		_flash_t -= delta
	if not _warning and _cy >= period - telegraph:
		_warning = true
	if _cy >= period:
		_cy = 0.0
		_warning = false
		_flash_t = 0.2
		# Strike: enemies + player (hurt_area respects the player's i-frames).
		main.area_damage_amount(global_position, radius, dmg, {"color": color})
		main.hurt_area(global_position, radius, dmg)

func _draw() -> void:
	if mode == "field":
		draw_circle(Vector2.ZERO, radius, Color(color.r, color.g, color.b, 0.20))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 28, Color(color.r, color.g, color.b, 0.5), 2.0)
		# Thorn ticks around the patch.
		for i in 10:
			var a := (float(i) / 10.0) * TAU
			var inner := Vector2(cos(a), sin(a)) * (radius * 0.55)
			var outer := Vector2(cos(a), sin(a)) * (radius * 0.9)
			draw_line(inner, outer, Color(color.r, color.g, color.b, 0.6), 2.0)
	else:
		draw_circle(Vector2.ZERO, radius, Color(0.18, 0.16, 0.14, 0.18))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 28, Color(0.55, 0.5, 0.46, 0.5), 2.0)
		if _warning:
			var pulse := 0.5 + 0.5 * sin(_cy * 30.0)
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 28, Color(1.0, 0.31, 0.24, 0.4 + 0.5 * pulse), 3.0)
		if _flash_t > 0.0:
			draw_circle(Vector2.ZERO, radius, Color(1, 1, 1, _flash_t * 2.5))
			for i in 12:
				var a := (float(i) / 12.0) * TAU
				draw_line(Vector2.ZERO, Vector2(cos(a), sin(a)) * radius, Color(0.9, 0.9, 0.95, _flash_t * 4.0), 2.0)
