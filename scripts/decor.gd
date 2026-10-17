@tool
class_name Decor
extends Node2D

## Flat vector scenery. Before the seam: sun, village houses, the cube community, the
## moon poster, rocks and goo hills, then pines, a waterfall, cave crystals, the old camp,
## falling snow and clouds. Past it: grid, cut-off text, stuck bars, wireframe trees,
## missing textures, debug boxes and gizmos, a window with no outside, and the moon as a
## flat drawing.

enum Kind {
	SUN, HOUSE, BG_CUBE, POSTER, ROCK, HILL, GRID, CUT_TEXT, BAR, MOON, WINDOW,
	PINE, BIRD, WATERFALL, WATER, CRYSTAL, CAVE_BACK, STALACTITE, TENT, FLAGS, CAMPFIRE,
	SNOWFALL, CLOUD, WIRE_TREE, CHECKER, GIZMO, DEBUG_BOX,
}

const ANIMATED: Array[Kind] = [
	Kind.SUN, Kind.BG_CUBE, Kind.CUT_TEXT, Kind.BAR, Kind.GRID, Kind.WINDOW, Kind.BIRD, Kind.WATERFALL,
	Kind.WATER, Kind.CRYSTAL, Kind.FLAGS, Kind.CAMPFIRE, Kind.SNOWFALL, Kind.CLOUD, Kind.CHECKER, Kind.DEBUG_BOX,
]
const SMOOTH: Array[Kind] = [
	Kind.SUN, Kind.BG_CUBE, Kind.BIRD, Kind.WATERFALL, Kind.WATER, Kind.CRYSTAL, Kind.FLAGS, Kind.CAMPFIRE,
	Kind.SNOWFALL, Kind.CLOUD,
]

const INK := Color(0.12, 0.06, 0.05)

var kind: Kind = Kind.ROCK
var size := Vector2(32.0, 32.0)
var color := Color.WHITE
var variant: int = 0
var text: String = ""
var seed_value: int = 0

var _t: float = 0.0
var _redraw_clock: float = 0.0
var _poly := PackedVector2Array()
var _points := PackedVector2Array()


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_t = rng.randf() * 10.0
	if kind == Kind.ROCK or kind == Kind.HILL:
		var count := 14
		for i in count:
			var a := TAU * i / count
			var r := 0.5 + rng.randf_range(-0.08, 0.08)
			_poly.append(Vector2(cos(a) * size.x * r, sin(a) * size.y * r))
	if kind in [Kind.SNOWFALL, Kind.CRYSTAL, Kind.CLOUD]:
		var count := 140 if kind == Kind.SNOWFALL else 5
		for i in count:
			_points.append(Vector2(rng.randf_range(-0.5, 0.5) * size.x, rng.randf_range(-0.5, 0.5) * size.y))
	set_process(kind in ANIMATED)


func _process(delta: float) -> void:
	_t += delta
	_redraw_clock -= delta
	if _redraw_clock <= 0.0:
		_redraw_clock = 0.05 if kind in SMOOTH else randf_range(0.08, 0.4)
		queue_redraw()


func _draw() -> void:
	match kind:
		Kind.SUN:
			_draw_sun()
		Kind.HOUSE:
			_draw_house()
		Kind.BG_CUBE:
			_draw_bg_cube()
		Kind.POSTER:
			_draw_poster()
		Kind.ROCK:
			draw_colored_polygon(_scaled(_poly, 1.15), INK)
			draw_colored_polygon(_poly, color)
		Kind.HILL:
			draw_colored_polygon(_poly, color)
		Kind.GRID:
			_draw_grid()
		Kind.CUT_TEXT:
			_draw_cut_text()
		Kind.BAR:
			_draw_bar()
		Kind.MOON:
			# A flat white circle: no shading, no depth. It is a drawing.
			draw_circle(Vector2.ZERO, size.x * 0.5 + 3.0, INK)
			draw_circle(Vector2.ZERO, size.x * 0.5, Color(0.97, 0.97, 0.94))
		Kind.WINDOW:
			_draw_window()
		Kind.PINE:
			_draw_pine()
		Kind.BIRD:
			_draw_bird()
		Kind.WATERFALL:
			_draw_waterfall()
		Kind.WATER:
			_draw_water()
		Kind.CRYSTAL:
			_draw_crystals()
		Kind.CAVE_BACK:
			_draw_cave_back()
		Kind.STALACTITE:
			_draw_stalactite()
		Kind.TENT:
			_draw_tent()
		Kind.FLAGS:
			_draw_flags()
		Kind.CAMPFIRE:
			_draw_campfire()
		Kind.SNOWFALL:
			_draw_snowfall()
		Kind.CLOUD:
			_draw_cloud()
		Kind.WIRE_TREE:
			_draw_wire_tree()
		Kind.CHECKER:
			_draw_checker()
		Kind.GIZMO:
			_draw_gizmo()
		Kind.DEBUG_BOX:
			_draw_debug_box()


func _draw_sun() -> void:
	var r := size.x * 0.5
	for i in 12:
		var a := TAU * i / 12.0 + _t * 0.15
		var dir := Vector2(cos(a), sin(a))
		draw_line(dir * (r + 6.0), dir * (r + 18.0 + sin(_t * 2.0 + i) * 4.0), Color(1.0, 0.8, 0.35, 0.9), 5.0)
	draw_circle(Vector2.ZERO, r + 3.0, INK)
	draw_circle(Vector2.ZERO, r, Color(1.0, 0.82, 0.38))
	draw_circle(Vector2(-r * 0.3, -r * 0.3), r * 0.35, Color(1.0, 0.92, 0.6))


func _draw_house() -> void:
	var w := size.x
	var h := size.y
	var body := Rect2(-w * 0.5, -h * 0.62, w, h * 0.62)
	var roof := PackedVector2Array([Vector2(-w * 0.62, -h * 0.6), Vector2(0.0, -h), Vector2(w * 0.62, -h * 0.6)])
	draw_colored_polygon(_scaled(roof, 1.1), INK)
	draw_colored_polygon(TerrainArt.rounded(body.grow(3.0), 6.0), INK)
	draw_colored_polygon(TerrainArt.rounded(body, 4.0), color)
	draw_colored_polygon(roof, color.darkened(0.45))
	var door := Rect2(-w * 0.12, -h * 0.32, w * 0.24, h * 0.32)
	draw_rect(door, INK)
	var win := Rect2(w * 0.18, -h * 0.5, w * 0.18, h * 0.15)
	draw_rect(win.grow(2.0), INK)
	draw_rect(win, Color(1.0, 0.86, 0.5))


func _draw_bg_cube() -> void:
	var s := size.x
	var hop := maxf(0.0, sin(_t * 3.0)) * s * 0.35
	var r := Rect2(-s * 0.5, -s - hop, s, s)
	draw_colored_polygon(TerrainArt.rounded(r.grow(2.0), 4.0), INK)
	draw_colored_polygon(TerrainArt.rounded(r, 3.0), color)
	var eye_y := r.position.y + s * 0.4
	draw_circle(Vector2(-s * 0.18, eye_y), s * 0.09, INK)
	draw_circle(Vector2(s * 0.18, eye_y), s * 0.09, INK)


func _draw_poster() -> void:
	var paper := Rect2(-size * 0.5, size)
	draw_colored_polygon(TerrainArt.rounded(paper.grow(3.0), 4.0), INK)
	draw_colored_polygon(TerrainArt.rounded(paper, 3.0), Color(0.98, 0.93, 0.8))
	var moon_center := Vector2(0.0, -size.y * 0.12)
	draw_circle(moon_center, size.x * 0.28 + 2.0, INK)
	draw_circle(moon_center, size.x * 0.28, Color.WHITE)
	for i in 3:
		draw_circle(Vector2(-size.x * 0.32 + i * size.x * 0.3, -size.y * 0.38 + (i % 2) * 6.0), 2.0, Color(0.95, 0.75, 0.3))
	if variant == 1:
		var tip := Vector2(0.0, size.y * 0.1)
		draw_line(Vector2(0.0, size.y * 0.42), tip, INK, 4.0)
		draw_colored_polygon(PackedVector2Array([tip + Vector2(-7.0, 6.0), tip + Vector2(0.0, -4.0), tip + Vector2(7.0, 6.0)]), INK)
	else:
		draw_string(ThemeDB.fallback_font, Vector2(-size.x * 0.32, size.y * 0.38), "LUA", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, INK)
	draw_circle(Vector2(0.0, -size.y * 0.5 + 3.0), 3.0, Color(0.85, 0.2, 0.2))


func _draw_grid() -> void:
	var r := Rect2(-size * 0.5, size)
	var step := Tuning.CUBE
	var x := r.position.x
	var col := Color(0.6, 0.72, 0.85, 0.08)
	while x < r.end.x:
		draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), col, 1.0)
		x += step
	var y := r.position.y
	while y < r.end.y:
		draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), col, 1.0)
		y += step
	# A few cells that failed to draw.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + int(_t * 4.0)
	for i in 6:
		var cell := Vector2(rng.randi_range(0, int(size.x / step) - 1), rng.randi_range(0, int(size.y / step) - 1)) * step
		draw_rect(Rect2(r.position + cell, Vector2(step, step)), Color(0.85, 0.9, 1.0, 0.06))


func _draw_cut_text() -> void:
	var font := ThemeDB.fallback_font
	var flicker := 0.25 + 0.75 * float(randf() > 0.15)
	draw_string(font, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.85, 0.9, 1.0, 0.55 * flicker))
	# Cut off: the bottom half of the line is just not there.
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	var cut := Rect2(width * randf_range(0.55, 0.85), -22.0, width, 30.0)
	draw_rect(cut, Color(0.1, 0.1, 0.13))


func _draw_bar() -> void:
	var r := Rect2(-size * 0.5, size)
	draw_rect(r.grow(2.0), Color(0.85, 0.9, 1.0, 0.5), false, 2.0)
	draw_rect(Rect2(r.position, Vector2(r.size.x * 0.99, r.size.y)), Color(0.3, 0.9, 0.5, 0.5))


func _draw_window() -> void:
	var r := Rect2(-size * 0.5, size)
	var bar := Rect2(r.position - Vector2(0.0, 26.0), Vector2(r.size.x, 26.0))
	draw_rect(r, Color(0.85, 0.88, 0.95, 0.9), false, 3.0)
	draw_rect(bar, Color(0.3, 0.32, 0.4, 0.9))
	draw_string(ThemeDB.fallback_font, bar.position + Vector2(10.0, 19.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.9, 0.92, 1.0))
	# A close button that does not respond.
	var close := Rect2(bar.end.x - 24.0, bar.position.y + 3.0, 20.0, 20.0)
	draw_rect(close, Color(0.75, 0.25, 0.3))
	draw_line(close.position + Vector2(5.0, 5.0), close.end - Vector2(5.0, 5.0), Color.WHITE, 2.0)
	draw_line(Vector2(close.position.x + 5.0, close.end.y - 5.0), Vector2(close.end.x - 5.0, close.position.y + 5.0), Color.WHITE, 2.0)


## A pine standing on its base: three stacked tiers and a trunk.
func _draw_pine() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(-w * 0.07 - 3.0, -h * 0.22, w * 0.14 + 6.0, h * 0.22), INK)
	draw_rect(Rect2(-w * 0.07, -h * 0.22, w * 0.14, h * 0.22), Color(0.36, 0.22, 0.12))
	for tier in 3:
		var base := -h * (0.18 + tier * 0.24)
		var half := w * (0.5 - tier * 0.11)
		var tip := base - h * 0.36
		var tri := PackedVector2Array([Vector2(-half, base), Vector2(0.0, tip), Vector2(half, base)])
		draw_colored_polygon(_scaled_about(tri, 1.12, Vector2(0.0, (base + tip) * 0.5)), INK)
		draw_colored_polygon(tri, color.darkened(tier * 0.06))
		draw_line(Vector2(-half * 0.6, base - 3.0), Vector2(half * 0.2, base - h * 0.08), color.lightened(0.18), 3.0)


func _draw_bird() -> void:
	var drift := Vector2(fmod(_t * 26.0, size.x) - size.x * 0.5, sin(_t * 0.7) * 10.0)
	var flap := sin(_t * 9.0) * 5.0
	draw_polyline(PackedVector2Array([drift + Vector2(-7.0, -flap), drift, drift + Vector2(7.0, -flap)]), INK, 2.5)


func _draw_waterfall() -> void:
	var r := Rect2(-size.x * 0.5, -size.y, size.x, size.y)
	draw_rect(r.grow(3.0), Color(INK, 0.6))
	draw_rect(r, Color(0.55, 0.8, 0.95, 0.85))
	var x := r.position.x + 5.0
	var i := 0
	while x < r.end.x - 3.0:
		var y := r.position.y + fmod(_t * 160.0 + i * 37.0, r.size.y)
		draw_line(Vector2(x, y), Vector2(x, minf(y + 26.0, r.end.y)), Color(0.92, 0.97, 1.0, 0.8), 3.0)
		x += 9.0
		i += 1
	for k in 4:
		var bob := sin(_t * 3.0 + k) * 3.0
		draw_circle(Vector2(r.position.x + r.size.x * (k + 0.5) / 4.0, r.end.y - 4.0 + bob), size.x * 0.16, Color(0.95, 0.98, 1.0, 0.85))


## Water lying in a pit: a wavy surface over a darker body.
func _draw_water() -> void:
	var r := Rect2(-size * 0.5, size)
	var top := PackedVector2Array()
	var steps := maxi(4, int(r.size.x / 8.0))
	for i in steps + 1:
		var x := r.position.x + r.size.x * i / steps
		top.append(Vector2(x, r.position.y + sin(_t * 2.6 + i * 0.9) * 2.5))
	var body := top.duplicate()
	body.append(r.end)
	body.append(Vector2(r.position.x, r.end.y))
	draw_colored_polygon(body, Color(0.2, 0.45, 0.62, 0.92))
	draw_polyline(top, Color(0.8, 0.95, 1.0), 3.0)


func _draw_crystals() -> void:
	var glow := 0.55 + 0.25 * sin(_t * 1.8)
	for i in _points.size():
		var p := _points[i] * 0.6
		var h := size.y * (0.35 + 0.12 * (i % 3))
		var w := size.x * 0.12
		var shard := PackedVector2Array([p + Vector2(-w, 0.0), p + Vector2(-w * 0.6, -h * 0.8), p + Vector2(0.0, -h),
				p + Vector2(w * 0.6, -h * 0.7), p + Vector2(w, 0.0)])
		draw_circle(p + Vector2(0.0, -h * 0.5), h * 0.7, Color(color, 0.12 * glow))
		draw_colored_polygon(_scaled_about(shard, 1.18, p + Vector2(0.0, -h * 0.5)), INK)
		draw_colored_polygon(shard, color)
		draw_line(p + Vector2(-w * 0.3, -h * 0.15), p + Vector2(0.0, -h * 0.85), Color(1.0, 1.0, 1.0, 0.5 * glow), 2.0)


## The inside of the mountain: a dark wall behind the cave room, hiding the sky.
func _draw_cave_back() -> void:
	var r := Rect2(-size * 0.5, size)
	draw_rect(r, Color(0.09, 0.07, 0.13))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in 26:
		var p := r.position + Vector2(rng.randf() * r.size.x, rng.randf() * r.size.y)
		draw_circle(p, rng.randf_range(10.0, 34.0), Color(0.14, 0.11, 0.2))
	for i in 18:
		var p := r.position + Vector2(rng.randf() * r.size.x, rng.randf() * r.size.y)
		draw_circle(p, rng.randf_range(1.0, 2.0), Color(0.75, 0.6, 1.0, 0.5))


func _draw_stalactite() -> void:
	var tri := PackedVector2Array([Vector2(-size.x * 0.5, 0.0), Vector2(size.x * 0.5, 0.0), Vector2(size.x * 0.08, size.y)])
	draw_colored_polygon(_scaled_about(tri, 1.2, Vector2(0.0, size.y * 0.3)), INK)
	draw_colored_polygon(tri, color)


func _draw_tent() -> void:
	var w := size.x
	var h := size.y
	var tent := PackedVector2Array([Vector2(-w * 0.5, 0.0), Vector2(0.0, -h), Vector2(w * 0.5, 0.0)])
	draw_colored_polygon(_scaled_about(tent, 1.1, Vector2(0.0, -h * 0.4)), INK)
	draw_colored_polygon(tent, color)
	draw_colored_polygon(PackedVector2Array([Vector2(-w * 0.14, 0.0), Vector2(0.0, -h * 0.55), Vector2(w * 0.14, 0.0)]), INK)
	draw_line(Vector2(0.0, -h), Vector2(0.0, -h - 10.0), INK, 3.0)
	# Abandoned: a torn patch on one side.
	draw_colored_polygon(PackedVector2Array([Vector2(w * 0.2, -h * 0.25), Vector2(w * 0.3, -h * 0.4), Vector2(w * 0.36, -h * 0.18)]),
			color.darkened(0.4))


## A string of little flags. They alternate between the two players' colors: earlier
## climbers, or so it seems.
func _draw_flags() -> void:
	var a := Vector2(-size.x * 0.5, 0.0)
	var b := Vector2(size.x * 0.5, 0.0)
	var pts := PackedVector2Array()
	for i in 13:
		var t := i / 12.0
		pts.append(a.lerp(b, t) + Vector2(0.0, sin(PI * t) * size.y))
	draw_polyline(pts, INK, 2.0)
	var colors := [Color(1.0, 0.56, 0.28), Color(0.3, 0.82, 0.86)]
	for i in range(1, 12):
		var p := pts[i]
		var sway := sin(_t * 2.0 + i) * 2.0
		var flag := PackedVector2Array([p + Vector2(-6.0, 0.0), p + Vector2(6.0, 0.0), p + Vector2(sway, 13.0)])
		draw_colored_polygon(flag, INK)
		draw_colored_polygon(_scaled_about(flag, 0.7, p + Vector2(0.0, 4.0)), colors[i % 2])


func _draw_campfire() -> void:
	for i in 5:
		var a := PI + PI * (i + 0.5) / 5.0
		draw_circle(Vector2(cos(a) * size.x * 0.45, -4.0), 6.0, INK)
		draw_circle(Vector2(cos(a) * size.x * 0.45, -4.0), 4.0, Color(0.55, 0.52, 0.5))
	draw_line(Vector2(-size.x * 0.3, -2.0), Vector2(size.x * 0.25, -12.0), INK, 7.0)
	draw_line(Vector2(size.x * 0.3, -2.0), Vector2(-size.x * 0.25, -12.0), INK, 7.0)
	draw_line(Vector2(-size.x * 0.3, -2.0), Vector2(size.x * 0.25, -12.0), Color(0.3, 0.2, 0.15), 4.0)
	draw_line(Vector2(size.x * 0.3, -2.0), Vector2(-size.x * 0.25, -12.0), Color(0.3, 0.2, 0.15), 4.0)
	# Long cold: only a thin wisp of smoke.
	var pts := PackedVector2Array()
	for i in 8:
		var y := -14.0 - i * 7.0
		pts.append(Vector2(sin(_t * 1.5 + i * 0.7) * (2.0 + i), y))
	draw_polyline(pts, Color(0.9, 0.9, 0.9, 0.45), 3.0)


func _draw_snowfall() -> void:
	for i in _points.size():
		var p := _points[i]
		var y := fmod(p.y + size.y * 0.5 + _t * (22.0 + (i % 5) * 6.0), size.y) - size.y * 0.5
		var x := p.x + sin(_t * 0.8 + i) * 8.0
		draw_circle(Vector2(x, y), 2.0 + (i % 3) * 1.0, Color(1.0, 1.0, 1.0, 0.9))


func _draw_cloud() -> void:
	var drift := sin(_t * 0.15) * 12.0
	for p in _points:
		draw_circle(Vector2(p.x * 0.8 + drift, p.y * 0.3), size.y * 0.42 + 3.0, Color(color.darkened(0.25), color.a))
	for p in _points:
		draw_circle(Vector2(p.x * 0.8 + drift, p.y * 0.3), size.y * 0.42, color)


func _draw_wire_tree() -> void:
	var w := size.x
	var h := size.y
	var edge := Color(0.3, 0.95, 1.0, 0.7)
	draw_line(Vector2(0.0, 0.0), Vector2(0.0, -h * 0.22), edge, 1.5)
	for tier in 3:
		var base := -h * (0.18 + tier * 0.24)
		var half := w * (0.5 - tier * 0.11)
		var tip := Vector2(0.0, base - h * 0.36)
		draw_polyline(PackedVector2Array([Vector2(-half, base), tip, Vector2(half, base), Vector2(-half, base)]), edge, 1.5)
		draw_line(Vector2(-half, base), Vector2(half * 0.3, base - h * 0.2), Color(edge, 0.35), 1.0)


## The texture that failed to load.
func _draw_checker() -> void:
	var r := Rect2(-size * 0.5, size)
	var cell := 16.0
	var flick := 1.0 if randf() > 0.1 else 0.0
	var y := r.position.y
	var row := 0
	while y < r.end.y:
		var x := r.position.x
		var col := 0
		while x < r.end.x:
			var c := Color(0.95, 0.2, 0.75, 0.8 * flick) if (row + col) % 2 == 0 else Color(0.05, 0.05, 0.06, 0.8 * flick)
			draw_rect(Rect2(x, y, minf(cell, r.end.x - x), minf(cell, r.end.y - y)), c)
			x += cell
			col += 1
		y += cell
		row += 1


func _draw_gizmo() -> void:
	var l := size.x
	draw_line(Vector2.ZERO, Vector2(l, 0.0), Color(0.95, 0.3, 0.3), 3.0)
	draw_colored_polygon(PackedVector2Array([Vector2(l + 10.0, 0.0), Vector2(l, -6.0), Vector2(l, 6.0)]), Color(0.95, 0.3, 0.3))
	draw_line(Vector2.ZERO, Vector2(0.0, -l), Color(0.4, 0.95, 0.4), 3.0)
	draw_colored_polygon(PackedVector2Array([Vector2(0.0, -l - 10.0), Vector2(-6.0, -l), Vector2(6.0, -l)]), Color(0.4, 0.95, 0.4))
	draw_rect(Rect2(4.0, -16.0, 12.0, 12.0), Color(0.95, 0.85, 0.3, 0.7))


## A collision box with no art: the hold exists, only the debug view draws it.
func _draw_debug_box() -> void:
	var r := Rect2(-size * 0.5, size)
	var col := Color(0.3, 1.0, 0.45, 0.95 if randf() > 0.08 else 0.4)
	draw_rect(r, Color(col, 0.12))
	var x := r.position.x
	while x < r.end.x:
		draw_line(Vector2(x, r.position.y), Vector2(minf(x + 6.0, r.end.x), r.position.y), col, 2.0)
		draw_line(Vector2(x, r.end.y), Vector2(minf(x + 6.0, r.end.x), r.end.y), col, 2.0)
		x += 10.0
	draw_line(r.position, Vector2(r.position.x, r.end.y), col, 2.0)
	draw_line(Vector2(r.end.x, r.position.y), r.end, col, 2.0)
	draw_line(r.position, r.end, Color(col, 0.5), 1.0)
	draw_line(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y), Color(col, 0.5), 1.0)
	if text != "":
		draw_string(ThemeDB.fallback_font, r.position + Vector2(0.0, -6.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)


func _scaled_about(poly: PackedVector2Array, factor: float, center: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(center + (p - center) * factor)
	return out


func _scaled(poly: PackedVector2Array, factor: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(p * factor)
	return out
