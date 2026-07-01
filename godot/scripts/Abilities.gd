class_name Abilities
extends RefCounted
## Active abilities, ported from js/abilities.js. Each ability is a Dictionary
## with a `mech` (nova/slam/volley/radial/chain/orbit/dash/blink) interpreted by
## activate(). `kind` (attack/orbit/movement) drives how the Player uses it.

# kind per mechanic
const KIND := {
	"nova": "attack", "slam": "attack", "volley": "attack", "radial": "attack",
	"chain": "attack", "orbit": "orbit", "dash": "movement", "blink": "movement",
}

static func _d(base: Dictionary, extra: Dictionary) -> Dictionary:
	var out := base.duplicate()
	for k in extra: out[k] = extra[k]
	return out

# Per-class ability pools — LOCKED: exactly 8 abilities per class, one for
# each mechanic (nova/slam/volley/radial/chain/orbit/dash/blink). Keeping a
# 1:1 class-to-mechanic mapping means every class needs the same 8 VFX/art
# templates, just recolored — no bespoke per-class effects to animate.
static func by_class() -> Dictionary:
	return {
		"knight": [
			{"id": "kn_bash", "name": "Shield Bash", "mech": "nova", "icon": "shield slam", "max_rank": 5, "flavor": "Knock foes back around you", "cd": 2.2, "cd_step": 0.15, "rad": 70.0, "rad_step": 12.0, "dmg": 1.2, "dmg_step": 0.4, "knock": 200.0, "color": "dfe7f5"},
			{"id": "kn_slam", "name": "Ground Slam", "mech": "slam", "icon": "cracked earth", "max_rank": 5, "flavor": "Shatter the earth", "cd": 3.0, "cd_step": 0.2, "rad": 80.0, "rad_step": 14.0, "dmg": 1.6, "dmg_step": 0.5, "knock": 140.0, "color": "b9c2d6"},
			{"id": "kn_spears", "name": "Spear Throw", "mech": "volley", "icon": "thrown spear", "max_rank": 5, "flavor": "Hurl spears", "cd": 1.6, "cd_step": 0.1, "count": 1, "count_step": 1, "dmg": 1.0, "pierce": 2, "size": 7.0, "color": "cdd6e6"},
			{"id": "kn_radiance", "name": "Righteous Burst", "mech": "radial", "icon": "holy shards", "max_rank": 5, "flavor": "Holy shards burst outward", "cd": 3.6, "cd_step": 0.2, "count": 6, "count_step": 2, "dmg": 0.65, "size": 6.0, "color": "f5e9b0"},
			{"id": "kn_judgment", "name": "Judgment Chain", "mech": "chain", "icon": "holy arc", "max_rank": 5, "flavor": "Holy light arcs between foes", "cd": 2.0, "cd_step": 0.13, "targets": 3, "target_step": 1, "dmg": 1.0, "color": "f5e9b0"},
			{"id": "kn_whirl", "name": "Whirling Blades", "mech": "orbit", "icon": "orbiting sword", "max_rank": 5, "flavor": "Swords orbit you", "count": 2, "count_step": 1, "dmg": 0.5, "dmg_step": 0.12, "dist": 70.0, "speed": 3.0, "size": 13.0, "color": "cdd6e6"},
			{"id": "kn_charge", "name": "Valor Charge", "mech": "dash", "icon": "charging knight", "max_rank": 5, "flavor": "Charge, trampling foes", "cd": 4.0, "cd_step": 0.3, "dist": 150.0, "dist_step": 25.0, "dmg": 1.0, "dmg_step": 0.4, "color": "dfe7f5"},
			{"id": "kn_step", "name": "Guardian's Step", "mech": "blink", "icon": "shield flash", "max_rank": 5, "flavor": "Flash aside, shielded", "cd": 3.5, "cd_step": 0.3, "dist": 140.0, "dist_step": 18.0, "color": "dfe7f5"},
		],
		"archer": [
			{"id": "ar_multi", "name": "Multishot", "mech": "volley", "icon": "arrow fan", "max_rank": 6, "flavor": "Fan of arrows", "cd": 1.3, "cd_step": 0.08, "count": 3, "count_step": 1, "dmg": 0.7, "pierce": 1, "size": 5.0, "color": "cdeccd"},
			{"id": "ar_rain", "name": "Arrow Rain", "mech": "slam", "icon": "falling arrows", "max_rank": 5, "flavor": "Arrows fall from above", "cd": 2.8, "cd_step": 0.2, "rad": 75.0, "rad_step": 14.0, "dmg": 1.2, "dmg_step": 0.4, "color": "bfe0bf"},
			{"id": "ar_ricochet", "name": "Ricochet", "mech": "chain", "icon": "bouncing arrow", "max_rank": 6, "flavor": "Arrow bounces foe to foe", "cd": 1.6, "cd_step": 0.1, "targets": 2, "target_step": 1, "dmg": 0.9, "color": "cdeccd"},
			{"id": "ar_scatter", "name": "Scattershot", "mech": "radial", "icon": "arrow burst", "max_rank": 5, "flavor": "Arrows burst outward", "cd": 2.4, "cd_step": 0.15, "count": 6, "count_step": 2, "dmg": 0.6, "pierce": 1, "size": 5.0, "color": "cdeccd"},
			{"id": "ar_point", "name": "Point-Blank Volley", "mech": "nova", "icon": "bow blast", "max_rank": 5, "flavor": "Loose a bow-blast around you", "cd": 2.6, "cd_step": 0.18, "rad": 75.0, "rad_step": 12.0, "dmg": 1.3, "dmg_step": 0.4, "color": "a9e6b4"},
			{"id": "ar_quiver", "name": "Orbiting Quiver", "mech": "orbit", "icon": "orbiting arrows", "max_rank": 5, "flavor": "Arrows circle, ready to loose", "count": 2, "count_step": 1, "dmg": 0.45, "dmg_step": 0.1, "dist": 72.0, "speed": 3.2, "size": 10.0, "color": "cdeccd"},
			{"id": "ar_roll", "name": "Dodge Roll", "mech": "dash", "icon": "evasive roll", "max_rank": 5, "flavor": "Nimble evasive roll", "cd": 2.5, "cd_step": 0.25, "dist": 130.0, "dist_step": 18.0, "color": "cdeccd"},
			{"id": "ar_evade", "name": "Evasive Step", "mech": "blink", "icon": "quickstep", "max_rank": 5, "flavor": "Slip out of danger", "cd": 3.2, "cd_step": 0.3, "dist": 140.0, "dist_step": 18.0, "color": "cdeccd"},
		],
		"mage": [
			{"id": "mg_firenova", "name": "Fire Nova", "mech": "nova", "icon": "fire burst", "max_rank": 6, "flavor": "Erupt in flame", "cd": 2.0, "cd_step": 0.12, "rad": 90.0, "rad_step": 14.0, "dmg": 1.0, "dmg_step": 0.35, "color": "ff7a2a"},
			{"id": "mg_meteor", "name": "Meteor", "mech": "slam", "icon": "falling meteor", "max_rank": 5, "flavor": "Call down a meteor", "cd": 3.0, "cd_step": 0.2, "rad": 95.0, "rad_step": 16.0, "dmg": 2.0, "dmg_step": 0.6, "color": "ff9a4a"},
			{"id": "mg_bolt", "name": "Arcane Bolt", "mech": "volley", "icon": "arcane bolt", "max_rank": 5, "flavor": "A piercing bolt of raw force", "cd": 1.4, "cd_step": 0.09, "count": 1, "count_step": 1, "dmg": 1.3, "pierce": 4, "size": 7.0, "speed": 520.0, "color": "6aa9ff"},
			{"id": "mg_frostring", "name": "Frost Ring", "mech": "radial", "icon": "frost shards", "max_rank": 5, "flavor": "Chilling bolts outward", "cd": 2.4, "cd_step": 0.15, "count": 8, "count_step": 2, "dmg": 0.6, "size": 6.0, "color": "7fd0ff"},
			{"id": "mg_chain", "name": "Chain Lightning", "mech": "chain", "icon": "lightning arc", "max_rank": 6, "flavor": "Lightning arcs between foes", "cd": 1.8, "cd_step": 0.12, "targets": 3, "target_step": 1, "dmg": 1.1, "color": "bfe6ff"},
			{"id": "mg_orbs", "name": "Arcane Orbs", "mech": "orbit", "icon": "orbiting orb", "max_rank": 5, "flavor": "Orbs circle you", "count": 2, "count_step": 1, "dmg": 0.5, "dmg_step": 0.12, "dist": 76.0, "speed": 2.6, "size": 12.0, "color": "6aa9ff"},
			{"id": "mg_surge", "name": "Arcane Surge", "mech": "dash", "icon": "force surge", "max_rank": 5, "flavor": "Surge forward in a burst of force", "cd": 3.2, "cd_step": 0.25, "dist": 150.0, "dist_step": 20.0, "dmg": 0.6, "dmg_step": 0.2, "color": "6aa9ff"},
			{"id": "mg_blink", "name": "Blink", "mech": "blink", "icon": "teleport flash", "max_rank": 5, "flavor": "Teleport from danger", "cd": 3.5, "cd_step": 0.3, "dist": 150.0, "dist_step": 20.0, "color": "6aa9ff"},
		],
		"rogue": [
			{"id": "rg_fan", "name": "Fan of Knives", "mech": "volley", "icon": "knife fan", "max_rank": 6, "flavor": "Spray of knives", "cd": 1.1, "cd_step": 0.07, "count": 3, "count_step": 1, "dmg": 0.6, "size": 5.0, "spread": 0.9, "color": "f4dd8a"},
			{"id": "rg_poison", "name": "Poison Cloud", "mech": "slam", "icon": "poison cloud", "max_rank": 5, "flavor": "Choking venom", "cd": 2.6, "cd_step": 0.18, "rad": 80.0, "rad_step": 14.0, "dmg": 1.0, "dmg_step": 0.35, "slow": 1.0, "color": "9bd34a"},
			{"id": "rg_flurry", "name": "Blade Flurry", "mech": "nova", "icon": "spin slash", "max_rank": 5, "flavor": "Spin, cutting all nearby", "cd": 1.9, "cd_step": 0.13, "rad": 65.0, "rad_step": 10.0, "dmg": 1.1, "dmg_step": 0.35, "color": "f4dd8a"},
			{"id": "rg_burst", "name": "Knife Storm", "mech": "radial", "icon": "knife burst", "max_rank": 5, "flavor": "Knives in all directions", "cd": 2.2, "cd_step": 0.14, "count": 7, "count_step": 2, "dmg": 0.55, "size": 5.0, "color": "f4dd8a"},
			{"id": "rg_backstab", "name": "Backstab Chain", "mech": "chain", "icon": "dagger leap", "max_rank": 5, "flavor": "Dagger leaps foe to foe", "cd": 1.7, "cd_step": 0.11, "targets": 3, "target_step": 1, "dmg": 1.0, "color": "f4dd8a"},
			{"id": "rg_knives", "name": "Whirling Knives", "mech": "orbit", "icon": "orbiting knife", "max_rank": 5, "flavor": "Knives orbit you", "count": 3, "count_step": 1, "dmg": 0.45, "dmg_step": 0.1, "dist": 60.0, "speed": 4.0, "size": 10.0, "color": "f4dd8a"},
			{"id": "rg_shadow", "name": "Shadow Dash", "mech": "dash", "icon": "shadow slash", "max_rank": 6, "flavor": "Slip through foes, cutting them", "cd": 2.0, "cd_step": 0.2, "dist": 150.0, "dist_step": 16.0, "dmg": 1.2, "dmg_step": 0.35, "color": "cdb0ff"},
			{"id": "rg_smoke", "name": "Smoke Step", "mech": "blink", "icon": "smoke puff", "max_rank": 5, "flavor": "Vanish in smoke", "cd": 3.0, "cd_step": 0.3, "dist": 140.0, "dist_step": 18.0, "color": "b0b0c0"},
		],
		"cleric": [
			{"id": "cl_holynova", "name": "Holy Nova", "mech": "nova", "icon": "holy burst", "max_rank": 6, "flavor": "Burst of light, heals you", "cd": 2.2, "cd_step": 0.13, "rad": 90.0, "rad_step": 12.0, "dmg": 1.0, "dmg_step": 0.3, "heal": 10.0, "color": "fff3c4"},
			{"id": "cl_smite", "name": "Smite", "mech": "slam", "icon": "holy pillar", "max_rank": 5, "flavor": "Pillar of holy fire", "cd": 2.6, "cd_step": 0.18, "rad": 80.0, "rad_step": 14.0, "dmg": 1.8, "dmg_step": 0.5, "color": "fff3c4"},
			{"id": "cl_bolts", "name": "Holy Bolts", "mech": "volley", "icon": "light bolt", "max_rank": 5, "flavor": "Bolts of light", "cd": 1.5, "cd_step": 0.1, "count": 2, "count_step": 1, "dmg": 0.9, "pierce": 1, "size": 6.0, "color": "fff3c4"},
			{"id": "cl_radiance", "name": "Radiant Burst", "mech": "radial", "icon": "radiant motes", "max_rank": 5, "flavor": "Holy motes fly outward", "cd": 2.6, "cd_step": 0.16, "count": 6, "count_step": 2, "dmg": 0.6, "size": 6.0, "color": "fff3c4"},
			{"id": "cl_judgment", "name": "Judgment", "mech": "chain", "icon": "light arc", "max_rank": 5, "flavor": "Light leaps between foes", "cd": 2.0, "cd_step": 0.13, "targets": 3, "target_step": 1, "dmg": 1.0, "color": "fff3c4"},
			{"id": "cl_censers", "name": "Censers", "mech": "orbit", "icon": "orbiting censer", "max_rank": 5, "flavor": "Holy flames orbit you", "count": 2, "count_step": 1, "dmg": 0.5, "dmg_step": 0.12, "dist": 74.0, "speed": 2.6, "size": 13.0, "color": "fff3c4"},
			{"id": "cl_sancdash", "name": "Sanctified Dash", "mech": "dash", "icon": "wings of light", "max_rank": 5, "flavor": "Dash on wings of light", "cd": 3.0, "cd_step": 0.3, "dist": 140.0, "dist_step": 18.0, "color": "fff3c4"},
			{"id": "cl_step", "name": "Divine Step", "mech": "blink", "icon": "divine flash", "max_rank": 5, "flavor": "Teleport in a flash of light", "cd": 3.4, "cd_step": 0.3, "dist": 140.0, "dist_step": 18.0, "color": "fff3c4"},
		],
		"barbarian": [
			{"id": "bb_cleave", "name": "Cleave", "mech": "nova", "icon": "sweeping axe", "max_rank": 5, "flavor": "Brutal sweeping cleave", "cd": 1.8, "cd_step": 0.12, "rad": 80.0, "rad_step": 12.0, "dmg": 1.3, "dmg_step": 0.4, "knock": 120.0, "color": "e89a8a"},
			{"id": "bb_quake", "name": "Earthquake", "mech": "slam", "icon": "ground crack", "max_rank": 5, "flavor": "The ground erupts", "cd": 3.0, "cd_step": 0.2, "rad": 100.0, "rad_step": 16.0, "dmg": 1.7, "dmg_step": 0.5, "knock": 160.0, "color": "c08050"},
			{"id": "bb_axes", "name": "Axe Throw", "mech": "volley", "icon": "thrown axe", "max_rank": 5, "flavor": "Hurl heavy axes", "cd": 1.6, "cd_step": 0.1, "count": 1, "count_step": 1, "dmg": 1.6, "pierce": 3, "size": 9.0, "speed": 380.0, "color": "d98c5a"},
			{"id": "bb_storm", "name": "Axe Storm", "mech": "radial", "icon": "axe burst", "max_rank": 5, "flavor": "Axes fly in all directions", "cd": 2.8, "cd_step": 0.18, "count": 7, "count_step": 2, "dmg": 0.6, "pierce": 1, "size": 8.0, "speed": 360.0, "color": "d98c5a"},
			{"id": "bb_frenzy", "name": "Frenzied Swings", "mech": "chain", "icon": "axe frenzy", "max_rank": 5, "flavor": "Axe blows leap foe to foe", "cd": 1.9, "cd_step": 0.12, "targets": 3, "target_step": 1, "dmg": 1.1, "color": "e89a8a"},
			{"id": "bb_whirlwind", "name": "Whirlwind", "mech": "orbit", "icon": "orbiting axe", "max_rank": 6, "flavor": "Axes whirl about you", "count": 2, "count_step": 1, "dmg": 0.55, "dmg_step": 0.12, "dist": 66.0, "speed": 3.4, "size": 16.0, "color": "e2655a"},
			{"id": "bb_rush", "name": "Battle Rush", "mech": "dash", "icon": "charging rush", "max_rank": 6, "flavor": "Charge, smashing through ranks", "cd": 2.5, "cd_step": 0.2, "dist": 160.0, "dist_step": 20.0, "dmg": 1.4, "dmg_step": 0.4, "color": "e2655a"},
			{"id": "bb_leap", "name": "Berserker's Leap", "mech": "blink", "icon": "leaping roar", "max_rank": 5, "flavor": "Leap clear of the fray, roaring", "cd": 3.6, "cd_step": 0.3, "dist": 150.0, "dist_step": 20.0, "color": "e2655a"},
		],
	}

static func by_id(id: String) -> Dictionary:
	for cls in by_class():
		for a in by_class()[cls]:
			if a["id"] == id:
				return a
	return {}

static func kind_of(def: Dictionary) -> String:
	return KIND[def["mech"]]

static func cooldown(def: Dictionary, rank: int) -> float:
	var cd_min := 1.0
	match def["mech"]:
		"volley": cd_min = 0.6
		"radial", "chain": cd_min = 1.2
		"dash": cd_min = 1.5
		"blink": cd_min = 2.0
	return maxf(cd_min, def["cd"] - def.get("cd_step", 0.0) * (rank - 1))

static func describe(def: Dictionary, rank: int) -> String:
	var f: String = def["flavor"]
	match def["mech"]:
		"nova", "slam":
			return "%s — %d%% dmg, %d radius" % [f, roundi((def["dmg"] + def.get("dmg_step", 0.0) * (rank - 1)) * 100), roundi(def["rad"] + def.get("rad_step", 0.0) * (rank - 1))]
		"volley":
			return "%s — %d projectiles" % [f, def["count"] + def.get("count_step", 1) * (rank - 1)]
		"radial":
			return "%s — %d bolts outward" % [f, def["count"] + def.get("count_step", 2) * (rank - 1)]
		"chain":
			return "%s — leaps to %d foes" % [f, def["targets"] + def.get("target_step", 1) * (rank - 1)]
		"orbit":
			return "%s — %d orbiting, %d%% dmg" % [f, def["count"] + def.get("count_step", 1) * (rank - 1), roundi((def["dmg"] + def.get("dmg_step", 0.0) * (rank - 1)) * 100)]
		"dash", "blink":
			return "%s — %d dist" % [f, roundi(def["dist"] + def.get("dist_step", 0.0) * (rank - 1))]
	return f

static func sync_orbit(def: Dictionary, player: Player, rank: int) -> void:
	var count: int = def["count"] + def.get("count_step", 1) * (rank - 1)
	var mult: float = def["dmg"] + def.get("dmg_step", 0.0) * (rank - 1)
	player.sync_orbit_group(def["id"], count, mult, def.get("dist", 70.0), def.get("speed", 2.8), def.get("size", 14.0), Color(def["color"]))

static func activate(def: Dictionary, player: Player, main: Node, rank: int) -> void:
	var col := Color(def["color"])
	match def["mech"]:
		"nova":
			var rad: float = def["rad"] + def.get("rad_step", 0.0) * (rank - 1)
			var mult: float = def["dmg"] + def.get("dmg_step", 0.0) * (rank - 1)
			var opts := {"color": col}
			if def.has("slow"): opts["slow"] = def["slow"]
			if def.has("knock"): opts["knockback"] = def["knock"]
			main.area_damage(player.global_position, rad, mult, opts)
			var world := main.get_node("World")
			Vfx.ring(world, player.global_position, col, rad, 0.35)
			Vfx.burst(world, player.global_position, col, 10, 140.0, 0.3, 3.0)
			if def.has("heal"): player.hp = min(player.max_hp, player.hp + def["heal"])
		"slam":
			var t: Node2D = main.nearest_enemy_to(player.global_position)
			if t == null: return
			var rad: float = def["rad"] + def.get("rad_step", 0.0) * (rank - 1)
			var mult: float = def["dmg"] + def.get("dmg_step", 0.0) * (rank - 1)
			var opts := {"color": col}
			if def.has("slow"): opts["slow"] = def["slow"]
			if def.has("knock"): opts["knockback"] = def["knock"]
			main.area_damage(t.global_position, rad, mult, opts)
			var world := main.get_node("World")
			Vfx.ring(world, t.global_position, col, rad, 0.35)
			Vfx.burst(world, t.global_position, col, 12, 160.0, 0.3, 3.0)
		"volley":
			var base: float = main.dir_to_nearest(player.global_position)
			var n: int = def["count"] + def.get("count_step", 1) * (rank - 1)
			var spread: float = def.get("spread", 0.6)
			for i in n:
				var a: float = base if n == 1 else base + (i - (n - 1) / 2.0) * (spread / n)
				main.spawn_player_projectile(player.global_position, Vector2(cos(a), sin(a)) * def.get("speed", 460.0), player.damage * def.get("dmg", 0.8), false, def.get("pierce", 0), def.get("size", 6.0), col)
		"radial":
			var n: int = def["count"] + def.get("count_step", 2) * (rank - 1)
			for i in n:
				var a := (float(i) / n) * TAU
				main.spawn_player_projectile(player.global_position, Vector2(cos(a), sin(a)) * def.get("speed", 380.0), player.damage * def.get("dmg", 0.7), false, def.get("pierce", 0), def.get("size", 6.0), col)
		"chain":
			var hops: int = def["targets"] + def.get("target_step", 1) * (rank - 1)
			var seen := {}
			var from := player.global_position
			for i in hops:
				var best: Node2D = null
				var bd := INF
				for e in main.get_tree().get_nodes_in_group("enemies"):
					if seen.has(e.get_instance_id()): continue
					var d: float = from.distance_squared_to(e.global_position)
					if d < bd: bd = d; best = e
				if best == null: break
				seen[best.get_instance_id()] = true
				Vfx.chain_link(main.get_node("World"), from, best.global_position, col, 2.5, 0.25)
				best.take_damage(player.damage * def.get("dmg", 1.1), false)
				Vfx.burst(main.get_node("World"), best.global_position, col, 5, 90.0, 0.2, 2.0)
				from = best.global_position
		"dash":
			var dist: float = def["dist"] + def.get("dist_step", 0.0) * (rank - 1)
			var d := player.move_dir
			if d.length() < 0.01:
				var a: float = main.dir_to_nearest(player.global_position)
				d = Vector2(cos(a), sin(a))
			var hit_mult: float = def.get("dmg", 0.0)
			if def.has("dmg"): hit_mult = def["dmg"] + def.get("dmg_step", 0.0) * (rank - 1)
			Vfx.burst(main.get_node("World"), player.global_position, col, 8, 60.0, 0.25, 2.5)
			player.start_dash(d.normalized(), dist, hit_mult)
		"blink":
			var dist: float = def["dist"] + def.get("dist_step", 0.0) * (rank - 1)
			var t: Node2D = main.nearest_enemy_to(player.global_position)
			var a: float
			if t != null: a = (player.global_position - t.global_position).angle()
			elif player.move_dir.length() > 0.01: a = player.move_dir.angle()
			else: a = randf() * TAU
			var world := main.get_node("World")
			Vfx.ring(world, player.global_position, col, 40.0, 0.3)
			player.global_position += Vector2(cos(a), sin(a)) * dist
			Vfx.ring(world, player.global_position, col, 40.0, 0.3)
			player.invuln = maxf(player.invuln, 0.4)

# Roll n level-up options: each is NEW (rank 1) or a RANK-UP of an owned ability.
static func roll(class_id: String, owned: Dictionary, n: int) -> Array:
	var pool := []
	for ab in by_class().get(class_id, []):
		var cur: int = owned.get(ab["id"], 0)
		if cur < ab["max_rank"]:
			pool.append({"ability": ab, "is_new": cur == 0, "next_rank": cur + 1})
	pool.shuffle()
	return pool.slice(0, n)
