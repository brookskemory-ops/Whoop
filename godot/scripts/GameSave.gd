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
var upgrades := {}          # legacy flat dict — kept only as a migration source, see load_data()
var volume := 0.7
var muted := false

# Stage/difficulty progression. "Stage" = themed map (Forest/Dungeon/...),
# distinct from player.level (character XP). stage_clears is keyed
# stage_id -> tier_id -> true once won at that tier. unlocked_tier is the
# highest tier id playable across ALL stages (see GameData.DIFFICULTIES).
var stage_clears := {}
var unlocked_tier := "tier1"

# Per-class permanent upgrades: {"knight": {"vigor": 0, ...}, "archer": {...}}.
var class_upgrades := {}

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
	stage_clears = {}
	unlocked_tier = "tier1"
	class_upgrades = {}

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
			stage_clears = parsed.get("stage_clears", {})
			unlocked_tier = parsed.get("unlocked_tier", "tier1")
			class_upgrades = parsed.get("class_upgrades", {})

	# One-time migration: older saves only ever had the flat global `upgrades`
	# dict. If this save predates class_upgrades and the player had actually
	# bought anything, seed every class with those same levels once — there's
	# no way to reconstruct a "real" per-class split from flat data, so
	# giving everyone the same starting point is the least-bad option and
	# never wipes existing progress.
	if class_upgrades.is_empty():
		var had_any := false
		for k in upgrades:
			if int(upgrades[k]) > 0:
				had_any = true
				break
		if had_any:
			for cid in GameData.CLASSES:
				class_upgrades[cid] = upgrades.duplicate()

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
		"stage_clears": stage_clears, "unlocked_tier": unlocked_tier,
		"class_upgrades": class_upgrades,
	}))
	f.close()

func get_class_upgrade(cid: String, id: String) -> int:
	return int(class_upgrades.get(cid, {}).get(id, 0))

func set_class_upgrade(cid: String, id: String, lvl: int) -> void:
	if not class_upgrades.has(cid):
		class_upgrades[cid] = {}
	class_upgrades[cid][id] = lvl

func stage_unlocked(id: String) -> bool:
	var stage: Dictionary = GameData.stage_by_id(id)
	if stage.is_empty():
		return false
	var unlock: Dictionary = stage["unlock"]
	if unlock["type"] == "default":
		return true
	if unlock["type"] == "stage_clear":
		return not stage_clears.get(unlock["stage"], {}).is_empty()
	return false

func tier_unlocked(id: String) -> bool:
	return GameData.difficulty_index(id) <= GameData.difficulty_index(unlocked_tier)

func mark_stage_cleared(stage_id: String, tier_id: String) -> void:
	if not stage_clears.has(stage_id):
		stage_clears[stage_id] = {}
	stage_clears[stage_id][tier_id] = true
	# Advance the globally-unlocked tier once every stage has cleared it.
	var next_i := GameData.difficulty_index(unlocked_tier) + 1
	if next_i < GameData.DIFFICULTIES.size():
		var all_cleared := true
		for s in GameData.STAGES:
			if not stage_clears.get(s["id"], {}).get(unlocked_tier, false):
				all_cleared = false
				break
		if all_cleared:
			unlocked_tier = GameData.DIFFICULTIES[next_i]["id"]

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
