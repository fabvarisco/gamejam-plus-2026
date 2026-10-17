@tool
class_name Lift
extends AnimatableBody2D

## The camp's weighted platform. It stays down while a cube stands on it; once it has
## been used and both cubes leave it, it rises out of reach and stays up until the room
## resets. Moved inside the simulation step; its position applies to physics at once, so
## a rewound tick sees the lift where it was.

const RISE_SPEED := 70.0
const SINK_SPEED := 120.0

var rect_down := Rect2()
var rise: float = 0.0
var offset: float = 0.0
var triggered: bool = false
var ceiling_y: float = 0.0


func setup(r: Rect2, rise_px: float, ceiling: float) -> void:
	rect_down = r
	rise = rise_px
	ceiling_y = ceiling
	collision_layer = 1
	collision_mask = 0
	sync_to_physics = false
	position = r.get_center()
	var shape := RectangleShape2D.new()
	shape.size = r.size
	var cs := CollisionShape2D.new()
	cs.shape = shape
	add_child(cs)


func top_rect() -> Rect2:
	return Rect2(rect_down.position - Vector2(0.0, offset), rect_down.size)


func update(delta: float, cubes: Array) -> void:
	var top := top_rect()
	var occupied := false
	for cube in cubes:
		var c := cube as PlayerCube
		var feet := c.global_position.y + Tuning.CUBE * 0.5
		var over := c.global_position.x + Tuning.CUBE * 0.45 > top.position.x and c.global_position.x - Tuning.CUBE * 0.45 < top.end.x
		if c.on_floor and over and absf(feet - top.position.y) < 6.0:
			occupied = true
	if occupied:
		triggered = true
		offset = move_toward(offset, 0.0, SINK_SPEED * delta)
	elif triggered:
		offset = move_toward(offset, rise, RISE_SPEED * delta)
	position = rect_down.get_center() - Vector2(0.0, offset)


func apply_offset(value: float) -> void:
	offset = value
	position = rect_down.get_center() - Vector2(0.0, offset)


func reset() -> void:
	triggered = false
	apply_offset(0.0)


func _draw() -> void:
	var local := Rect2(-rect_down.size * 0.5, rect_down.size)
	var cable_top := ceiling_y - global_position.y
	for x in [local.position.x + 8.0, local.end.x - 8.0]:
		draw_line(Vector2(x, local.position.y), Vector2(x, cable_top), Color(0.12, 0.06, 0.05), 4.0)
		draw_line(Vector2(x, local.position.y), Vector2(x, cable_top), Color(0.7, 0.6, 0.4), 2.0)
	draw_colored_polygon(TerrainArt.rounded(local.grow(3.0), 8.0), Color(0.12, 0.06, 0.05))
	draw_colored_polygon(TerrainArt.rounded(local, 6.0), Color(0.55, 0.36, 0.18))
	draw_colored_polygon(TerrainArt.rounded(Rect2(local.position + Vector2(4.0, 2.0), Vector2(local.size.x - 8.0, 5.0)), 2.0), Color(0.78, 0.6, 0.32))


func _process(_delta: float) -> void:
	queue_redraw()
