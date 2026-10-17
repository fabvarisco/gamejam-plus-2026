@tool
class_name Decor
extends Node2D

## Flat vector scenery. Before the seam: sun, village houses, the cube community, the
## moon poster, rocks and goo hills. Past it: grid, cut-off text, stuck bars, a window
## with no outside, and the moon as a flat drawing.

enum Kind { SUN, HOUSE, BG_CUBE, POSTER, ROCK, HILL, GRID, CUT_TEXT, BAR, MOON, WINDOW }

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
	set_process(kind in [Kind.SUN, Kind.BG_CUBE, Kind.CUT_TEXT, Kind.BAR, Kind.GRID, Kind.WINDOW])


func _process(delta: float) -> void:
	_t += delta
	_redraw_clock -= delta
	if _redraw_clock <= 0.0:
		_redraw_clock = 0.05 if kind in [Kind.SUN, Kind.BG_CUBE] else randf_range(0.08, 0.4)
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


func _scaled(poly: PackedVector2Array, factor: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(p * factor)
	return out
