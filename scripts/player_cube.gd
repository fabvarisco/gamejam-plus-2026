class_name PlayerCube
extends CharacterBody2D

@export var player_index: int = 0
@export var move_speed: float = 240.0
@export var jump_velocity: float = -430.0

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var _jump_held: bool = false


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta
	var axis := _horizontal_axis()
	velocity.x = axis * move_speed
	var jump_down := _jump_down()
	if jump_down and not _jump_held and is_on_floor():
		velocity.y = jump_velocity
	_jump_held = jump_down
	move_and_slide()


func _horizontal_axis() -> float:
	if player_index == 0:
		return float(int(Input.is_physical_key_pressed(KEY_D)) - int(Input.is_physical_key_pressed(KEY_A)))
	return float(int(Input.is_physical_key_pressed(KEY_RIGHT)) - int(Input.is_physical_key_pressed(KEY_LEFT)))


func _jump_down() -> bool:
	if player_index == 0:
		return Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_SPACE)
	return Input.is_physical_key_pressed(KEY_UP)
