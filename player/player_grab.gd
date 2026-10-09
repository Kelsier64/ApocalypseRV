extends Node
const GrabRules = preload("res://core/raker_grab_rules.gd")
## Transient control ownership. Physics remains in Player; no state is serialized.
signal changed(presses: int, required: int, remaining: float)
signal released(reason: String)
const ARM_GRIP_LEAD_TIME := .35
enum Mode { RAKER, EXECUTION }
var mode := Mode.RAKER
var execution_anchor: Node3D
var execution_look_target: Node3D
var execution_body_offset := Vector3.ZERO
var execution_finished := false
var execution_seat_rid: RID
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
var camera_target := Quaternion.IDENTITY
var camera_elapsed := 0.0
var seated_camera_rotation := Vector3.ZERO
var camera_rest_position := Vector3.ZERO
var camera_rest_near := .05
var bite_pull_offset := Vector3.ZERO
var bite_pull_ready := false
var keep_flashlight := false
var hud: CanvasLayer
var label: Label
var bar: ProgressBar
var threshold_mark: ColorRect
var impact: ColorRect
var impact_remaining := 0.0
var impact_strength := .78
var arm_grip_weight := 0.0
var recovery_camera: Camera3D
var recovery_rotation := Vector3.ZERO
var recovery_position := Vector3.ZERO
var recovery_start_rotation := Vector3.ZERO
var recovery_target_rotation := Vector3.ZERO
var recovery_target_position := Vector3.ZERO
var recovery_elapsed := 0.0
var recovery_anchor := Vector3.ZERO

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
	threshold_mark = ColorRect.new()
	threshold_mark.color = Color.ORANGE
	threshold_mark.position = Vector2(440.0 * GrabRules.WOUNDED_PERCENT / 100.0, 0)
	threshold_mark.size = Vector2(3, 24)
	track.add_child(threshold_mark)
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
	mode = Mode.RAKER
	clear_view_recovery()
	# Snapshot actual illumination before UI cleanup can reactivate a stowed light.
	var held := player.held_item_node as Flashlight
	keep_flashlight = held != null and held.get_node("Beam").is_visible_in_tree()
	player.grab_started.emit()
	if player.is_placing_equipment():
		player.cancel_equipment_placement()
	player.exit_ui_mode()
	captor = owner_node
	captor.tree_exiting.connect(_owner_exiting, CONNECT_ONE_SHOT)
	required = clampi(count, GrabRules.MIN_PRESSES, GrabRules.MAX_PRESSES)
	presses = 0
	remaining = GrabRules.HOLD_DURATION
	accepting = true
	space_down = Input.is_physical_key_pressed(KEY_SPACE)
	jump_release_required = space_down
	camera = player.seated_in.seat_camera if is_instance_valid(player.seated_in) else player.camera
	camera_start = camera.basis.get_rotation_quaternion()
	var direction: Vector3 = captor.grab_face_position() - camera.global_position
	var parent := camera.get_parent() as Node3D
	camera_target = camera_start
	if direction.length_squared() > .0001:
		camera_target = (parent.global_basis.inverse() * Basis.looking_at(direction.normalized(), Vector3.UP)).get_rotation_quaternion()
	seated_camera_rotation = camera.rotation
	camera_rest_position = camera.position
	camera_rest_near = camera.near
	camera.near = minf(camera.near, .012)
	camera_elapsed = 0
	arm_grip_weight = 0.0
	bite_pull_ready = false
	bite_pull_offset = Vector3.ZERO
	if is_instance_valid(player.held_item_node): player.held_item_node.show()
	player._advance_flashlight(0.0)
	hud.show()
	update_progress(remaining)
	return true

func can_begin_execution() -> bool:
	# Giant hands can reach crawling, roof-supported and climbing survivors.
	return not active() and immunity <= 0 and not player.is_player_dead

func begin_execution(owner_node: Node3D, anchor: Node3D, look_target: Node3D) -> bool:
	if not can_begin_execution() or not is_instance_valid(owner_node) or not is_instance_valid(anchor) or not is_instance_valid(look_target): return false
	if not WorldEntities.same_world(player, owner_node) or not WorldEntities.same_world(player, anchor) or not WorldEntities.same_world(player, look_target): return false
	# cast_motion ignores shapes overlapping the starting pose. Refuse that
	# invalid volume before releasing seat/ladder ownership, rather than
	# extracting a disabled seated capsule through an already-overlapping roof.
	if not _execution_volume_clear(owner_node, player.seated_in): return false
	clear_view_recovery()
	player.grab_started.emit()
	player.cancel_equipment_placement()
	player.exit_ui_mode()
	# Release the driver at the actual contact location. Ordinary seat exits
	# search/teleport to an aisle; that would bypass the giant's swept lift.
	if is_instance_valid(player.seated_in):
		var seat: Node3D = player.seated_in
		if not seat.has_method("release_for_execution") or not seat.release_for_execution(player): return false
		execution_seat_rid = seat.get_rid() if seat is CollisionObject3D else RID()
	player._exit_climb_to_normal()
	player.rv_support.clear()
	player.released_carrier_velocity = Vector3.ZERO
	player.velocity = Vector3.ZERO
	captor = owner_node
	mode = Mode.EXECUTION
	execution_anchor = anchor
	execution_look_target = look_target
	# The chest anchor moves the body without snapping the initial contact.
	execution_body_offset = player.global_position - anchor.global_position
	execution_finished = false
	captor.tree_exiting.connect(_owner_exiting, CONNECT_ONE_SHOT)
	accepting = false
	presses = 0
	required = 0
	remaining = 0.0
	keep_flashlight = false
	space_down = Input.is_physical_key_pressed(KEY_SPACE)
	jump_release_required = space_down
	camera = player.camera
	camera_rest_position = camera.position
	camera_rest_near = camera.near
	camera.near = minf(camera.near, .012)
	camera_elapsed = 0.0
	arm_grip_weight = 0.0
	camera.make_current()
	hud.hide()
	return true

func is_executing() -> bool:
	return active() and mode == Mode.EXECUTION

func advance_execution(_delta: float) -> void:
	if not is_executing(): return
	if not is_instance_valid(execution_anchor) or not is_instance_valid(execution_look_target) or not WorldEntities.same_world(player, execution_anchor) or not WorldEntities.same_world(player, execution_look_target):
		end("execution_anchor_removed")
		return
	if not _execution_volume_clear(captor):
		end("execution_path_blocked")
		return
	var motion: Vector3 = execution_anchor.global_position + execution_body_offset - player.global_position
	if motion.length_squared() > .000001:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = player.body_collision_shape.shape
		query.transform = player.global_transform * player.body_collision_shape.transform
		query.motion = motion
		query.margin = .001
		query.collision_mask = player.collision_mask
		var exclusions: Array[RID] = [player.get_rid()]
		if captor is CollisionObject3D: exclusions.append(captor.get_rid())
		if execution_seat_rid.is_valid(): exclusions.append(execution_seat_rid)
		query.exclude = exclusions
		var safe := player.get_world_3d().direct_space_state.cast_motion(query)
		player.global_position += motion * safe[0]
		if safe[0] < .999:
			end("execution_path_blocked")
			return
	player.velocity = Vector3.ZERO

func _execution_volume_clear(owner_node: Node3D, seat: Node3D = null) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = player.body_collision_shape.shape
	query.transform = player.global_transform * player.body_collision_shape.transform
	query.margin = 0.0
	query.collision_mask = player.collision_mask
	var exclusions: Array[RID] = [player.get_rid()]
	if owner_node is CollisionObject3D: exclusions.append(owner_node.get_rid())
	if seat is CollisionObject3D: exclusions.append(seat.get_rid())
	if execution_seat_rid.is_valid(): exclusions.append(execution_seat_rid)
	query.exclude = exclusions
	return player.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _owner_exiting() -> void:
	end("owner_removed")

func update_progress(seconds: float) -> void:
	remaining = maxf(0, seconds)
	label.text = "連按 SPACE 掙脫  %d / %d\n%.1f 秒  ·  %d%% 可避免致命咬擊" % [presses, required, remaining, GrabRules.WOUNDED_PERCENT]
	bar.value = 100.0 * presses / maxi(1, required)
	changed.emit(presses, required, remaining)

func submit_struggle() -> bool:
	if not active() or not accepting or remaining <= 0: return false
	presses += 1
	update_progress(remaining)
	if presses >= required: captor.grab.escape()
	return true

func _input(event: InputEvent) -> void:
	# Explicit playground-only controls stay usable during a one-second capture.
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
	if mode == Mode.EXECUTION: return
	_update_bite_pull(delta)

func _update_bite_pull(delta: float = 1.0 / 60.0) -> void:
	if not is_instance_valid(camera): return
	var parent := camera.get_parent() as Node3D
	var anchor := parent.to_global(camera_rest_position)
	var weight := 0.0
	# The monster can restrain the arm before biting, but the camera keeps its
	# face view until actual damage contact releases the survivor.
	var preparing_arm: bool = captor.grab.phase == captor.grab.Phase.HOLD and remaining <= ARM_GRIP_LEAD_TIME and player.body_state.has_part(&"left_arm") and GrabRules.reaches_wounded_threshold(presses, required)
	var arm_bite: bool = captor.grab.bite_part == &"left_arm" or preparing_arm
	arm_grip_weight = move_toward(arm_grip_weight, 1.0 if arm_bite else 0.0, delta / .18)
	if captor.grab.phase == captor.grab.Phase.BITE:
		if not bite_pull_ready:
			var toward: Vector3 = (captor.global_position-anchor).slide(Vector3.UP).normalized()
			var pull := toward * .18
			# A crouched captor pulls a standing head down too. The full-body
			# player's eyes are higher than the old capsule-only camera.
			if is_instance_valid(player.seated_in) or captor.get("crouched") == true:
				pull -= Vector3.UP * .17
			bite_pull_offset = parent.global_basis.inverse() * pull
			bite_pull_ready = true
		weight = preload("res://enemies/raker_pose_modifier.gd").bite_weight(captor.grab.elapsed)
		if captor.grab.bite_part == &"left_arm": weight *= .15
	# Hands pull the victim's head forward during the bite. Keep body/seat fixed,
	# and latch the direction once so camera/mouth solvers never chase each other.
	# Seat-local offset follows moving RVs; a sphere sweep prevents wall clipping.
	var motion := _safe_camera_motion(camera, parent.global_basis * bite_pull_offset * weight, captor)
	camera.position = parent.to_local(anchor + motion)

func _safe_camera_motion(view: Camera3D, motion: Vector3, owner_node: Node3D = null) -> Vector3:
	var parent := view.get_parent() as Node3D
	var anchor := parent.to_global(camera_rest_position)
	if motion.length_squared() > .000001:
		var shape := SphereShape3D.new()
		shape.radius = .09
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = Transform3D(Basis.IDENTITY, anchor)
		query.motion = motion
		query.collision_mask = 1
		query.exclude = [player.get_rid()]
		if is_instance_valid(owner_node): query.exclude.append(owner_node.get_rid())
		var safe := player.get_world_3d().direct_space_state.cast_motion(query)
		motion *= safe[0]
	return motion

func _process(delta: float) -> void:
	impact_remaining = maxf(0, impact_remaining - delta)
	impact.color.a = impact_strength * pow(impact_remaining / .22, 2)
	if not active() or not is_instance_valid(camera):
		_recover_view(delta)
		return
	camera_elapsed += delta
	if mode == Mode.EXECUTION:
		if is_instance_valid(execution_look_target):
			var direction := execution_look_target.global_position - camera.global_position
			if direction.length_squared() > .0001:
				camera.global_basis = Basis.looking_at(direction.normalized(), Vector3.UP)
		return
	# Lift toward the face once, then hold that parent-local view through bite.
	# Following the lunging mouth caused a downward whip at contact.
	camera.basis = Basis(camera_start.slerp(camera_target, clampf(camera_elapsed / .15, 0, 1)))

func bite_impact() -> void:
	# Brief crush flash survives fatal-grab cleanup, then clears independently.
	impact_remaining = .22
	impact_strength = .28 if active() and captor.grab.bite_part == &"left_arm" else .78

func end(reason: String = "cancelled") -> void:
	var previous := captor
	var was_execution := mode == Mode.EXECUTION
	var arm_release: bool = not was_execution and is_instance_valid(previous) and reason == "bitten" and previous.grab.bite_part == &"left_arm" and not player.is_player_dead
	var owned_view := is_instance_valid(camera) and camera.current
	captor = null
	execution_anchor = null
	execution_look_target = null
	execution_body_offset = Vector3.ZERO
	execution_seat_rid = RID()
	keep_flashlight = false
	accepting = false
	remaining = 0
	hud.hide()
	if is_instance_valid(previous):
		if previous.tree_exiting.is_connected(_owner_exiting): previous.tree_exiting.disconnect(_owner_exiting)
		immunity = 3.0
		jump_release_required = space_down
		if not was_execution and previous.grab.victim == player: previous.grab.cancel(reason)
	if is_instance_valid(player.held_item_node): player.held_item_node.show()
	# Arm framing is temporary; it must never become the controller's body yaw.
	# Other outcomes retain their existing final-view handoff.
	if is_instance_valid(camera):
		if arm_release:
			recovery_camera = camera
			recovery_rotation = camera.rotation - seated_camera_rotation
			for axis in 3: recovery_rotation[axis] = wrapf(recovery_rotation[axis], -PI, PI)
			recovery_start_rotation = recovery_rotation
			recovery_position = camera.position - camera_rest_position
			var parent := camera.get_parent() as Node3D
			var motion := _safe_camera_motion(camera, player.global_basis * Vector3(-.13, .06, .12), previous)
			recovery_target_position = parent.global_basis.inverse() * motion
			var eye := parent.to_global(camera_rest_position + recovery_target_position)
			var look := player.to_global(Vector3(-.34, 1.32, -.34)) - eye
			recovery_target_rotation = (parent.global_basis.inverse() * Basis.looking_at(look.normalized(), Vector3.UP)).get_euler() - seated_camera_rotation
			for axis in 3: recovery_target_rotation[axis] = recovery_rotation[axis] + wrapf(recovery_target_rotation[axis] - recovery_rotation[axis], -PI, PI)
			recovery_elapsed = 0.0
			recovery_anchor = player.global_position
		else:
			camera.position = camera_rest_position
		camera.near = camera_rest_near
	if is_instance_valid(camera) and camera == player.camera and not arm_release:
		var view := camera.global_basis.get_euler()
		player.global_rotation.y = view.y
		camera.rotation = Vector3(clampf(view.x, deg_to_rad(-80), deg_to_rad(80)), 0, 0)
	elif is_instance_valid(camera) and camera != player.camera and not arm_release:
		camera.rotation = seated_camera_rotation
	camera = null
	mode = Mode.RAKER
	# Release the real input path as well as the ownership flag. A visible
	# pointer (e.g. focus/UI changes during capture) otherwise leaves mouse look
	# gated even though GRABBED and its HUD have already disappeared.
	if owned_view and reason not in ["world_transition", "world_changed", "player_removed", "death"]:
		player.in_ui_mode = false
		player.set_physics_process(true)
		player.set_process_unhandled_input(not is_instance_valid(player.seated_in))
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	released.emit(reason)

func _recover_view(delta: float) -> void:
	if not is_instance_valid(recovery_camera): return
	if not recovery_camera.current or player.is_player_dead or player.is_crawling() or player.locomotion_state != player.LocomotionState.NORMAL or (not is_instance_valid(player.seated_in) and player.global_position.distance_to(recovery_anchor) > 2.0):
		clear_view_recovery()
		return
	# Input is already free. Only after contact, turn toward the torn arm, then
	# remove our offset. Apply deltas so new mouse input is never overwritten.
	var base_rotation := _limit_free_view(recovery_camera.rotation - recovery_rotation)
	recovery_elapsed += delta
	var turn := smoothstep(0.0, .16, recovery_elapsed)
	var after := 1.0 - smoothstep(.32, .85, recovery_elapsed)
	var offset := recovery_start_rotation.lerp(recovery_target_rotation, turn) * after
	recovery_camera.rotation = _limit_free_view(base_rotation + offset)
	recovery_rotation = recovery_camera.rotation - base_rotation
	var parent := recovery_camera.get_parent() as Node3D
	var motion := parent.global_basis * recovery_position.lerp(recovery_target_position, turn) * after
	recovery_camera.position = camera_rest_position + parent.global_basis.inverse() * _safe_camera_motion(recovery_camera, motion)
	if after <= 0.0: clear_view_recovery()

func _limit_free_view(rotation: Vector3) -> Vector3:
	rotation.x = clampf(rotation.x, deg_to_rad(-80), deg_to_rad(80))
	if recovery_camera != player.camera:
		rotation.y = clampf(rotation.y, deg_to_rad(-120), deg_to_rad(120))
	return rotation

func clear_view_recovery() -> void:
	if is_instance_valid(recovery_camera):
		recovery_camera.rotation = _limit_free_view(recovery_camera.rotation - recovery_rotation)
		recovery_camera.position = camera_rest_position
	recovery_camera = null
	recovery_rotation = Vector3.ZERO

func _exit_tree() -> void:
	if active(): end("player_removed")
