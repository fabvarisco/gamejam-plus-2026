class_name EntangledRope
extends Node2D

## The bond. A Verlet chain between the two cube centers: it sags when slack, collides
## with terrain only (never with the cubes), and drags on the terrain it touches.
## Past the 3-cube rest length it pulls the cubes together, harder the more it stretches;
## there is no hard maximum. Friction where the rope wraps terrain lightens the pull felt
## by a cube standing on a hold, which is what makes it an anchor.
## Online, netfox records the chain (`ROLLBACK_STATE`) every tick so it can be rewound
## together with the cubes.

const SEGMENTS := 24
const ITERATIONS := 10
const SUBSTEPS := 2
const RADIUS := 2.5
const LOOK_AHEAD := 18.0
const PAYOUT_SPEED := 900.0

## The chain's state, as netfox property paths relative to the game root.
const ROLLBACK_STATE: Array[String] = [
	"Rope:points", "Rope:prev_points", "Rope:span_rest", "Rope:tail_owner", "Rope:prev_stretch",
]

var stage: StageGenerator
var corrupted: bool = false
## Tests switch this off to measure what a cube can reach alone.
var forces_enabled: bool = true

var points := PackedVector2Array()
var prev_points := PackedVector2Array()
var span_rest: float = Tuning.ROPE_REST
var tail_owner: int = -1
var prev_stretch: float = 0.0

var _contact := PackedVector2Array()
var _colliders: Array[Rect2] = []
var _glitch_clock: float = 0.0
var _a: PlayerCube
var _b: PlayerCube

@onready var _outline: Line2D = $Outline
@onready var _line: Line2D = $Line2D
@onready var _tail: Line2D = $Tail


func _ready() -> void:
	points.resize(SEGMENTS + 1)
	prev_points.resize(SEGMENTS + 1)
	_contact.resize(SEGMENTS + 1)
	top_level = true
	global_position = Vector2.ZERO


func reset(a: Vector2, b: Vector2) -> void:
	for i in SEGMENTS + 1:
		var t := float(i) / SEGMENTS
		points[i] = a.lerp(b, t)
		prev_points[i] = points[i]
		_contact[i] = Vector2.ZERO
	span_rest = Tuning.ROPE_REST
	tail_owner = -1
	prev_stretch = 0.0


func path_length() -> float:
	var total := 0.0
	for i in SEGMENTS:
		total += points[i].distance_to(points[i + 1])
	return total


## Advances the chain and, on the simulating peer, writes forces and climb targets into
## both cubes. `a` is pinned to particle 0 and `b` to the last particle.
func step(delta: float, a: PlayerCube, b: PlayerCube, write_forces: bool) -> void:
	var pa := a.global_position
	var pb := b.global_position
	_update_span(delta, a, b)
	_gather_colliders(pa, pb)
	var h := delta / SUBSTEPS
	var seg_rest := span_rest / SEGMENTS
	for _s in SUBSTEPS:
		for i in range(1, SEGMENTS):
			var cur := points[i]
			var vel := (cur - prev_points[i]) * 0.992
			prev_points[i] = cur
			points[i] = cur + vel + Vector2(0.0, Tuning.GRAVITY) * h * h
		points[0] = pa
		points[SEGMENTS] = pb
		for it in ITERATIONS:
			_solve_segments(seg_rest)
			_collide(it == ITERATIONS - 1)
		points[0] = pa
		points[SEGMENTS] = pb

	if write_forces and forces_enabled:
		_write_forces(delta, a, b)
	elif write_forces:
		a.rope_force = Vector2.ZERO
		b.rope_force = Vector2.ZERO
	_a = a
	_b = b


func _process(_delta: float) -> void:
	if _a != null:
		_redraw(_a, _b)


func _update_span(delta: float, a: PlayerCube, b: PlayerCube) -> void:
	# A climbing cube holds the rope where it is; the rope behind it hangs as a tail.
	var climber := 0 if a.climbing else (1 if b.climbing else -1)
	if climber >= 0:
		# Hand over hand: the climber takes rope in, so the rope ahead stays taut and what
		# it has passed hangs behind it as a tail.
		tail_owner = climber
		span_rest = maxf(Tuning.CUBE, minf(span_rest, path_length()) - Tuning.CLIMB_SPEED * 1.5 * delta)
	else:
		span_rest = move_toward(span_rest, Tuning.ROPE_REST, PAYOUT_SPEED * delta)
		if span_rest >= Tuning.ROPE_REST:
			tail_owner = -1


func _gather_colliders(pa: Vector2, pb: Vector2) -> void:
	_colliders.clear()
	if stage == null:
		return
	var bounds := Rect2(pa, Vector2.ZERO).expand(pb).grow(Tuning.ROPE_REST + Tuning.CUBE)
	for r in stage.rope_colliders():
		if bounds.intersects(r):
			_colliders.append(r)


func _solve_segments(seg_rest: float) -> void:
	for i in SEGMENTS:
		var d := points[i + 1] - points[i]
		var length := d.length()
		if length <= seg_rest or length < 0.0001:
			continue
		var corr := d * ((length - seg_rest) / length)
		if i == 0:
			points[i + 1] -= corr
		elif i + 1 == SEGMENTS:
			points[i] += corr
		else:
			points[i] += corr * 0.5
			points[i + 1] -= corr * 0.5


func _collide(apply_friction: bool) -> void:
	for i in range(1, SEGMENTS):
		var p := points[i]
		var normal := Vector2.ZERO
		for rect in _colliders:
			var r := rect.grow(RADIUS)
			if not r.has_point(p):
				continue
			var prev := prev_points[i]
			var left := p.x - r.position.x
			var right := r.end.x - p.x
			var top := p.y - r.position.y
			var bottom := r.end.y - p.y
			# Exit through a side the particle came from; fall back to least penetration.
			var best := INF
			var n := Vector2.ZERO
			if prev.x <= r.position.x and left < best:
				best = left
				n = Vector2.LEFT
			if prev.x >= r.end.x and right < best:
				best = right
				n = Vector2.RIGHT
			if prev.y <= r.position.y and top < best:
				best = top
				n = Vector2.UP
			if prev.y >= r.end.y and bottom < best:
				best = bottom
				n = Vector2.DOWN
			if n == Vector2.ZERO:
				best = minf(minf(left, right), minf(top, bottom))
				if best == top:
					n = Vector2.UP
				elif best == left:
					n = Vector2.LEFT
				elif best == right:
					n = Vector2.RIGHT
				else:
					n = Vector2.DOWN
			p += n * best
			normal += n
		points[i] = p
		_contact[i] = normal.normalized() if normal != Vector2.ZERO else Vector2.ZERO
		if apply_friction and normal != Vector2.ZERO:
			var n2 := _contact[i]
			var vel := p - prev_points[i]
			var tangential := vel - n2 * vel.dot(n2)
			prev_points[i] = p - tangential * (1.0 - Tuning.ROPE_TERRAIN_FRICTION)


func _write_forces(delta: float, a: PlayerCube, b: PlayerCube) -> void:
	var length := path_length()
	var stretch := length - Tuning.ROPE_REST - Tuning.ROPE_SLACK_DEADZONE
	var rate := (stretch - prev_stretch) / maxf(delta, 0.0001)
	prev_stretch = stretch
	var tension := 0.0
	if stretch > 0.0:
		tension = Tuning.ROPE_K_LINEAR * stretch + Tuning.ROPE_K_QUADRATIC * stretch * stretch
		tension = maxf(0.0, tension + Tuning.ROPE_DAMPING * rate)

	var wrap := _wrap_angle()
	var hold := exp(-Tuning.ROPE_TERRAIN_FRICTION * wrap)
	var ta := tension
	var tb := tension
	var a_floor := a.on_floor
	var b_floor := b.on_floor
	if a_floor and not b_floor:
		ta *= hold
	elif b_floor and not a_floor:
		tb *= hold

	a.rope_force = Vector2.ZERO if a.climbing else _pull_dir(0, 1) * ta
	b.rope_force = Vector2.ZERO if b.climbing else _pull_dir(SEGMENTS, -1) * tb

	# A cube can climb toward a partner that stands on a hold. Close to the partner it
	# aims at the partner itself, which pulls it up and over the lip the partner is on.
	var gap := a.global_position.distance_to(b.global_position)
	a.climb_available = gap > Tuning.CUBE * 0.9 and b_floor
	b.climb_available = gap > Tuning.CUBE * 0.9 and a_floor
	var close := gap < Tuning.CUBE * 2.0
	a.climb_target = b.global_position if close else _point_along(0, 1, 28.0)
	b.climb_target = a.global_position if close else _point_along(SEGMENTS, -1, 28.0)


## Direction from a cube toward the rope just ahead of it. Where the rope lies on terrain,
## aim half a cube off the surface so a hauled cube is pulled up and over the lip.
func _pull_dir(start: int, dir: int) -> Vector2:
	var origin := points[start]
	var target := _point_along(start, dir, LOOK_AHEAD)
	var d := target - origin
	if d.length() < 0.5:
		d = points[SEGMENTS - start] - origin
	return d.normalized() if d.length() > 0.001 else Vector2.ZERO


func _point_along(start: int, dir: int, distance: float) -> Vector2:
	var travelled := 0.0
	var i := start
	while i + dir >= 0 and i + dir <= SEGMENTS:
		travelled += points[i].distance_to(points[i + dir])
		i += dir
		if travelled >= distance:
			break
	var point := points[i]
	if _contact[i] != Vector2.ZERO:
		point += _contact[i] * Tuning.CUBE * 0.5
	return point


func _wrap_angle() -> float:
	var total := 0.0
	for i in range(1, SEGMENTS):
		if _contact[i] == Vector2.ZERO:
			continue
		var d0 := points[i] - points[i - 1]
		var d1 := points[i + 1] - points[i]
		if d0.length() < 0.01 or d1.length() < 0.01:
			continue
		total += absf(d0.angle_to(d1))
	return minf(total, TAU)


func _redraw(a: PlayerCube, b: PlayerCube) -> void:
	var pts := PackedVector2Array()
	pts.append(points[0])
	for i in range(1, SEGMENTS):
		# Smooth the polyline a little so the sag reads as a curve.
		pts.append((points[i - 1] + points[i] * 2.0 + points[i + 1]) * 0.25)
	pts.append(points[SEGMENTS])
	_line.points = pts
	_outline.points = pts

	var tail_len := Tuning.ROPE_REST - span_rest
	if tail_owner >= 0 and tail_len > 2.0:
		var holder := a if tail_owner == 0 else b
		var start := holder.global_position
		var sway := sin(Time.get_ticks_msec() * 0.004) * 4.0
		_tail.points = PackedVector2Array([
			start,
			start + Vector2(sway * 0.5, tail_len * 0.5),
			start + Vector2(sway, tail_len),
		])
		_tail.visible = true
	else:
		_tail.visible = false

	if corrupted:
		_glitch_clock -= get_process_delta_time()
		if _glitch_clock <= 0.0:
			_glitch_clock = randf_range(0.05, 0.5)
			var wrong := randf() < 0.3
			_line.default_color = Color(0.3, 1.0, 0.6) if wrong else Color(0.86, 0.78, 0.6)
			_outline.default_color = Color(0.9, 0.1, 0.6) if wrong else Color(0.16, 0.08, 0.05)
