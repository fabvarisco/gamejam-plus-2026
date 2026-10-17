extends Node2D

## The climb. The host (or a local debug session) simulates both cubes and the rope and
## drives the story beats; the client sends its input and renders snapshots. Story beats
## travel as reliable events so both players see them at the same moment.

const C := Tuning.CUBE
const LINE := "Nossa, ainda bem que não é a gente."
const WITNESS_DURATION := 7.0
const ENDING_IDLE_LIMIT := 10.0
const ROOM_FOR_SEAM := 5
const ROOM_WITNESS := 3
const ROOM_EDGE := 7
const P1_COLOR := Color(1.0, 0.56, 0.28)
const P2_COLOR := Color(0.3, 0.82, 0.86)

enum Ending { NONE, MOON, FALL, FADE, DONE }

@onready var stage: StageGenerator = $StageGenerator
@onready var player_1: PlayerCube = $Players/Player1
@onready var player_2: PlayerCube = $Players/Player2
@onready var rope: EntangledRope = $Rope
@onready var camera: Camera2D = $Camera2D
@onready var effects: Node2D = $Effects
@onready var sky: ColorRect = $Sky/Fill
@onready var glitch: ColorRect = $Glitch/Overlay
@onready var hint: Label = $HUD/Hint
@onready var room_label: Label = $HUD/RoomLabel
@onready var status: Label = $HUD/Status
@onready var fade: ColorRect = $HUD/Fade
@onready var music: Music = $Music

## Set by tests: when true, inputs come from `test_inputs` instead of the keyboard.
var test_mode: bool = false
var test_inputs: Array = [[0.0, false, false], [0.0, false, false]]

var checkpoint: int = 0
var corrupted: bool = false
var witness_done: bool = false
var sim_time: float = 0.0
var waiting_for_partner: bool = false
var resets: int = 0

var _remote_input: Array = [0.0, false, false]
var _witness_t: float = -1.0
var _ending: Ending = Ending.NONE
var _ending_t: float = 0.0
var _edge_idle: float = 0.0
var _glitch_t: float = 0.0
var _glitch_burst: float = 0.0
var _corruption_visual: float = 0.0
var _speech: Label
var _room_shown: int = -1
var _room_label_t: float = 0.0


func _ready() -> void:
	player_1.base_color = P1_COLOR
	player_2.base_color = P2_COLOR
	player_1.player_index = 0
	player_2.player_index = 1
	player_1.simulated = Net.is_authority()
	player_2.simulated = Net.is_authority()
	rope.stage = stage
	stage.generation_seed = Net.stage_seed
	stage.generate()
	_place_at_checkpoint()
	camera.global_position = stage.room_center(0)
	fade.color.a = 1.0
	create_tween().tween_property(fade, "color:a", 0.0, 0.8)
	_update_hint()
	if Net.mode == Net.Mode.HOST:
		waiting_for_partner = true
		Net.partner_left.connect(_on_partner_left)
	elif Net.mode == Net.Mode.CLIENT:
		_rpc_client_ready.rpc_id(1)
	_update_status()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		Net.leave_to_menu()


# --- Simulation ----------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if Net.mode == Net.Mode.CLIENT:
		var input := _read_input(0)
		_rpc_input.rpc_id(1, input[0], input[1], input[2])
		rope.step(delta, player_1, player_2, false)
		return
	if waiting_for_partner:
		rope.step(delta, player_1, player_2, false)
		return
	sim_time += delta
	var locked := _witness_t >= 0.0 or _ending != Ending.NONE
	var inputs := [_read_input(0), _read_input(1) if Net.mode == Net.Mode.LOCAL else _remote_input]
	var cubes := [player_1, player_2]
	for i in 2:
		var cube: PlayerCube = cubes[i]
		cube.input_axis = inputs[i][0]
		cube.input_jump = inputs[i][1]
		cube.input_climb = inputs[i][2]
		cube.input_locked = locked
	if stage.lift != null:
		stage.lift.update(delta, cubes)
	for j in stage.jitters:
		j.apply_time(sim_time)
	if _try_seam(cubes, locked):
		return
	player_1.step(delta)
	player_2.step(delta)
	rope.step(delta, player_1, player_2, true)
	_progress(delta)
	if Net.mode == Net.Mode.HOST:
		_rpc_snapshot.rpc(_snapshot())


func _read_input(slot: int) -> Array:
	if test_mode:
		return test_inputs[slot]
	if Net.mode == Net.Mode.LOCAL:
		if slot == 0:
			return [
				float(int(Input.is_physical_key_pressed(KEY_D)) - int(Input.is_physical_key_pressed(KEY_A))),
				Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_SPACE),
				Input.is_physical_key_pressed(KEY_C),
			]
		return [
			float(int(Input.is_physical_key_pressed(KEY_RIGHT)) - int(Input.is_physical_key_pressed(KEY_LEFT))),
			Input.is_physical_key_pressed(KEY_UP),
			Input.is_physical_key_pressed(KEY_PERIOD) or Input.is_physical_key_pressed(KEY_KP_0),
		]
	return [
		Input.get_axis("move_left", "move_right"),
		Input.is_action_pressed("jump"),
		Input.is_action_pressed("climb"),
	]


func _progress(delta: float) -> void:
	if _ending != Ending.NONE:
		_step_ending(delta)
		return
	if _witness_t >= 0.0:
		_witness_t += delta
		if _witness_t >= WITNESS_DURATION:
			_witness_t = -1.0
			_emit("witness_end")
		return

	var room: StageGenerator.Room = stage.rooms[checkpoint]
	var in_pit := 0
	for cube in [player_1, player_2]:
		var p: Vector2 = cube.global_position
		if p.y > room.floor_y + 2.0 * C or p.x < -14.0 * C or p.x > 44.0 * C:
			_emit("reset")
			return
		for zone in room.fall_zones:
			if zone.has_point(p):
				in_pit += 1
				break
	# One cube dangling in a pit is held by the rope and can climb back; both is a fall.
	if in_pit == 2:
		_emit("reset")
		return
	# Room 4: once the lift has risen there is no way back up from its floor.
	if checkpoint == ROOM_WITNESS and stage.lift != null and stage.lift.offset > C \
			and stage.lift_stuck_zone.has_point(player_1.global_position) \
			and stage.lift_stuck_zone.has_point(player_2.global_position):
		_emit("reset")
		return

	if checkpoint < ROOM_EDGE and _both_standing_above(stage.floor_y(checkpoint + 1)):
		_emit("checkpoint", [checkpoint + 1])
		return

	if checkpoint == ROOM_WITNESS and not witness_done and player_1.is_on_floor() and player_2.is_on_floor() \
			and stage.witness_trigger.has_point(player_1.global_position) \
			and stage.witness_trigger.has_point(player_2.global_position):
		_witness_t = 0.0
		_emit("witness")
		return

	if checkpoint == ROOM_EDGE:
		_edge_idle += delta
		var near_border := player_1.global_position.x < stage.border_left_x + 3.0 * C \
				or player_2.global_position.x < stage.border_left_x + 3.0 * C
		if near_border or _edge_idle > ENDING_IDLE_LIMIT:
			_emit("ending", [Ending.MOON])


## Room 5: jumping from the glitching bump under the broken corner is the glitch. The
## seam pulls both cubes past the wall onto room 6's floor; the crossing then counts as
## soon as both stand there.
func _try_seam(cubes: Array, locked: bool) -> bool:
	if locked or corrupted or checkpoint != ROOM_FOR_SEAM - 1:
		return false
	for cube in cubes:
		if cube.input_jump and cube.is_on_floor() and stage.seam_trigger.has_point(cube.global_position):
			var spawns: Array[Vector2] = stage.rooms[ROOM_FOR_SEAM].spawns
			player_1.teleport(spawns[0])
			player_2.teleport(spawns[1])
			rope.reset(spawns[0], spawns[1])
			_glitch_burst = 0.6
			return true
	return false


func _both_standing_above(floor_line: float) -> bool:
	for cube in [player_1, player_2]:
		if not cube.is_on_floor() or cube.global_position.y > floor_line - C * 0.25:
			return false
	return true


func _step_ending(delta: float) -> void:
	_ending_t += delta
	match _ending:
		Ending.MOON:
			if _ending_t > 2.4:
				_emit("ending", [Ending.FALL])
		Ending.FALL:
			# Both fall down the mountain they climbed, past the ledge from room 4.
			var targets := [stage.echo_x - C * 0.6, stage.echo_x + C * 0.6]
			var cubes := [player_1, player_2]
			for i in 2:
				var cube: PlayerCube = cubes[i]
				cube.velocity.x = (targets[i] - cube.global_position.x) * 1.6
			var witness_y := stage.witness_spots[0].y if not stage.witness_spots.is_empty() else stage.floor_y(ROOM_WITNESS)
			if _midpoint().y > witness_y + 5.0 * C:
				_emit("ending", [Ending.FADE])
		Ending.FADE:
			if _ending_t > 5.5:
				_emit("ending", [Ending.DONE])


# --- Events --------------------------------------------------------------------------

func _emit(event_name: String, args: Array = []) -> void:
	_apply_event(event_name, args)
	if Net.mode == Net.Mode.HOST:
		_rpc_event.rpc(event_name, args)


func _apply_event(event_name: String, args: Array) -> void:
	match event_name:
		"reset":
			resets += 1
			_place_at_checkpoint()
			_flash(0.25)
		"checkpoint":
			checkpoint = args[0]
			_edge_idle = 0.0
			if checkpoint >= ROOM_FOR_SEAM and not corrupted:
				_cross_seam()
		"witness":
			_start_witness()
		"witness_end":
			witness_done = true
			if _speech != null:
				_speech.queue_free()
				_speech = null
			music.set_state(Music.State.CORRUPT if corrupted else Music.State.PLAY)
		"ending":
			_set_ending(args[0])
		"full_state":
			var state: Dictionary = args[0]
			checkpoint = state["checkpoint"]
			witness_done = state["witness_done"]
			if state["corrupted"] and not corrupted:
				_cross_seam()
			_place_at_checkpoint()


func _place_at_checkpoint() -> void:
	var room: StageGenerator.Room = stage.rooms[checkpoint]
	player_1.teleport(room.spawns[0])
	player_2.teleport(room.spawns[1])
	rope.reset(room.spawns[0], room.spawns[1])
	if checkpoint == ROOM_WITNESS and stage.lift != null:
		stage.lift.reset()


func _cross_seam() -> void:
	corrupted = true
	player_1.set_corrupted(true)
	player_2.set_corrupted(true)
	rope.corrupted = true
	stage.set_corrupted_visible(true)
	_glitch_burst = 0.8
	music.set_state(Music.State.CORRUPT)


func _start_witness() -> void:
	music.set_state(Music.State.DUCK)
	var echo := FallingEcho.new()
	echo.position = Vector2(stage.echo_x, camera.global_position.y - 460.0)
	echo.fall_distance = 1400.0
	effects.add_child(echo)
	_speech = Label.new()
	_speech.text = LINE
	_speech.add_theme_font_size_override("font_size", 18)
	_speech.add_theme_color_override("font_color", Color(0.15, 0.08, 0.05))
	var bubble := StyleBoxFlat.new()
	bubble.bg_color = Color(1.0, 0.97, 0.88)
	bubble.border_color = Color(0.15, 0.08, 0.05)
	bubble.set_border_width_all(3)
	bubble.set_corner_radius_all(10)
	bubble.set_content_margin_all(8)
	_speech.add_theme_stylebox_override("normal", bubble)
	_speech.modulate.a = 0.0
	effects.add_child(_speech)
	var tween := create_tween()
	tween.tween_interval(1.6)
	tween.tween_property(_speech, "modulate:a", 1.0, 0.3)


func _set_ending(phase: int) -> void:
	_ending = phase as Ending
	_ending_t = 0.0
	match _ending:
		Ending.MOON:
			player_1.input_locked = true
			player_2.input_locked = true
			if stage.moon != null:
				var tween := create_tween()
				for i in 8:
					tween.tween_property(stage.moon, "visible", i % 2 == 1, 0.08 + i * 0.03)
				tween.tween_property(stage.moon, "visible", false, 0.0)
			_glitch_burst = 0.8
		Ending.FALL:
			stage.fail_floor.fail()
			stage.set_ending(true)
			player_1.set_ending_fall(true)
			player_2.set_ending_fall(true)
			music.set_state(Music.State.CUT)
			_place_witnesses()
		Ending.FADE:
			create_tween().tween_property(fade, "color:a", 1.0, 2.5)
		Ending.DONE:
			if Net.is_authority():
				Net.leave_to_menu()


func _place_witnesses() -> void:
	# Two small cubes on the room 4 ledge, watching. They say they are glad it is not them.
	for i in stage.witness_spots.size():
		var s := Sprite2D.new()
		s.texture = PlayerCube.TEX_IDLE
		s.scale = Vector2(0.2, 0.2)
		s.position = stage.witness_spots[i] + Vector2(0.0, -2.0)
		s.flip_h = stage.echo_x < s.position.x
		var mat := ShaderMaterial.new()
		mat.shader = PlayerCube.RECOLOR
		mat.set_shader_parameter("tint", P1_COLOR if i == 0 else P2_COLOR)
		s.material = mat
		effects.add_child(s)


func _flash(duration: float) -> void:
	var tween := create_tween()
	tween.tween_property(fade, "color:a", 0.6, duration * 0.4)
	tween.tween_property(fade, "color:a", 0.0, duration * 0.6)


# --- Presentation --------------------------------------------------------------------

func _process(delta: float) -> void:
	var mid := _midpoint()
	var target := mid
	if _ending == Ending.NONE:
		var idx := stage.room_index_at(mid.y)
		var cap := checkpoint + 1 if corrupted or checkpoint + 1 < ROOM_FOR_SEAM else ROOM_FOR_SEAM - 1
		target = stage.room_center(clampi(idx, 0, mini(cap, Tuning.ROOM_COUNT - 1)))
	camera.global_position = camera.global_position.lerp(target, 1.0 - exp(-delta * (6.0 if _ending == Ending.NONE else 10.0)))

	if _speech != null:
		_speech.position = mid + Vector2(-_speech.size.x * 0.5, -C * 2.6)

	_corruption_visual = move_toward(_corruption_visual, 1.0 if corrupted else 0.0, delta * 0.6)
	(sky.material as ShaderMaterial).set_shader_parameter("corruption", _corruption_visual)
	(sky.material as ShaderMaterial).set_shader_parameter("height", clampf(-camera.global_position.y / (Tuning.ROOM_PITCH * C * 7.0), 0.0, 1.0))
	_update_glitch(delta)
	_update_room_label(delta)


func _midpoint() -> Vector2:
	return (player_1.global_position + player_2.global_position) * 0.5


func _update_glitch(delta: float) -> void:
	_glitch_burst = maxf(0.0, _glitch_burst - delta)
	var level := 0.0
	if corrupted:
		_glitch_t -= delta
		if _glitch_t <= 0.0:
			_glitch_t = randf_range(0.8, 3.5)
			_glitch_burst = maxf(_glitch_burst, randf_range(0.06, 0.25))
		level = 0.05 + (0.08 if checkpoint >= ROOM_EDGE else 0.0)
	if _glitch_burst > 0.0:
		level = maxf(level, minf(0.9, 0.3 + _glitch_burst * 0.6))
	glitch.visible = level > 0.0
	(glitch.material as ShaderMaterial).set_shader_parameter("intensity", level)


func _update_room_label(delta: float) -> void:
	if checkpoint != _room_shown:
		_room_shown = checkpoint
		_room_label_t = 3.0
		var room_name := StageGenerator.ROOM_NAMES[checkpoint]
		room_label.text = "%d · %s" % [checkpoint + 1, room_name]
		if corrupted:
			room_label.text = room_label.text.substr(0, randi_range(3, room_label.text.length()))
		_update_hint()
	_room_label_t = maxf(0.0, _room_label_t - delta)
	room_label.modulate.a = clampf(_room_label_t, 0.0, 1.0)


func _update_hint() -> void:
	if checkpoint > 1:
		hint.text = ""
		return
	if Net.mode == Net.Mode.LOCAL:
		hint.text = "P1  A/D move · W/Space jump · C climb        P2  ←/→ move · ↑ jump · . climb        Esc menu"
	else:
		hint.text = "A/D or ←/→ move · Space/W/↑ jump (let go early for a short hop) · hold C to climb the rope back to your partner"


func _update_status() -> void:
	if waiting_for_partner:
		status.text = "Waiting for your partner…\nRoom code  %s" % Net.room_code
		status.visible = true
	else:
		status.visible = false


# --- Network -------------------------------------------------------------------------

func _snapshot() -> Array:
	return [
		sim_time,
		player_1.global_position, player_1.velocity, player_1.net_flags(),
		player_2.global_position, player_2.velocity, player_2.net_flags(),
		stage.lift.offset if stage.lift != null else 0.0,
	]


func _on_partner_left() -> void:
	waiting_for_partner = true
	_update_status()


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_input(axis: float, jump: bool, climb: bool) -> void:
	if Net.mode == Net.Mode.HOST:
		_remote_input = [clampf(axis, -1.0, 1.0), jump, climb]


@rpc("any_peer", "call_remote", "reliable")
func _rpc_client_ready() -> void:
	if Net.mode != Net.Mode.HOST:
		return
	var peer := multiplayer.get_remote_sender_id()
	# A partner (re)joining starts from the shared room floor, as the GDD asks.
	_place_at_checkpoint()
	_rpc_event.rpc_id(peer, "full_state", [{
		"checkpoint": checkpoint,
		"corrupted": corrupted,
		"witness_done": witness_done,
	}])
	_remote_input = [0.0, false, false]
	waiting_for_partner = false
	_update_status()


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_snapshot(data: Array) -> void:
	sim_time = data[0]
	player_1.apply_snapshot(data[1], data[2], data[3])
	player_2.apply_snapshot(data[4], data[5], data[6])
	if stage.lift != null:
		stage.lift.apply_offset(data[7])
	for j in stage.jitters:
		j.apply_time(sim_time)
	player_1.ending_fall = _ending >= Ending.FALL
	player_2.ending_fall = _ending >= Ending.FALL


@rpc("authority", "call_remote", "reliable")
func _rpc_event(event_name: String, args: Array) -> void:
	_apply_event(event_name, args)
	if event_name == "ending" and args[0] == Ending.DONE:
		Net.leave_to_menu()
