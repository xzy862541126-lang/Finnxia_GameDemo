extends SceneTree

const Rules = preload("res://garden_board.gd")
const Chapter = preload("res://garden_chapter.gd")
const Campaign = preload("res://campaign.gd")
const Store = preload("res://save_store.gd")
const Level = preload("res://level.gd")
const APP: PackedScene = preload("res://campaign.tscn")
const DIRS: Dictionary[String, Vector2i] = {"U": Vector2i.UP, "R": Vector2i.RIGHT, "D": Vector2i.DOWN, "L": Vector2i.LEFT}
var failures: int = 0
var checks: int = 0
var game: Campaign
var isolated_path: String
var capture_dir: String = ""

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			capture_dir = arg.trim_prefix("--capture-dir=")
	_run.call_deferred()

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("GARDEN_TEST: " + message)

func board_for(definition: Dictionary) -> Rules:
	var floor_tiles: Array[Vector2i] = []
	var rows: Array = definition["rows"]
	for y: int in range(rows.size()):
		for x: int in range(str(rows[y]).length()):
			if str(rows[y])[x] != "#":
				floor_tiles.append(Vector2i(x, y))
	var cargo: Array[Vector2i] = []
	var goals: Array[Vector2i] = []
	cargo.assign(definition["boxes"])
	goals.assign(definition["goals"])
	var board: Rules = Rules.new()
	board.configure(floor_tiles, goals, definition["player"], cargo)
	board.configure_mechanisms(definition)
	return board

func snapshot(board: Rules) -> Array:
	return [board.player_cell, board.box_cells.duplicate(), board.blooms.duplicate(), board.bridges.duplicate(), board.consumed.duplicate()]

func apply_snapshot(board: Rules, saved: Array) -> void:
	board.player_cell = saved[0]
	board.box_cells.assign(saved[1])
	board.blooms.assign(saved[2])
	board.bridges.assign(saved[3])
	board.consumed.assign(saved[4])
	board.steps = 0
	board.pushes = 0
	board.history.clear()

func solve(definition: Dictionary) -> String:
	var board: Rules = board_for(definition)
	var queue: Array[Array] = [[snapshot(board), ""]]
	var seen: Dictionary = {var_to_str(queue[0][0]): true}
	var cursor: int = 0
	var began: int = Time.get_ticks_msec()
	while cursor < queue.size() and seen.size() < 25000 and Time.get_ticks_msec() - began < 15000:
		var state: Array = queue[cursor][0]
		var route: String = queue[cursor][1]
		cursor += 1
		apply_snapshot(board, state)
		if board.is_solved():
			print("GARDEN_SOLVER title=%s steps=%d states=%d route=%s" % [definition["title"], route.length(), seen.size(), route])
			return route
		for letter: String in DIRS:
			apply_snapshot(board, state)
			if not board.commit_step(board.plan_step(DIRS[letter])):
				continue
			var next: Array = snapshot(board)
			var key: String = var_to_str(next)
			if not seen.has(key):
				seen[key] = true
				queue.append([next, route + letter])
	expect(false, "Solver blocked or state/time limit exceeded")
	return ""

func test_rules() -> void:
	var definition: Dictionary = Chapter.entries()[0]
	var board: Rules = board_for(definition)
	var flower: Vector2i = definition["flowers"][0]["cell"]
	var gate: Vector2i = definition["flowers"][0]["gates"][0]
	expect(board.gate_closed(gate), "Gate begins closed")
	var first: Dictionary = board.plan_step(Vector2i.RIGHT)
	expect(board.blooms.is_empty(), "Plan does not bloom or mutate state")
	expect(board.commit_step(first), "Push cargo onto flower")
	expect(board.blooms.has(flower) and not board.gate_closed(gate), "Cargo blooms flower and opens linked gate")
	expect(not board.commit_step(first), "Old transaction cannot commit twice")
	expect(board.commit_step(board.plan_step(Vector2i.RIGHT)), "Push cargo off flower through gate")
	expect(not board.gate_closed(gate), "Moving cargo away does not close gate")
	expect(board.undo() and board.blooms.has(flower), "Undo later move retains earlier activation")
	expect(board.undo() and board.gate_closed(gate) and board.steps == 4, "Undo triggering move restores gate and adds score")
	expect(not board.undo() and board.steps == 4, "Empty undo does not charge")
	board.restart()
	expect(board.steps == 0 and board.blooms.is_empty(), "Restart resets flower state")
	var bridge_def: Dictionary = Chapter.entries()[1]
	board = board_for(bridge_def)
	expect(board.commit_step(board.plan_step(Vector2i.RIGHT)), "Walk towards bridge supply")
	var water: Vector2i = bridge_def["water"][0]
	expect(not board.walkable(water), "Water blocks player before bridge")
	expect(board.commit_step(board.plan_step(Vector2i.RIGHT)), "Push timber into water")
	expect(board.consumed.has(1) and board.bridges.has(water), "Timber consumed and bridge constructed atomically")
	expect(board.box_at(water) == -1 and board.walkable(water), "Bridge is floor, not an occupying crate")
	expect(board.completed_goals() == 0 and not board.is_solved(), "Bridge material never counts as delivery")
	expect(board.commit_step(board.plan_step(Vector2i.RIGHT)) and board.player_cell == water, "Player can cross new bridge")
	board.undo()
	board.undo()
	expect(board.bridges.is_empty() and board.consumed.is_empty() and not board.walkable(water), "Undo bridge restores timber and water")
	board.timber_indices.clear()
	expect(board.plan_step(Vector2i.RIGHT).is_empty(), "Ordinary cargo cannot fall into water")
	board = board_for(bridge_def)
	board.box_cells[1] = bridge_def["goals"][0]
	expect(board.completed_goals() == 0, "Material on goal does not satisfy goal")
	board = board_for(definition)
	board.timber_indices[0] = true
	board.commit_step(board.plan_step(Vector2i.RIGHT))
	expect(board.blooms.is_empty(), "Only delivery cargo activates flower")

func find_button(parent: Node, text: String) -> Button:
	for child: Node in parent.get_children():
		if child is Button and (child as Button).text.contains(text):
			return child as Button
		var found: Button = find_button(child, text)
		if found != null:
			return found
	return null

func click(text: String) -> void:
	var button: Button = find_button(game.ui, text)
	expect(button != null and not button.disabled, "Clickable button " + text)
	if button != null and not button.disabled:
		button.pressed.emit()
	await process_frame
	await process_frame

func capture(filename: String) -> void:
	if capture_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(capture_dir.path_join(filename)) == OK, "Capture " + filename)

func step(letter: String) -> bool:
	var before: int = game.level.board.steps
	var accepted: bool = game.level.try_step(DIRS[letter])
	expect(accepted, "Physical move accepted " + letter + " at " + str(game.level.board.player_cell))
	if not accepted:
		return false
	var frames: int = 0
	while game.level.busy and frames < 120:
		await physics_frame
		frames += 1
	await process_frame
	expect(not game.level.busy and game.level.board.steps == before + 1, "Physical step commits once")
	var board: Rules = game.level.board as Rules
	for index: int in range(game.level.boxes.size()):
		var box: StaticBody2D = game.level.boxes[index]
		expect(box.visible == not board.consumed.has(index), "Consumed timber hidden; other boxes visible")
		expect(box.collision_layer == (0 if board.consumed.has(index) else 2), "Consumption and collision agree")
		expect(box.get_collision_exceptions().is_empty(), "No leaked bridge or player collision exception")
	for cell: Vector2i in game.level.mechanism_view.barriers:
		var body: StaticBody2D = game.level.mechanism_view.barriers[cell]
		expect(body.collision_layer == (0 if board.walkable(cell) else 1), "Physical gate/water matches logical state")
	return failures == 0

func persist_and_resume() -> void:
	var expected: Array = snapshot(game.level.board)
	var total: int = game.level.board.steps
	var active: Dictionary = game.level.capture_state()
	game.manual_save()
	var disk: Store = Store.new()
	disk.path = game.garden_store.path
	disk.level_count = 3
	expect(disk.load_save(), "Repair save reads from disk")
	expect(disk.data["active"] == JSON.parse_string(JSON.stringify(active)), "Repair action log persists")
	game.show_menu()
	expect(not game.garden_mode and game.store == game.classic_store, "Returning home restores classic context")
	await click("花园修复篇")
	await click("继续修复存档")
	game.level.player.set_physics_process(false)
	game.level.player.walk_duration = 0.05
	game.level.player.push_duration = 0.07
	expect(snapshot(game.level.board) == expected, "Reload reproduces flowers gates bridges and consumed timber")
	expect(game.level.board.steps == total, "Reload preserves cumulative score")
	await physics_frame
	await physics_frame

func _run() -> void:
	test_rules()
	var solutions: Array[String] = []
	for entry: Dictionary in Chapter.entries():
		var route: String = solve(entry)
		expect(not route.is_empty() and route.length() == str(entry["solution"]).length(), "Authored route matches shortest length")
		solutions.append(route)
	isolated_path = "user://garden_mechanism_test_%d.json" % Time.get_ticks_usec()
	game = APP.instantiate() as Campaign
	game.save_path = isolated_path
	root.add_child(game)
	current_scene = game
	await process_frame
	game.start_new_game()
	game.level.player.set_physics_process(false)
	game.manual_save()
	game.show_menu()
	var classic_before: PackedByteArray = FileAccess.get_file_as_bytes(isolated_path)
	await click("花园修复篇")
	expect(game.garden_mode and game.entries.size() == 3, "Separate three-stage chapter")
	await capture("01_chapter.png")
	await click("开始修复")
	for level_index: int in range(3):
		expect(game.current_index == level_index and game.level.board is Rules, "Correct chapter rules")
		game.level.player.set_physics_process(false)
		game.level.player.walk_duration = 0.05
		game.level.player.push_duration = 0.07
		await physics_frame
		await physics_frame
		await capture("level_%d_before.png" % level_index)
		if level_index == 1:
			await step("R")
			expect(game.level.try_step(Vector2i.RIGHT), "Begin construction movement")
			await physics_frame
			game.show_pause()
			var paused_board: Rules = game.level.board as Rules
			expect(not game.level.busy and paused_board.bridges.is_empty() and paused_board.consumed.is_empty(), "Pause rolls back incomplete construction")
			expect(paused_board.steps == 1, "Half-step construction is not scored")
			for box: StaticBody2D in game.level.boxes:
				expect(box.get_collision_exceptions().is_empty(), "Pause clears temporary water exception")
			game.close_modal()
			game.level.restart_level()
			await physics_frame
			await physics_frame
		var exercised: bool = false
		var replay: String = solutions[level_index]
		for letter: String in replay:
			if not await step(letter):
				break
			var board: Rules = game.level.board as Rules
			var event_happened: bool = not board.blooms.is_empty() if level_index == 0 else not board.bridges.is_empty()
			if event_happened and not exercised and not board.is_solved():
				exercised = true
				await capture("level_%d_activated.png" % level_index)
				await persist_and_resume()
				var score: int = game.level.board.steps
				game.level.undo_move()
				expect(game.level.board.steps == score + 1, "Mechanism undo adds one scored step")
				var reverted: Rules = game.level.board as Rules
				if level_index == 0:
					expect(reverted.blooms.is_empty(), "Undo activation after reload closes gate")
				else:
					expect(reverted.bridges.is_empty() and reverted.consumed.is_empty(), "Undo construction after reload restores timber")
				await step(letter)
				await capture("level_%d_restored.png" % level_index)
		for index: int in range(4):
			await process_frame
		expect(exercised and game.level.board.is_solved(), "Chapter level solved with undo and resume")
		expect(game.modal_kind == "win", "Win modal after cargo delivered")
		expect(game.garden_store.data["completed"].size() == level_index + 1, "Repair progress saved once")
		print("GARDEN_LEVEL_PASS level=%d score=%d" % [level_index + 1, game.level.board.steps])
		if failures > 0:
			break
		if level_index < 2:
			await click("下一关")
	if failures == 0:
		await click("查看胜利纪念")
		expect(game.screen == "garden_ending", "Separate repair ending")
		await capture("02_ending.png")
		await click("返回主页")
		expect(game.menu_art.revival_stage == 3, "All three visual restoration rewards shown")
		await capture("03_revived_home.png")
		expect(FileAccess.get_file_as_bytes(isolated_path) == classic_before, "Standard save remained byte-for-byte unchanged")
		game.queue_free()
		await process_frame
		game = APP.instantiate() as Campaign
		game.save_path = isolated_path
		root.add_child(game)
		current_scene = game
		await process_frame
		expect(game.menu_art.revival_stage == 3 and game.classic_store.data["current"] == 0, "Revival persists across application restart")
		await click("花园修复篇")
		await click("继续修复存档")
		expect(game.screen == "garden_ending", "Completed repair save returns to repair ending")
	game.queue_free()
	await process_frame
	await process_frame
	for prefix: String in [isolated_path, isolated_path + ".restoration"]:
		for suffix: String in ["", ".bak", ".new", ".damaged"]:
			var filename: String = ProjectSettings.globalize_path(prefix + suffix)
			if FileAccess.file_exists(filename):
				DirAccess.remove_absolute(filename)
	print("GARDEN_TEST_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
