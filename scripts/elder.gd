class_name Elder
extends Node2D

## The village elder who welcomes the two cubes before the climb: the same cube sprite,
## grayed with age, with a beard, bushy eyebrows and a cane. Placed with its feet on the
## ground at the node's position. It bobs while it talks.

const TINT := Color(0.72, 0.7, 0.78)
const WHITE := Color(0.97, 0.96, 0.92)
const INK := Color(0.12, 0.06, 0.05)
## The sprite is 256 px drawn at 0.2: its body spans 32 px and ends 17.6 px below center.
const SCALE := 0.2
const FEET := 17.6

var facing_left: bool = true
var talking: bool = false

var _sprite: Sprite2D
var _details: Node2D
var _t: float = 0.0


func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.texture = PlayerCube.TEX_IDLE
	_sprite.scale = Vector2(SCALE, SCALE)
	_sprite.flip_h = facing_left
	var mat := ShaderMaterial.new()
	mat.shader = PlayerCube.RECOLOR
	mat.set_shader_parameter("tint", TINT)
	_sprite.material = mat
	add_child(_sprite)
	_details = Node2D.new()
	_details.draw.connect(_draw_details)
	add_child(_details)


func _process(delta: float) -> void:
	_t += delta
	var bob := absf(sin(_t * 9.0)) * 2.5 if talking else sin(_t * 1.5) * 0.6
	_sprite.position = Vector2(0.0, -FEET - bob)
	_details.position = _sprite.position
	_details.queue_redraw()


## Drawn around the sprite's center; x mirrors with the facing so the beard sits under
## the eyes.
func _draw_details() -> void:
	var f := -1.0 if facing_left else 1.0
	# Cane, held on the facing side.
	var cane_x := 20.0 * f
	_details.draw_line(Vector2(cane_x, -2.0), Vector2(cane_x, FEET), INK, 4.0)
	_details.draw_line(Vector2(cane_x, -2.0), Vector2(cane_x, FEET), Color(0.55, 0.35, 0.18), 2.0)
	_details.draw_arc(Vector2(cane_x - 3.0 * f, -2.0), 3.0, PI, TAU, 6, INK, 3.0)
	# Bushy eyebrows over both eyes.
	for ex in [-5.0, 7.4]:
		var c := Vector2(ex * f, -7.0)
		_details.draw_line(c - Vector2(4.0, 0.0), c + Vector2(4.0, -1.5 * f), INK, 4.0)
		_details.draw_line(c - Vector2(4.0, 0.0), c + Vector2(4.0, -1.5 * f), WHITE, 2.5)
	# A long white beard from under the eyes, past the bottom of the body.
	var beard := PackedVector2Array([
		Vector2(-6.0 * f, 3.5), Vector2(13.0 * f, 3.5), Vector2(10.0 * f, 12.0),
		Vector2(5.0 * f, 22.0), Vector2(0.0, 13.0), Vector2(-4.0 * f, 10.0),
	])
	var outline := PackedVector2Array()
	for p in beard:
		outline.append(Vector2(3.5 * f, 11.0) + (p - Vector2(3.5 * f, 11.0)) * 1.15)
	_details.draw_colored_polygon(outline, INK)
	_details.draw_colored_polygon(beard, WHITE)
	_details.draw_line(Vector2(2.0 * f, 6.0), Vector2(5.0 * f, 15.0), Color(0.8, 0.78, 0.74), 1.5)
