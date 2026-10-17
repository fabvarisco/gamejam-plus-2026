class_name PlayerCube
extends CharacterBody2D

## One climber. The game feeds it input and the rope feeds it a force; `step()` is called
## by the simulating peer only. Clients receive snapshots and just animate.

const TEX_IDLE := preload("res://Assets/cubo_parado_dir.svg")
const TEX_WALK := preload("res://Assets/cubo_andar_1_dir.svg")
const TEX_JUMP := preload("res://Assets/cubo_pulando_dir.svg")
const TEX_FALL := preload("res://Assets/cubo_caindo_dir.svg")
const TEX_LAND := preload("res://Assets/cubo_aterrissando_dir.svg")
const TEX_BLINK := preload("res://Assets/cubo_piscando_dir.svg")
const TEX_HURT := preload("res://Assets/cubo_dano_dir.svg")
const RECOLOR := preload("res://scripts/cube_recolor.gdshader")

const GLITCH_PALETTE: Array[Color] = [
	Color(0.62, 0.64, 0.68), Color(0.95, 0.2, 0.75), Color(0.25, 0.95, 0.45),
	Color(0.2, 0.85, 1.0), Color(0.96, 0.96, 0.96), Color(0.18, 0.18, 0.22),
]

const SQUASH_SMOOTH := 16.0

const FLAG_FLOOR := 1
const FLAG_LEFT := 2
const FLAG_CLIMB := 4
const FLAG_LAND := 8

@export var player_index: int = 0
@export var base_color: Color = Color(1.0, 0.56, 0.3):
	set(value):
		base_color = value
		_apply_colors()

# Written by the game every tick.
var input_axis: float = 0.0
var input_jump: bool = false
var input_climb: bool = false
var input_locked: bool = false

# Written by the rope every tick.
var rope_force: Vector2 = Vector2.ZERO
var climb_target: Vector2 = Vector2.ZERO
var climb_available: bool = false

## False on a client: the cube then only follows snapshots from the host.
var simulated: bool = true
var climbing: bool = false
var corrupted: bool = false
var ending_fall: bool = false
var facing_left: bool = false

var _jump_prev: bool = false
var _jumping: bool = false
var _coyote: float = 0.0
var _jump_buffer: float = 0.0
var _land_timer: float = 0.0
var _hurt_timer: float = 0.0
var _blink_timer: float = 0.0
var _walk_clock: float = 0.0
var _glitch_clock: float = 0.0
var _glitch_color: Color = Color.WHITE
var _glitch_amount: float = 0.0
var _anim_on_floor: bool = true
var _visual_scale := Vector2.ONE
var _step_phase: float = 0.0

# Client-side interpolation target.
var _net_target: Vector2 = Vector2.ZERO
var _net_has_target: bool = false

@onready var _visual: Node2D = $Visual
@onready var sprite: Sprite2D = $Visual/Sprite2D
@onready var _walk_dust: CPUParticles2D = $Visual/WalkDust
@onready var _land_dust: CPUParticles2D = $Visual/LandDust


func _ready() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = RECOLOR
	sprite.material = mat
	_apply_colors()


func step(delta: float) -> void:
	var was_on_floor := is_on_floor()
	if ending_fall:
		velocity.y = minf(velocity.y + Tuning.GRAVITY * delta, Tuning.MAX_FALL_SPEED)
		global_position += velocity * delta
		return

	_coyote = Tuning.COYOTE_TIME if was_on_floor else maxf(0.0, _coyote - delta)
	var jump := input_jump and not input_locked
	if jump and not _jump_prev:
		_jump_buffer = Tuning.JUMP_BUFFER
	else:
		_jump_buffer = maxf(0.0, _jump_buffer - delta)
	_jump_prev = jump
	var axis := 0.0 if input_locked else input_axis

	climbing = input_climb and not input_locked and climb_available \
			and (not was_on_floor or climb_target.y < global_position.y - 8.0)
	# A climbing cube hangs on the rope: the partner cannot stand on it or ride it.
	collision_layer = 0 if climbing else 2
	if climbing:
		_step_climb()
		return

	velocity.y = minf(velocity.y + Tuning.GRAVITY * delta, Tuning.MAX_FALL_SPEED)
	var force := rope_force
	if was_on_floor:
		var target := axis * Tuning.WALK_SPEED
		if axis != 0.0 and signf(force.x) == -signf(axis):
			# Walking against the rope: the partner's weight slows the walk, and a pull
			# stronger than the cube's grip stops it.
			target *= clampf(1.0 - absf(force.x) / Tuning.ANCHOR_GRIP, 0.0, 1.0)
		velocity.x = move_toward(velocity.x, target, Tuning.GROUND_ACCEL * delta)
		# A cube on a hold is an anchor: sideways pull under its grip does nothing.
		if absf(force.x) > Tuning.ANCHOR_GRIP:
			velocity.x += (force.x - signf(force.x) * Tuning.ANCHOR_GRIP) * delta
		velocity.y += force.y * delta
	else:
		var swinging := force.length() > Tuning.SWING_MIN_TENSION
		if axis != 0.0 and swinging:
			# On a taut rope, input pumps the swing along the arc, past walking speed.
			var tangent := Vector2(-force.y, force.x).normalized()
			if tangent.x * axis < 0.0:
				tangent = -tangent
			velocity += tangent * Tuning.SWING_PUMP * delta
			velocity = velocity.limit_length(Tuning.SWING_MAX_SPEED)
		elif axis != 0.0 and not (signf(velocity.x) == axis and absf(velocity.x) > Tuning.AIR_SPEED):
			velocity.x = move_toward(velocity.x, axis * Tuning.AIR_SPEED, Tuning.AIR_ACCEL * delta)
		velocity += force * delta
		if is_on_wall():
			# Hauled against a wall, the rope drags the cube up the face toward the lip.
			var into := -force.dot(get_wall_normal())
			if into > 0.0 and force.y < 0.0:
				velocity.y -= into * delta

	if _jump_buffer > 0.0 and _coyote > 0.0:
		velocity.y = -Tuning.JUMP_VELOCITY
		velocity.x = clampf(velocity.x, -Tuning.AIR_SPEED, Tuning.AIR_SPEED)
		_on_jumped()
		_jumping = true
		_jump_buffer = 0.0
		_coyote = 0.0
	if _jumping and not jump and velocity.y < 0.0:
		velocity.y *= Tuning.JUMP_CUT
		_jumping = false
	if velocity.y >= 0.0:
		_jumping = false

	var fall_speed := velocity.y
	move_and_slide()
	if not was_on_floor and is_on_floor():
		_land_timer = 0.14
		_on_landed()
		if corrupted and fall_speed > 650.0:
			_hurt_timer = 0.35

	# Step over small lips, grounded or not (standing on the partner leaves you a hair
	# below the next step).
	if is_on_wall():
		var into := -signf(get_wall_normal().x)
		var pulled := force.x * into > 200.0
		if (axis == into or pulled) and velocity.y > -200.0:
			_try_mantle(into)

	if axis != 0.0:
		facing_left = axis < 0.0


func _step_climb() -> void:
	var to := climb_target - global_position
	velocity = to.normalized() * Tuning.CLIMB_SPEED if to.length() > 2.0 else Vector2.ZERO
	if to.y > -1.0:
		# Level with the target: step sideways onto the hold, never above it (climbing
		# past the partner's feet would lift the partner off its hold).
		velocity = Vector2(signf(to.x) * Tuning.CLIMB_SPEED if absf(to.x) > 2.0 else 0.0, 0.0)
	if is_on_wall():
		# Hand over hand up a rope that hugs a wall: slide along it instead of into it.
		var n := get_wall_normal()
		if velocity.dot(n) < 0.0:
			velocity -= n * velocity.dot(n)
			velocity = velocity.normalized() * Tuning.CLIMB_SPEED if velocity.length() > 1.0 else Vector2.ZERO
	if is_on_ceiling() and velocity.y < 0.0:
		# Under a ledge's lip: shuffle out to the nearer side that is open above.
		velocity = Vector2(_open_side() * Tuning.CLIMB_SPEED, 0.0)
	move_and_slide()
	if is_on_wall():
		_try_mantle(-signf(get_wall_normal().x))
	if absf(to.x) > 1.0:
		facing_left = to.x < 0.0


func _open_side() -> float:
	var shift := 4.0
	while shift <= Tuning.CUBE:
		for side in [1.0, -1.0]:
			var moved := global_transform.translated(Vector2(side * shift, 0.0))
			if not test_move(global_transform, Vector2(side * shift, 0.0)) and not test_move(moved, Vector2(0.0, -6.0)):
				return side
		shift += 4.0
	return 0.0


## Pops the cube over a ledge lip that is less than MANTLE_HEIGHT above its feet.
func _try_mantle(dir: float) -> void:
	if dir == 0.0:
		return
	var lift := 2.0
	while lift <= Tuning.MANTLE_HEIGHT:
		var raised := global_transform.translated(Vector2(0.0, -lift))
		if not test_move(global_transform, Vector2(0.0, -lift)) and not test_move(raised, Vector2(dir * 3.0, 0.0)):
			global_position += Vector2(dir * 3.0, -lift)
			velocity.y = minf(velocity.y, 0.0)
			return
		lift += 2.0


func teleport(pos: Vector2) -> void:
	global_position = pos
	velocity = Vector2.ZERO
	rope_force = Vector2.ZERO
	climbing = false
	_jumping = false
	_net_target = pos
	_net_has_target = false


func set_ending_fall(on: bool) -> void:
	ending_fall = on
	collision_mask = 0 if on else 3
	collision_layer = 0 if on else 2


func set_corrupted(on: bool) -> void:
	corrupted = on
	_apply_colors()


func net_flags() -> int:
	var flags := 0
	if is_on_floor():
		flags |= FLAG_FLOOR
	if facing_left:
		flags |= FLAG_LEFT
	if climbing:
		flags |= FLAG_CLIMB
	if _land_timer > 0.0:
		flags |= FLAG_LAND
	return flags


func apply_snapshot(pos: Vector2, vel: Vector2, flags: int) -> void:
	if not _net_has_target or pos.distance_to(global_position) > Tuning.CUBE * 3.0:
		global_position = pos
	_net_target = pos
	_net_has_target = true
	velocity = vel
	var on_floor := flags & FLAG_FLOOR != 0
	if _anim_on_floor and not on_floor and vel.y < -200.0:
		_on_jumped()
	_anim_on_floor = on_floor
	facing_left = flags & FLAG_LEFT != 0
	climbing = flags & FLAG_CLIMB != 0
	if flags & FLAG_LAND != 0 and _land_timer <= 0.0:
		_land_timer = 0.14
		_on_landed()


func _process(delta: float) -> void:
	if not simulated and _net_has_target:
		global_position = global_position.lerp(_net_target, 1.0 - exp(-delta * 25.0))
	elif simulated:
		_anim_on_floor = is_on_floor()
	_land_timer = maxf(0.0, _land_timer - delta)
	_hurt_timer = maxf(0.0, _hurt_timer - delta)
	_update_texture(delta)
	_update_glitch(delta)
	_apply_juice(delta)


func _on_jumped() -> void:
	_visual_scale = Vector2(0.72, 1.34)


func _on_landed() -> void:
	_visual_scale = Vector2(1.36, 0.64)
	_land_dust.restart()


## Squash and stretch around the feet, plus walking dust. Visual only, so it runs from
## velocity and floor state on both peers.
func _apply_juice(delta: float) -> void:
	var target := Vector2.ONE
	if ending_fall:
		pass
	elif not _anim_on_floor:
		var stretch := clampf(absf(velocity.y) / 520.0, 0.0, 1.0)
		if velocity.y < 0.0:
			target = Vector2(lerpf(1.0, 0.8, stretch), lerpf(1.0, 1.24, stretch))
		else:
			target = Vector2(lerpf(1.0, 1.1, stretch), lerpf(1.0, 0.86, stretch))
	else:
		var move := clampf(absf(velocity.x) / Tuning.WALK_SPEED, 0.0, 1.0)
		_step_phase += absf(velocity.x) * delta * 0.09
		var bob := sin(_step_phase) * 0.05 * move
		target = Vector2(lerpf(1.0, 1.1, move) + bob, lerpf(1.0, 0.9, move) - bob)
	_visual_scale = _visual_scale.lerp(target, 1.0 - exp(-SQUASH_SMOOTH * delta))
	_visual.scale = _visual_scale
	var walking := _anim_on_floor and not ending_fall and absf(velocity.x) > 30.0
	_walk_dust.emitting = walking
	if walking:
		_walk_dust.direction = Vector2(-signf(velocity.x), -0.45)


func _update_texture(delta: float) -> void:
	sprite.flip_h = facing_left
	if ending_fall:
		sprite.texture = TEX_FALL
		sprite.rotation += delta * 5.0 * (1.0 if player_index == 0 else -1.0)
		return
	sprite.rotation = 0.0
	if _hurt_timer > 0.0:
		sprite.texture = TEX_HURT
	elif climbing:
		sprite.texture = TEX_JUMP
	elif not _anim_on_floor:
		sprite.texture = TEX_JUMP if velocity.y < 0.0 else TEX_FALL
	elif _land_timer > 0.0:
		sprite.texture = TEX_LAND
	elif absf(velocity.x) > 10.0:
		_walk_clock += delta
		sprite.texture = TEX_WALK if int(_walk_clock * 8.0) % 2 == 0 else TEX_IDLE
	else:
		_walk_clock = 0.0
		# Blinking belongs to the corrupted half.
		if corrupted:
			_blink_timer -= delta
			if _blink_timer < -0.12:
				_blink_timer = randf_range(1.5, 3.5)
			sprite.texture = TEX_BLINK if _blink_timer < 0.0 else TEX_IDLE
		else:
			sprite.texture = TEX_IDLE


func _update_glitch(delta: float) -> void:
	if not corrupted:
		return
	_glitch_clock -= delta
	if _glitch_clock <= 0.0:
		_glitch_clock = randf_range(0.05, 0.4)
		_glitch_amount = 1.0 if randf() < 0.55 else randf_range(0.0, 0.4)
		_glitch_color = GLITCH_PALETTE[randi() % GLITCH_PALETTE.size()]
		var mat := sprite.material as ShaderMaterial
		mat.set_shader_parameter("glitch", _glitch_amount)
		mat.set_shader_parameter("glitch_tint", _glitch_color)
		mat.set_shader_parameter("slice_seed", randf())
		# Past the seam the cube never holds its village color for long.
		var tint := GLITCH_PALETTE[randi() % GLITCH_PALETTE.size()] if randf() < 0.35 else base_color
		mat.set_shader_parameter("tint", tint)
		_set_dust_color(tint)


func _apply_colors() -> void:
	if not is_node_ready():
		return
	var mat := sprite.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("tint", base_color)
	mat.set_shader_parameter("glitch", 0.0)
	mat.set_shader_parameter("glitch_tint", base_color)
	_set_dust_color(base_color)


func _set_dust_color(body: Color) -> void:
	_walk_dust.color = Color(body.r, body.g, body.b, 0.9)
	_land_dust.color = Color(body.r, body.g, body.b, 1.0)
