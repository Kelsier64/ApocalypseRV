extends SceneTree
var failures: Array[String] = []
func _init() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func visual_bounds(visual: Node3D) -> AABB:
	var bounds := AABB()
	var found := false
	for child in visual.get_children():
		if not child is MeshInstance3D: continue
		var part: AABB = Transform3D(visual.basis, Vector3.ZERO) * child.transform * child.get_aabb()
		bounds = bounds.merge(part) if found else part
		found = true
	return bounds

func check_visual(prop: Item, mounted: Node3D, label: String) -> void:
	var loose := prop.get_node("WheelMesh") as Node3D
	check(loose.scene_file_path == mounted.scene_file_path, label + " uses the mounted wheel visual scene")
	check(loose.get_child_count() == mounted.get_child_count(), label + " retains all tread, rim and lug parts")
	for child in mounted.get_children():
		var counterpart := loose.get_node_or_null(NodePath(child.name)) as MeshInstance3D
		check(counterpart != null and counterpart.mesh == child.mesh and counterpart.transform.is_equal_approx(child.transform), label + " shares geometry and materials for " + child.name)
	var installed_size := visual_bounds(mounted).size
	var loose_size := visual_bounds(loose).size
	check(loose_size.is_equal_approx(Vector3(installed_size.z, installed_size.y, installed_size.x)), label + " matches actual mounted mesh dimensions after axle rotation")
	check(prop.scale.is_equal_approx(Vector3.ONE), label + " retains full world scale")

func run() -> void:
	var world := Node3D.new()
	world.set_meta("entity_domain", true)
	root.add_child(world)
	current_scene = world
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	world.add_child(shell)
	var rv: Chassis = shell.get_node("Chassis")
	rv.freeze = true
	rv.set_physics_process(false)
	await physics_frame
	var healthy: Item = load("res://props/wheel.tscn").instantiate()
	healthy.freeze = true
	world.add_child(healthy)
	check_visual(healthy, rv.installed_wheels[0].get_node("WheelMesh"), "Healthy loose wheel")
	check(not rv.puncture_wheel(-1) and not rv.puncture_wheel(4), "Invalid slots cannot puncture")
	for slot in range(4):
		check(rv.puncture_wheel(slot), "Each tire punctures independently")
		check(not rv.puncture_wheel(slot), "Repeated contact is idempotent")
		check(rv.wheel_health[slot] == 0 and rv.installed_wheels[slot].wheel_radius < rv.WHEEL_RADIUS, "Flat tire collapses")
		check(rv.tire_warning().contains(TireDynamics.NAMES[slot] + "爆胎"), "Warning identifies tire position")
	var saved := VehicleSnapshot.capture(rv)
	check(VehicleSnapshot.validate(saved), "Flat wheels use valid existing save schema")
	for slot in range(4): rv.get_node("WheelSocket%d" % slot).repair_health(60)
	check(rv.wheel_health.all(func(hp): return hp == 60), "Existing repair restores each flat")
	check(VehicleSnapshot.apply(rv, saved), "Restore flat tires")
	check(rv.wheel_health.all(func(hp): return hp == 0), "Four flat states survive restore")
	check(rv.installed_wheels.all(func(w): return w.wheel_radius < rv.WHEEL_RADIUS), "Restored flat physics applied")
	rv.energy.engine_running = false
	rv.linear_velocity = Vector3.ZERO
	var mounted_flat := rv.installed_wheels[0].get_node("WheelMesh") as Node3D
	var healthy_shape := healthy.get_node("CollisionShape3D").shape as CylinderShape3D
	var old_id := rv.wheel_ids[0]
	check(rv.remove_wheel_to_world(0), "Flat wheel can be removed")
	var props := WorldEntities.get_container(rv).get_children().filter(func(n): return n is Item and n.item_name == ItemNames.WHEEL and n.persistent_id == old_id)
	check(props.size() == 1 and props[0].condition == 0 and props[0].persistent_id == old_id, "Removed flat preserves condition and identity")
	check_visual(props[0], mounted_flat, "Removed flat wheel")
	check(is_equal_approx(healthy_shape.radius, Chassis.WHEEL_RADIUS), "Flat item resizing does not mutate another wheel's collision shape")
	var player: Node3D = load("res://player/player.tscn").instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	check(player.add_prop_item(props[0], "res://props/wheel.tscn"), "Flat enters inventory")
	check_visual(player.held_item_node, mounted_flat, "Held flat wheel")
	check(player.enter_equipment_placement(), "Flat wheel enters independent placement preview")
	check_visual(player.placement.placing_equipment, mounted_flat, "Flat placement preview")
	player.cancel_equipment_placement()
	props[0].queue_free()
	check(rv.install_wheel_from_player(player, 0), "Flat can be reinstalled without resetting it")
	check(rv.wheel_health[0] == 0 and rv.wheel_ids[0] == old_id, "Reinstall does not cure a puncture")
	rv.add_item(ItemNames.METAL_PARTS, 2)
	var repair := RepairOperation.new()
	repair.step(player, rv.get_node("WheelSocket0"), true, 2.0)
	check(rv.wheel_health[0] == 60 and rv.get_item_count(ItemNames.METAL_PARTS) == 0, "Actual repair operation consumes two metal and fixes puncture")
	check(is_equal_approx(rv.installed_wheels[0].wheel_radius, rv.WHEEL_RADIUS), "Repair restores radius")
	healthy.condition = 0.0
	check_visual(healthy, rv.installed_wheels[2].get_node("WheelMesh"), "Loose wheel condition update")
	healthy.condition = 60.0
	check_visual(healthy, rv.installed_wheels[0].get_node("WheelMesh"), "Repaired loose wheel")
	check(is_equal_approx(healthy_shape.radius, Chassis.WHEEL_RADIUS) and is_equal_approx(healthy_shape.height, Chassis.WHEEL_WIDTH), "Repair restores loose collision dimensions")
	rv.remove_wheel(1)
	check(not rv.puncture_wheel(1), "Empty socket cannot puncture")
	rv.get_node("WheelSocket1").repair_health(60)
	check(rv.wheel_health[1] == 0, "Empty socket cannot repair a removed tire")
	var hazard := TireSpikeStrip.new()
	world.add_child(hazard)
	check(hazard.crosses_spikes(Vector3(0, 0, 2), Vector3(0, 0, -2)), "Swept contact catches a fast crossing")
	check(not hazard.crosses_spikes(Vector3(3, 0, 2), Vector3(3, 0, -2)), "Side pass misses spikes")
	check(not hazard.crosses_spikes(Vector3(0, 1, 2), Vector3(0, 1, -2)), "Airborne pass misses spikes")
	hazard.rotation.y = PI / 3
	check(hazard.crosses_spikes(hazard.to_global(Vector3(0, 0, 2)), hazard.to_global(Vector3(0, 0, -2))), "Rotated strip uses its own geometry")
	var field := WorldField.new(42)
	var loot_before := field.loot_plan(6)
	var count := 0
	var example_band := -1
	for band in range(300):
		var placement := TireSpikeStrip.placement(field, band)
		check(placement == TireSpikeStrip.placement(WorldField.new(42), band), "Roadside hazards regenerate deterministically")
		if band < 3: check(placement.is_empty(), "Initial 450 metres safe")
		if not placement.is_empty():
			count += 1
			example_band = band
			var position: Vector3 = placement.transform.origin
			var road := field.road_query(position.x, position.z)
			check(road.distance > road.width / 2 - 1.0, "Hazard stays near shoulder and leaves road centre open")
	check(count > 0 and count < 35, "Hazards are rare across 300 seeded bands")
	check(loot_before == field.loot_plan(6), "Hazard RNG does not perturb loot")
	if example_band >= 0:
		var chunk := Node3D.new()
		world.add_child(chunk)
		TireSpikeStrip.build(chunk, field, example_band)
		var generated := chunk.get_node("TireSpikeStrip") as TireSpikeStrip
		var generated_pose := generated.global_transform
		check(not generated.is_physics_processing(), "Distant generated hazard does no per-frame work")
		chunk.free()
		chunk = Node3D.new()
		world.add_child(chunk)
		TireSpikeStrip.build(chunk, field, example_band)
		check(chunk.get_node("TireSpikeStrip").global_transform == generated_pose, "Unloading and rebuilding preserves hazard placement")
	print("SPIKE_SPAWNS %d / 300 bands" % count)
	world.queue_free()
	await process_frame
	RoadsideKit.scenes.clear()
	RoadsideKit.meshes.clear()
	RoadsideKit.materials.clear()
	await physics_frame
	await process_frame
	if failures.is_empty(): print("PASS: Tire puncture lifecycle, repair, persistence and seeded hazards")
	else:
		for failure in failures: push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)
