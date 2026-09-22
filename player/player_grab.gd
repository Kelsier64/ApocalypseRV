extends Node
## Transient control ownership. Physics remains in Player; no state is serialized.
signal changed(presses: int, required: int, remaining: float)
signal released(reason: String)
var player: CharacterBody3D
var captor: Node3D
var required := 0
var presses := 0
var remaining := 0.0
var immunity := 0.0
var accepting := false
var space_down := false
var jump_release_required := false
var camera: Camera3D
var camera_start := Quaternion.IDENTITY
var camera_elapsed := 0.0
var seated_camera_rotation := Vector3.ZERO
var camera_rest_position := Vector3.ZERO
var hud: CanvasLayer
var label: Label
var bar: ProgressBar
var impact: ColorRect
var impact_remaining := 0.0

func _ready() -> void:
	player = get_parent()
	hud = CanvasLayer.new()
	hud.layer = 30
	add_child(hud)
	var screen := Control.new()
	hud.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(440, 0)
	screen.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	panel.offset_left = -220
	panel.offset_right = 220
	panel.offset_top = -250
	panel.offset_bottom = -140
	label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 24)
	panel.add_child(label)
	var track := Control.new()
	track.custom_minimum_size = Vector2(440, 24)
	panel.add_child(track)
	bar = ProgressBar.new()
	bar.show_percentage = false
	track.add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mark := ColorRect.new()
	mark.color = Color.ORANGE
	mark.position = Vector2(352, 0)
	mark.size = Vector2(3, 24)
	track.add_child(mark)
	var impact_layer := CanvasLayer.new()
	impact_layer.layer = 29
	add_child(impact_layer)
	impact = ColorRect.new()
	impact_layer.add_child(impact)
	impact.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	impact.mouse_filter = Control.MOUSE_FILTER_IGNORE
	impact.color = Color(.22, .008, .003, 0)
	hud.hide()

func active() -> bool:
	return is_instance_valid(captor)

func can_begin() -> bool:
	return not active() and immunity <= 0 and not player.is_player_dead and player.locomotion_state == player.LocomotionState.NORMAL

func begin(owner_node: Node3D, count: int) -> bool:
	if not can_begin() or not is_instance_valid(owner_node): return false
	player.grab_started.emit()
	if player.is_placing_equipment():
		player.placement.placing_equipment.cancel_placement()
		player.placement.placing_equipment = null
		player.placement._clear_marker()
	player.exit_ui_mode()
	captor = owner_node
	captor.tree_exiting.connect(_owner_exiting, CONNECT_ONE_SHOT)
	required = clampi(count, 6, 10)
	presses = 0
	remaining = 2.0
	accepting = true
	space_down = Input.is_physical_key_pressed(KEY_SPACE)
	jump_release_required = space_down
	camera = player.seated_in.seat_camera if is_instance_valid(player.seated_in) else player.camera
	camera_start = camera.global_basis.get_rotation_quaternion()
	seated_camera_rotation = camera.rotation
	camera_rest_position = camera.position
	camera_elapsed = 0
	if is_instance_valid(player.held_item_node): player.held_item_node.hide()
	hud.show()
	update_progress(remaining)
	return true

func _owner_exiting() -> void:
	end("owner_removed")

func update_progress(seconds: float) -> void:
	remaining = maxf(0, seconds)
	label.text = "連按 SPACE 掙脫  %d / %d\n%.1f 秒  ·  80%% 可避免致命咬擊" % [presses, required, remaining]
	bar.value = 100.0 * presses / maxi(1, required)
	changed.emit(presses, required, remaining)

func submit_struggle() -> bool:
	if not active() or not accepting or remaining <= 0: return false
	presses += 1
	update_progress(remaining)
	if presses >= required: captor.grab.escape()
	return true

func _input(event: InputEvent) -> void:
	# Explicit playground-only controls stay usable during a two-second capture.
	var playground := get_tree().current_scene
	if active() and is_instance_valid(playground) and playground.has_method("setup_grab") and event is InputEventKey and event.pressed and not event.echo and (event.keycode in [KEY_F7, KEY_F11, KEY_F12] or (event.keycode == KEY_F9 and "--bite-review" in OS.get_cmdline_user_args())):
		playground._input(event)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and (event.physical_keycode == KEY_SPACE or event.keycode == KEY_SPACE):
		if not event.pressed:
			space_down = false
			jump_release_required = false
		elif not event.echo and not space_down:
			space_down = true
			if active():
				jump_release_required = true
				submit_struggle()
		# Consume the successful final press too: no jump or handbrake on release.
		if active() or jump_release_required:
			get_viewport().set_input_as_handled()
	if active(): get_viewport().set_input_as_handled()

func _physics_process(delta: float) -> void:
	immunity = maxf(0, immunity - delta)
	if not active(): return
	if captor.is_queued_for_deletion() or not WorldEntities.same_world(player, captor):
		end("world_changed")
		return
	_update_bite_pull()

func _update_bite_pull() -> void:
	if not is_instance_valid(camera): return
	var parent := camera.get_parent() as Node3D
	var anchor := parent.to_global(camera_rest_position)
	var weight := 0.0
	if captor.grab.phase == captor.grab.Phase.BITE:
		weight = preload("res://enemies/raker_pose_modifier.gd").bite_weight(captor.grab.elapsed)
	var mouth: Vector3 = captor.get_node("BodyMesh").bone_world_position("mouth")
	var toward := mouth - anchor
	# Hands pull the victim's head forward during the bite. Keep body/seat fixed,
	# limit head travel to 28 cm, and sweep a head-sized volume against walls.
	var motion := toward.normalized() * clampf(toward.length() - .10, 0, .28) * weight
	if motion.length_squared() > .000001:
		var shape := SphereShape3D.new()
		shape.radius = .09
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = Transform3D(Basis.IDENTITY, anchor)
		query.motion = motion
		query.collision_mask = 1
		query.exclude = [player.get_rid(), captor.get_rid()]
		var safe := player.get_world_3d().direct_space_state.cast_motion(query)
		motion *= safe[0]
	camera.position = parent.to_local(anchor + motion)

func _process(delta: float) -> void:
	impact_remaining = maxf(0, impact_remaining - delta)
	impact.color.a = .78 * pow(impact_remaining / .22, 2)
	if not active() or not is_instance_valid(camera): return
	camera_elapsed += delta
	var direction: Vector3 = captor.grab_face_position() - camera.global_position
	if direction.length_squared() < .0001: return
	var target := Basis.looking_at(direction.normalized(), Vector3.UP).get_rotation_quaternion()
	camera.global_basis = Basis(camera_start.slerp(target, clampf(camera_elapsed / .15, 0, 1)))
	if captor.grab.phase == captor.grab.Phase.BITE:
		var time: float = captor.grab.elapsed
		var snap := smoothstep(.29, .37, time) * (1.0 - smoothstep(.38, .52, time))
		camera.rotate_object_local(Vector3.RIGHT, deg_to_rad(-5) * snap)
		camera.rotate_object_local(Vector3.BACK, deg_to_rad(3) * snap)

func bite_impact() -> void:
	# Brief crush flash survives fatal-grab cleanup, then clears independently.
	impact_remaining = .22

func end(reason: String = "cancelled") -> void:
	var previous := captor
	captor = null
	accepting = false
	remaining = 0
	hud.hide()
	if is_instance_valid(previous):
		if previous.tree_exiting.is_connected(_owner_exiting): previous.tree_exiting.disconnect(_owner_exiting)
		immunity = 3.0
		jump_release_required = space_down
		if previous.grab.victim == player: previous.grab.cancel(reason)
	if is_instance_valid(player.held_item_node): player.held_item_node.show()
	# Keep the final viewing direction; restore ordinary yaw/pitch ownership.
	if is_instance_valid(camera): camera.position = camera_rest_position
	if is_instance_valid(camera) and camera == player.camera:
		var view := camera.global_basis.get_euler()
		player.global_rotation.y = view.y
		camera.rotation = Vector3(clampf(view.x, deg_to_rad(-80), deg_to_rad(80)), 0, 0)
	elif is_instance_valid(camera):
		camera.rotation = seated_camera_rotation
	camera = null
	released.emit(reason)

func _exit_tree() -> void:
	if active(): end("player_removed")
