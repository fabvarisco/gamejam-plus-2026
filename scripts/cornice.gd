@tool
class_name Cornice
extends StaticBody2D

## The snowline's snow bridge. It holds one cube, cracks while a cube stands on it, and
## breaks the moment both stand on it together, so the pair has to cross one at a time.
## It comes back when the room resets. Updated by the simulating peer; clients receive
## its state in the snapshot.

const SNOW := Color(0.97, 0.98, 1.0)
const SHADE := Color(0.76, 0.84, 0.95)
const INK := Color(0.09, 0.11, 0.17)

var rect := Rect2()
var intact: bool = true

var _shape: CollisionShape2D
var _loaded: bool = false
var _chunks: Array[Dictionary] = []


func setup(r: Rect2) -> void:
	rect = r
	collision_layer = 1
	collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = r.size
	_shape = CollisionShape2D.new()
	_shape.shape = shape
	_shape.position = r.get_center()
	add_child(_shape)


func update(cubes: Array) -> void:
	if not intact:
		return
	var on := 0
	for cube in cubes:
		var c := cube as PlayerCube
		var feet := c.global_position.y + Tuning.CUBE * 0.5
		# Mostly on it: a cube with only a corner over the snow stands on the rock.
		var over := c.global_position.x > rect.position.x and c.global_position.x < rect.end.x
		if c.on_floor and over and absf(feet - rect.position.y) < 6.0:
			on += 1
	_loaded = on > 0
	if on >= 2:
		set_intact(false)


func set_intact(value: bool) -> void:
	if value == intact:
		return
	intact = value
	_shape.disabled = not intact
	_chunks.clear()
	if not intact:
		var x := rect.position.x
		while x < rect.end.x:
			_chunks.append({
				"rect": Rect2(x, rect.position.y, Tuning.CUBE * 0.5, rect.size.y),
				"vel": Vector2(randf_range(-30.0, 30.0), randf_range(-40.0, 10.0)),
			})
			x += Tuning.CUBE * 0.5
	queue_redraw()


func _process(delta: float) -> void:
	for c in _chunks:
		c["vel"] += Vector2(0.0, Tuning.GRAVITY * 0.5) * delta
		var r: Rect2 = c["rect"]
		r.position += c["vel"] * delta
		c["rect"] = r
	queue_redraw()


func _draw() -> void:
	if not intact:
		for c in _chunks:
			var r: Rect2 = c["rect"]
			draw_colored_polygon(TerrainArt.rounded(r.grow(2.0), 4.0), INK)
			draw_colored_polygon(TerrainArt.rounded(r, 3.0), SNOW)
		return
	var shake := Vector2(randf_range(-1.0, 1.0), 0.0) if _loaded else Vector2.ZERO
	var r := Rect2(rect.position + shake, rect.size)
	draw_colored_polygon(TerrainArt.rounded(r.grow(3.0), 8.0), INK)
	draw_colored_polygon(TerrainArt.rounded(r, 7.0), SHADE)
	draw_colored_polygon(TerrainArt.rounded(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.55)), 6.0), SNOW)
	# Icicles under it, and cracks that open while a cube stands on it.
	var x := r.position.x + 8.0
	while x < r.end.x - 4.0:
		draw_colored_polygon(PackedVector2Array([Vector2(x - 4.0, r.end.y - 1.0), Vector2(x + 4.0, r.end.y - 1.0),
				Vector2(x, r.end.y + 9.0 + fmod(x, 7.0))]), SHADE)
		x += 13.0
	var crack := INK if _loaded else Color(INK, 0.35)
	for i in 3:
		var cx := r.position.x + r.size.x * (0.25 + i * 0.25)
		draw_polyline(PackedVector2Array([Vector2(cx, r.position.y + 2.0), Vector2(cx + 4.0, r.position.y + 8.0),
				Vector2(cx - 2.0, r.end.y - 2.0)]), crack, 2.0)
