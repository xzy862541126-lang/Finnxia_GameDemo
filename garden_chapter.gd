extends RefCounted

const Catalog = preload("res://campaign_catalog.gd")
const Scenery = preload("res://scenery_theme.gd")
const Board = preload("res://garden_board.gd")

static func entries() -> Array[Dictionary]:
	return [
		{"title": "第一朵花", "subtitle": "货箱压住粉色花坛 → 藤门永久打开；箱子仍要送到金色目标", "art_index": 2, "theme": 0,
		"rows": ["#########", "#   #   #", "#   #   #", "#       #", "#   #   #", "#   #   #", "#########"],
		"player": Vector2i(1, 3), "boxes": [Vector2i(2, 3)], "goals": [Vector2i(6, 3)],
		"timber": [], "water": [], "flowers": [{"cell": Vector2i(3, 3), "gates": [Vector2i(4, 3)]}], "solution": "RRRR"},
		{"title": "溪上的第一座桥", "subtitle": "蓝绳木料箱推进水沟会变成桥；普通货箱不能进水", "art_index": 3, "theme": 2,
		"rows": ["#########", "#   #   #", "#   #   #", "#       #", "#   #   #", "#   #   #", "#########"],
		"player": Vector2i(1, 3), "boxes": [Vector2i(2, 4), Vector2i(3, 3)], "goals": [Vector2i(6, 3)],
		"timber": [1], "water": [Vector2i(4, 3)], "flowers": [], "solution": "RRDDLULURRRR"},
		{"title": "让花园重新呼吸", "subtitle": "先用货箱开门，再把桥材送入溪沟，最后运货过桥", "art_index": 5, "theme": 0,
		"rows": ["#############", "#   #   #   #", "#   #   #   #", "#           #", "#   #   #   #", "#   #   #   #", "#############"],
		"player": Vector2i(1, 3), "boxes": [Vector2i(2, 3), Vector2i(7, 2)], "goals": [Vector2i(10, 3)],
		"timber": [1], "water": [Vector2i(8, 3)], "flowers": [{"cell": Vector2i(3, 3), "gates": [Vector2i(4, 3)]}],
		"solution": "RRRRUURRDLDRDDLULURRRR"}
	]

static func create_level(index: int) -> Node2D:
	var definition: Dictionary = entries()[index]
	var level: Node2D = Catalog.LEVEL_SCENE.instantiate()
	var rows: Array = definition["rows"]
	var offset: Vector2i = Vector2i(int((20 - str(rows[0]).length()) / 2.0), 2)
	level.set_meta("campaign_index", definition["art_index"])
	level.set_meta("theme", definition["theme"])
	level.set_meta("garden_chapter", index)
	var tiles: TileMapLayer = level.get_node("TileMapLayer") as TileMapLayer
	tiles.clear()
	Scenery.build_courtyard(tiles, rows, offset, definition["art_index"])
	for folder: String in ["Boxes", "Goals"]:
		for child: Node in level.get_node(folder).get_children():
			child.free()
	for index_box: int in range(definition["boxes"].size()):
		var box: Node2D = Catalog.CRATE_SCENE.instantiate()
		box.position = Vector2(offset + definition["boxes"][index_box]) * 64.0
		level.get_node("Boxes").add_child(box)
	for cell: Vector2i in definition["goals"]:
		var goal: Node2D = Catalog.GOAL_SCENE.instantiate()
		goal.position = Vector2(offset + cell) * 64.0
		level.get_node("Goals").add_child(goal)
	level.get_node("player").position = Vector2(offset + definition["player"]) * 64.0
	var water: Array[Vector2i] = []
	for cell: Vector2i in definition["water"]:
		water.append(cell + offset)
	var flowers: Array[Dictionary] = []
	for flower: Dictionary in definition["flowers"]:
		var gates: Array[Vector2i] = []
		for cell: Vector2i in flower["gates"]:
			gates.append(cell + offset)
		flowers.append({"cell": flower["cell"] + offset, "gates": gates})
	level.set_meta("mechanisms", {"timber": definition["timber"], "water": water, "flowers": flowers})
	return level
