class_name EntangledRope
extends Node2D

@export var max_length: float = 220.0
@export var player_a_path: NodePath
@export var player_b_path: NodePath

@onready var _line: Line2D = $Line2D

var _player_a: CharacterBody2D
var _player_b: CharacterBody2D


func _ready() -> void:
	_player_a = get_node_or_null(player_a_path) as CharacterBody2D
	_player_b = get_node_or_null(player_b_path) as CharacterBody2D
	process_physics_priority = 10


func _physics_process(_delta: float) -> void:
	if _player_a == null or _player_b == null:
		return
	_constrain_players()
	var a := _player_a.global_position
	var b := _player_b.global_position
	_line.points = PackedVector2Array([to_local(a), to_local(b)])


func _constrain_players() -> void:
	var delta := _player_b.global_position - _player_a.global_position
	var dist := delta.length()
	if dist <= max_length or dist < 0.001:
		return
	var n := delta / dist
	var excess := dist - max_length
	var weight_a := 0.5
	var weight_b := 0.5
	if _player_a.is_on_floor() and not _player_b.is_on_floor():
		weight_a = 0.18
		weight_b = 0.82
	elif _player_b.is_on_floor() and not _player_a.is_on_floor():
		weight_a = 0.82
		weight_b = 0.18
	_player_a.global_position += n * excess * weight_a
	_player_b.global_position -= n * excess * weight_b
	var separating := (_player_b.velocity - _player_a.velocity).dot(n)
	if separating > 0.0:
		_player_a.velocity += n * separating * weight_a
		_player_b.velocity -= n * separating * weight_b
