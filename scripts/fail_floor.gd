@tool
class_name FailFloor
extends StaticBody2D

## Room 8's floor. It holds until the end, then breaks into pieces and drops the cubes.

var rects: Array[Rect2] = []
var bridges: Array[Rect2] = []
var failed: bool = false

var _shapes: Array[CollisionShape2D] = []
var _pieces: Array[Dictionary] = []


func setup(floor_rects: Array[Rect2], bridge_rects: Array[Rect2]) -> void:
	rects = floor_rects
	bridges = bridge_rects
	collision_layer = 1
	collision_mask = 0
	for r in rects + bridges:
		var shape := RectangleShape2D.new()
		shape.size = r.size
		var cs := CollisionShape2D.new()
		cs.shape = shape
		cs.position = r.get_center()
		cs.one_way_collision = bridges.has(r)
		add_child(cs)
		_shapes.append(cs)


func fail() -> void:
	if failed:
		return
	failed = true
	for cs in _shapes:
		cs.disabled = true
	_pieces.clear()
	for r in rects + bridges:
		var x := r.position.x
		while x < r.end.x:
			_pieces.append({
				"rect": Rect2(x, r.position.y, Tuning.CUBE, r.size.y),
				"vel": Vector2(randf_range(-40.0, 40.0), randf_range(-60.0, 20.0)),
				"delay": randf_range(0.0, 0.5),
			})
			x += Tuning.CUBE


func restore() -> void:
	failed = false
	_pieces.clear()
	for cs in _shapes:
		cs.disabled = false
	queue_redraw()


func _process(delta: float) -> void:
	if not failed:
		return
	for p in _pieces:
		p["delay"] -= delta
		if p["delay"] > 0.0:
			continue
		p["vel"] += Vector2(0.0, Tuning.GRAVITY * 0.5) * delta
		var r: Rect2 = p["rect"]
		r.position += p["vel"] * delta
		p["rect"] = r
	queue_redraw()


func _draw() -> void:
	if not failed:
		TerrainArt.paint(self, rects, Themes.Style.GRID)
		TerrainArt.paint_bridges(self, bridges, Themes.Style.GRID)
		return
	var pieces: Array[Rect2] = []
	for p in _pieces:
		pieces.append(p["rect"])
	TerrainArt.paint(self, pieces, Themes.Style.GRID)
