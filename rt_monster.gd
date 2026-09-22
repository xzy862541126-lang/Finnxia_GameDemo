extends Sprite2D

const Art = preload("res://rt_art.gd")
var boss: bool = false
var clock: float = 0.0

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture = Art.texture("boss" if boss else "monster")

func animate(delta: float, alive: bool, facing: Vector2i) -> void:
	visible = alive
	clock += delta
	flip_h = facing.x < 0
	offset.y = -2.0 if int(clock * 4.0) % 2 else 0.0
