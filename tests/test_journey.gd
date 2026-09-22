extends SceneTree

const App = preload("res://journey.gd")
const Level = preload("res://journey_level.gd")
const Catalog = preload("res://journey_catalog.gd")
const Store = preload("res://journey_save.gd")
var game: App
var failures: int = 0
var checks: int = 0
var capture_dir: String = ""
var path: String
const DIR: Dictionary = {"U": Vector2i.UP, "D": Vector2i.DOWN, "L": Vector2i.LEFT, "R": Vector2i.RIGHT}

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): capture_dir = arg.trim_prefix("--capture-dir=")
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("JOURNEY_TEST " + label)

func find_button(node: Node, value: String) -> Button:
	if node is Button and node.text.contains(value): return node
	for child: Node in node.get_children():
		var result: Button = find_button(child, value)
		if result != null: return result
	return null

func click(b: Button) -> void:
	check(b != null and not b.disabled, "Button exists and enabled")
	if b == null: return
	var at: Vector2 = b.get_global_rect().get_center()
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = at
	root.push_input(motion, true)
	await process_frame
	for pressed: bool in [true, false]:
		var e: InputEventMouseButton = InputEventMouseButton.new()
		e.position = at
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(e, true)
		await process_frame
	await process_frame

func tick(seconds: float) -> void:
	for i: int in range(int(ceil(seconds * 60.0))):
		game.level._physics_process(1.0 / 60.0)

func walk(route: String) -> bool:
	for key: String in route:
		if not game.level.try_step(DIR[key]):
			check(false, "Rejected level=%s at=%s dir=%s" % [game.level.definition["id"], game.level.hero["cell"], key])
			return false
		tick(0.3)
		if game.level.dead:
			check(false, "Reference route died")
			return false
	return true

func wait_enemy(index: int, at: Vector2i) -> bool:
	for i: int in range(1200):
		var e: Dictionary = game.level.room()["enemies"][index]
		if not game.level.moving(e) and e["cell"] == at: return true
		tick(1.0 / 60.0)
	return false

func capture(name: String) -> void:
	if capture_dir.is_empty(): return
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(capture_dir.path_join(name + ".png"))

func flush() -> void:
	await process_frame
	await process_frame
	await process_frame

func setup_level() -> void:
	game.level.set_physics_process(false)
	game.level.release_input = false
	game.level.paused = false
	if game.level.guide.is_open(): game.level.guide.close_guide()

func normalize_npc_waits(data: Dictionary) -> void:
	for s: Dictionary in [data["state"]] + data["history"]:
		for dyn: Dictionary in s["dynamic"]:
			for e: Dictionary in dyn["enemies"]:
				e["wait"] = maxf(float(e["wait"]), 0.6)
			if not dyn["cat"].is_empty():
				dyn["cat"]["wait"] = maxf(float(dyn["cat"]["wait"]), 1.0)

func persist_restore() -> void:
	var before: Dictionary = game.level.capture_state()
	normalize_npc_waits(before)
	check(game.save_active(), "Save full world and history")
	var disk: Store = Store.new()
	disk.path = path
	check(disk.load_save(), "Read independent binary save")
	normalize_npc_waits(disk.data["active"])
	check(disk.data["active"] == before, "Vectors, mechanism and NPC timers roundtrip")
	var clone: Level = Level.new()
	clone.definition = game.level.definition
	clone.tutorials_enabled = false
	root.add_child(clone)
	clone.set_physics_process(false)
	check(clone.restore_state(disk.data["active"]), "Valid snapshot restores")
	check(clone.capture_state() == before, "Restored full state exactly matches @%s" % game.level.definition["id"])
	if not before["history"].is_empty():
		check(clone.undo(), "Undo remains available after reload")
	var malformed: Dictionary = before.duplicate(true)
	malformed["state"]["hero"]["duration"] = 0.0
	check(not clone.restore_state(malformed), "Reject invalid interpolation duration")
	clone.free()

func all_text(node: Node) -> String:
	var value: String = node.text if node is Label else ""
	for child: Node in node.get_children(): value += all_text(child)
	return value

func compare_original(index: int) -> void:
	var classic: Node2D = Catalog.Classic.create_level(index)
	root.add_child(classic)
	classic.player.set_physics_process(false)
	var r: Dictionary = game.level.rooms[0]
	var expected_floor: Dictionary = classic.board.floor_cells.duplicate()
	if r["floor"].has(Vector2i(11, 8)): expected_floor[Vector2i(11, 8)] = true
	check(r["floor"] == expected_floor, "Original walkable layout preserved, plus the filled cell under the cat")
	check(r["goals"] == classic.board.goal_cells.keys(), "Original goal positions and count retained")
	var cargo: Array[Vector2i] = []
	var timber: int = 0
	for b: Dictionary in r["boxes"]:
		if b["timber"]: timber += 1
		else: cargo.append(b["cell"])
		check(not b.get("tool", false), "No battle-tool filler boxes in main puzzle")
	check(cargo == classic.board.box_cells, "All original delivery boxes preserved in order")
	check(cargo.size() == r["goals"].size(), "Exactly one delivery box per goal")
	check(timber == r["water"].size(), "Exactly one marked timber for every repair objective")
	var mapping: Dictionary = {}
	for c: Vector2i in classic.tiles.get_used_cells(): mapping[c] = classic.tiles.get_cell_source_id(c)
	if not r["render_tiles"].has(Vector2i(11, 8)): mapping.erase(Vector2i(11, 8))
	check(mapping == r["render_tiles"], "Original boundary preserved except removed sacks")
	check(game.level.hero["cell"] == classic.board.player_cell, "Original starting position preserved")
	for f: Dictionary in r["flowers"]:
		check(r["goals"].has(f["gates"][0]), "Flower opens a required delivery goal, not an irrelevant prop")
	classic.free()

func hidden_run(advanced: bool = false) -> bool:
	var main_before: Dictionary = game.level.room().duplicate(true)
	var portal: Vector2i = game.level.room()["portal"]
	while game.level.hero["cell"].x < portal.x:
		if not walk("R"): return false
	while game.level.hero["cell"].y < portal.y:
		if not walk("D"): return false
	game.level.interact()
	if game.level.guide.is_open(): game.level.guide.close_guide()
	check(game.level.room_index == 1, "Portal enters compact hidden puzzle")
	check(game.level.room()["size"] == Vector2i(13, 9), "Hidden room has compact designed bounds")
	check(game.level.solid(Vector2i(6, 2)) and game.level.solid(Vector2i(9, 6)), "Both combat gates initially block access")
	for b: Dictionary in game.level.room()["boxes"]: check(b["tool"], "Hidden boxes visibly classified as tools")
	await capture("hidden_advanced" if advanced else "hidden_compact")
	if not walk("DD"): return false
	if not wait_enemy(0, Vector2i(4, 4)): return false
	check(walk("R"), "Push tool box into crush-wall lane")
	check(not game.level.room()["enemies"][0]["alive"] and not game.level.solid(Vector2i(6, 2)), "Crushing small enemy opens only first gate")
	check(game.level.undo(), "Crush action can be undone")
	check(game.level.room()["enemies"][0]["alive"] and game.level.solid(Vector2i(6, 2)), "Undo restores enemy and its locked gate")
	check(not game.level.paused, "Undo does not pause active gameplay")
	check(walk("R"), "Move immediately after undo without Space")
	if not walk("UURRRR" + ("D" if advanced else "DD")): return false
	check(wait_enemy(1, Vector2i(9, 3 if advanced else 4)), "Wait for boss patrol at intended water lane")
	if not walk("R"): return false
	check(not game.level.room()["enemies"][1]["alive"] and not game.level.solid(Vector2i(9, 6)), "Drowning boss unlocks chest chamber")
	check(game.level.room()["boxes"][0]["cell"] == Vector2i(4, 4), "First tool has performed its only intended job")
	if not walk("DD" if advanced else "D"): return false
	if not walk("RDD"): return false
	game.level.interact()
	check(game.level.guide.is_open() and game.level.guide.pages.has("relic"), "Chest pickup popup shows every time, even if seen before")
	if game.level.guide.is_open(): game.level.guide.close_guide()
	check(game.level.relic and game.level.room()["chest_open"], "Clear both encounters and obtain relic")
	await persist_restore()
	if not walk("UULUUU" + "L".repeat(6)): return false
	game.level.interact()
	check(game.level.room_index == 0 and game.level.relic, "Return with relic")
	while game.level.hero["cell"].y > Vector2i(game.level.definition["start"]).y:
		if not walk("U"): return false
	while game.level.hero["cell"] != Vector2i(game.level.definition["start"]):
		if not walk("L"): return false
	main_before["return"] = game.level.room()["return"]
	main_before.erase("cat")
	var main_now: Dictionary = game.level.room().duplicate(true)
	main_now.erase("cat")
	check(main_now == main_before, "Hidden excursion does not rearrange original main puzzle")
	return true

func verify_cat_undo() -> void:
	game.discard_level()
	game.load_definition(5)
	setup_level()
	var cat: Dictionary = game.level.room()["cat"]
	check(not cat.is_empty() and cat.has("patrol_cells"), "Level six keeps a designed cat route")
	var before: Vector2i = cat["cell"]
	cat["wait"] = 0.0
	tick(0.01)
	check(game.level.undo(), "Cat action is undoable")
	check(game.level.room()["cat"]["cell"] == before, "Z restores cat to previous cell")
	check(float(game.level.room()["cat"]["wait"]) > 0.0, "Restored cat still waits before acting")
	tick(1.5)
	check(game.level.room()["cat"]["cell"] != before, "Cat resumes its own patrol after undo")
	check(walk("D"), "Player still moves after undoing a cat action")
	check(game.level.undo(), "Second consecutive undo still works")
	await flush()

func verify_continue_resume() -> void:
	game.discard_level()
	game.load_definition(0)
	setup_level()
	var start: Vector2i = game.level.hero["cell"]
	check(walk("D"), "Make progress before saving")
	game.save_active()
	game.show_menu(false)
	check(game.screen == "menu", "Back to the main menu")
	await click(find_button(game.ui, "继续旅程"))
	check(game.level != null and not game.level.paused, "Continue resumes without forced pause")
	check(game.level.hero["cell"] == start + Vector2i.DOWN, "Continue restores the saved position")
	check(walk("D"), "Hero is controllable right after continue, no R needed")
	await flush()

func verify_undo_input() -> void:
	setup_level()
	var start: Vector2i = game.level.hero["cell"]
	check(walk("D"), "Prepare undo")
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_Z
	key.pressed = true
	root.push_input(key, true)
	await flush()
	check(not game.level.paused, "Z keeps world running")
	tick(0.05)
	Input.action_press("ui_down")
	tick(1.0 / 60.0)
	Input.action_release("ui_down")
	tick(0.3)
	check(game.level.hero["cell"] == start + Vector2i.DOWN, "Direction works after Z without Space")

func _run() -> void:
	path = "user://original_nine_test_%d.save" % Time.get_ticks_usec()
	var baseline_files: Array[String] = ["res://campaign_catalog.gd", "res://campaign_levels.json", "res://level_1.tscn", "res://tests/difficulty_report.json"]
	var hashes: Dictionary = {}
	for file: String in baseline_files: hashes[file] = FileAccess.get_sha256(file)
	game = load("res://journey.tscn").instantiate()
	game.save_path = path
	root.add_child(game)
	current_scene = game
	await flush()
	var Grade = load("res://rank_badge.gd")
	for sample: Array in [[20, "S"], [21, "A"], [25, "A"], [26, "B"], [32, "B"], [33, "C"], [40, "C"], [41, "D"]]:
		check(Grade.grade(sample[0], 20) == sample[1], "SABCD threshold " + sample[1])
	check(game.definitions.size() == 9, "Nine original stages")
	var references: Array[int] = [2, 11, 26, 39, 86, 116, 125, 133, 188]
	var minimum_pushes: Array[int] = [2, 5, 7, 11, 27, 31, 33, 35, 49]
	await capture("menu")
	await click(find_button(game.ui, "开始游戏"))
	check(game.level.guide.is_open(), "New-run tutorial opens")
	await click(game.level.guide.next_button)
	check(game.level.guide.next_button.disabled, "Last tutorial page is disabled")
	await click(game.level.guide.close_button)
	game.tutorials_enabled = false
	await verify_undo_input()
	await verify_cat_undo()
	await verify_continue_resume()
	game.load_level(0)
	for index: int in range(9):
		setup_level()
		compare_original(index)
		var d: Dictionary = game.level.definition
		check(d["title"].ends_with(Catalog.Classic.entries()[index]["title"]), "Original stage name and order")
		check(d["reference"] == references[index], "Keep full original reference route")
		check(d["difficulty_metrics"]["minimum_pushes"] == minimum_pushes[index], "Retain original verified puzzle complexity baseline")
		if index in [0, 2, 3, 4, 6, 8]: await capture("level_%02d" % (index + 1))
		if index == 6:
			if not await hidden_run():
				check(false, "Hidden encounter route failed")
				break
		var exercised: bool = false
		for letter: String in d["solution"]:
			if not walk(letter): break
			if not exercised and not game.level.finished and (not game.level.room()["blooms"].is_empty() or not game.level.room()["bridges"].is_empty()):
				exercised = true
				await persist_restore()
		check(game.level.finished, "All original cargo delivered and repairs finished")
		check(game.level.room()["water"].size() == game.level.room()["bridges"].size(), "Every extra timber actually built its bridge")
		for b: Dictionary in game.level.room()["boxes"]:
			if b["timber"]: check(b["used"], "No useless leftover material box")
			else: check(game.level.room()["goals"].has(b["cell"]), "No leftover ordinary cargo box")
		await flush()
		check(game.modal_kind == "win", "Winning dialog")
		var labels: String = all_text(game.modal)
		check(labels.contains("共用 %d 步，参考 %d 步" % [game.level.steps, d["reference"]]), "Plain step summary")
		check(labels.contains("隐藏探索") == (index == 6), "No hidden exploration text on ordinary stages")
		var badge: Control = game.modal.find_child("RankBadge", true, false)
		check(badge != null and badge.rank == Grade.grade(game.level.steps, d["reference"]), "Real pixel grade badge in results")
		if index == 0:
			for grade: String in ["S", "A", "B", "C", "D"]:
				badge.rank = grade
				await capture("grade_" + grade)
		if index == 8: await capture("final_win")
		print("ORIGINAL_STAGE_PASS level=%d cargo=%d steps=%d" % [index + 1, game.level.room()["goals"].size(), game.level.steps])
		if failures > 0: break
		await click(find_button(game.ui, "查看总成绩" if index == 8 else "下一关"))
	if failures == 0:
		check(game.screen == "ending", "Full nine-stage conclusion")
		await capture("ending")
		await click(find_button(game.ui, "返回主菜单"))
		await click(find_button(game.ui, "重新游玩"))
		await click(find_button(game.ui, "取消"))
		check(game.store.data["completed"].size() == 9, "Cancel keeps all progress")
		game.store.data["relic"] = false
		for index: int in [6, 7, 8]:
			game.load_level(index)
			setup_level()
			check(walk(game.definitions[index]["solution"]), "Late original puzzle works without relic or hidden excursion")
			check(game.level.finished, "No hidden reward required")
			await flush()
			check(not all_text(game.modal).contains("隐藏探索"), "Unvisited hidden room does not add a zero-step result line")
			check(not game.level.status_label.text.contains("探索"), "Main HUD hides zero-step exploration")
		game.load_level(8)
		setup_level()
		var r: Dictionary = game.level.room()
		var cargo_index: int = 0
		for b: Dictionary in r["boxes"]:
			if b["timber"]: continue
			b["cell"] = r["goals"][cargo_index]
			b["from"] = b["cell"]
			cargo_index += 1
		game.level._check_win()
		check(not game.level.finished, "Deliveries alone do not bypass the required bridge repair")
		for w: Vector2i in r["water"]: r["bridges"][w] = true
		r["boxes"].append(Catalog.actor(r["start"]))
		game.level._check_win()
		check(not game.level.finished, "Extra unmatched ordinary crate is never accepted as a win")
	for file: String in baseline_files: check(hashes[file] == FileAccess.get_sha256(file), "Original asset untouched: " + file)
	game.free()
	await flush()
	for suffix: String in ["", ".new", ".bak", ".damaged"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	print("ORIGINAL_NINE_TEST_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
