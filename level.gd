extends Node2D

signal puzzle_completed
signal state_changed

const GardenArt = preload("res://garden_art.gd")
var suspended: bool = false

const BoardRules = preload("res://sokoban_board.gd")
const GardenRules = preload("res://garden_board.gd")
const MechanismView = preload("res://garden_mechanisms.gd")
const BRIDGE_SUPPLY: Texture2D = preload("res://assets/scenery/bridge_supply.png")
var mechanism_view: MechanismView
var _bridge_barrier: StaticBody2D
const PlayerController = preload("res://player.gd")
const CRATE: Texture2D = preload("res://assets/crate.png")
const CRATE_COMPLETE: Texture2D = preload("res://assets/crate_on_goal.png")
const GOAL: Texture2D = preload("res://assets/goal.png")
const GOAL_COMPLETE: Texture2D = preload("res://assets/goal_complete.png")

var board: BoardRules = BoardRules.new()
var busy: bool = false
var boxes: Array[StaticBody2D] = []
var goals: Array[Sprite2D] = []
var _plan: Dictionary = {}
var _elapsed: float = 0.0
var _duration: float = 0.2
var _player_start: Vector2
var _player_target: Vector2
var _box_start: Vector2
var _box_target: Vector2
var _moving_box: StaticBody2D
var _completion_announced: bool = false
var _goal_positions: Array[Vector2i] = []

@onready var tiles: TileMapLayer = $TileMapLayer
@onready var player: PlayerController = $player
@onready var status_label: Label = $HUD/Panel/Rows/Status
@onready var undo_button: Button = $HUD/Panel/Rows/Buttons/Undo
@onready var restart_button: Button = $HUD/Panel/Rows/Buttons/Restart

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var initial_boxes: Array[Vector2i] = []
	for child: Node in $Boxes.get_children():
		var box: StaticBody2D = child as StaticBody2D
		if box != null:
			boxes.append(box)
			initial_boxes.append(world_to_cell(box.global_position))
	for child: Node in $Goals.get_children():
		var goal: Sprite2D = child as Sprite2D
		if goal != null:
			goals.append(goal)
			_goal_positions.append(world_to_cell(goal.global_position))
	var start: Vector2i = world_to_cell(player.global_position)
	if has_meta("mechanisms"):
		board = GardenRules.new()
	board.configure(_find_floor(start), _goal_positions, start, initial_boxes)
	if board is GardenRules:
		var garden: GardenRules = board as GardenRules
		garden.configure_mechanisms(get_meta("mechanisms"))
		mechanism_view = MechanismView.new()
		mechanism_view.name = "GardenMechanisms"
		add_child(mechanism_view)
		mechanism_view.setup(garden)
	var art: GardenArt = GardenArt.new()
	art.name = "GardenArt"
	art.floor_cells.assign(board.floor_cells.keys())
	for cell: Vector2i in tiles.get_used_cells():
		var source_id: int = tiles.get_cell_source_id(cell)
		art.blocked_cells[cell] = true
		if source_id >= 5:
			art.obstacle_cells[cell] = source_id
		else:
			art.wall_cells.append(cell)
	art.theme_index = int(get_meta("theme", 0))
	art.scene_index = int(get_meta("campaign_index", 0))
	add_child(art)
	player.step_requested.connect(try_step)
	undo_button.pressed.connect(undo_move)
	restart_button.pressed.connect(restart_level)
	_sync_view()

func world_to_cell(top_left: Vector2) -> Vector2i:
	return tiles.local_to_map(tiles.to_local(top_left) + Vector2(tiles.tile_set.tile_size) * 0.5)

func cell_to_world(cell: Vector2i) -> Vector2:
	return tiles.to_global(tiles.map_to_local(cell) - Vector2(tiles.tile_set.tile_size) * 0.5)

func _is_wall(cell: Vector2i) -> bool:
	var data: TileData = tiles.get_cell_tile_data(cell)
	if data == null:
		return false
	for layer_index: int in range(tiles.tile_set.get_physics_layers_count()):
		if data.get_collision_polygons_count(layer_index) > 0:
			return true
	return false

func _find_floor(start: Vector2i) -> Array[Vector2i]:
	var bounds: Rect2i = tiles.get_used_rect()
	var visited: Dictionary[Vector2i, bool] = {start: true}
	var pending: Array[Vector2i] = [start]
	var index: int = 0
	while index < pending.size():
		var current: Vector2i = pending[index]
		index += 1
		for direction: Vector2i in BoardRules.DIRECTIONS:
			var neighbor: Vector2i = current + direction
			if bounds.has_point(neighbor) and not visited.has(neighbor) and not _is_wall(neighbor):
				visited[neighbor] = true
				pending.append(neighbor)
	return pending

func try_step(direction: Vector2i) -> bool:
	if suspended or busy or board.is_solved() or not BoardRules.DIRECTIONS.has(direction):
		return false
	player.face_direction(direction)
	var next_plan: Dictionary = board.plan_step(direction)
	if next_plan.is_empty():
		return false
	var box_index: int = next_plan["box_index"]
	_moving_box = boxes[box_index] if box_index >= 0 else null
	_player_start = player.global_position
	_player_target = cell_to_world(next_plan["to"])
	var motion: Vector2 = _player_target - _player_start
	if _moving_box != null:
		_box_start = _moving_box.global_position
		_box_target = cell_to_world(next_plan["box_to"])
		player.add_collision_exception_with(_moving_box)
		_moving_box.add_collision_exception_with(player)
		if mechanism_view != null:
			_bridge_barrier = mechanism_view.bridge_target(box_index, next_plan["box_to"])
			if _bridge_barrier != null:
				_moving_box.add_collision_exception_with(_bridge_barrier)
		if _moving_box.test_move(_moving_box.global_transform, _box_target - _box_start):
			_release_box_exception()
			return false
	if player.test_move(player.global_transform, motion):
		_release_box_exception()
		return false
	_plan = next_plan
	_elapsed = 0.0
	_duration = player.push_duration if box_index >= 0 else player.walk_duration
	busy = true
	player.begin_step(direction, box_index >= 0)
	undo_button.disabled = true
	return true

func _physics_process(delta: float) -> void:
	if not busy:
		return
	_elapsed = minf(_elapsed + delta, _duration)
	var progress: float = _elapsed / _duration
	# Grid occupancy is committed only after both physical bodies finish this step.
	if _moving_box != null:
		_moving_box.global_position = _box_start.lerp(_box_target, progress)
	var next_position: Vector2 = _player_start.lerp(_player_target, progress)
	var collision: KinematicCollision2D = player.move_and_collide(next_position - player.global_position)
	if collision != null:
		_cancel_motion()
		return
	player.sample_step(progress)
	if progress >= 1.0:
		if not board.commit_step(_plan):
			_cancel_motion()
			return
		_release_box_exception()
		busy = false
		var finished_garden: GardenRules = board as GardenRules
		var delivered: bool = _plan["box_index"] >= 0 and board.goal_cells.has(_plan["box_to"])
		var bloomed: bool = finished_garden != null and finished_garden.blooms.has(_plan["box_to"])
		var built: bool = finished_garden != null and finished_garden.bridges.has(_plan["box_to"])
		_plan.clear()
		player.finish_step()
		_sync_view()
		if built:
			_play_sfx(&"bridge")
		elif bloomed:
			_play_sfx(&"bloom")
		elif delivered:
			_play_sfx(&"placement")

func _play_sfx(name: StringName, throttle: float = 0.0) -> void:
	var audio: Node = get_node_or_null("/root/GameAudio")
	if audio != null and audio.has_method("play"):
		audio.call("play", name, throttle)

func _release_box_exception() -> void:
	if is_instance_valid(_moving_box):
		player.remove_collision_exception_with(_moving_box)
		_moving_box.remove_collision_exception_with(player)
		if is_instance_valid(_bridge_barrier):
			_moving_box.remove_collision_exception_with(_bridge_barrier)
	_bridge_barrier = null
	_moving_box = null

func _cancel_motion() -> void:
	_release_box_exception()
	busy = false
	_plan.clear()
	player.finish_step()
	player.clear_input()
	_sync_view()

func _sync_view() -> void:
	player.global_position = cell_to_world(board.player_cell)
	player.force_update_transform()
	var garden: GardenRules = board as GardenRules
	if mechanism_view != null:
		mechanism_view.sync_state(garden)
	for index: int in range(boxes.size()):
		var cell: Vector2i = board.box_cells[index]
		var used: bool = garden != null and garden.consumed.has(index)
		boxes[index].visible = not used
		boxes[index].collision_layer = 0 if used else 2
		boxes[index].collision_mask = 0 if used else 1
		boxes[index].global_position = cell_to_world(cell)
		boxes[index].force_update_transform()
		var sprite: Sprite2D = boxes[index].get_node("Sprite2D") as Sprite2D
		if garden != null and garden.timber_indices.has(index):
			sprite.texture = BRIDGE_SUPPLY
		else:
			sprite.texture = CRATE_COMPLETE if board.goal_cells.has(cell) else CRATE
	for index: int in range(goals.size()):
		var occupied: bool = board.box_cells.has(_goal_positions[index])
		if garden != null:
			var box_index: int = garden.box_at(_goal_positions[index])
			occupied = box_index >= 0 and not garden.timber_indices.has(box_index)
		goals[index].texture = GOAL_COMPLETE if occupied else GOAL
	var solved: bool = board.is_solved()
	player.input_locked = solved or suspended
	undo_button.disabled = board.history.is_empty() or busy or suspended
	restart_button.disabled = suspended
	status_label.text = "目标 %d / %d    步数 %d    推动 %d" % [board.completed_goals(), goals.size(), board.steps, board.pushes]
	if solved:
		status_label.text = "通关！全部箱子归位    步数 %d    推动 %d" % [board.steps, board.pushes]
		if not _completion_announced:
			_completion_announced = true
			puzzle_completed.emit()
			print("SOKOBAN_COMPLETE steps=%d pushes=%d" % [board.steps, board.pushes])
	else:
		_completion_announced = false
	state_changed.emit()

func undo_move() -> void:
	if suspended or busy:
		return
	if board.undo():
		_play_sfx(&"undo", 0.03)
		player.clear_input()
		player.finish_step()
		_sync_view()

func restart_level() -> void:
	if suspended:
		return
	_release_box_exception()
	busy = false
	_plan.clear()
	board.restart()
	player.clear_input()
	player.finish_step()
	player.face_direction(Vector2i.DOWN)
	_sync_view()

func set_modal(locked: bool) -> void:
	suspended = locked
	if locked and busy:
		_cancel_motion()
	player.clear_input()
	player.wait_for_release = true
	player.input_locked = locked or board.is_solved()
	undo_button.disabled = locked or busy or board.history.is_empty()
	restart_button.disabled = locked

func capture_state() -> Dictionary:
	var moves: String = ""
	var letters: Dictionary[Vector2i, String] = {Vector2i.UP: "U", Vector2i.DOWN: "D", Vector2i.LEFT: "L", Vector2i.RIGHT: "R"}
	for index: int in range(board.history.size()):
		var before: Vector2i = board.history[index]["player"]
		var after: Vector2i = board.history[index + 1]["player"] if index + 1 < board.history.size() else board.player_cell
		moves += letters[after - before]
	return {"moves": moves, "total_steps": board.steps}

func restore_state(snapshot: Dictionary) -> bool:
	if not snapshot.get("moves") is String or str(snapshot["moves"]).length() > 10000:
		return false
	var total_steps: Variant = snapshot.get("total_steps", str(snapshot["moves"]).length())
	if not (total_steps is int or total_steps is float):
		return false
	if not is_finite(float(total_steps)) or float(total_steps) != floorf(float(total_steps)) or float(total_steps) < str(snapshot["moves"]).length() or float(total_steps) > 2147483647:
		return false
	var candidate: BoardRules = GardenRules.new() if board is GardenRules else BoardRules.new()
	var floor_tiles: Array[Vector2i] = []
	floor_tiles.assign(board.floor_cells.keys())
	candidate.configure(floor_tiles, _goal_positions, board._initial_player, board._initial_boxes)
	if candidate is GardenRules:
		(candidate as GardenRules).configure_mechanisms((board as GardenRules).mechanisms)
	var directions: Dictionary[String, Vector2i] = {"U": Vector2i.UP, "D": Vector2i.DOWN, "L": Vector2i.LEFT, "R": Vector2i.RIGHT}
	for letter: String in str(snapshot["moves"]):
		if not directions.has(letter) or not candidate.commit_step(candidate.plan_step(directions[letter])):
			return false
	candidate.steps = int(total_steps)
	_release_box_exception()
	busy = false
	_plan.clear()
	board = candidate
	player.clear_input()
	player.finish_step()
	_sync_view()
	return true

func _unhandled_input(event: InputEvent) -> void:
	if suspended or not event is InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode in [KEY_Z, KEY_U, KEY_BACKSPACE]:
		undo_move()
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_R:
		restart_level()
		get_viewport().set_input_as_handled()
