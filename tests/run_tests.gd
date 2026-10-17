extends SceneTree

## Headless playtests for the GDD's room rules. Each test builds a fresh mountain in local
## mode, places the cubes and drives them with scripted input.
##
##   godot --headless --path . --fixed-fps 60 -s res://tests/run_tests.gd [-- name_filter] [seed=N] [trace]

# Loaded at runtime: preloading would compile main.gd before the Net autoload exists.
var main_scene: PackedScene
const C := Tuning.CUBE

const VILLAGE := 0
const FOREST := 1
const GORGE := 2
const CAVE := 3
const CAMP := 4
const SNOWLINE := 5
const SUMMIT := 6
const SEAM := 7
const WIREFRAME := 8
const RERUN := 9
const DEBUG := 10
const LOADING := 11
const EDGE := 12
## Rooms with 2-cube lips (anchor: stack or haul).
const LIP_ROOMS: Array[int] = [FOREST, CAVE, SNOWLINE, WIREFRAME, RERUN, DEBUG, LOADING]

var main: Node
var stage: StageGenerator
var a: PlayerCube
var b: PlayerCube
var net: Node
var failures: int = 0
var tracing: bool = false
var default_seed: int = 1
var _last_jump := [false, false]


func _initialize() -> void:
	net = root.get_node("Net")
	main_scene = load("res://scenes/main.tscn")
	var filter := ""
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		filter = args[0]
	tracing = args.has("trace")
	for arg in args:
		if arg.begins_with("seed="):
			default_seed = int(arg.trim_prefix("seed="))
	var tests := [
		"test_settle", "test_hang_holds", "test_solo_step", "test_solo_lip_fails", "test_stack_climbs_lip",
		"test_haul_up_lip", "test_climb_recovery", "test_solo_gap_fails", "test_swing_crosses_gap",
		"test_anchor_follows", "test_water_resets", "test_lift", "test_witness", "test_cornice_breaks_under_two",
		"test_cornice_one_at_a_time", "test_loading_bar_crossing", "test_loading_bar_empties", "test_wall_unreachable",
		"test_seam_crossing", "test_room_paths", "test_exits", "test_ending", "test_seeds_spawn_clear",
	]
	for t in tests:
		if filter != "" and not t.contains(filter):
			continue
		var ok: bool = await call(t)
		print(("PASS  " if ok else "FAIL  ") + t)
		if not ok:
			failures += 1
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


# --- Harness -------------------------------------------------------------------------

func fresh(checkpoint: int = 0, seed_value: int = -1) -> void:
	if seed_value < 0:
		seed_value = default_seed
	if main != null:
		main.queue_free()
		await process_frame
	net.mode = net.Mode.LOCAL
	net.stage_seed = seed_value
	main = main_scene.instantiate()
	main.test_mode = true
	root.add_child(main)
	await process_frame
	stage = main.stage
	a = main.player_1
	b = main.player_2
	main.checkpoint = checkpoint
	_last_jump = [false, false]
	idle()


func spot(room: int, lx: float, ly: float) -> Vector2:
	return stage._spot(stage.rooms[room], lx, ly)


## +1 means "local +x" (away from the room's entry), converted to a world direction.
func fwd(room: int) -> float:
	return -1.0 if stage.rooms[room].mirrored else 1.0


func place(pa: Vector2, pb: Vector2) -> void:
	a.teleport(pa)
	b.teleport(pb)
	main.rope.reset(pa, pb)


func inp(slot: int, axis: float, jump: bool = false, climb: bool = false) -> void:
	main.test_inputs[slot] = [axis, jump, climb]


func idle() -> void:
	inp(0, 0.0)
	inp(1, 0.0)


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func height(room: int, cube: PlayerCube) -> float:
	# Height of the cube's feet above the room floor, in cubes.
	return (stage.floor_y(room) - (cube.global_position.y + C * 0.5)) / C


## Greedy waypoint follower: walk toward each point, jump when it is above.
func follow(slot: int, waypoints: Array, max_frames: int, other_axis := 0.0) -> bool:
	var cube := a if slot == 0 else b
	var wi := 0
	for f in max_frames:
		if wi >= waypoints.size():
			return true
		var t: Vector2 = waypoints[wi]
		var d := t - cube.global_position
		var axis := 0.0
		if absf(d.x) > 3.0:
			axis = signf(d.x)
		var want_up := d.y < -6.0 and (absf(d.x) < C * 1.5 or cube.is_on_wall())
		var jump: bool = _jump_policy(slot, cube, want_up)
		inp(slot, axis, jump)
		inp(1 - slot, other_axis)
		await physics_frame
		if cube.is_on_floor() and absf(d.x) <= 8.0 and absf(d.y) <= 8.0:
			wi += 1
	return wi >= waypoints.size()


## Climb as a pair along one path, like players would: the leader only moves on once the
## follower has caught up to the waypoint behind it, and the follower never steps onto the
## leader's waypoint. Indices count completed waypoints.
func climb_together(path: Array, max_frames: int = 1500) -> bool:
	var idx := [0, 0]
	var cubes := [a, b]
	for f in max_frames:
		if idx[0] >= path.size() and idx[1] >= path.size() - 2:
			return true
		for slot in 2:
			var cube: PlayerCube = cubes[slot]
			var target: int = idx[slot]
			var allowed: bool = target < path.size()
			if slot == 0:
				allowed = allowed and idx[1] >= target - 1
			else:
				allowed = allowed and target <= mini(idx[0] - 1, path.size() - 2)
			if not allowed:
				inp(slot, 0.0)
				continue
			var t: Vector2 = path[target]
			var d := t - cube.global_position
			var axis := signf(d.x) if absf(d.x) > 3.0 else 0.0
			var want_up := d.y < -6.0 and (absf(d.x) < C * 1.5 or cube.is_on_wall())
			var jump: bool = _jump_policy(slot, cube, want_up)
			inp(slot, axis, jump)
		await physics_frame
		if tracing and f % 5 == 0:
			print("        f%d idx %s  a %s floor=%s v=%s F=%s in=%s  b %s floor=%s" % [f, idx, _fmt(a), a.is_on_floor(), a.velocity.round(), a.rope_force.round(), main.test_inputs[0], _fmt(b), b.is_on_floor()])
		for slot in 2:
			var cube: PlayerCube = cubes[slot]
			if idx[slot] < path.size():
				var d: Vector2 = path[idx[slot]] - cube.global_position
				if cube.is_on_floor() and absf(d.x) <= 8.0 and absf(d.y) <= 8.0:
					idx[slot] += 1
	print("      pair stuck at leader %d, follower %d (a %s, b %s)" % [idx[0], idx[1], (a.global_position / C).snapped(Vector2(0.1, 0.1)), (b.global_position / C).snapped(Vector2(0.1, 0.1))])
	return false


func _fmt(cube: PlayerCube) -> String:
	var room := stage.room_index_at(cube.global_position.y)
	var lx := cube.global_position.x / C
	if stage.rooms[room].mirrored:
		lx = Tuning.ROOM_W - lx
	return "r%d(%.2f, %.2f)" % [room + 1, lx, (stage.floor_y(room) - cube.global_position.y) / C - 0.5]


## Press jump when the target is above (releasing for a frame between hops), and keep it
## held while rising so the jump is never cut short.
func _jump_policy(slot: int, cube: PlayerCube, want_up: bool) -> bool:
	var rising: bool = not cube.is_on_floor() and _last_jump[slot] and cube.velocity.y < 0.0
	var jump: bool = rising or (want_up and not (cube.is_on_floor() and _last_jump[slot]))
	_last_jump[slot] = jump
	return jump


## Waypoints in local cubes, with extra points on long flat stretches so a climbing pair
## never has to spread wider than the rope.
func _route(room: int, points: Array) -> Array:
	var out := []
	for i in points.size():
		if i > 0 and points[i][1] == points[i - 1][1]:
			var from: float = points[i - 1][0]
			var to: float = points[i][0]
			var steps := int(ceil(absf(to - from) / 1.4))
			for k in range(1, steps):
				out.append(spot(room, lerpf(from, to, float(k) / steps), points[i][1]))
		out.append(spot(room, points[i][0], points[i][1]))
	return out


func check(cond: bool, message: String) -> bool:
	if not cond:
		print("      " + message)
	return cond


# --- Tests ---------------------------------------------------------------------------

func test_settle() -> bool:
	await fresh()
	await frames(60)
	return check(a.is_on_floor() and b.is_on_floor(), "cubes did not land at spawn") \
			and check(a.rope_force.length() < 1.0, "slack rope pulls: %s" % a.rope_force)


func test_hang_holds() -> bool:
	# The gorge: one cube on the edge, the other hanging over the river. The anchor holds.
	await fresh(GORGE)
	var near := _gap_near(GORGE)
	place(spot(GORGE, near + 2.5, 6.0), spot(GORGE, near + 4.0, 3.4))
	await frames(180)
	var stretch: float = main.rope.path_length() - Tuning.ROPE_REST
	return check(main.resets == 0, "hanging cube caused a reset") \
			and check(a.is_on_floor(), "anchor was pulled off the edge") \
			and check(not b.is_on_floor(), "partner is not hanging") \
			and check(stretch < C * 0.75, "rope stretched %.1f px while hanging" % stretch)


func test_solo_step() -> bool:
	# A 1-cube step is a solo move.
	await fresh(VILLAGE)
	main.rope.forces_enabled = false
	place(spot(VILLAGE, 17.0, 0.0), spot(VILLAGE, 14.0, 0.0))
	var ok := await follow(0, [spot(VILLAGE, 18.5, 1.0)], 120)
	return check(ok, "could not hop onto a 1-cube step (height %.2f)" % height(VILLAGE, a))


func test_solo_lip_fails() -> bool:
	# Every 2-cube lip is out of reach of a solo jump.
	var ok := true
	for room in LIP_ROOMS:
		await fresh(room)
		for lip in _lips(room):
			main.rope.forces_enabled = false
			place(spot(room, lip.x - 0.6, lip.y), stage.rooms[room].spawns[1])
			await frames(5)
			var best := 0.0
			for i in 240:
				inp(0, fwd(room), i % 30 < 20)
				await physics_frame
				best = maxf(best, height(room, a))
			ok = check(best < lip.y + 1.95, "%s: solo jump reached the lip at %d (feet at %.2f cubes)" % [_name(room), lip.x, best]) and ok
	return ok


func test_stack_climbs_lip() -> bool:
	# One stays below as a step, the other jumps from it onto the lip.
	var ok := true
	for room in LIP_ROOMS:
		await fresh(room)
		for lip in _lips(room):
			place(spot(room, lip.x - 0.55, lip.y + 1.0), spot(room, lip.x - 0.55, lip.y))
			await frames(20)
			for i in 50:
				inp(0, fwd(room), i < 18)
				await physics_frame
			idle()
			await frames(30)
			ok = check(height(room, a) > lip.y + 1.9 and a.is_on_floor(),
					"%s: stacked jump did not reach the lip at %d (%.2f)" % [_name(room), lip.x, height(room, a)]) and ok
	return ok


func test_haul_up_lip() -> bool:
	# The one on top walks on and hauls the partner up the lip with the rope.
	var ok := true
	for room in LIP_ROOMS:
		await fresh(room)
		for lip in _lips(room):
			place(spot(room, lip.x + 0.6, lip.y + 2.0), spot(room, lip.x - 0.6, lip.y))
			await frames(10)
			await follow(0, _profile_path(room, lip.x + 1, lip.x + 5), 400)
			idle()
			await frames(60)
			ok = check(height(room, b) > lip.y + 1.9, "%s: partner was not hauled onto the lip at %d (%.2f)" % [_name(room), lip.x, height(room, b)]) and ok
	return ok


func test_climb_recovery() -> bool:
	# A cube left hanging over the river climbs the rope back up to its partner with C.
	await fresh(GORGE)
	var near := _gap_near(GORGE)
	place(spot(GORGE, near + 2.5, 6.0), spot(GORGE, near + 4.0, 3.4))
	await frames(90)
	for i in 300:
		inp(1, 0.0, false, true)
		await physics_frame
		if b.is_on_floor() and height(GORGE, b) > 5.9:
			break
	inp(1, 0.0)
	await frames(30)
	return check(height(GORGE, b) > 5.9 and b.is_on_floor(), "climbing did not get the cube back up (%.2f)" % height(GORGE, b)) \
			and check(main.resets == 0, "climbing caused a reset")


func test_solo_gap_fails() -> bool:
	# No swing gap can be jumped or run off alone, whenever the jump is pressed.
	var ok := true
	for g in await _swings():
		for jump_at in [-1, 4, 8, 12, 16]:
			await fresh(g.room)
			main.rope.forces_enabled = false
			place(spot(g.room, g.edge - 1.5, g.top), stage.rooms[g.room].spawns[1])
			await frames(10)
			var landed := false
			for i in 150:
				inp(0, fwd(g.room), jump_at >= 0 and i > jump_at and i < jump_at + 22)
				await physics_frame
				if a.is_on_floor() and height(g.room, a) > g.far_top - 0.1 and _local_x(g.room, a) > g.far_x:
					landed = true
			ok = check(not landed, "%s: a solo %s crossed the gap at %d" % [_name(g.room),
					"walk-off" if jump_at < 0 else "jump at frame %d" % jump_at, g.edge]) and ok
	return ok


func test_swing_crosses_gap() -> bool:
	# One holds the edge, the other walks off, pumps the swing and grabs the far side.
	var ok := true
	for g in await _swings():
		await fresh(g.room)
		place(spot(g.room, g.edge - 0.55, g.top), spot(g.room, g.edge - 1.6, g.top))
		await frames(20)
		var crossed := await _swing(g, b, 900)
		ok = check(crossed, "%s: swing at %d did not reach the far side (b at %.1f, %.2f; resets %d)" % [_name(g.room), g.edge, _local_x(g.room, b), height(g.room, b), main.resets]) \
				and check(a.is_on_floor() and height(g.room, a) > g.top - 0.1, "%s: anchor lost the edge at %d" % [_name(g.room), g.edge]) and ok
	return ok


func test_anchor_follows() -> bool:
	# After the swing the anchor crosses too: it walks off the edge while the partner,
	# standing back on the far side, holds it, and hauls it up by walking on if it lands
	# at the bottom of the pit.
	var ok := true
	for g in await _swings():
		await fresh(g.room)
		place(spot(g.room, g.edge - 0.55, g.top), spot(g.room, g.far_x + g.stand_back, g.far_top))
		await frames(20)
		var crossed := false
		for i in 900:
			inp(0, fwd(g.room))
			var haul := a.is_on_floor() and height(g.room, a) < g.far_top - 1.0
			inp(1, fwd(g.room) if haul and b.is_on_floor() else 0.0)
			await physics_frame
			if a.is_on_floor() and height(g.room, a) > g.far_top - 0.1 and _local_x(g.room, a) > g.far_x:
				crossed = true
				break
		ok = check(crossed, "%s: anchor did not follow across at %d (a %s, b %s)" % [_name(g.room), g.edge, _fmt(a), _fmt(b)]) and ok
	return ok


func test_water_resets() -> bool:
	# Both cubes in the gorge's river (or any room's pit) is a fall back to the floor.
	await fresh(GORGE)
	var near := _gap_near(GORGE)
	place(spot(GORGE, near + 1.5, 0.0), spot(GORGE, near + 3.0, 0.0))
	await frames(10)
	return check(main.resets >= 1, "landing in the river did not reset the room")


func test_lift() -> bool:
	await fresh(CAMP)
	var lift := stage.lift
	var on_lift := lift.top_rect()
	var center_x := on_lift.get_center().x
	place(Vector2(center_x - C * 0.6, on_lift.position.y - C * 0.5), Vector2(center_x + C * 0.6, on_lift.position.y - C * 0.5))
	await frames(60)
	var stays := lift.offset < 1.0
	# Both step back onto the near ledge: the lift rises.
	place(spot(CAMP, 10.5, 6.0), spot(CAMP, 11.5, 6.0))
	await frames(90)
	return check(stays, "lift rose with cubes on it") and check(lift.offset > C, "lift did not rise once empty (%.1f)" % lift.offset)


func test_witness() -> bool:
	await fresh(CAMP)
	place(spot(CAMP, 25.0, 7.0), spot(CAMP, 26.3, 7.0))
	await frames(30)
	var started: bool = main._witness_t >= 0.0
	await frames(int(60 * 7.5))
	return check(started, "witness cutscene did not start") and check(main.witness_done, "witness cutscene did not end")


func test_cornice_breaks_under_two() -> bool:
	# The snowline: a cornice holds one cube and breaks under two, dropping both.
	await fresh(SNOWLINE)
	place(spot(SNOWLINE, 12.5, 4.0), spot(SNOWLINE, 11.5, 4.0))
	await frames(30)
	var holds_one: bool = stage.cornices[0].intact and main.resets == 0
	place(spot(SNOWLINE, 12.5, 4.0), spot(SNOWLINE, 13.4, 4.0))
	await frames(90)
	return check(holds_one, "a cornice did not hold a single cube") \
			and check(main.resets >= 1, "two cubes on a cornice did not fall (resets %d)" % main.resets) \
			and check(stage.cornices[0].intact, "the cornice did not come back after the reset")


func test_cornice_one_at_a_time() -> bool:
	# Crossing one at a time: each cube waits on the pillar or a cliff while the other
	# is on a cornice. The rope only just reaches.
	await fresh(SNOWLINE)
	place(spot(SNOWLINE, 11.55, 4.0), spot(SNOWLINE, 11.45, 4.0))
	await frames(10)
	var steps := [[0, 14.5], [1, 14.5], [0, 17.5], [1, 17.5], [0, 19.0]]
	var ok := true
	for st in steps:
		var reached: bool = await follow(st[0], [spot(SNOWLINE, st[1], 4.0)], 300)
		if not reached:
			print("      stop %s not reached (a %s, b %s)" % [st, _fmt(a), _fmt(b)])
		ok = ok and reached
		idle()
		await frames(15)
	return check(ok, "a cube did not reach its next stop") \
			and check(main.resets == 0, "the pair fell (resets %d)" % main.resets) \
			and check(stage.cornices[0].intact and stage.cornices[1].intact, "a cornice broke") \
			and check(_local_x(SNOWLINE, b) > 17.0 and height(SNOWLINE, b) > 3.9, "b did not cross (%s)" % _fmt(b))


func test_loading_bar_crossing() -> bool:
	# The pair waits for the bar to restart and crosses together right behind the fill.
	await fresh(LOADING)
	var bar: LoadingBar = stage.loading_bars[0]
	place(spot(LOADING, 10.5, 4.0), spot(LOADING, 9.5, 4.0))
	await frames(10)
	main.sim_time = LoadingBar.PERIOD - 0.05 - bar.phase
	var cubes := [a, b]
	for f in 600:
		for slot in 2:
			var cube: PlayerCube = cubes[slot]
			# Walk on while the bar is filled a cube ahead (the follower trails the leader).
			var ahead := spot(LOADING, _local_x(LOADING, cube) + 1.0, 3.5)
			var axis := fwd(LOADING) if _solid_at(ahead) or _local_x(LOADING, cube) > 17.6 else 0.0
			if slot == 1 and _local_x(LOADING, a) - _local_x(LOADING, b) < 1.2:
				axis = 0.0
			if _local_x(LOADING, cube) > 19.4:
				axis = 0.0
			inp(slot, axis)
		await physics_frame
		if _local_x(LOADING, b) > 18.2 and b.is_on_floor() and a.is_on_floor():
			break
	return check(main.resets == 0, "the pair fell (resets %d; a %s, b %s)" % [main.resets, _fmt(a), _fmt(b)]) \
			and check(_local_x(LOADING, a) > 18.0 and _local_x(LOADING, b) > 18.0, "the pair did not cross (a %s, b %s)" % [_fmt(a), _fmt(b)])


func test_loading_bar_empties() -> bool:
	# At 99% the whole bar vanishes; a pair standing on it falls.
	await fresh(LOADING)
	var bar: LoadingBar = stage.loading_bars[0]
	place(spot(LOADING, 13.5, 4.0), spot(LOADING, 14.5, 4.0))
	main.sim_time = LoadingBar.FULL_END - 0.3 - bar.phase
	await frames(90)
	return check(main.resets >= 1, "the bar emptied under the pair without a fall")


func test_wall_unreachable() -> bool:
	# The summit: nothing reaches the next hold past it.
	await fresh(SUMMIT)
	place(spot(SUMMIT, 26.4, 6.0), spot(SUMMIT, 24.0, 6.0))
	await frames(10)
	var reached := false
	for i in 240:
		inp(0, fwd(SUMMIT), i % 40 < 25)
		await physics_frame
		if _local_x(SUMMIT, a) > 32.5 and a.is_on_floor():
			reached = true
	return check(not reached, "a cube reached the far hold")


func test_seam_crossing() -> bool:
	# The summit to the seam room, from the entrance: the pair climbs the stairs to the
	# summit, one hops onto the glitching bump and jumps, and the seam pulls both through.
	await fresh(SUMMIT)
	var r: StageGenerator.Room = stage.rooms[SUMMIT]
	place(r.spawns[0], r.spawns[1])
	await frames(10)
	var climbed := await climb_together(_route(SUMMIT, [[4.5, 0.0]]) + _profile_path(SUMMIT, 5, 22))
	var jumped := await follow(0, [spot(SUMMIT, 22.5, 7.0)], 240)
	inp(0, 0.0, true)
	await frames(2)
	inp(0, 0.0)
	await frames(30)
	return check(climbed, "could not climb the stairs to the summit") \
			and check(jumped or main.corrupted, "could not get onto the glitching bump") \
			and check(main.checkpoint == SEAM, "checkpoint did not move to the seam room (%d)" % main.checkpoint) \
			and check(main.corrupted, "world did not corrupt after the seam")


func test_room_paths() -> bool:
	# From each room's spawn, the pair can walk and climb to the start of its puzzle.
	var ok := true
	var targets := {FOREST: -1, GORGE: -2, CAVE: -1, CAMP: 13, SNOWLINE: 11, WIREFRAME: -1, RERUN: -1, DEBUG: -2, LOADING: 10}
	for room in targets:
		await fresh(room)
		var r: StageGenerator.Room = stage.rooms[room]
		place(r.spawns[0], r.spawns[1])
		await frames(10)
		var to: int = targets[room]
		if to == -1:
			to = _lips(room)[0].x
		elif to == -2:
			to = _swings_in(room)[0].edge - 1
		var path := _route(room, [[4.5, 0.0]]) + _profile_path(room, 5, to)
		if not await climb_together(path):
			print("      %s: could not reach the puzzle from the spawn" % _name(room))
			ok = false
	return ok


func test_exits() -> bool:
	# Every room's exit leads onto the next floor, climbing as a pair.
	var ok := true
	for room in Tuning.ROOM_COUNT:
		if room == SUMMIT or room == EDGE:
			continue
		await fresh(room)
		if room >= SEAM:
			main._apply_event("checkpoint", [SEAM])
			main.checkpoint = room
		var path := []
		if room == SEAM:
			for top in range(1, 11):
				path.append(spot(room, 12.5 - (top - 1), top))
			path += [spot(room, 3.5, 11.0), spot(room, 4.5, 11.0), spot(room, 5.5, 11.0)]
			place(spot(room, 14.0, 0.0), spot(room, 15.3, 0.0))
		else:
			path = _profile_path(room, 23, 27) + [spot(room, 27.5, 11.0), spot(room, 26.0, 11.0)]
			place(spot(room, 22.6, _top(room, 22)), spot(room, 21.2, _top(room, 21)))
		await frames(10)
		var climbed := await climb_together(path)
		await frames(20)
		var moved: bool = main.checkpoint == room + 1
		if not (climbed and moved):
			print("      %s exit failed (climbed %s, checkpoint %d)" % [_name(room), climbed, main.checkpoint])
			ok = false
	return ok


func test_ending() -> bool:
	await fresh(EDGE - 1)
	main._apply_event("checkpoint", [SEAM])
	main._apply_event("checkpoint", [EDGE])
	main._place_at_checkpoint()
	await frames(20)
	var t := 0
	while t < 60 * 16 and main._ending < 3:
		# Toward the border, which is at the edge room's local left.
		inp(0, -fwd(EDGE))
		inp(1, -fwd(EDGE))
		await physics_frame
		t += 1
	return check(main._ending >= 3, "ending did not reach the fade (phase %d)" % main._ending) \
			and check(stage.fail_floor.failed, "floor did not fail")


func test_seeds_spawn_clear() -> bool:
	var ok := true
	for seed_value in [1, 2, 3, 7, 42, 1234]:
		for room in Tuning.ROOM_COUNT:
			await fresh(room, seed_value)
			var r: StageGenerator.Room = stage.rooms[room]
			place(r.spawns[0], r.spawns[1])
			await frames(30)
			if not (a.is_on_floor() and b.is_on_floor()) or main.resets > 0:
				print("      seed %d %s: spawn not standing (resets %d)" % [seed_value, _name(room), main.resets])
				ok = false
	return ok


# --- Layout probes -------------------------------------------------------------------

## Height of the highest walkable surface in a column (0 is the room floor).
func _top(room: int, lx: int) -> int:
	for k in range(10, 0, -1):
		# spot(.., k - 1) is the middle of the cell whose top is at height k.
		if _solid_at(spot(room, lx + 0.5, k - 1.0)) and (k == 10 or not _solid_at(spot(room, lx + 0.5, k))):
			return k
	return 0


## Standing points over each column from `from_x` to `to_x` (inclusive), at its top.
func _profile_path(room: int, from_x: int, to_x: int) -> Array:
	var points := []
	var step := 1 if to_x >= from_x else -1
	for lx in range(from_x, to_x + step, step):
		points.append([lx + 0.5, float(_top(room, lx))])
	return _route(room, points)


## Each 2-cube lip as (x, height of its foot).
func _lips(room: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for lx in range(5, 24):
		var here := _top(room, lx)
		var before := _top(room, lx - 1)
		if here - before == 2:
			out.append(Vector2i(lx, before))
	return out


class Swing:
	var room: int
	## First column past the anchor's ledge, and that ledge's height.
	var edge: int
	var top: int
	## First column of the far hold, and its height.
	var far_x: int
	var far_top: int
	## Where the partner waits on the far hold while the anchor follows.
	var stand_back: float


func _swings() -> Array[Swing]:
	var out: Array[Swing] = []
	await fresh(GORGE)
	for room in [GORGE, CAVE, CAMP, WIREFRAME, DEBUG]:
		if room != GORGE:
			await fresh(room)
		out.append_array(_swings_in(room))
	return out


## Swing gaps: a ledge, then a drop of at least two columns, then a hold two cubes lower.
func _swings_in(room: int) -> Array[Swing]:
	var out: Array[Swing] = []
	var lx := 6
	while lx < 24:
		var top := _top(room, lx - 1)
		if top >= 4 and _top(room, lx) < top - 2:
			var far := lx + 1
			while far < 26 and _top(room, far) < top - 2:
				far += 1
			if _top(room, far) == top - 2:
				var g := Swing.new()
				g.room = room
				g.edge = lx
				g.top = top
				g.far_x = far
				g.far_top = top - 2
				var width := 0
				while _top(room, far + width) == g.far_top and width < 4:
					width += 1
				g.stand_back = minf(2.5, width - 0.5)
				out.append(g)
				lx = far
				continue
		lx += 1
	return out


## Pumps a swinging cube until it lands on the far hold.
func _swing(g: Swing, cube: PlayerCube, max_frames: int) -> bool:
	var slot := 0 if cube == a else 1
	for i in max_frames:
		var axis := fwd(g.room)
		if not cube.is_on_floor() and cube.rope_force.length() > 300.0:
			# Pump: push the way the swing is already moving.
			axis = signf(cube.velocity.x) if absf(cube.velocity.x) > 20.0 else fwd(g.room)
		inp(slot, axis)
		await physics_frame
		if cube.is_on_floor() and height(g.room, cube) > g.far_top - 0.1 and _local_x(g.room, cube) > g.far_x:
			idle()
			return true
	return false


func _gap_near(room: int) -> int:
	# The near ledge is the plate whose top is 6 cubes up, with open space under it.
	for lx in range(6, 22):
		if _solid_at(spot(room, lx + 0.5, 4.6)) and not _solid_at(spot(room, lx + 0.5, 1.0)):
			return lx
	return 14


func _solid_at(p: Vector2) -> bool:
	var space: PhysicsDirectSpaceState2D = main.get_world_2d().direct_space_state
	var q := PhysicsPointQueryParameters2D.new()
	q.position = p
	q.collision_mask = 1
	return not space.intersect_point(q, 1).is_empty()


func _local_x(room: int, cube: PlayerCube) -> float:
	var x := cube.global_position.x / C
	return (Tuning.ROOM_W - x) if stage.rooms[room].mirrored else x


func _name(room: int) -> String:
	return Themes.NAMES[room]
