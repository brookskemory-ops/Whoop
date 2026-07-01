class_name MapBuilder
extends RefCounted
## Builds a bounded, stage-themed TileMap + scattered obstacles at run start.
## Ground tilesets come from PixelLab Wang/corner-autotile exports (JSON +
## PNG pair, see assets/map/<name>_tileset.json/.png) — Godot's own
## TileMap.set_cells_terrain_connect() does the corner-matching, we just have
## to describe the 16 tiles' corner patterns once when building the TileSet.

const WORLD_SCALE := 2.0  # matches the old floor Sprite2D's scale(2,2)

static func build_tile_set(json_path: String, png_path: String) -> Dictionary:
	var f := FileAccess.open(json_path, FileAccess.READ)
	var meta = JSON.parse_string(f.get_as_text())
	f.close()
	var tile_size: int = int(meta["tile_size"]["width"])
	var tex: Texture2D = load(png_path)

	var atlas := TileSetAtlasSource.new()
	atlas.texture = tex
	atlas.texture_region_size = Vector2i(tile_size, tile_size)

	var ts := TileSet.new()
	ts.tile_size = Vector2i(tile_size, tile_size)
	ts.add_terrain_set()
	ts.set_terrain_set_mode(0, TileSet.TERRAIN_MODE_MATCH_CORNERS)
	ts.add_terrain(0)  # index 0: lower
	ts.add_terrain(0)  # index 1: upper
	ts.set_terrain_name(0, 0, meta["lower_description"])
	ts.set_terrain_name(0, 1, meta["upper_description"])

	for tile in meta["tileset_data"]["tiles"]:
		var bbox: Dictionary = tile["bounding_box"]
		var coords := Vector2i(int(bbox["x"]) / tile_size, int(bbox["y"]) / tile_size)
		atlas.create_tile(coords)
		var td := atlas.get_tile_data(coords, 0)
		td.terrain_set = 0
		var corners: Dictionary = tile["corners"]
		td.set_terrain_peering_bit(TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER, 1 if corners["NW"] == "upper" else 0)
		td.set_terrain_peering_bit(TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER, 1 if corners["NE"] == "upper" else 0)
		td.set_terrain_peering_bit(TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER, 1 if corners["SW"] == "upper" else 0)
		td.set_terrain_peering_bit(TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER, 1 if corners["SE"] == "upper" else 0)

	ts.add_source(atlas, 0)
	return {"tile_set": ts, "tile_size": tile_size}

## Builds the ground TileMap for a stage: fills the whole bounds with the
## lower terrain, then scatters a handful of upper-terrain patches for
## texture variety. Returns the TileMap node (caller adds it to the tree).
static func build_ground(stage: Dictionary) -> TileMap:
	var built := build_tile_set(
		"res://assets/map/%s_tileset.json" % stage["tileset"],
		"res://assets/map/%s_tileset.png" % stage["tileset"])
	var tile_size: int = built["tile_size"]
	var tile_map := TileMap.new()
	tile_map.name = "Ground"
	tile_map.tile_set = built["tile_set"]
	tile_map.scale = Vector2.ONE * WORLD_SCALE
	tile_map.z_index = -100

	var bounds: Vector2 = stage["bounds"]
	var cols := int(bounds.x / (tile_size * WORLD_SCALE))
	var rows := int(bounds.y / (tile_size * WORLD_SCALE))
	var hc := cols / 2
	var hr := rows / 2

	# Over-fill a few cells past the play bounds so that when the camera sits
	# against its limit there's never a strip of empty background showing
	# beyond the ground (matters most on the bright, torch-less forest).
	var pad := 3
	var all_cells: Array[Vector2i] = []
	for x in range(-hc - pad, hc + pad):
		for y in range(-hr - pad, hr + pad):
			all_cells.append(Vector2i(x, y))
	tile_map.set_cells_terrain_connect(0, all_cells, 0, 0, false)

	var patch_count: int = maxi(3, (cols * rows) / 260)
	for i in patch_count:
		var pw := randi_range(3, 7)
		var ph := randi_range(3, 7)
		var px := randi_range(-hc, hc - pw)
		var py := randi_range(-hr, hr - ph)
		var patch: Array[Vector2i] = []
		for x in range(px, px + pw):
			for y in range(py, py + ph):
				patch.append(Vector2i(x, y))
		tile_map.set_cells_terrain_connect(0, patch, 0, 1, false)

	return tile_map

## Scatters blocking obstacle props across the bounds, avoiding a clear zone
## around the center (run start point) and avoiding overlap with each other.
## Returns an array of {"pos": Vector2, "radius": float} for spawn-clamping.
static func scatter_obstacles(world: Node2D, stage: Dictionary, textures: Array, clear_radius: float = 220.0) -> Array:
	var placed := []
	var bounds: Vector2 = stage["bounds"]
	var half := bounds * 0.5
	var margin := 96.0
	var density: float = stage.get("obstacle_density", 0.06)
	var count := int((bounds.x * bounds.y) / 40000.0 * density)
	var attempts := 0
	while placed.size() < count and attempts < count * 10:
		attempts += 1
		var pos := Vector2(randf_range(-half.x + margin, half.x - margin), randf_range(-half.y + margin, half.y - margin))
		if pos.length() < clear_radius:
			continue
		var tex: Texture2D = textures[randi() % textures.size()]
		var radius: float = maxf(tex.get_width(), tex.get_height()) * 0.32
		var ok := true
		for p in placed:
			if pos.distance_to(p["pos"]) < radius + p["radius"] + 20.0:
				ok = false
				break
		if not ok:
			continue
		var obs := preload("res://scripts/Obstacle.gd").new()
		obs.setup(tex, radius)
		obs.global_position = pos
		obs.z_index = -10
		world.add_child(obs)
		placed.append({"pos": pos, "radius": radius})
	return placed

## Builds an invisible perimeter of four StaticBody2D walls at the play bounds
## so the player (and enemies) are physically contained — the Camera2D limits
## stop the view at the edge, but without these walls the player would keep
## walking off-screen into the void beyond it.
static func build_walls(stage: Dictionary) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = "Walls"
	# Arena perimeter sits on layer 3 (see Player/Enemy collision masks) — both
	# the player and every enemy (including bosses) are contained by it.
	body.collision_layer = 0b100
	body.collision_mask = 0
	var half: Vector2 = stage["bounds"] * 0.5
	var thick := 64.0
	# [center, size] for each of the four edges (walls sit just outside bounds).
	var edges := [
		[Vector2(0, -half.y - thick * 0.5), Vector2(half.x * 2.0 + thick * 2.0, thick)],  # top
		[Vector2(0, half.y + thick * 0.5), Vector2(half.x * 2.0 + thick * 2.0, thick)],   # bottom
		[Vector2(-half.x - thick * 0.5, 0), Vector2(thick, half.y * 2.0 + thick * 2.0)],  # left
		[Vector2(half.x + thick * 0.5, 0), Vector2(thick, half.y * 2.0 + thick * 2.0)],   # right
	]
	for e in edges:
		var col := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = e[1]
		col.shape = shape
		col.position = e[0]
		body.add_child(col)
	return body
