@tool
class_name StageGenerator
extends Node2D

## Builds the mountain: thirteen single-screen rooms stacked bottom to top, laid out on
## cube multiples (see GDD "Level shape" and "The rooms"). Rooms alternate direction, so
## a room's exit opening is the next room's entry. Templates are written for a room that
## is entered on the left (local x grows away from the entry) and mirrored when needed.
## Each room has its own scenery (`Themes`). The seed varies crux positions and scenery.
##
## Local room coordinates are in cubes: x in [0, ROOM_W), y up from the floor surface.
## A room's floor band (y in [-1, 0)) is also the ceiling of the room below.

signal generated

const C := Tuning.CUBE
const W := Tuning.ROOM_W

const ROOM_WITNESS := 4
const ROOM_WALL := 6
const ROOM_SEAM := 7
const ROOM_WIREFRAME := 8
const ROOM_EDGE := 12

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
## The camp, below the near ledge: once the lift has risen, both cubes down here are stuck.
var lift_stuck_zone := Rect2()
## The summit's seam: a cube standing on the glitching bump that jumps is pulled through
## the broken corner, and pulls its partner with it.
var seam_trigger := Rect2()
var witness_spots: Array[Vector2] = []
var echo_x: float = 0.0
var moon: Decor
var lift: Lift
var fail_floor: FailFloor
var jitters: Array[JitterPlatform] = []
var cornices: Array[Cornice] = []
var loading_bars: Array[LoadingBar] = []

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
		room.mirrored = _mirrored(i)
		room.corrupted = i >= ROOM_SEAM
		room.art = TerrainArt.new()
		room.art.name = "Art%d" % (i + 1)
		room.art.style = Themes.STYLES[i]
		room.art.palette = Themes.rock(i)
		room.art.jitter = i == ROOM_WIREFRAME
		room.art.seed_value = _rng.randi()
		room.decor = Node2D.new()
		room.decor.name = "Decor%d" % (i + 1)
		room.decor.z_index = -5
		_root.add_child(room.decor)
		_root.add_child(room.art)
		rooms.append(room)

	_build_village(rooms[0])
	_build_forest(rooms[1])
	_build_gorge(rooms[2])
	_build_cave(rooms[3])
	_build_camp(rooms[4])
	_build_snowline(rooms[5])
	_build_summit(rooms[6])
	_build_seam(rooms[7])
	_build_wireframe(rooms[8])
	_build_rerun(rooms[9])
	_build_debug(rooms[10])
	_build_loading(rooms[11])
	_build_edge(rooms[12])

	for room in rooms:
		room.art.finalize()
	set_corrupted_visible(false)
	generated.emit()


## Rooms alternate direction so each exit leads into the next entry. The seam room is
## entered by the glitch, not by a staircase, and climbs back over itself to the left.
func _mirrored(index: int) -> bool:
	if index <= ROOM_WALL:
		return index % 2 == 1
	if index <= ROOM_SEAM + 1:
		return false
	if index < ROOM_EDGE:
		return (index - ROOM_SEAM - 1) % 2 == 1
	# The edge is laid out for an entry on its local right.
	return _mirrored(index - 1)


func floor_y(index: int) -> float:
	return -float(index * Tuning.ROOM_PITCH) * C


## Which room a world-space height belongs to: from just below its floor band up to
## just below the next room's band.
func room_index_at(y: float) -> int:
	var idx := int(floor((-y + C) / (Tuning.ROOM_PITCH * C)))
	return clampi(idx, 0, Tuning.ROOM_COUNT - 1)


func room_center(index: int) -> Vector2:
	return Vector2(W * 0.5 * C, floor_y(index) - Tuning.ROOM_H * 0.5 * C)


## True when a point in the edge room is close to the screen border the rope runs into.
func near_border(p: Vector2) -> bool:
	var room := rooms[ROOM_EDGE]
	var lx := (W - p.x / C) if room.mirrored else p.x / C
	return lx < -2.0


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
	for c in cornices:
		if c.intact:
			_rope_cache.append(c.rect)
	for bar in loading_bars:
		_rope_cache.append_array(bar.solid_rects())
	if fail_floor != null and not fail_floor.failed:
		_rope_cache.append_array(fail_floor.rects)
	return _rope_cache


func set_ending(on: bool) -> void:
	_ending = on


## The rooms past the seam do not exist on screen until the cubes glitch through it.
func set_corrupted_visible(on: bool) -> void:
	for room in rooms:
		if room.corrupted:
			room.art.visible = on
			room.decor.visible = on
	for j in jitters:
		j.visible = on
	for bar in loading_bars:
		bar.visible = on
	if fail_floor != null:
		fail_floor.visible = on


## Moving holds that run on the shared game clock.
func apply_time(t: float) -> void:
	for j in jitters:
		j.apply_time(t)
	for bar in loading_bars:
		bar.apply_time(t)


func cornice_bits() -> int:
	var bits := 0
	for i in cornices.size():
		if cornices[i].intact:
			bits |= 1 << i
	return bits


func apply_cornice_bits(bits: int) -> void:
	for i in cornices.size():
		cornices[i].set_intact(bits & (1 << i) != 0)


# --- Honest rooms --------------------------------------------------------------------

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


func _build_forest(room: Room) -> void:
	# Anchor, twice: two 2-cube lips in a row, each out of reach of a solo jump. The shelf
	# between them is just wide enough to haul the partner up before the next one.
	_floor_band(room)
	_walls(room, true, true)
	var lip := 8 + _rng.randi_range(0, 1)
	_solid(room, lip, 0, 6, 2)
	_solid(room, lip + 6, 0, W - lip - 6, 4)
	_stairs(room, 20, 24, 5, 6)
	_exit_steps(room)
	room.spawns = _entry_spawns(room)

	for i in 7:
		var lx := -4.0 + i * 5.6 + _rng.randf_range(-1.0, 1.0)
		var h := _rng.randf_range(4.5, 7.5)
		_decor(room, Decor.Kind.PINE, _ground(room, lx), Vector2(h * 0.55, h) * C,
				Color.from_hsv(_rng.randf_range(0.3, 0.38), 0.5, _rng.randf_range(0.38, 0.5)))
	_decor(room, Decor.Kind.POSTER, _spot(room, lip - 2.5, 3.2), Vector2(1.8, 2.2) * C, Color.WHITE, 1)
	for i in 3:
		_decor(room, Decor.Kind.BIRD, _spot(room, _rng.randf_range(6.0, 24.0), _rng.randf_range(7.5, 9.0)), Vector2(10.0, 1.0) * C)
	_hills(room, Color(0.3, 0.5, 0.32, 0.5))


func _build_gorge(room: Room) -> void:
	# Swing over the river: a high ledge jutting over the gorge and a far ledge two cubes
	# lower. One holds the edge, the other swings across. Both in the water is a fall.
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
	room.fall_zones.append(_zone(room, near, 0, 5, 1.5))

	var water := _rect(room, near, 0, 5, 1.1)
	_decor(room, Decor.Kind.WATERFALL, _ground(room, near + 2.5), Vector2(2.2, 9.0) * C)
	_decor(room, Decor.Kind.WATER, water.get_center(), water.size).z_index = 8
	for i in 4:
		var lx: float = [-3.0, 1.5, 27.5, 32.0][i] + _rng.randf_range(-0.8, 0.8)
		var h := _rng.randf_range(5.0, 7.0)
		_decor(room, Decor.Kind.PINE, _ground(room, lx), Vector2(h * 0.55, h) * C, Color(0.24, 0.42, 0.3))
	_rocks(room, 3)
	_hills(room, Color(0.4, 0.55, 0.6, 0.45))


func _build_cave(room: Room) -> void:
	# Inside the mountain, the first mix: a 2-cube lip, then a swing across a dark pit.
	# The shelf over the lip is just wide enough to haul the partner up.
	_floor_band(room)
	_walls(room, true, true)
	var lip := 6
	_solid(room, lip, 0, 10 - lip, 2)
	_stairs(room, 10, 13, 3, 5)
	_solid(room, 13, 5, 3, 1)
	_solid(room, 18, 0, W - 18, 4)
	_stairs(room, 22, 24, 5, 6)
	_exit_steps(room)
	room.spawns = _entry_spawns(room)
	room.fall_zones.append(_zone(room, 13, 0, 5, 1.5))

	_decor(room, Decor.Kind.CAVE_BACK, room_center(room.index), Vector2(W + 2.0, Tuning.ROOM_PITCH + 0.5) * C)
	for i in 6:
		var lx := _rng.randf_range(1.0, 29.0)
		_decor(room, Decor.Kind.STALACTITE, _spot(room, lx, 9.5), Vector2(_rng.randf_range(0.5, 0.9), _rng.randf_range(0.8, 1.6)) * C,
				Themes.ROCK[3][1])
	var crystal_spots := [[1.5, 0.0], [lip + 1.0, 2.0], [26.0, 6.0], [20.0, 4.0]]
	for spot in crystal_spots:
		_decor(room, Decor.Kind.CRYSTAL, _spot(room, spot[0], spot[1] - 0.5), Vector2(1.2, 1.4) * C,
				Color.from_hsv(_rng.randf_range(0.72, 0.85), 0.5, 1.0))
	_decor(room, Decor.Kind.CRYSTAL, _spot(room, 15.5, 0.0), Vector2(2.0, 1.2) * C, Color(0.45, 0.9, 1.0))


func _build_camp(room: Room) -> void:
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

	# The old camp of earlier climbers: torn tents, a cold fire, flags in two colors.
	_decor(room, Decor.Kind.TENT, _ground(room, 2.2), Vector2(2.6, 2.0) * C, Color(0.85, 0.55, 0.3))
	_decor(room, Decor.Kind.CAMPFIRE, _ground(room, 5.0), Vector2(1.2, 1.0) * C)
	_decor(room, Decor.Kind.TENT, _spot(room, 20.0, 3.5), Vector2(2.2, 1.7) * C, Color(0.35, 0.7, 0.75))
	_decor(room, Decor.Kind.FLAGS, _spot(room, 20.5, 6.6), Vector2(5.0, 0.6) * C)
	_decor(room, Decor.Kind.POSTER, _spot(room, 1.2, 4.0), Vector2(1.6, 2.0) * C, Color.WHITE, 1)
	_rocks(room, 4)
	_hills(room, Color(0.75, 0.4, 0.3, 0.4))


func _build_snowline(room: Room) -> void:
	# Weight again, on snow: two cornices across the crevasses hold one cube each and break
	# under two, so the pair crosses one at a time (the rope only just allows it, waiting
	# on the pillar between them). Then a 2-cube lip.
	_floor_band(room)
	_walls(room, true, true)
	_stairs(room, 5, 9, 1, 4)
	_solid(room, 9, 0, 3, 4)
	_cornice(room, 12, 3, 2, 1)
	_solid(room, 14, 0, 1, 4)
	_cornice(room, 15, 3, 2, 1)
	_solid(room, 17, 0, 3, 4)
	_solid(room, 20, 0, W - 20, 6)
	_exit_steps(room)
	room.spawns = _entry_spawns(room)
	room.fall_zones.append(_zone(room, 12, 0, 2, 2.5))
	room.fall_zones.append(_zone(room, 15, 0, 2, 2.5))

	_decor(room, Decor.Kind.SNOWFALL, room_center(room.index), Vector2(W + 8.0, Tuning.ROOM_PITCH) * C)
	for i in 5:
		var lx: float = [-3.5, 0.5, 3.0, 27.0, 31.5][i]
		var h := _rng.randf_range(3.5, 5.0)
		_decor(room, Decor.Kind.PINE, _ground(room, lx), Vector2(h * 0.55, h) * C, Color(0.75, 0.84, 0.9))
	_hills(room, Color(0.86, 0.9, 0.98, 0.6))


func _build_summit(room: Room) -> void:
	# Above the clouds the honest climb ends. The summit faces a gap wider than any
	# stretch of the rope, and the sky above it is empty. The ceiling over the stairs is
	# the wall, and one corner of it is broken: the seam.
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

	# The wall: the seam room's floor, drawn as this room's ceiling. Its corner over the
	# summit is broken: the collision forgot [21, 24), and under it a glitching rock bump
	# on the summit is the hold that clips through the wall. Jumping from it is the glitch.
	_solid(room, 0, 10, 21, 1)
	var seam := GlitchArt.new()
	seam.name = "Seam"
	seam.rects = [_rect(room, 21, 10, 3, 1)]
	_root.add_child(seam)
	var bump := _solid(room, 22, 6, 1, 1)
	var holds := GlitchArt.new()
	holds.name = "SeamHolds"
	holds.draw_offset = Vector2(3.0, -2.0)
	holds.rects = [bump, _rect(room, 22, 7.6, 1, 0.8), _rect(room, 21.5, 8.7, 1, 0.8)]
	_root.add_child(holds)
	seam_trigger = _rect(room, 21.6, 7.0, 1.8, 1.0)

	for i in 5:
		var lx := _rng.randf_range(-6.0, 36.0)
		_decor(room, Decor.Kind.CLOUD, _spot(room, lx, _rng.randf_range(-1.5, 1.5)), Vector2(_rng.randf_range(5.0, 9.0), 2.0) * C,
				Color(0.86, 0.84, 0.95, 0.9))
	_decor(room, Decor.Kind.CLOUD, _spot(room, 31.0, 4.5), Vector2(6.0, 1.6) * C, Color(0.8, 0.78, 0.92, 0.75))
	_decor(room, Decor.Kind.POSTER, _spot(room, 3.0, 2.6), Vector2(1.6, 2.0) * C, Color.WHITE, 1)


# --- Corrupted rooms -----------------------------------------------------------------

func _build_seam(room: Room) -> void:
	# Past the seam. The floor is the summit's ceiling; a 1-wide staircase climbs left to
	# the next room, which is entered from the left.
	_walls(room, true, false)
	for top in range(1, 11):
		_solid(room, 13 - top, 0, 1, top)
	room.spawns = [_spot(room, 14.0, 0.0), _spot(room, 15.3, 0.0)]
	_corrupt_decor(room, ["simulat", "ERR 0x07", "C:\\montanha\\sala_08"])


func _build_wireframe(room: Room) -> void:
	# The cave again, as an untextured mesh: a lip, then a swing, on ground that jitters.
	# The far side's landing blinks out, so the swing has to be timed.
	_floor_band(room)
	_walls(room, true, true)
	_solid(room, 6, 0, 4, 2)
	_stairs(room, 10, 13, 3, 5)
	_solid(room, 13, 5, 3, 1)
	_jitter(room, 18, 3, 2, 1, 1.0)
	_solid(room, 20, 0, W - 20, 4)
	_jitter(room, 22, 4, 1, 1, 0.8)
	_jitter(room, 23, 4, 1, 2, 2.2)
	_exit_steps(room)
	room.spawns = _entry_spawns(room)
	room.fall_zones.append(_zone(room, 13, 0, 7, 1.5))

	for i in 6:
		var lx := -4.0 + i * 6.5 + _rng.randf_range(-1.0, 1.0)
		var h := _rng.randf_range(4.5, 7.0)
		_decor(room, Decor.Kind.WIRE_TREE, _ground(room, lx), Vector2(h * 0.55, h) * C)
	_decor(room, Decor.Kind.CHECKER, _spot(room, 27.0, 1.5), Vector2(2.0, 2.0) * C)
	_corrupt_decor(room, ["mesh_montanha.obj", "textura não encontrada", "sala_09"])


func _build_rerun(room: Room) -> void:
	# The village, reused: its houses stacked crooked into three 2-cube lips. The same
	# anchor three times, on shelves narrower than the forest's.
	_floor_band(room)
	_walls(room, true, true)
	var lip := 7 + _rng.randi_range(0, 1)
	_solid(room, lip, 0, 5, 2)
	_solid(room, lip + 5, 0, 5, 4)
	_solid(room, lip + 10, 0, W - lip - 10, 6)
	_exit_steps(room)
	room.spawns = _entry_spawns(room)

	# The village houses, copy-pasted onto every shelf.
	for k in 3:
		var hue: float = [0.85, 0.55, 0.15][k]
		_decor(room, Decor.Kind.HOUSE, _ground(room, lip + k * 5 + 1.6) + Vector2(0.0, -(k * 2.0 + 2.0) * C),
				Vector2(2.4, 2.4) * C, Color.from_hsv(hue, 0.5, 0.9))
	for i in 5:
		var size := _rng.randf_range(0.35, 0.5)
		_decor(room, Decor.Kind.BG_CUBE, _ground(room, 1.0 + i * 1.3), Vector2(size, size) * C, Color.from_hsv(0.5 + i * 0.1, 0.5, 0.9))
	_decor(room, Decor.Kind.POSTER, _spot(room, 4.0, 3.0), Vector2(1.8, 2.2) * C)
	_decor(room, Decor.Kind.POSTER, _spot(room, 5.0, 3.3), Vector2(1.8, 2.2) * C)
	_corrupt_decor(room, ["vila_copia(3)", "reutilizar_assets = true", "sala_10"])


func _build_debug(room: Room) -> void:
	# The engine's debug view: the swing's far ledge has no art at all, only its collision
	# boxes. Trust the box, swing onto it, then haul up a 2-cube lip.
	_floor_band(room)
	_walls(room, true, true)
	_stairs(room, 5, 10, 1, 5)
	_solid(room, 10, 5, 3, 1)
	var hidden := _rect(room, 15, 0, 5, 4)
	_add_collision(hidden)
	_rope_static.append(hidden)
	_solid(room, 20, 0, W - 20, 6)
	_exit_steps(room)
	room.spawns = _entry_spawns(room)
	room.fall_zones.append(_zone(room, 10, 0, 5, 1.5))

	_decor(room, Decor.Kind.DEBUG_BOX, hidden.get_center(), hidden.size, Color.WHITE, 0, "col_ledge_02 (sem arte)")
	_decor(room, Decor.Kind.GIZMO, _spot(room, 11.5, 6.0), Vector2(1.2, 1.2) * C)
	_decor(room, Decor.Kind.GIZMO, _spot(room, 25.0, 6.0), Vector2(1.6, 1.6) * C)
	_decor(room, Decor.Kind.CHECKER, _spot(room, 2.0, 4.5), Vector2(1.5, 1.5) * C)
	_corrupt_decor(room, ["DEBUG: draw_collision = true", "fps: 60  cubos: 2", "sala_11"])


func _build_loading(room: Room) -> void:
	# A progress bar bridges the pit. It fills one block at a time, holds at 99% and then
	# empties all at once: the pair crosses together behind the fill. Then a 2-cube lip.
	_floor_band(room)
	_walls(room, true, true)
	_stairs(room, 5, 9, 1, 4)
	_solid(room, 9, 0, 2, 4)
	var bar := LoadingBar.new()
	bar.name = "LoadingBar"
	var span := _rect(room, 11, 3, 7, 1)
	if room.mirrored:
		# The bar fills from the entry side.
		bar.reverse = true
	bar.setup(span, 0.0)
	_root.add_child(bar)
	loading_bars.append(bar)
	_solid(room, 18, 0, 2, 4)
	_solid(room, 20, 0, W - 20, 6)
	_exit_steps(room)
	room.spawns = _entry_spawns(room)
	room.fall_zones.append(_zone(room, 11, 0, 7, 1.5))

	for i in 3:
		var pos := _spot(room, _rng.randf_range(2.0, 26.0), _rng.randf_range(6.0, 8.5))
		_decor(room, Decor.Kind.BAR, pos, Vector2(_rng.randf_range(4.0, 7.0), 0.5) * C)
	_corrupt_decor(room, ["carregando...", "não feche o jogo", "dica: a lua", "sala_12.tmp"])


func _build_edge(room: Room) -> void:
	# No new puzzle and no platform past the screen. The rope hits the border.
	fail_floor = FailFloor.new()
	fail_floor.name = "FailFloor"
	fail_floor.setup([_rect(room, -5, -1, 27, 1)], [_rect(room, 22, -1, 8, 1)])
	_root.add_child(fail_floor)
	_solid(room, -6, -1, 1, 14)
	_solid(room, 35, -1, 1, 14)
	room.spawns = [_spot(room, 18.5, 0.0), _spot(room, 20.0, 0.0)]
	moon = _decor(room, Decor.Kind.MOON, _spot(room, 7.0, 8.8), Vector2(3.6, 3.6) * C)
	_decor(room, Decor.Kind.WINDOW, _spot(room, 7.0, 8.8), Vector2(11.0, 7.4) * C, Color.WHITE, 0, "lua.png")
	_corrupt_decor(room, ["FIM DA SIMULA", "não há saída", "sala_13"])


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
	_bridge(room, 0, -1, 8, 1, room.art)
	_solid(room, 8, -1, to_x - 8, 1, room.art)


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


func _cornice(room: Room, lx: float, ly: float, w: float, h: float) -> void:
	var c := Cornice.new()
	c.name = "Cornice%d" % cornices.size()
	c.setup(_rect(room, lx, ly, w, h))
	_root.add_child(c)
	cornices.append(c)


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
	cornices.clear()
	loading_bars.clear()
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
