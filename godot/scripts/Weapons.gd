class_name Weapons
extends RefCounted
## Weapon fire logic, ported from js/weapons.js. The four patterns (melee / nova
## use main.area_damage; projectile uses main.spawn_player_projectile; orbital is
## set up in init_weapon). `main` supplies the combat ctx helpers.

static func init_weapon(id: String, player: Player) -> void:
	match id:
		"censer":
			player.add_orbit_group(2, 0.55, 74.0, 2.4, 14.0, Color("fff3c4"))
		"whirlwind_axe":
			player.add_orbit_group(2, 0.6, 64.0, 3.0, 16.0, Color("e2655a"))

static func fire(id: String, player: Player, main: Node) -> void:
	var a: float = main.dir_to_nearest(player.global_position)
	var dirv := Vector2(cos(a), sin(a))
	var crit := randf() < player.crit
	var mult := player.crit_mult if crit else 1.0
	var sp: float = player.proj_speed
	var sz: float = player.proj_size

	match id:
		"arming_sword":
			var rng := 56.0 * sz / 6.0
			main.area_damage(player.global_position + dirv * rng * 0.5, rng, 1.5 * mult, {"crit": crit, "knockback": 90.0})
		"warhammer":
			var rng := 86.0 * sz / 6.0
			main.area_damage(player.global_position + dirv * rng * 0.45, rng, 2.6 * mult, {"crit": crit, "knockback": 260.0})
		"shortbow":
			main.spawn_player_projectile(player.global_position, dirv * sp, player.damage * mult, crit, player.pierce + 1, sz, Color("cdeccd"))
		"crossbow":
			main.spawn_player_projectile(player.global_position, dirv * sp * 1.25, player.damage * mult, crit, player.pierce + 3, sz * 0.9, Color("a9e6b4"))
		"fireball":
			var aoe: float = player.aoe_mult
			var cb := func(pos: Vector2): main.area_damage(pos, 60.0 * aoe, 0.8, {})
			main.spawn_player_projectile(player.global_position, dirv * sp * 0.8, player.damage * mult, crit, 0, sz * 1.3, Color("ff9a4a"), cb)
		"frost_nova":
			main.area_damage(player.global_position, 120.0 * player.aoe_mult, 0.9 * mult, {"slow": 1.5})
		"daggers":
			var a2 := a + randf_range(-0.06, 0.06)
			main.spawn_player_projectile(player.global_position, Vector2(cos(a2), sin(a2)) * sp * 1.1, player.damage * mult, crit, player.pierce, sz * 0.8, Color("f4dd8a"))
		"fan_of_knives":
			var n := 4 + player.proj_count
			var spread := 0.5
			for i in n:
				var ai := a + (i - (n - 1) / 2.0) * (spread / n)
				var cr := randf() < player.crit
				var m2 := player.crit_mult if cr else 1.0
				main.spawn_player_projectile(player.global_position, Vector2(cos(ai), sin(ai)) * sp, player.damage * m2, cr, player.pierce, sz * 0.8, Color("f4dd8a"))
		"holy_bolt":
			main.spawn_player_projectile(player.global_position, dirv * sp, player.damage * 1.1 * mult, crit, player.pierce + 1, sz, Color("fff3c4"))
		"throwing_axe":
			main.spawn_player_projectile(player.global_position, dirv * sp * 0.85, player.damage * 1.8 * mult, crit, player.pierce + 2, sz * 1.4, Color("d98c5a"))
