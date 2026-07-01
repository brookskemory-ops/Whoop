extends Line2D
## Fading connector line — spawned by Vfx.chain_link() for chain-mechanic
## abilities (lightning/holy light/dagger leaps between foes).

var life := 0.25
var _t := 0.0

func _process(delta: float) -> void:
	_t += delta
	if _t >= life:
		queue_free()
		return
	modulate.a = 1.0 - (_t / life)
