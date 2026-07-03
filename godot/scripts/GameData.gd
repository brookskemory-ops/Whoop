extends Node
## Static game data ported from the JS build (js/classes.js +
## assets/anim/manifest.json). Autoloaded as `GameData`.

# Temporarily vaulted: only these are offered in Class Select while
# Cleric/Barbarian still use the old shared ability mechanics (pending their
# own bespoke-kit pass, same as Knight/Archer/Mage already got).
const AVAILABLE_CLASSES := ["knight", "archer", "mage", "rogue"]

# The six playable classes (base stat tilt + weapon pool), ported from
# js/classes.js. `unlock.type` is "default" | "gold" | "achievement".
const CLASSES := {
	"knight":    {"name": "Knight",    "color": "c9d1e0", "blurb": "Stalwart defender. High HP, sweeping melee arcs.",
		"max_hp": 140.0, "speed": 175.0, "damage": 12.0, "crit": 0.03, "regen": 0.2,
		"weapon": "arming_sword", "weapons": ["arming_sword", "warhammer"], "unlock": {"type": "default"}},
	"archer":    {"name": "Archer",    "color": "7bdc8a", "blurb": "Ranged marksman. Piercing arrows from afar.",
		"max_hp": 90.0,  "speed": 195.0, "damage": 11.0, "crit": 0.08, "regen": 0.0,
		"weapon": "shortbow", "weapons": ["shortbow", "crossbow"], "unlock": {"type": "gold", "cost": 150}},
	"mage":      {"name": "Mage",      "color": "6aa9ff", "blurb": "Glass cannon. Explosive area damage, frail.",
		"max_hp": 70.0,  "speed": 180.0, "damage": 16.0, "crit": 0.05, "regen": 0.0,
		"weapon": "fireball", "weapons": ["fireball", "frost_nova"], "unlock": {"type": "gold", "cost": 250}},
	"rogue":     {"name": "Rogue",     "color": "e8c14a", "blurb": "Swift assassin. Fast, crit-heavy daggers.",
		"max_hp": 80.0,  "speed": 215.0, "damage": 8.0,  "crit": 0.18, "regen": 0.0,
		"weapon": "daggers", "weapons": ["daggers", "fan_of_knives"], "unlock": {"type": "gold", "cost": 200}},
	"cleric":    {"name": "Cleric",    "color": "f0e6b0", "blurb": "Holy support. Sustains through constant regen.",
		"max_hp": 100.0, "speed": 180.0, "damage": 10.0, "crit": 0.04, "regen": 1.0,
		"weapon": "holy_bolt", "weapons": ["holy_bolt", "censer"], "unlock": {"type": "achievement", "achievement": "survive_8"}},
	"barbarian": {"name": "Barbarian", "color": "e2655a", "blurb": "Raging bruiser. Whirling orbital axes.",
		"max_hp": 130.0, "speed": 185.0, "damage": 14.0, "crit": 0.06, "regen": 0.0,
		"weapon": "whirlwind_axe", "weapons": ["whirlwind_axe", "throwing_axe"], "unlock": {"type": "achievement", "achievement": "level_15"}},
}

# Animation layout (mirrors assets/anim/manifest.json). The five base
# directions are baked; the other three mirror them horizontally at runtime.
const ANIM_BASE_DIRS := ["south", "north", "east", "north-east", "south-east"]
const ANIM_FRAMES := {"idle": 5, "walk": 9, "attack": 7, "special": 7, "dash": 5, "hurt": 5, "death": 7}
const ANIM_FPS := {"idle": 6.0, "walk": 10.0, "attack": 16.0, "special": 13.0, "dash": 18.0, "hurt": 16.0, "death": 10.0}
const ANIM_LOOP := {"idle": true, "walk": true, "attack": false, "special": false, "dash": false, "hurt": false, "death": false}
const ANIM_MIRROR := {"west": "east", "north-west": "north-east", "south-west": "south-east"}

# Classes that currently have external 8-dir animation art on disk.
const ANIMATED_CLASSES := ["knight", "archer", "mage", "rogue", "cleric"]

# Weapon metadata, ported from js/weapons.js. Fire logic lives in Weapons.gd.
const WEAPON_META := {
	"arming_sword":  {"name": "Arming Sword",     "type": "melee",      "cooldown": 0.7,
		"desc": "Sweeping arc that strikes all foes in front.", "unlock": {"type": "default"}},
	"warhammer":     {"name": "Warhammer",        "type": "melee",      "cooldown": 1.3,
		"desc": "Slow, devastating slam with heavy knockback.", "unlock": {"type": "gold", "cost": 120}},
	"shortbow":      {"name": "Shortbow",         "type": "projectile", "cooldown": 0.6,
		"desc": "Fires an arrow that pierces one enemy.", "unlock": {"type": "default"}},
	"crossbow":      {"name": "Crossbow",         "type": "projectile", "cooldown": 0.35,
		"desc": "Rapid bolts that punch through three foes.", "unlock": {"type": "achievement", "achievement": "archer_kills_500"}},
	"fireball":      {"name": "Fireball",         "type": "projectile", "cooldown": 0.85,
		"desc": "Hurls a fireball that bursts on impact.", "unlock": {"type": "default"}},
	"frost_nova":    {"name": "Frost Nova",       "type": "nova",       "cooldown": 1.5,
		"desc": "Erupts frost around you, chilling all nearby.", "unlock": {"type": "achievement", "achievement": "survive_12"}},
	"daggers":       {"name": "Throwing Daggers", "type": "projectile", "cooldown": 0.28,
		"desc": "Flings rapid daggers with a high crit rate.", "unlock": {"type": "default"}},
	"fan_of_knives": {"name": "Fan of Knives",    "type": "projectile", "cooldown": 0.7,
		"desc": "Throws a spread volley of knives at once.", "unlock": {"type": "gold", "cost": 140}},
	"holy_bolt":     {"name": "Holy Bolt",        "type": "projectile", "cooldown": 0.7,
		"desc": "Looses a bolt of light; a healing aura sustains you.", "unlock": {"type": "default"}},
	"censer":        {"name": "Holy Censer",      "type": "orbital",    "cooldown": 0.7,
		"desc": "Censers of holy flame orbit and scorch the unworthy.", "unlock": {"type": "gold", "cost": 160}},
	"whirlwind_axe": {"name": "Whirlwind Axe",    "type": "orbital",    "cooldown": 0.7,
		"desc": "Axes whirl around you, cleaving anything close.", "unlock": {"type": "default"}},
	"throwing_axe":  {"name": "Throwing Axe",     "type": "projectile", "cooldown": 0.9,
		"desc": "Lobs a heavy axe that tears through ranks.", "unlock": {"type": "gold", "cost": 150}},
}

# Achievements, ported from js/achievements.js. `metric` selects which run-stat
# field check_achievements() compares against `value`.
const ACHIEVEMENTS := [
	{"id": "survive_8", "name": "Hold the Line", "desc": "Survive 8:00 in a single run.", "unlocks": "Cleric (class)", "metric": "time", "value": 480.0},
	{"id": "level_15", "name": "Seasoned", "desc": "Reach level 15 in a single run.", "unlocks": "Barbarian (class)", "metric": "level", "value": 15.0},
	{"id": "survive_12", "name": "Unbroken", "desc": "Survive 12:00 in a single run.", "unlocks": "Frost Nova (Mage weapon)", "metric": "time", "value": 720.0},
	{"id": "archer_kills_500", "name": "Fletcher", "desc": "Slay 500 foes as the Archer (lifetime).", "unlocks": "Crossbow (Archer weapon)", "metric": "archer_kills", "value": 500.0},
	{"id": "kills_1000", "name": "Reaper", "desc": "Slay 1000 foes (lifetime).", "unlocks": "500 bonus gold", "metric": "total_kills", "value": 1000.0},
]

func check_achievements(stats: Dictionary, earned: Dictionary) -> Array:
	var fresh := []
	for a in ACHIEVEMENTS:
		if earned.get(a["id"], false):
			continue
		var ok := false
		match a["metric"]:
			"time": ok = stats["time"] >= a["value"]
			"level": ok = stats["level"] >= a["value"]
			"total_kills": ok = stats["total_kills"] >= a["value"]
			"archer_kills": ok = float(stats["class_kills"].get("archer", 0)) >= a["value"]
		if ok:
			fresh.append(a["id"])
	return fresh

func achievement_by_id(id: String) -> Dictionary:
	for a in ACHIEVEMENTS:
		if a["id"] == id:
			return a
	return {}

# Stages: distinct themed maps, each with its own bounds/obstacle density and
# enemy-pool identity. "Stage" here means map/theme — NOT the same concept as
# player.level (character XP progression), which is unrelated.
const STAGES := [
	{"id": "forest", "name": "Ashwood Vale", "tileset": "forest", "lighting": "bright",
		"blurb": "Sunlit woods, open ground and light cover.",
		"intro": "The vale remembers older wars. Mind the brambles — they drink deep.",
		"hazard": {"type": "field", "count": 7, "radius": 74.0, "dps": 7.0, "slow_mult": 0.55, "color": "5f8a3e"},
		"unlock": {"type": "default"}, "bounds": Vector2(4000.0, 4000.0), "obstacle_density": 0.12,
		"obstacle_textures": ["res://assets/map/obstacles/forest_tree.png", "res://assets/map/obstacles/forest_tree.png",
			"res://assets/map/obstacles/forest_rock.png", "res://assets/map/obstacles/forest_bush.png"]},
	{"id": "dungeon", "name": "The Sunken Vault", "tileset": "dungeon", "lighting": "torch",
		"blurb": "Torch-lit ruin, tight quarters and dense cover.",
		"intro": "Something below still guards the dark. Watch the stones underfoot.",
		"hazard": {"type": "periodic", "count": 8, "radius": 60.0, "dmg": 24.0, "period": 2.8, "telegraph": 0.7, "color": "c8b48a"},
		"unlock": {"type": "stage_clear", "stage": "forest"}, "bounds": Vector2(3600.0, 3600.0), "obstacle_density": 0.15,
		"obstacle_textures": ["res://assets/map/obstacles/dungeon_pillar.png", "res://assets/map/obstacles/dungeon_rubble.png",
			"res://assets/map/obstacles/forest_rock.png"]},
]

# Difficulty tiers apply across all stages. A tier unlocks globally once every
# stage in STAGES has been cleared at the previous tier (see
# GameSave.stage_clears / GameSave.unlocked_tier).
const DIFFICULTIES := [
	{"id": "tier1", "name": "Novice Oath", "hp_mult": 1.0, "dmg_mult": 1.0, "spawn_mult": 1.0},
	{"id": "tier2", "name": "Sworn Oath", "hp_mult": 1.35, "dmg_mult": 1.2, "spawn_mult": 1.15,
		"unlocks_enemy": ["charger"]},
	{"id": "tier3", "name": "Broken Oath", "hp_mult": 1.8, "dmg_mult": 1.45, "spawn_mult": 1.3,
		"unlocks_enemy": ["charger", "splitter"], "hazard_intensity": 1.5},
]

func stage_by_id(id: String) -> Dictionary:
	for s in STAGES:
		if s["id"] == id:
			return s
	return {}

func stage_index(id: String) -> int:
	for i in STAGES.size():
		if STAGES[i]["id"] == id:
			return i
	return -1

func difficulty_by_id(id: String) -> Dictionary:
	for d in DIFFICULTIES:
		if d["id"] == id:
			return d
	return {}

func difficulty_index(id: String) -> int:
	for i in DIFFICULTIES.size():
		if DIFFICULTIES[i]["id"] == id:
			return i
	return -1

# Permanent meta-upgrade tracks (bought with gold in the Armory), ported from
# UPGRADE_TRACKS in js/game.js.
const UPGRADE_TRACKS := [
	{"id": "vigor", "name": "Vigor", "max": 8},
	{"id": "might", "name": "Might", "max": 8},
	{"id": "haste", "name": "Haste", "max": 6},
	{"id": "fortune", "name": "Fortune", "max": 6},
	{"id": "revive", "name": "Revive", "max": 2},
]

func upgrade_cost(id: String, lvl: int) -> int:
	match id:
		"vigor": return roundi(40.0 * pow(1.6, lvl))
		"might", "haste": return roundi(50.0 * pow(1.6, lvl))
		"fortune": return roundi(60.0 * pow(1.6, lvl))
		"revive":
			var costs := [300, 800]
			return costs[lvl] if lvl < costs.size() else 9999
	return 9999

func upgrade_desc(id: String, lvl: int) -> String:
	match id:
		"vigor": return "+%d max HP" % (lvl * 20)
		"might": return "+%d%% damage" % (lvl * 8)
		"haste": return "+%d%% move speed" % (lvl * 5)
		"fortune": return "+%d%% gold, +%d%% XP" % [lvl * 10, lvl * 8]
		"revive": return "%d second chance%s per run" % [lvl, "" if lvl == 1 else "s"]
	return ""

# Enemy archetypes, ported from js/enemies.js (ENEMY_BASE). `kind` selects the AI.
const ENEMY_BASE := {
	"skeleton":  {"kind": "chaser",    "r": 12.0, "hp": 18.0,   "speed": 70.0,  "dmg": 8.0,  "color": "d6d3c4", "gold": 1.0,   "xp": 1.0},
	"goblin":    {"kind": "chaser",    "r": 10.0, "hp": 12.0,   "speed": 132.0, "dmg": 6.0,  "color": "7bbf63", "gold": 1.0,   "xp": 1.0},
	"ogre":      {"kind": "chaser",    "r": 20.0, "hp": 70.0,   "speed": 48.0,  "dmg": 16.0, "color": "9b59b6", "gold": 3.0,   "xp": 4.0},
	"shooter":   {"kind": "shooter",   "r": 12.0, "hp": 24.0,   "speed": 64.0,  "dmg": 7.0,  "color": "6aa9ff", "gold": 2.0,   "xp": 3.0},
	"exploder":  {"kind": "exploder",  "r": 13.0, "hp": 20.0,   "speed": 118.0, "dmg": 20.0, "color": "e8893a", "gold": 2.0,   "xp": 3.0},
	"splitter":  {"kind": "splitter",  "r": 16.0, "hp": 42.0,   "speed": 66.0,  "dmg": 9.0,  "color": "caa24a", "gold": 2.0,   "xp": 3.0},
	"charger":   {"kind": "charger",   "r": 15.0, "hp": 46.0,   "speed": 60.0,  "dmg": 20.0, "color": "d05a7a", "gold": 3.0,   "xp": 4.0},
	"spawnling": {"kind": "chaser",    "r": 7.0,  "hp": 7.0,    "speed": 150.0, "dmg": 5.0,  "color": "caa24a", "gold": 0.0,   "xp": 1.0},
	"miniboss":  {"kind": "miniboss",  "r": 34.0, "hp": 700.0,  "speed": 44.0,  "dmg": 18.0, "color": "b14a8a", "gold": 25.0,  "xp": 16.0, "boss": true},
	"finalboss": {"kind": "finalboss", "r": 48.0, "hp": 2600.0, "speed": 40.0,  "dmg": 24.0, "color": "c0341f", "gold": 120.0, "xp": 24.0, "boss": true, "final": true},
}

const DIR8 := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]

# Mobs with PixelLab rotation art at assets/mobs/<kind>/<dir>.png (static 8-dir
# poses, no walk cycle). Scale tuned per-mob so the on-screen size tracks each
# archetype's collision radius (see ENEMY_BASE) at roughly the same visual
# weight as the player's SPRITE_SCALE.
const MOB_ART := ["skeleton", "goblin", "ogre", "shooter", "exploder", "splitter", "charger", "spawnling", "miniboss", "finalboss"]
const MOB_SPRITE_SCALE := {
	"skeleton": 1.05, "goblin": 0.95, "ogre": 1.0, "shooter": 1.1, "exploder": 1.05,
	"splitter": 1.0, "charger": 1.05, "spawnling": 1.2, "miniboss": 1.1, "finalboss": 1.35,
}

static func dir_of(angle: float) -> String:
	var i := int(round(angle / (PI / 4.0)))
	i = ((i % 8) + 8) % 8
	return DIR8[i]
