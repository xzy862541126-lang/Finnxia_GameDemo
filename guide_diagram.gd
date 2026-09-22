extends Node2D

const Art = preload("res://rt_art.gd")
var topic: String = "basics"
const CRATE: Texture2D = preload("res://assets/crate.png")
const GOAL: Texture2D = preload("res://assets/goal.png")
const DONE: Texture2D = preload("res://assets/crate_on_goal.png")
const PLAYER: Texture2D = preload("res://assets/player_right.png")
const TIMBER: Texture2D = preload("res://assets/scenery/bridge_supply.png")

func tile(at: Vector2, tex: Texture2D = null) -> void:
	draw_rect(Rect2(at, Vector2(80, 80)), Color("334d48"))
	draw_rect(Rect2(at + Vector2(3, 3), Vector2(74, 74)), Color("537067"))
	if tex != null:
		draw_texture_rect(tex, Rect2(at + Vector2(8, 8), Vector2(64, 64)), false)

func arrow(at: Vector2) -> void:
	draw_rect(Rect2(at + Vector2(0, 10), Vector2(30, 6)), Color("eed19a"))
	draw_colored_polygon(PackedVector2Array([at + Vector2(28, 0), at + Vector2(42, 13), at + Vector2(28, 26)]), Color("eed19a"))

func water(at: Vector2) -> void:
	draw_rect(Rect2(at, Vector2(80, 80)), Color("326a83"))
	for i: int in range(4):
		draw_rect(Rect2(at + Vector2(8 + i % 2 * 12, 14 + i * 16), Vector2(40, 3)), Color("83bdc7"))

func gate(at: Vector2, opened: bool) -> void:
	tile(at)
	for i: int in range(2 if opened else 5):
		var x: float = (6 + i * 62) if opened else (8 + i * 14)
		draw_line(at + Vector2(x, 4), at + Vector2(x + 4, 76), Color("263f35"), 8)
		draw_line(at + Vector2(x, 4), at + Vector2(x + 4, 76), Color("99b976"), 3)

func _draw() -> void:
	var a: Vector2 = Vector2(20, 62)
	match topic:
		"basics":
			tile(a, PLAYER)
			tile(a + Vector2(80, 0), CRATE)
			tile(a + Vector2(160, 0), GOAL)
			arrow(a + Vector2(256, 25))
			tile(a + Vector2(320, 0), PLAYER)
			tile(a + Vector2(400, 0), DONE)
		"rules":
			tile(a, PLAYER)
			tile(a + Vector2(80, 0), CRATE)
			tile(a + Vector2(160, 0), CRATE)
			draw_line(a + Vector2(84, 8), a + Vector2(230, 70), Color("d97f7a"), 6)
			draw_line(a + Vector2(230, 8), a + Vector2(84, 70), Color("d97f7a"), 6)
			tile(a + Vector2(340, 0), Art.texture("relic"))
		"flower":
			tile(a, CRATE)
			tile(a + Vector2(80, 0))
			for i: int in range(4):
				draw_rect(Rect2(a + Vector2(98 + i % 2 * 22, 18 + i / 2 * 24), Vector2(14, 14)), Color("ecacc1"))
			gate(a + Vector2(170, 0), false)
			arrow(a + Vector2(268, 25))
			tile(a + Vector2(330, 0), CRATE)
			gate(a + Vector2(410, 0), true)
		"bridge":
			tile(a, PLAYER)
			tile(a + Vector2(80, 0), TIMBER)
			water(a + Vector2(160, 0))
			arrow(a + Vector2(262, 25))
			water(a + Vector2(330, 0))
			for i: int in range(7):
				draw_rect(Rect2(a + Vector2(330 + i * 11, 10), Vector2(10, 60)), Color("c19b67"))
			tile(a + Vector2(410, 0), CRATE)
		"patrol":
			tile(a, PLAYER)
			arrow(a + Vector2(114, 25))
			tile(a + Vector2(180, 0), Art.texture("monster"))
			draw_rect(Rect2(a + Vector2(290, 0), Vector2(4, 80)), Color("dd8c83"))
			tile(a + Vector2(340, 0), PLAYER)
			arrow(a + Vector2(436, 25))
		"crush", "water", "boss":
			tile(a, PLAYER)
			tile(a + Vector2(80, 0), CRATE)
			tile(a + Vector2(160, 0), Art.texture("boss" if topic == "boss" else "monster"))
			if topic == "crush":
				draw_texture_rect(load("res://assets/wall_stone.png"), Rect2(a + Vector2(240, 0), Vector2(80, 80)), false)
			else:
				water(a + Vector2(240, 0))
			arrow(a + Vector2(348, 25))
			tile(a + Vector2(410, 0), Art.texture("chest"))
		"cat":
			tile(a, Art.texture("cat"))
			tile(a + Vector2(80, 0), CRATE)
			arrow(a + Vector2(190, 25))
			tile(a + Vector2(270, 0), Art.texture("cat"))
			tile(a + Vector2(350, 0), CRATE)
		"relic":
			tile(a, CRATE)
			tile(a + Vector2(80, 0), PLAYER)
			arrow(a + Vector2(196, 25))
			tile(a + Vector2(270, 0), CRATE)
			tile(a + Vector2(350, 0), PLAYER)
			draw_texture_rect(Art.texture("relic"), Rect2(a + Vector2(445, -10), Vector2(80, 80)), false)
