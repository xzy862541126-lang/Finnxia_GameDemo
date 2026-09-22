extends Node2D

const Art = preload("res://rt_art.gd")
const PlayerView = preload("res://rt_player.gd")
const MonsterView = preload("res://rt_monster.gd")
const CatView = preload("res://rt_cat.gd")
const Guide = preload("res://rt_guide.gd")
const DIRECTIONS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
const CELL: float = 64.0
const WALK: float = 0.17
const PUSH: float = 0.25
const CRATE: Texture2D = preload("res://assets/crate.png")
const DONE: Texture2D = preload("res://assets/crate_on_goal.png")
const GOAL: Texture2D = preload("res://assets/goal.png")
const WALL: Texture2D = preload("res://assets/wall_moss.png")
const ROCK: Texture2D = preload("res://assets/rock.png")

@export var tutorials_enabled: bool = true
var rooms: Array[Dictionary] = []
var room_index: int = 0
var hero: Dictionary
var facing: Vector2i = Vector2i.RIGHT
var pushing: bool = false
var dead: bool = false
var relic: bool = false
var finished: bool = false
var paused: bool = false
var release_input: bool = true
var history: Array[Dictionary] = []
var steps: int = 0
var player_view: PlayerView
var monster_views: Array[MonsterView] = []
var box_views: Array[Sprite2D] = []
var cat_view: CatView
var camera: Camera2D
var guide: Guide
var hud: Label
var banner: Label
var notice: String = "东侧藤洞按 E 进入隐藏温室；本模式进度仅保留到退出。"
var effects: Array[Dictionary] = []
var world_clock: float = 0.0

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	get_tree().auto_accept_quit = true
	rooms = [_main_room(), _hidden_room()]
	hero = actor(Vector2i(3, 5))
	player_view = PlayerView.new()
	player_view.z_index = 4
	add_child(player_view)
	camera = Camera2D.new()
	camera.position_smoothing_enabled = false
	add_child(camera)
	camera.make_current()
	guide = Guide.new()
	add_child(guide)
	guide.closed.connect(func() -> void: release_input = true)
	_build_hud()
	_rebuild_views()
	teach(["patrol", "crush", "water", "cat"])
	_update_view(0.0)

func actor(cell: Vector2i) -> Dictionary:
	return {"cell": cell, "from": cell, "t": 1.0, "duration": WALK}

func room() -> Dictionary:
	return rooms[room_index]

func _make_room(size: Vector2i) -> Dictionary:
	var floor_cells: Dictionary = {}
	for y: int in range(1, size.y - 1):
		for x: int in range(1, size.x - 1):
			floor_cells[Vector2i(x, y)] = true
	return {"size": size, "floor": floor_cells, "water": {}, "goals": [], "boxes": [], "enemies": [], "cat": {}, "chest_open": false}

func _main_room() -> Dictionary:
	var r: Dictionary = _make_room(Vector2i(30, 18))
	for rect: Rect2i in [Rect2i(1, 1, 3, 2), Rect2i(26, 1, 3, 4), Rect2i(1, 14, 4, 3), Rect2i(12, 3, 2, 3), Rect2i(11, 10, 1, 1), Rect2i(23, 9, 2, 2)]:
		for y: int in range(rect.position.y, rect.end.y):
			for x: int in range(rect.position.x, rect.end.x):
				r["floor"].erase(Vector2i(x, y))
	r["goals"] = [Vector2i(7, 5), Vector2i(19, 10)]
	for cell: Vector2i in [Vector2i(5, 5), Vector2i(17, 10), Vector2i(9, 10), Vector2i(18, 5), Vector2i(15, 7)]:
		r["boxes"].append(actor(cell))
	r["enemies"] = [_enemy(Vector2i(10, 10), Vector2i.DOWN, Vector2i(10, 9), Vector2i(10, 11)), _enemy(Vector2i(20, 5), Vector2i.UP, Vector2i(20, 4), Vector2i(20, 6))]
	for y: int in range(3, 8):
		r["water"][Vector2i(21, y)] = true
	r["portal"] = Vector2i(26, 13)
	r["cat"] = actor(Vector2i(14, 7))
	r["cat"].merge({"dir": Vector2i.RIGHT, "wait": 4.0})
	return r

func _hidden_room() -> Dictionary:
	var r: Dictionary = _make_room(Vector2i(20, 14))
	for cell: Vector2i in [Vector2i(1, 1), Vector2i(18, 1), Vector2i(18, 12), Vector2i(6, 7)]:
		r["floor"].erase(cell)
	for y: int in range(3, 9):
		r["water"][Vector2i(12, y)] = true
	r["boxes"] = [actor(Vector2i(10, 5)), actor(Vector2i(4, 7))]
	r["enemies"] = [_enemy(Vector2i(11, 5), Vector2i.DOWN, Vector2i(11, 4), Vector2i(11, 6), true), _enemy(Vector2i(5, 7), Vector2i.DOWN, Vector2i(5, 6), Vector2i(5, 8))]
	r["portal"] = Vector2i(2, 2)
	r["chest"] = Vector2i(16, 9)
	return r

func _enemy(cell: Vector2i, direction: Vector2i, low: Vector2i, high: Vector2i, boss: bool = false) -> Dictionary:
	var result: Dictionary = actor(cell)
	result.merge({"dir": direction, "low": low, "high": high, "alive": true, "boss": boss, "wait": 2.5 if boss else 2.0})
	return result

func blocked() -> bool:
	return paused or dead or finished or guide.is_open()

func moving(a: Dictionary) -> bool:
	return float(a["t"]) < 1.0

func position_of(a: Dictionary) -> Vector2:
	return (Vector2(a["from"]).lerp(Vector2(a["cell"]), float(a["t"])) + Vector2(0.5, 0.5)) * CELL

func start_move(a: Dictionary, to: Vector2i, duration: float) -> void:
	a["from"] = a["cell"]
	a["cell"] = to
	a["t"] = 0.0
	a["duration"] = duration

func solid(cell: Vector2i) -> bool:
	return not room()["floor"].has(cell) or room()["water"].has(cell)

func box_at(cell: Vector2i) -> int:
	for index: int in range(room()["boxes"].size()):
		var b: Dictionary = room()["boxes"][index]
		if b["cell"] == cell or (moving(b) and b["from"] == cell):
			return index
	return -1

func enemy_at(cell: Vector2i) -> int:
	for index: int in range(room()["enemies"].size()):
		var e: Dictionary = room()["enemies"][index]
		if e["alive"] and (e["cell"] == cell or (moving(e) and e["from"] == cell)):
			return index
	return -1

func cat_at(cell: Vector2i) -> bool:
	var cat: Dictionary = room()["cat"]
	return not cat.is_empty() and (cat["cell"] == cell or (moving(cat) and cat["from"] == cell))

func _physics_process(delta: float) -> void:
	if not blocked():
		world_clock += delta
		_advance(hero, delta)
		for b: Dictionary in room()["boxes"]:
			_advance(b, delta)
		for e: Dictionary in room()["enemies"]:
			_advance(e, delta)
		if not room()["cat"].is_empty():
			_advance(room()["cat"], delta)
		_contact()
		if not dead:
			_poll_input()
			_tick_enemies(delta)
			_tick_cat(delta)
			_contact()
		_check_win()
	_update_view(delta if not blocked() else 0.0)

func _advance(a: Dictionary, delta: float) -> void:
	a["t"] = minf(1.0, float(a["t"]) + delta / float(a["duration"]))

func _poll_input() -> void:
	var direction: Vector2i = Vector2i.ZERO
	for pair: Array in [["ui_right", Vector2i.RIGHT], ["ui_left", Vector2i.LEFT], ["ui_down", Vector2i.DOWN], ["ui_up", Vector2i.UP]]:
		if Input.is_action_pressed(pair[0]):
			direction = pair[1]
	if release_input:
		if direction == Vector2i.ZERO:
			release_input = false
		return
	if direction != Vector2i.ZERO:
		try_step(direction, Input.is_key_pressed(KEY_SHIFT))

func try_step(direction: Vector2i, pull: bool = false) -> bool:
	if blocked() or moving(hero) or not DIRECTIONS.has(direction):
		return false
	facing = direction
	var to: Vector2i = hero["cell"] + direction
	if solid(to) or cat_at(to):
		return false
	var index: int = box_at(to)
	if index >= 0:
		if not can_push(index, direction):
			return false
	elif pull and relic:
		index = box_at(hero["cell"] - direction)
		if index >= 0 and moving(room()["boxes"][index]):
			return false
	_checkpoint()
	pushing = index >= 0
	if index >= 0:
		if pull and relic and box_at(to) < 0:
			start_move(room()["boxes"][index], hero["cell"], PUSH)
		else:
			_push(index, direction)
		sound(&"push")
	else:
		sound(&"walk", 0.15)
	start_move(hero, to, PUSH if pushing else WALK)
	steps += 1
	return true

func can_push(index: int, direction: Vector2i) -> bool:
	var b: Dictionary = room()["boxes"][index]
	if moving(b):
		return false
	var to: Vector2i = b["cell"] + direction
	if solid(to) or box_at(to) >= 0 or cat_at(to) or to == room().get("chest", Vector2i(-1, -1)):
		return false
	var index_enemy: int = enemy_at(to)
	if index_enemy < 0:
		return true
	var e: Dictionary = room()["enemies"][index_enemy]
	if moving(e):
		return false
	var beyond: Vector2i = to + direction
	if enemy_at(beyond) >= 0 or cat_at(beyond) or beyond == hero["cell"]:
		return false
	if e["boss"] and (not room()["floor"].has(beyond) or box_at(beyond) >= 0):
		return false
	return true

func _push(index: int, direction: Vector2i) -> void:
	var b: Dictionary = room()["boxes"][index]
	var to: Vector2i = b["cell"] + direction
	var index_enemy: int = enemy_at(to)
	if index_enemy >= 0:
		var e: Dictionary = room()["enemies"][index_enemy]
		var beyond: Vector2i = to + direction
		if room()["water"].has(beyond) or not room()["floor"].has(beyond) or box_at(beyond) >= 0:
			e["alive"] = false
			var water_kill: bool = room()["water"].has(beyond)
			sound(&"splash" if water_kill else &"crush")
			effects.append({"pos": position_of(e), "time": 0.65, "color": Color("8bdbe1") if water_kill else Color("eccd8c")})
			notice = "落水！环境击败。" if water_kill else "夹住了！挤压击败。"
		else:
			start_move(e, beyond, PUSH)
			e["wait"] = 2.5
	start_move(b, to, PUSH)

func _tick_enemies(delta: float) -> void:
	for e: Dictionary in room()["enemies"]:
		if not e["alive"] or moving(e):
			continue
		e["wait"] -= delta
		if float(e["wait"]) > 0.0:
			continue
		if has_method("_checkpoint_npc"):
			call("_checkpoint_npc")
		else:
			_checkpoint()
		var to: Vector2i = e["cell"] + e["dir"]
		if to.x < e["low"].x or to.x > e["high"].x or to.y < e["low"].y or to.y > e["high"].y or solid(to) or box_at(to) >= 0 or cat_at(to) or enemy_at(to) >= 0:
			e["dir"] = -Vector2i(e["dir"])
		else:
			start_move(e, to, 0.85)
		e["wait"] = 2.0 if e["boss"] else 1.5

func _tick_cat(delta: float) -> void:
	var cat: Dictionary = room()["cat"]
	if cat.is_empty() or moving(cat):
		return
	cat["wait"] = maxf(float(cat["wait"]) - delta, 0.0)
	if float(cat["wait"]) > 0.0:
		return
	if has_method("_checkpoint_npc"):
		call("_checkpoint_npc")
	else:
		_checkpoint()
	cat["wait"] = 4.0
	var direction: Vector2i = cat["dir"]
	var to: Vector2i = cat["cell"] + direction
	var index: int = box_at(to)
	if solid(to) or enemy_at(to) >= 0 or to == hero["cell"] or (moving(hero) and to == hero["from"]):
		cat["dir"] = DIRECTIONS[(DIRECTIONS.find(direction) + 1) % 4]
		return
	if index >= 0:
		var next: Vector2i = to + direction
		var corner: bool = (solid(next + Vector2i.UP) or solid(next + Vector2i.DOWN)) and (solid(next + Vector2i.LEFT) or solid(next + Vector2i.RIGHT))
		if room()["goals"].has(to) or corner or enemy_at(next) >= 0 or next == hero["cell"] or not can_push(index, direction):
			cat["dir"] = DIRECTIONS[(DIRECTIONS.find(direction) + 1) % 4]
			return
		_push(index, direction)
		sound(&"cat", 2.0)
	start_move(cat, to, 0.7)

func _contact() -> void:
	if dead:
		return
	for e: Dictionary in room()["enemies"]:
		if e["alive"] and position_of(e).distance_to(position_of(hero)) < 36.0:
			dead = true
			notice = "被击倒了 · Z 无限撤销 / R 重开 / Esc 返回菜单"
			sound(&"defeat")
			return

func _checkpoint() -> void:
	history.append({"rooms": rooms.duplicate(true), "room": room_index, "hero": hero.duplicate(true), "facing": facing, "relic": relic, "finished": finished, "clock": world_clock})

func undo() -> bool:
	if guide.is_open() or history.is_empty():
		return false
	var s: Dictionary = history.pop_back()
	rooms.assign(s["rooms"])
	room_index = s["room"]
	hero = s["hero"]
	facing = s["facing"]
	relic = s["relic"]
	finished = s["finished"]
	world_clock = s["clock"]
	dead = false
	paused = true
	release_input = true
	pushing = false
	effects.clear()
	notice = "已回到之前的完整状态 · 空格继续，Z 可继续回退"
	_rebuild_views()
	sound(&"undo")
	return true

func interact() -> void:
	if blocked() or moving(hero):
		return
	var cell: Vector2i = hero["cell"]
	if room_index == 1 and cell.distance_to(room()["chest"]) <= 1.0:
		if room()["chest_open"]:
			return
		for e: Dictionary in room()["enemies"]:
			if e["alive"]:
				notice = "宝箱仍被封印：先击败守卫和小怪。"
				return
		_checkpoint()
		room()["chest_open"] = true
		relic = true
		sound(&"treasure")
		notice = "获得藤蔓手套！Shift + 方向键拉箱；回庭院试试。"
		teach(["relic"], true)
	elif cell.distance_to(room()["portal"]) <= 1.0:
		_checkpoint()
		room()["return"] = hero.duplicate(true)
		room_index = 1 - room_index
		hero = room().get("return", actor(Vector2i(3, 2))).duplicate(true)
		release_input = true
		sound(&"portal")
		_rebuild_views()
		notice = "清除两位守卫，再到东南角宝箱旁按 E。" if room_index == 1 else "已返回庭院：遗物现在可以改变你的解法。"
		if room_index == 1:
			teach(["boss"])

func _check_win() -> void:
	if room_index != 0 or moving(hero) or dead or finished:
		return
	for goal: Vector2i in room()["goals"]:
		if box_at(goal) < 0:
			return
	finished = true
	notice = "庭院修复完成！R 再试一次，Esc 返回主菜单。探索不计常规评分。"
	sound(&"win")

func teach(keys: Array[String], force: bool = false) -> void:
	if tutorials_enabled or force:
		guide.open(keys, force)
		release_input = true

func _build_hud() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	var top: ColorRect = ColorRect.new()
	top.size = Vector2(1280, 74)
	top.color = Color(0.06, 0.14, 0.12, 0.94)
	layer.add_child(top)
	hud = Label.new()
	hud.position = Vector2(22, 12)
	hud.add_theme_font_size_override("font_size", 19)
	hud.add_theme_color_override("font_color", Color("efdbad"))
	layer.add_child(hud)
	var bottom: ColorRect = ColorRect.new()
	bottom.position = Vector2(0, 684)
	bottom.size = Vector2(1280, 84)
	bottom.color = top.color
	layer.add_child(bottom)
	banner = Label.new()
	banner.position = Vector2(22, 696)
	banner.add_theme_font_size_override("font_size", 18)
	banner.add_theme_color_override("font_color", Color("ebcc89"))
	layer.add_child(banner)
	for item: Array in [["图解 H", 888, 0], ["暂停 Space", 1000, 1], ["菜单 Esc", 1140, 2]]:
		var b: Button = Button.new()
		b.text = item[0]
		b.position = Vector2(item[1], 17)
		b.size = Vector2(106 if item[2] != 1 else 132, 40)
		b.focus_mode = Control.FOCUS_NONE
		var action: int = item[2]
		b.pressed.connect(func() -> void:
			if guide.is_open(): return
			if action == 0: teach(["patrol", "crush", "water", "cat", "boss", "relic"], true)
			elif action == 1: toggle_pause()
			else: get_tree().change_scene_to_file("res://campaign.tscn"))
		layer.add_child(b)

func _rebuild_views() -> void:
	for view: Node in box_views + monster_views:
		view.free()
	box_views.clear()
	monster_views.clear()
	if is_instance_valid(cat_view):
		cat_view.free()
	cat_view = null
	for b: Dictionary in room()["boxes"]:
		var sprite: Sprite2D = Sprite2D.new()
		sprite.texture = CRATE
		sprite.z_index = 3
		add_child(sprite)
		box_views.append(sprite)
	for e: Dictionary in room()["enemies"]:
		var view: MonsterView = MonsterView.new()
		view.boss = e["boss"]
		view.z_index = 3
		add_child(view)
		monster_views.append(view)
	if not room()["cat"].is_empty():
		cat_view = CatView.new()
		cat_view.z_index = 3
		add_child(cat_view)

func _update_view(delta: float) -> void:
	player_view.position = position_of(hero)
	player_view.modulate = Color("cf7674") if dead else Color.WHITE
	player_view.sample(facing, moving(hero) and not dead, pushing, delta)
	for i: int in range(box_views.size()):
		var b: Dictionary = room()["boxes"][i]
		box_views[i].position = position_of(b)
		box_views[i].texture = DONE if room()["goals"].has(b["cell"]) else CRATE
	for i: int in range(monster_views.size()):
		var e: Dictionary = room()["enemies"][i]
		monster_views[i].position = position_of(e)
		monster_views[i].animate(delta, e["alive"], e["dir"])
	if cat_view != null:
		cat_view.position = position_of(room()["cat"])
		cat_view.animate(delta, moving(room()["cat"]))
	var size: Vector2 = Vector2(room()["size"]) * CELL
	camera.position = Vector2(clampf(player_view.position.x, 640, maxf(640, size.x - 640)), clampf(player_view.position.y, 384, maxf(384, size.y - 384)))
	var filled: int = 0
	for goal: Vector2i in room()["goals"]:
		if box_at(goal) >= 0: filled += 1
	var objective: String = "藤蔓手套：Shift 拉箱" if relic else "击败两位守卫 → E 开宝箱" if room_index else "目标 %d / %d" % [filled, room()["goals"].size()]
	hud.text = "%s  ·  %s\nWASD / 方向键移动 · E 交互 · Z 撤销 · R 重开" % ["藤洞温室" if room_index else "苔庭探险 · 测试", objective]
	banner.text = notice + "\n" + ("世界已暂停 · 空格继续" if paused else "无限撤销  |  慢速巡逻  |  可选隐藏探索，不影响主线存档")
	for fx: Dictionary in effects:
		fx["time"] -= delta
	effects = effects.filter(func(fx: Dictionary) -> bool: return fx["time"] > 0)
	queue_redraw()

func toggle_pause() -> void:
	if dead or finished: return
	paused = not paused
	release_input = true

func _unhandled_input(event: InputEvent) -> void:
	if guide.is_open() or not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_Z: undo()
		KEY_SPACE: toggle_pause()
		KEY_E: interact()
		KEY_H: teach(["patrol", "crush", "water", "cat", "boss", "relic"], true)
		KEY_R: get_tree().reload_current_scene()
		KEY_ESCAPE: get_tree().change_scene_to_file("res://campaign.tscn")
		_: return
	get_viewport().set_input_as_handled()

func sound(key: StringName, throttle: float = 0.0) -> void:
	var audio: Node = get_node_or_null("/root/GameAudio")
	if audio != null: audio.call("play", key, throttle)

func _draw() -> void:
	if rooms.is_empty(): return
	var r: Dictionary = room()
	draw_rect(Rect2(Vector2.ZERO, Vector2(r["size"]) * CELL), Color("192d2a"))
	for y: int in range(r["size"].y):
		for x: int in range(r["size"].x):
			var cell: Vector2i = Vector2i(x, y)
			var pos: Vector2 = Vector2(cell) * CELL
			if not r["floor"].has(cell):
				draw_texture_rect(WALL if x + y > 4 else ROCK, Rect2(pos, Vector2(64, 64)), false)
				continue
			draw_rect(Rect2(pos + Vector2(1, 1), Vector2(62, 62)), Color("47655b") if (x + y) % 2 else Color("4b695d"))
			draw_rect(Rect2(pos + Vector2(4, 4), Vector2(55, 2)), Color("698271"))
			if (x * 11 + y * 5) % 7 == 0:
				for leaf: int in range(3):
					draw_rect(Rect2(pos + Vector2(5 + leaf * 4, 53 - leaf % 2 * 4), Vector2(3, 8)), Color("849666"))
				if (x + y) % 3 == 0:
					draw_rect(Rect2(pos + Vector2(8, 49), Vector2(4, 4)), Color("c4a6a0"))
			if (x * 7 + y * 3) % 11 == 0:
				draw_rect(Rect2(pos + Vector2(7, 48), Vector2(11, 3)), Color("9aa873"))
			if r["water"].has(cell):
				draw_rect(Rect2(pos, Vector2(64, 64)), Color("326a83"))
				for wave: int in range(3):
					draw_rect(Rect2(pos + Vector2(5 + posmod(int(world_clock * 12) + wave * 8, 20), 10 + wave * 18), Vector2(26, 3)), Color("89c6c8"))
	for goal: Vector2i in r["goals"]:
		draw_texture(GOAL, Vector2(goal) * CELL)
	for e: Dictionary in r["enemies"]:
		if e["alive"]:
			var next: Vector2 = Vector2(e["cell"] + e["dir"]) * CELL
			draw_rect(Rect2(next + Vector2(4, 4), Vector2(56, 56)), Color(0.87, 0.43, 0.42, 0.18))
	var portal: Vector2 = Vector2(r["portal"]) * CELL
	draw_texture(Art.texture("portal"), portal)
	draw_string(ThemeDB.fallback_font, portal + Vector2(-16, -8), "E 返回" if room_index else "E 隐藏入口", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("f4dba3"))
	if room_index == 1:
		var at: Vector2 = Vector2(r["chest"]) * CELL
		draw_texture(Art.texture("relic" if r["chest_open"] else "chest"), at)
		draw_string(ThemeDB.fallback_font, at + Vector2(-12, -8), "E 宝箱", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("f4dba3"))
	if cat_view != null:
		var p: Vector2 = position_of(r["cat"])
		var d: Vector2 = Vector2(r["cat"]["dir"])
		draw_line(p + Vector2(0, -40), p + Vector2(0, -40) + d * 22, Color("efdaac"), 3)
	for fx: Dictionary in effects:
		for i: int in range(8):
			var a: float = TAU * i / 8.0
			var p: Vector2 = fx["pos"] + Vector2(cos(a), sin(a)) * (1.0 - fx["time"]) * 70
			draw_rect(Rect2(p.round(), Vector2(6, 6)), fx["color"])
