extends StaticBody2D
## A blocking terrain prop (tree/rock/pillar/rubble) scattered across a
## bounded stage. Player/Enemy are CharacterBody2D using move_and_slide(),
## so this needs no special-case movement code — collision "just works".

func setup(tex: Texture2D, collision_radius: float) -> void:
	var spr := Sprite2D.new()
	spr.texture = tex
	add_child(spr)
	var shape := CircleShape2D.new()
	shape.radius = collision_radius
	var col := CollisionShape2D.new()
	col.shape = shape
	add_child(col)
