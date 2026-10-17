@tool
class_name JitterPlatform
extends StaticBody2D

## Room 7's ground that jitters and reappears: it flickers as a warning, blinks out for a
## moment on a fixed rhythm, then comes back. Driven by the shared game clock so both
## peers see the same rhythm.

const PERIOD := 3.2
const OFF_TIME := 0.6
const WARN_TIME := 0.5

var rect := Rect2()
var phase: float = 0.0
var solid: bool = true

var _shape: CollisionShape2D
var _warning: bool = false
var _jit := Vector2.ZERO


func setup(r: Rect2, phase_seconds: float) -> void:
	rect = r
	phase = phase_seconds
	collision_layer = 1
	collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = r.size
	_shape = CollisionShape2D.new()
	_shape.shape = shape
	_shape.position = r.get_center()
	add_child(_shape)


func apply_time(t: float) -> void:
	var local := fmod(t + phase, PERIOD)
	var now_solid := local >= OFF_TIME
	_warning = now_solid and local > PERIOD - WARN_TIME
	if now_solid != solid:
		solid = now_solid
		_shape.set_deferred("disabled", not solid)


func _process(_delta: float) -> void:
	_jit = Vector2(randf_range(-2.0, 2.0), randf_range(-1.0, 1.0)) if randf() < 0.5 else Vector2.ZERO
	queue_redraw()


func _draw() -> void:
	if not solid:
		draw_rect(Rect2(rect.position + _jit * 3.0, rect.size), Color(0.2, 0.9, 1.0, 0.35), false, 1.5)
		return
	if _warning and randf() < 0.5:
		draw_rect(Rect2(rect.position + _jit * 2.0, rect.size), Color(0.95, 0.2, 0.75, 0.6))
		return
	draw_set_transform(_jit)
	var blocks: Array[Rect2] = [rect]
	TerrainArt.paint(self, blocks, true)
