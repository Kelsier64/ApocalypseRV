extends "res://tests/rv_rebuild_playground.gd"
## Production seat and mirrors with asymmetric rear obstacles for orientation QA.
func _ready() -> void:
	super._ready()
	get_window().title = "ApocalypseRV - Driving Experience"
	for side in [-1.0, 1.0]:
		var block := RoadsideKit.part(self, Vector3(0.8, 1.5, 0.8), Vector3(side * 3.5, 0.75, 8), Color("d84028") if side < 0 else Color("238bec"))
		var label := Label3D.new()
		label.text = "LEFT / L" if side < 0 else "RIGHT / R"
		label.font_size = 96
		label.position = block.position + Vector3(0, 1.25, 0)
		label.rotation.y = PI
		add_child(label)
	await get_tree().physics_frame
	seat.interact_hold(player)
	view = 2
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _process(delta: float) -> void:
	super._process(delta)
	instructions.text = "DRIVING EXPERIENCE | F6 left mirror | F7 right mirror | F1 road\nF8 engine hatch (E) | F9 ramp | F11 night | F12 wheel replay | Lighting: service console\n" + result

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F6, KEY_F7:
				seat.interact_hold(player)
				seat.seat_camera.current = true
				var mirror: Node3D = rv.get_node("Mirrors").mirrors[0 if event.keycode == KEY_F6 else 1].rig
				seat.seat_camera.look_at(mirror.global_position + rv.global_basis.y * 0.3, rv.global_basis.y)
				return
			KEY_F1:
				seat.interact_hold(player)
				seat.seat_camera.rotation = seat.REST_CAMERA_ROTATION
				seat.seat_camera.current = true
				return
			KEY_F11:
				rv.interior_requested.work = true
				rv.interior_requested.service = true
	super._unhandled_input(event)
