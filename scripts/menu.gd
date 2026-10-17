extends Control

## Title screen. One player creates a room and reads out the code; the other types it in.
## The level only starts when both are connected. "Local test" (debug builds only) puts
## both cubes on one keyboard for development.

@onready var code_label: Label = %CodeLabel
@onready var code_input: LineEdit = %CodeInput
@onready var message: Label = %Message
@onready var create_button: Button = %CreateButton
@onready var join_button: Button = %JoinButton
@onready var local_button: Button = %LocalButton


func _ready() -> void:
	create_button.pressed.connect(_on_create)
	join_button.pressed.connect(_on_join)
	code_input.text_submitted.connect(func(_t: String) -> void: _on_join())
	local_button.pressed.connect(func() -> void: Net.start_local())
	local_button.visible = OS.is_debug_build()
	Net.join_failed.connect(_show_message)
	Net.session_closed.connect(_show_message)
	message.text = Net.last_message
	Net.last_message = ""
	code_label.text = ""
	_apply_command_line()


## Development shortcuts: `-- --host`, `-- --join=CODE`, `-- --local`, `-- --seed=N`.
func _apply_command_line() -> void:
	var seed_value := 0
	var action := ""
	var code := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_value = int(arg.trim_prefix("--seed="))
		elif arg == "--host" or arg == "--local":
			action = arg
		elif arg.begins_with("--join="):
			action = "--join"
			code = arg.trim_prefix("--join=")
	if Net.mode != Net.Mode.NONE or action.is_empty():
		return
	match action:
		"--local":
			Net.start_local(seed_value)
		"--host":
			_on_create()
			if seed_value != 0:
				Net.stage_seed = seed_value
		"--join":
			code_input.text = code
			_on_join()


func _on_create() -> void:
	var err := Net.host()
	if err != OK:
		_show_message("Could not open a room (port %d busy?)." % Net.PORT)
		return
	code_label.text = "Room code  %s" % Net.room_code
	message.text = "Waiting for your partner to join…"
	_set_buttons_enabled(false)


func _on_join() -> void:
	var code := code_input.text.strip_edges()
	if code.is_empty():
		_show_message("Type the room code your partner sees.")
		return
	var err := Net.join(code)
	if err != OK:
		_show_message("That code does not look right.")
		return
	message.text = "Joining…"
	_set_buttons_enabled(false)


func _show_message(text: String) -> void:
	message.text = text
	code_label.text = ""
	_set_buttons_enabled(true)


func _set_buttons_enabled(on: bool) -> void:
	create_button.disabled = not on
	join_button.disabled = not on
	code_input.editable = on
