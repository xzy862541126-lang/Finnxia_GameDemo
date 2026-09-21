extends Node2D

const GardenBoard = preload("res://garden_board.gd")
var status_label: Label
var board: GardenBoard
var barriers: Dictionary[Vector2i, StaticBody2D] = {}
var _previous_blooms: Dictionary = {}
var _previous_bridges: Dictionary = {}
var _bursts: Dictionary[Vector2i, float] = {}
var _clock: float = 0.0
var _tick: float = 0.0

func setup(rules: GardenBoard) -> void:
	board = rules
	status_label = Label.new()
	status_label.position = Vector2(190, 635)
	status_label.size = Vector2(900, 45)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 20)
	status_label.add_theme_color_override("font_color", Color("ecd5ab"))
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(status_label)
	for cell: Vector2i in board.water_cells:
		_add_barrier(cell)
	for flower: Vector2i in board.flower_gates:
		for cell: Vector2i in board.flower_gates[flower]:
			_add_barrier(cell)
	sync_state(rules, false)

func _add_barrier(cell: Vector2i) -> void:
	if barriers.has(cell):
		return
	var body: StaticBody2D = StaticBody2D.new()
	body.position = Vector2(cell) * 64.0
	body.collision_layer = 1
	body.collision_mask = 3
	var collider: CollisionShape2D = CollisionShape2D.new()
	var rectangle: RectangleShape2D = RectangleShape2D.new()
	rectangle.size = Vector2(64, 64)
	collider.position = Vector2(32, 32)
	collider.shape = rectangle
	body.add_child(collider)
	add_child(body)
	barriers[cell] = body

func bridge_target(index: int, cell: Vector2i) -> StaticBody2D:
	if board.timber_indices.has(index) and board.water_cells.has(cell) and not board.bridges.has(cell):
		return barriers.get(cell) as StaticBody2D
	return null

func sync_state(rules: GardenBoard, animate: bool = true) -> void:
	board = rules
	var sections: PackedStringArray = []
	if not board.flower_gates.is_empty():
		sections.append("花坛 %d / %d · 藤门开后常开" % [board.blooms.size(), board.flower_gates.size()])
	if not board.water_cells.is_empty():
		sections.append("木桥 %d / %d · 蓝绳桥材不计目标" % [board.bridges.size(), board.water_cells.size()])
	status_label.text = "    |    ".join(sections)
	for cell: Vector2i in _bursts.keys():
		if not board.blooms.has(cell) and not board.bridges.has(cell):
			_bursts.erase(cell)
	for cell: Vector2i in barriers:
		barriers[cell].collision_layer = 0 if board.walkable(cell) else 1
		barriers[cell].collision_mask = 0 if board.walkable(cell) else 3
	if animate:
		for cell: Vector2i in board.blooms:
			if not _previous_blooms.has(cell):
				_bursts[cell] = 1.0
		for cell: Vector2i in board.bridges:
			if not _previous_bridges.has(cell):
				_bursts[cell] = 1.0
	else:
		_bursts.clear()
	_previous_blooms = board.blooms.duplicate()
	_previous_bridges = board.bridges.duplicate()
	queue_redraw()

func _process(delta: float) -> void:
	_clock += delta
	_tick += delta
	for cell: Vector2i in _bursts.keys():
		_bursts[cell] -= delta
		if _bursts[cell] <= 0.0:
			_bursts.erase(cell)
	if _tick >= 0.08:
		_tick = 0.0
		queue_redraw()

func _flower(at: Vector2, color: Color, size_px: int = 4) -> void:
	draw_rect(Rect2(at + Vector2(-size_px, -2), Vector2(size_px * 2 + 2, 4)), color)
	draw_rect(Rect2(at + Vector2(-2, -size_px), Vector2(4, size_px * 2 + 2)), color)
	draw_rect(Rect2(at + Vector2(-1, -1), Vector2(3, 3)), Color("ffe6a0"))

func _draw() -> void:
	if board == null:
		return
	for cell: Vector2i in board.water_cells:
		var pos: Vector2 = Vector2(cell) * 64.0
		draw_rect(Rect2(pos, Vector2(64, 64)), Color("253f53"))
		draw_rect(Rect2(pos + Vector2(3, 3), Vector2(58, 58)), Color("377d90"))
		for row: int in range(4):
			var shift: int = int(_clock * 5.0 + row * 7) % 22
			draw_rect(Rect2(pos + Vector2(6 + shift, 10 + row * 12), Vector2(17, 2)), Color("8fc1c4"))
		if board.bridges.has(cell):
			draw_rect(Rect2(pos + Vector2(0, 7), Vector2(64, 51)), Color("483b33"))
			for plank: int in range(7):
				draw_rect(Rect2(pos + Vector2(plank * 9 + 1, 10), Vector2(8, 45)), Color("b58c55"))
				draw_rect(Rect2(pos + Vector2(plank * 9 + 2, 12), Vector2(2, 40)), Color("e0bb79"))
			draw_rect(Rect2(pos + Vector2(0, 16), Vector2(64, 3)), Color("6f543c"))
			draw_rect(Rect2(pos + Vector2(0, 48), Vector2(64, 3)), Color("6f543c"))
	for cell: Vector2i in board.flower_gates:
		var pos: Vector2 = Vector2(cell) * 64.0
		var open: bool = board.blooms.has(cell)
		draw_rect(Rect2(pos + Vector2(3, 3), Vector2(58, 58)), Color("596f50"))
		draw_rect(Rect2(pos + Vector2(6, 6), Vector2(52, 52)), Color("7b8963"))
		for side: int in range(4):
			var dot: Vector2 = Vector2(12 + side * 13, 8)
			_flower(pos + dot, Color("f5b5bf") if open else Color("b48e9e"), 3)
			_flower(pos + Vector2(dot.x, 56), Color("f5b5bf") if open else Color("b48e9e"), 3)
		_flower(pos + Vector2(32, 31), Color("f5afc1") if open else Color("bea0a3"), 8 if open else 4)
		for gate: Vector2i in board.flower_gates[cell]:
			var gp: Vector2 = Vector2(gate) * 64.0
			draw_rect(Rect2(gp + Vector2(2, 2), Vector2(5, 60)), Color("447155"))
			draw_rect(Rect2(gp + Vector2(57, 2), Vector2(5, 60)), Color("447155"))
			if board.gate_closed(gate):
				for branch: int in range(4):
					var bx: float = 9 + branch * 13
					draw_polyline(PackedVector2Array([gp + Vector2(bx, 3), gp + Vector2(bx + 7, 22), gp + Vector2(bx - 4, 44), gp + Vector2(bx + 2, 61)]), Color("294c39"), 8)
					draw_polyline(PackedVector2Array([gp + Vector2(bx, 3), gp + Vector2(bx + 7, 22), gp + Vector2(bx - 4, 44), gp + Vector2(bx + 2, 61)]), Color("79a262"), 3)
					_flower(gp + Vector2(bx + 5, 26), Color("c49db0"), 3)
			else:
				_flower(gp + Vector2(5, 14), Color("f0aebd"), 4)
				_flower(gp + Vector2(59, 49), Color("f0aebd"), 4)
	for cell: Vector2i in _bursts:
		var age: float = 1.0 - _bursts[cell]
		for index: int in range(10):
			var angle: float = TAU * index / 10.0
			var at: Vector2 = Vector2(cell) * 64.0 + Vector2(32, 32) + Vector2(cos(angle), sin(angle)) * (10.0 + age * 50.0)
			draw_rect(Rect2(at.round(), Vector2(4, 4)), Color(1.0, 0.83, 0.52, 1.0 - age))
