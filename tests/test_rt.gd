extends SceneTree

const RT = preload("res://rt_level.gd")
const Catalog = preload("res://campaign_catalog.gd")
const Campaign = preload("res://campaign.gd")
const Audio = preload("res://game_audio.gd")
var level: RT
var checks: int = 0
var failures: int = 0
var capture_dir: String = ""

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): capture_dir = arg.trim_prefix("--capture-dir=")
	_run.call_deferred()

func expect(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FEATURE_TEST: " + text)

func tick(seconds: float) -> void:
	for index: int in range(int(ceil(seconds * 60.0))):
		level._physics_process(1.0 / 60.0)

func walk(direction: Vector2i, count: int = 1, pull: bool = false) -> void:
	for i: int in range(count):
		var accepted: bool = level.try_step(direction, pull)
		expect(accepted, "Player action accepted at %s direction %s" % [level.hero["cell"], direction])
		if not accepted: return
		tick(0.3)
		expect(not level.dead, "Route survives real-time patrol")

func wait_for(index: int, cell: Vector2i) -> bool:
	for i: int in range(1200):
		var enemy: Dictionary = level.room()["enemies"][index]
		if enemy["cell"] == cell and not level.moving(enemy): return true
		tick(1.0 / 60.0)
	return false

func capture(name: String) -> void:
	if capture_dir.is_empty(): return
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(capture_dir.path_join(name + ".png"))

func click_control(control: Control) -> void:
	var point: Vector2 = control.get_global_rect().get_center()
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	await process_frame
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame

func guide_key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame

func _run() -> void:
	for pair: Array in [[20, "S"], [21, "A"], [25, "A"], [26, "B"], [32, "B"], [33, "C"]]:
		expect(Catalog.grade(pair[0], 20) == pair[1], "Grade boundary")
	var all: Array[Dictionary] = Catalog.entries()
	var records: Dictionary = {}
	var total: int = 0
	for i: int in range(all.size()):
		var length: int = str(all[i]["solution"]).length()
		records[str(i)] = {"steps": length, "pushes": 0}
		total += length
	expect(Catalog.aggregate(records, all) == {"grade": "S", "steps": total, "reference": total}, "Full campaign total uses matching nine levels")
	records.erase("0")
	expect(Catalog.aggregate(records, all)["grade"] == "—", "Incomplete campaign not ranked")
	var game: Campaign = load("res://campaign.tscn").instantiate()
	var path: String = "user://features_%d.json" % Time.get_ticks_usec()
	game.save_path = path
	root.add_child(game)
	game.start_new_game()
	await process_frame
	await process_frame
	expect(game.guide.is_open() and game.level.suspended, "Basic goal guide automatically pauses normal level")
	expect(game.guide.pages == ["basics", "rules"], "Normal level teaches goals and winning")
	await capture("guide_basics")
	expect(game.guide.previous_button.disabled and not game.guide.next_button.disabled, "First page disables previous button")
	await click_control(game.guide.previous_button)
	await guide_key(KEY_A)
	expect(game.guide.index == 0, "First page cannot wrap backwards with mouse or keyboard")
	await click_control(game.guide.next_button)
	expect(game.guide.index == 1, "Real mouse click advances page")
	expect(game.guide.next_button.disabled and not game.guide.previous_button.disabled, "Last page disables next button")
	await click_control(game.guide.next_button)
	await guide_key(KEY_D)
	expect(game.guide.index == 1, "Last page cannot wrap forward with mouse or keyboard")
	await click_control(game.guide.previous_button)
	expect(game.guide.index == 0, "Real mouse click returns to previous page")
	await guide_key(KEY_D)
	expect(game.guide.index == 1 and game.level.board.steps == 0, "Keyboard flips page without moving player")
	await click_control(game.guide.close_button)
	expect(not game.guide.is_open() and not game.level.suspended, "Real mouse click closes guide and resumes level")
	game.show_tutorial(true)
	await guide_key(KEY_ESCAPE)
	expect(not game.guide.is_open() and not game.level.suspended and game.modal_kind.is_empty(), "ESC closes guide without opening pause")
	game.load_level(0)
	expect(not game.guide.is_open(), "No new mechanic, no repeated teaching")
	await process_frame
	await process_frame
	var header_buttons: HBoxContainer = game.ui.find_child("HeaderButtons", true, false) as HBoxContainer
	expect(header_buttons != null, "Header uses a dedicated button row")
	if header_buttons != null:
		for button: Control in header_buttons.get_children():
			expect(not button.get_global_rect().intersects(game.save_hint.get_global_rect()), "Save status never overlaps header buttons")
		var previous_right: float = -1.0
		for button: Control in header_buttons.get_children():
			expect(button.global_position.x >= previous_right + 9.0, "Header buttons keep their spacing")
			previous_right = button.get_global_rect().end.x
	await capture("header_layout")
	game.show_garden_select()
	game.store.new_run()
	game.load_level(0)
	expect(game.guide.pages == ["flower"] and game.guide.is_open(), "Flower gate shown on first garden encounter")
	expect(game.guide.previous_button.disabled and game.guide.next_button.disabled, "Single-page guide disables both navigation buttons")
	await capture("guide_flower")
	game.guide.close_guide()
	game.store.data["unlocked"] = 3
	game.load_level(1)
	expect(game.guide.pages == ["bridge"], "Only new bridge mechanic taught")
	await capture("guide_bridge")
	game.guide.close_guide()
	game.load_level(2)
	expect(not game.guide.is_open(), "Combination level does not repeat tutorials")
	game.show_menu(false)
	game.store.data["completed"] = {}
	for i: int in range(all.size()):
		game.store.data["completed"][str(i)] = {"steps": str(all[i]["solution"]).length(), "pushes": 0}
	game.show_ending()
	await capture("grade_ending")
	root.remove_child(game)
	game.free()
	await process_frame
	for suffix: String in ["", ".tmp", ".bak", ".restoration", ".restoration.tmp", ".restoration.bak"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	var audio: Node = root.get_node_or_null("GameAudio")
	if audio != null:
		for key: String in ["defeat", "crush", "splash", "cat", "portal", "treasure"]:
			expect(audio._streams.has(StringName(key)) and audio._streams[StringName(key)].data.size() > 100, "New synthesized sound " + key)
	level = load("res://rt_level.tscn").instantiate()
	level.tutorials_enabled = false
	root.add_child(level)
	level.set_physics_process(false)
	tick(0.05)
	expect(level.room()["size"] == Vector2i(30, 18), "Expanded main room")
	var start_enemy: Vector2i = level.room()["enemies"][0]["cell"]
	tick(3.0)
	expect(level.room()["enemies"][0]["cell"] != start_enemy, "NPC patrol advances with stationary player")
	level.teach(["water"], true)
	var before: Array[Dictionary] = level.rooms.duplicate(true)
	tick(3.0)
	expect(level.rooms == before, "Guide freezes all NPCs and timers")
	level.guide.close_guide()
	level.hero = level.actor(Vector2i(9, 7))
	level._checkpoint()
	level.hero = level.actor(level.room()["enemies"][0]["cell"])
	level._contact()
	expect(level.dead, "Contact immediately kills without auto-respawn")
	before = level.rooms.duplicate(true)
	tick(2.0)
	expect(level.rooms == before, "Death freezes world")
	expect(level.undo() and not level.dead and level.paused, "Unlimited undo restores entire world and allows planning")
	level.rooms = [level._main_room(), level._hidden_room()]
	level.hero = level.actor(Vector2i(3, 5))
	level.history.clear()
	level.paused = false
	level.release_input = false
	level._rebuild_views()
	walk(Vector2i.RIGHT, 3)
	expect(level.room()["boxes"][0]["cell"] == Vector2i(7, 5), "First goal filled by normal walking and pushing")
	expect(level.player_view.get_rect().size == Vector2(64, 64), "Idle after pushing displays one sprite, never the whole strip")
	await capture("realtime_main")
	walk(Vector2i.DOWN, 8)
	walk(Vector2i.RIGHT, 20)
	level.interact()
	expect(level.room_index == 1, "Walked to entrance and entered hidden room")
	walk(Vector2i.DOWN, 5)
	expect(wait_for(1, Vector2i(5, 7)), "Small enemy reaches crush lane")
	walk(Vector2i.RIGHT)
	expect(not level.room()["enemies"][1]["alive"], "Actual player push crushes monster against wall")
	walk(Vector2i.UP, 2)
	walk(Vector2i.RIGHT, 5)
	expect(wait_for(0, Vector2i(11, 5)), "Boss reaches water lane")
	await capture("hidden_boss")
	walk(Vector2i.RIGHT)
	expect(not level.room()["enemies"][0]["alive"], "Actual push defeats boss into water, no direct die call")
	walk(Vector2i.DOWN, 4)
	walk(Vector2i.RIGHT, 6)
	level.interact()
	expect(level.relic and level.room()["chest_open"], "Chest opens only after both enemies defeated")
	level.undo()
	expect(not level.relic and not level.room()["chest_open"], "Undo chest reverses reward and lock atomically")
	level.toggle_pause()
	level.interact()
	walk(Vector2i.LEFT, 6)
	walk(Vector2i.UP, 7)
	walk(Vector2i.LEFT, 8)
	level.interact()
	expect(level.room_index == 0 and level.relic, "Returns with relic and original main-room state")
	walk(Vector2i.LEFT, 8)
	walk(Vector2i.UP, 3)
	walk(Vector2i.RIGHT, 1, true)
	expect(level.room()["boxes"][1]["cell"] == Vector2i(18, 10), "Relic pulls adjacent box in main room")
	walk(Vector2i.DOWN, 2)
	walk(Vector2i.LEFT, 2)
	walk(Vector2i.UP, 2)
	walk(Vector2i.RIGHT)
	expect(level.finished and not level.dead, "Complete playable main-hidden-reward-return-win loop")
	await capture("realtime_win")
	var cat: Dictionary = level.room()["cat"]
	level.finished = false
	cat.assign(level.actor(Vector2i(18, 10)))
	cat.merge({"dir": Vector2i.RIGHT, "wait": 0.0})
	var goal_box: Vector2i = level.room()["boxes"][1]["cell"]
	level._tick_cat(0.1)
	expect(level.room()["boxes"][1]["cell"] == goal_box, "Cat does not disturb delivered goal boxes")
	level.free()
	await process_frame
	print("FEATURE_TEST_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
