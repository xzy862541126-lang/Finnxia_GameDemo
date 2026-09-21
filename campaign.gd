extends Node2D

const Catalog = preload("res://campaign_catalog.gd")
const LevelController = preload("res://level.gd")
const SaveStore = preload("res://save_store.gd")
const GardenArt = preload("res://garden_art.gd")
const GardenChapter = preload("res://garden_chapter.gd")
var garden_mode: bool = false
var classic_store: SaveStore
var garden_store: SaveStore = SaveStore.new()
const GOLD: Color = Color("edd39c")
const INK: Color = Color("132d2c")
const MUTED: Color = Color("a9c1b2")

@export var save_path: String = "user://garden_campaign.json"
var store: SaveStore = SaveStore.new()
var level: LevelController
var current_index: int = 0
var screen: String = "menu"
var modal_kind: String = ""
var entries: Array[Dictionary] = []
var ui: Control
var modal: Control
var menu_art: GardenArt
var save_hint: Label
var _ui_theme: Theme
var _save_queued: bool = false

func _ready() -> void:
	get_tree().auto_accept_quit = false
	entries = Catalog.entries()
	store.path = save_path
	store.load_save()
	classic_store = store
	garden_store.path = save_path + ".restoration"
	garden_store.level_count = 3
	garden_store.load_save()
	_ui_theme = _make_theme()
	menu_art = GardenArt.new()
	menu_art.menu_mode = true
	add_child(menu_art)
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = _ui_theme
	layer.add_child(ui)
	show_menu(false)

func _make_theme() -> Theme:
	var result: Theme = Theme.new()
	result.default_font_size = 20
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box: StyleBoxFlat = StyleBoxFlat.new()
		box.bg_color = Color("23483e") if state == "normal" else Color("356650")
		if state == "disabled":
			box.bg_color = Color("253b35")
		box.border_color = Color("71885d") if state != "focus" else GOLD
		box.set_border_width_all(2)
		box.set_corner_radius_all(3)
		box.content_margin_left = 18
		box.content_margin_right = 18
		box.content_margin_top = 10
		box.content_margin_bottom = 10
		result.set_stylebox(state, "Button", box)
	result.set_color("font_color", "Button", GOLD)
	result.set_color("font_hover_color", "Button", Color("fff4cd"))
	result.set_color("font_disabled_color", "Button", Color("708576"))
	result.set_color("font_color", "Label", GOLD)
	return result

func _clear_ui() -> void:
	for child: Node in ui.get_children():
		ui.remove_child(child)
		child.queue_free()
	modal = null
	modal_kind = ""
	save_hint = null

func _label(parent: Node, text: String, rect: Rect2, font_size: int = 20, color: Color = GOLD) -> Label:
	var label: Label = Label.new()
	label.position = rect.position
	label.size = rect.size
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, rect: Rect2, callback: Callable, disabled: bool = false) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.position = rect.position
	button.size = rect.size
	button.disabled = disabled
	button.pressed.connect(func() -> void:
		GameAudio.play(&"ui_click", 0.02)
		callback.call_deferred())
	button.mouse_entered.connect(func() -> void:
		if not button.disabled:
			GameAudio.play(&"ui_hover", 0.03))
	parent.add_child(button)
	return button

func _panel(parent: Node, rect: Rect2) -> Panel:
	var panel: Panel = Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color("162f2d")
	style.border_color = Color("8f9060")
	style.set_border_width_all(3)
	style.set_corner_radius_all(4)
	style.shadow_color = Color(0.02, 0.06, 0.06, 0.5)
	style.shadow_size = 12
	style.shadow_offset = Vector2(0, 6)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel

func _discard_level() -> void:
	if is_instance_valid(level):
		remove_child(level)
		level.queue_free()
	level = null

func show_menu(persist: bool = true) -> void:
	if is_instance_valid(level) and persist:
		level.set_modal(true)
		_save_active()
	_discard_level()
	garden_mode = false
	store = classic_store
	entries = Catalog.entries()
	screen = "menu"
	_clear_ui()
	menu_art.visible = true
	menu_art.theme_index = 0
	menu_art.revival_stage = (garden_store.data.get("completed", {}) as Dictionary).size()
	_label(ui, "MOSS & CRATES  /  森林搬运委托", Rect2(72, 104, 520, 30), 18, MUTED)
	_label(ui, "苔庭搬运记", Rect2(68, 148, 570, 80), 60)
	_label(ui, "把每一份小小的货物，送到它的星光里。", Rect2(76, 252, 520, 36), 21, MUTED)
	_label(ui, "9 座庭院  ·  四季像素花园  ·  一步一步解开谜题", Rect2(76, 294, 535, 30), 17, MUTED)
	var continue_text: String = "继续游戏"
	if store.has_save():
		continue_text = "继续游戏  ·  第 %02d 关" % (int(store.data["current"]) + 1)
		if store.data["finished"]:
			continue_text = "查看通关纪念"
	_button(ui, continue_text, Rect2(76, 349, 448, 54), continue_game, not store.has_save())
	_button(ui, "开始游戏" if not store.has_save() else "重新游玩", Rect2(76, 419, 448, 54), request_new_game)
	_button(ui, "关卡手册", Rect2(76, 489, 215, 52), show_level_select)
	_button(ui, "本机存档", Rect2(309, 489, 215, 52), show_save_info)
	_button(ui, "退出", Rect2(76, 557, 448, 48), request_exit)
	_button(ui, "音效设置", Rect2(76, 656, 215, 44), show_audio_settings)
	_garden_bookmark()
	var message: String = "%d / 9 份委托已完成" % (store.data.get("completed", {}) as Dictionary).size()
	if not store.last_error.is_empty():
		message = store.last_error
	elif store.recovered:
		message = "已从本机备份恢复进度。"
	elif store.data.has("upgrade_notice"):
		message = str(store.data["upgrade_notice"])
	_label(ui, message, Rect2(76, 624, 448, 28), 17, MUTED)
	var card: Panel = _panel(ui, Rect2(747, 567, 430, 118))
	_label(card, "一只箱子，一段旅程", Rect2(24, 15, 390, 35), 26)
	_label(card, "方向键 / WASD   ·   Z 撤销   ·   R 重开", Rect2(24, 65, 390, 26), 17, MUTED)

func _garden_bookmark() -> void:
	var bookmark: Button = Button.new()
	bookmark.text = ""
	bookmark.position = Vector2(588, 0)
	bookmark.size = Vector2(68, 176)
	bookmark.focus_mode = Control.FOCUS_NONE
	bookmark.pivot_offset = Vector2(34, 0)
	var glow: ColorRect = ColorRect.new()
	glow.color = Color(0.99, 0.86, 0.45, 0.0)
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bookmark.add_child(glow)
	var hover_tween: Tween
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color("d8b13f")
	style.border_color = Color("8a6a1c")
	style.set_border_width_all(2)
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0
	style.corner_radius_top_left = 0
	style.corner_radius_top_right = 0
	bookmark.add_theme_stylebox_override("normal", style)
	var hover: StyleBoxFlat = style.duplicate()
	hover.bg_color = Color("f0cd5e")
	hover.border_color = Color("6b4f10")
	bookmark.add_theme_stylebox_override("hover", hover)
	var pressed: StyleBoxFlat = style.duplicate()
	pressed.bg_color = Color("c19a2e")
	bookmark.add_theme_stylebox_override("pressed", pressed)
	bookmark.mouse_entered.connect(func() -> void:
		GameAudio.play(&"ui_hover", 0.03)
		if hover_tween != null:
			hover_tween.kill()
		hover_tween = create_tween().set_parallel(true)
		hover_tween.tween_property(bookmark, "scale", Vector2(1.06, 1.06), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		hover_tween.tween_property(glow, "color:a", 0.28, 0.12))
	bookmark.mouse_exited.connect(func() -> void:
		if hover_tween != null:
			hover_tween.kill()
		hover_tween = create_tween().set_parallel(true)
		hover_tween.tween_property(bookmark, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		hover_tween.tween_property(glow, "color:a", 0.0, 0.16))
	bookmark.button_down.connect(func() -> void:
		if hover_tween != null:
			hover_tween.kill()
		bookmark.scale = Vector2(0.97, 0.97)
		glow.color.a = 0.36)
	bookmark.button_up.connect(func() -> void:
		bookmark.scale = Vector2(1.06, 1.06))
	bookmark.pressed.connect(func() -> void:
		GameAudio.play(&"ui_click", 0.02)
		show_garden_select())
	ui.add_child(bookmark)
	# Pixel ribbon, wreath and drop shadow are painted on the bookmark itself.
	bookmark.draw.connect(func() -> void:
		var body: Rect2 = Rect2(Vector2(3, 3), Vector2(62, 160))
		bookmark.draw_rect(Rect2(Vector2(6, 8), Vector2(62, 160)), Color(0.02, 0.04, 0.02, 0.55))
		bookmark.draw_rect(body, Color("e6c14b"))
		bookmark.draw_rect(Rect2(Vector2(6, 6), Vector2(56, 3)), Color("f7e08b"))
		bookmark.draw_rect(Rect2(Vector2(6, 6), Vector2(3, 152)), Color("f7e08b"))
		bookmark.draw_rect(Rect2(Vector2(59, 9), Vector2(3, 148)), Color("9a7420"))
		var thread: Color = Color("8a6a1c")
		# Lantern charm hangs from the ribbon knot and glows warm.
		bookmark.draw_rect(Rect2(Vector2(30, 4), Vector2(8, 10)), thread)
		bookmark.draw_rect(Rect2(Vector2(28, 6), Vector2(12, 3)), thread.lightened(0.3))
		for knot: int in range(2):
			bookmark.draw_rect(Rect2(Vector2(31, 13 + knot * 4), Vector2(6, 3)), thread.darkened(0.15))
		bookmark.draw_rect(Rect2(Vector2(26, 16), Vector2(16, 5)), Color("5c4313"))
		bookmark.draw_rect(Rect2(Vector2(25, 21), Vector2(18, 12)), Color("7a5a1a"))
		bookmark.draw_rect(Rect2(Vector2(27, 23), Vector2(14, 8)), Color("fff3b0"))
		bookmark.draw_rect(Rect2(Vector2(29, 25), Vector2(10, 4)), Color("ffffff"))
		bookmark.draw_rect(Rect2(Vector2(25, 33), Vector2(18, 3)), Color("5c4313"))
		bookmark.draw_rect(Rect2(Vector2(20, 22), Vector2(4, 12)), Color(1.0, 0.93, 0.62, 0.25))
		bookmark.draw_rect(Rect2(Vector2(44, 22), Vector2(4, 12)), Color(1.0, 0.93, 0.62, 0.25))
		bookmark.draw_rect(Rect2(Vector2(22, 18), Vector2(3, 20)), Color(1.0, 0.9, 0.55, 0.16))
		bookmark.draw_rect(Rect2(Vector2(43, 18), Vector2(3, 20)), Color(1.0, 0.9, 0.55, 0.16))
		var notch: Color = Color("9a7420")
		bookmark.draw_rect(Rect2(Vector2(3, 92), Vector2(7, 4)), notch)
		bookmark.draw_rect(Rect2(Vector2(58, 116), Vector2(7, 4)), notch)
		var tip: PackedVector2Array = PackedVector2Array([Vector2(5, 161), Vector2(34, 174), Vector2(63, 161)])
		bookmark.draw_colored_polygon(tip, Color("e6c14b"))
		bookmark.draw_polyline(tip, Color("9a7420"), 2)
		bookmark.draw_rect(Rect2(Vector2(20, 136), Vector2(28, 3)), thread))
	var title: Label = Label.new()
	title.text = "花园\n修复篇"
	title.position = Vector2(8, 48)
	title.size = Vector2(52, 58)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color("3a2a12"))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bookmark.add_child(title)
	var done: Label = Label.new()
	done.text = "%d/3" % (garden_store.data.get("completed", {}) as Dictionary).size()
	done.position = Vector2(0, 108)
	done.size = Vector2(68, 22)
	done.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	done.add_theme_font_size_override("font_size", 14)
	done.add_theme_color_override("font_color", Color("6b4f10"))
	done.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bookmark.add_child(done)
	# The fresh badge floats outside the bookmark, overlapping the cover edge.
	var fresh: Button = Button.new()
	fresh.text = "新"
	fresh.position = Vector2(668, 6)
	fresh.size = Vector2(30, 30)
	fresh.focus_mode = Control.FOCUS_NONE
	fresh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge_style: StyleBoxFlat = StyleBoxFlat.new()
	badge_style.bg_color = Color("d95f68")
	badge_style.border_color = Color("8c3f4e")
	badge_style.set_border_width_all(2)
	badge_style.set_corner_radius_all(4)
	fresh.add_theme_stylebox_override("normal", badge_style)
	fresh.add_theme_stylebox_override("hover", badge_style)
	fresh.add_theme_stylebox_override("pressed", badge_style)
	fresh.add_theme_stylebox_override("disabled", badge_style)
	fresh.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	fresh.add_theme_font_size_override("font_size", 14)
	fresh.add_theme_color_override("font_color", Color("fff6d4"))
	ui.add_child(fresh)

func request_new_game() -> void:
	if not store.has_save():
		start_new_game()
		return
	var card: Panel = _dialog("重新开始这段旅程？", "当前冒险进度、关卡纪录和存档将被重置。", "confirm_new")
	_button(card, "取消", Rect2(40, 270, 260, 54), close_modal)
	_button(card, "确认重新游玩", Rect2(320, 270, 280, 54), start_new_game)

func start_new_game() -> void:
	store.new_run()
	load_level(0)

func continue_game() -> void:
	if not store.has_save():
		return
	if store.data["finished"]:
		show_ending()
	else:
		load_level(int(store.data["current"]), true)

func load_level(index: int, resume: bool = false) -> void:
	if not store.has_save() or index < 0 or index >= entries.size() or index >= int(store.data["unlocked"]):
		return
	var snapshot: Dictionary = store.data["active"].duplicate(true) if resume else {}
	_discard_level()
	_clear_ui()
	menu_art.visible = false
	screen = "playing"
	current_index = index
	level = (GardenChapter.create_level(index) if garden_mode else Catalog.create_level(index)) as LevelController
	add_child(level)
	var restored: bool = snapshot.is_empty() or level.restore_state(snapshot)
	level.puzzle_completed.connect(_on_completed, CONNECT_DEFERRED)
	level.state_changed.connect(_queue_save)
	level.player.wait_for_release = true
	store.data["current"] = index
	store.data["finished"] = false
	_draw_header()
	_save_active()
	if not restored:
		save_hint.text = "进度与关卡不匹配，已安全重开本关。"
	if level.board.is_solved():
		_on_completed.call_deferred()

func _draw_header() -> void:
	var heading: Dictionary = entries[current_index]
	_label(ui, "%02d / %02d  ·  %s" % [current_index + 1, entries.size(), heading["title"]], Rect2(28, 9, 620, 32), 25)
	_label(ui, str(heading["subtitle"]), Rect2(28, 43, 660, 25), 16, MUTED)
	save_hint = _label(ui, "每一步自动保存", Rect2(740, 17, 150, 26), 15, MUTED)
	_button(ui, "音效", Rect2(900, 12, 84, 42), toggle_audio)
	_button(ui, "保存", Rect2(998, 12, 94, 42), manual_save)
	_button(ui, "菜单 Esc", Rect2(1104, 12, 146, 42), show_pause)

func toggle_audio() -> void:
	GameAudio.set_enabled(not GameAudio.enabled)
	show_audio_settings()

func show_audio_settings() -> void:
	var card: Panel = _dialog("花园的声音", "当前状态：%s    音量：%d dB" % ["开启" if GameAudio.enabled else "静音", int(GameAudio.volume_db)], "audio")
	var note: Label = _label(card, "关闭后游戏仍会完整记录成绩。", Rect2(40, 205, 560, 26), 16, MUTED)
	_button(card, "开启 / 静音", Rect2(40, 250, 260, 52), func() -> void: toggle_audio())
	_button(card, "音量 +", Rect2(320, 250, 130, 52), func() -> void:
		GameAudio.set_volume_db(GameAudio.volume_db + 3.0)
		show_audio_settings())
	_button(card, "音量 −", Rect2(468, 250, 130, 52), func() -> void:
		GameAudio.set_volume_db(GameAudio.volume_db - 3.0)
		show_audio_settings())
	_button(card, "试听", Rect2(40, 310, 268, 50), func() -> void: GameAudio.play(&"ui_confirm", 0.0))
	_button(card, "关闭", Rect2(330, 310, 268, 50), close_modal)

func show_garden_select() -> void:
	if is_instance_valid(level):
		level.set_modal(true)
		_save_active()
	_discard_level()
	garden_mode = true
	store = garden_store
	entries = GardenChapter.entries()
	_clear_ui()
	screen = "garden_select"
	menu_art.visible = true
	menu_art.revival_stage = (store.data.get("completed", {}) as Dictionary).size()
	var backdrop: ColorRect = ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.025, 0.075, 0.065, 0.55)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(backdrop)
	_label(ui, "花园修复篇", Rect2(72, 44, 750, 66), 44)
	_label(ui, "让推箱子改变花园：开花开路 → 木料搭桥 → 组合修复", Rect2(76, 120, 1080, 34), 21, MUTED)
	_label(ui, "独立三关试玩，不覆盖标准九关存档。成功撤销仍 +1 步，并还原整步机关变化。", Rect2(76, 161, 1120, 32), 18, MUTED)
	var unlocked: int = int(store.data.get("unlocked", 1))
	var notes: Array[String] = ["粉色花坛点亮后，藤门本局常开。", "蓝绳木料箱入水成桥，不计交货目标。", "先临时挪开货箱，给桥材留出空间。"]
	for index: int in range(entries.size()):
		var card: Panel = _panel(ui, Rect2(76 + index * 380, 259, 352, 249))
		_label(card, "%02d  %s" % [index + 1, entries[index]["title"]], Rect2(19, 24, 318, 44), 25)
		var note: Label = _label(card, notes[index], Rect2(20, 82, 306, 72), 20, MUTED)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_button(card, "已完成 · 再次修复" if (store.data.get("completed", {}) as Dictionary).has(str(index)) else "开始修复" if index < unlocked else "完成前一关解锁", Rect2(20, 177, 310, 52), func() -> void: _select_level(index), index >= unlocked)
	_button(ui, "继续修复存档", Rect2(76, 560, 350, 55), continue_game, not store.has_save())
	_button(ui, "返回主菜单", Rect2(76, 648, 280, 53), func() -> void: show_menu(false))
	_label(ui, "修复奖励：花坛绽放 / 星灯点亮 / 萤火满园", Rect2(466, 573, 700, 32), 20, MUTED)

func _queue_save() -> void:
	if _save_queued:
		return
	_save_queued = true
	_flush_save.call_deferred()

func _flush_save() -> void:
	_save_queued = false
	if is_instance_valid(level):
		_save_active()

func _save_active() -> bool:
	if not is_instance_valid(level) or not store.has_save():
		return false
	store.data["current"] = current_index
	store.data["active"] = level.capture_state()
	var ok: bool = store.write_save()
	if is_instance_valid(save_hint):
		save_hint.text = "已保存到本机" if ok else "保存失败，请检查权限"
	return ok

func manual_save() -> void:
	_save_active()

func _dialog(title: String, description: String, kind: String) -> Panel:
	close_modal(false)
	if is_instance_valid(level):
		level.set_modal(true)
	modal_kind = kind
	modal = Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(modal)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0.025, 0.065, 0.075, 0.78)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(shade)
	var card: Panel = _panel(modal, Rect2(320, 170, 640, 390))
	_label(card, "MOSS & CRATES", Rect2(40, 28, 560, 26), 16, MUTED)
	_label(card, title, Rect2(40, 79, 580, 58), 34)
	var body: Label = _label(card, description, Rect2(40, 151, 560, 97), 20, MUTED)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return card

func close_modal(resume: bool = true) -> void:
	if is_instance_valid(modal):
		ui.remove_child(modal)
		modal.queue_free()
	modal = null
	modal_kind = ""
	if resume and is_instance_valid(level):
		level.set_modal(false)

func show_pause() -> void:
	if not is_instance_valid(level) or level.board.is_solved():
		return
	var card: Panel = _dialog("在花园里歇一会儿", "进度会自动保存在这台电脑。返回主菜单后，可以从这里继续。", "pause")
	_button(card, "继续游戏", Rect2(40, 265, 260, 54), close_modal)
	_button(card, "保存并返回主菜单", Rect2(320, 265, 280, 54), func() -> void: show_menu())

func _on_completed() -> void:
	if not is_instance_valid(level) or not level.board.is_solved() or modal_kind == "win":
		return
	var key: String = str(current_index)
	var best: Dictionary = store.data["completed"].get(key, {})
	if best.is_empty() or level.board.steps < int(best["steps"]):
		store.data["completed"][key] = {"steps": level.board.steps, "pushes": level.board.pushes}
	store.data["unlocked"] = maxi(int(store.data["unlocked"]), mini(current_index + 2, entries.size()))
	var final_level: bool = current_index == entries.size() - 1
	store.data["finished"] = final_level and store.data["completed"].size() == entries.size()
	_save_active()
	var description: String = "%s 已完成！\n%d 步  ·  %d 次推动  ·  %d 个货箱归位" % [entries[current_index]["title"], level.board.steps, level.board.pushes, level.goals.size()]
	if garden_mode:
		var rewards: Array[String] = ["主页奖励：花坛绽放", "主页奖励：星灯点亮", "主页奖励：萤火满园"]
		description += "\n" + rewards[current_index]
		menu_art.revival_stage = store.data["completed"].size()
	GameAudio.play(&"win" if not final_level else &"finale")
	var card: Panel = _dialog("花园因你而改变" if garden_mode else "所有货物，妥善抵达", description, "win")
	_button(card, "主菜单", Rect2(40, 280, 150, 54), func() -> void: show_menu())
	_button(card, "再玩一次", Rect2(207, 280, 165, 54), func() -> void: load_level(current_index))
	_button(card, "查看胜利纪念" if final_level else "下一关  →", Rect2(391, 280, 209, 54), show_ending if final_level else next_level)

func next_level() -> void:
	if is_instance_valid(level) and level.board.is_solved() and current_index + 1 < entries.size():
		load_level(current_index + 1)

func show_ending() -> void:
	if not store.has_save() or store.data["completed"].size() < entries.size():
		return
	if garden_mode:
		_show_garden_ending()
		return
	_discard_level()
	_clear_ui()
	screen = "ending"
	menu_art.visible = true
	menu_art.theme_index = 3
	_label(ui, "THE GARDEN REMEMBERS", Rect2(70, 70, 580, 34), 19, MUTED)
	_label(ui, "全部通关！", Rect2(65, 150, 590, 94), 65)
	_label(ui, "九座庭院的灯，都为你亮起。", Rect2(76, 260, 540, 48), 27)
	_label(ui, "谢谢你，把每一份委托送到终点。", Rect2(76, 317, 540, 34), 21, MUTED)
	var total_steps: int = 0
	var total_pushes: int = 0
	for record: Dictionary in store.data["completed"].values():
		total_steps += int(record["steps"])
		total_pushes += int(record["pushes"])
	_label(ui, "完成 9 / 9   ·   最佳纪录合计\n%d 步    %d 次推动" % [total_steps, total_pushes], Rect2(76, 390, 540, 82), 23)
	_button(ui, "返回开局页面", Rect2(76, 515, 450, 58), func() -> void: show_menu(false))
	_button(ui, "重新开启旅程", Rect2(76, 590, 450, 54), request_new_game)
	var badge: Panel = _panel(ui, Rect2(784, 566, 354, 120))
	_label(badge, "花园守护者", Rect2(32, 17, 300, 44), 32)
	_label(badge, "九份委托  /  永久珍藏于本机", Rect2(32, 74, 310, 28), 17, MUTED)

func _show_garden_ending() -> void:
	_discard_level()
	_clear_ui()
	screen = "garden_ending"
	menu_art.visible = true
	menu_art.revival_stage = 3
	_label(ui, "RESTORE THE GARDEN", Rect2(76, 77, 550, 40), 21, MUTED)
	_label(ui, "花园，重新呼吸", Rect2(70, 170, 560, 80), 44)
	_label(ui, "花已盛开，星灯亮起，萤火满园。", Rect2(76, 285, 550, 40), 25)
	_label(ui, "你完成了三份修复委托。\n这份变化会保存在主页，随时可以回来看看。", Rect2(76, 355, 560, 90), 20, MUTED)
	_button(ui, "返回主页 · 查看复苏", Rect2(76, 508, 450, 60), func() -> void: show_menu(false))
	_button(ui, "重温修复关卡", Rect2(76, 590, 450, 55), show_garden_select)

func show_level_select() -> void:
	_clear_ui()
	screen = "select"
	menu_art.visible = true
	_label(ui, "庭院手册", Rect2(72, 41, 650, 65), 43)
	_label(ui, "依次完成委托解锁新庭院。已解锁关卡可以随时重玩。", Rect2(76, 113, 950, 32), 20, MUTED)
	var unlocked: int = int(store.data.get("unlocked", 1))
	for index: int in range(entries.size()):
		var row: int = int(index / 3.0)
		var column: int = index % 3
		var entry: Dictionary = entries[index]
		var cleared: bool = (store.data.get("completed", {}) as Dictionary).has(str(index))
		var title: String = "%02d   %s\n%s · %s" % [index + 1, entry["title"], entry["difficulty"], "已完成" if cleared else "可挑战" if index < unlocked else "待解锁"]
		_button(ui, title, Rect2(76 + column * 381, 185 + row * 145, 350, 118), func() -> void: _select_level(index), index >= unlocked)
	_button(ui, "← 返回主菜单", Rect2(76, 657, 280, 54), func() -> void: show_menu(false))

func _select_level(index: int) -> void:
	if not store.has_save():
		store.new_run()
	if not store.data["active"].is_empty() and not str(store.data["active"].get("moves", "")).is_empty() and not store.data["finished"]:
		var card: Panel = _dialog("从头挑战这座庭院？", "当前关卡的断点会被替换，解锁进度和已完成纪录会保留。", "select_confirm")
		_button(card, "取消", Rect2(40, 270, 260, 54), close_modal)
		_button(card, "开始挑战", Rect2(320, 270, 280, 54), func() -> void: load_level(index))
	else:
		load_level(index)

func show_save_info() -> void:
	var text: String = "尚无存档。开始游戏后，每完成一步都会自动保存。"
	if store.has_save():
		text = "第 %02d 关 · 已完成 %d / 9 关\n保存时间：%s\n存档仅保存在这台电脑，支持关卡内断点继续与撤销。" % [int(store.data["current"]) + 1, store.data["completed"].size(), store.data["updated"]]
	var card: Panel = _dialog("本机冒险存档", text, "save_info")
	_button(card, "关闭", Rect2(40, 285, 260, 54), close_modal)
	_button(card, "继续这份存档", Rect2(320, 285, 280, 54), continue_game, not store.has_save())

func request_exit() -> void:
	var card: Panel = _dialog("暂别花园？", "已保存的旅程不会消失，下次打开即可继续。", "exit")
	_button(card, "留下来", Rect2(40, 270, 260, 54), close_modal)
	_button(card, "退出游戏", Rect2(320, 270, 280, 54), _exit_game)

func _exit_game() -> void:
	if is_instance_valid(level):
		_save_active()
	get_tree().quit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_exit_game()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if modal_kind in ["pause", "save_info", "confirm_new", "select_confirm", "exit", "audio"]:
			GameAudio.play(&"ui_back", 0.02)
			close_modal.call_deferred()
		elif screen == "playing" and modal_kind.is_empty():
			show_pause.call_deferred()
		elif screen in ["select", "garden_select", "garden_ending"]:
			GameAudio.play(&"ui_back", 0.02)
			show_menu.call_deferred(false)
		get_viewport().set_input_as_handled()
