extends Node2D

## The climb. One simulation step (`_simulate`) moves the lift, the cubes and the rope and
## advances the story; everything it reads from the previous tick is plain state.
##
## Locally the step runs every physics frame. Online it runs under netfox: each cube has
## a RollbackSynchronizer for its state and for its player's input (owned by that
## player), and this node has one for the rope, the lift, the cornices and the story.
## The host is the authority over all state. The client predicts both cubes from the
## latest server state and the latest known inputs, and rewinds when a newer server
## state arrives. Story effects (flash, music, the line, the ending) are played by the
## presentation layer when it sees the state change, so they need no events.

const C := Tuning.CUBE
const LINE := "Nossa, ainda bem que não é a gente."
const INTRO_LINE := "Bem-vindos à Torre Paralelepípeda, vocês foram os cubos escolhidos para subir a torre e chegar à Lua para nos salvar da maldição que transforma os cubos em paralelepípedos. Muitos tentaram e não conseguiram. Boa Sorte!"
## The elder greets each new climb differently: the falls so far pick the line.
const RETURN_LINES: Array[String] = [
	"Você ainda está tentando subir essa torre?",
	"Mas você não desiste mesmo hein!",
]
## The fourth climb never starts: the curse breaks instead, and the elder turns into a
## parallelepiped and fades away.
const FINAL_RUN := 3
const FINAL_LINE := "Você quebrou a maldição, nãooooooo!!!"
const FINAL_HOLD := 1.2
const FINAL_MORPH := 1.6
const FINAL_FADE := 1.4
const FINAL_GAME_OVER := 4.0
## The elder's line types out at this many characters per second, then stays a while.
const INTRO_TYPE_RATE := 34.0
const INTRO_HOLD := 3.0
## A jump skips the intro, but not in its first moment (a jump still held from the menu).
const INTRO_SKIP_AFTER := 1.0
const WITNESS_DURATION := 7.0
const ENDING_IDLE_LIMIT := 10.0
const ROOM_FOR_SEAM := StageGenerator.ROOM_SEAM
const ROOM_WITNESS := StageGenerator.ROOM_WITNESS
const ROOM_EDGE := StageGenerator.ROOM_EDGE
const SKY_BLEND := 1.5
const P1_COLOR := Color(1.0, 0.56, 0.28)
const P2_COLOR := Color(0.3, 0.82, 0.86)
const PLAYER_INPUT := preload("res://scripts/player_input.gd")
## The story and the world's moving holds, as netfox property paths (the rope's chain is
## added from `EntangledRope.ROLLBACK_STATE`).
const WORLD_STATE: Array[String] = [
	":checkpoint", ":corrupted", ":witness_done", ":witness_t", ":ending", ":ending_t", ":edge_idle",
	":resets", ":sim_time", ":lift_state", ":cornice_bits", ":intro_t", ":intro_jump_held", ":runs",
]

enum Ending { NONE, MOON, FALL, FADE }

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

# Simulation state (recorded every tick online).
var checkpoint: int = 0
var corrupted: bool = false
var witness_done: bool = false
var witness_t: float = -1.0
## The elder's welcome: seconds since it began, or -1 once the climb has started.
var intro_t: float = -1.0
var intro_jump_held: bool = false
## Climbs finished so far: each one ends in the fall and starts the game over.
var runs: int = 0
var ending: int = Ending.NONE
var ending_t: float = 0.0
var edge_idle: float = 0.0
var resets: int = 0
var sim_time: float = 0.0
var lift_state: Vector2:
	get:
		return Vector2(stage.lift.offset, float(stage.lift.triggered)) if stage.lift != null else Vector2.ZERO
	set(value):
		if stage.lift != null:
			stage.lift.triggered = value.y > 0.5
			stage.lift.apply_offset(value.x)
var cornice_bits: int:
	get:
		return stage.cornice_bits()
	set(value):
		stage.apply_cornice_bits(value)

## Host only: the client is missing, so the climb holds still.
var waiting_for_partner: bool = false

var _inputs: Array[Node] = []
var _synchronizers: Array[Node] = []
## Host only: ticks at which a rejoining partner puts both cubes back on the room floor.
var _place_ticks: Dictionary = {}
var _loop_starting: bool = false
var _glitch_t: float = 0.0
var _glitch_burst: float = 0.0
var _corruption_visual: float = 0.0
var _speech: Label
var _room_shown: int = -1
var _room_label_t: float = 0.0
var _resets_shown: int = 0
var _corrupted_shown: bool = false
var _witness_shown: bool = false
var _ending_shown: int = Ending.NONE
var _intro_shown: bool = false
var _intro_speech: Label
var _elder: Elder
var _jump_now: bool = false
var _runs_shown: int = 0
var _witness_sprites: Array[Node] = []
var _game_over: Label
## Set when the final script is over (tests stop here instead of leaving to the menu).
var finished: bool = false
var _sky_top := Themes.SKIES[0][0] as Color
var _sky_bottom := Themes.SKIES[0][1] as Color
var _sky_stars: float = 0.0


func _ready() -> void:
	player_1.base_color = P1_COLOR
	player_2.base_color = P2_COLOR
	player_1.player_index = 0
	player_2.player_index = 1
	rope.stage = stage
	stage.generation_seed = Net.stage_seed
	stage.generate()
	_place_at_checkpoint()
	_elder = Elder.new()
	_elder.name = "Elder"
	_elder.position = stage.elder_spot
	$Players.add_child(_elder)
	# Every climb opens with the elder's welcome.
	intro_t = 0.0
	camera.global_position = stage.room_center(0)
	fade.color.a = 1.0
	create_tween().tween_property(fade, "color:a", 0.0, 0.8)
	_update_hint()
	if Net.is_online():
		_setup_rollback()
	if Net.mode == Net.Mode.HOST:
		waiting_for_partner = true
		Net.partner_left.connect(_on_partner_left)
	elif Net.mode == Net.Mode.CLIENT:
		_rpc_client_ready.rpc_id(1)
	_update_status()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		Net.leave_to_menu()


# --- Netfox --------------------------------------------------------------------------

func _setup_rollback() -> void:
	var cubes := [player_1, player_2]
	for i in 2:
		var cube: PlayerCube = cubes[i]
		var input := PLAYER_INPUT.new()
		input.name = "Input"
		# Player 1 is the host. Player 2 belongs to whoever joins; the host learns who
		# when the client says it is ready.
		var owner_id := 1 if i == 0 else (multiplayer.get_unique_id() if Net.mode == Net.Mode.CLIENT else -1)
		input.set_multiplayer_authority(owner_id)
		cube.add_child(input)
		_inputs.append(input)
		var sync := RollbackSynchronizer.new()
		sync.name = "Rollback"
		sync.root = cube
		sync.enable_prediction = true
		sync.state_properties = PlayerCube.ROLLBACK_STATE
		sync.input_properties = PLAYER_INPUT.PROPERTIES
		cube.add_child(sync)
		_synchronizers.append(sync)
	var world := RollbackSynchronizer.new()
	world.name = "Rollback"
	world.root = self
	world.enable_prediction = true
	world.state_properties = WORLD_STATE + EntangledRope.ROLLBACK_STATE
	add_child(world)
	_synchronizers.append(world)
	if Net.mode == Net.Mode.HOST:
		# Nothing goes to a partner until its game is loaded: packets queued during the
		# load would arrive seconds stale and flood its rollback.
		for sync in _synchronizers:
			sync.visibility_filter.default_visibility = false
	NetworkRollback.before_loop.connect(_on_before_loop)
	NetworkRollback.on_prepare_tick.connect(_on_prepare_tick)


func _exit_tree() -> void:
	if NetworkRollback.before_loop.is_connected(_on_before_loop):
		NetworkRollback.before_loop.disconnect(_on_before_loop)
		NetworkRollback.on_prepare_tick.disconnect(_on_prepare_tick)


func _on_before_loop() -> void:
	_loop_starting = true


## The rope ties both cubes and the world into one simulation, so on the host every
## resimulation (a late input from the client) replays all of it from the first changed
## tick. Connected before the synchronizers, so they see the mutation for this tick.
func _on_prepare_tick(tick: int) -> void:
	if not _loop_starting:
		return
	_loop_starting = false
	if multiplayer.is_server():
		for node in [self, player_1, player_2]:
			NetworkRollback.mutate(node, tick)


func _rollback_tick(delta: float, tick: int, is_fresh: bool) -> void:
	if waiting_for_partner:
		return
	if _place_ticks.has(tick):
		_place_at_checkpoint()
	var inputs := []
	for input in _inputs:
		inputs.append([input.axis, input.jump, input.climb])
	_simulate(delta, inputs, is_fresh)


# --- Simulation ----------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if Net.is_online():
		return
	_simulate(delta, [_read_input(0), _read_input(1)], true)


func _simulate(delta: float, inputs: Array, fresh: bool) -> void:
	sim_time += delta
	var falling := ending >= Ending.FALL
	if stage.fail_floor != null and stage.fail_floor.failed != falling:
		if falling:
			stage.fail_floor.fail()
		else:
			stage.fail_floor.restore()
	stage.set_ending(falling)
	var locked := intro_t >= 0.0 or witness_t >= 0.0 or ending != Ending.NONE
	_jump_now = inputs[0][1] or inputs[1][1]
	var cubes := [player_1, player_2]
	for i in 2:
		var cube: PlayerCube = cubes[i]
		cube.input_axis = clampf(inputs[i][0], -1.0, 1.0)
		cube.input_jump = inputs[i][1]
		cube.input_climb = inputs[i][2]
		cube.input_locked = locked
		cube.fx_enabled = fresh
	if stage.lift != null:
		stage.lift.update(delta, cubes)
	for c in stage.cornices:
		c.update(cubes)
	stage.apply_time(sim_time)
	if _try_seam(cubes, locked):
		return
	player_1.step(delta)
	player_2.step(delta)
	rope.step(delta, player_1, player_2, true)
	_progress(delta)


func _read_input(slot: int) -> Array:
	if test_mode:
		return test_inputs[slot]
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


func _progress(delta: float) -> void:
	if ending != Ending.NONE:
		_step_ending(delta)
		return
	if intro_t >= 0.0:
		intro_t += delta
		if is_final_run():
			return
		var skipped := _jump_now and not intro_jump_held and intro_t > INTRO_SKIP_AFTER
		intro_jump_held = _jump_now
		if skipped or intro_t >= intro_duration():
			intro_t = -1.0
		return
	if witness_t >= 0.0:
		witness_t += delta
		if witness_t >= WITNESS_DURATION:
			witness_t = -1.0
			witness_done = true
		return

	var room: StageGenerator.Room = stage.rooms[checkpoint]
	var in_pit := 0
	for cube in [player_1, player_2]:
		var p: Vector2 = cube.global_position
		if p.y > room.floor_y + 2.0 * C or p.x < -14.0 * C or p.x > 44.0 * C:
			_fall()
			return
		for zone in room.fall_zones:
			if zone.has_point(p):
				in_pit += 1
				break
	# One cube dangling in a pit is held by the rope and can climb back; both is a fall.
	if in_pit == 2:
		_fall()
		return
	# The camp: once the lift has risen there is no way back up from its floor.
	if checkpoint == ROOM_WITNESS and stage.lift != null and stage.lift.offset > C \
			and stage.lift_stuck_zone.has_point(player_1.global_position) \
			and stage.lift_stuck_zone.has_point(player_2.global_position):
		_fall()
		return

	if checkpoint < ROOM_EDGE and _both_standing_above(stage.floor_y(checkpoint + 1)):
		set_checkpoint(checkpoint + 1)
		return

	if checkpoint == ROOM_WITNESS and not witness_done and player_1.on_floor and player_2.on_floor \
			and stage.witness_trigger.has_point(player_1.global_position) \
			and stage.witness_trigger.has_point(player_2.global_position):
		witness_t = 0.0
		return

	if checkpoint == ROOM_EDGE:
		edge_idle += delta
		var near_border := stage.near_border(player_1.global_position) or stage.near_border(player_2.global_position)
		if near_border or edge_idle > ENDING_IDLE_LIMIT:
			_set_ending(Ending.MOON)


## The summit: jumping from the glitching bump under the broken corner is the glitch. The
## seam pulls both cubes past the wall onto the seam room's floor; the crossing then
## counts as soon as both stand there.
func _try_seam(cubes: Array, locked: bool) -> bool:
	if locked or corrupted or checkpoint != ROOM_FOR_SEAM - 1:
		return false
	for cube in cubes:
		if cube.input_jump and cube.on_floor and stage.seam_trigger.has_point(cube.global_position):
			var spawns: Array[Vector2] = stage.rooms[ROOM_FOR_SEAM].spawns
			player_1.teleport(spawns[0])
			player_2.teleport(spawns[1])
			rope.reset(spawns[0], spawns[1])
			return true
	return false


func _both_standing_above(floor_line: float) -> bool:
	for cube in [player_1, player_2]:
		if not cube.on_floor or cube.global_position.y > floor_line - C * 0.25:
			return false
	return true


func _step_ending(delta: float) -> void:
	ending_t += delta
	match ending:
		Ending.MOON:
			if ending_t > 2.4:
				_set_ending(Ending.FALL)
		Ending.FALL:
			# Both fall down the mountain they climbed, past the camp ledge where they watched.
			var targets := [stage.echo_x - C * 0.6, stage.echo_x + C * 0.6]
			var cubes := [player_1, player_2]
			for i in 2:
				var cube: PlayerCube = cubes[i]
				cube.velocity.x = (targets[i] - cube.global_position.x) * 1.6
			var witness_y := stage.witness_spots[0].y if not stage.witness_spots.is_empty() else stage.floor_y(ROOM_WITNESS)
			if _midpoint().y > witness_y + 5.0 * C:
				_set_ending(Ending.FADE)
		Ending.FADE:
			if ending_t > 5.5:
				_restart_climb()


func _set_ending(phase: int) -> void:
	ending = phase
	ending_t = 0.0
	if phase == Ending.FALL:
		player_1.set_ending_fall(true)
		player_2.set_ending_fall(true)


func _fall() -> void:
	resets += 1
	_place_at_checkpoint()


## The fall at the edge is not the end: the game starts over in the village, and the
## elder greets the pair again.
func _restart_climb() -> void:
	runs += 1
	checkpoint = 0
	corrupted = false
	witness_done = false
	witness_t = -1.0
	ending = Ending.NONE
	ending_t = 0.0
	edge_idle = 0.0
	player_1.set_ending_fall(false)
	player_2.set_ending_fall(false)
	if stage.lift != null:
		stage.lift.reset()
	_place_at_checkpoint()
	intro_t = 0.0
	intro_jump_held = true


func is_final_run() -> bool:
	return runs >= FINAL_RUN


func intro_line() -> String:
	if is_final_run():
		return FINAL_LINE
	return INTRO_LINE if runs == 0 else RETURN_LINES[runs - 1]


func _typing_time() -> float:
	return intro_line().length() / INTRO_TYPE_RATE


func intro_duration() -> float:
	if is_final_run():
		return _typing_time() + FINAL_HOLD + FINAL_MORPH + FINAL_FADE + FINAL_GAME_OVER
	return _typing_time() + INTRO_HOLD


## Moves the climb to a room (the story's checkpoint). Rooms from the seam up are the
## corrupted half.
func set_checkpoint(index: int) -> void:
	checkpoint = index
	edge_idle = 0.0
	if checkpoint >= ROOM_FOR_SEAM:
		corrupted = true


func _place_at_checkpoint() -> void:
	var room: StageGenerator.Room = stage.rooms[checkpoint]
	player_1.teleport(room.spawns[0])
	player_2.teleport(room.spawns[1])
	rope.reset(room.spawns[0], room.spawns[1])
	if checkpoint == ROOM_WITNESS and stage.lift != null:
		stage.lift.reset()
	for c in stage.cornices:
		c.set_intact(true)


# --- Story effects -------------------------------------------------------------------

## Plays the effects for whatever the simulation state changed since the last frame.
func _show_story() -> void:
	if runs != _runs_shown:
		_runs_shown = runs
		_show_restart()
	if resets > _resets_shown:
		_flash(0.25)
	_resets_shown = resets
	if corrupted != _corrupted_shown:
		_corrupted_shown = corrupted
		_show_corruption(corrupted)
	var welcoming := intro_t >= 0.0
	if welcoming != _intro_shown:
		_intro_shown = welcoming
		if welcoming:
			_start_intro()
		else:
			_end_intro()
	if _intro_speech != null and welcoming:
		var typed := int(intro_t * INTRO_TYPE_RATE)
		_intro_speech.visible_characters = typed
		_elder.talking = typed < intro_line().length()
	if welcoming and is_final_run():
		_show_final()
	var watching := witness_t >= 0.0
	if watching != _witness_shown:
		_witness_shown = watching
		if watching:
			_start_witness()
		else:
			_end_witness()
	while _ending_shown < ending:
		_ending_shown += 1
		_show_ending(_ending_shown)


func _show_corruption(on: bool) -> void:
	player_1.set_corrupted(on)
	player_2.set_corrupted(on)
	rope.corrupted = on
	stage.set_corrupted_visible(on)
	if on:
		_glitch_burst = 0.8
	music.set_state(Music.State.CORRUPT if on else Music.State.PLAY)


func _start_intro() -> void:
	music.set_state(Music.State.DUCK)
	# Long lines wrap at a fixed width; the bubble keeps its full size while it types out.
	var line := intro_line()
	_intro_speech = _make_bubble(line, 460.0 if line.length() > 48 else 0.0)
	_intro_speech.visible_characters = 0
	_update_hint()


func _end_intro() -> void:
	if _intro_speech != null:
		var bubble := _intro_speech
		_intro_speech = null
		var tween := create_tween()
		tween.tween_property(bubble, "modulate:a", 0.0, 0.3)
		tween.tween_callback(bubble.queue_free)
	_elder.talking = false
	music.set_state(Music.State.CORRUPT if corrupted else Music.State.PLAY)
	_update_hint()


func _make_bubble(text: String, wrap_width: float = 0.0) -> Label:
	var label := Label.new()
	if wrap_width > 0.0:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = wrap_width
		label.size.x = wrap_width
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.15, 0.08, 0.05))
	var bubble := StyleBoxFlat.new()
	bubble.bg_color = Color(1.0, 0.97, 0.88)
	bubble.border_color = Color(0.15, 0.08, 0.05)
	bubble.set_border_width_all(3)
	bubble.set_corner_radius_all(10)
	bubble.set_content_margin_all(8)
	label.add_theme_stylebox_override("normal", bubble)
	effects.add_child(label)
	return label


func _start_witness() -> void:
	music.set_state(Music.State.DUCK)
	var echo := FallingEcho.new()
	echo.position = Vector2(stage.echo_x, camera.global_position.y - 460.0)
	echo.fall_distance = 1400.0
	effects.add_child(echo)
	_speech = _make_bubble(LINE)
	_speech.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_interval(1.6)
	tween.tween_property(_speech, "modulate:a", 1.0, 0.3)


func _end_witness() -> void:
	if _speech != null:
		_speech.queue_free()
		_speech = null
	music.set_state(Music.State.CORRUPT if corrupted else Music.State.PLAY)


func _show_ending(phase: int) -> void:
	match phase:
		Ending.MOON:
			if stage.moon != null:
				var tween := create_tween()
				for i in 8:
					tween.tween_property(stage.moon, "visible", i % 2 == 1, 0.08 + i * 0.03)
				tween.tween_property(stage.moon, "visible", false, 0.0)
			_glitch_burst = 0.8
		Ending.FALL:
			music.set_state(Music.State.CUT)
			_place_witnesses()
		Ending.FADE:
			create_tween().tween_property(fade, "color:a", 1.0, 2.5)


## Back in the village for another climb: undo the ending's effects.
func _show_restart() -> void:
	_ending_shown = ending
	for node in _witness_sprites:
		node.queue_free()
	_witness_sprites.clear()
	if stage.moon != null:
		stage.moon.visible = true
	_room_shown = -1
	camera.global_position = stage.room_center(0)
	create_tween().tween_property(fade, "color:a", 0.0, 1.2)


## The curse breaks: after its line, the elder becomes a parallelepiped, fades, and the
## game is over.
func _show_final() -> void:
	var t := intro_t - _typing_time() - FINAL_HOLD
	var morph := clampf(t / FINAL_MORPH, 0.0, 1.0)
	if morph > 0.0 and _elder.cursed == 0.0:
		_glitch_burst = 0.6
		_flash(0.3)
		if _intro_speech != null:
			create_tween().tween_property(_intro_speech, "modulate:a", 0.0, 0.4)
	_elder.cursed = morph
	_elder.modulate.a = 1.0 - clampf((t - FINAL_MORPH) / FINAL_FADE, 0.0, 1.0)
	if t > FINAL_MORPH + FINAL_FADE and _game_over == null:
		_show_game_over()
	if intro_t >= intro_duration() and not finished:
		finished = true
		if not test_mode:
			Net.leave_to_menu()


func _show_game_over() -> void:
	_game_over = Label.new()
	_game_over.text = "GAME OVER"
	_game_over.add_theme_font_size_override("font_size", 64)
	_game_over.add_theme_color_override("font_color", Color(1.0, 0.97, 0.9))
	_game_over.add_theme_color_override("font_outline_color", Color(0.16, 0.08, 0.05))
	_game_over.add_theme_constant_override("outline_size", 12)
	_game_over.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_game_over.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_game_over.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_game_over.grow_vertical = Control.GROW_DIRECTION_BOTH
	_game_over.modulate.a = 0.0
	hint.get_parent().add_child(_game_over)
	create_tween().tween_property(_game_over, "modulate:a", 1.0, 0.8)
	hint.text = ""


func _place_witnesses() -> void:
	# Two small cubes on the camp's ledge, watching. They say they are glad it is not them.
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
		_witness_sprites.append(s)


func _flash(duration: float) -> void:
	var tween := create_tween()
	tween.tween_property(fade, "color:a", 0.6, duration * 0.4)
	tween.tween_property(fade, "color:a", 0.0, duration * 0.6)


# --- Presentation --------------------------------------------------------------------

func _process(delta: float) -> void:
	_show_story()
	var mid := _midpoint()
	var target := mid
	if ending == Ending.NONE:
		var idx := stage.room_index_at(mid.y)
		var cap := checkpoint + 1 if corrupted or checkpoint + 1 < ROOM_FOR_SEAM else ROOM_FOR_SEAM - 1
		target = stage.room_center(clampi(idx, 0, mini(cap, Tuning.ROOM_COUNT - 1)))
	camera.global_position = camera.global_position.lerp(target, 1.0 - exp(-delta * (6.0 if ending == Ending.NONE else 10.0)))

	if _speech != null:
		_speech.position = mid + Vector2(-_speech.size.x * 0.5, -C * 2.6)
	if _intro_speech != null:
		_intro_speech.position = _elder.position + Vector2(-_intro_speech.size.x * 0.5, -_intro_speech.size.y - C * 1.6)

	_corruption_visual = move_toward(_corruption_visual, 1.0 if corrupted else 0.0, delta * 0.6)
	_update_sky(delta)
	_update_glitch(delta)
	_update_room_label(delta)


## Each room has its own sky; the camera's room blends in as the climb moves up.
func _update_sky(delta: float) -> void:
	var idx := stage.room_index_at(camera.global_position.y + Tuning.ROOM_H * 0.5 * C)
	if not corrupted:
		idx = mini(idx, ROOM_FOR_SEAM - 1)
	var theme: Array = Themes.SKIES[idx]
	var k := 1.0 - exp(-delta * SKY_BLEND)
	_sky_top = _sky_top.lerp(theme[0], k)
	_sky_bottom = _sky_bottom.lerp(theme[1], k)
	_sky_stars = lerpf(_sky_stars, theme[2], k)
	var mat := sky.material as ShaderMaterial
	mat.set_shader_parameter("corruption", _corruption_visual)
	mat.set_shader_parameter("top_color", _sky_top)
	mat.set_shader_parameter("bottom_color", _sky_bottom)
	mat.set_shader_parameter("stars", _sky_stars)


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
		var room_name := Themes.NAMES[checkpoint]
		room_label.text = "%d · %s" % [checkpoint + 1, room_name]
		if runs > 0:
			room_label.text += "  (climb %d)" % (runs + 1)
		if corrupted:
			room_label.text = room_label.text.substr(0, randi_range(3, room_label.text.length()))
		_update_hint()
	_room_label_t = maxf(0.0, _room_label_t - delta)
	room_label.modulate.a = clampf(_room_label_t, 0.0, 1.0)


func _update_hint() -> void:
	if intro_t >= 0.0:
		hint.text = "" if is_final_run() else "Press jump to continue"
		return
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

func _on_partner_left() -> void:
	waiting_for_partner = true
	_update_status()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_client_ready() -> void:
	if Net.mode != Net.Mode.HOST:
		return
	# The partner's cube follows the new peer's input from now on.
	var peer := multiplayer.get_remote_sender_id()
	_inputs[1].set_multiplayer_authority(peer)
	_synchronizers[1].process_authority()
	for sync in _synchronizers:
		sync.visibility_filter.set_visibility_for(peer, true)
		sync.visibility_filter.update_visibility()
	# A partner (re)joining starts from the shared room floor, as the GDD asks. netfox
	# sends the client the rest of the state.
	_place_ticks[NetworkTime.tick] = true
	waiting_for_partner = false
	_update_status()
	_rpc_start_clock.rpc_id(peer)


## Host to client: both games are loaded, so the client can sync its clock now.
@rpc("authority", "call_remote", "reliable")
func _rpc_start_clock() -> void:
	Net.start_clock()
