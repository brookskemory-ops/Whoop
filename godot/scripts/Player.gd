class_name Player
extends CharacterBody2D
## Player avatar. Movement + the 8-direction animation state machine (ported from
## js/game.js), driving the PixelLab sprite art, plus the class weapon (Weapons.gd)
## and orbital groups.

signal died
signal leveled_up

const SPRITE_SCALE := 1.5

var cls_id := "knight"
var max_hp := 140.0
var hp := 140.0
var move_speed := 175.0
var damage := 12.0
var crit := 0.03
var regen := 0.2

# Combat stats (DEFAULTS in js/game.js).
var proj_speed := 420.0
var proj_size := 6.0
var pierce := 0
var aoe_mult := 1.0
var crit_mult := 2.0
var proj_count := 1

# Permanent meta-upgrades (applied in setup() from GameSave.class_upgrades).
var revives := 0
var fortune_gold := 1.0
var fortune_xp := 1.0

var weapon_id := "arming_sword"
var weapon_type := "melee"
var orbit_groups: Array = []
var skills: Array = []          # active abilities: {id, rank, timer}
var dash = null                 # {vel, time, hit_mult, hits}

# Shield pool shared by Knight's Bulwark Stance (burst refresh, no passive
# regen) and Mage's Mana Shield (passive, regenerates via shield_regen).
var shield := 0.0
var shield_max := 0.0
var shield_regen := 0.0

# Archer's Eagle Eye: standing still stacks bonus crit chance (added
# straight into `crit`), reset the moment the player moves.
var focus_rank := 0
var focus_max_stacks := 0
var focus_step := 0.0
var _focus_timer := 0.0
var _focus_bonus := 0.0

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

func setup(id: String, chosen_weapon_id: String = "") -> void:
	cls_id = id
	var c: Dictionary = GameData.CLASSES[id]
	max_hp = c["max_hp"]
	move_speed = c["speed"]; damage = c["damage"]; crit = c["crit"]; regen = c["regen"]
	weapon_id = chosen_weapon_id if chosen_weapon_id != "" else c["weapon"]
	var wm: Dictionary = GameData.WEAPON_META[weapon_id]
	weapon_type = wm["type"]
	attack_cooldown = wm["cooldown"]
	_has_anim = GameData.ANIMATED_CLASSES.has(id)

	# Apply permanent upgrades bought in the Armory (ported from createPlayer).
	# Upgrades are per-class — read this class's own track, not a shared pool.
	var u: Dictionary = GameSave.class_upgrades.get(id, {})
	max_hp += float(u.get("vigor", 0)) * 20.0
	damage *= 1.0 + float(u.get("might", 0)) * 0.08
	move_speed *= 1.0 + float(u.get("haste", 0)) * 0.05
	fortune_gold = 1.0 + float(u.get("fortune", 0)) * 0.10
	fortune_xp = 1.0 + float(u.get("fortune", 0)) * 0.08
	revives = int(u.get("revive", 0))
	hp = max_hp

func _ready() -> void:
	add_to_group("player")
	_spr.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	add_child(_spr)
	if weapon_type == "orbital":
		Weapons.init_weapon(weapon_id, self)

func radius() -> float:
	return 14.0

func add_orbit_group(count: int, mult: float, dist: float, speed: float, r: float, col: Color) -> void:
	orbit_groups.append({"key": "weapon", "count": count, "mult": mult, "dist": dist, "speed": speed, "radius": r, "color": col, "orbs": []})

func _physics_process(delta: float) -> void:
	var main := get_tree().current_scene
	if dash != null:
		velocity = dash["vel"]
		move_and_slide()
		moving = true
		facing = dash["vel"].angle()
		if dash["hit_mult"] > 0.0:
			for e in get_tree().get_nodes_in_group("enemies"):
				var id := e.get_instance_id()
				if not dash["hits"].has(id) and global_position.distance_to(e.global_position) < radius() + e.radius + 6.0:
					dash["hits"][id] = true
					e.take_damage(damage * dash["hit_mult"], false)
		dash["time"] -= delta
		if dash["time"] <= 0.0:
			dash = null
	else:
		moving = move_dir.length() > 0.1
		velocity = move_dir.normalized() * move_speed if moving else Vector2.ZERO
		move_and_slide()

	var foe := _nearest_enemy()
	if foe != null:
		facing = (foe.global_position - global_position).angle()
	elif moving:
		facing = move_dir.angle()

	if regen > 0.0:
		hp = min(max_hp, hp + regen * delta)
	if invuln > 0.0:
		invuln -= delta
	if shield_max > 0.0 and shield < shield_max:
		shield = minf(shield_max, shield + shield_regen * delta)

	if focus_rank > 0:
		if moving:
			if _focus_bonus > 0.0:
				crit -= _focus_bonus
				_focus_bonus = 0.0
			_focus_timer = 0.0
		else:
			_focus_timer += delta
			var target_bonus: float = minf(focus_max_stacks, floor(_focus_timer)) * focus_step
			if target_bonus != _focus_bonus:
				crit += target_bonus - _focus_bonus
				_focus_bonus = target_bonus

	# Class weapon (orbital weapons fire continuously via the orbital tick).
	if weapon_type != "orbital":
		_attack_timer -= delta
		if _attack_timer <= 0.0:
			Weapons.fire(weapon_id, self, main)
			GameAudio.sfx("cast")
			_attack_timer = attack_cooldown
			_atk_t = 0.3

	# Active abilities: attack abilities auto-fire on their cooldown.
	for s in skills:
		var def := Abilities.by_id(s["id"])
		if Abilities.kind_of(def) == "attack":
			s["timer"] -= delta
			if s["timer"] <= 0.0:
				Abilities.activate(def, self, main, s["rank"])
				GameAudio.sfx("cast")
				s["timer"] = Abilities.cooldown(def, s["rank"])
				_atk_t = 0.3
		elif s["timer"] > 0.0:
			s["timer"] -= delta

	_tick_orbitals(delta, main)
	_update_anim(delta)

func use_movement_ability() -> void:
	var main := get_tree().current_scene
	for s in skills:
		var def := Abilities.by_id(s["id"])
		if Abilities.kind_of(def) == "movement" and s["timer"] <= 0.0:
			Abilities.activate(def, self, main, s["rank"])
			GameAudio.sfx("cast")
			s["timer"] = Abilities.cooldown(def, s["rank"])
			return

func start_dash(dir: Vector2, dist: float, hit_mult: float) -> void:
	var dur := 0.16
	dash = {"vel": dir * dist / dur, "time": dur, "hit_mult": hit_mult, "hits": {}}
	invuln = maxf(invuln, 0.3)

func owned_ranks() -> Dictionary:
	var m := {}
	for s in skills:
		m[s["id"]] = s["rank"]
	return m

func apply_pick(option: Dictionary) -> void:
	var def: Dictionary = option["ability"]
	var inst = null
	for s in skills:
		if s["id"] == def["id"]:
			inst = s; break
	if inst == null:
		inst = {"id": def["id"], "rank": 0, "timer": 0.0}
		skills.append(inst)
	inst["rank"] = option["next_rank"]
	if Abilities.kind_of(def) == "orbit":
		Abilities.sync_orbit(def, self, inst["rank"])
	elif Abilities.kind_of(def) == "passive":
		Abilities.apply_passive(def, self, inst["rank"])

func sync_orbit_group(key: String, count: int, mult: float, dist: float, speed: float, r: float, col: Color) -> void:
	for g in orbit_groups:
		if g.get("key", "") == key:
			g["count"] = count; g["mult"] = mult; g["dist"] = dist
			g["speed"] = speed; g["radius"] = r; g["color"] = col
			return
	orbit_groups.append({"key": key, "count": count, "mult": mult, "dist": dist, "speed": speed, "radius": r, "color": col, "orbs": []})

func _tick_orbitals(delta: float, main: Node) -> void:
	for g in orbit_groups:
		var orbs: Array = g["orbs"]
		while orbs.size() < g["count"]:
			var vis := preload("res://scripts/OrbVisual.gd").new()
			vis.radius = g["radius"]; vis.color = g["color"]
			add_child(vis)
			orbs.append({"angle": randf() * TAU, "hits": {}, "node": vis})
		while orbs.size() > g["count"]:
			var o: Dictionary = orbs.pop_back()
			o["node"].queue_free()
		var n := orbs.size()
		for i in n:
			var orb: Dictionary = orbs[i]
			orb["angle"] += g["speed"] * delta
			var a: float = orb["angle"] + i * TAU / n
			var off: Vector2 = Vector2(cos(a), sin(a)) * float(g["dist"])
			orb["node"].position = off
			var owpos: Vector2 = global_position + off
			for e in get_tree().get_nodes_in_group("enemies"):
				if owpos.distance_to(e.global_position) < g["radius"] + e.radius:
					var id := e.get_instance_id()
					var last: float = orb["hits"].get(id, -1.0)
					if main.elapsed - last > 0.35:
						orb["hits"][id] = main.elapsed
						var cr := randf() < crit
						e.take_damage(damage * g["mult"] * (crit_mult if cr else 1.0), cr)

func take_damage(amount: float) -> void:
	if invuln > 0.0:
		return
	var dmg := amount
	if shield > 0.0:
		var absorb := minf(shield, dmg)
		shield -= absorb
		dmg -= absorb
	hp -= dmg
	invuln = 0.6
	_hurt_t = 0.3
	var main := get_tree().current_scene
	if main and main.has_method("add_shake"):
		main.add_shake(7.0)
	GameAudio.sfx("hurt")
	if hp <= 0.0:
		died.emit()

func gain_xp(amount: float) -> void:
	xp += amount
	while xp >= xp_next:
		xp -= xp_next
		level += 1
		xp_next = floor(xp_next * 1.35 + 3.0)
		leveled_up.emit()

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
	if dash != null: st = "dash"
	elif _atk_t > 0.0: st = "attack"
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
