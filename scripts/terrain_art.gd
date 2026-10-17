@tool
class_name TerrainArt
extends Node2D

## Paints collision rectangles as gooey rock: a thick dark outline, a rounded body, a
## glossy top and drips under exposed undersides. All outlines are drawn before all
## fills, so touching blocks merge into one mass. The corrupted style past the seam is
## flat interface gray with a pixel grid and offset copies of its own outline.

const HONEST_OUTLINE := Color(0.12, 0.06, 0.05)
const HONEST_FILL := Color(0.33, 0.19, 0.11)
const HONEST_INNER := Color(0.4, 0.25, 0.14)
const HONEST_TOP := Color(0.58, 0.4, 0.2)
const CORRUPT_OUTLINE := Color(0.05, 0.05, 0.08)
const CORRUPT_FILL := Color(0.24, 0.25, 0.3)
const CORRUPT_GRID := Color(0.42, 0.46, 0.54, 0.5)
const GHOST_A := Color(0.95, 0.2, 0.75, 0.35)
const GHOST_B := Color(0.2, 0.9, 1.0, 0.3)

var rects: Array[Rect2] = []
## One-way floors: drawn as a sagging goo membrane so they read as passable from below.
var bridges: Array[Rect2] = []
var corrupt: bool = false
var jitter: bool = false
var seed_value: int = 0

var _drips: Array[Vector3] = []
var _specks: Array[Vector3] = []
var _offset := Vector2.ZERO
var _clock: float = 0.0


func finalize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_drips.clear()
	_specks.clear()
	for r in rects:
		if not corrupt and not _covered(Vector2(r.get_center().x, r.end.y + 3.0), r):
			var count := rng.randi_range(0, mini(3, int(r.size.x / Tuning.CUBE)))
			for i in count:
				var x := rng.randf_range(r.position.x + 6.0, r.end.x - 6.0)
				if not _covered(Vector2(x, r.end.y + 3.0), r):
					_drips.append(Vector3(x, r.end.y - 2.0, rng.randf_range(6.0, 18.0)))
		var speck_count := int(r.size.x * r.size.y / (Tuning.CUBE * Tuning.CUBE * 2.5))
		for i in speck_count:
			_specks.append(Vector3(rng.randf_range(r.position.x + 5.0, r.end.x - 5.0),
					rng.randf_range(r.position.y + 8.0, r.end.y - 5.0), rng.randf_range(1.5, 3.5)))
	set_process(jitter and not Engine.is_editor_hint())
	queue_redraw()


func _process(delta: float) -> void:
	_clock -= delta
	if _clock <= 0.0:
		_clock = randf_range(0.04, 0.3)
		_offset = Vector2(randf_range(-2.0, 2.0), randf_range(-1.5, 1.5)) if randf() < 0.6 else Vector2.ZERO
		queue_redraw()


func _draw() -> void:
	draw_set_transform(_offset)
	if not corrupt:
		for d in _drips:
			_drip(d, HONEST_OUTLINE, 3.0)
	paint(self, rects, corrupt)
	paint_bridges(self, bridges, corrupt)
	if not corrupt:
		for d in _drips:
			_drip(d, HONEST_FILL, 0.0)
		for s in _specks:
			draw_circle(Vector2(s.x, s.y), s.z, HONEST_INNER.darkened(0.25))


func _drip(d: Vector3, color: Color, extra: float) -> void:
	var start := Vector2(d.x, d.y)
	var end := start + Vector2(0.0, d.z)
	var width := 5.0 + extra * 2.0
	draw_line(start, end, color, width)
	draw_circle(end, width * 0.5 + 1.0, color)


func _covered(point: Vector2, except: Rect2) -> bool:
	for r in rects:
		if r != except and r.has_point(point):
			return true
	return false


static func paint(ci: CanvasItem, blocks: Array[Rect2], corrupt_style: bool) -> void:
	if corrupt_style:
		for r in blocks:
			ci.draw_colored_polygon(rounded(r.grow(2.0), 3.0), CORRUPT_OUTLINE)
		for r in blocks:
			ci.draw_colored_polygon(rounded(r, 2.0), CORRUPT_FILL)
			var x := r.position.x + 8.0
			while x < r.end.x:
				ci.draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), CORRUPT_GRID, 1.0)
				x += 8.0
			var y := r.position.y + 8.0
			while y < r.end.y:
				ci.draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), CORRUPT_GRID, 1.0)
				y += 8.0
		for r in blocks:
			ci.draw_rect(Rect2(r.position + Vector2(6.0, -4.0), r.size), GHOST_A, false, 1.5)
			ci.draw_rect(Rect2(r.position + Vector2(-5.0, 3.0), r.size), GHOST_B, false, 1.5)
		return
	for r in blocks:
		ci.draw_colored_polygon(rounded(r.grow(3.0), 10.0), HONEST_OUTLINE)
	for r in blocks:
		ci.draw_colored_polygon(rounded(r, 8.0), HONEST_FILL)
	for r in blocks:
		if r.size.x > 16.0 and r.size.y > 16.0:
			ci.draw_colored_polygon(rounded(r.grow(-7.0), 5.0), HONEST_INNER)
	for r in blocks:
		if not _covered_in(blocks, Vector2(r.get_center().x, r.position.y - 2.0), r):
			ci.draw_colored_polygon(rounded(Rect2(r.position.x + 4.0, r.position.y + 2.0, r.size.x - 8.0, 6.0), 3.0), HONEST_TOP)


static func paint_bridges(ci: CanvasItem, spans: Array[Rect2], corrupt_style: bool) -> void:
	for r in spans:
		var top := r.position.y
		if corrupt_style:
			ci.draw_rect(Rect2(r.position.x, top, r.size.x, 6.0), CORRUPT_FILL)
			var x := r.position.x
			while x < r.end.x:
				ci.draw_line(Vector2(x, top), Vector2(x + 4.0, top), CORRUPT_GRID, 2.0)
				x += 8.0
			ci.draw_rect(Rect2(r.position.x, top, r.size.x, 6.0), GHOST_B, false, 1.5)
			continue
		var pts := PackedVector2Array()
		var steps := int(r.size.x / 8.0)
		for i in steps + 1:
			var x := r.position.x + r.size.x * i / steps
			pts.append(Vector2(x, top + 3.0 + sin(PI * i / steps) * 7.0))
		ci.draw_polyline(pts, HONEST_OUTLINE, 9.0)
		ci.draw_polyline(pts, HONEST_TOP, 4.0)
		for i in range(1, steps, 2):
			var p := pts[i]
			ci.draw_line(p, p + Vector2(0.0, 6.0 + (i % 3) * 3.0), HONEST_OUTLINE, 3.0)


static func _covered_in(blocks: Array[Rect2], point: Vector2, except: Rect2) -> bool:
	for r in blocks:
		if r != except and r.has_point(point):
			return true
	return false


static func rounded(r: Rect2, radius: float) -> PackedVector2Array:
	var rad := minf(radius, minf(r.size.x, r.size.y) * 0.5)
	var pts := PackedVector2Array()
	var centers := [
		Vector2(r.position.x + rad, r.position.y + rad),
		Vector2(r.end.x - rad, r.position.y + rad),
		Vector2(r.end.x - rad, r.end.y - rad),
		Vector2(r.position.x + rad, r.end.y - rad),
	]
	for c in 4:
		var start := PI + c * PI * 0.5
		for k in 4:
			var a := start + k * PI / 6.0
			pts.append(centers[c] + Vector2(cos(a), sin(a)) * rad)
	return pts
