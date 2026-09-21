extends RefCounted

const DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

var floor_cells: Dictionary[Vector2i, bool] = {}
var goal_cells: Dictionary[Vector2i, bool] = {}
var player_cell: Vector2i
var box_cells: Array[Vector2i] = []
var steps: int = 0
var pushes: int = 0
var history: Array[Dictionary] = []
var _initial_player: Vector2i
var _initial_boxes: Array[Vector2i] = []

func configure(floor_tiles: Array[Vector2i], goals: Array[Vector2i], start: Vector2i, boxes: Array[Vector2i]) -> void:
	floor_cells.clear()
	goal_cells.clear()
	for cell: Vector2i in floor_tiles:
		floor_cells[cell] = true
	for cell: Vector2i in goals:
		goal_cells[cell] = true
	_initial_player = start
	_initial_boxes = boxes.duplicate()
	restart()

func plan_step(direction: Vector2i) -> Dictionary:
	if not DIRECTIONS.has(direction) or is_solved():
		return {}
	var destination: Vector2i = player_cell + direction
	if not floor_cells.has(destination):
		return {}
	var box_index: int = box_cells.find(destination)
	var box_destination: Vector2i = destination + direction
	if box_index >= 0 and (not floor_cells.has(box_destination) or box_cells.has(box_destination)):
		return {}
	return {
		"direction": direction,
		"from": player_cell,
		"to": destination,
		"box_index": box_index,
		"box_from": destination,
		"box_to": box_destination
	}

func commit_step(plan: Dictionary) -> bool:
	if plan.is_empty() or plan != plan_step(plan.get("direction", Vector2i.ZERO)):
		return false
	history.append({"player": player_cell, "boxes": box_cells.duplicate(), "steps": steps, "pushes": pushes})
	player_cell = plan["to"]
	var box_index: int = plan["box_index"]
	if box_index >= 0:
		box_cells[box_index] = plan["box_to"]
		pushes += 1
	steps += 1
	return true

func undo() -> bool:
	if history.is_empty():
		return false
	var snapshot: Dictionary = history.pop_back()
	player_cell = snapshot["player"]
	box_cells.assign(snapshot["boxes"])
	steps += 1
	pushes = snapshot["pushes"]
	return true

func restart() -> void:
	player_cell = _initial_player
	box_cells = _initial_boxes.duplicate()
	steps = 0
	pushes = 0
	history.clear()

func completed_goals() -> int:
	var count: int = 0
	for cell: Vector2i in box_cells:
		if goal_cells.has(cell):
			count += 1
	return count

func is_solved() -> bool:
	return not goal_cells.is_empty() and box_cells.size() == goal_cells.size() and completed_goals() == goal_cells.size()
