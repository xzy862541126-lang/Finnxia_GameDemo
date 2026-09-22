extends "res://rt_level.gd"

signal exit_requested
signal restart_requested
signal save_requested
signal completed
const Catalog = preload("res://journey_catalog.gd")
const Scenery = preload("res://scenery_theme.gd")
const GardenArt = preload("res://garden_art.gd")
const CLASSIC_SCENE: PackedScene = preload("res://level_1.tscn")
const TIMBER: Texture2D = preload("res://assets/scenery/bridge_supply.png")
var definition: Dictionary
var start_relic: bool = false
var seen_guides: Dictionary = {}
var scenery: Node2D
var current_art: GardenArt
var status_label: Label
var save_label: Label
var hud_buttons: Array[Button] = []
var exploration_steps: int = 0
var dirty: bool = false
var _won_announced: bool = false

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rooms.assign(definition["rooms"].duplicate(true))
	hero = actor(definition["start"])
	relic = start_relic
	player_view = PlayerView.new()
	player_view.z_index = 4
	add_child(player_view)
	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()
	guide = Guide.new()
	guide.seen = seen_guides
	guide.body_overrides = {
		"basics": "每个普通货箱都对应一个金色目标，全部到位即可交货。\n有水道的关卡，还要用蓝绳桥材完成修桥。\n桥材和隐藏房的红带工具箱，不算交货箱。",
		"boss": "红带箱只用来战斗，不用送到目标点。\n先用石墙夹住小怪打开隔门，再把Boss推下水。\n通过最后一道门，按 E 开宝箱；出口按 E 返回。",
		"rules": "方向键 / WASD 移动，一次推一个箱子。Z 撤销，R 重开。\nS≤参考步数；A≤1.25倍；B≤1.6倍；C≤2倍；其余为D。\n参考是可复现解法，不是理论最少步数。",
		"relic": "站在箱子旁，按住 Shift 向后走，就能拉动箱子。\n一次只能拉一个，身后要有空位。\n带着手套完成本关，就能在后续关卡继续使用。"
	}
	add_child(guide)
	guide.closed.connect(func() -> void:
		release_input = true
		dirty = true)
	_build_hud()
	_rebuild_views()
	notice = definition["hint"]
	_update_view(0.0)

func begin_tutorial() -> void:
	var topics: Array[String] = []
	topics.assign(definition["topics"])
	if relic: topics.append("relic")
	teach(topics)

func gate_closed(cell: Vector2i) -> bool:
	if room().get("combat_gates", {}).has(cell):
		return room()["enemies"][room()["combat_gates"][cell]]["alive"]
	for flower: Dictionary in room().get("flowers", []):
		if flower["gates"].has(cell) and not room()["blooms"].has(flower["cell"]): return true
	return false

func solid(cell: Vector2i) -> bool:
	return not room()["floor"].has(cell) or gate_closed(cell) or (room()["water"].has(cell) and not room()["bridges"].has(cell))

func box_at(cell: Vector2i) -> int:
	for i: int in range(room()["boxes"].size()):
		var b: Dictionary = room()["boxes"][i]
		if b.get("used", false): continue
		if b["cell"] == cell or (moving(b) and b["from"] == cell): return i
	return -1

func can_push(index: int, direction: Vector2i) -> bool:
	var b: Dictionary = room()["boxes"][index]
	var to: Vector2i = b["cell"] + direction
	if b.get("timber", false) and room()["water"].has(to) and not room()["bridges"].has(to):
		return not moving(b) and room()["floor"].has(to) and not gate_closed(to) and box_at(to) < 0 and enemy_at(to) < 0 and not cat_at(to)
	var e: int = enemy_at(to)
	if e >= 0 and gate_closed(to + direction): return false
	return super.can_push(index, direction)

func _push(index: int, direction: Vector2i) -> void:
	var b: Dictionary = room()["boxes"][index]
	var to: Vector2i = b["cell"] + direction
	var enemy: int = enemy_at(to)
	if enemy >= 0:
		var e: Dictionary = room()["enemies"][enemy]
		var beyond: Vector2i = to + direction
		var drowning: bool = room()["water"].has(beyond) and not room()["bridges"].has(beyond)
		if drowning or not room()["floor"].has(beyond) or box_at(beyond) >= 0:
			e["alive"] = false
			sound(&"splash" if drowning else &"crush")
			effects.append({"pos": position_of(e), "time": 0.65, "color": Color("8bdbe1") if drowning else Color("eccd8c")})
			notice = "怪物落水了！" if drowning else "箱子夹住了怪物！"
		else:
			start_move(e, beyond, PUSH)
			e["wait"] = 2.5
	start_move(b, to, PUSH)

func _tick_cat(delta: float) -> void:
	var cat: Dictionary = room()["cat"]
	if not cat.is_empty():
		if cat.has("patrol_cells") and not moving(cat) and not cat["patrol_cells"].has(cat["cell"] + cat["dir"]):
			cat["dir"] = -Vector2i(cat["dir"])
		var index: int = box_at(cat["cell"] + cat["dir"])
		if index >= 0 and room()["boxes"][index].get("timber", false):
			cat["wait"] = maxf(float(cat["wait"]) - delta, 0.0)
			if float(cat["wait"]) <= 0.0:
				_checkpoint_npc()
				cat["dir"] = DIRECTIONS[(DIRECTIONS.find(cat["dir"]) + 1) % 4]
				cat["wait"] = 4.0
			return
	super._tick_cat(delta)

func _resolve_mechanisms() -> void:
	for b: Dictionary in room()["boxes"]:
		if moving(b) or b.get("used", false): continue
		var c: Vector2i = b["cell"]
		if b.get("timber", false):
			if room()["water"].has(c) and not room()["bridges"].has(c):
				b["used"] = true
				room()["bridges"][c] = true
				notice = "木桥搭好了，普通货箱现在可以过河。"
				sound(&"bridge")
				dirty = true
		elif not b.get("tool", false):
			for flower: Dictionary in room()["flowers"]:
				if c == flower["cell"] and not room()["blooms"].has(c):
					room()["blooms"][c] = true
					notice = "花坛亮了，藤蔓门已打开。"
					sound(&"bloom")
					dirty = true

func try_step(direction: Vector2i, pull: bool = false) -> bool:
	var accepted: bool = super.try_step(direction, pull)
	if accepted:
		if room_index != 0:
			steps -= 1
			exploration_steps += 1
		dirty = true
	return accepted

func _check_win() -> void:
	_resolve_mechanisms()
	if finished or dead or moving(hero) or room_index != 0: return
	if room()["goals"].is_empty(): return
	var cargo: int = 0
	for b: Dictionary in room()["boxes"]:
		if not b.get("timber", false) and not b.get("tool", false): cargo += 1
	if cargo != room()["goals"].size(): return
	for water: Vector2i in room()["water"]:
		if not room()["bridges"].has(water): return
	for goal: Vector2i in room()["goals"]:
		var index: int = box_at(goal)
		if index < 0 or room()["boxes"][index].get("timber", false) or room()["boxes"][index].get("tool", false) or moving(room()["boxes"][index]): return
	finished = true
	dirty = true
	sound(&"win")
	if not _won_announced:
		_won_announced = true
		completed.emit()

func snapshot() -> Dictionary:
	var dynamics: Array = []
	for r: Dictionary in rooms:
		dynamics.append({"boxes": r["boxes"].duplicate(true), "enemies": r["enemies"].duplicate(true), "cat": r["cat"].duplicate(true), "blooms": r["blooms"].duplicate(), "bridges": r["bridges"].duplicate(), "chest_open": r["chest_open"], "return": r.get("return", {}).duplicate(true)})
	return {"dynamic": dynamics, "room": room_index, "hero": hero.duplicate(true), "facing": facing, "relic": relic, "finished": finished, "clock": world_clock}

func _checkpoint() -> void:
	history.append(snapshot())
	dirty = true

func _checkpoint_npc() -> void:
	var s: Dictionary = snapshot()
	s["player"] = false
	history.append(s)
	dirty = true

func apply_snapshot(s: Dictionary) -> void:
	for i: int in range(rooms.size()):
		for key: String in s["dynamic"][i]:
			if key == "return" and s["dynamic"][i][key].is_empty(): rooms[i].erase(key)
			else: rooms[i][key] = s["dynamic"][i][key].duplicate(true) if s["dynamic"][i][key] is Array or s["dynamic"][i][key] is Dictionary else s["dynamic"][i][key]
		for e: Dictionary in rooms[i]["enemies"]:
			e["wait"] = maxf(float(e["wait"]), 0.6)
		if not rooms[i]["cat"].is_empty():
			rooms[i]["cat"]["wait"] = maxf(float(rooms[i]["cat"]["wait"]), 1.0)
	room_index = s["room"]
	hero = s["hero"].duplicate(true)
	facing = s["facing"]
	relic = s["relic"]
	finished = s["finished"]
	world_clock = s["clock"]
	dead = false
	paused = true
	release_input = true
	pushing = false
	effects.clear()
	_won_announced = false
	_rebuild_views()
	_update_view(0.0)

func undo() -> bool:
	if guide.is_open() or history.is_empty(): return false
	var was_paused: bool = paused
	if room_index == 0: steps += 1
	else: exploration_steps += 1
	while not history.is_empty():
		var s: Dictionary = history.pop_back()
		apply_snapshot(s)
		if bool(s.get("player", true)):
			break
	paused = was_paused
	notice = "已撤销。空格继续。" if paused else "已撤销，可以继续移动。"
	_update_view(0.0)
	sound(&"undo")
	dirty = true
	return true

func interact() -> void:
	if blocked() or moving(hero): return
	if room_index == 0 and room().has("portal") and Vector2i(hero["cell"]).distance_to(room()["portal"]) <= 1.0:
		_checkpoint()
		room()["return"] = hero.duplicate(true)
		room_index = 1
		hero = room().get("return", actor(room()["spawn"])).duplicate(true)
		release_input = true
		_rebuild_views()
		sound(&"portal")
		notice = "红带箱是战斗工具：先夹小怪开门，再把Boss推下水。"
		teach(["patrol", "crush", "water", "boss"])
	elif room_index > 0:
		super.interact()
	_update_view(0.0)
	dirty = true

func capture_state() -> Dictionary:
	return {"id": definition["id"], "state": snapshot(), "history": history.duplicate(true), "steps": steps, "exploration_steps": exploration_steps, "dead": dead}

func valid_actor(a: Variant, r: Dictionary) -> bool:
	if not a is Dictionary: return false
	for key: String in ["cell", "from"]:
		if not a.get(key) is Vector2i or not r["floor"].has(a[key]): return false
	for key: String in ["t", "duration"]:
		if not (a.get(key) is float or a.get(key) is int) or not is_finite(float(a[key])): return false
	return a["t"] >= 0.0 and a["t"] <= 1.0 and a["duration"] > 0.0 and a["duration"] <= 10.0 and Vector2i(a["cell"]).distance_to(a["from"]) <= 1.0

func valid_snapshot(s: Variant) -> bool:
	if not s is Dictionary or not s.get("room") is int or s["room"] < 0 or s["room"] >= rooms.size(): return false
	if not s.get("dynamic") is Array or s["dynamic"].size() != rooms.size(): return false
	if not s.get("facing") in DIRECTIONS or not s.get("relic") is bool or not s.get("finished") is bool: return false
	if not (s.get("clock") is float or s.get("clock") is int) or not is_finite(float(s["clock"])) or s["clock"] < 0: return false
	if not valid_actor(s.get("hero"), rooms[s["room"]]): return false
	for i: int in range(rooms.size()):
		var r: Dictionary = rooms[i]
		var d: Variant = s["dynamic"][i]
		if not d is Dictionary: return false
		for key: String in ["boxes", "enemies"]:
			if not d.get(key) is Array or d[key].size() != r[key].size(): return false
			for j: int in range(d[key].size()):
				var a: Variant = d[key][j]
				if not valid_actor(a, r): return false
				if key == "boxes":
					if not a.get("timber") is bool or a["timber"] != r[key][j]["timber"] or not a.get("used") is bool: return false
					if not a.get("tool") is bool or a["tool"] != r[key][j]["tool"]: return false
					if a["used"] and not a["timber"]: return false
				else:
					if not a.get("alive") is bool or a.get("boss") != r[key][j]["boss"] or not a.get("dir") in DIRECTIONS: return false
					if a.get("low") != r[key][j]["low"] or a.get("high") != r[key][j]["high"]: return false
					if not (a.get("wait") is float or a.get("wait") is int) or not is_finite(float(a["wait"])): return false
		if not d.get("cat") is Dictionary or d["cat"].is_empty() != r["cat"].is_empty(): return false
		if not d["cat"].is_empty():
			if not valid_actor(d["cat"], r) or not d["cat"].get("dir") in DIRECTIONS or not (d["cat"].get("wait") is float or d["cat"].get("wait") is int): return false
		for key: String in ["blooms", "bridges"]:
			if not d.get(key) is Dictionary: return false
			for at: Variant in d[key]:
				if not at is Vector2i or not d[key][at] is bool or not r["floor"].has(at): return false
		if not d.get("chest_open") is bool or not d.get("return") is Dictionary: return false
		if not d["return"].is_empty() and not valid_actor(d["return"], r): return false
	return true

func restore_state(data: Dictionary) -> bool:
	if data.get("id") != definition["id"] or not valid_snapshot(data.get("state")): return false
	if not data.get("history") is Array or not data.get("dead") is bool: return false
	for key: String in ["steps", "exploration_steps"]:
		if not data.get(key) is int or data[key] < 0: return false
	for s: Variant in data["history"]:
		if not valid_snapshot(s): return false
	apply_snapshot(data["state"])
	history.assign(data["history"].duplicate(true))
	steps = data["steps"]
	exploration_steps = data["exploration_steps"]
	dead = data["dead"]
	notice = "进度已恢复。空格继续；Z 撤销。"
	return true

func _build_hud() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	for rect: Rect2 in [Rect2(0, 0, 1280, 80), Rect2(0, 674, 1280, 94)]:
		var panel: ColorRect = ColorRect.new()
		panel.position = rect.position
		panel.size = rect.size
		panel.color = Color(0.055, 0.12, 0.11, 0.96)
		layer.add_child(panel)
	hud = _label(layer, Vector2(24, 10), Vector2(690, 60), 20)
	banner = _label(layer, Vector2(24, 716), Vector2(1220, 44), 17)
	status_label = _label(layer, Vector2(24, 680), Vector2(1220, 30), 20)
	save_label = _label(layer, Vector2(960, 57), Vector2(292, 22), 13)
	save_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for item: Array in [["图解 H", 734, 0], ["暂停", 840, 1], ["保存", 944, 2], ["菜单 Esc", 1050, 3], ["重开 R", 1162, 4]]:
		var button: Button = Button.new()
		if has_meta("hud_theme"):
			button.theme = get_meta("hud_theme")
		button.text = item[0]
		button.position = Vector2(item[1], 12)
		button.size = Vector2(96 if item[2] < 3 else 104, 40)
		button.add_theme_font_size_override("font_size", 17)
		button.focus_mode = Control.FOCUS_NONE
		var action: int = item[2]
		button.pressed.connect(_hud_action.bind(action))
		layer.add_child(button)
		hud_buttons.append(button)

func _hud_action(action: int) -> void:
	if guide.is_open(): return
	match action:
		0: show_help()
		1: toggle_pause()
		2: save_requested.emit()
		3: exit_requested.emit()
		4: restart_requested.emit()

func _label(parent: Node, at: Vector2, extent: Vector2, font_size: int) -> Label:
	var label: Label = Label.new()
	label.position = at
	label.size = extent
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("ecd7aa"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	parent.add_child(label)
	return label

func show_help() -> void:
	var topics: Array[String] = ["basics", "rules"]
	for key: String in definition["topics"]:
		if not topics.has(key): topics.append(key)
	if room_index > 0:
		for key: String in ["crush", "water", "boss"]:
			if not topics.has(key): topics.append(key)
	if relic: topics.append("relic")
	teach(topics, true)

func _unhandled_input(event: InputEvent) -> void:
	if guide.is_open() or not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_Z: undo()
		KEY_SPACE: toggle_pause()
		KEY_E: interact()
		KEY_H: show_help()
		KEY_R: restart_requested.emit()
		KEY_ESCAPE: exit_requested.emit()
		_: return
	get_viewport().set_input_as_handled()

func _rebuild_views() -> void:
	super._rebuild_views()
	for i: int in range(box_views.size()):
		var b: Dictionary = room()["boxes"][i]
		if b.get("tool", false):
			var stripe: ColorRect = ColorRect.new()
			stripe.position = Vector2(-22, 12)
			stripe.size = Vector2(44, 5)
			stripe.color = Color("df7b6b")
			stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box_views[i].add_child(stripe)
		elif b.get("timber", false):
			_label(box_views[i], Vector2(-24, -44), Vector2(56, 22), 14).text = "桥材"
	_refresh_scenery()

func _refresh_scenery() -> void:
	if is_instance_valid(scenery): scenery.free()
	scenery = Node2D.new()
	add_child(scenery)
	var template: Node = CLASSIC_SCENE.instantiate()
	var tiles: TileMapLayer = TileMapLayer.new()
	tiles.tile_set = template.get_node("TileMapLayer").tile_set
	template.free()
	tiles.collision_enabled = false
	tiles.z_index = -1
	scenery.add_child(tiles)
	Scenery.install_sources(tiles)
	for c: Vector2i in room()["render_tiles"]:
		tiles.set_cell(c, room()["render_tiles"][c], Vector2i.ZERO)
	current_art = GardenArt.new()
	current_art.floor_cells.assign(room()["floor"].keys())
	current_art.theme_index = room()["theme"]
	current_art.scene_index = room()["art"]
	for c: Vector2i in tiles.get_used_cells():
		var id: int = tiles.get_cell_source_id(c)
		current_art.blocked_cells[c] = true
		if id >= 5: current_art.obstacle_cells[c] = id
		else: current_art.wall_cells.append(c)
	scenery.add_child(current_art)
	var backdrop: Polygon2D = Polygon2D.new()
	backdrop.polygon = PackedVector2Array([Vector2(-2048, -2048), Vector2(8192, -2048), Vector2(8192, 8192), Vector2(-2048, 8192)])
	backdrop.color = GardenArt.COLORS[posmod(room()["theme"], 4)]
	backdrop.z_index = -20
	scenery.add_child(backdrop)

func _update_view(delta: float) -> void:
	super._update_view(delta)
	for i: int in range(box_views.size()):
		var b: Dictionary = room()["boxes"][i]
		box_views[i].visible = not b.get("used", false)
		if b.get("timber", false): box_views[i].texture = TIMBER
	if current_art != null: current_art.set_process(not blocked())
	var size: Vector2 = Vector2(room()["size"]) * CELL
	var center: Vector2 = size * 0.5
	if room_index == 0:
		center = Vector2(640, 384)
	else:
		center = Vector2(room()["size"]) * CELL * 0.5
	camera.position = center
	var filled: int = 0
	for goal: Vector2i in rooms[0]["goals"]:
		for b: Dictionary in rooms[0]["boxes"]:
			if not b.get("used", false) and not b.get("timber", false) and b["cell"] == goal: filled += 1
	hud.text = "%s%s\n%s" % [definition["title"], " · 隐藏温室" if room_index else "", definition["hint"]]
	status_label.text = "货箱 %d / %d   共用 %d 步" % [filled, rooms[0]["goals"].size(), steps]
	if not rooms[0]["water"].is_empty():
		status_label.text += "   修桥 %d / %d" % [rooms[0]["bridges"].size(), rooms[0]["water"].size()]
	if rooms.size() > 1 and (exploration_steps > 0 or room_index > 0): status_label.text += "   探索 %d 步" % exploration_steps
	if relic: status_label.text += "   Shift 拉箱"
	if room_index > 0:
		var remaining: int = 0
		for e: Dictionary in room()["enemies"]:
			if e["alive"]: remaining += 1
		status_label.text = "守卫剩余 %d   战斗工具箱 2   探索 %d 步" % [remaining, exploration_steps]
	banner.text = ("已死亡 · Z 撤销，空格继续" if dead else "已暂停 · 空格继续 / Z 继续撤销" if paused else notice) + "  |  WASD 移动 · E 交互 · Z 撤销"

func _draw() -> void:
	if rooms.is_empty(): return
	var r: Dictionary = room()
	for w: Vector2i in r["water"]:
		var p: Vector2 = Vector2(w) * CELL
		draw_rect(Rect2(p, Vector2(64, 64)), Color("326a83"))
		for i: int in range(3): draw_rect(Rect2(p + Vector2(6 + posmod(int(world_clock * 12) + i * 9, 22), 12 + i * 16), Vector2(27, 3)), Color("83b9c6"))
		if r["bridges"].has(w):
			for i: int in range(7):
				draw_rect(Rect2(p + Vector2(i * 9 + 1, 7), Vector2(8, 50)), Color("bc965f"))
				draw_rect(Rect2(p + Vector2(i * 9 + 2, 10), Vector2(2, 44)), Color("edcd94"))
	for flower: Dictionary in r["flowers"]:
		var p: Vector2 = Vector2(flower["cell"]) * CELL
		var open: bool = r["blooms"].has(flower["cell"])
		draw_rect(Rect2(p + Vector2(3, 3), Vector2(58, 58)), Color("77815a"))
		for i: int in range(8):
			var pos: Vector2 = p + Vector2(12 + i % 4 * 13, 10 if i < 4 else 50)
			draw_rect(Rect2(pos - Vector2(4, 1), Vector2(9, 3)), Color("f3b5c0") if open else Color("c29eae"))
			draw_rect(Rect2(pos - Vector2(1, 4), Vector2(3, 9)), Color("f3b5c0") if open else Color("c29eae"))
		for gate: Vector2i in flower["gates"]:
			var at: Vector2 = Vector2(gate) * CELL
			for i: int in range(2 if open else 5):
				var x: float = 5 + i * 52 if open else 7 + i * 12
				draw_polyline(PackedVector2Array([at + Vector2(x, 2), at + Vector2(x + 4, 24), at + Vector2(x - 2, 62)]), Color("274e38"), 7)
				draw_line(at + Vector2(x, 4), at + Vector2(x + 2, 58), Color("91b574"), 2)
	for gate: Vector2i in r.get("combat_gates", {}):
		var at: Vector2 = Vector2(gate) * CELL
		if gate_closed(gate):
			for i: int in range(5): draw_rect(Rect2(at + Vector2(5 + i * 12, 2), Vector2(5, 60)), Color("ad8c66"))
		else:
			draw_rect(Rect2(at + Vector2(2, 2), Vector2(4, 60)), Color("74ad91"))
			draw_rect(Rect2(at + Vector2(58, 2), Vector2(4, 60)), Color("74ad91"))
	for g: Vector2i in r["goals"]: draw_texture(GOAL, Vector2(g) * CELL)
	for e: Dictionary in r["enemies"]:
		if e["alive"]:
			draw_rect(Rect2(Vector2(e["cell"] + e["dir"]) * CELL + Vector2(5, 5), Vector2(54, 54)), Color(0.8, 0.3, 0.25, 0.2))
	if r.has("portal"):
		var at: Vector2 = Vector2(r["portal"]) * CELL
		draw_texture(Art.texture("portal"), at)
		draw_string(ThemeDB.fallback_font, at + Vector2(-16, -9), "E 返回" if room_index else "E 隐藏入口", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("efd8a0"))
	if r.has("chest") and not r["chest_open"]:
		var at: Vector2 = Vector2(r["chest"]) * CELL
		draw_texture(Art.texture("chest"), at)
		draw_string(ThemeDB.fallback_font, at + Vector2(-8, -9), "E 宝箱", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("efd8a0"))
	if not r["cat"].is_empty():
		var at: Vector2 = position_of(r["cat"]) + Vector2(0, -40)
		draw_line(at, at + Vector2(r["cat"]["dir"]) * 20, Color("efdaac"), 3)
	for fx: Dictionary in effects:
		for i: int in range(8):
			var a: float = TAU * i / 8.0
			draw_rect(Rect2(fx["pos"] + Vector2(cos(a), sin(a)) * (1.0 - fx["time"]) * 70, Vector2(5, 5)), fx["color"])
