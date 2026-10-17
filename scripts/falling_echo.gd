class_name FallingEcho
extends Node2D

## Room 4's falling cubes: two cubes tied by a rope, tumbling down the face in the same
## fall sprite the players use, their colors already refusing to hold still. They are the
## players, later; nothing here says so.

var fall_distance: float = 1400.0

var _cubes: Array[Sprite2D] = []
var _rope: Line2D
var _velocity := Vector2(0.0, 60.0)
var _travelled: float = 0.0
var _clock: float = 0.0


func _ready() -> void:
	z_index = 5
	_rope = Line2D.new()
	_rope.width = 3.5
	_rope.default_color = Color(0.86, 0.78, 0.6)
	add_child(_rope)
	for i in 2:
		var s := Sprite2D.new()
		s.texture = PlayerCube.TEX_FALL
		s.scale = Vector2(0.2, 0.2)
		var mat := ShaderMaterial.new()
		mat.shader = PlayerCube.RECOLOR
		s.material = mat
		s.position = Vector2(-18.0 if i == 0 else 18.0, -40.0 * i)
		add_child(s)
		_cubes.append(s)


func _process(delta: float) -> void:
	_velocity.y = minf(_velocity.y + Tuning.GRAVITY * 0.5 * delta, 700.0)
	position += _velocity * delta
	_travelled += _velocity.y * delta
	for i in _cubes.size():
		var s := _cubes[i]
		s.rotation += delta * (4.0 if i == 0 else -5.0)
		s.position.x = (-18.0 if i == 0 else 18.0) + sin(_travelled * 0.01 + i) * 10.0
	_rope.points = PackedVector2Array([_cubes[0].position, (_cubes[0].position + _cubes[1].position) * 0.5 + Vector2(0.0, 14.0), _cubes[1].position])
	_clock -= delta
	if _clock <= 0.0:
		_clock = randf_range(0.06, 0.25)
		for s in _cubes:
			var mat := s.material as ShaderMaterial
			mat.set_shader_parameter("tint", PlayerCube.GLITCH_PALETTE[randi() % PlayerCube.GLITCH_PALETTE.size()])
			mat.set_shader_parameter("glitch", randf() * 0.6)
			mat.set_shader_parameter("glitch_tint", PlayerCube.GLITCH_PALETTE[randi() % PlayerCube.GLITCH_PALETTE.size()])
			mat.set_shader_parameter("slice_seed", randf())
	if _travelled > fall_distance:
		queue_free()
