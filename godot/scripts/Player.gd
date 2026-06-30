class_name Player
extends CharacterBody2D
## Player avatar. Movement + the 8-direction animation state machine ported
## from js/game.js (updatePlayerAnim / render), driving the PixelLab sprite art.

signal died

const SPRITE_SCALE := 0.6

var cls_id := "knight"
var max_hp := 140.0
var hp := 140.0
var move_speed := 175.0
var damage := 12.0
var crit := 0.03
var regen := 0.2

var move_dir := Vector2.ZERO          # set each frame by Main (joystick + keys)
var facing := 0.0
var moving := false
var invuln := 0.0
var level := 1
var xp := 0.0
var xp_next := 5.0

var attack_cooldown := 0.6
var _attack_timer := 0.0
var _atk_t := 0.0
var _hurt_t := 0.0

var _anim_state := "idle"
var _frame := 0
var _anim_t := 0.0
var _has_anim := false
var _tex_cache := {}

@onready var _spr := Sprite2D.new()

func setup(id: String) -> void:
	cls_id = id
	var c: Dictionary = GameData.CLASSES[id]
	max_hp = c["max_hp"]; hp = max_hp
	move_speed = c["speed"]; damage = c["damage"]; crit = c["crit"]; regen = c["regen"]
	_has_anim = GameData.ANIMATED_CLASSES.has(id)

func _ready() -> void:
	add_to_group("player")
	_spr.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	add_child(_spr)

func _physics_process(delta: float) -> void:
	moving = move_dir.length() > 0.1
	velocity = move_dir.normalized() * move_speed if moving else Vector2.ZERO
	move_and_slide()

	# Facing: aim at nearest foe, else move direction.
	var foe := _nearest_enemy()
	if foe != null:
		facing = (foe.global_position - global_position).angle()
	elif moving:
		facing = move_dir.angle()

	if regen > 0.0:
		hp = min(max_hp, hp + regen * delta)
	if invuln > 0.0:
		invuln -= delta

	# Auto-attack: fire at the nearest foe on cooldown.
	_attack_timer -= delta
	if _attack_timer <= 0.0 and foe != null:
		_fire_at(foe)
		_attack_timer = attack_cooldown
		_atk_t = 0.3

	_update_anim(delta)

func _fire_at(foe: Node2D) -> void:
	var dir := (foe.global_position - global_position).normalized()
	var crit_hit := randf() < crit
	var proj := preload("res://scripts/Projectile.gd").new()
	proj.setup(global_position, dir * 420.0, damage * (2.0 if crit_hit else 1.0), crit_hit)
	get_parent().add_child(proj)

func take_damage(amount: float) -> void:
	if invuln > 0.0:
		return
	hp -= amount
	invuln = 0.6
	_hurt_t = 0.3
	if hp <= 0.0:
		died.emit()

func gain_xp(amount: float) -> void:
	xp += amount
	while xp >= xp_next:
		xp -= xp_next
		level += 1
		xp_next = floor(xp_next * 1.35 + 3.0)

func _nearest_enemy() -> Node2D:
	var best: Node2D = null
	var bd := INF
	for e in get_tree().get_nodes_in_group("enemies"):
		var d: float = global_position.distance_squared_to(e.global_position)
		if d < bd:
			bd = d; best = e
	return best

# ── Animation ────────────────────────────────────────────────────────────────
func _update_anim(delta: float) -> void:
	if _atk_t > 0.0: _atk_t -= delta
	if _hurt_t > 0.0: _hurt_t -= delta

	var st := "idle"
	if _atk_t > 0.0: st = "attack"
	elif _hurt_t > 0.0: st = "hurt"
	elif moving: st = "walk"

	if st != _anim_state:
		_anim_state = st; _frame = 0; _anim_t = 0.0

	if not _has_anim:
		return
	var fps: float = GameData.ANIM_FPS[st]
	var n: int = GameData.ANIM_FRAMES[st]
	var loops: bool = GameData.ANIM_LOOP[st]
	_anim_t += delta
	var fd := 1.0 / fps
	while _anim_t >= fd:
		_anim_t -= fd
		_frame += 1
		if _frame >= n:
			_frame = 0 if loops else n - 1

	var dir := GameData.dir_of(facing)
	var flip := false
	if GameData.ANIM_MIRROR.has(dir):
		dir = GameData.ANIM_MIRROR[dir]; flip = true
	var frames := _frames_for(st, dir)
	if frames.is_empty():
		return
	_spr.flip_h = flip
	_spr.texture = frames[min(_frame, frames.size() - 1)]
	# Blink while invulnerable.
	_spr.visible = not (invuln > 0.0 and int(Time.get_ticks_msec() / 50) % 2 == 0)

func _frames_for(state: String, dir: String) -> Array:
	var key := state + "/" + dir
	if not _tex_cache.has(key):
		var arr := []
		for i in GameData.ANIM_FRAMES[state]:
			var p := "res://assets/anim/%s/%s/%s/frame_%03d.png" % [cls_id, state, dir, i]
			if ResourceLoader.exists(p):
				arr.append(load(p))
		_tex_cache[key] = arr
	return _tex_cache[key]
