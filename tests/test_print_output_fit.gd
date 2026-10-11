extends SceneTree
var failures: Array[String] = []
func _init() -> void: _run.call_deferred()
func check(okay: bool, message: String) -> void:
	if not okay: failures.append(message)
func products(world: Node, scene: String) -> Array[Item]:
	var result: Array[Item] = []
	for item in WorldEntities.get_container(world).get_children():
		if item is Item and item.scene_file_path == scene: result.append(item)
	return result
func mesh_bounds(node: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if not mesh.is_visible_in_tree(): continue
		var box: AABB = (node.global_transform.affine_inverse() * mesh.global_transform) * mesh.mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result
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
	var player: CharacterBody3D = load("res://player/player.tscn").instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	player.global_position = Vector3(10, 3, 0)
	await process_frame
	await physics_frame
	var station: CraftingStation = rv.get_node("CraftingStation")
	check(station.position.is_equal_approx(Vector3(-1.15, .5, 1)), "Original production cabin printer position remains unchanged")
	var wheel := RecipeCatalog.find("wheel")
	var next := RecipeCatalog.find("wheel")
	rv.inventory = {}
	rv.deposit_materials(wheel.costs)
	rv.deposit_materials(next.costs)
	rv.current_power = 50
	check(station.request_craft(wheel.recipe_id) and station.request_craft(next.recipe_id), "Cabin queues two official full-size wheels")
	print("Cabin wheel pose: ", station.jobs[0].print_orientation, "/", station.jobs[0].print_offset)
	check(station.jobs[0].get("print_orientation", 0) != 0, "Real roof selects a flat full-size wheel")
	station.step_work(wheel.duration * .5)
	var saved := station.capture_service_state()
	var preview_bounds := mesh_bounds(station.print_visual.preview)
	check(preview_bounds.size.y < .8 and preview_bounds.size.x > 1.3 and preview_bounds.size.z > 1.3, "Preview uses genuinely horizontal full-size wheel geometry")
	check(ItemState.valid_service(station.scene_file_path, saved), "Checkpoint schema accepts fixed integer print pose")
	station.restore_service_state(saved)
	check(station.capture_service_state() == saved and mesh_bounds(station.print_visual.preview).is_equal_approx(preview_bounds), "Partial print restores identical queue pose and preview")
	var invalid := saved.duplicate(true)
	invalid.jobs[0].print_orientation = 3
	check(not ItemState.valid_service(station.scene_file_path, invalid), "Out-of-range orientation is rejected")
	invalid = saved.duplicate(true)
	invalid.jobs[0].print_offset = -1
	check(not ItemState.valid_service(station.scene_file_path, invalid), "Out-of-range bed offset is rejected")
	invalid = saved.duplicate(true)
	invalid.jobs[0].print_offset = 1.0
	check(not ItemState.valid_service(station.scene_file_path, invalid), "Noninteger offset is rejected")
	station.step_work(wheel.duration * .5)
	var wheels := products(world, wheel.scene_path)
	check(wheels.size() == 1 and station.jobs.size() == 1, "First full-size wheel actually delivers beneath intact cabin roof")
	if not wheels.is_empty():
		var item := wheels[0]
		item.freeze = true
		var expected := CraftingOutputPlacement.output_pose(item, station.spawn_marker.global_transform, saved.jobs[0].print_orientation, saved.jobs[0].print_offset)
		check(item.global_transform.is_equal_approx(expected), "Preview and delivered item use the exact same chosen pose")
		check(absf(item.global_basis.y.dot(Vector3.UP)) < .001, "Delivered tire is physically rotated rather than shrunk")
		await physics_frame
		station.step_work(next.duration)
		var charge: float = rv.current_power
		check(station.jobs[0].get("print_orientation", 0) != 0, "Next wheel retains a structural cabin fit despite the previous output occupying bed")
		check(station.jobs.size() == 1 and station.last_error == "Output blocked", "Delivered tire occupies bed and blocks second tire")
		station.step_work(0)
		check(rv.current_power == charge, "Blocked next output retry charges no extra power")
		var ray: RayCast3D = player.camera.get_node("InteractRay")
		ray._step_buttons(item, true, false, 0.0)
		ray._step_buttons(item, false, false, 0.0)
		await process_frame
		await physics_frame
		check(products(world, wheel.scene_path).is_empty(), "Actual E interaction handler picks up manufactured wheel")
		station.step_work(0)
		check(station.jobs.is_empty() and products(world, next.scene_path).size() == 1 and rv.current_power == charge, "Wheel pickup frees bed and resumes already-paid next output")
	for item in products(world, next.scene_path): item.queue_free()
	await physics_frame
	await check_blocked_retry(world, rv, station, wheel)
	world.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: full-size cabin wheel fit, matching preview, pickup, queue, fixed pose save and blocked retry")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
func check_blocked_retry(world: Node3D, rv: Chassis, station: CraftingStation, recipe: RecipeDefinition) -> void:
	rv.deposit_materials(recipe.costs)
	rv.current_power = 50
	var blocker := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	collision.shape.size = Vector3(3, 2, 3)
	blocker.add_child(collision)
	world.add_child(blocker)
	blocker.global_position = station.spawn_marker.global_position + Vector3.UP * .5
	await physics_frame
	check(station.request_craft(recipe.recipe_id), "Fully obstructed bed accepts a pending wheel request")
	var startup_charge: float = rv.current_power
	station.step_work(recipe.duration)
	check(not station.jobs[0].has("print_orientation") and station.print_visual.preview == null and station.jobs[0].remaining == recipe.duration, "Without any structural pose, fabrication waits before geometry or work begins")
	check(rv.current_power == startup_charge and station.last_error == "Output blocked", "No-fit startup spends no battery or work time")
	var waiting := station.capture_service_state()
	station.restore_service_state(waiting)
	station.step_work(recipe.duration)
	check(rv.current_power == startup_charge and station.capture_service_state() == waiting, "Unchosen pose wait survives checkpoint restore")
	blocker.global_position = Vector3(10, 5, 0)
	await physics_frame
	station.step_work(recipe.duration * .5)
	check(station.jobs[0].get("print_orientation", 0) == 1 and station.print_visual.preview != null, "Clearing startup obstacle selects a real roof-compatible pose and starts printing")
	var original := station.capture_service_state()
	blocker.global_position = station.spawn_marker.global_position + Vector3.UP * .5
	await physics_frame
	station.step_work(recipe.duration * .5)
	var charge: float = rv.current_power
	check(station.jobs.size() == 1 and is_zero_approx(station.jobs[0].remaining) and products(world, recipe.scene_path).is_empty(), "All bed space blocked retains completed wheel without output")
	var completed := station.capture_service_state()
	station.restore_service_state(completed)
	station.step_work(recipe.duration)
	check(rv.current_power == charge and products(world, recipe.scene_path).is_empty(), "Completed blocked restore never charges or duplicates")
	check(station.jobs[0].print_orientation == original.jobs[0].print_orientation and station.jobs[0].print_offset == original.jobs[0].print_offset, "Later obstruction never changes printed pose")
	blocker.queue_free()
	await physics_frame
	# Legacy completed queues have no new pose fields; migrate and deliver on bed.
	completed.jobs[0].erase("print_orientation")
	completed.jobs[0].erase("print_offset")
	check(ItemState.valid_service(station.scene_file_path, completed), "Legacy completed wheel jobs remain valid")
	station.restore_service_state(completed)
	station.step_work(0)
	check(station.jobs.is_empty() and products(world, recipe.scene_path).size() == 1 and rv.current_power == charge, "Legacy remaining-zero wheel selects cabin fit and resumes after clearing obstacle")
	station.step_work(0)
	check(products(world, recipe.scene_path).size() == 1, "Completion retries produce one wheel only")
