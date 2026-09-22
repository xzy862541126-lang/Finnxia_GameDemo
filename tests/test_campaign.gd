extends SceneTree

const CampaignController = preload("res://campaign.gd")
const Catalog = preload("res://campaign_catalog.gd")
const SaveStore = preload("res://save_store.gd")
const CAMPAIGN: PackedScene = preload("res://campaign.tscn")
const DIRECTIONS: Dictionary[String, Vector2i] = {"U": Vector2i.UP, "D": Vector2i.DOWN, "L": Vector2i.LEFT, "R": Vector2i.RIGHT}
var failures: int = 0
var checks: int = 0
var game: CampaignController
var test_path: String
var capture_dir: String = ""

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			capture_dir = argument.trim_prefix("--capture-dir=")
	_run.call_deferred()

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("CAMPAIGN_TEST: " + message)

func _find_button(parent: Node, text: String) -> Button:
	for child: Node in parent.get_children():
		if child is Button and (child as Button).text.contains(text):
			return child as Button
		var nested: Button = _find_button(child, text)
		if nested != null:
			return nested
	return null

func _click(text: String) -> void:
	var button: Button = _find_button(game.ui, text)
	expect(button != null and not button.disabled, "Enabled UI button: " + text)
	if button != null and not button.disabled:
		button.pressed.emit()
	await process_frame
	await process_frame

func _capture(filename: String) -> void:
	if capture_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	expect(image.save_png(capture_dir.path_join(filename)) == OK, "Capture " + filename)

func _step(letter: String) -> bool:
	var level: Node = game.level
	var before: int = level.board.steps
	if not level.try_step(DIRECTIONS[letter]):
		expect(false, "Move rejected on level %d at %s direction %s" % [game.current_index + 1, level.board.player_cell, letter])
		return false
	var count: int = 0
	while level.busy and count < 60:
		await physics_frame
		count += 1
	await process_frame
	expect(level.board.steps == before + 1 and not level.busy, "Physical step committed exactly once")
	expect(level.player.global_position.is_equal_approx(level.cell_to_world(level.board.player_cell)), "Physical player aligned")
	for box: StaticBody2D in level.boxes:
		expect(box.get_collision_exceptions().is_empty(), "Crate exceptions cleared")
	return failures == 0

func _test_scenery(index: int, definition: Dictionary) -> void:
	var art: Node = game.level.get_node("GardenArt")
	var counts: Dictionary[int, int] = {}
	var left_edges: Dictionary[int, int] = {}
	for cell: Vector2i in game.level.tiles.get_used_cells():
		var source_id: int = game.level.tiles.get_cell_source_id(cell)
		counts[source_id] = counts.get(source_id, 0) + 1
		left_edges[cell.y] = mini(int(left_edges.get(cell.y, cell.x)), cell.x)
		if source_id >= 5:
			expect(art.obstacle_cells.has(cell), "Obstacle has continuous paving and contact shadow")
			expect(not art.wall_cells.has(cell), "Prop excluded from large wall shadows")
			expect(not game.level.board.floor_cells.has(cell), "Rendered prop remains an actual blocker")
	var different_edges: Dictionary = {}
	for edge: int in left_edges.values():
		different_edges[edge] = true
	expect(different_edges.size() >= 3, "Courtyard has a stepped non-rectangular outer silhouette")
	expect(art.obstacle_cells.size() >= 6, "Each courtyard has multiple interior and side-court props")
	if definition.get("original_scene", false):
		expect(index == 3, "Original first scene now appears fourth")
		expect(game.level.tiles.tile_set.get_source_count() == 7, "Theme resources do not mutate original shared TileSet")
		return
	var rows: Array = definition["rows"]
	var width: int = str(rows[0]).length()
	var offset: Vector2i = Vector2i(int((20 - width) / 2.0), maxi(1, int((12 - rows.size()) / 2.0)))
	var expected_floor: Dictionary[Vector2i, bool] = {}
	for y: int in range(rows.size()):
		for x: int in range(width):
			var cell: Vector2i = offset + Vector2i(x, y)
			if str(rows[y])[x] != "#":
				expected_floor[cell] = true
			elif x > 0 and x < width - 1 and y > 0 and y < rows.size() - 1:
				expect(game.level.tiles.get_cell_source_id(cell) >= 5, "Original interior wall becomes themed obstacle")
	expect(game.level.board.floor_cells == expected_floor, "Exact legacy walkable set unchanged, not just a matching count")
	var original_boxes: Array[Vector2i] = []
	for pair: Array in definition["boxes"]:
		original_boxes.append(offset + Vector2i(int(pair[0]), int(pair[1])))
	expect(game.level.board.box_cells == original_boxes, "Legacy box order and positions unchanged")
	var art_index: int = int(definition["art_index"])
	var landmark: int = [5, 20, 18, 19, 12, 13, 14, 16, 17][art_index]
	expect(counts.get(landmark, 0) > 0, "Scene contains the landmark promised by its name")
	if art_index == 2:
		expect(counts.get(18, 0) >= 2, "Double-arch corridor actually contains two arches")
	var prefix: String = str(definition["solution"]).substr(0, mini(8, str(definition["solution"]).length() - 1))
	expect(game.level.restore_state({"moves": prefix}), "Legacy action-sequence save still restores")
	expect(game.level.board.steps == prefix.length(), "Legacy saved move count retained")
	expect(game.level.capture_state() == {"moves": prefix, "total_steps": prefix.length()}, "Legacy history upgrades with inferred total steps")
	game.level.restart_level()

func _run() -> void:
	test_path = "user://campaign_test_%d.json" % Time.get_ticks_usec()
	expect(not FileAccess.file_exists(test_path), "Isolated test save path")
	game = CAMPAIGN.instantiate() as CampaignController
	game.save_path = test_path
	game.tutorials_enabled = false
	root.add_child(game)
	current_scene = game
	await process_frame
	expect(game.screen == "menu" and game.level == null, "Startup is main menu, not a level")
	expect(_find_button(game.ui, "继续游戏").disabled, "Continue disabled without save")
	expect(game.entries.size() == 9, "Original plus eight new levels")
	await _capture("01_menu.png")
	await _click("开始游戏")
	expect(game.screen == "playing" and game.current_index == 0, "Start button enters level one")
	await physics_frame
	await physics_frame
	await _capture("02_garden.png")
	game.level.player.set_physics_process(false)
	game.level.player.walk_duration = 0.04
	game.level.player.push_duration = 0.04
	var initial_player: Vector2i = game.level.board.player_cell
	var initial_boxes: Array[Vector2i] = game.level.board.box_cells.duplicate()
	expect(game.level.boxes.size() == 1, "First level teaches with just one box")
	expect(not game.level.restore_state({"moves": "UUUU"}), "Illegal snapshot rejected instead of walking through wall")
	expect(game.level.board.steps == 0, "Rejected snapshot leaves board untouched")
	game.show_pause()
	var paused_cell: Vector2i = game.level.board.player_cell
	Input.action_press("ui_left")
	for index: int in range(4):
		await physics_frame
	expect(not game.level.try_step(Vector2i.LEFT), "Modal locks direct move entry")
	game.level.restart_level()
	game.level.undo_move()
	expect(game.level.board.player_cell == paused_cell and game.level.suspended, "Modal locks undo and restart")
	game.close_modal()
	game.level.player.set_physics_process(true)
	for index: int in range(3):
		await physics_frame
	expect(game.level.board.player_cell == paused_cell, "Held direction cannot leak through closed modal")
	Input.action_release("ui_left")
	await physics_frame
	await physics_frame
	game.level.player.set_physics_process(false)
	await _step("D")
	var saved_snapshot: Dictionary = game.level.capture_state()
	game.manual_save()
	var disk_store: SaveStore = SaveStore.new()
	disk_store.path = test_path
	expect(disk_store.load_save(), "Real disk save reads back")
	expect(disk_store.data["active"] == JSON.parse_string(JSON.stringify(saved_snapshot)), "Disk snapshot retains movement and total steps")
	await _click("菜单")
	await _click("保存并返回主菜单")
	expect(game.screen == "menu" and game.level == null, "Pause returns to opening page")
	await _click("继续游戏")
	expect(game.level.board.steps == 1 and game.level.board.player_cell == initial_player + Vector2i.DOWN, "Continue restores exact tile and counters")
	expect(game.level.board.pushes == 1 and game.level.board.box_cells.has(initial_boxes[0] + Vector2i.DOWN), "Continue restores pushed crate")
	game.level.undo_move()
	expect(game.level.board.pushes == 0 and game.level.board.box_cells == initial_boxes, "Undo after reload restores pushed crate")
	expect(game.level.board.steps == 2 and game.level.board.player_cell == initial_player, "Undo restores position but charges one step")
	expect(game.level.capture_state() == {"moves": "", "total_steps": 2}, "Undo-to-start keeps total cost despite empty path")
	game.manual_save()
	expect(disk_store.load_save() and int(disk_store.data["active"]["total_steps"]) == 2, "Undo cost survives disk save")
	await _click("菜单")
	await _click("保存并返回主菜单")
	await _click("继续游戏")
	expect(game.level.board.steps == 2 and game.level.board.history.is_empty(), "Continue cannot erase undo cost")
	game.level.undo_move()
	expect(game.level.board.steps == 2, "Empty undo after reload does not add steps")
	game.level.player.set_physics_process(false)
	await physics_frame
	await physics_frame
	await _step("D")
	expect(game.level.board.steps == 3, "Next move continues cumulative score after reload")
	game.level.undo_move()
	expect(game.level.board.steps == 4, "Further undo increases score after reload")
	for invalid_total: Variant in [-1, 1.5, "2", null, INF, NAN, 2147483648]:
		expect(not game.level.restore_state({"moves": "", "total_steps": invalid_total}), "Invalid cumulative score rejected")
		var invalid_record: Dictionary = game.store.data.duplicate(true)
		invalid_record["active"] = {"moves": "", "total_steps": invalid_total}
		expect(not game.store._valid(invalid_record), "Invalid score rejected by save store")
	expect(not game.level.restore_state({"moves": "D", "total_steps": 0}), "Total cannot be less than replay length")
	expect(game.level.board.steps == 4, "Rejected snapshots do not change score")
	game.level.restart_level()
	expect(game.level.board.steps == 0, "Explicit restart resets cumulative score")
	var threshold: int = 0
	for level_index: int in range(9):
		expect(game.current_index == level_index, "Correct sequential level")
		var definition: Dictionary = game.entries[level_index]
		var metrics: Dictionary = definition["difficulty_metrics"]
		expect(int(metrics["minimum_pushes"]) > threshold, "Proven minimum pushes increase, not merely distance")
		threshold = int(metrics["minimum_pushes"])
		if level_index >= 4:
			expect(definition.get("added_obstacles", []).size() >= 4, "Late levels add real blocking props")
			expect(int(metrics["forced_extra_pushes"]) >= 4, "Late puzzles require detours beyond Manhattan distance")
		game.level.player.set_physics_process(false)
		game.level.player.walk_duration = 0.04
		game.level.player.push_duration = 0.04
		await physics_frame
		await physics_frame
		_test_scenery(level_index, definition)
		await _capture("level_%02d.png" % (level_index + 1))
		expect(game.level.boxes.size() == game.level.goals.size(), "Box-goal count matches")
		var map_bounds: Rect2i = game.level.tiles.get_used_rect()
		expect(map_bounds.position.y >= 1, "Board leaves room for top header")
		expect(map_bounds.end.y <= 11, "Board leaves room for bottom HUD")
		for letter: String in str(definition["solution"]):
			if not await _step(letter):
				break
		for frame_index: int in range(4):
			await process_frame
		expect(game.level.board.is_solved(), "Level %d physical replay solved" % (level_index + 1))
		expect(game.modal_kind == "win" and game.level.suspended, "Win dialog locks background")
		expect(game.store.data["completed"].has(str(level_index)), "Completion persisted")
		expect(int(game.store.data["unlocked"]) == mini(level_index + 2, 9), "Next level unlocks")
		if level_index == 0:
			await _capture("03_next_level.png")
		print("CAMPAIGN_LEVEL_PASS level=%d steps=%d pushes=%d" % [level_index + 1, game.level.board.steps, game.level.board.pushes])
		if failures > 0:
			break
		if level_index < 8:
			await _click("下一关")
	if failures == 0:
		await _click("查看胜利纪念")
		expect(game.screen == "ending" and game.level == null, "Final ending screen")
		expect(game.store.data["finished"] and game.store.data["completed"].size() == 9, "Campaign completed exactly nine levels")
		await _capture("04_ending.png")
		await _click("返回开局页面")
		expect(game.screen == "menu", "Ending returns to opening page")
		await _click("查看通关纪念")
		expect(game.screen == "ending", "Finished save reopens ending")
		await _click("返回开局页面")
		await _click("关卡手册")
		expect(game.screen == "select", "Level selection opens")
		await _capture("05_level_select.png")
		await _click("返回主菜单")
		var before_reset: Dictionary = game.store.data.duplicate(true)
		await _click("重新游玩")
		expect(game.modal_kind == "confirm_new", "Restart journey requires confirmation")
		await _click("取消")
		expect(game.store.data == before_reset, "Cancel preserves save")
		await _click("重新游玩")
		await _click("确认重新游玩")
		expect(game.current_index == 0 and int(game.store.data["unlocked"]) == 1 and game.store.data["completed"].is_empty(), "Confirmed new journey resets progress")
		game.level.set_modal(true)
		game.manual_save()
		var corrupt: FileAccess = FileAccess.open(test_path, FileAccess.WRITE)
		corrupt.store_string("{broken save")
		corrupt.close()
		var recovered_store: SaveStore = SaveStore.new()
		recovered_store.path = test_path
		expect(recovered_store.load_save() and recovered_store.recovered, "Corrupt primary recovers from backup")
		expect(recovered_store.write_save(), "Recovered save can be written safely")
		var final_store: SaveStore = SaveStore.new()
		final_store.path = test_path
		expect(final_store.load_save() and not final_store.recovered, "Recovered primary valid again")
		var invalid: Dictionary = final_store.data.duplicate(true)
		invalid["current"] = 999
		expect(not final_store._valid(invalid), "Invalid level index rejected")
		invalid = final_store.data.duplicate(true)
		invalid["active"] = {"moves": "DROP TABLE"}
		expect(not final_store._valid(invalid), "Invalid action data rejected")
	game.queue_free()
	await process_frame
	await process_frame
	for suffix: String in ["", ".bak", ".new", ".damaged"]:
		var absolute: String = ProjectSettings.globalize_path(test_path + suffix)
		if FileAccess.file_exists(absolute):
			DirAccess.remove_absolute(absolute)
	print("CAMPAIGN_TEST_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
