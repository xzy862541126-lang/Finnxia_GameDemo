extends Sprite2D

var direction: Vector2i = Vector2i.DOWN
var clock: float = 0.0
var textures: Dictionary = {}

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for action: String in ["idle", "walk", "push"]:
		textures[action] = {}
		for pair: Array in [[Vector2i.UP, "up"], [Vector2i.DOWN, "down"], [Vector2i.LEFT, "left"], [Vector2i.RIGHT, "right"]]:
			var path: String = "res://assets/player_%s.png" % pair[1] if action == "idle" else "res://assets/animations/%s_%s.png" % [action, pair[1]]
			textures[action][pair[0]] = load(path)
	sample(Vector2i.DOWN, false, false, 0.0)

func sample(facing: Vector2i, moving: bool, pushing: bool, delta: float) -> void:
	if facing != Vector2i.ZERO:
		direction = facing
	clock += delta
	var action: String = ("push" if pushing else "walk") if moving else "idle"
	frame = 0
	hframes = 1
	texture = textures[action][direction]
	if moving:
		hframes = 6
		frame = int(clock * 18.0) % 6
