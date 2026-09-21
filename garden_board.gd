extends "res://sokoban_board.gd"

var mechanisms: Dictionary = {}
var timber_indices: Dictionary[int, bool] = {}
var water_cells: Dictionary[Vector2i, bool] = {}
var flower_gates: Dictionary[Vector2i, Array] = {}
var blooms: Dictionary[Vector2i, bool] = {}
var bridges: Dictionary[Vector2i, bool] = {}
var consumed: Dictionary[int, bool] = {}

func configure_mechanisms(definition: Dictionary) -> void:
	mechanisms = definition.duplicate(true)
	timber_indices.clear()
	water_cells.clear()
	flower_gates.clear()
	for index: int in definition.get("timber", []):
		timber_indices[index] = true
	for cell: Vector2i in definition.get("water", []):
		water_cells[cell] = true
	for flower: Dictionary in definition.get("flowers", []):
		flower_gates[flower["cell"]] = flower["gates"].duplicate()
	restart()

func box_at(cell: Vector2i) -> int:
	for index: int in range(box_cells.size()):
		if not consumed.has(index) and box_cells[index] == cell:
			return index
	return -1

func gate_closed(cell: Vector2i) -> bool:
	for flower: Vector2i in flower_gates:
		if flower_gates[flower].has(cell) and not blooms.has(flower):
			return true
	return false

func walkable(cell: Vector2i) -> bool:
	return floor_cells.has(cell) and not gate_closed(cell) and (not water_cells.has(cell) or bridges.has(cell))

func plan_step(direction: Vector2i) -> Dictionary:
	if not DIRECTIONS.has(direction) or is_solved():
		return {}
	var destination: Vector2i = player_cell + direction
	if not walkable(destination):
		return {}
	var box_index: int = box_at(destination)
	var next_cell: Vector2i = destination + direction
	if box_index >= 0:
		if box_at(next_cell) >= 0 or not floor_cells.has(next_cell) or gate_closed(next_cell):
			return {}
		if not walkable(next_cell) and not timber_indices.has(box_index):
			return {}
	return {"direction": direction, "from": player_cell, "to": destination,
		"box_index": box_index, "box_from": destination, "box_to": next_cell}

func commit_step(plan: Dictionary) -> bool:
	var before: Dictionary = {"blooms": blooms.duplicate(), "bridges": bridges.duplicate(), "consumed": consumed.duplicate()}
	if not super.commit_step(plan):
		return false
	history.back().merge(before)
	var index: int = plan["box_index"]
	if index >= 0:
		var cell: Vector2i = plan["box_to"]
		if timber_indices.has(index) and water_cells.has(cell) and not bridges.has(cell):
			bridges[cell] = true
			consumed[index] = true
		elif not timber_indices.has(index) and flower_gates.has(cell):
			blooms[cell] = true
	return true

func undo() -> bool:
	if history.is_empty():
		return false
	var previous: Dictionary = history.back()
	if not super.undo():
		return false
	blooms.assign(previous["blooms"])
	bridges.assign(previous["bridges"])
	consumed.assign(previous["consumed"])
	return true

func restart() -> void:
	super.restart()
	blooms.clear()
	bridges.clear()
	consumed.clear()

func completed_goals() -> int:
	var count: int = 0
	for index: int in range(box_cells.size()):
		if not timber_indices.has(index) and goal_cells.has(box_cells[index]):
			count += 1
	return count

func is_solved() -> bool:
	return not goal_cells.is_empty() and box_cells.size() - timber_indices.size() == goal_cells.size() and completed_goals() == goal_cells.size()
