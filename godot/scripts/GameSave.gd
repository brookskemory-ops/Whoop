extends Node
## Persistent meta-progression, ported from the loadMeta/saveMeta localStorage
## logic in js/game.js. Autoloaded as `GameSave`. Uses Godot's user:// directory
## (replaces localStorage; works the same across desktop/mobile exports).

const SAVE_PATH := "user://ironvow_save.json"

var gold := 0
var best_time := 0.0
var unlocked_classes := {}
var unlocked_weapons := {}
var achievements := {}
var total_kills := 0
var class_kills := {}
var upgrades := {}
var volume := 0.7
var muted := false

func _ready() -> void:
	load_data()

func load_data() -> void:
	gold = 0
	best_time = 0.0
	unlocked_classes = {"knight": true}
	unlocked_weapons = {}
	achievements = {}
	total_kills = 0
	class_kills = {}
	upgrades = {"vigor": 0, "might": 0, "haste": 0, "fortune": 0, "revive": 0}
	volume = 0.7
	muted = false

	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed is Dictionary:
			gold = parsed.get("gold", 0)
			best_time = parsed.get("best_time", 0.0)
			unlocked_classes = parsed.get("unlocked_classes", unlocked_classes)
			unlocked_weapons = parsed.get("unlocked_weapons", unlocked_weapons)
			achievements = parsed.get("achievements", achievements)
			total_kills = parsed.get("total_kills", 0)
			class_kills = parsed.get("class_kills", class_kills)
			var u: Dictionary = parsed.get("upgrades", {})
			for k in upgrades:
				if u.has(k):
					upgrades[k] = u[k]
			volume = float(parsed.get("volume", 0.7))
			muted = bool(parsed.get("muted", false))

	for id in GameData.CLASSES:
		if GameData.CLASSES[id]["unlock"]["type"] == "default":
			unlocked_classes[id] = true
	for id in GameData.WEAPON_META:
		if GameData.WEAPON_META[id]["unlock"]["type"] == "default":
			unlocked_weapons[id] = true

func save_data() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"gold": gold, "best_time": best_time,
		"unlocked_classes": unlocked_classes, "unlocked_weapons": unlocked_weapons,
		"achievements": achievements, "total_kills": total_kills,
		"class_kills": class_kills, "upgrades": upgrades,
		"volume": volume, "muted": muted,
	}))
	f.close()

func class_unlocked(id: String) -> bool:
	return bool(unlocked_classes.get(id, false))

func weapon_unlocked(id: String) -> bool:
	return bool(unlocked_weapons.get(id, false))

func apply_unlock(id: String) -> void:
	match id:
		"survive_8": unlocked_classes["cleric"] = true
		"level_15": unlocked_classes["barbarian"] = true
		"survive_12": unlocked_weapons["frost_nova"] = true
		"archer_kills_500": unlocked_weapons["crossbow"] = true
		"kills_1000": gold += 500
