extends Sprite2D

const Art = preload("res://rt_art.gd")
var clock: float = 0.0

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture = Art.texture("cat")

func animate(delta: float, moving: bool) -> void:
	clock += delta
	offset.y = -2.0 if moving and int(clock * 6.0) % 2 else 0.0
