@tool
class_name GlitchArt
extends Node2D

## The seam. Rock that tears into offset slices, drops rows and flashes wrong colors, so
## it reads as the program failing rather than as a hidden normal hold. `draw_offset`
## draws the shapes away from where their collision really is.

const FILL := Color(0.33, 0.19, 0.11)
const OUTLINE := Color(0.12, 0.06, 0.05)
const WRONG_A := Color(0.95, 0.2, 0.75)
const WRONG_B := Color(0.2, 0.95, 0.6)

var rects: Array[Rect2] = []
var draw_offset := Vector2.ZERO

var _clock: float = 0.0
var _frame_seed: int = 0


func _ready() -> void:
	z_index = 2


func _process(delta: float) -> void:
	_clock -= delta
	if _clock <= 0.0:
		_clock = randf_range(0.04, 0.18)
		_frame_seed = randi()
		queue_redraw()


func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _frame_seed
	for r in rects:
		var shift := draw_offset if rng.randf() < 0.75 else draw_offset * rng.randf_range(-1.0, 2.0)
		var rr := Rect2(r.position + shift, r.size)
		draw_rect(rr.grow(3.0), OUTLINE)
		var y := rr.position.y
		while y < rr.end.y:
			var slice := minf(4.0, rr.end.y - y)
			var off := rng.randf_range(-9.0, 9.0) if rng.randf() < 0.3 else 0.0
			var roll := rng.randf()
			if roll >= 0.06:
				var color := FILL
				if roll < 0.14:
					color = WRONG_A
				elif roll < 0.2:
					color = WRONG_B
				draw_rect(Rect2(rr.position.x + off, y, rr.size.x, slice), color)
			y += slice
		if rng.randf() < 0.3:
			draw_rect(rr.grow(1.0), WRONG_B, false, 1.5)
