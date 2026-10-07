extends SceneTree
var failures: Array[String] = []
func _init() -> void: _run.call_deferred()
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func press(seat: Node, key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	seat._unhandled_input(event)

func pose_steps() -> void:
	for frame in 24:
		await physics_frame
		await process_frame

func check_road_visibility(rv: Chassis, seat: Item) -> void:
	var camera: Camera3D = seat.get_node("Camera3D")
	var blockers: Array[Node] = seat.get_node("CockpitVisual").find_children("*", "MeshInstance3D", true, false)
	blockers.append_array(rv.get_node("StructureSlots").occupant("front").find_children("*", "MeshInstance3D", true, false))
	# Sample actual road sight lines beyond the nose, with the chassis 1.2 m
	# above level ground. Transparent windshield glass is intentionally visible through.
	for distance in [15.0, 25.0, 40.0]:
		var road := rv.to_global(Vector3(seat.position.x, -1.2, -6.0 - distance))
		var screen := camera.unproject_position(road)
		check(not camera.is_position_behind(road) and Rect2(Vector2.ZERO, root.size).has_point(screen), "Default driving view includes road %d m beyond the nose" % distance)
		for candidate in blockers:
			var mesh := candidate as MeshInstance3D
			if mesh.name == "Windshield" or not mesh.mesh is BoxMesh or not mesh.is_visible_in_tree(): continue
			var intersection: Variant = mesh.get_aabb().intersects_segment(mesh.to_local(camera.global_position), mesh.to_local(road))
			check(intersection == null, "Road %d m ahead is not hidden by %s" % [distance, mesh.name])

func palm_position(skeleton: Skeleton3D, side: String) -> Vector3:
	var hand := skeleton.find_bone("hand_" + side)
	var rest := skeleton.get_bone_global_rest(hand)
	var middle := skeleton.get_bone_global_rest(skeleton.find_bone("middle_01_" + side)).origin
	var index := skeleton.get_bone_global_rest(skeleton.find_bone("index_01_" + side)).origin
	var pinky := skeleton.get_bone_global_rest(skeleton.find_bone("pinky_01_" + side)).origin
	var palm := (middle - rest.origin).normalized().cross((index - pinky).normalized()).normalized() * (1.0 if side == "L" else -1.0)
	var center := rest.origin.lerp(middle, .72) + palm * .014
	return skeleton.global_transform * skeleton.get_bone_global_pose(hand) * (rest.affine_inverse() * center)

func check_driving_pose(player: CharacterBody3D, wheel: Node3D, note: String) -> void:
	var skeleton: Skeleton3D = player.get_node("Visuals").skeleton
	var rim: TorusMesh = wheel.get_node("Rim").mesh
	for side in ["L", "R"]:
		var hip := skeleton.get_bone_global_pose(skeleton.find_bone("thigh_" + side)).origin
		var knee := skeleton.get_bone_global_pose(skeleton.find_bone("shin_" + side)).origin
		var ankle := skeleton.get_bone_global_pose(skeleton.find_bone("foot_" + side)).origin
		var knee_dot := (knee - hip).normalized().dot((ankle - knee).normalized())
		check(knee_dot < cos(PI / 4.0), note + " " + side + " knee bends at least 45 degrees into a seated posture (%.3f alignment)" % knee_dot)
		if not player.body_state.has_part(&"left_arm" if side == "L" else &"right_arm"): continue
		var palm := wheel.to_local(palm_position(skeleton, side))
		var radius := Vector2(palm.x, palm.z).length()
		check(absf(palm.y) < .09 and radius > rim.inner_radius - .045 and radius < rim.outer_radius + .05, note + " " + side + " hand contacts the steering rim (%.3f plane, %.3f radius)" % [palm.y, radius])

func _run() -> void:
	var world := Node3D.new()
	world.set_meta("entity_domain", true)
	root.add_child(world)
	current_scene = world
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	world.add_child(shell)
	var rv: Chassis = shell.get_node("Chassis")
	rv.freeze = true
	rv.set_physics_process(false)
	var seat: Item = rv.get_node("DriverSeat")
	var visual: Node3D = seat.get_node("CockpitVisual")
	visual.set_process(false)
	var player: CharacterBody3D = load("res://player/player.tscn").instantiate()
	player.position = Vector3(10, 0, 0)
	world.add_child(player)
	player.set_physics_process(false)
	await physics_frame
	await physics_frame
	var side_door: RVStructurePanel = rv.get_node("RightMiddle")
	check(VehicleStatus.read(rv).filter(func(row): return row.id == "door")[0].level == 0, "Closed vehicle structures leave door warning off")
	side_door.restore_angles([-PI / 2])
	check(VehicleStatus.read(rv).filter(func(row): return row.id == "door")[0].level == 3, "Open independent side door activates cockpit warning")
	side_door.set_health(0.0)
	check(VehicleStatus.read(rv).filter(func(row): return row.id == "door")[0].level == 0, "Broken door state does not leave a stale open-door warning")
	side_door.set_health(side_door.max_health)
	side_door.restore_angles([0.0])
	var console_ray := PhysicsRayQueryParameters3D.create(seat.to_global(Vector3(1.3, 1.1, 0)), seat.to_global(Vector3(0.48, 0.7, -0.5)))
	var console_hit := rv.get_world_3d().direct_space_state.intersect_ray(console_ray)
	check(console_hit.get("collider") == seat, "Gear and brake console targets the same seat equipment")
	seat.interact_hold(player)
	check(seat.current_driver == player and rv.is_player_driving, "Production cockpit grants driving through the actual seat")
	check(player.is_visible_in_tree(), "Seated driver remains visible to vehicle observers and mirrors")
	check_road_visibility(rv, seat)
	var player_visual: PlayerModelVisual = player.get_node("Visuals")
	check(player_visual.local_body.is_visible_in_tree(), "Driving camera can display the seated player's local body")
	check((seat.seat_camera.cull_mask & PlayerModelVisual.LOCAL_VIEW_LAYER) != 0 and (seat.seat_camera.cull_mask & PlayerModelVisual.FULL_BODY_LAYER) == 0, "Driving camera sees the local body without the complete head mesh")
	await pose_steps()
	check_driving_pose(player, visual.get_node("SteeringTilt/SteeringWheel"), "Centered steering")
	var skeleton := player_visual.skeleton
	var root_bone := skeleton.find_bone("root")
	var seated_root := skeleton.get_bone_pose_position(root_bone)
	for side in ["R", "L"]:
		var input_field := "throttle_input" if side == "R" else "brake_input"
		var foot := skeleton.find_bone("foot_" + side)
		var other_foot := skeleton.find_bone("foot_L" if side == "R" else "foot_R")
		var rest_foot := skeleton.get_bone_global_pose(foot).basis.get_rotation_quaternion()
		var rest_other_foot := skeleton.get_bone_global_pose(other_foot).basis.get_rotation_quaternion()
		rv.set(input_field, 1.0)
		await pose_steps()
		check(rest_foot.angle_to(skeleton.get_bone_global_pose(foot).basis.get_rotation_quaternion()) > .1, input_field + " presses its corresponding driver's foot")
		check(rest_other_foot.is_equal_approx(skeleton.get_bone_global_pose(other_foot).basis.get_rotation_quaternion()), input_field + " leaves the other pedal foot at rest")
		check_driving_pose(player, visual.get_node("SteeringTilt/SteeringWheel"), input_field + " pressed")
		rv.set(input_field, 0.0)
		await pose_steps()
		check(rest_foot.is_equal_approx(skeleton.get_bone_global_pose(foot).basis.get_rotation_quaternion()), input_field + " release returns the foot to its original orientation")
		check_driving_pose(player, visual.get_node("SteeringTilt/SteeringWheel"), input_field + " released")
	check(player.global_basis.is_equal_approx(seat.global_basis), "Entering the seat aligns driver orientation with cockpit")
	var parked_transform := rv.global_transform
	rv.global_transform = Transform3D(Basis.from_euler(Vector3(0.08, 0.65, -0.06)), Vector3(3, 1, 2)) * parked_transform
	player._physics_process(1.0 / 60.0)
	check(player.global_basis.is_equal_approx(seat.global_basis) and player.global_position.is_equal_approx(seat.global_position), "Driver follows seat orientation and position during vehicle turns and tilt")
	rv.global_transform = parked_transform
	player._physics_process(1.0 / 60.0)
	var mirrors := rv.get_node("Mirrors")
	mirrors._process(0.1)
	check(mirrors.mirrors.size() == 2, "Exactly two mirrors belong to this RV")
	for mirror in mirrors.mirrors:
		check(mirror.rig.visible and mirror.viewport.world_3d == rv.get_world_3d(), "Installed mirrors use the vehicle world")
		var target := rv.to_global(Vector3(mirror.side * 3.5, 1.5, 8.0))
		var uv: Vector2 = mirror.camera.unproject_position(target)
		check(not mirror.camera.is_position_behind(target) and Rect2(Vector2.ZERO, mirrors.resolution).has_point(uv), "Each camera covers its own rear-side obstacle")
	rv.linear_velocity = rv.global_basis.y * 0.3
	visual._process(1.0)
	check(visual.get_node("Readout").text.begins_with("000"), "Suspension travel is not displayed as road speed")
	rv.linear_velocity = Vector3.ZERO
	press(seat, KEY_B)
	press(seat, KEY_C)
	press(seat, KEY_SPACE)
	visual._process(1.0)
	check(rv.energy.engine_running and rv.gear == 1 and not rv.handbrake, "Cockpit controls operate existing engine, gear and brake state")
	check(visual.get_node("EngineStatus").text == "ENGINE ON" and visual.get_node("BrakeStatus").text.is_empty(), "Physical instruments reflect driver controls")
	var forward_pose: Vector3 = visual.get_node("GearLever").rotation
	press(seat, KEY_Z)
	press(seat, KEY_SPACE)
	rv.steering = 0.3
	rv.current_fuel = 25
	rv.current_power = 75
	visual._process(1.0)
	check(visual.get_node("Readout").text.ends_with("R"), "Physical gear readout follows reverse")
	check(not visual.get_node("GearLever").rotation.is_equal_approx(forward_pose), "Gear lever moves between forward and reverse")
	var wheel: Node3D = visual.get_node("SteeringTilt/SteeringWheel")
	var wheel_center_x := seat.to_local(wheel.global_position).x
	var left_angle := wheel.rotation.y
	check(left_angle > 0.5, "Positive chassis steering turns the cockpit wheel left")
	# Its highest rim point is local -Z after the wheel's fixed tilt.
	check(seat.to_local(wheel.to_global(Vector3(0, 0, -0.23))).x < wheel_center_x - 0.1, "Left steering moves the top of the wheel toward the driver's left")
	await pose_steps()
	check_driving_pose(player, wheel, "Left steering")
	rv.steering = -0.3
	visual._process(1.0)
	check(wheel.rotation.y < -0.5 and is_equal_approx(absf(wheel.rotation.y), left_angle), "Right steering turns the wheel right with symmetric travel")
	check(seat.to_local(wheel.to_global(Vector3(0, 0, -0.23))).x > wheel_center_x + 0.1, "Right steering moves the top of the wheel toward the driver's right")
	await pose_steps()
	check_driving_pose(player, wheel, "Right steering")
	rv.steering = 0.0
	visual._process(1.0)
	check(absf(wheel.rotation.y) < 0.001, "Releasing steering returns the cockpit wheel to center")
	await pose_steps()
	check_driving_pose(player, wheel, "Released steering")
	check(visual.get_node("ParkingLever").rotation.x > 0.4 and visual.get_node("BrakeStatus").text == "PARK", "Handbrake handle and lamp agree with actual brake")
	check(visual.get_node("FuelNeedle").rotation.z > 0 and visual.get_node("BatteryNeedle").rotation.z < 0, "Fuel and battery needles use independent live quantities")
	var socket: BatterySocket = rv.get_node("BatterySocket")
	var battery := socket.installed_battery
	socket.installed_battery = null
	visual._process(1.0)
	check(visual.get_node("BatteryLabel").text == "NO BAT", "Missing battery is distinct from a charged battery")
	socket.installed_battery = battery
	var bounds := seat.get_placement_bounds()
	check(bounds.size.z > 1.8 and bounds.size.x >= 1.44, "Placement measures console and chair as one equipment item")
	rv.set_handbrake(false)
	seat.exit_seat()
	player.set_physics_process(false)
	check(player.seated_in == null and not rv.is_player_driving and not rv.handbrake, "Exit restores player control without engaging parking brake")
	var locomotion: Node = player_visual.get_node("Locomotion")
	locomotion._physics_process(1.0 / 60.0)
	check(not locomotion.driving.active and skeleton.get_bone_pose_position(root_bone).is_equal_approx(Vector3.ZERO), "First locomotion tick clears driving pose and restores skeleton root after exit")
	for missing_arm in [&"left_arm", &"right_arm"]:
		seat.interact_hold(player)
		await pose_steps()
		check(locomotion.driving.active and skeleton.get_bone_pose_position(root_bone).is_equal_approx(seated_root), "Reentering the cockpit does not accumulate seated root offsets")
		check(player.body_state.sever(missing_arm), "Single-arm driving fixture removes one arm through body state")
		player._apply_body_capabilities()
		await pose_steps()
		check(seat.current_driver == player and player.can_drive(), "Driver remains capable with one surviving arm")
		check_driving_pose(player, wheel, "Driving without " + String(missing_arm))
		player.body_state.reset()
		player._apply_body_capabilities()
		seat.exit_seat()
		player.set_physics_process(false)
		locomotion._physics_process(1.0 / 60.0)
		check(not locomotion.driving.active and skeleton.get_bone_pose_position(root_bone).is_equal_approx(Vector3.ZERO), "Repeated seat exit clears driving root pose")
	mirrors._process(0.1)
	for mirror in mirrors.mirrors: check(mirror.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Leaving the seat stops mirror rendering")
	var left_panel: RVStructurePanel = rv.get_node("LeftFront")
	left_panel.take_damage(100000.0)
	mirrors._process(0.1)
	check(not mirrors.mirrors[0].rig.visible and mirrors.mirrors[1].rig.visible, "Destroying a mirror's side panel removes only that mirror")
	left_panel.set_health(left_panel.max_health)
	var exit_local := rv.to_local(player.global_position)
	check(exit_local.x > 0.5 and exit_local.x < 1.4 and exit_local.y < 0.7, "Default cockpit exits into the aisle instead of above the roof")
	var cockpit_id := seat.persistent_id
	check(seat.pickup(player).contains("已拾取") and not seat.is_fixed and not seat.can_operate(), "Picking up the whole cockpit stops its service")
	check(player.inventory.active_item().state.id == cockpit_id and player.inventory.active_item().is_large, "Cockpit inventory owns the same large Item identity")
	check(player.enter_equipment_placement(), "Held cockpit starts an independent placement preview")
	var ghost := player.placement.placing_equipment as Item
	var rim: GeometryInstance3D = ghost.get_node("CockpitVisual/SteeringTilt/SteeringWheel/Rim")
	check(ghost.presentation_only and not ghost.can_operate() and rim.material_override == ghost.ghost_material, "Nested steering wheel participates in an inactive placement preview")
	player.cancel_equipment_placement()
	var held_rim: GeometryInstance3D = player.held_item_node.get_node("CockpitVisual/SteeringTilt/SteeringWheel/Rim")
	check(player.inventory.active_item().state.id == cockpit_id and held_rim.material_override == null and player.held_item_node.visible, "Cancel retains the complete held cockpit and its original material")
	player.global_position = rv.to_global(Vector3(0, 0.5, 0))
	await physics_frame
	await physics_frame
	check(player.enter_equipment_placement(), "Cockpit preview can reopen after cancellation")
	var moved := Transform3D(Basis(Vector3.UP, 0.15), Vector3(-0.7, 0.49605, -3.0))
	player.placement.placing_equipment.global_transform = rv.global_transform * moved
	player.placement.target_support = rv
	player.placement.can_place_equipment = true
	check(player.placement.commit(player), "Held cockpit fixes at the validated new pose")
	check(player.inventory.items.is_empty() and not player.is_placing_equipment(), "Cockpit fixation transfers inventory ownership once")
	var snapshot := VehicleSnapshot.capture(rv)
	check(VehicleSnapshot.validate(snapshot), "Cockpit assembly keeps existing snapshot schema")
	check(await VehicleSnapshot.apply(rv, snapshot), "Snapshot restores moved cockpit")
	var restored: Item
	for device in rv.get_equipment():
		if device.scene_file_path == "res://equipment/driver_seat.tscn": restored = device
	check(restored != null and restored.transform.is_equal_approx(moved), "Saved cockpit position is preserved")
	check(restored != null and restored.has_node("CockpitVisual/SteeringTilt/SteeringWheel"), "Full control assembly is reconstructed from one saved equipment")
	mirrors._process(0.1)
	check(mirrors.mirrors.size() == 2 and mirrors.mirrors[0].rig.visible, "Loading reconnects the existing mirror pair without orphan cameras")
	# Open the new rear leaves before checking the passage and fixed jambs.
	for device in rv.get_structures():
		if device.scene_file_path == "res://equipment/rv_rear_door.tscn": device.restore_angles([-PI / 2, PI / 2])
	check(VehicleStatus.read(rv).filter(func(row): return row.id == "door")[0].level == 3, "Open independent rear door activates cockpit warning")
	await physics_frame
	var query := PhysicsRayQueryParameters3D.create(rv.to_global(Vector3(0, 1.4, 7)), rv.to_global(Vector3(0, 1.4, 5)))
	check(rv.get_world_3d().direct_space_state.intersect_ray(query).is_empty(), "Rear entrance has no invisible wall")
	query.from = rv.to_global(Vector3(1.7, 1.4, 7))
	query.to = rv.to_global(Vector3(1.7, 1.4, 5))
	check(not rv.get_world_3d().direct_space_state.intersect_ray(query).is_empty(), "Rear wall remains solid beside entrance")
	world.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: visible seated driving pose, steering direction, cockpit controls, instruments, whole-assembly placement, aisle exit and checkpoint")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
