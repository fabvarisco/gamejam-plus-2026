@tool
class_name LoadingBar
extends StaticBody2D

## The loading room's bridge: a progress bar over a pit. Its blocks fill in one at a time,
## hold for a moment at 99%, then all vanish together and the bar starts over. Driven by
## the shared game clock, so both peers see the same bar.

const PERIOD := 6.0
const FILL_STEP := 0.4
const FULL_END := 5.2
const WARN_TIME := 0.6
const EDGE := Color(0.85, 0.9, 1.0, 0.7)
const FILL := Color(0.3, 0.9, 0.5)
const INK := Color(0.05, 0.06, 0.08)

var rect := Rect2()
var segments: Array[Rect2] = []
var solid: Array[bool] = []
var phase: float = 0.0
## Fill from the right end instead (for a mirrored room, whose entry is on the right).
var reverse: bool = false

var _shapes: Array[CollisionShape2D] = []
var _local: float = 0.0


func setup(r: Rect2, phase_seconds: float) -> void:
	rect = r
	phase = phase_seconds
	collision_layer = 1
	collision_mask = 0
	var count := int(round(r.size.x / Tuning.CUBE))
	for i in count:
		var seg := Rect2(r.position.x + i * Tuning.CUBE, r.position.y, Tuning.CUBE, r.size.y)
		segments.append(seg)
		solid.append(true)
		var shape := RectangleShape2D.new()
		shape.size = seg.size
		var cs := CollisionShape2D.new()
		cs.shape = shape
		cs.position = seg.get_center()
		add_child(cs)
		_shapes.append(cs)


func apply_time(t: float) -> void:
	_local = fmod(t + phase, PERIOD)
	for i in segments.size():
		var order := segments.size() - 1 - i if reverse else i
		var now := _local >= order * FILL_STEP and _local < FULL_END
		if now != solid[i]:
			solid[i] = now
			_shapes[i].set_deferred("disabled", not now)
	queue_redraw()


func solid_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for i in segments.size():
		if solid[i]:
			out.append(segments[i])
	return out


func _draw() -> void:
	var frame := rect.grow(4.0)
	draw_rect(frame, Color(INK, 0.5))
	draw_rect(frame, EDGE, false, 2.0)
	var warn := _local < FULL_END and _local > FULL_END - WARN_TIME
	for i in segments.size():
		if not solid[i]:
			continue
		var color := FILL
		if warn and randf() < 0.5:
			color = Color(0.95, 0.2, 0.75)
		draw_rect(segments[i].grow(-2.0), color)
	var filled := 0
	for s in solid:
		filled += int(s)
	var pct := mini(99, int(99.0 * filled / maxf(1.0, segments.size())))
	draw_string(ThemeDB.fallback_font, Vector2(rect.position.x, rect.position.y - 12.0), "carregando... %d%%" % pct,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, EDGE)
