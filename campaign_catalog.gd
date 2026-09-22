extends RefCounted

const SceneryTheme = preload("res://scenery_theme.gd")
const LEVEL_SCENE: PackedScene = preload("res://level_1.tscn")
const CRATE_SCENE: PackedScene = preload("res://crate.tscn")
const GOAL_SCENE: PackedScene = preload("res://goal.tscn")
const ORIGINAL_SOLUTION: String = "LDDLLURRURDDUUURRRDDURRDDLLLRUUULLLDDRD"

static func grade(steps: int, reference: int) -> String:
	if reference <= 0 or steps < 0:
		return "—"
	if steps <= reference:
		return "S"
	if steps * 4 <= reference * 5:
		return "A"
	if steps * 5 <= reference * 8:
		return "B"
	return "C"

static func aggregate(records: Dictionary, definitions: Array[Dictionary]) -> Dictionary:
	var steps: int = 0
	var reference: int = 0
	for index: int in range(definitions.size()):
		if not records.has(str(index)):
			return {"grade": "—", "steps": steps, "reference": reference}
		steps += int(records[str(index)]["steps"])
		reference += str(definitions[index]["solution"]).length()
	return {"grade": grade(steps, reference), "steps": steps, "reference": reference}

static func entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var file: FileAccess = FileAccess.open("res://campaign_levels.json", FileAccess.READ)
	if file == null:
		push_error("Missing campaign_levels.json")
		return result
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Array:
		for entry: Dictionary in parsed:
			result.append(entry)
	result.insert(3, {
		"title": "苔石庭院", "subtitle": "综合练习：从两侧绕行，按顺序把三箱送入围栏", "difficulty": "进阶",
		"theme": 0, "art_index": 0, "original_scene": true, "solution": ORIGINAL_SOLUTION,
		"difficulty_metrics": {"minimum_pushes": 11, "forced_extra_pushes": 0, "solution_steps": 39}
	})
	return result

static func create_level(index: int) -> Node2D:
	var all_levels: Array[Dictionary] = entries()
	assert(index >= 0 and index < all_levels.size())
	var definition: Dictionary = all_levels[index]
	var level: Node2D = LEVEL_SCENE.instantiate()
	var art_index: int = int(definition.get("art_index", index))
	level.set_meta("campaign_index", art_index)
	level.set_meta("campaign_title", definition["title"])
	level.set_meta("theme", definition["theme"])
	if definition.get("original_scene", false):
		return level
	var tiles: TileMapLayer = level.get_node("TileMapLayer") as TileMapLayer
	tiles.clear()
	var rows: Array = definition["rows"]
	var width: int = str(rows[0]).length()
	var offset: Vector2i = Vector2i(int((20 - width) / 2.0), maxi(1, int((12 - rows.size()) / 2.0)))
	SceneryTheme.build_courtyard(tiles, rows, offset, art_index)
	var box_parent: Node = level.get_node("Boxes")
	var goal_parent: Node = level.get_node("Goals")
	for child: Node in box_parent.get_children():
		child.free()
	for child: Node in goal_parent.get_children():
		child.free()
	for pair: Array in definition["boxes"]:
		var box: Node2D = CRATE_SCENE.instantiate()
		box.position = Vector2(offset + Vector2i(int(pair[0]), int(pair[1]))) * 64.0
		box_parent.add_child(box)
	for pair: Array in definition["goals"]:
		var goal: Node2D = GOAL_SCENE.instantiate()
		goal.position = Vector2(offset + Vector2i(int(pair[0]), int(pair[1]))) * 64.0
		goal_parent.add_child(goal)
	var start: Array = definition["player"]
	level.get_node("player").position = Vector2(offset + Vector2i(int(start[0]), int(start[1]))) * 64.0
	return level
