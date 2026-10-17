extends "res://tests/run_tests.gd"

## Renders one screenshot per room (and a few story beats) into the folder given as the
## first user argument. Needs a display: run under xvfb-run with a GL driver.

func _initialize() -> void:
	net = root.get_node("Net")
	main_scene = load("res://scenes/main.tscn")
	var out: String = OS.get_cmdline_user_args()[0]
	for room in Tuning.ROOM_COUNT:
		await fresh(room, 3)
		if room >= 5:
			main._apply_event("checkpoint", [5])
		main.checkpoint = room
		var r: StageGenerator.Room = stage.rooms[room]
		place(r.spawns[0], r.spawns[1])
		main.camera.global_position = stage.room_center(room)
		await frames(90)
		await _shot(out + "/room_%d.png" % (room + 1))
	# The witness beat in room 4.
	await fresh(3, 3)
	place(spot(3, 25.0, 7.0), spot(3, 26.3, 7.0))
	main.camera.global_position = stage.room_center(3)
	await frames(75)
	await _shot(out + "/witness_fall.png")
	await frames(60)
	await _shot(out + "/witness.png")
	# A swing in room 3.
	await fresh(2, 3)
	var near := _gap_near(2)
	place(spot(2, near + 2.45, 6.0), spot(2, near + 4.2, 3.0))
	main.camera.global_position = stage.room_center(2)
	await frames(60)
	await _shot(out + "/swing.png")
	quit()


func _shot(path: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("saved ", path)
