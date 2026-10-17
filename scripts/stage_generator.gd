@tool
class_name StageGenerator
extends Node2D

## Builds the mountain: eight single-screen rooms stacked bottom to top, laid out on cube
## multiples (see GDD "Level shape" and "The eight rooms"). Rooms alternate direction, so
## a room's exit opening is the next room's entry. Templates are written for a room that
## is entered on the left (local x grows away from the entry) and mirrored when needed.
## The seed varies crux positions, step widths and all scenery.
##
## Local room coordinates are in cubes: x in [0, ROOM_W), y up from the floor surface.
## A room's floor band (y in [-1, 0)) is also the ceiling of the room below.

signal generated

const C := Tuning.CUBE
const W := Tuning.ROOM_W

const ROOM_NAMES: Array[String] = ["Village", "Ledge", "Gap", "Witness", "Wall", "Seam", "Fault", "Edge"]

@export var generation_seed: int = 1
@export_tool_button("Generate Stage") var generate_action = generate


class Room:
	var index: int
	var floor_y: float
	var mirrored: bool
	var corrupted: bool
	var spawns: Array[Vector2] = []
	## Pits. A cube dangling into one is held by the rope; both in it is a fall.
	var fall_zones: Array[Rect2] = []
	var art: TerrainArt
	var decor: Node2D


var rooms: Array[Room] = []
var witness_trigger := Rect2()
## Room 4, below the near ledge: once the lift has risen, both cubes down here are stuck.
var lift_stuck_zone := Rect2()
var witness_spots: Array[Vector2] = []
var echo_x: float = 0.0
var border_left_x: float = 0.0
var moon: Decor
var lift: Lift
var fail_floor: FailFloor
var jitters: Array[JitterPlatform] = []

var _rng := RandomNumberGenerator.new()
var _rope_static: Array[Rect2] = []
var _rope_cache: Array[Rect2] = []
var _ending: bool = false
var _root: Node2D
var _body: StaticBody2D


func generate() -> void:
	_clear()
	var seed_value := generation_seed
	if seed_value == 0:
		seed_value = randi()
	_rng.seed = seed_value
	_ending = false

	for i in Tuning.ROOM_COUNT:
		var room := Room.new()
		room.index = i
		room.floor_y = floor_y(i)
		room.mirrored = i % 2 == 1
		room.corrupted = i >= 5
		room.art = TerrainArt.new()
		room.art.name = "Art%d" % (i + 1)
		room.art.corrupt = room.corrupted
		room.art.jitter = i == 6
		room.art.seed_value = _rng.randi()
		room.decor = Node2D.new()
		room.decor.name = "Decor%d" % (i + 1)
		room.decor.z_index = -5
		_root.add_child(room.decor)
		_root.add_child(room.art)
		rooms.append(room)

	_build_village(rooms[0])
	_build_ledge(rooms[1])
	_build_gap(rooms[2])
	_build_witness(rooms[3])
	_build_wall(rooms[4])
	_build_seam(rooms[5])
	_build_fault(rooms[6])
	_build_edge(rooms[7])

	for room in rooms:
		room.art.finalize()
	set_corrupted_visible(false)
	generated.emit()


func floor_y(index: int) -> float:
	return -float(index * Tuning.ROOM_PITCH) * C


## Which room a world-space height belongs to: from just below its floor band up to
## just below the next room's band.
func room_index_at(y: float) -> int:
	var idx := int(floor((-y + C) / (Tuning.ROOM_PITCH * C)))
	return clampi(idx, 0, Tuning.ROOM_COUNT - 1)


func room_center(index: int) -> Vector2:
	return Vector2(W * 0.5 * C, floor_y(index) - Tuning.ROOM_H * 0.5 * C)


func rope_colliders() -> Array[Rect2]:
	if _ending:
		return []
	_rope_cache.clear()
	_rope_cache.append_array(_rope_static)
	if lift != null:
		_rope_cache.append(lift.top_rect())
	for j in jitters:
		if j.solid:
			_rope_cache.append(j.rect)
	if fail_floor != null and not fail_floor.failed:
		_rope_cache.append_array(fail_floor.rects)
	return _rope_cache


func set_ending(on: bool) -> void:
	_ending = on


## Rooms 6 to 8 do not exist on screen until the cubes glitch through the seam.
func set_corrupted_visible(on: bool) -> void:
	for room in rooms:
		if room.corrupted:
			room.art.visible = on
			room.decor.visible = on
	for j in jitters:
		j.visible = on
	if fail_floor != null:
		fail_floor.visible = on


# --- Rooms -------------------------------------------------------------------------

func _build_village(room: Room) -> void:
	# Flat ground: walk together, stretch the rope, learn the three-cube limit.
	_solid(room, -6, -8, W + 12, 8)
	_walls(room, true, true)
	_stairs(room, 18, 24, 1, 6)
	_exit_steps(room)
	room.spawns = [_spot(room, 3.0, 0.0), _spot(room, 4.5, 0.0)]

	_decor(room, Decor.Kind.SUN, _spot(room, 32.6, 8.0), Vector2(1.6, 1.6) * C)
	var hx := 0.4
	for i in 2:
		var w := _rng.randf_range(2.4, 3.0)
		_decor(room, Decor.Kind.HOUSE, _ground(room, hx + w * 0.5), Vector2(w, _rng.randf_range(2.4, 3.0)) * C,
				Color.from_hsv(_rng.randf_range(0.0, 0.12), 0.45, 0.85))
		hx += w + _rng.randf_range(0.4, 0.9)
	_decor(room, Decor.Kind.POSTER, _spot(room, 6.5, 2.8), Vector2(1.8, 2.2) * C)
	for i in 6:
		var size := _rng.randf_range(0.35, 0.55)
		_decor(room, Decor.Kind.BG_CUBE, _ground(room, _rng.randf_range(0.6, 7.5)), Vector2(size, size) * C,
				Color.from_hsv(_rng.randf(), 0.55, 0.95))
	for i in 5:
		var size := _rng.randf_range(0.3, 0.45)
		var side := -1.0 if i % 2 == 0 else 1.0
		var x := 15.0 + side * _rng.randf_range(16.5, 19.5)
		_decor(room, Decor.Kind.BG_CUBE, Vector2(x * C, room.floor_y), Vector2(size, size) * C, Color.from_hsv(_rng.randf(), 0.5, 0.95))
	_hills(room, Color(0.85, 0.52, 0.3, 0.55))


func _build_ledge(room: Room) -> void:
	# A 2-cube lip a solo jump cannot reach. One stays on the ground as a step; the
	# other climbs it and hauls the partner up with the rope.
	_floor_band(room)
	_walls(room, true, true)
	var lip := 11 + _rng.randi_range(0, 2)
	_solid(room, lip, 0, W - lip, 2)
	_stairs(room, 20, 24, 3, 6)
	_exit_steps(room)
	room.spawns = _entry_spawns(room)
	_decor(room, Decor.Kind.POSTER, _spot(room, lip - 2.5, 3.2), Vector2(1.8, 2.2) * C, Color.WHITE, 1)
	_rocks(room, 3)
	_hills(room, Color(0.8, 0.5, 0.32, 0.5))


func _build_gap(room: Room) -> void:
	# A 2-cube gap between a high ledge jutting over open space and a far ledge two cubes
	# lower. One holds the edge, the other swings (pumping under the ledge) and grabs the
	# far side. A fall lands on the room floor, and the stairs lead back up.
	_floor_band(room)
	_walls(room, true, true)
	var near := 11 + _rng.randi_range(0, 2)
	_stairs(room, near - 5, near, 1, 5)
	_solid(room, near, 5, 3, 1)
	var far := near + 5
	_solid(room, far, 0, W - far, 4)
	_stairs(room, 22, 24, 5, 6)
	_exit_steps(room)
	room.spawns = _entry_spawns(room)
	_rocks(room, 5)
	_hills(room, Color(0.72, 0.46, 0.34, 0.45))


func _build_witness(room: Room) -> void:
	# Weight: the lift stays down while someone stands on it and rises once both leave.
	# One stays on it as the anchor while the other crosses the 2-cube gap.
	_floor_band(room)
	_walls(room, true, true)
	_stairs(room, 5, 10, 1, 5)
	_solid(room, 10, 0, 2, 6)
	lift = Lift.new()
	lift.name = "Lift"
	lift.setup(_rect(room, 12, 5, 3, 1), 3.0 * C, room.floor_y - Tuning.ROOM_H * C)
	_root.add_child(lift)
	_solid(room, 17, 0, W - 17, 4)
	_stairs(room, 22, 24, 5, 6)
	_exit_steps(room)
	room.spawns = _entry_spawns(room)
	lift_stuck_zone = _rect(room, 0, 0, 15, 5.5)

	# The climb pauses on the exit steps, looking out over the face of the mountain.
	witness_trigger = _rect(room, 24, 6.5, 6, 4.5)
	witness_spots = [_spot(room, 25.5, 8.0), _spot(room, 26.5, 9.0)]
	echo_x = _spot(room, 31.5, 0.0).x
	_rocks(room, 4)
	_hills(room, Color(0.66, 0.42, 0.36, 0.4))


func _build_wall(room: Room) -> void:
	# The honest climb ends. The summit faces a gap wider than any stretch of the rope,
	# and the sky above it is empty. The ceiling over the stairs is the wall, and one
	# corner of it is broken: the seam.
	_floor_band(room, 27)
	_walls(room, true, false)
	_solid(room, 12, 0, 2, 1)
	_solid(room, 14, 0, 2, 2)
	_solid(room, 16, 0, 1, 3)
	_solid(room, 17, 0, 1, 4)
	_solid(room, 18, 0, 2, 5)
	_solid(room, 20, 0, 7, 6)
	# The next hold, six cubes out. Nothing reaches it.
	_solid(room, 33, 6, 2, 1)
	room.spawns = _entry_spawns(room)

	# The wall: room 6's floor, drawn as this room's ceiling. Collision forgot [16, 19).
	_solid(room, 0, 10, 16, 1)
	_solid(room, 19, 10, 3, 1)
	var seam := GlitchArt.new()
	seam.name = "Seam"
	seam.rects = [_rect(room, 16, 10, 3, 1)]
	_root.add_child(seam)
	# A broken corner and holds that draw in the wrong place, clipping into the wall.
	_solid(room, 19, 5, 1, 2)
	var holds := GlitchArt.new()
	holds.name = "SeamHolds"
	holds.draw_offset = Vector2(9.0, -6.0)
	for h in [[18, 7], [17, 8], [16, 9]]:
		var r := _rect(room, h[0], h[1], 1, 1)
		_add_collision(r)
		holds.rects.append(r)
	_root.add_child(holds)
	_hills(room, Color(0.6, 0.4, 0.4, 0.35))


func _build_seam(room: Room) -> void:
	# Past the seam. The floor is room 5's ceiling; a 1-wide staircase climbs left to
	# room 7, which is entered from the left.
	room.mirrored = false
	_walls(room, true, false)
	for top in range(1, 11):
		_solid(room, 13 - top, 0, 1, top)
	room.spawns = [_spot(room, 14.0, 0.0), _spot(room, 15.3, 0.0)]
	_corrupt_decor(room, ["simulat", "ERR 0x05", "C:\\montanha\\sala_06"])


func _build_fault(room: Room) -> void:
	# First mix of two ideas on ground that jitters and blinks: a lip, then a gap.
	room.mirrored = false
	_floor_band(room)
	_walls(room, true, true)
	_solid(room, 8, 0, 2, 2)
	_stairs(room, 10, 13, 3, 5)
	_solid(room, 13, 5, 3, 1)
	_solid(room, 18, 0, W - 18, 4)
	_jitter(room, 22, 4, 1, 1, 0.0)
	_jitter(room, 23, 4, 1, 2, 1.4)
	_exit_steps(room)
	room.spawns = _entry_spawns(room)
	_corrupt_decor(room, ["carregando... 99%", "sala_07.tmp", "lua.png"])


func _build_edge(room: Room) -> void:
	# No new puzzle and no platform past the screen. The rope hits the border.
	room.mirrored = false
	fail_floor = FailFloor.new()
	fail_floor.name = "FailFloor"
	fail_floor.setup([_rect(room, -5, -1, 27, 1)], [_rect(room, 22, -1, 8, 1)])
	_root.add_child(fail_floor)
	_solid(room, -6, -1, 1, 14)
	_solid(room, 35, -1, 1, 14)
	border_left_x = -5.0 * C
	room.spawns = [_spot(room, 18.5, 0.0), _spot(room, 20.0, 0.0)]
	moon = _decor(room, Decor.Kind.MOON, _spot(room, 7.0, 8.8), Vector2(3.6, 3.6) * C)
	_decor(room, Decor.Kind.WINDOW, _spot(room, 7.0, 8.8), Vector2(11.0, 7.4) * C, Color.WHITE, 0, "lua.png")
	_corrupt_decor(room, ["FIM DA SIMULA", "não há saída", "sala_08"])


# --- Building blocks -----------------------------------------------------------------

## A rectangle in local cube coordinates, converted to world space.
func _rect(room: Room, lx: float, ly: float, w: float, h: float) -> Rect2:
	var x := (W - lx - w) if room.mirrored else lx
	return Rect2(x * C, room.floor_y - (ly + h) * C, w * C, h * C)


func _spot(room: Room, lx: float, ly: float) -> Vector2:
	var x := (W - lx) if room.mirrored else lx
	return Vector2(x * C, room.floor_y - ly * C - C * 0.5)


func _ground(room: Room, lx: float) -> Vector2:
	var x := (W - lx) if room.mirrored else lx
	return Vector2(x * C, room.floor_y)


func _zone(room: Room, lx: float, ly: float, w: float, h: float) -> Rect2:
	return _rect(room, lx, ly, w, h)


func _solid(room: Room, lx: float, ly: float, w: float, h: float, art: TerrainArt = null) -> Rect2:
	var r := _rect(room, lx, ly, w, h)
	_add_collision(r)
	_rope_static.append(r)
	(art if art != null else room.art).rects.append(r)
	return r


func _add_collision(r: Rect2) -> void:
	var shape := RectangleShape2D.new()
	shape.size = r.size
	var cs := CollisionShape2D.new()
	cs.shape = shape
	cs.position = r.get_center()
	_body.add_child(cs)


## The room's floor, drawn as the ceiling of the room below. Over the entry (local x in
## [0, 8), where the room below has its exit staircase) it is a one-way goo bridge:
## solid from above, passable from below.
func _floor_band(room: Room, to_x: int = W) -> void:
	var art := rooms[room.index - 1].art if room.index > 0 else room.art
	_bridge(room, 0, -1, 8, 1, art)
	_solid(room, 8, -1, to_x - 8, 1, art)


func _bridge(room: Room, lx: float, ly: float, w: float, h: float, art: TerrainArt) -> void:
	var r := _rect(room, lx, ly, w, h)
	var shape := RectangleShape2D.new()
	shape.size = r.size
	var cs := CollisionShape2D.new()
	cs.shape = shape
	cs.position = r.get_center()
	cs.one_way_collision = true
	_body.add_child(cs)
	art.bridges.append(r)


func _walls(room: Room, left: bool, right: bool) -> void:
	if left:
		_solid(room, -1 if not room.mirrored else W, -1, 1, Tuning.ROOM_PITCH + 1)
	if right:
		_solid(room, W if not room.mirrored else -1, -1, 1, Tuning.ROOM_PITCH + 1)


## Solid 1-cube steps rising from `top_from` to `top_to` across local x [x_from, x_to).
func _stairs(room: Room, x_from: int, x_to: int, top_from: int, top_to: int) -> void:
	var count := top_to - top_from + 1
	var span := x_to - x_from
	var x := x_from
	for i in count:
		var width := int(round(float(span) * (i + 1) / count)) - int(round(float(span) * i / count))
		width = maxi(width, 1)
		_solid(room, x, 0, width, top_from + i)
		x += width


## The way out: 1-wide steps from 7 to 10 under the next room's one-way bridge, so a
## pair on neighbouring steps stays inside the rope's reach. From the 10 step a jump
## lands on the bridge, which is the next room's floor at 11. Rooms arrive at 6.
func _exit_steps(room: Room) -> void:
	_stairs(room, 24, 28, 7, 10)


func _entry_spawns(room: Room) -> Array[Vector2]:
	return [_spot(room, 3.0, 0.0), _spot(room, 4.5, 0.0)]


func _jitter(room: Room, lx: float, ly: float, w: float, h: float, phase: float) -> void:
	var platform := JitterPlatform.new()
	platform.name = "Jitter%d" % jitters.size()
	platform.setup(_rect(room, lx, ly, w, h), phase)
	_root.add_child(platform)
	jitters.append(platform)


func _decor(room: Room, kind: Decor.Kind, pos: Vector2, size: Vector2, color: Color = Color.WHITE,
		variant: int = 0, text: String = "") -> Decor:
	var d := Decor.new()
	d.kind = kind
	d.position = pos
	d.size = size
	d.color = color
	d.variant = variant
	d.text = text
	d.seed_value = _rng.randi()
	room.decor.add_child(d)
	return d


func _rocks(room: Room, count: int) -> void:
	for i in count:
		_decor(room, Decor.Kind.ROCK, _spot(room, _rng.randf_range(9.0, 28.0), _rng.randf_range(6.0, 9.0)),
				Vector2.ONE * _rng.randf_range(0.4, 0.9) * C, Color(0.5, 0.32, 0.22))


func _hills(room: Room, color: Color) -> void:
	for i in 3:
		var side := -1.0 if i % 2 == 0 else 1.0
		var x := 15.0 + side * _rng.randf_range(19.0, 24.0)
		_decor(room, Decor.Kind.HILL, Vector2(x * C, room.floor_y + C * 2.0),
				Vector2(_rng.randf_range(6.0, 9.0), _rng.randf_range(5.0, 9.0)) * C, color)


func _corrupt_decor(room: Room, texts: Array) -> void:
	_decor(room, Decor.Kind.GRID, room_center(room.index), Vector2(40.0, Tuning.ROOM_PITCH) * C)
	for i in texts.size():
		var pos := Vector2(_rng.randf_range(-3.0, 31.0) * C, room.floor_y - _rng.randf_range(3.0, 9.5) * C)
		_decor(room, Decor.Kind.CUT_TEXT, pos, Vector2(_rng.randf_range(3.0, 7.0) * C, C), Color.WHITE, 0, texts[i])
	for i in 2:
		var pos := Vector2(_rng.randf_range(-2.0, 30.0) * C, room.floor_y - _rng.randf_range(2.0, 9.0) * C)
		_decor(room, Decor.Kind.BAR, pos, Vector2(_rng.randf_range(4.0, 8.0), 0.5) * C)


func _clear() -> void:
	rooms.clear()
	jitters.clear()
	_rope_static.clear()
	witness_spots.clear()
	lift = null
	fail_floor = null
	moon = null
	for child in get_children():
		remove_child(child)
		child.free()
	_root = Node2D.new()
	_root.name = "Generated"
	add_child(_root)
	_body = StaticBody2D.new()
	_body.name = "Terrain"
	_body.collision_layer = 1
	_body.collision_mask = 0
	_root.add_child(_body)
