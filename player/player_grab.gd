extends Node
const GrabRules = preload("res://core/raker_grab_rules.gd")
## Transient control ownership. Physics remains in Player; no state is serialized.
signal changed(presses: int, required: int, remaining: float)
signal released(reason: String)
const ARM_GRIP_LEAD_TIME := .35
const EXECUTION_VIEW_SPEED := 60.0
const EXECUTION_VIEW_PITCH_LIMIT := 60.0
const EXECUTION_VIEW_DELAY := .2
const EXECUTION_VIEW_EASE_SECONDS := .6
const EXECUTION_LOOK_YAW_LIMIT := 25.0
const EXECUTION_LOOK_PITCH_LIMIT := 18.0
const PlayerVisual = preload("res://player/player_model_visual.gd")
# Jolt and live suspension can establish tiny floor or side resting contacts.
# Recovery follows their normals, is bounded, and checks the complete volume.
const EXECUTION_CONTACT_DEPTH := .005
const EXECUTION_CONTACT_CLEARANCE := .001
const EXECUTION_CONTACT_LIMIT := 32
const EXECUTION_WALL_CLEARANCE_LIMIT := .05
enum Mode { RAKER, EXECUTION }
var mode := Mode.RAKER
var execution_anchor: Node3D
var execution_look_target: Node3D
var execution_body_offset := Vector3.ZERO
var execution_wall_clearance := Vector3.ZERO
var execution_wall_clearance_distance := 0.0
var execution_finished := false
var execution_guided_basis := Basis.IDENTITY
var execution_look_offset := Vector2.ZERO
var execution_observer: Camera3D
var execution_death_view := false
var execution_death_offset := Vector3.ZERO
var execution_death_focus := Vector3.ZERO
var execution_seat_rid: RID
var execution_seat: CollisionObject3D
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
var camera_rest_fov := 75.0
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
	camera_rest_fov = camera.fov
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
	if not _ensure_execution_volume_clear(owner_node, player.seated_in): return false
	var initial_view: Basis = player.camera.global_basis
	if is_instance_valid(player.seated_in):
		var seat_view := player.seated_in.get("seat_camera") as Camera3D
		if is_instance_valid(seat_view) and seat_view.current: initial_view = seat_view.global_basis
	clear_view_recovery()
	player.grab_started.emit()
	player.cancel_equipment_placement()
	player.exit_ui_mode()
	# Release the driver at the actual contact location. Ordinary seat exits
	# search/teleport to an aisle; that would bypass the giant's swept lift.
	if is_instance_valid(player.seated_in):
		var seat: Node3D = player.seated_in
		# The occupied seat owns its back/cushion/console shapes. Capture that
		# body's identity before releasing the driver; never exclude the RV.
		var seat_body := seat as CollisionObject3D
		var seat_rid := seat_body.get_rid() if is_instance_valid(seat_body) else RID()
		if not seat.has_method("release_for_execution") or not seat.release_for_execution(player): return false
		execution_seat = seat_body if is_instance_valid(seat_body) else null
		execution_seat_rid = seat_rid if is_instance_valid(execution_seat) else RID()
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
	execution_wall_clearance = Vector3.ZERO
	execution_wall_clearance_distance = 0.0
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
	camera.global_basis = initial_view
	execution_guided_basis = initial_view
	execution_look_offset = Vector2.ZERO
	camera_rest_position = camera.position
	camera_rest_near = camera.near
	camera_rest_fov = camera.fov
	camera.near = minf(camera.near, .012)
	camera_elapsed = 0.0
	arm_grip_weight = 0.0
	camera.make_current()
	_try_start_execution_observer()
	hud.hide()
	return true

func is_executing() -> bool:
	return active() and mode == Mode.EXECUTION

func advance_execution(_delta: float) -> void:
	if not is_executing(): return
	if not is_instance_valid(execution_anchor) or not is_instance_valid(execution_look_target) or not WorldEntities.same_world(player, execution_anchor) or not WorldEntities.same_world(player, execution_look_target):
		end("execution_anchor_removed")
		return
	var before_recovery := player.global_position
	if not _ensure_execution_volume_clear(captor):
		end("execution_path_blocked")
		return
	execution_body_offset += player.global_position - before_recovery
	var motion: Vector3 = execution_anchor.global_position + execution_body_offset - player.global_position
	if motion.length_squared() > .000001:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = player.body_collision_shape.shape
		query.transform = player.global_transform * player.body_collision_shape.transform
		query.motion = motion
		query.margin = 0.0
		query.collision_mask = player.collision_mask
		var exclusions: Array[RID] = [player.get_rid()]
		if captor is CollisionObject3D: exclusions.append(captor.get_rid())
		var seat_exclusion := _execution_seat_exclusion()
		if seat_exclusion.is_valid(): exclusions.append(seat_exclusion)
		query.exclude = exclusions
		var safe := player.get_world_3d().direct_space_state.cast_motion(query)
		if safe[0] < .999:
			var clearance := _execution_lift_wall_clearance(motion, safe)
			if clearance != Vector3.INF:
				player.global_position += clearance
				execution_body_offset += clearance
				execution_wall_clearance += clearance
				execution_wall_clearance_distance += clearance.length()
				query.transform = player.global_transform * player.body_collision_shape.transform
				safe = player.get_world_3d().direct_space_state.cast_motion(query)
		player.global_position += motion * safe[0]
		if safe[0] < .999:
			end("execution_path_blocked")
			return
	player.velocity = Vector3.ZERO

func _execution_lift_wall_clearance(motion: Vector3, safe: PackedFloat32Array) -> Vector3:
	# A rolled side wall can lean into an otherwise clear vertical capture
	# column. Move the complete body a few millimetres inward, only when both
	# that lateral move and the subsequent lift clear every actual solid.
	if not captor is SlenderSpeaker or captor.phase != SlenderSpeaker.Phase.LIFT or motion.y <= 0.0:
		return Vector3.INF
	var space := player.get_world_3d().direct_space_state
	var contact_query := _execution_shape_query(captor)
	contact_query.transform.origin += motion * minf(1.0, safe[1] + .005)
	var hit := space.get_rest_info(contact_query)
	if hit.is_empty(): return Vector3.INF
	var collider := instance_from_id(int(hit.collider_id)) as RVStructurePanel
	if collider == null or collider.is_destroyed or collider.structure_kind != "side" \
		or RVConnection.resolve(collider) != captor.target_vehicle:
		return Vector3.INF
	var normal: Vector3 = hit.normal
	if absf(normal.y) > .2: return Vector3.INF
	normal = normal.slide(Vector3.UP).normalized()
	for distance in [.005, .01, .02, .03, .04, .05]:
		var clearance: Vector3 = normal * distance
		if execution_wall_clearance_distance + clearance.length() > EXECUTION_WALL_CLEARANCE_LIMIT: continue
		var query := _execution_shape_query(captor)
		query.motion = clearance
		if space.cast_motion(query)[0] < .999: continue
		query.transform.origin += clearance
		query.motion = Vector3.ZERO
		if not space.intersect_shape(query, 1).is_empty(): continue
		query.motion = motion
		if space.cast_motion(query)[0] >= .999: return clearance
	return Vector3.INF

func _execution_volume_clear(owner_node: Node3D, seat: Node3D = null) -> bool:
	return player.get_world_3d().direct_space_state.intersect_shape(_execution_shape_query(owner_node, seat), 1).is_empty()

func _ensure_execution_volume_clear(owner_node: Node3D, seat: Node3D = null) -> bool:
	var query := _execution_shape_query(owner_node, seat)
	var space := player.get_world_3d().direct_space_state
	if space.intersect_shape(query, 1).is_empty(): return true
	# Disabled seated/climbing shapes cannot use ordinary resting-contact recovery to
	# extract a capsule already embedded in the vehicle shell.
	if player.body_collision_shape.disabled: return false
	# At world-scale coordinates Jolt can return a real resting contact whose
	# two points differ by less than one float ULP. Computing its normal from
	# that delta rejects a valid contact as zero-depth or sideways. A small query
	# margin gives each contact a measurable separation; remove that margin
	# from the allowed physical penetration rather than increasing tolerance.
	query.margin = EXECUTION_CONTACT_CLEARANCE
	var contacts := space.collide_shape(query, EXECUTION_CONTACT_LIMIT)
	if contacts.is_empty() or contacts.size() >= EXECUTION_CONTACT_LIMIT * 2: return false
	var recovery := Vector3.ZERO
	for index in range(0, contacts.size(), 2):
		# collide_shape returns the query point followed by the obstacle point.
		var separation: Vector3 = contacts[index + 1] - contacts[index]
		var depth := separation.length()
		var normal := separation.normalized()
		if depth <= .000001 or depth > EXECUTION_CONTACT_DEPTH + query.margin: return false
		# Live suspension also moves a wall or console against a resting body.
		# Resolve only this bounded starting contact along its actual normal;
		# a later swept hit still cancels, so this cannot extract through solids.
		recovery += normal * maxf(0.0, depth - normal.dot(recovery))
	if recovery.length() > EXECUTION_CONTACT_DEPTH + EXECUTION_CONTACT_CLEARANCE: return false
	query.margin = 0.0
	query.motion = recovery
	# Starting contacts are known and shallow. The swept recovery must
	# still stop at every other shape, including another shape of the Chassis.
	var safe := space.cast_motion(query)
	if safe[0] < .999: return false
	query.transform.origin += query.motion
	query.motion = Vector3.ZERO
	if not space.intersect_shape(query, 1).is_empty(): return false
	player.global_position += recovery
	return true

func _execution_shape_query(owner_node: Node3D, seat: Node3D = null) -> PhysicsShapeQueryParameters3D:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = player.body_collision_shape.shape
	query.transform = player.global_transform * player.body_collision_shape.transform
	query.margin = 0.0
	query.collision_mask = player.collision_mask
	var exclusions: Array[RID] = [player.get_rid()]
	if owner_node is CollisionObject3D: exclusions.append(owner_node.get_rid())
	if seat is CollisionObject3D: exclusions.append(seat.get_rid())
	var seat_exclusion := _execution_seat_exclusion()
	if seat_exclusion.is_valid(): exclusions.append(seat_exclusion)
	query.exclude = exclusions
	return query

func _execution_seat_exclusion() -> RID:
	if not is_instance_valid(execution_seat) or execution_seat.is_queued_for_deletion() \
			or not WorldEntities.same_world(player, execution_seat):
		execution_seat = null
		execution_seat_rid = RID()
	return execution_seat_rid

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
	if is_executing() and event is InputEventMouseMotion:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			_execution_mouse_look(event)
		get_viewport().set_input_as_handled()
		return
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

func _execution_mouse_look(event: InputEventMouseMotion) -> void:
	var view := execution_observer if is_instance_valid(execution_observer) else camera
	if not is_executing() or not is_instance_valid(view) or not view.current or player.in_ui_mode: return
	var sensitivity: float = player.MOUSE_SENSITIVITY * float(player.game_settings.get_setting(&"sensitivity"))
	var y_direction := -1.0 if bool(player.game_settings.get_setting(&"invert_y")) else 1.0
	execution_look_offset.x = clampf(execution_look_offset.x - event.relative.x * sensitivity,
		-deg_to_rad(EXECUTION_LOOK_YAW_LIMIT), deg_to_rad(EXECUTION_LOOK_YAW_LIMIT))
	execution_look_offset.y = clampf(execution_look_offset.y - event.relative.y * sensitivity * y_direction,
		-deg_to_rad(EXECUTION_LOOK_PITCH_LIMIT), deg_to_rad(EXECUTION_LOOK_PITCH_LIMIT))
	if is_instance_valid(execution_observer):
		_update_execution_observer()
	else:
		_apply_execution_view()

func _try_start_execution_observer() -> void:
	if is_instance_valid(execution_observer) or not captor.has_method("execution_camera_frame"): return
	# Keep the survivor's eyes through the lift; the captor signals arrival.
	if captor.has_method("execution_camera_ready") and not captor.execution_camera_ready(): return
	execution_look_offset = Vector2.ZERO
	execution_observer = Camera3D.new()
	execution_observer.name = "ExecutionObserver"
	player.add_child(execution_observer)
	execution_observer.top_level = true
	execution_observer.fov = 65.0
	execution_observer.near = .05
	execution_observer.far = camera.far
	execution_observer.cull_mask = (camera.cull_mask | PlayerVisual.FULL_BODY_LAYER) & ~PlayerVisual.LOCAL_VIEW_LAYER
	camera.near = camera_rest_near
	_update_execution_observer()
	execution_observer.make_current()

func _update_execution_observer() -> void:
	if not is_instance_valid(execution_observer) or not is_instance_valid(captor): return
	var frame: Dictionary = captor.execution_camera_frame(player)
	var pivot: Vector3 = frame.pivot
	var focus: Vector3 = frame.focus
	var offset: Vector3 = frame.offset
	# Orbit the composition, leaving the captive's body and eyes untouched.
	offset = offset.rotated(Vector3.UP, execution_look_offset.x)
	var right := Vector3.UP.cross(offset).normalized()
	offset = offset.rotated(right, execution_look_offset.y)
	_position_execution_observer(pivot, focus, offset, captor)

func _position_execution_observer(pivot: Vector3, focus: Vector3, offset: Vector3, owner_node: Node3D = null) -> void:
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = .18
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, pivot)
	query.motion = offset
	query.collision_mask = 1
	query.exclude = [player.get_rid()]
	if owner_node is CollisionObject3D: query.exclude.append(owner_node.get_rid())
	var seat := _execution_seat_exclusion()
	if seat.is_valid(): query.exclude.append(seat)
	var safe := player.get_world_3d().direct_space_state.cast_motion(query)
	execution_observer.global_position = pivot + offset * safe[0]
	if execution_observer.global_position.distance_squared_to(focus) > .0001:
		execution_observer.look_at(focus, Vector3.UP)

func has_execution_death_view() -> bool:
	return execution_death_view and is_instance_valid(execution_observer) and execution_observer.current

func clear_execution_observer(restore_view := true) -> void:
	var owned := is_instance_valid(execution_observer) and execution_observer.current
	if is_instance_valid(execution_observer):
		execution_observer.clear_current()
		execution_observer.queue_free()
	execution_observer = null
	execution_death_view = false
	execution_death_offset = Vector3.ZERO
	execution_death_focus = Vector3.ZERO
	if owned and restore_view and is_instance_valid(player.camera): player.camera.make_current()

func _apply_execution_view() -> void:
	var forward := -execution_guided_basis.z.normalized()
	var yaw := atan2(-forward.x, -forward.z) + execution_look_offset.x
	var pitch := clampf(asin(clampf(forward.y, -1.0, 1.0)) + execution_look_offset.y,
		deg_to_rad(-80.0), deg_to_rad(80.0))
	camera.global_basis = Basis.from_euler(Vector3(pitch, yaw, 0.0))

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
		if owner_node is CollisionObject3D: query.exclude.append(owner_node.get_rid())
		var safe := player.get_world_3d().direct_space_state.cast_motion(query)
		motion *= safe[0]
	return motion

func _process(delta: float) -> void:
	impact_remaining = maxf(0, impact_remaining - delta)
	impact.color.a = impact_strength * pow(impact_remaining / .22, 2)
	if execution_death_view:
		if not player.is_player_dead or not has_execution_death_view():
			clear_execution_observer(not player.is_player_dead)
		else:
			# Follow the physical torso after ownership ends, without chasing the
			# recovering giant or switching into the detached head's eyes.
			var pivot: Vector3 = player.ragdoll_control.third_person_anchor_position()
			_position_execution_observer(pivot, pivot + execution_death_focus, execution_death_offset)
			return
	if not active() or not is_instance_valid(camera):
		_recover_view(delta)
		return
	camera_elapsed += delta
	if mode == Mode.EXECUTION:
		_try_start_execution_observer()
		if is_instance_valid(execution_observer):
			_update_execution_observer()
			return
		if is_instance_valid(execution_look_target):
			var focus: Vector3 = execution_look_target.global_position
			# Guide a separate view so tracking never erases the survivor's look offset.
			# Retain the capture view briefly, then ease into the slower turn.
			var weight := smoothstep(EXECUTION_VIEW_DELAY,
				EXECUTION_VIEW_DELAY + EXECUTION_VIEW_EASE_SECONDS, camera_elapsed)
			if weight > 0.0:
				execution_guided_basis = execution_view_basis(execution_guided_basis, camera.global_position,
					focus, captor.global_position, delta * weight)
				_apply_execution_view()
		return
	# Lift toward the face once, then hold that parent-local view through bite.
	# Following the lunging mouth caused a downward whip at contact.
	camera.basis = Basis(camera_start.slerp(camera_target, clampf(camera_elapsed / .15, 0, 1)))

static func execution_view_basis(current_basis: Basis, eye: Vector3, focus: Vector3,
		_captor_center: Vector3, delta: float) -> Basis:
	if delta <= 0.0: return current_basis
	var direction := focus - eye
	if direction.length_squared() <= .0001: return current_basis
	var forward := -current_basis.z.normalized()
	var yaw := atan2(-forward.x, -forward.z)
	var pitch := asin(clampf(forward.y, -1.0, 1.0))
	var horizontal := direction.slide(Vector3.UP)
	# The bent speaker can cross directly over the survivor. Its tiny horizontal
	# offset must not reverse the view while the face is almost straight above.
	var overhead := horizontal.length() < absf(direction.y) * tan(deg_to_rad(90.0 - EXECUTION_VIEW_PITCH_LIMIT))
	var target_yaw := yaw
	# Above the comfortable viewing cone, retain yaw rather than steering
	# toward a different body point while the animated speaker crosses overhead.
	if not overhead and horizontal.length_squared() > .0001:
		target_yaw = atan2(-horizontal.x, -horizontal.z)
	var target_pitch := clampf(atan2(direction.y, direction.slide(Vector3.UP).length()),
		-deg_to_rad(EXECUTION_VIEW_PITCH_LIMIT), deg_to_rad(EXECUTION_VIEW_PITCH_LIMIT))
	var turn := Vector2(wrapf(target_yaw - yaw, -PI, PI), target_pitch - pitch)
	turn = turn.limit_length(deg_to_rad(EXECUTION_VIEW_SPEED) * delta)
	return Basis.from_euler(Vector3(pitch + turn.y, yaw + turn.x, 0.0))

func bite_impact() -> void:
	# Brief crush flash survives fatal-grab cleanup, then clears independently.
	impact_remaining = .22
	impact_strength = .28 if active() and captor.grab.bite_part == &"left_arm" else .78

func end(reason: String = "cancelled") -> void:
	var previous := captor
	var was_execution := mode == Mode.EXECUTION
	var arm_release: bool = not was_execution and is_instance_valid(previous) and reason == "bitten" and previous.grab.bite_part == &"left_arm" and not player.is_player_dead
	var observer_owned := is_instance_valid(execution_observer) and execution_observer.current
	var owned_view := observer_owned or (is_instance_valid(camera) and camera.current)
	if was_execution and reason == "death" and observer_owned:
		var pivot: Vector3 = player.execution_contact_position()
		execution_death_view = true
		execution_death_offset = execution_observer.global_position - pivot
		execution_death_focus = Vector3.ZERO
	else:
		clear_execution_observer()
	captor = null
	execution_anchor = null
	execution_look_target = null
	execution_guided_basis = Basis.IDENTITY
	execution_look_offset = Vector2.ZERO
	execution_body_offset = Vector3.ZERO
	execution_wall_clearance = Vector3.ZERO
	execution_wall_clearance_distance = 0.0
	execution_seat_rid = RID()
	execution_seat = null
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
		camera.fov = camera_rest_fov
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
	clear_execution_observer(false)
