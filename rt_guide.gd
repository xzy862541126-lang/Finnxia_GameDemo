extends CanvasLayer

signal closed
const Diagram = preload("res://guide_diagram.gd")
const PAGES: Dictionary = {
	"basics": ["目标点 · 获胜条件", "把箱子推到金色方框里，箱子会变绿。\n所有箱子都到位，就过关了。"],
	"rules": ["移动 · 推箱子", "方向键 / WASD 移动，一次只能推一个箱子。\nZ 撤销，R 重开。撤销不限次数，但仍会计步。\n步数越少，评分越高：S、A、B、C。"],
	"flower": ["花坛 · 打开藤蔓门", "把箱子推到粉色花坛上，藤蔓门就会打开。\n箱子移开后，门不会关。\n花坛不是目标点，最后还要把箱子推到金色方框里。"],
	"bridge": ["木料 · 搭桥", "把绑着蓝绳的木料箱推入水里，就能搭桥。\n普通箱子不能下水，要等桥搭好再推过去。\n木料箱不用送到目标点。"],
	"patrol": ["巡逻怪 · 躲开怪物", "你不动，怪物也会沿路线移动。\n碰到怪物就会死亡，游戏会暂停。\n按 Z 撤销，再按空格继续。"],
	"crush": ["箱子 · 挤压怪物", "用箱子把怪物夹在墙边，就能击败它。\n怪物身后是空格时，只会被推开一格。\nBoss 不能被挤死，要把它推下水。"],
	"water": ["水沟 · 推怪下水", "用箱子把怪物推入蓝色水沟，就能击败它。\n玩家和普通箱子不能下水。\n推错了，可以按 Z 撤销。"],
	"cat": ["园丁猫 · 帮忙推箱子", "猫走得很慢，遇到挡路的箱子会推一下。\n它不会伤害你，也不会推已到位的箱子。\n看头顶箭头判断方向，站在它前面可以挡住它。"],
	"boss": ["Boss · 打开宝箱", "用箱子把 Boss 推下水，再击败小怪。\n到宝箱旁按 E，拿到可以拉箱子的手套。\n回到入口按 E，就能返回庭院。"],
	"relic": ["藤蔓手套 · 拉箱子", "站在箱子旁，按住 Shift 向后走，就能拉动箱子。\n一次只能拉一个，身后要有空位。\n手套能带回庭院，本次探索结束后不保留。"]}
var body_overrides: Dictionary = {}
var pages: Array[String] = []
var index: int = 0
var panel: Control
var title_label: Label
var body_label: Label
var count_label: Label
var diagram: Diagram
var seen: Dictionary = {}
var previous_button: Button
var next_button: Button
var close_button: Button

func is_open() -> bool:
	return is_instance_valid(panel) and panel.visible

func open(keys: Array[String], force: bool = false) -> bool:
	pages.clear()
	for key: String in keys:
		if PAGES.has(key) and (force or not seen.has(key)):
			pages.append(key)
	if pages.is_empty():
		return false
	if not is_instance_valid(panel):
		_build()
	panel.show()
	index = 0
	_refresh()
	return true

func _build() -> void:
	layer = 90
	panel = Control.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.025, 0.065, 0.07, 0.88)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(dim)
	var card: Panel = Panel.new()
	card.position = Vector2(280, 90)
	card.size = Vector2(720, 590)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color("183b33")
	style.border_color = Color("c4b37a")
	style.set_border_width_all(3)
	card.add_theme_stylebox_override("panel", style)
	panel.add_child(card)
	title_label = _label(card, Vector2(32, 28), 28)
	diagram = Diagram.new()
	diagram.position = Vector2(55, 106)
	diagram.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	card.add_child(diagram)
	body_label = _label(card, Vector2(36, 334), 21)
	body_label.size = Vector2(650, 122)
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	count_label = _label(card, Vector2(36, 496), 18)
	for entry: Array in [["上一张 A", 32, -1], ["下一张 D", 224, 1], ["关闭 Esc", 496, 0]]:
		var button: Button = Button.new()
		button.text = entry[0]
		button.position = Vector2(entry[1], 534)
		button.size = Vector2(176, 40)
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_color_override("font_color", Color("ecd7ad"))
		button.add_theme_color_override("font_disabled_color", Color("71807a"))
		for state: String in ["normal", "hover", "pressed", "disabled"]:
			var button_style: StyleBoxFlat = StyleBoxFlat.new()
			button_style.bg_color = Color("294f42") if state == "normal" else Color("3a6552")
			button_style.border_color = Color("819574")
			if state == "disabled":
				button_style.bg_color = Color("20352f")
				button_style.border_color = Color("3e5047")
			button_style.set_border_width_all(1)
			button_style.set_corner_radius_all(3)
			button.add_theme_stylebox_override(state, button_style)
		var direction: int = entry[2]
		if direction < 0:
			previous_button = button
		elif direction > 0:
			next_button = button
		else:
			close_button = button
		button.pressed.connect(close_guide if direction == 0 else turn.bind(direction))
		card.add_child(button)

func _label(parent: Node, pos: Vector2, font_size: int) -> Label:
	var label: Label = Label.new()
	label.position = pos
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("ecd7ad"))
	parent.add_child(label)
	return label

func _refresh() -> void:
	var key: String = pages[index]
	title_label.text = PAGES[key][0]
	body_label.text = body_overrides.get(key, PAGES[key][1])
	count_label.text = "%d / %d  ·  A / D 翻页，Esc 关闭  ·  游戏已暂停" % [index + 1, pages.size()]
	previous_button.disabled = index == 0
	next_button.disabled = index == pages.size() - 1
	diagram.topic = key
	diagram.queue_redraw()
	seen[key] = true

func turn(direction: int) -> void:
	if not is_open() or pages.is_empty():
		return
	var next_index: int = clampi(index + direction, 0, pages.size() - 1)
	if next_index != index:
		index = next_index
		_refresh()

func close_guide() -> void:
	if is_open():
		for key: String in pages:
			seen[key] = true
		panel.hide()
		closed.emit()

func _input(event: InputEvent) -> void:
	if not is_open():
		return
	if event is InputEventMouse or event is InputEventScreenTouch or event is InputEventScreenDrag:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if key in [KEY_A, KEY_LEFT]:
			turn(-1)
		elif key in [KEY_D, KEY_RIGHT]:
			turn(1)
		elif key == KEY_ESCAPE:
			close_guide()
	get_viewport().set_input_as_handled()
