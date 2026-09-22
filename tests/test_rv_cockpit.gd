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
	var seat: Equipment = rv.get_node("DriverSeat")
	var visual: Node3D = seat.get_node("CockpitVisual")
	visual.set_process(false)
	var player: CharacterBody3D = load("res://player/player.tscn").instantiate()
	player.position = Vector3(10, 0, 0)
	world.add_child(player)
	player.set_physics_process(false)
	await physics_frame
	await physics_frame
	var console_ray := PhysicsRayQueryParameters3D.create(seat.to_global(Vector3(1.3, 1.1, 0)), seat.to_global(Vector3(0.48, 0.7, -0.5)))
	var console_hit := rv.get_world_3d().direct_space_state.intersect_ray(console_ray)
	check(console_hit.get("collider") == seat, "Gear and brake console targets the same seat equipment")
	seat.interact_hold(player)
	check(seat.current_driver == player and rv.is_player_driving, "Production cockpit grants driving through the actual seat")
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
	check(absf(visual.get_node("SteeringTilt/SteeringWheel").rotation.y) > 0.5, "Steering wheel follows actual chassis steering")
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
	seat.exit_seat()
	player.set_physics_process(false)
	check(player.seated_in == null and rv.handbrake, "Exit restores player control and engages parking brake")
	mirrors._process(0.1)
	for mirror in mirrors.mirrors: check(mirror.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Leaving the seat stops mirror rendering")
	var left_panel: Equipment = rv.get_node("LeftFront")
	left_panel.enabled = false
	mirrors._process(0.1)
	check(not mirrors.mirrors[0].rig.visible and mirrors.mirrors[1].rig.visible, "Disabling a mirror's side panel removes only that mirror")
	left_panel.enabled = true
	var exit_local := rv.to_local(player.global_position)
	check(exit_local.x > 0.5 and exit_local.x < 1.4 and exit_local.y < 0.7, "Default cockpit exits into the aisle instead of above the roof")
	var original := seat.transform
	seat.start_placement(player)
	check(seat.is_being_placed and not seat.can_operate(), "Moving the whole cockpit stops its service")
	var rim: GeometryInstance3D = visual.get_node("SteeringTilt/SteeringWheel/Rim")
	check(rim.material_override == seat.ghost_material, "Nested steering wheel participates in placement preview")
	seat.cancel_placement()
	player.placement.placing_equipment = null
	check(seat.transform.is_equal_approx(original) and rim.material_override == null, "Cancel restores cockpit placement and original material")
	var moved := Transform3D(Basis(Vector3.UP, 0.3), Vector3(0.0, 0.5, -2.0))
	seat.confirm_placement(rv.global_transform * moved, rv)
	var snapshot := VehicleSnapshot.capture(rv)
	check(VehicleSnapshot.validate(snapshot), "Cockpit assembly keeps existing snapshot schema")
	check(await VehicleSnapshot.apply(rv, snapshot), "Snapshot restores moved cockpit")
	var restored: Equipment
	for device in rv.get_equipment():
		if device.scene_file_path == "res://equipment/driver_seat.tscn": restored = device
	check(restored != null and restored.transform.is_equal_approx(moved), "Saved cockpit position is preserved")
	check(restored != null and restored.has_node("CockpitVisual/SteeringTilt/SteeringWheel"), "Full control assembly is reconstructed from one saved equipment")
	mirrors._process(0.1)
	check(mirrors.mirrors.size() == 2 and mirrors.mirrors[0].rig.visible, "Loading reconnects the existing mirror pair without orphan cameras")
	# Open the new rear leaves before checking the passage and fixed jambs.
	for device in rv.get_equipment():
		if device.scene_file_path == "res://equipment/rv_rear_door.tscn": device.restore_angles([-PI / 2, PI / 2])
	await physics_frame
	var query := PhysicsRayQueryParameters3D.create(rv.to_global(Vector3(0, 1.4, 7)), rv.to_global(Vector3(0, 1.4, 5)))
	check(rv.get_world_3d().direct_space_state.intersect_ray(query).is_empty(), "Rear entrance has no invisible wall")
	query.from = rv.to_global(Vector3(1.7, 1.4, 7))
	query.to = rv.to_global(Vector3(1.7, 1.4, 5))
	check(not rv.get_world_3d().direct_space_state.intersect_ray(query).is_empty(), "Rear wall remains solid beside entrance")
	world.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: cockpit controls, instruments, whole-assembly placement, aisle exit and checkpoint")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
