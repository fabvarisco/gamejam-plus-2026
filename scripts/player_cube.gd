class_name PlayerCube
extends CharacterBody2D

@export var player_index: int = 0
@export var move_speed: float = 240.0
@export var jump_velocity: float = -430.0

const MOVE_SMOOTH := 14.0
const SQUASH_SMOOTH := 16.0

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var _jump_held: bool = false
var _visual_scale := Vector2.ONE
var _step_phase := 0.0

@onready var _visual: Node2D = $Visual
@onready var _sprite: Sprite2D = $Visual/Sprite2D
@onready var _walk_dust: CPUParticles2D = $Visual/WalkDust
@onready var _land_dust: CPUParticles2D = $Visual/LandDust


func _ready() -> void:
	var body := _body_color()
	_walk_dust.color = Color(body.r, body.g, body.b, 0.9)
	_land_dust.color = Color(body.r, body.g, body.b, 1.0)


func _physics_process(delta: float) -> void:
	var was_on_floor := is_on_floor()
	if not was_on_floor:
		velocity.y += gravity * delta
	var axis := _horizontal_axis()
	var target_speed := axis * move_speed
	velocity.x = lerpf(velocity.x, target_speed, 1.0 - exp(-MOVE_SMOOTH * delta))
	var jump_down := _jump_down()
	var jumped := jump_down and not _jump_held and was_on_floor
	if jumped:
		velocity.y = jump_velocity
		_visual_scale = Vector2(0.72, 1.34)
	_jump_held = jump_down
	move_and_slide()
	if not was_on_floor and is_on_floor():
		_visual_scale = Vector2(1.36, 0.64)
		_land_dust.restart()
	_apply_juice(delta, axis)


func _apply_juice(delta: float, axis: float) -> void:
	var target := Vector2.ONE
	if not is_on_floor():
		var stretch := clampf(absf(velocity.y) / 520.0, 0.0, 1.0)
		if velocity.y < 0.0:
			target = Vector2(lerpf(1.0, 0.8, stretch), lerpf(1.0, 1.24, stretch))
		else:
			target = Vector2(lerpf(1.0, 1.1, stretch), lerpf(1.0, 0.86, stretch))
	else:
		var move := clampf(absf(velocity.x) / move_speed, 0.0, 1.0)
		_step_phase += absf(velocity.x) * delta * 0.09
		var bob := sin(_step_phase) * 0.05 * move
		target = Vector2(lerpf(1.0, 1.1, move) + bob, lerpf(1.0, 0.9, move) - bob)
	if axis != 0.0:
		_sprite.flip_h = axis < 0.0
	_visual_scale = _visual_scale.lerp(target, 1.0 - exp(-SQUASH_SMOOTH * delta))
	_visual.scale = _visual_scale
	var walking := is_on_floor() and absf(velocity.x) > 30.0
	_walk_dust.emitting = walking
	if walking:
		_walk_dust.direction = Vector2(-signf(velocity.x), -0.45)


func _body_color() -> Color:
	var texture := _sprite.texture
	if texture == null:
		return Color(0.647, 0.42, 0.961)
	var image := texture.get_image()
	if image == null or image.is_empty():
		return Color(0.647, 0.42, 0.961)
	var pixel := image.get_pixel(image.get_width() / 2, int(image.get_height() * 0.53))
	if pixel.a < 0.2:
		return Color(0.647, 0.42, 0.961)
	return Color(pixel.r, pixel.g, pixel.b, 1.0) * _sprite.modulate


func _horizontal_axis() -> float:
	if player_index == 0:
		return float(int(Input.is_physical_key_pressed(KEY_D)) - int(Input.is_physical_key_pressed(KEY_A)))
	return float(int(Input.is_physical_key_pressed(KEY_RIGHT)) - int(Input.is_physical_key_pressed(KEY_LEFT)))


func _jump_down() -> bool:
	if player_index == 0:
		return Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_SPACE)
	return Input.is_physical_key_pressed(KEY_UP)
