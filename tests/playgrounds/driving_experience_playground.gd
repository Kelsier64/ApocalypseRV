extends "res://tests/playgrounds/rv_rebuild_playground.gd"
## Production seat and mirrors with asymmetric rear obstacles for orientation QA.
func _ready() -> void:
	super._ready()
	get_window().title = "ApocalypseRV - Driving Experience"
	for side in [-1.0, 1.0]:
		RoadsideKit.part(self, Vector3(0.8, 1.5, 0.8), Vector3(side * 3.5, 0.75, 8), Color("d84028") if side < 0 else Color("238bec"))
	# Fixed equipment attaches to the RV a few frames after load; seat only then.
	for i in range(Engine.physics_ticks_per_second * 2):
		if seat.can_operate(): break
		await get_tree().physics_frame
	seat.interact_hold(player)
	if not rv.is_player_driving: push_warning("Driving playground could not seat the player")
	view = 2
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if "--mirror-capture" in OS.get_cmdline_user_args(): _capture_mirrors()

## Renders the seated rest view, the view turned to the cabin mirror, a close-up and
## the mirror's own render target, then quits.
func _capture_mirrors() -> void:
	var folder := "res://.godot/driving-mirror-captures"
	DirAccess.make_dir_recursive_absolute(folder)
	instructions.get_parent().visible = false
	var mirror: Dictionary = rv.get_node("Mirrors").mirror_for("front")
	var face: MeshInstance3D = mirror.face
	for shot: String in ["seat_rest", "seat_mirror", "close"]:
		seat.seat_camera.rotation = seat.REST_CAMERA_ROTATION
		seat.seat_camera.current = true
		if shot == "seat_mirror": seat.seat_camera.look_at(face.global_position, rv.global_basis.y)
		if shot == "close":
			view = 5
			observer.current = true
			observer.global_position = seat.seat_camera.global_position.lerp(face.global_position, 0.6)
			observer.look_at(face.global_position, rv.global_basis.y)
		for i in range(30): await get_tree().process_frame
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var path := folder + "/" + shot + ".png"
		get_viewport().get_texture().get_image().save_png(path)
		print("CAPTURE: ", ProjectSettings.globalize_path(path))
		view = 2
	var viewport: SubViewport = mirror.viewport
	var target := folder + "/mirror_target.png"
	viewport.get_texture().get_image().save_png(target)
	print("CAPTURE: ", ProjectSettings.globalize_path(target), " visible=", mirror.rig.is_visible_in_tree(), " driving=", rv.is_player_driving, " camera=", get_viewport().get_camera_3d().get_path())
	get_tree().quit()

func _process(delta: float) -> void:
	super._process(delta)
	instructions.text = "DRIVING EXPERIENCE | F5 cabin mirror | F6 left mirror | F7 right mirror | F1 road | Backspace break/rebuild front wall\nF8 engine hatch (E) | F9 ramp | F11 night | F12 wheel replay | Lighting: service console\n" + result

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F5, KEY_F6, KEY_F7:
				seat.interact_hold(player)
				seat.seat_camera.current = true
				var slot: String = {KEY_F5: "front", KEY_F6: "left_0", KEY_F7: "right_0"}[event.keycode]
				var mirror: Dictionary = rv.get_node("Mirrors").mirror_for(slot)
				var lift := 0.0 if event.keycode == KEY_F5 else 0.3
				seat.seat_camera.look_at(mirror.face.global_position + rv.global_basis.y * lift, rv.global_basis.y)
				return
			KEY_BACKSPACE:
				# Break or rebuild the front wall that carries the cabin mirror.
				var slots: RVStructureSlots = rv.get_node("StructureSlots")
				var front: RVStructurePanel = slots.occupant("front")
				if front != null and front.can_operate(): front.take_damage(1e9)
				else: slots.replace_panel("front", "rv_wall_front", 1e9)
				return
			KEY_F1:
				seat.interact_hold(player)
				seat.seat_camera.rotation = seat.REST_CAMERA_ROTATION
				seat.seat_camera.current = true
				return
			KEY_F11:
				rv.interior_requested.service = true
	super._unhandled_input(event)
