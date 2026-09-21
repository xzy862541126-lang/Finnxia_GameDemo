extends Node2D

var floor_cells: Array[Vector2i] = []
var wall_cells: Array[Vector2i] = []
var obstacle_cells: Dictionary[Vector2i, int] = {}
var blocked_cells: Dictionary[Vector2i, bool] = {}
var scene_index: int = 0
var theme_index: int = 0
var menu_mode: bool = false
var revival_stage: int = 0
var _time: float = 0.0
var _accumulator: float = 0.0
const COLORS: Array[Color] = [Color("223e36"), Color("3d3e29"), Color("243642"), Color("34314a")]
const FLOORS: Array[Color] = [Color("72806a"), Color("948665"), Color("728893"), Color("858092")]
const LEAVES: Array[Color] = [Color("345b45"), Color("746539"), Color("345767"), Color("524b6b")]
const MENU_COVER: Texture2D = preload("res://assets/ui/menu_cover.png")

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = -10

func _process(delta: float) -> void:
	_time += delta
	_accumulator += delta
	if _accumulator >= 0.1:
		_accumulator = 0.0
		queue_redraw()

func _draw() -> void:
	var palette: int = posmod(theme_index, COLORS.size())
	draw_rect(Rect2(0, 0, 1280, 768), COLORS[palette])
	for y: int in range(0, 768, 16):
		for x: int in range(0, 1280, 16):
			var seed_value: int = posmod(x * 31 + y * 17, 101)
			if seed_value < 27:
				draw_rect(Rect2(x + 3, y + 6, 3, 5), COLORS[palette].lightened(0.055))
				if seed_value < 8:
					draw_rect(Rect2(x + 6, y + 3, 2, 7), COLORS[palette].lightened(0.08))
	if menu_mode:
		_draw_menu_garden(palette)
	else:
		for cell: Vector2i in wall_cells:
			draw_rect(Rect2(Vector2(cell) * 64.0 + Vector2(4, 10), Vector2(64, 64)), Color(0.03, 0.09, 0.09, 0.4))
		for cell: Vector2i in floor_cells:
			_draw_paving(Vector2(cell) * 64.0, cell.x + cell.y * 7, palette)
		for cell: Vector2i in obstacle_cells:
			_draw_paving(Vector2(cell) * 64.0, cell.x + cell.y * 7, palette)
			_draw_obstacle_base(Vector2(cell) * 64.0, obstacle_cells[cell], palette)
		for cell: Vector2i in wall_cells:
			if not blocked_cells.has(cell + Vector2i.UP) and not floor_cells.has(cell + Vector2i.UP):
				var pos: Vector2 = Vector2(cell) * 64.0
				if posmod(cell.x + cell.y, 3) == 0:
					_draw_bush(pos + Vector2(30, -8), palette)
				if posmod(cell.x * 3 + cell.y, 5) == 0:
					_draw_lamp(pos + Vector2(32, -16))
			if not blocked_cells.has(cell + Vector2i.LEFT) and not floor_cells.has(cell + Vector2i.LEFT) and posmod(cell.y, 2) == 0:
				_draw_flowers(Vector2(cell) * 64.0 + Vector2(-20, 40), palette)
		_draw_theme_accents(palette)
	for index: int in range(38 if scene_index == 5 else 22):
		var px: float = fmod(index * 173.0 + sin(_time * 0.4 + index) * 12.0 + 1300.0, 1280.0)
		var py: float = fmod(index * 97.0 + _time * (3.0 + index % 3), 690.0) + 30.0
		var alpha: float = 0.2 + 0.3 * (sin(_time * 1.6 + index) * 0.5 + 0.5)
		draw_rect(Rect2(roundf(px), roundf(py), 3, 3), Color(0.93, 0.85, 0.46, alpha))

func _draw_paving(pos: Vector2, seed_value: int, palette: int) -> void:
	var base: Color = FLOORS[palette].darkened(float(posmod(seed_value, 4)) * 0.025)
	draw_rect(Rect2(pos, Vector2(64, 64)), base.darkened(0.19))
	draw_rect(Rect2(pos + Vector2(1, 1), Vector2(61, 61)), base)
	draw_rect(Rect2(pos + Vector2(2, 2), Vector2(59, 2)), base.lightened(0.12))
	draw_rect(Rect2(pos + Vector2(2, 3), Vector2(2, 57)), base.lightened(0.05))
	draw_rect(Rect2(pos + Vector2(5, 60), Vector2(55, 2)), base.darkened(0.08))
	if posmod(seed_value, 5) == 0:
		draw_line(pos + Vector2(45, 2), pos + Vector2(42, 9), base.darkened(0.15), 2)
		draw_line(pos + Vector2(42, 9), pos + Vector2(48, 13), base.darkened(0.15), 2)
	if posmod(seed_value, 7) == 0:
		draw_rect(Rect2(pos + Vector2(3, 51), Vector2(5, 8)), LEAVES[palette])

func _draw_obstacle_base(pos: Vector2, source_id: int, palette: int) -> void:
	var shadow: Color = Color(0.12, 0.17, 0.17, 0.20)
	draw_rect(Rect2(pos + Vector2(12, 45), Vector2(40, 13)), shadow)
	draw_rect(Rect2(pos + Vector2(7, 48), Vector2(50, 7)), shadow)
	if source_id in [5, 6, 13, 16]:
		var moss: Color = LEAVES[palette].lightened(0.06)
		if source_id == 16:
			moss = Color("b1c6c3")
		draw_rect(Rect2(pos + Vector2(7, 50), Vector2(9, 3)), moss)
		draw_rect(Rect2(pos + Vector2(45, 54), Vector2(11, 3)), moss)
		draw_rect(Rect2(pos + Vector2(50, 46), Vector2(3, 6)), moss.darkened(0.12))
	elif source_id in [7, 8, 12, 14, 15, 20]:
		draw_rect(Rect2(pos + Vector2(6, 57), Vector2(49, 2)), Color("aa9165"))
		draw_rect(Rect2(pos + Vector2(10, 60), Vector2(5, 1)), Color("887655"))
	elif source_id in [9, 10, 18]:
		_draw_flowers(pos + Vector2(8, 53), palette)
	elif source_id in [11, 19]:
		draw_rect(Rect2(pos + Vector2(8, 56), Vector2(10, 2)), Color("8fbec5"))
		draw_rect(Rect2(pos + Vector2(44, 50), Vector2(9, 2)), Color("60949d"))
	elif source_id == 17:
		draw_rect(Rect2(pos + Vector2(5, 35), Vector2(54, 26)), Color(0.91, 0.75, 0.36, 0.08))

func _draw_theme_accents(palette: int) -> void:
	for cell: Vector2i in wall_cells:
		if not blocked_cells.has(cell + Vector2i.UP) and not floor_cells.has(cell + Vector2i.UP):
			var pos: Vector2 = Vector2(cell) * 64.0
			if scene_index == 7:
				draw_rect(Rect2(pos + Vector2(6, -3), Vector2(51, 3)), Color("bfd1cc"))
			elif scene_index == 5 and posmod(cell.x, 2) == 0:
				_draw_bush(pos + Vector2(9, -9), palette)
		if scene_index == 3 and not blocked_cells.has(cell + Vector2i.LEFT) and not floor_cells.has(cell + Vector2i.LEFT):
			var bank: Vector2 = Vector2(cell) * 64.0 + Vector2(-21, 7)
			draw_rect(Rect2(bank, Vector2(15, 48)), Color("315568"))
			draw_rect(Rect2(bank + Vector2(3, 12), Vector2(8, 2)), Color("76a7b4"))
			draw_rect(Rect2(bank + Vector2(6, 33), Vector2(7, 2)), Color("76a7b4"))
	for cell: Vector2i in floor_cells:
		if posmod(cell.x * 5 + cell.y * 3, 13) != 0:
			continue
		var pos: Vector2 = Vector2(cell) * 64.0
		if scene_index == 8:
			draw_rect(Rect2(pos + Vector2(8, 8), Vector2(2, 8)), Color("d2bd87"))
			draw_rect(Rect2(pos + Vector2(5, 11), Vector2(8, 2)), Color("d2bd87"))
		elif scene_index == 4:
			for petal: Vector2 in [Vector2(6, 8), Vector2(10, 8), Vector2(6, 12), Vector2(10, 12)]:
				draw_rect(Rect2(pos + petal, Vector2(3, 3)), Color("7e9e67"))
		elif scene_index == 2:
			draw_rect(Rect2(pos + Vector2(8, 11), Vector2(3, 2)), Color("d6b39b"))
		elif scene_index == 7:
			draw_rect(Rect2(pos + Vector2(4, 51), Vector2(7, 3)), Color("bac7be"))

func _draw_bush(pos: Vector2, palette: int) -> void:
	var leaf: Color = LEAVES[palette]
	draw_rect(Rect2(pos + Vector2(-24, -4), Vector2(48, 20)), Color("192e2b"))
	draw_rect(Rect2(pos + Vector2(-26, -20), Vector2(50, 27)), leaf.darkened(0.18))
	draw_rect(Rect2(pos + Vector2(-20, -29), Vector2(37, 34)), leaf)
	draw_rect(Rect2(pos + Vector2(-8, -34), Vector2(26, 32)), leaf.lightened(0.09))
	for index: int in range(7):
		draw_rect(Rect2(pos + Vector2(-16 + index * 5, -24 + (index % 3) * 8), Vector2(5, 3)), leaf.lightened(0.2))

func _draw_flowers(pos: Vector2, palette: int) -> void:
	for index: int in range(3):
		var center: Vector2 = pos + Vector2(index * 9 - 8, -(index % 2) * 9)
		draw_rect(Rect2(center, Vector2(2, 12)), LEAVES[palette].lightened(0.22))
		draw_rect(Rect2(center + Vector2(-3, -3), Vector2(8, 5)), Color("d79882") if index % 2 == 0 else Color("e7d89e"))
		draw_rect(Rect2(center + Vector2(-1, -5), Vector2(4, 9)), Color("e0b8a3") if index % 2 == 0 else Color("e7d89e"))
		draw_rect(Rect2(center, Vector2(2, 2)), Color("93623e"))

func _draw_lamp(pos: Vector2) -> void:
	draw_rect(Rect2(pos + Vector2(-2, 0), Vector2(4, 19)), Color("303d38"))
	draw_rect(Rect2(pos + Vector2(-9, -18), Vector2(18, 22)), Color("243831"))
	draw_rect(Rect2(pos + Vector2(-6, -15), Vector2(12, 15)), Color("d0a457"))
	draw_rect(Rect2(pos + Vector2(-3, -13), Vector2(6, 11)), Color("fae8a2"))
	draw_rect(Rect2(pos + Vector2(-11, -21), Vector2(22, 4)), Color("a18b57"))

func _draw_restored_garden() -> void:
	for index: int in range(14):
		var at: Vector2 = Vector2(745 + index * 31, 745 - (index % 3) * 8)
		_draw_flowers(at, 0)
	if revival_stage >= 2:
		for at: Vector2 in [Vector2(795, 720), Vector2(1128, 720)]:
			draw_rect(Rect2(at + Vector2(-28, -35), Vector2(56, 62)), Color(1.0, 0.80, 0.36, 0.08))
			draw_rect(Rect2(at + Vector2(-18, -28), Vector2(36, 44)), Color(1.0, 0.80, 0.36, 0.10))
			_draw_lamp(at)
	if revival_stage >= 3:
		for index: int in range(16):
			var px: float = 740 + index * 28 + sin(_time + index) * 4
			var py: float = 693 + sin(_time * 0.8 + index * 1.4) * 16
			draw_rect(Rect2(roundf(px), roundf(py), 3, 3), Color("f5da93"))

func _draw_menu_garden(_palette: int) -> void:
	draw_texture_rect(MENU_COVER, Rect2(640, 0, 640, 768), false)
	if revival_stage > 0:
		_draw_restored_garden()
	draw_rect(Rect2(0, 0, 640, 768), Color(0.045, 0.10, 0.10, 0.83))
	for strip: int in range(24):
		var alpha: float = 0.72 * (1.0 - float(strip) / 24.0)
		draw_rect(Rect2(640 + strip * 2, 0, 2, 768), Color(0.045, 0.10, 0.10, alpha))
