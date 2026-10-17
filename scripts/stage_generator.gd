@tool
class_name StageGenerator
extends Node2D

signal generated(start_position: Vector2, goal_position: Vector2)

@export var generation_seed: int = 1
@export var rope_length: float = 220.0
@export var band_count: int = 5
@export var stage_width: float = 900.0
@export var band_height: float = 150.0
@export var show_graph: bool = true
@export_tool_button("Generate Stage") var generate_action = generate


class Island:
	var id: int
	var band: int
	var position: Vector2
	var radius: float
	var stand_point: Vector2
	var edges: Array[int] = []


var islands: Array[Island] = []
var goal_position: Vector2 = Vector2.ZERO
var start_position: Vector2 = Vector2.ZERO

var _rng := RandomNumberGenerator.new()
var _graph_edges: Array[Dictionary] = []
var _islands_root: Node2D
var _decor_root: Node2D
var _goal_root: Node2D


func _ready() -> void:
	_ensure_roots()


func generate() -> void:
	_ensure_roots()
	_clear_generated()
	islands.clear()
	_graph_edges.clear()

	var seed_value := generation_seed
	if seed_value == 0:
		seed_value = randi()
	_rng.seed = seed_value

	_build_islands()
	_connect_and_repair()
	_build_scenery()
	_build_goal()
	queue_redraw()
	generated.emit(start_position, goal_position)


func _ensure_roots() -> void:
	_islands_root = get_node_or_null("Islands") as Node2D
	if _islands_root == null:
		_islands_root = Node2D.new()
		_islands_root.name = "Islands"
		add_child(_islands_root)
	_decor_root = get_node_or_null("Decor") as Node2D
	if _decor_root == null:
		_decor_root = Node2D.new()
		_decor_root.name = "Decor"
		add_child(_decor_root)
	_goal_root = get_node_or_null("Goal") as Node2D
	if _goal_root == null:
		_goal_root = Node2D.new()
		_goal_root.name = "Goal"
		add_child(_goal_root)


func _clear_generated() -> void:
	for root in [_islands_root, _decor_root, _goal_root]:
		if root == null:
			continue
		for child in root.get_children():
			root.remove_child(child)
			child.free()


func _build_islands() -> void:
	var min_gap := 170.0
	for band in band_count:
		var count := 1
		if band > 0 and band < band_count - 1:
			count = _rng.randi_range(1, 3)
		var placed_x: Array[float] = []
		var y := -float(band) * band_height
		for _i in count:
			var x := 0.0
			for _attempt in 24:
				x = _rng.randf_range(-stage_width * 0.45, stage_width * 0.45)
				var ok := true
				for other_x in placed_x:
					if absf(other_x - x) < min_gap:
						ok = false
						break
				if ok:
					break
			placed_x.append(x)
			var island := Island.new()
			island.id = islands.size()
			island.band = band
			island.radius = _rng.randf_range(46.0, 72.0)
			island.position = Vector2(x, y + _rng.randf_range(-22.0, 22.0))
			island.stand_point = island.position + Vector2(0.0, -island.radius * 0.35)
			islands.append(island)
	if not islands.is_empty():
		start_position = islands[0].stand_point + Vector2(0.0, -8.0)


func _connect_and_repair() -> void:
	for band in range(band_count - 1):
		var lower := _ids_in_band(band)
		var upper := _ids_in_band(band + 1)
		if lower.is_empty() or upper.is_empty():
			continue
		var best_i := lower[0]
		var best_j := upper[0]
		var best_d := INF
		for i in lower:
			for j in upper:
				var d: float = islands[i].stand_point.distance_to(islands[j].stand_point)
				if d < best_d:
					best_d = d
					best_i = i
					best_j = j
		_nudge_edge(best_i, best_j)
		_add_edge(best_i, best_j)
		for i in lower:
			for j in upper:
				if i == best_i and j == best_j:
					continue
				if islands[i].stand_point.distance_to(islands[j].stand_point) <= rope_length * 0.95:
					_add_edge(i, j)
		for a in range(lower.size()):
			for b in range(a + 1, lower.size()):
				if islands[lower[a]].stand_point.distance_to(islands[lower[b]].stand_point) <= rope_length:
					_add_edge(lower[a], lower[b])
	var last_ids := _ids_in_band(band_count - 1)
	for a in range(last_ids.size()):
		for b in range(a + 1, last_ids.size()):
			if islands[last_ids[a]].stand_point.distance_to(islands[last_ids[b]].stand_point) <= rope_length:
				_add_edge(last_ids[a], last_ids[b])

	for _attempt in 10:
		if _validate_rope_path():
			break
		_tighten_spine()
	_rebuild_debug_edges()


func _nudge_edge(from_id: int, to_id: int) -> void:
	var a := islands[from_id]
	var b := islands[to_id]
	var min_d := rope_length * 0.6
	var max_d := rope_length * 0.92
	var offset := Vector2(0.0, -b.radius * 0.35)
	var target := b.stand_point
	var delta := target - a.stand_point
	var dist := delta.length()
	if dist < 0.001:
		target = a.stand_point + Vector2(min_d * 0.5, -band_height * 0.7)
	elif dist > max_d:
		target = a.stand_point + delta.normalized() * max_d
	elif dist < min_d:
		target = a.stand_point + delta.normalized() * min_d
	b.stand_point = target
	b.position = b.stand_point - offset


func _tighten_spine() -> void:
	for band in range(band_count - 1):
		var lower := _ids_in_band(band)
		var upper := _ids_in_band(band + 1)
		if lower.is_empty() or upper.is_empty():
			continue
		var i := lower[0]
		var j := upper[0]
		var best := INF
		for li in lower:
			for ui in upper:
				var d: float = islands[li].stand_point.distance_to(islands[ui].stand_point)
				if d < best:
					best = d
					i = li
					j = ui
		islands[j].position.x = lerpf(islands[j].position.x, islands[i].position.x, 0.45)
		islands[j].stand_point = islands[j].position + Vector2(0.0, -islands[j].radius * 0.35)
		_add_edge(i, j)


func _add_edge(a: int, b: int) -> void:
	if a == b:
		return
	if not islands[a].edges.has(b):
		islands[a].edges.append(b)
	if not islands[b].edges.has(a):
		islands[b].edges.append(a)


func _ids_in_band(band: int) -> Array[int]:
	var ids: Array[int] = []
	for island in islands:
		if island.band == band:
			ids.append(island.id)
	return ids


func _is_pair_legal(i: int, j: int) -> bool:
	if i == j:
		return true
	return islands[i].stand_point.distance_to(islands[j].stand_point) <= rope_length


func _validate_rope_path() -> bool:
	if islands.is_empty():
		return false
	var start := Vector2i(0, 0)
	var seen: Dictionary = {}
	var queue: Array[Vector2i] = [start]
	seen[start] = true
	while not queue.is_empty():
		var state: Vector2i = queue.pop_front()
		var a := state.x
		var b := state.y
		if a == b and islands[a].band == band_count - 1:
			return true
		var opts_a: Array[int] = islands[a].edges.duplicate()
		opts_a.append(a)
		var opts_b: Array[int] = islands[b].edges.duplicate()
		opts_b.append(b)
		for na in opts_a:
			if not _is_pair_legal(na, b):
				continue
			var ns_a := Vector2i(mini(na, b), maxi(na, b))
			if not seen.has(ns_a):
				seen[ns_a] = true
				queue.append(ns_a)
		for nb in opts_b:
			if not _is_pair_legal(a, nb):
				continue
			var ns_b := Vector2i(mini(a, nb), maxi(a, nb))
			if not seen.has(ns_b):
				seen[ns_b] = true
				queue.append(ns_b)
	return false


func _rebuild_debug_edges() -> void:
	_graph_edges.clear()
	var seen: Dictionary = {}
	for island in islands:
		for other_id in island.edges:
			var key := Vector2i(mini(island.id, other_id), maxi(island.id, other_id))
			if seen.has(key):
				continue
			seen[key] = true
			_graph_edges.append({
				"a": island.stand_point,
				"b": islands[other_id].stand_point,
				"legal": _is_pair_legal(island.id, other_id),
			})


func _build_scenery() -> void:
	for island in islands:
		var balls := _make_metaballs(island)
		var polygon := _metaball_polygon(balls)
		if polygon.size() < 3:
			continue
		polygon = _rdp(polygon, 2.2)
		_ensure_clockwise(polygon)
		_spawn_island_body(island, polygon)
		_spawn_drips(polygon)
		if island.band > 0 and _rng.randf() < 0.55:
			_spawn_background_blob(island.position + Vector2(_rng.randf_range(-220.0, 220.0), 40.0), island.radius * 0.7)


func _make_metaballs(island: Island) -> Array[Dictionary]:
	var balls: Array[Dictionary] = []
	var count := _rng.randi_range(3, 6)
	for _i in count:
		var offset := Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(8.0, island.radius * 0.55)
		offset.y *= 0.72
		balls.append({
			"c": island.position + offset,
			"r": _rng.randf_range(island.radius * 0.38, island.radius * 0.62),
		})
	return balls


func _metaball_polygon(balls: Array[Dictionary]) -> PackedVector2Array:
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for ball in balls:
		var c: Vector2 = ball["c"]
		var r: float = ball["r"]
		min_p = min_p.min(c - Vector2(r, r) * 2.2)
		max_p = max_p.max(c + Vector2(r, r) * 2.2)
	var cell := 8.0
	var cols := maxi(8, int(ceil((max_p.x - min_p.x) / cell)) + 1)
	var rows := maxi(8, int(ceil((max_p.y - min_p.y) / cell)) + 1)
	var field: Array = []
	field.resize(rows)
	for y in rows:
		var row: Array[float] = []
		row.resize(cols)
		for x in cols:
			row[x] = _field(min_p + Vector2(x, y) * cell, balls)
		field[y] = row
	var iso := 1.0
	var segments: Array = []
	for y in rows - 1:
		for x in cols - 1:
			var v := [
				field[y][x],
				field[y][x + 1],
				field[y + 1][x + 1],
				field[y + 1][x],
			]
			var p := [
				min_p + Vector2(x, y) * cell,
				min_p + Vector2(x + 1, y) * cell,
				min_p + Vector2(x + 1, y + 1) * cell,
				min_p + Vector2(x, y + 1) * cell,
			]
			var idx := 0
			if v[0] >= iso:
				idx |= 1
			if v[1] >= iso:
				idx |= 2
			if v[2] >= iso:
				idx |= 4
			if v[3] >= iso:
				idx |= 8
			for seg in _ms_segments(idx, p, v, iso):
				segments.append(seg)
	return _stitch(segments)


func _field(point: Vector2, balls: Array[Dictionary]) -> float:
	var sum := 0.0
	for ball in balls:
		var d: float = maxf(point.distance_to(ball["c"]), 0.001)
		var r: float = ball["r"]
		sum += (r * r) / (d * d)
	return sum


func _ms_segments(idx: int, p: Array, v: Array, iso: float) -> Array:
	if idx == 0 or idx == 15:
		return []
	var e := [
		_cross(p[0], p[1], v[0], v[1], iso),
		_cross(p[1], p[2], v[1], v[2], iso),
		_cross(p[2], p[3], v[2], v[3], iso),
		_cross(p[3], p[0], v[3], v[0], iso),
	]
	var table := {
		1: [[3, 0]],
		2: [[0, 1]],
		3: [[3, 1]],
		4: [[1, 2]],
		5: [[3, 0], [1, 2]],
		6: [[0, 2]],
		7: [[3, 2]],
		8: [[2, 3]],
		9: [[0, 2]],
		10: [[0, 1], [2, 3]],
		11: [[1, 2]],
		12: [[1, 3]],
		13: [[0, 1]],
		14: [[0, 3]],
	}
	var result: Array = []
	if not table.has(idx):
		return result
	for pair in table[idx]:
		result.append([e[pair[0]], e[pair[1]]])
	return result


func _cross(pa: Vector2, pb: Vector2, va: float, vb: float, iso: float) -> Vector2:
	var dv := vb - va
	var t := 0.5
	if absf(dv) > 0.0001:
		t = clampf((iso - va) / dv, 0.0, 1.0)
	return pa.lerp(pb, t)


func _stitch(segments: Array) -> PackedVector2Array:
	var poly := PackedVector2Array()
	if segments.is_empty():
		return poly
	var used := PackedByteArray()
	used.resize(segments.size())
	poly.append(segments[0][0])
	poly.append(segments[0][1])
	used[0] = 1
	for _guard in segments.size():
		var end: Vector2 = poly[poly.size() - 1]
		var found := false
		for i in segments.size():
			if used[i] == 1:
				continue
			var a: Vector2 = segments[i][0]
			var b: Vector2 = segments[i][1]
			if a.distance_to(end) < 0.8:
				poly.append(b)
				used[i] = 1
				found = true
				break
			if b.distance_to(end) < 0.8:
				poly.append(a)
				used[i] = 1
				found = true
				break
		if not found:
			break
	if poly.size() > 2 and poly[0].distance_to(poly[poly.size() - 1]) < 1.5:
		poly.remove_at(poly.size() - 1)
	return poly


func _rdp(points: PackedVector2Array, epsilon: float) -> PackedVector2Array:
	if points.size() < 3:
		return points
	var first := 0
	var last := points.size() - 1
	var max_d := 0.0
	var max_i := 0
	for i in range(1, last):
		var d := _perp_dist(points[i], points[first], points[last])
		if d > max_d:
			max_d = d
			max_i = i
	if max_d > epsilon:
		var left := _rdp(points.slice(0, max_i + 1), epsilon)
		var right := _rdp(points.slice(max_i, points.size()), epsilon)
		var merged := PackedVector2Array()
		for i in left.size() - 1:
			merged.append(left[i])
		for p in right:
			merged.append(p)
		return merged
	return PackedVector2Array([points[first], points[last]])


func _perp_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 0.0001:
		return p.distance_to(a)
	return absf(ab.cross(p - a)) / sqrt(len_sq)


func _ensure_clockwise(poly: PackedVector2Array) -> void:
	var area := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		area += p.x * q.y - q.x * p.y
	if area > 0.0:
		poly.reverse()


func _spawn_island_body(island: Island, polygon: PackedVector2Array) -> void:
	var body := StaticBody2D.new()
	body.name = "Island_%d" % island.id
	body.collision_layer = 1
	body.collision_mask = 0
	var outline := Polygon2D.new()
	outline.polygon = _scaled_poly(polygon, island.position, 1.08)
	outline.color = Color(0.16, 0.08, 0.05)
	body.add_child(outline)
	var fill := Polygon2D.new()
	fill.polygon = polygon
	fill.color = Color(0.42, 0.24, 0.09)
	body.add_child(fill)
	var inner := Polygon2D.new()
	inner.polygon = _scaled_poly(polygon, island.position, 0.62)
	inner.color = Color(0.62, 0.38, 0.12)
	body.add_child(inner)
	var collider := CollisionPolygon2D.new()
	collider.polygon = polygon
	body.add_child(collider)
	_islands_root.add_child(body)
	_own_if_editor(body)


func _scaled_poly(polygon: PackedVector2Array, center: Vector2, scale_v: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in polygon:
		out.append(center + (p - center) * scale_v)
	return out


func _spawn_drips(polygon: PackedVector2Array) -> void:
	if polygon.is_empty():
		return
	var lowest: Array[Vector2] = []
	var copy: Array[Vector2] = []
	for p in polygon:
		copy.append(p)
	copy.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.y > b.y)
	for i in mini(3, copy.size()):
		lowest.append(copy[i])
	for origin in lowest:
		if _rng.randf() < 0.35:
			continue
		var line := Line2D.new()
		line.width = _rng.randf_range(3.0, 6.0)
		line.default_color = Color(0.28, 0.14, 0.08)
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		var points := PackedVector2Array()
		var cursor := origin
		points.append(cursor)
		var branches := _rng.randi_range(2, 4)
		for _i in branches:
			cursor += Vector2(_rng.randf_range(-10.0, 10.0), _rng.randf_range(14.0, 28.0))
			points.append(cursor)
		line.points = points
		_decor_root.add_child(line)
		_own_if_editor(line)


func _spawn_background_blob(center: Vector2, radius: float) -> void:
	var fake := Island.new()
	fake.position = center
	fake.radius = radius
	var poly := _metaball_polygon(_make_metaballs(fake))
	if poly.size() < 3:
		return
	var blob := Polygon2D.new()
	blob.polygon = poly
	blob.color = Color(0.12, 0.07, 0.1, 0.55)
	blob.z_index = -2
	_decor_root.add_child(blob)
	_own_if_editor(blob)


func _build_goal() -> void:
	var top_ids := _ids_in_band(band_count - 1)
	if top_ids.is_empty():
		return
	var island := islands[top_ids[0]]
	goal_position = island.stand_point + Vector2(0.0, -70.0)
	var pipe := Node2D.new()
	pipe.position = goal_position
	var mouth := Polygon2D.new()
	mouth.polygon = PackedVector2Array([
		Vector2(-28, 18), Vector2(28, 18), Vector2(22, -8), Vector2(-22, -8),
	])
	mouth.color = Color(0.18, 0.48, 0.32)
	pipe.add_child(mouth)
	var tube := Polygon2D.new()
	tube.polygon = PackedVector2Array([
		Vector2(-16, -8), Vector2(16, -8), Vector2(16, -80), Vector2(-16, -80),
	])
	tube.color = Color(0.12, 0.36, 0.24)
	pipe.add_child(tube)
	var lip := Polygon2D.new()
	lip.polygon = PackedVector2Array([
		Vector2(-32, 18), Vector2(32, 18), Vector2(32, 28), Vector2(-32, 28),
	])
	lip.color = Color(0.25, 0.62, 0.4)
	pipe.add_child(lip)
	_goal_root.add_child(pipe)
	_own_if_editor(pipe)


func _own_if_editor(node: Node) -> void:
	if not Engine.is_editor_hint() or get_tree() == null:
		return
	var scene_root := get_tree().edited_scene_root
	if scene_root == null:
		return
	node.owner = scene_root
	for child in node.get_children():
		_own_if_editor(child)


func _draw() -> void:
	if not show_graph:
		return
	for e in _graph_edges:
		var col := Color(0.35, 0.9, 0.45, 0.85) if e["legal"] else Color(0.9, 0.25, 0.2, 0.85)
		draw_line(e["a"], e["b"], col, 2.2)
	for island in islands:
		draw_circle(island.stand_point, 5.0, Color(0.95, 0.85, 0.35, 0.9))
