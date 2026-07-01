class_name Vfx
extends RefCounted
## Lightweight particle-burst / ring helpers used for death bursts, pickups,
## level-ups, and boss telegraphs — replacing flat draw_circle-only feedback.

static var _dot_tex: ImageTexture

static func _dot() -> ImageTexture:
	if _dot_tex == null:
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		for y in 8:
			for x in 8:
				if Vector2(x - 3.5, y - 3.5).length() <= 3.5:
					img.set_pixel(x, y, Color(1, 1, 1, 1))
		_dot_tex = ImageTexture.create_from_image(img)
	return _dot_tex

## One-shot radial particle burst (hit sparks, death bursts, pickup sparkle).
static func burst(world: Node, pos: Vector2, color: Color, amount: int = 14, speed: float = 220.0, life: float = 0.4, size: float = 3.0) -> void:
	if world == null or not is_instance_valid(world):
		return
	var p := CPUParticles2D.new()
	world.add_child(p)
	p.global_position = pos
	p.texture = _dot()
	p.emitting = false
	p.one_shot = true
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 1.0
	p.direction = Vector2.RIGHT
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.35
	p.initial_velocity_max = speed
	p.gravity = Vector2.ZERO
	p.damping_min = speed * 1.2
	p.damping_max = speed * 2.0
	p.scale_amount_min = size * 0.5
	p.scale_amount_max = size
	p.color = color
	p.z_index = 60
	p.emitting = true
	world.get_tree().create_timer(life + 0.15).timeout.connect(func():
		if is_instance_valid(p): p.queue_free()
	)

## Expanding, fading ring — used for level-ups, boss-spawn telegraphs, and
## nova/slam ability impacts.
static func ring(world: Node, pos: Vector2, color: Color, max_radius: float = 60.0, life: float = 0.4) -> void:
	if world == null or not is_instance_valid(world):
		return
	var r := preload("res://scripts/VfxRing.gd").new()
	r.global_position = pos
	r.color = color
	r.max_radius = max_radius
	r.life = life
	r.z_index = 60
	world.add_child(r)

## Fading connector line — used by chain-mechanic abilities to show the
## lightning/light/dagger leaping from one foe to the next.
static func chain_link(world: Node, from: Vector2, to: Vector2, color: Color, width: float = 2.5, life: float = 0.25) -> void:
	if world == null or not is_instance_valid(world):
		return
	var l := preload("res://scripts/VfxChainLink.gd").new()
	l.global_position = from
	l.width = width
	l.default_color = color
	l.add_point(Vector2.ZERO)
	l.add_point(to - from)
	l.life = life
	l.z_index = 55
	world.add_child(l)
