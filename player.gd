extends CharacterBody2D

signal step_requested(direction: Vector2i)

const INPUTS: Dictionary[String, Vector2i] = {
	"ui_up": Vector2i.UP,
	"ui_right": Vector2i.RIGHT,
	"ui_left": Vector2i.LEFT,
	"ui_down": Vector2i.DOWN
}
const IDLE: Dictionary[Vector2i, Texture2D] = {
	Vector2i.UP: preload("res://assets/player_up.png"),
	Vector2i.RIGHT: preload("res://assets/player_right.png"),
	Vector2i.LEFT: preload("res://assets/player_left.png"),
	Vector2i.DOWN: preload("res://assets/player_down.png")
}
const WALK: Dictionary[Vector2i, Texture2D] = {
	Vector2i.UP: preload("res://assets/animations/walk_up.png"),
	Vector2i.RIGHT: preload("res://assets/animations/walk_right.png"),
	Vector2i.LEFT: preload("res://assets/animations/walk_left.png"),
	Vector2i.DOWN: preload("res://assets/animations/walk_down.png")
}
const PUSH: Dictionary[Vector2i, Texture2D] = {
	Vector2i.UP: preload("res://assets/animations/push_up.png"),
	Vector2i.RIGHT: preload("res://assets/animations/push_right.png"),
	Vector2i.LEFT: preload("res://assets/animations/push_left.png"),
	Vector2i.DOWN: preload("res://assets/animations/push_down.png")
}

@export_range(0.08, 0.5, 0.01) var walk_duration: float = 0.20
@export_range(0.10, 0.6, 0.01) var push_duration: float = 0.26

var facing: Vector2i = Vector2i.DOWN
var is_moving: bool = false
var input_locked: bool = false
var animation_state: StringName = &"idle"
var _queued_direction: Vector2i = Vector2i.ZERO
var _last_action: String = ""
var wait_for_release: bool = false

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_mask = 3
	face_direction(facing)

func _unhandled_input(event: InputEvent) -> void:
	if input_locked or wait_for_release or event.is_echo():
		return
	for action: String in INPUTS:
		if event.is_action_pressed(action):
			_last_action = action
			_queued_direction = INPUTS[action]
			get_viewport().set_input_as_handled()
			return

func _physics_process(_delta: float) -> void:
	if wait_for_release:
		for action: String in INPUTS:
			if Input.is_action_pressed(action):
				return
		wait_for_release = false
	if is_moving or input_locked:
		return
	if _queued_direction != Vector2i.ZERO:
		var direction: Vector2i = _queued_direction
		_queued_direction = Vector2i.ZERO
		step_requested.emit(direction)
		return
	if not _last_action.is_empty() and Input.is_action_pressed(_last_action):
		step_requested.emit(INPUTS[_last_action])
		return
	for action: String in INPUTS:
		if Input.is_action_pressed(action):
			_last_action = action
			step_requested.emit(INPUTS[action])
			return

func face_direction(direction: Vector2i) -> void:
	if not IDLE.has(direction):
		return
	facing = direction
	sprite.frame = 0
	sprite.hframes = 1
	sprite.texture = IDLE[facing]
	animation_state = &"idle"

var _step_sound_played: bool = false

func begin_step(direction: Vector2i, pushing: bool) -> void:
	facing = direction
	is_moving = true
	animation_state = &"push" if pushing else &"walk"
	sprite.frame = 0
	sprite.texture = PUSH[facing] if pushing else WALK[facing]
	sprite.hframes = 6
	_step_sound_played = false
	_play_sfx(&"push" if pushing else &"walk", 0.02)

func sample_step(progress: float) -> void:
	sprite.frame = clampi(int(progress * 6.0), 0, 5)
	if not _step_sound_played and progress >= 0.5:
		_step_sound_played = true
		_play_sfx(&"walk", 0.05)

func _play_sfx(name: StringName, throttle: float = 0.0) -> void:
	var audio: Node = get_node_or_null("/root/GameAudio")
	if audio != null and audio.has_method("play"):
		audio.call("play", name, throttle)

func finish_step() -> void:
	is_moving = false
	face_direction(facing)

func clear_input() -> void:
	_queued_direction = Vector2i.ZERO
	_last_action = ""
