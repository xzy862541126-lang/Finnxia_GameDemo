extends RefCounted

const TEXTURES: Dictionary[int, String] = {
	8: "timber_stack", 9: "flower_planter", 10: "vine_pillar",
	11: "moon_basin", 12: "workbench", 13: "fern_mound",
	14: "bell_stand", 15: "grain_sacks", 16: "frost_bush",
	17: "star_lantern", 18: "vine_arch", 19: "moon_bridge", 20: "timber_shed"
}
const CARDINALS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

static func install_sources(tiles: TileMapLayer) -> void:
	tiles.tile_set = tiles.tile_set.duplicate()
	for source_id: int in TEXTURES:
		var source: TileSetAtlasSource = TileSetAtlasSource.new()
		source.texture = load("res://assets/scenery/%s.png" % TEXTURES[source_id]) as Texture2D
		source.texture_region_size = Vector2i(64, 64)
		source.resource_name = TEXTURES[source_id]
		tiles.tile_set.add_source(source, source_id)
		source.create_tile(Vector2i.ZERO)
		var tile: TileData = source.get_tile_data(Vector2i.ZERO, 0)
		tile.set_collision_polygons_count(0, 1)
		tile.set_collision_polygon_points(0, 0, PackedVector2Array([Vector2(-32, -32), Vector2(32, -32), Vector2(32, 32), Vector2(-32, 32)]))

static func silhouette(width: int, height: int, index: int) -> Dictionary[Vector2i, bool]:
	var region: Dictionary[Vector2i, bool] = {}
	var left_center: int = 2 + index % maxi(1, height - 4)
	var right_center: int = height - 3 - index % 2
	for y: int in range(height):
		var left: int = 0
		var right: int = width - 1
		if y == 0 or y == height - 1:
			left = 1
			right = width - 2
		elif y >= 2 and y <= height - 3:
			left = -2 if absi(y - left_center) <= 1 else -1
			right += 2 if absi(y - right_center) <= 1 else 1
		for x: int in range(left, right + 1):
			region[Vector2i(x, y)] = true
	return region

static func is_boundary(cell: Vector2i, region: Dictionary[Vector2i, bool]) -> bool:
	for direction: Vector2i in CARDINALS:
		if not region.has(cell + direction):
			return true
	return false

static func interior_sources(index: int) -> Array[int]:
	match index:
		1: return [20, 8, 7]
		2: return [10, 10, 9]
		3: return [11, 5, 10]
		4: return [12, 8, 9]
		5: return [6, 13, 6, 5]
		6: return [14, 15, 7, 8]
		7: return [16, 10, 5, 16, 13]
		8: return [17, 15, 20, 14, 17, 7]
	return [5, 6, 7]

static func border_sources(index: int) -> Array[int]:
	match index:
		1: return [8, 7, 6, 20, 8, 13]
		2: return [18, 18, 9, 9, 10, 13]
		3: return [19, 11, 5, 19, 10, 11]
		4: return [12, 9, 8, 7, 12, 9]
		5: return [13, 6, 13, 5, 13, 6]
		6: return [14, 7, 15, 8, 7, 15]
		7: return [16, 5, 16, 10, 16, 13]
		8: return [17, 15, 20, 8, 17, 14]
	return [5, 6, 7]

static func build_courtyard(tiles: TileMapLayer, rows: Array, offset: Vector2i, index: int) -> void:
	install_sources(tiles)
	var width: int = str(rows[0]).length()
	var height: int = rows.size()
	var region: Dictionary[Vector2i, bool] = silhouette(width, height, index)
	var interior: Array[int] = interior_sources(index)
	var border: Array[int] = border_sources(index)
	var interior_index: int = 0
	var border_index: int = 0
	for cell: Vector2i in region:
		var original: bool = cell.x >= 0 and cell.x < width
		if original and str(rows[cell.y])[cell.x] != "#":
			continue
		var source_id: int
		if is_boundary(cell, region):
			var variants: Array[int] = [1, 3, 4, 4, 4]
			source_id = variants[posmod(cell.x * 7 + cell.y * 3 + index, variants.size())]
		elif original and cell.x > 0 and cell.x < width - 1:
			source_id = interior[interior_index % interior.size()]
			interior_index += 1
		else:
			source_id = border[border_index % border.size()]
			border_index += 1
		tiles.set_cell(offset + cell, source_id, Vector2i.ZERO)
