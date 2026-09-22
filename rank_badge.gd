extends Control

const COLORS: Dictionary = {"S": Color("f4ca63"), "A": Color("ed7774"), "B": Color("77b9ec"), "C": Color("8dc58b"), "D": Color("929b9e")}
const GLYPHS: Dictionary = {
	"S": ["01111", "11000", "11000", "01110", "00011", "00011", "11110"],
	"A": ["01110", "11011", "11011", "11111", "11011", "11011", "11011"],
	"B": ["11110", "11011", "11011", "11110", "11011", "11011", "11110"],
	"C": ["01111", "11000", "11000", "11000", "11000", "11000", "01111"],
	"D": ["11110", "11011", "11011", "11011", "11011", "11011", "11110"]}
@export var rank: String = "S":
	set(value):
		rank = value if COLORS.has(value) else "D"
		queue_redraw()

static func grade(steps: int, reference: int) -> String:
	if reference <= 0 or steps < 0: return "D"
	if steps <= reference: return "S"
	if steps * 4 <= reference * 5: return "A"
	if steps * 5 <= reference * 8: return "B"
	if steps <= reference * 2: return "C"
	return "D"

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(174, 180)
	tooltip_text = "S≤参考步数；A≤1.25倍；B≤1.6倍；C≤2倍；D>2倍"

func _draw() -> void:
	var color: Color = COLORS[rank]
	var outline: PackedVector2Array = PackedVector2Array([Vector2(16, 6), Vector2(158, 6), Vector2(158, 14), Vector2(166, 14), Vector2(166, 140), Vector2(158, 140), Vector2(158, 148), Vector2(16, 148), Vector2(16, 140), Vector2(8, 140), Vector2(8, 14), Vector2(16, 14), Vector2(16, 6)])
	draw_colored_polygon(outline, Color("102a25"))
	draw_polyline(outline, color.darkened(0.3), 4)
	draw_line(Vector2(20, 16), Vector2(152, 16), color.lightened(0.2), 2)
	for x: int in [24, 142]:
		draw_rect(Rect2(x, 28, 8, 8), color)
		draw_rect(Rect2(x + 2, 40, 4, 4), color.darkened(0.2))
	var rows: Array = GLYPHS[rank]
	for y: int in range(7):
		for x: int in range(5):
			if rows[y][x] == "1":
				var p: Vector2 = Vector2(57 + x * 12, 31 + y * 12)
				draw_rect(Rect2(p + Vector2(3, 4), Vector2(12, 12)), color.darkened(0.65))
				draw_rect(Rect2(p, Vector2(12, 12)), color)
				draw_rect(Rect2(p, Vector2(12, 2)), color.lightened(0.25))
	for i: int in range(5):
		var earned: bool = i < 5 - "SABCD".find(rank)
		draw_rect(Rect2(47 + i * 17, 126, 10, 6), color if earned else Color("30423c"))
	var font: Font = ThemeDB.fallback_font
	draw_string(font, Vector2(0, 173), "本关评级", HORIZONTAL_ALIGNMENT_CENTER, 174, 17, color)
