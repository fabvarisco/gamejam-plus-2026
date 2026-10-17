extends Node

## One player's input in online play. The owning peer reads its keyboard before each
## netfox tick loop; netfox records these fields every tick, sends them to the host and
## replays them when it rewinds. Every input is held (jump edges are found by the cube),
## so reading once per loop is enough.

## The fields, as netfox property paths relative to the cube.
const PROPERTIES: Array[String] = ["Input:axis", "Input:jump", "Input:climb"]

var axis: float = 0.0
var jump: bool = false
var climb: bool = false
## Set by the network check: [axis, jump, climb] to send instead of the keyboard.
var scripted: Array = []


func _ready() -> void:
	NetworkTime.before_tick_loop.connect(_gather)


func _exit_tree() -> void:
	if NetworkTime.before_tick_loop.is_connected(_gather):
		NetworkTime.before_tick_loop.disconnect(_gather)


func _gather() -> void:
	if not is_multiplayer_authority():
		return
	if not scripted.is_empty():
		axis = scripted[0]
		jump = scripted[1]
		climb = scripted[2]
		return
	axis = Input.get_axis("move_left", "move_right")
	jump = Input.is_action_pressed("jump")
	climb = Input.is_action_pressed("climb")
