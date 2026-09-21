extends SceneTree

const Store = preload("res://save_store.gd")
const Catalog = preload("res://campaign_catalog.gd")
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var store: Store = Store.new()
	store.path = "user://difficulty_upgrade_test_%d.json" % Time.get_ticks_usec()
	var old: Dictionary = {"version": 1, "unlocked": 9, "current": 0, "completed": {"0": {"steps": 39, "pushes": 11}, "1": {"steps": 47, "pushes": 13}}, "active": {"moves": "LDD"}, "finished": false, "updated": "test"}
	var file: FileAccess = FileAccess.open(store.path, FileAccess.WRITE)
	file.store_string(JSON.stringify(old))
	file.close()
	check(store.load_save(), "Legacy disk save loads")
	check(int(store.data["version"]) == 2, "Schema upgraded")
	check(int(store.data["current"]) == 3, "Original first level moves to fourth")
	check(store.data["active"] == old["active"], "Unchanged original scene keeps active replay")
	check(store.data["completed"].has("3") and store.data["completed"].size() == 1, "Only unchanged results become current medals")
	check(store.data["legacy_v1"] == JSON.parse_string(JSON.stringify(old)), "All old progress preserved as archive")
	check(store.data["unlocked"] == 9, "Existing unlocked access preserved")
	var level: Node2D = Catalog.create_level(3)
	root.add_child(level)
	check(level.restore_state(store.data["active"]), "Original active save restores in new slot")
	check(level.board.steps == 3 and level.board.pushes == 2, "Replay counters preserved")
	level.queue_free()
	check(store.write_save(), "Upgraded save writes")
	var reload_store: Store = Store.new()
	reload_store.path = store.path
	check(reload_store.load_save() and reload_store.data == JSON.parse_string(JSON.stringify(store.data)), "Upgrade survives disk round-trip")
	for old_index: int in range(9):
		old["current"] = old_index
		var migrated: Dictionary = store.migrate_legacy(old)
		check(store._valid(migrated), "Migrated record validates")
		check(migrated["current"] == Store.LEGACY_ORDER[old_index], "Stable identity mapping")
		if old_index != 0:
			check(migrated["active"].is_empty(), "Changed layout cannot inherit unsafe replay")
	old["version"] = 999
	check(not store._valid(old), "Unknown version rejected")
	await process_frame
	for suffix: String in ["", ".bak", ".new", ".damaged"]:
		var path: String = ProjectSettings.globalize_path(store.path + suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	print("SAVE_UPGRADE_TEST failures=%d" % failures)
	quit(0 if failures == 0 else 1)
