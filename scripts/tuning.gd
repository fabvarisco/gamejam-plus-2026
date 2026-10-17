class_name Tuning
extends RefCounted

## Every distance in the GDD is measured in cubes. These numbers keep the rules readable:
## a 1-cube step or gap is solo, a 2-cube lip or gap needs the rope, and the elastic rope
## never stretches across a 4-cube gap.

const CUBE := 32.0
const GRAVITY := 2400.0

# Movement: a solo jump rises 1.25 cubes and covers well under 1 cube of horizontal gap.
const WALK_SPEED := 4.0 * CUBE
const AIR_SPEED := 2.0 * CUBE
const GROUND_ACCEL := 2400.0
const AIR_ACCEL := 420.0
const JUMP_VELOCITY := 438.0
const JUMP_CUT := 0.45
const COYOTE_TIME := 0.08
const JUMP_BUFFER := 0.1
const MAX_FALL_SPEED := 900.0
const MANTLE_HEIGHT := 0.3 * CUBE

# Rope: rest length of three cubes, elastic past it, with no hard maximum.
const ROPE_REST := 3.0 * CUBE
const ROPE_SLACK_DEADZONE := 1.5
const ROPE_K_LINEAR := 100.0
const ROPE_K_QUADRATIC := 8.0
const ROPE_DAMPING := 8.0
const ROPE_TERRAIN_FRICTION := 0.5
const ANCHOR_GRIP := 3200.0
const CLIMB_SPEED := 2.6 * CUBE
const SWING_MIN_TENSION := 300.0
const SWING_PUMP := 900.0
const SWING_MAX_SPEED := 720.0

# Layout.
const ROOM_W := 30
const ROOM_H := 10
const ROOM_PITCH := 11
const ROOM_COUNT := 13
