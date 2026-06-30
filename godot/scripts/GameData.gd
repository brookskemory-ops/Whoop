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

const DIR8 := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]

static func dir_of(angle: float) -> String:
	var i := int(round(angle / (PI / 4.0)))
	i = ((i % 8) + 8) % 8
	return DIR8[i]
