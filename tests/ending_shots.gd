extends "res://tests/screenshots.gd"

func _initialize() -> void:
	net = root.get_node("Net")
	main_scene = load("res://scenes/main.tscn")
	var out: String = OS.get_cmdline_user_args()[0]
	await fresh(EDGE - 1, 3)
	main._apply_event("checkpoint", [SEAM])
	main._apply_event("checkpoint", [EDGE])
	main._place_at_checkpoint()
	main.camera.global_position = stage.room_center(EDGE)
	await frames(80)
	var t := 0
	var shots := {60: "ending_walk", 320: "ending_moon", 430: "ending_moon_gone", 470: "ending_floor_fails", 540: "ending_fall", 640: "ending_falling", 760: "ending_past_witness", 860: "ending_fade"}
	while t < 880:
		inp(0, -fwd(EDGE))
		inp(1, -fwd(EDGE))
		await physics_frame
		t += 1
		if shots.has(t):
			await _shot(out + "/%s.png" % shots[t])
	var menu: Node = load("res://scenes/menu.tscn").instantiate()
	main.queue_free()
	root.add_child(menu)
	await frames(10)
	await _shot(out + "/menu.png")
	quit()
