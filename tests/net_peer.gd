extends Node

## One side of a two-process network check. Start a host, then a client:
##   godot --headless --path . res://tests/net_peer.tscn -- host
##   godot --headless --path . res://tests/net_peer.tscn -- client
## Each presses "right" on its own cube once the climb starts and reports what it sees.
## The driver moves itself under the root so it survives the switch into the climb.

var role: String


func _ready() -> void:
	role = OS.get_cmdline_user_args()[0]
	_run.call_deferred()


func _run() -> void:
	var tree := get_tree()
	get_parent().remove_child(self)
	tree.root.add_child(self)
	if role.begins_with("host"):
		Net.host()
		Net.stage_seed = 77
		print("[host] code ", Net.room_code, " decodes to ", Net.decode_code(Net.room_code))
	else:
		await tree.create_timer(0.5).timeout
		print("[client] join error ", Net.join("127.0.0.1"))
	var main: Node = null
	for i in 900:
		await tree.process_frame
		main = tree.current_scene
		if main != null and main.name == "Main" and main.is_node_ready():
			break
	if main == null or main.name != "Main":
		print("[%s] FAIL: never entered the climb" % role)
		tree.quit(1)
		return
	main.test_mode = true
	main.test_inputs[0] = [0.0, false, false]
	if role == "host_watch":
		# Report the pause state while a partner leaves and another one joins.
		for i in 14:
			await tree.create_timer(1.0).timeout
			main = tree.current_scene
			print("[host] t=%d waiting=%s partner=%s" % [i, main.waiting_for_partner, Net.partner_present])
		tree.quit()
		return
	if role == "client_quick":
		await tree.create_timer(2.0).timeout
		print("[client] leaving")
		tree.quit()
		return
	await tree.create_timer(1.0).timeout
	var start1: Vector2 = main.player_1.global_position
	var start2: Vector2 = main.player_2.global_position
	main.test_inputs[0] = [1.0, false, false]
	await tree.create_timer(1.5).timeout
	var d1: float = main.player_1.global_position.x - start1.x
	var d2: float = main.player_2.global_position.x - start2.x
	print("[%s] waiting=%s sim_time=%.2f p1 moved %.0f px, p2 moved %.0f px, seed %d" % [role, main.waiting_for_partner, main.sim_time, d1, d2, Net.stage_seed])
	await tree.create_timer(1.0).timeout
	tree.quit()
