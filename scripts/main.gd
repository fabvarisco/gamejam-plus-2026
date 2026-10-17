extends Node2D

@onready var stage: StageGenerator = $StageGenerator
@onready var player_1: PlayerCube = $Players/Player1
@onready var player_2: PlayerCube = $Players/Player2
@onready var rope: EntangledRope = $Rope
@onready var camera: Camera2D = $Camera2D
@onready var hint: Label = $CanvasLayer/Hint


func _ready() -> void:
	stage.generated.connect(_on_stage_generated)
	rope.max_length = stage.rope_length
	stage.generate()


func _on_stage_generated(start_position: Vector2, _goal_position: Vector2) -> void:
	player_1.global_position = start_position + Vector2(-18.0, -20.0)
	player_2.global_position = start_position + Vector2(18.0, -20.0)
	player_1.velocity = Vector2.ZERO
	player_2.velocity = Vector2.ZERO
	rope.max_length = stage.rope_length
	camera.global_position = start_position
	hint.text = "P1 WASD / Space   P2 Arrows   R reroll   G graph   Seed %d" % stage.generation_seed


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_R:
			if stage.generation_seed == 0:
				stage.generation_seed = randi()
			else:
				stage.generation_seed += 1
			stage.generate()
		elif event.physical_keycode == KEY_G:
			stage.show_graph = not stage.show_graph
			stage.queue_redraw()


func _process(delta: float) -> void:
	var midpoint := (player_1.global_position + player_2.global_position) * 0.5
	camera.global_position = camera.global_position.lerp(midpoint, 1.0 - exp(-delta * 4.0))
