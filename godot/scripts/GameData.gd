extends Node
## Static game data ported from the JS build (js/classes.js +
## assets/anim/manifest.json). Autoloaded as `GameData`.

# The six playable classes (base stat tilt + starter weapon).
const CLASSES := {
	"knight":    {"name": "Knight",    "color": "c9d1e0", "max_hp": 140.0, "speed": 175.0, "damage": 12.0, "crit": 0.03, "regen": 0.2, "weapon": "arming_sword"},
	"archer":    {"name": "Archer",    "color": "7bdc8a", "max_hp": 90.0,  "speed": 195.0, "damage": 11.0, "crit": 0.08, "regen": 0.0, "weapon": "shortbow"},
	"mage":      {"name": "Mage",      "color": "6aa9ff", "max_hp": 70.0,  "speed": 180.0, "damage": 16.0, "crit": 0.05, "regen": 0.0, "weapon": "fireball"},
	"rogue":     {"name": "Rogue",     "color": "e8c14a", "max_hp": 80.0,  "speed": 215.0, "damage": 8.0,  "crit": 0.18, "regen": 0.0, "weapon": "daggers"},
	"cleric":    {"name": "Cleric",    "color": "f0e6b0", "max_hp": 100.0, "speed": 180.0, "damage": 10.0, "crit": 0.04, "regen": 1.0, "weapon": "holy_bolt"},
	"barbarian": {"name": "Barbarian", "color": "e2655a", "max_hp": 130.0, "speed": 185.0, "damage": 14.0, "crit": 0.06, "regen": 0.0, "weapon": "whirlwind_axe"},
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
	"arming_sword":  {"name": "Arming Sword",     "type": "melee",      "cooldown": 0.7},
	"warhammer":     {"name": "Warhammer",        "type": "melee",      "cooldown": 1.3},
	"shortbow":      {"name": "Shortbow",         "type": "projectile", "cooldown": 0.6},
	"crossbow":      {"name": "Crossbow",         "type": "projectile", "cooldown": 0.35},
	"fireball":      {"name": "Fireball",         "type": "projectile", "cooldown": 0.85},
	"frost_nova":    {"name": "Frost Nova",       "type": "nova",       "cooldown": 1.5},
	"daggers":       {"name": "Throwing Daggers", "type": "projectile", "cooldown": 0.28},
	"fan_of_knives": {"name": "Fan of Knives",    "type": "projectile", "cooldown": 0.7},
	"holy_bolt":     {"name": "Holy Bolt",        "type": "projectile", "cooldown": 0.7},
	"censer":        {"name": "Holy Censer",      "type": "orbital",    "cooldown": 0.7},
	"whirlwind_axe": {"name": "Whirlwind Axe",    "type": "orbital",    "cooldown": 0.7},
	"throwing_axe":  {"name": "Throwing Axe",     "type": "projectile", "cooldown": 0.9},
}

# Enemy archetypes, ported from js/enemies.js (ENEMY_BASE). `kind` selects the AI.
const ENEMY_BASE := {
	"skeleton":  {"kind": "chaser",    "r": 12.0, "hp": 18.0,   "speed": 70.0,  "dmg": 8.0,  "color": "d6d3c4", "gold": 1.0,   "xp": 1.0},
	"goblin":    {"kind": "chaser",    "r": 10.0, "hp": 12.0,   "speed": 132.0, "dmg": 6.0,  "color": "7bbf63", "gold": 1.0,   "xp": 1.0},
	"ogre":      {"kind": "chaser",    "r": 20.0, "hp": 70.0,   "speed": 48.0,  "dmg": 16.0, "color": "9b59b6", "gold": 3.0,   "xp": 3.0},
	"shooter":   {"kind": "shooter",   "r": 12.0, "hp": 24.0,   "speed": 64.0,  "dmg": 7.0,  "color": "6aa9ff", "gold": 2.0,   "xp": 2.0},
	"exploder":  {"kind": "exploder",  "r": 13.0, "hp": 20.0,   "speed": 118.0, "dmg": 20.0, "color": "e8893a", "gold": 2.0,   "xp": 2.0},
	"splitter":  {"kind": "splitter",  "r": 16.0, "hp": 42.0,   "speed": 66.0,  "dmg": 9.0,  "color": "caa24a", "gold": 2.0,   "xp": 2.0},
	"charger":   {"kind": "charger",   "r": 15.0, "hp": 46.0,   "speed": 60.0,  "dmg": 20.0, "color": "d05a7a", "gold": 3.0,   "xp": 3.0},
	"spawnling": {"kind": "chaser",    "r": 7.0,  "hp": 7.0,    "speed": 150.0, "dmg": 5.0,  "color": "caa24a", "gold": 0.0,   "xp": 1.0},
	"miniboss":  {"kind": "miniboss",  "r": 34.0, "hp": 700.0,  "speed": 44.0,  "dmg": 18.0, "color": "b14a8a", "gold": 25.0,  "xp": 8.0,  "boss": true},
	"finalboss": {"kind": "finalboss", "r": 48.0, "hp": 2600.0, "speed": 40.0,  "dmg": 24.0, "color": "c0341f", "gold": 120.0, "xp": 10.0, "boss": true, "final": true},
}

const DIR8 := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]

static func dir_of(angle: float) -> String:
	var i := int(round(angle / (PI / 4.0)))
	i = ((i % 8) + 8) % 8
	return DIR8[i]
