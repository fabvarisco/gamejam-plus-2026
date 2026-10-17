extends SceneTree

## Headless playtests for the GDD's room rules. Each test builds a fresh mountain in local
## mode, places the cubes and drives them with scripted input.
##
##   godot --headless --path . --fixed-fps 60 -s res://tests/run_tests.gd [-- name_filter] [seed=N] [trace]

# Loaded at runtime: preloading would compile main.gd before the Net autoload exists.
var main_scene: PackedScene
const C := Tuning.CUBE

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
		"test_lift", "test_witness", "test_wall_unreachable", "test_seam_crossing", "test_room_paths", "test_exits",
		"test_ending", "test_seeds_spawn_clear",
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
	# Room 3: one cube on the edge, the other hanging in the pit. The anchor holds.
	await fresh(2)
	var near := _gap_near()
	place(spot(2, near + 2.5, 6.0), spot(2, near + 4.0, 3.4))
	await frames(180)
	var stretch: float = main.rope.path_length() - Tuning.ROPE_REST
	return check(main.resets == 0, "hanging cube caused a reset") \
			and check(a.is_on_floor(), "anchor was pulled off the edge") \
			and check(not b.is_on_floor(), "partner is not hanging") \
			and check(stretch < C * 0.75, "rope stretched %.1f px while hanging" % stretch)


func test_solo_step() -> bool:
	# A 1-cube step is a solo move.
	await fresh(0)
	main.rope.forces_enabled = false
	place(spot(0, 17.0, 0.0), spot(0, 14.0, 0.0))
	var ok := await follow(0, [spot(0, 18.5, 1.0)], 120)
	return check(ok, "could not hop onto a 1-cube step (height %.2f)" % height(0, a))


func test_solo_lip_fails() -> bool:
	# Rooms 2 and 7: the 2-cube lip is out of reach of a solo jump.
	var ok := true
	for room in [1, 6]:
		await fresh(room)
		main.rope.forces_enabled = false
		var lip := _lip(room)
		place(spot(room, lip - 0.6, 0.0), spot(room, lip - 5.0, 0.0))
		var best := 0.0
		for i in 240:
			inp(0, fwd(room), i % 30 < 20)
			await physics_frame
			best = maxf(best, height(room, a))
		ok = check(best < 1.95, "room %d: solo jump reached the lip (feet at %.2f cubes)" % [room + 1, best]) and ok
	return ok


func test_stack_climbs_lip() -> bool:
	# Rooms 2 and 7: one stays on the ground as a step, the other jumps from it onto the lip.
	var ok := true
	for room in [1, 6]:
		await fresh(room)
		var lip := _lip(room)
		place(spot(room, lip - 0.55, 1.0), spot(room, lip - 0.55, 0.0))
		await frames(20)
		for i in 50:
			inp(0, fwd(room), i < 18)
			await physics_frame
		await frames(30)
		ok = check(height(room, a) > 1.9 and a.is_on_floor(), "room %d: stacked jump did not reach the lip (%.2f)" % [room + 1, height(room, a)]) and ok
	return ok


func test_haul_up_lip() -> bool:
	# Room 2: the one on top walks away and hauls the partner up the lip with the rope.
	await fresh(1)
	var lip := _lip(1)
	place(spot(1, lip + 0.6, 2.0), spot(1, lip - 0.6, 0.0))
	await frames(10)
	var waypoints := [spot(1, lip + 2.0, 2.0), spot(1, lip + 3.5, 2.0), spot(1, lip + 5.0, 2.0)]
	await follow(0, waypoints, 400)
	await frames(60)
	return check(height(1, b) > 1.9, "partner was not hauled onto the lip (%.2f)" % height(1, b))


func test_climb_recovery() -> bool:
	# Room 3: a cube left hanging climbs the rope back up to its partner with C.
	await fresh(2)
	var near := _gap_near()
	place(spot(2, near + 2.5, 6.0), spot(2, near + 4.0, 3.4))
	await frames(90)
	for i in 300:
		inp(1, 0.0, false, true)
		await physics_frame
		if b.is_on_floor() and height(2, b) > 5.9:
			break
	inp(1, 0.0)
	await frames(30)
	return check(height(2, b) > 5.9 and b.is_on_floor(), "climbing did not get the cube back up (%.2f)" % height(2, b)) \
			and check(main.resets == 0, "climbing caused a reset")


func test_solo_gap_fails() -> bool:
	# Room 3: the 2-cube gap cannot be jumped alone.
	await fresh(2)
	main.rope.forces_enabled = false
	var near := _gap_near()
	place(spot(2, near + 1.5, 6.0), spot(2, near - 4.0, 0.0))
	await frames(10)
	var landed := false
	for i in 120:
		inp(0, fwd(2), i > 8 and i < 30)
		await physics_frame
		if a.is_on_floor() and height(2, a) > 3.9 and _local_x(2, a) > near + 5.0:
			landed = true
	return check(not landed, "a solo jump crossed the 2-cube gap")


func test_swing_crosses_gap() -> bool:
	# Rooms 3, 4 (from the lift) and 7: one holds the edge, the other walks off, pumps
	# the swing and grabs the far side.
	var ok := true
	for room in [2, 3, 6]:
		await fresh(room)
		var near := _gap_near(room)
		place(spot(room, near + 2.45, 6.0), spot(room, near + 1.2, 6.0))
		await frames(20)
		var crossed := false
		for i in 900:
			var axis := fwd(room)
			if not b.is_on_floor() and b.rope_force.length() > 300.0:
				# Pump: push the way the swing is already moving.
				axis = signf(b.velocity.x) if absf(b.velocity.x) > 20.0 else fwd(room)
			inp(1, axis)
			await physics_frame
			if b.is_on_floor() and height(room, b) > 3.9 and _local_x(room, b) > near + 5.0:
				crossed = true
				break
		ok = check(crossed, "room %d: swing did not reach the far side (b at %.1f, %.2f; resets %d)" % [room + 1, _local_x(room, b), height(room, b), main.resets]) \
				and check(a.is_on_floor() and height(room, a) > 5.9, "room %d: anchor lost the edge" % (room + 1)) and ok
	return ok


func test_lift() -> bool:
	await fresh(3)
	var lift := stage.lift
	var on_lift := lift.top_rect()
	var center_x := on_lift.get_center().x
	place(Vector2(center_x - C * 0.6, on_lift.position.y - C * 0.5), Vector2(center_x + C * 0.6, on_lift.position.y - C * 0.5))
	await frames(60)
	var stays := lift.offset < 1.0
	# Both step back onto the near ledge: the lift rises.
	place(spot(3, 10.5, 6.0), spot(3, 11.5, 6.0))
	await frames(90)
	return check(stays, "lift rose with cubes on it") and check(lift.offset > C, "lift did not rise once empty (%.1f)" % lift.offset)


func test_witness() -> bool:
	await fresh(3)
	place(spot(3, 25.0, 7.0), spot(3, 26.3, 7.0))
	await frames(30)
	var started: bool = main._witness_t >= 0.0
	await frames(int(60 * 7.5))
	return check(started, "witness cutscene did not start") and check(main.witness_done, "witness cutscene did not end")


func test_wall_unreachable() -> bool:
	# Room 5: nothing reaches the next hold past the summit.
	await fresh(4)
	place(spot(4, 26.4, 6.0), spot(4, 24.0, 6.0))
	await frames(10)
	var reached := false
	for i in 240:
		inp(0, fwd(4), i % 40 < 25)
		await physics_frame
		if a.global_position.x > 32.5 * C and a.is_on_floor():
			reached = true
	return check(not reached, "a cube reached the far hold")


func test_seam_crossing() -> bool:
	# Room 5 to 6, from the room's entrance: the pair climbs the stairs to the summit, one
	# hops onto the glitching bump and jumps, and the seam pulls both past the wall.
	await fresh(4)
	var r: StageGenerator.Room = stage.rooms[4]
	place(r.spawns[0], r.spawns[1])
	await frames(10)
	var path := _route(4, [[4.5, 0.0], [11.4, 0.0], [12.5, 1.0], [13.5, 1.0], [14.5, 2.0], [15.5, 2.0],
			[16.5, 3.0], [17.5, 4.0], [18.5, 5.0], [19.5, 5.0], [20.5, 6.0], [21.4, 6.0]])
	var climbed := await climb_together(path)
	var jumped := await follow(0, [spot(4, 22.5, 7.0)], 240)
	inp(0, 0.0, true)
	await frames(2)
	inp(0, 0.0)
	await frames(30)
	return check(climbed, "could not climb the stairs to the summit") \
			and check(jumped or main.corrupted, "could not get onto the glitching bump") \
			and check(main.checkpoint == 5, "checkpoint did not move to room 6 (%d)" % main.checkpoint) \
			and check(main.corrupted, "world did not corrupt after the seam")


func test_room_paths() -> bool:
	# From each room's spawn, the pair can walk and climb to the start of its puzzle.
	var ok := true
	var routes := {
		1: [[4.5, 0.0], [10.5, 0.0]],
		2: [],
		3: [[4.5, 0.0], [5.5, 1.0], [6.5, 2.0], [7.5, 3.0], [8.5, 4.0], [9.5, 5.0], [10.5, 6.0], [11.5, 6.0], [12.6, 6.0]],
		6: [],
	}
	await fresh(2)
	var near := _gap_near(2)
	var gap_route := [[4.5, 0.0], [near - 5.6, 0.0]]
	for k in range(1, 6):
		gap_route.append([near - 5 + k - 0.5, float(k)])
	gap_route += [[near + 0.5, 6.0], [near + 1.6, 6.0]]
	routes[2] = gap_route
	routes[6] = [[9.5, 2.0], [10.5, 3.0], [11.5, 4.0], [12.5, 5.0], [13.5, 6.0], [14.6, 6.0]]
	for room in routes:
		await fresh(room)
		var r: StageGenerator.Room = stage.rooms[room]
		if room == 6:
			# Room 7 starts after its lip, which needs the stack (tested elsewhere).
			place(spot(room, 9.5, 2.0), spot(room, 8.5, 2.0))
		else:
			place(r.spawns[0], r.spawns[1])
		await frames(10)
		if not await climb_together(_route(room, routes[room])):
			print("      room %d: could not reach the puzzle from the spawn" % (room + 1))
			ok = false
	return ok


func test_exits() -> bool:
	# Every room's exit leads onto the next floor, climbing as a pair.
	var ok := true
	for room in [0, 1, 2, 3, 5, 6]:
		await fresh(room)
		var path := []
		if room == 5:
			for top in range(1, 11):
				path.append(spot(room, 12.5 - (top - 1), top))
			path += [spot(room, 3.5, 11.0), spot(room, 5.0, 11.0), spot(room, 6.5, 11.0)]
			place(spot(room, 14.0, 0.0), spot(room, 15.3, 0.0))
		else:
			path = [
				spot(room, 23.5, 6.0), spot(room, 24.5, 7.0), spot(room, 25.5, 8.0), spot(room, 26.5, 9.0),
				spot(room, 27.5, 10.0), spot(room, 27.5, 11.0), spot(room, 26.0, 11.0),
			]
			place(spot(room, 22.6, 5.0), spot(room, 21.2, 4.0))
		await frames(10)
		var climbed := await climb_together(path)
		await frames(20)
		var moved: bool = main.checkpoint == room + 1
		if not (climbed and moved):
			print("      room %d exit failed (climbed %s, checkpoint %d)" % [room + 1, climbed, main.checkpoint])
			ok = false
	return ok


func test_ending() -> bool:
	await fresh(6)
	main._apply_event("checkpoint", [5])
	main._apply_event("checkpoint", [7])
	main._place_at_checkpoint()
	await frames(20)
	var t := 0
	while t < 60 * 16 and main._ending < 3:
		inp(0, -1.0)
		inp(1, -1.0)
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
				print("      seed %d room %d: spawn not standing" % [seed_value, room + 1])
				ok = false
	return ok


# --- Layout probes -------------------------------------------------------------------

func _lip(room: int) -> int:
	# The lip is the first solid column of height 2 past the entry.
	for lx in range(7, 20):
		if _solid_at(spot(room, lx + 0.5, 1.0)):
			return lx
	return 12


func _gap_near(room: int = 2) -> int:
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
