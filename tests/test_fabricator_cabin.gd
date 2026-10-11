extends SceneTree
## Real cabin printing keeps crouched bodies on the bed until safe controller use.
var failures: Array[String] = []

func _init() -> void: _run.call_deferred()

func check(okay: bool, message: String) -> void:
	if not okay: failures.append(message)

func _bodies(world: Node) -> Array[PrintedPlayerBody]:
	var result: Array[PrintedPlayerBody] = []
	for node in WorldEntities.get_container(world).get_children():
		if node is PrintedPlayerBody: result.append(node)
	return result

func _bounds(node: Node3D) -> AABB:
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
	check(station.position.is_equal_approx(Vector3(-1.15, .5, 1)), "Fixture keeps original production printer coordinates and roof")
	var recipe := RecipeCatalog.find("printed_player")
	rv.inventory = {}
	rv.deposit_materials(recipe.costs)
	rv.deposit_materials(recipe.costs)
	rv.current_power = 50
	var power_before: float = rv.current_power
	check(station.request_craft("printed_player") and station.request_craft("printed_player"), "Two official bodies queue inside cabin")
	check(_bounds(station.print_visual.preview).size.y < 1.2, "Original cabin roof selects a crouched print preview under 1.2m high")
	var rig: Node3D = station.get_node("Details")
	var gantry: Node3D = rig.get_node("Gantry")
	station.step_work(recipe.duration * .5)
	rig._physics_process(2.0)
	var halfway_height := gantry.position.y
	var saved := station.capture_service_state()
	var saved_bounds := _bounds(station.print_visual.preview)
	var saved_power: float = rv.current_power
	var saved_inventory: Dictionary = rv.inventory.duplicate(true)
	station.restore_service_state(saved)
	check(station.jobs[0].get("crouching") == true and is_equal_approx(station.print_visual.progress, .5) and _bounds(station.print_visual.preview).is_equal_approx(saved_bounds), "Restoring partial cabin print preserves crouched geometry and progress")
	check(rv.current_power == saved_power and rv.inventory == saved_inventory, "Restoring crouched queue does not recharge reserved power or inputs")
	station.step_work(recipe.duration * .49)
	rig._physics_process(2.0)
	check(gantry.position.y > halfway_height, "Crouched print still raises frame as layers accumulate")
	station.step_work(recipe.duration * .01 + .0001)
	check(station.jobs.size() == 1 and _bodies(world).size() == 1, "First crouched body completes on cabin bed and advances queue")
	check(is_equal_approx(power_before - rv.current_power, recipe.power_cost), "First fabrication charges power exactly once")
	check(is_zero_approx(station.print_visual.progress), "Next queue entry starts a fresh preview")
	var body: PrintedPlayerBody = _bodies(world)[0] if not _bodies(world).is_empty() else null
	if body != null:
		body.freeze = true
		check(body.crouching and _bounds(body).size.y < 1.2, "Physical delivered body keeps the crouched bake")
		check(body.global_position.distance_to(station.spawn_marker.global_position) < .1, "Delivered feet remain at output marker on bed")
		check(body.global_position.y + _bounds(body).end.y < 2.500574, "Delivered crouched mesh stays below original RV roof")
	# Existing body occupies the sole permitted output; adjacent floor stays open.
	await physics_frame
	station.step_work(recipe.duration)
	var occupied_power: float = rv.current_power
	check(station.jobs.size() == 1 and is_zero_approx(station.jobs[0].remaining) and _bodies(world).size() == 1, "Second completed body remains blocked while first occupies bed")
	check(station.last_error.begins_with("Output blocked"), "Occupied bed reports explicit blocked output")
	station.step_work(recipe.duration)
	station.step_work(0)
	check(_bodies(world).size() == 1 and rv.current_power == occupied_power, "Occupied-bed retries neither duplicate bodies nor charge again")
	if body != null: await _check_real_e(world, player, body, station)
	# After transfer the controller occupies the bed and must also vacate.
	player.global_position = Vector3(10, 3, 0)
	player._update_crouch()
	check(not player.is_crouching(), "Controller stands only after leaving bed for full-height open space")
	if body != null: body.global_position = Vector3(10, 3, -3)
	await physics_frame
	station.step_work(0)
	check(station.jobs.is_empty() and _bodies(world).size() == 2, "Vacating bed resumes already-paid second body exactly once")
	check(rv.current_power == occupied_power and is_equal_approx(power_before - rv.current_power, recipe.power_cost * 2), "Two bodies consume exactly two recipe power costs")
	check(station.print_visual.preview == null, "Final delivery clears preview")
	# Real return clears the product on X/Z before it starts lowering.
	for tick in 40:
		if Vector2(rig.get_node("Gantry/Carriage/Head").position.x, rig.get_node("Gantry/Carriage").position.z).is_equal_approx(Vector2(.54, .55)): break
		rig._physics_process(.05)
	var completed_height := gantry.position.y
	rig._physics_process(.5)
	check(gantry.position.y < completed_height and gantry.position.y > .9, "Completed frame lowers gradually without snapping")
	station.step_work(0)
	station.step_work(recipe.duration)
	check(_bodies(world).size() == 2, "Repeated completed updates cannot duplicate bodies")
	for item in _bodies(world):
		item.global_position = Vector3(10 + _bodies(world).find(item) * 2, 3, -3)
		item.freeze = true
	await physics_frame
	await _check_low_clearance(world, rv, station)
	for item in _bodies(world): item.global_position = Vector3(10 + _bodies(world).find(item) * 2, 3, -3)
	await physics_frame
	await _check_ordinary_block(world, rv, station)
	world.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: cabin crouched bed printing, E transfer, occupancy, restore, gradual return and blocked retry")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _check_real_e(world: Node3D, player: CharacterBody3D, body: PrintedPlayerBody, station: CraftingStation) -> void:
	var ray: RayCast3D = player.camera.get_node("InteractRay")
	var reached := false
	var feet := body.global_position
	for direction in [Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3(1, 0, -1).normalized()]:
		var candidate: Vector3 = feet + direction * 1.15 - Vector3.UP * .25
		# Approach from the cabin floor, rather than another bed-height pose
		# whose standing controller would itself intersect the unchanged roof.
		candidate.y = station.global_position.y - .19
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = player.standing_collision_shape
		query.transform = Transform3D(Basis.IDENTITY, candidate) * player.standing_collision_transform
		query.collision_mask = 1
		query.exclude = [player.get_rid(), body.get_rid()]
		if not world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(): continue
		player.global_position = candidate
		player.camera.look_at(feet + Vector3.UP * .6)
		ray.force_raycast_update()
		if ray.get_collider() == body:
			reached = true
			break
	check(reached, "Crouched body on bed is reachable through real interaction ray")
	if not reached: return
	var instance_id := player.get_instance_id()
	var before := player.global_position
	Input.action_press("interact")
	for frame in 3: await physics_frame
	Input.action_release("interact")
	for frame in 3: await physics_frame
	check(player.get_instance_id() == instance_id and player.global_position.distance_to(before) > .5, "Real E moves the single controller into crouched body")
	check(player.global_position.distance_to(feet - Vector3.UP * .25) < .1, "E lands at physical body feet on bed")
	check(player.is_crouching(), "E preserves crouched state under cabin roof")
	player._update_crouch()
	check(player.is_crouching() and not player._crouch_standing_volume_clear(), "Releasing crouch cannot stand through roof while on bed")
	var collision := player.get_node("CollisionShape3D") as CollisionShape3D
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collision.shape
	query.transform = collision.global_transform
	query.collision_mask = 1
	query.exclude = [player.get_rid(), body.get_rid(), station.get_rid()]
	check(world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(), "Transferred crouched controller does not penetrate roof or cabin walls")

func _check_low_clearance(world: Node3D, rv: Chassis, station: CraftingStation) -> void:
	var recipe := RecipeCatalog.find("printed_player")
	rv.deposit_materials(recipe.costs)
	rv.current_power = 50
	var obstacle := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# Block only bed overhead; adjacent cabin floor remains available.
	box.size = Vector3(1.1, .1, 1.1)
	collider.shape = box
	obstacle.add_child(collider)
	world.add_child(obstacle)
	obstacle.global_position = station.spawn_marker.global_position + Vector3.UP * .7
	await physics_frame
	check(station.request_craft("printed_player"), "Too-low overhead fixture accepts pending body job")
	var before_count := _bodies(world).size()
	station.step_work(recipe.duration)
	check(station.jobs.size() == 1 and is_zero_approx(station.jobs[0].remaining) and station.last_error.begins_with("Output blocked"), "Roof too low even for crouch preserves completed blocked job")
	check(station.last_error.contains("bed") and station.last_error.contains("overhead"), "Blocked body explicitly requests clearing bed and overhead space")
	check(is_equal_approx(station.print_visual.progress, 1), "Blocked overhead retains completed visual")
	var power_after: float = rv.current_power
	station.step_work(recipe.duration)
	station.step_work(0)
	check(_bodies(world).size() == before_count and rv.current_power == power_after, "Open adjacent floor never supplies fallback or extra charge")
	obstacle.queue_free()
	await physics_frame
	station.step_work(0)
	check(station.jobs.is_empty() and _bodies(world).size() == before_count + 1 and rv.current_power == power_after, "Clearing overhead resumes paid body on bed exactly once")
	if _bodies(world).size() > before_count:
		var output: PrintedPlayerBody = _bodies(world).back()
		output.freeze = true
		check(output.crouching and output.global_position.distance_to(station.spawn_marker.global_position) < .1, "Resumed output remains crouched at original marker")
	station.step_work(0)
	check(_bodies(world).size() == before_count + 1, "Resumed completion never duplicates output")

func _check_ordinary_block(world: Node3D, rv: Chassis, station: CraftingStation) -> void:
	var recipe := RecipeCatalog.find("gasoline")
	rv.deposit_materials(recipe.costs)
	rv.current_power = 50
	check(station.request_craft("gasoline"), "Ordinary product queues")
	var obstacle := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1, 1, 1)
	collider.shape = box
	obstacle.add_child(collider)
	world.add_child(obstacle)
	obstacle.global_position = station.spawn_marker.global_position + Vector3.UP * .3
	await physics_frame
	station.step_work(recipe.duration)
	check(station.jobs.size() == 1 and station.last_error == "Output blocked", "Ordinary products retain original blocked-bed behavior")
	obstacle.queue_free()
	await physics_frame
	station.step_work(0)
	check(station.jobs.is_empty(), "Ordinary product completes once bed obstruction clears")
