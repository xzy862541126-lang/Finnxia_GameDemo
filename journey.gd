extends Node2D

const Catalog = preload("res://journey_catalog.gd")
const Level = preload("res://journey_level.gd")
const Store = preload("res://journey_save.gd")
const Grade = preload("res://rank_badge.gd")
const GardenArt = preload("res://garden_art.gd")
@export var save_path: String = "user://original_nine_v2.save"
@export var tutorials_enabled: bool = true
var store: Store = Store.new()
var level: Level
var art: GardenArt
var ui: Control
var modal: Control
var screen: String = "menu"
var modal_kind: String = ""
var definitions: Array[Dictionary]
var elapsed: float = 0.0
var message: String = "原九关布局已恢复。本版独立存档，之前的试玩进度保留不覆盖。"

func _ready() -> void:
	get_tree().auto_accept_quit = false
	for i: int in range(9): definitions.append(Catalog.build(i))
	store.path = save_path
	store.load_save()
	if not store.error_text.is_empty(): message = store.error_text
	art = GardenArt.new()
	art.menu_mode = true
	add_child(art)
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 60
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = _theme()
	layer.add_child(ui)
	show_menu(false)

func _theme() -> Theme:
	var theme: Theme = Theme.new()
	theme.default_font_size = 20
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = Color("254c3f") if state == "normal" else Color("386653")
		style.border_color = Color("9b9b71")
		if state == "disabled":
			style.bg_color = Color("23372f")
			style.border_color = Color("506455")
		style.set_border_width_all(2)
		style.set_corner_radius_all(3)
		theme.set_stylebox(state, "Button", style)
	theme.set_color("font_color", "Button", Color("eed8a8"))
	theme.set_color("font_disabled_color", "Button", Color("778b7d"))
	return theme

func text(parent: Node, value: String, at: Vector2, extent: Vector2, font_size: int = 20) -> Label:
	var label: Label = Label.new()
	label.text = value
	label.position = at
	label.size = extent
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("ebd5a3"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func button(parent: Node, value: String, rect: Rect2, action: Callable, disabled: bool = false) -> Button:
	var b: Button = Button.new()
	b.text = value
	b.position = rect.position
	b.size = rect.size
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = disabled
	b.pressed.connect(func() -> void:
		sound(&"ui_click")
		action.call_deferred())
	parent.add_child(b)
	return b

func _clear() -> void:
	for child: Node in ui.get_children():
		ui.remove_child(child)
		child.queue_free()
	modal = null
	modal_kind = ""

func discard_level() -> void:
	_discard_level()

func load_definition(index: int) -> void:
	store.new_run()
	store.data["unlocked"] = 9
	load_level(index)

func _discard_level() -> void:
	if is_instance_valid(level):
		remove_child(level)
		level.queue_free()
	level = null

func show_menu(persist: bool = true) -> void:
	if persist and is_instance_valid(level):
		level.paused = true
		save_active()
	_discard_level()
	_clear()
	screen = "menu"
	art.show()
	art.revival_stage = mini(3, store.data.get("completed", {}).size() / 3)
	text(ui, "MOSS & CRATES / 九关花园旅程", Vector2(76, 88), Vector2(540, 34), 19)
	text(ui, "苔庭搬运记", Vector2(70, 143), Vector2(560, 85), 58)
	text(ui, "推箱交货，开花搭桥，探索隐藏温室。", Vector2(76, 245), Vector2(535, 40), 24)
	text(ui, "由易到难的九关主线 · 遗物可带到下一关", Vector2(76, 293), Vector2(535, 30), 18)
	var has_save: bool = not store.data.is_empty()
	button(ui, "继续旅程" if not store.data.get("finished", false) else "查看通关成绩", Rect2(76, 349, 448, 54), continue_game, not has_save)
	button(ui, "重新游玩" if has_save else "开始游戏", Rect2(76, 419, 448, 54), request_new)
	button(ui, "关卡手册", Rect2(76, 489, 215, 50), show_select)
	button(ui, "声音设置", Rect2(309, 489, 215, 50), show_audio)
	button(ui, "退出游戏", Rect2(76, 557, 448, 48), request_quit)
	text(ui, message, Vector2(76, 626), Vector2(484, 62), 16)
	text(ui, "不再分开试玩 · 一个入口完成整段旅程", Vector2(748, 640), Vector2(430, 70), 21)

func request_new() -> void:
	if store.data.is_empty():
		start_new()
		return
	var card: Control = dialog("重新开始？", "只重置这条九关旅程的进度、遗物和成绩。旧版存档不受影响。", "new")
	button(card, "取消", Rect2(30, 242, 240, 48), close_modal)
	button(card, "确认重新开始", Rect2(298, 242, 282, 48), start_new)

func start_new() -> void:
	store.new_run()
	load_level(0)

func continue_game() -> void:
	if store.data.is_empty(): return
	if store.data["finished"]: show_ending()
	else: load_level(store.data["current"], true)

func load_level(index: int, resume: bool = false) -> void:
	if store.data.is_empty() or index < 0 or index >= 9 or index >= store.data["unlocked"]: return
	var state: Dictionary = store.data["active"].duplicate(true) if resume else {}
	_discard_level()
	_clear()
	art.hide()
	screen = "playing"
	level = Level.new()
	level.definition = definitions[index]
	level.set_meta("hud_theme", ui.theme)
	level.start_relic = store.data["relic"]
	level.seen_guides = store.data["seen"]
	level.tutorials_enabled = tutorials_enabled
	level.completed.connect(_on_completed, CONNECT_DEFERRED)
	level.exit_requested.connect(show_pause, CONNECT_DEFERRED)
	level.restart_requested.connect(request_restart, CONNECT_DEFERRED)
	level.save_requested.connect(save_active)
	add_child(level)
	store.data["current"] = index
	if not state.is_empty() and not level.restore_state(state):
		level.notice = "这份关卡断点已失效，本关从头开始；通关记录仍保留。"
	if not level.dead and not level.finished:
		level.paused = false
		level.release_input = true
	if level.finished:
		_on_completed.call_deferred()
	else:
		level.begin_tutorial()
	save_active()

func save_active() -> bool:
	if not is_instance_valid(level): return false
	store.data["active"] = level.capture_state()
	store.data["seen"] = level.guide.seen.duplicate()
	var ok: bool = store.write_save()
	level.save_label.text = "已保存到本机" if ok else store.error_text
	level.dirty = not ok
	if not ok: message = store.error_text
	return ok

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= 10.0:
		elapsed = 0.0
		if is_instance_valid(level) and level.dirty: save_active()

func dialog(title: String, description: String, kind: String) -> Control:
	close_modal(false)
	if is_instance_valid(level): level.paused = true
	modal_kind = kind
	modal = Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(modal)
	var shade: ColorRect = ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.02, 0.06, 0.06, 0.85)
	modal.add_child(shade)
	var card: Panel = Panel.new()
	card.position = Vector2(330, 213)
	card.size = Vector2(620, 328)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color("193b32")
	style.border_color = Color("c2af7e")
	style.set_border_width_all(3)
	card.add_theme_stylebox_override("panel", style)
	modal.add_child(card)
	text(card, title, Vector2(30, 26), Vector2(560, 55), 32)
	text(card, description, Vector2(30, 98), Vector2(560, 130), 20)
	return card

func close_modal(resume: bool = true) -> void:
	if is_instance_valid(modal):
		ui.remove_child(modal)
		modal.queue_free()
	modal = null
	modal_kind = ""
	if resume and is_instance_valid(level):
		level.paused = false
		level.release_input = true

func show_pause() -> void:
	if not is_instance_valid(level) or level.guide.is_open(): return
	if level.finished:
		_on_completed()
		return
	var card: Control = dialog("休息一下", "进度会保存在这条旅程里。返回后可以继续推箱、探索和撤销。", "pause")
	button(card, "继续游戏", Rect2(30, 242, 240, 48), close_modal)
	button(card, "保存并回主菜单", Rect2(298, 242, 282, 48), show_menu)

func request_restart() -> void:
	if not is_instance_valid(level) or level.guide.is_open(): return
	var card: Control = dialog("重开本关？", "本关箱子、机关、怪物和隐藏探索会重置。此前关卡获得的遗物仍保留。", "restart")
	button(card, "取消", Rect2(30, 242, 240, 48), close_modal)
	button(card, "重开本关", Rect2(298, 242, 282, 48), func() -> void: load_level(store.data["current"]))

func _on_completed() -> void:
	if not is_instance_valid(level) or not level.finished: return
	var i: int = store.data["current"]
	var key: String = str(i)
	var best: Dictionary = store.data["completed"].get(key, {})
	if best.is_empty() or level.steps < best["steps"]:
		store.data["completed"][key] = {"steps": level.steps}
	store.data["unlocked"] = maxi(store.data["unlocked"], mini(9, i + 2))
	store.data["relic"] = level.relic
	store.data["finished"] = store.data["completed"].size() == 9
	save_active()
	var rank: String = Grade.grade(level.steps, definitions[i]["reference"])
	var summary: String = "共用 %d 步，参考 %d 步。\n所有货箱已到位。" % [level.steps, definitions[i]["reference"]]
	if level.exploration_steps > 0 and level.rooms.size() > 1:
		summary += "\n隐藏探索 %d 步，不计评分。" % level.exploration_steps
	if level.relic: summary += "\n手套可带到后续关卡。"
	var card: Control = dialog("本关完成！", summary, "win")
	for child: Node in card.get_children():
		if child is Label and child.position.y > 90: child.size.x = 350
	var badge: Grade = Grade.new()
	badge.name = "RankBadge"
	badge.rank = rank
	badge.position = Vector2(414, 34)
	card.add_child(badge)
	button(card, "主菜单", Rect2(30, 242, 145, 48), show_menu)
	button(card, "再玩一次", Rect2(187, 242, 155, 48), func() -> void: load_level(i))
	button(card, "查看总成绩" if i == 8 else "下一关", Rect2(354, 242, 226, 48), show_ending if i == 8 else func() -> void: load_level(i + 1))

func show_ending() -> void:
	if store.data.get("completed", {}).size() != 9: return
	_discard_level()
	_clear()
	screen = "ending"
	art.show()
	art.revival_stage = 3
	var total: int = 0
	var reference: int = 0
	for i: int in range(9):
		total += store.data["completed"][str(i)]["steps"]
		reference += definitions[i]["reference"]
	text(ui, "花园旅程 · 全部完成", Vector2(76, 130), Vector2(600, 90), 46)
	text(ui, "开花、搭桥、交货，九座庭院重新亮起。", Vector2(76, 245), Vector2(560, 76), 23)
	text(ui, "九关最佳成绩\n共用 %d 步，参考 %d 步。" % [total, reference], Vector2(76, 350), Vector2(400, 126), 24)
	var badge: Grade = Grade.new()
	badge.rank = Grade.grade(total, reference)
	badge.position = Vector2(477, 306)
	ui.add_child(badge)
	button(ui, "返回主菜单", Rect2(76, 514, 448, 54), func() -> void: show_menu(false))
	button(ui, "重新开始旅程", Rect2(76, 588, 448, 54), request_new)
	sound(&"finale")

func show_select() -> void:
	_clear()
	screen = "select"
	art.hide()
	var backdrop: ColorRect = ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color("172d29")
	ui.add_child(backdrop)
	text(ui, "九关花园旅程", Vector2(60, 28), Vector2(900, 70), 40)
	text(ui, "基础推箱 → 开花搭桥 → 园丁猫 → 隐藏探索 → 综合交货", Vector2(64, 105), Vector2(1140, 38), 21)
	var unlocked: int = store.data.get("unlocked", 1)
	for i: int in range(9):
		var description: String = definitions[i]["title"] + "\n" + definitions[i]["hint"]
		if store.data.get("completed", {}).has(str(i)):
			description += "\n最佳 " + Grade.grade(store.data["completed"][str(i)]["steps"], definitions[i]["reference"])
		var index: int = i
		var b: Button = button(ui, description, Rect2(60 + i % 3 * 390, 176 + int(i / 3.0) * 143, 370, 122), func() -> void: select_level(index), i >= unlocked)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 18)
	button(ui, "返回主菜单", Rect2(60, 652, 260, 50), func() -> void: show_menu(false))

func select_level(index: int) -> void:
	if store.data.is_empty(): store.new_run()
	if not store.data["active"].is_empty():
		var card: Control = dialog("从头进入这关？", "当前关卡的断点将替换，解锁进度、最佳成绩和已带出的遗物会保留。", "select")
		button(card, "取消", Rect2(30, 242, 240, 48), close_modal)
		button(card, "进入关卡", Rect2(298, 242, 282, 48), func() -> void: load_level(index))
	else: load_level(index)

func show_audio() -> void:
	var audio: Node = get_node_or_null("/root/GameAudio")
	var enabled: bool = audio != null and audio.enabled
	var card: Control = dialog("声音设置", "当前：" + ("开启" if enabled else "静音") + "\n推箱、开门、搭桥、危险和宝箱均有音效提示。", "audio")
	button(card, "切换声音", Rect2(30, 242, 240, 48), func() -> void:
		if audio != null: audio.set_enabled(not audio.enabled)
		show_audio())
	button(card, "关闭", Rect2(298, 242, 282, 48), close_modal)

func request_quit() -> void:
	if is_instance_valid(level): save_active()
	get_tree().quit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST: request_quit()

func _input(event: InputEvent) -> void:
	if not is_instance_valid(modal): return
	if event is InputEventMouse or event is InputEventScreenTouch or event is InputEventScreenDrag: return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and modal_kind != "win": close_modal()
	get_viewport().set_input_as_handled()

func sound(key: StringName) -> void:
	var audio: Node = get_node_or_null("/root/GameAudio")
	if audio != null: audio.call("play", key)
