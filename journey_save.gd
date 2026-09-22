extends RefCounted

const Catalog = preload("res://journey_catalog.gd")
const LIMIT: int = 64 * 1024 * 1024
var path: String = "user://original_nine_v2.save"
var data: Dictionary = {}
var error_text: String = ""
var recovered: bool = false

func new_run() -> void:
	data = {"version": 1, "catalog": Catalog.VERSION, "current": 0, "unlocked": 1, "relic": false, "completed": {}, "seen": {}, "active": {}, "finished": false}

func valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != 1 or value.get("catalog") != Catalog.VERSION: return false
	if not value.get("current") is int or value["current"] < 0 or value["current"] >= 9: return false
	if not value.get("unlocked") is int or value["unlocked"] < 1 or value["unlocked"] > 9 or value["current"] >= value["unlocked"]: return false
	if not value.get("relic") is bool or not value.get("finished") is bool: return false
	if not value.get("completed") is Dictionary or not value.get("seen") is Dictionary or not value.get("active") is Dictionary: return false
	for key: Variant in value["completed"]:
		if not key is String or not key.is_valid_int() or int(key) < 0 or int(key) >= 9: return false
		var record: Variant = value["completed"][key]
		if not record is Dictionary or not record.get("steps") is int or record["steps"] < 0: return false
	for key: Variant in value["seen"]:
		if not key is String or not value["seen"][key] is bool: return false
	return true

func load_save() -> bool:
	data = {}
	error_text = ""
	recovered = false
	for file_path: String in [path, path + ".bak"]:
		if not FileAccess.file_exists(file_path): continue
		var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
		if file == null or file.get_length() > LIMIT: continue
		var candidate: Variant = file.get_var(false)
		if file.get_error() != OK or not valid(candidate): continue
		data = candidate
		recovered = file_path != path
		if recovered: error_text = "主存档不可用，已恢复备份。"
		return true
	if FileAccess.file_exists(path): error_text = "存档无法读取，未覆盖原文件。可重新开始。"
	return false

func write_save() -> bool:
	error_text = ""
	if not valid(data):
		error_text = "存档状态不完整，未覆盖旧文件。"
		return false
	var bytes: PackedByteArray = var_to_bytes(data)
	if bytes.size() > LIMIT - 4:
		error_text = "回溯记录过大，请先完成本关再保存。"
		return false
	var temp: String = path + ".new"
	var file: FileAccess = FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		error_text = "无法写入存档。"
		return false
	file.store_var(data, false)
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if error != OK:
		error_text = "存档写入失败，旧文件仍在。"
		return false
	var backup: String = path + (".damaged" if recovered else ".bak")
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(backup) and DirAccess.remove_absolute(backup) != OK:
			error_text = "备份无法替换。"
			return false
		if DirAccess.rename_absolute(path, backup) != OK:
			error_text = "无法备份旧存档。"
			return false
	if DirAccess.rename_absolute(temp, path) != OK:
		if FileAccess.file_exists(backup): DirAccess.copy_absolute(backup, path)
		error_text = "存档替换失败。"
		return false
	recovered = false
	return true
