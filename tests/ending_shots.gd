extends "res://tests/screenshots.gd"

func _initialize() -> void:
	net = root.get_node("Net")
	main_scene = load("res://scenes/main.tscn")
	var out: String = OS.get_cmdline_user_args()[0]
	await fresh(6, 3)
	main._apply_event("checkpoint", [5])
	main._apply_event("checkpoint", [7])
	main._place_at_checkpoint()
	main.camera.global_position = stage.room_center(7)
	await frames(80)
	var t := 0
	var shots := {60: "ending_walk", 320: "ending_moon", 430: "ending_moon_gone", 470: "ending_floor_fails", 540: "ending_fall", 600: "ending_past_witness", 700: "ending_fade"}
	while t < 720:
		inp(0, -1.0)
		inp(1, -1.0)
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
