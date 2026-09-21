extends RefCounted

const VERSION: int = 2
const LEGACY_ORDER: Array[int] = [3, 0, 1, 2, 4, 6, 5, 7, 8]
const LEVEL_COUNT: int = 9
var path: String = "user://garden_campaign.json"
var level_count: int = LEVEL_COUNT
var data: Dictionary = {}
var last_error: String = ""
var recovered: bool = false

func new_run() -> void:
	data = {"version": VERSION, "unlocked": 1, "current": 0, "completed": {}, "active": {}, "finished": false, "updated": ""}

func has_save() -> bool:
	return not data.is_empty()

func load_save() -> bool:
	data.clear()
	last_error = ""
	recovered = false
	for candidate: String in [path, path + ".bak"]:
		if not FileAccess.file_exists(candidate):
			continue
		var file: FileAccess = FileAccess.open(candidate, FileAccess.READ)
		if file == null or file.get_length() > 1048576:
			continue
		var parser: JSON = JSON.new()
		if parser.parse(file.get_as_text()) != OK:
			continue
		if _valid(parser.data):
			data = parser.data
			recovered = candidate != path
			return true
		if level_count == LEVEL_COUNT and _valid(parser.data, 1):
			data = migrate_legacy(parser.data)
			recovered = candidate != path
			return true
	if FileAccess.file_exists(path):
		last_error = "存档无法读取，可重新开始；原文件未删除。"
	return false

func migrate_legacy(record: Dictionary) -> Dictionary:
	var updated: Dictionary = record.duplicate(true)
	updated["version"] = VERSION
	updated["legacy_v1"] = record.duplicate(true)
	updated["completed"] = {}
	if record["completed"].has("0"):
		updated["completed"]["3"] = record["completed"]["0"].duplicate(true)
	updated["current"] = LEGACY_ORDER[int(record["current"])]
	var unlocked: int = 1
	for old_index: int in range(int(record["unlocked"])):
		unlocked = maxi(unlocked, LEGACY_ORDER[old_index] + 1)
	updated["unlocked"] = unlocked
	updated["finished"] = false
	if int(record["current"]) != 0:
		updated["active"] = {}
	updated["upgrade_notice"] = "难度升级：解锁保留，改版关卡重新挑战。"
	return updated

func _valid(value: Variant, expected_version: int = VERSION) -> bool:
	if not value is Dictionary:
		return false
	var record: Dictionary = value
	if record.get("version") != expected_version:
		return false
	for field: String in ["unlocked", "current"]:
		if not (record.get(field) is float or record.get(field) is int):
			return false
		if float(record[field]) != floorf(float(record[field])):
			return false
	if int(record["unlocked"]) < 1 or int(record["unlocked"]) > level_count or int(record["current"]) < 0 or int(record["current"]) >= int(record["unlocked"]):
		return false
	if not record.get("completed") is Dictionary or not record.get("active") is Dictionary or not record.get("finished") is bool or not record.get("updated") is String:
		return false
	for key: Variant in record["completed"]:
		if not str(key).is_valid_int() or int(str(key)) < 0 or int(str(key)) >= level_count:
			return false
		var best: Variant = record["completed"][key]
		if not best is Dictionary:
			return false
		for field: String in ["steps", "pushes"]:
			var limit: int = 2147483647 if field == "steps" else 10000
			if not (best.get(field) is int or best.get(field) is float) or not is_finite(float(best[field])) or float(best[field]) < 0 or float(best[field]) > limit or float(best[field]) != floorf(float(best[field])):
				return false
		if best["pushes"] > best["steps"]:
			return false
	var active: Dictionary = record["active"]
	if not active.is_empty():
		if not active.get("moves") is String or str(active["moves"]).length() > 10000:
			return false
		for letter: String in str(active["moves"]):
			if not "UDLR".contains(letter):
				return false
		var total_steps: Variant = active.get("total_steps", str(active["moves"]).length())
		if not (total_steps is int or total_steps is float):
			return false
		if not is_finite(float(total_steps)) or float(total_steps) != floorf(float(total_steps)) or float(total_steps) < str(active["moves"]).length() or float(total_steps) > 2147483647:
			return false
	return true

func write_save() -> bool:
	last_error = ""
	data["updated"] = Time.get_datetime_string_from_system(false, true)
	if not _valid(data):
		last_error = "存档状态校验失败，未覆盖旧存档。"
		return false
	var temporary: String = path + ".new"
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		last_error = "无法写入本机存档，请检查目录权限。"
		return false
	file.store_string(JSON.stringify(data))
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if error != OK:
		last_error = "存档写入失败，旧存档仍保留。"
		return false
	var absolute: String = ProjectSettings.globalize_path(path)
	var backup: String = absolute + ".bak"
	if FileAccess.file_exists(path):
		# Never replace a verified backup with a corrupt primary file after recovery.
		if recovered:
			var damaged: String = absolute + ".damaged"
			if FileAccess.file_exists(damaged):
				DirAccess.remove_absolute(damaged)
			error = DirAccess.rename_absolute(absolute, damaged)
		else:
			if FileAccess.file_exists(backup):
				DirAccess.remove_absolute(backup)
			error = DirAccess.rename_absolute(absolute, backup)
		if error != OK:
			last_error = "无法备份旧存档，已取消保存。"
			return false
	error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), absolute)
	if error != OK:
		if FileAccess.file_exists(backup):
			DirAccess.copy_absolute(backup, absolute)
		last_error = "存档替换失败，可从备份恢复。"
		return false
	recovered = false
	return true
