extends SceneTree

const BoardRules = preload("res://sokoban_board.gd")
const LevelController = preload("res://level.gd")
const LEVEL: PackedScene = preload("res://level_1.tscn")
const SOLUTION: String = "LDDLLURRURDDUUURRRDDURRDDLLLRUUULLLDDRD"
const DIRECTIONS: Dictionary[String, Vector2i] = {"U": Vector2i.UP, "D": Vector2i.DOWN, "L": Vector2i.LEFT, "R": Vector2i.RIGHT}

var failures: int = 0
var checks: int = 0
var completion_count: int = 0

func _initialize() -> void:
	_run.call_deferred()

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("SOKOBAN_TEST: " + message)

func _test_rules() -> void:
	var floor_tiles: Array[Vector2i] = []
	for y: int in range(5):
		for x: int in range(5):
			floor_tiles.append(Vector2i(x, y))
	var rules: BoardRules = BoardRules.new()
	rules.configure(floor_tiles, [Vector2i(3, 2)], Vector2i(1, 2), [Vector2i(2, 2)])
	expect(rules.plan_step(Vector2i(1, 1)).is_empty(), "No diagonal moves")
	expect(rules.plan_step(Vector2i.ZERO).is_empty(), "No zero-length moves")
	var plan: Dictionary = rules.plan_step(Vector2i.RIGHT)
	expect(not plan.is_empty() and rules.steps == 0, "Planning is read-only")
	expect(rules.commit_step(plan), "Single-box push accepted")
	expect(rules.is_solved() and rules.steps == 1 and rules.pushes == 1, "Goal completion and counts")
	expect(not rules.commit_step(plan), "Stale transaction rejected")
	expect(rules.plan_step(Vector2i.LEFT).is_empty(), "Solved board locks movement")
	expect(rules.undo() and not rules.is_solved(), "Undo restores goal status")
	expect(rules.player_cell == Vector2i(1, 2) and rules.box_cells == [Vector2i(2, 2)], "Undo restores both bodies")
	expect(rules.steps == 2 and rules.pushes == 0, "Undo adds a step while restoring board pushes")
	expect(not rules.undo() and rules.steps == 2, "Empty undo does not charge a step")
	expect(rules.commit_step(rules.plan_step(Vector2i.RIGHT)) and rules.steps == 3, "Move after undo keeps cumulative score")
	expect(rules.undo() and rules.steps == 4, "Repeated undo cannot reduce score")
	rules.configure(floor_tiles, [Vector2i(4, 2), Vector2i(4, 3)], Vector2i(1, 2), [Vector2i(2, 2), Vector2i(3, 2)])
	expect(rules.plan_step(Vector2i.RIGHT).is_empty(), "Cannot push two boxes")
	floor_tiles.erase(Vector2i(3, 2))
	rules.configure(floor_tiles, [Vector2i(4, 2)], Vector2i(1, 2), [Vector2i(2, 2)])
	expect(rules.plan_step(Vector2i.RIGHT).is_empty(), "Box cannot enter wall")
	expect(rules.history.is_empty(), "Blocked movement creates no history")
	rules.configure(floor_tiles, [Vector2i(1, 0)], Vector2i.ZERO, [Vector2i(2, 2)])
	expect(rules.plan_step(Vector2i.UP).is_empty(), "Cannot leave board")
	expect(rules.commit_step(rules.plan_step(Vector2i.RIGHT)), "Player can stand on empty goal")
	expect(not rules.is_solved(), "Player on goal is not completion")
	expect(rules.box_cells == [Vector2i(2, 2)], "Walking does not pull boxes")
	rules.restart()
	expect(rules.player_cell == Vector2i.ZERO and rules.steps == 0 and rules.history.is_empty(), "Restart restores initial state")

func _test_assets(level: LevelController) -> void:
	var player: CharacterBody2D = level.player
	for direction: Vector2i in BoardRules.DIRECTIONS:
		level.player.face_direction(direction)
		expect(level.player.sprite.texture == level.player.IDLE[direction], "Directional idle texture")
		for pushing: bool in [false, true]:
			level.player.begin_step(direction, pushing)
			var texture: Texture2D = level.player.sprite.texture
			expect(texture.get_size() == Vector2(384, 64), "Six-frame strip dimensions")
			expect(level.player.sprite.hframes == 6, "Sprite uses six frames")
			var image: Image = texture.get_image()
			expect(image.get_pixel(0, 0).a == 0.0, "Animation has real transparency")
			var distinct_frames: Dictionary = {}
			for frame_index: int in range(6):
				var frame_image: Image = image.get_region(Rect2i(frame_index * 64, 0, 64, 64))
				distinct_frames[hash(frame_image.get_data())] = true
			expect(distinct_frames.size() >= 4, "Animation changes limbs across frames")
			level.player.sample_step(0.5)
			expect(level.player.sprite.frame == 3, "Animation follows movement progress")
			level.player.finish_step()
	level.player.face_direction(Vector2i.DOWN)
	expect(player.collision_mask == 3, "Player sees walls and crates")

func _step(level: LevelController, direction: Vector2i) -> bool:
	var old_steps: int = level.board.steps
	var start: Vector2 = level.player.global_position
	var plan: Dictionary = level.board.plan_step(direction)
	var accepted: bool = level.try_step(direction)
	expect(accepted, "Solution move accepted: " + str(direction) + " at " + str(level.board.player_cell))
	if not accepted:
		if not plan.is_empty() and plan["box_index"] >= 0:
			var candidate: StaticBody2D = level.boxes[plan["box_index"]]
			var hit: KinematicCollision2D = KinematicCollision2D.new()
			var motion: Vector2 = Vector2(direction) * 64.0
			if candidate.test_move(candidate.global_transform, motion, hit):
				print("BOX_BLOCKED collider=", hit.get_collider(), " position=", hit.get_position(), " normal=", hit.get_normal(), " box=", candidate.global_position, " player=", level.player.global_position)
			level.player.add_collision_exception_with(candidate)
			if level.player.test_move(level.player.global_transform, motion, hit):
				print("PLAYER_BLOCKED collider=", hit.get_collider(), " position=", hit.get_position(), " normal=", hit.get_normal())
			level.player.remove_collision_exception_with(candidate)
		return false
	expect(not level.try_step(direction), "No overlapping move transactions")
	expect(level.player.animation_state == (&"push" if plan["box_index"] >= 0 else &"walk"), "Correct walking or pushing animation")
	await physics_frame
	await process_frame
	expect(level.busy, "Movement is not instant")
	var travelled: float = start.distance_to(level.player.global_position)
	expect(travelled > 0.0 and travelled < 64.0, "Intermediate movement position")
	if plan["box_index"] >= 0:
		var box: StaticBody2D = level.boxes[plan["box_index"]]
		var box_distance: float = level.cell_to_world(plan["box_from"]).distance_to(box.global_position)
		expect(is_equal_approx(travelled, box_distance), "Box and player move synchronously")
	var frame_count: int = 0
	while level.busy and frame_count < 240:
		await physics_frame
		frame_count += 1
	await process_frame
	expect(not level.busy and level.board.steps == old_steps + 1, "Step finishes and commits exactly once")
	expect(level.player.global_position.is_equal_approx(level.cell_to_world(level.board.player_cell)), "Player remains grid aligned")
	expect(level.player.get_collision_exceptions().is_empty(), "Temporary crate collision exception cleared")
	for index: int in range(level.boxes.size()):
		expect(level.boxes[index].global_position.is_equal_approx(level.cell_to_world(level.board.box_cells[index])), "Box remains grid aligned")
	return failures == 0

func _run() -> void:
	_test_rules()
	var level: LevelController = LEVEL.instantiate() as LevelController
	root.add_child(level)
	current_scene = level
	level.player.set_physics_process(false)
	level.puzzle_completed.connect(func() -> void: completion_count += 1)
	await physics_frame
	await physics_frame
	expect(level.tiles.get_used_cells().size() == 63, "Only three old wall tiles removed")
	expect(level.boxes.size() == 3 and level.goals.size() == 3, "Three boxes and three goals")
	expect(level.board.player_cell == Vector2i(10, 5), "Original player start retained")
	expect(level.board.box_cells == [Vector2i(8, 6), Vector2i(9, 6), Vector2i(13, 5)], "Exact screenshot box cells")
	for goal: Sprite2D in level.goals:
		expect(goal.get_child_count() == 0 and goal.get_class() == "Sprite2D", "Goals have no collision")
		var cell: Vector2i = level.world_to_cell(goal.global_position)
		expect(level.board.floor_cells.has(cell), "Goal belongs to traversable floor")
	_test_assets(level)
	expect(not level.try_step(Vector2i.RIGHT) and level.board.steps == 0, "Existing rock still blocks player")
	expect(level.player.facing == Vector2i.RIGHT, "Blocked movement still turns player")
	var extra_wall: StaticBody2D = StaticBody2D.new()
	var extra_shape: CollisionShape2D = CollisionShape2D.new()
	var rectangle: RectangleShape2D = RectangleShape2D.new()
	rectangle.size = Vector2(64, 64)
	extra_shape.shape = rectangle
	extra_shape.position = Vector2(32, 32)
	extra_wall.add_child(extra_shape)
	level.add_child(extra_wall)
	extra_wall.global_position = level.cell_to_world(Vector2i(10, 6))
	await physics_frame
	await physics_frame
	expect(not level.try_step(Vector2i.DOWN), "Physical sweep blocks a non-tile obstacle")
	extra_wall.queue_free()
	await physics_frame
	await physics_frame
	for letter: String in SOLUTION:
		if not await _step(level, DIRECTIONS[letter]):
			break
	expect(level.board.is_solved(), "Exact screenshot layout is solvable")
	expect(level.board.steps == 39 and level.board.pushes == 11, "Full route: 39 moves and 11 pushes")
	expect(completion_count == 1, "Completion emitted exactly once")
	expect(level.player.input_locked, "Movement locked after completion")
	for box: StaticBody2D in level.boxes:
		var sprite: Sprite2D = box.get_node("Sprite2D") as Sprite2D
		expect(sprite.texture == level.CRATE_COMPLETE, "Box changes texture on goal")
	level.undo_move()
	expect(not level.board.is_solved() and not level.player.input_locked, "Undo can leave completed state")
	expect(level.board.steps == 40 and level.board.pushes == 10, "Undo after completion adds one scored step")
	if failures == 0:
		await _step(level, Vector2i.DOWN)
		expect(level.board.steps == 41, "Completing again includes undo and replay cost")
		expect(completion_count == 2, "Completing again emits a new event")
	level.restart_level()
	expect(level.board.steps == 0 and level.board.pushes == 0 and not level.board.is_solved(), "Restart after winning")
	level.try_step(Vector2i.LEFT)
	await physics_frame
	level.restart_level()
	expect(not level.busy and level.player.global_position == level.cell_to_world(Vector2i(10, 5)), "Restart cancels in-flight movement")
	expect(level.player.get_collision_exceptions().is_empty(), "Restart cleans collision exceptions")
	level.player.set_physics_process(true)
	Input.action_press("ui_down")
	for index: int in range(35):
		await physics_frame
	Input.action_release("ui_down")
	while level.busy:
		await physics_frame
	expect(level.board.steps >= 2, "Held input moves continuously")
	expect(level.board.player_cell.x == 10, "Held input stays cardinal")
	level.restart_level()
	print("SOKOBAN_TEST_RESULT checks=%d failures=%d physics_hz=%d" % [checks, failures, Engine.physics_ticks_per_second])
	level.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
