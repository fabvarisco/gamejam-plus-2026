extends "res://tests/run_tests.gd"

## Renders one screenshot per room (and a few story beats) into the folder given as the
## first user argument. Needs a display: run under xvfb-run with a GL driver.

func _initialize() -> void:
	net = root.get_node("Net")
	main_scene = load("res://scenes/main.tscn")
	var out: String = OS.get_cmdline_user_args()[0]
	for room in Tuning.ROOM_COUNT:
		await fresh(room, 3)
		if room >= SEAM:
			main._apply_event("checkpoint", [SEAM])
		main.checkpoint = room
		var r: StageGenerator.Room = stage.rooms[room]
		place(r.spawns[0], r.spawns[1])
		main.camera.global_position = stage.room_center(room)
		await frames(90)
		await _shot(out + "/room_%d.png" % (room + 1))
	# The witness beat at the camp.
	await fresh(CAMP, 3)
	place(spot(CAMP, 25.0, 7.0), spot(CAMP, 26.3, 7.0))
	main.camera.global_position = stage.room_center(CAMP)
	await frames(75)
	await _shot(out + "/witness_fall.png")
	await frames(60)
	await _shot(out + "/witness.png")
	# A swing over the gorge.
	await fresh(GORGE, 3)
	var near := _gap_near(GORGE)
	place(spot(GORGE, near + 2.45, 6.0), spot(GORGE, near + 4.2, 3.0))
	main.camera.global_position = stage.room_center(GORGE)
	await frames(60)
	await _shot(out + "/swing.png")
	quit()


func _shot(path: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("saved ", path)
