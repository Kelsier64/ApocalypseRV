extends SceneTree
## Rendering-independent coverage for the real station's mesh-only print presentation.
var failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func check(okay: bool, message: String) -> void:
	if not okay: failures.append(message)

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
	await process_frame
	await physics_frame
	var station: CraftingStation = rv.get_node("CraftingStation")
	# Keep the real production station clear of the RV and other equipment.
	station.confirm_placement(rv.global_transform * Transform3D(Basis.IDENTITY, Vector3(10, 3, 0)), rv)
	rv.add_item(ItemNames.UNREFINED_FUEL, 100)
	rv.add_item(ItemNames.METAL_PARTS, 100)
	rv.current_power = 50.0
	var visual := station.get_node_or_null("PrintVisual") as Node3D
	check(visual != null, "Production crafting station includes its print presentation")
	if visual == null:
		world.queue_free()
		await process_frame
		_finish()
		return
	var recipe := RecipeCatalog.find("gasoline")
	check(station.request_craft("gasoline"), "Funded production job queues")
	check(is_equal_approx(float(visual.get("progress")), 0.0), "New job starts with no printed height")
	var preview := visual.get("preview") as Node3D
	check(is_instance_valid(preview), "Queue acceptance creates the mesh preview immediately")
	_check_mesh_only(preview)
	station.step_work(recipe.duration * 0.5)
	check(is_equal_approx(float(visual.get("progress")), 0.5), "Printed height follows authoritative remaining time")
	_check_rotated_station(station, visual)
	var half_remaining: float = station.jobs[0].remaining
	rv.current_power = 0.0
	station.step_work(recipe.duration)
	check(is_equal_approx(station.jobs[0].remaining, half_remaining) and is_equal_approx(float(visual.get("progress")), 0.5), "Battery pause preserves partial product and remaining time")
	rv.current_power = 50.0
	station.set_enabled(false)
	station.step_work(recipe.duration)
	check(is_equal_approx(station.jobs[0].remaining, half_remaining) and is_equal_approx(float(visual.get("progress")), 0.5), "Disabled station preserves partial print")
	station.set_enabled(true)
	var saved := station.capture_service_state()
	var materials_before := rv.get_item_count(ItemNames.UNREFINED_FUEL)
	station.restore_service_state(saved)
	check(is_equal_approx(float(visual.get("progress")), 0.5) and rv.get_item_count(ItemNames.UNREFINED_FUEL) == materials_before, "Restoring partial job restores print without charging materials")
	station.cancel_jobs()
	check(station.jobs.is_empty() and visual.get("preview") == null, "Cancellation removes partial presentation immediately")
	check(rv.get_item_count(ItemNames.UNREFINED_FUEL) == materials_before + int(recipe.costs[ItemNames.UNREFINED_FUEL]), "Cancellation refunds reserved inputs once")
	station.cancel_jobs()
	check(rv.get_item_count(ItemNames.UNREFINED_FUEL) == materials_before + int(recipe.costs[ItemNames.UNREFINED_FUEL]), "Repeated cancellation does not duplicate refunds")

	# Equal recipe IDs must still be separate products with distinct job identities.
	check(station.request_craft("gasoline") and station.request_craft("gasoline"), "Two identical recipes queue")
	check(station.jobs.size() == 2 and station.jobs[0].id != station.jobs[1].id, "Repeated recipe jobs retain independent identities")
	var obstacle := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3, 3, 3)
	collider.shape = box
	obstacle.add_child(collider)
	world.add_child(obstacle)
	obstacle.global_position = station.spawn_marker.global_position + station.global_basis.y * 0.5
	await physics_frame
	var products_before := _count_products(world, recipe.scene_path)
	station.step_work(recipe.duration)
	check(station.jobs.size() == 2 and is_zero_approx(station.jobs[0].remaining) and station.last_error == "Output blocked", "Blocked output retains the completed first job")
	check(is_equal_approx(float(visual.get("progress")), 1.0) and is_instance_valid(visual.get("preview")), "Blocked output keeps a fully printed visual")
	station.step_work(recipe.duration)
	check(_count_products(world, recipe.scene_path) == products_before and station.jobs.size() == 2, "Repeated blocked completion creates no physical product")
	obstacle.queue_free()
	await physics_frame
	station.step_work(0.0)
	check(_count_products(world, recipe.scene_path) == products_before + 1 and station.jobs.size() == 1, "Clearing output produces exactly one real item")
	check(is_equal_approx(float(visual.get("progress")), 0.0), "Following identical recipe resets print progress")
	_check_mesh_only(visual.get("preview") as Node3D)
	station.step_work(0.0)
	check(_count_products(world, recipe.scene_path) == products_before + 1, "A zero-time update cannot duplicate the completed product")
	station.cancel_jobs()
	check(visual.get("preview") == null, "Final queue cancellation clears presentation")
	await _check_catalog_and_pre_ready_restore(world, rv, station)
	world.queue_free()
	await process_frame
	_finish()

func _check_mesh_only(preview: Node3D) -> void:
	if not is_instance_valid(preview):
		check(false, "Print preview exists for the active job")
		return
	var meshes := preview.find_children("*", "MeshInstance3D", true, false)
	check(not meshes.is_empty(), "Preview contains actual product meshes")
	check(not preview is Item, "Preview root has no gameplay item ownership")
	for child in preview.find_children("*", "", true, false):
		check(not child is CollisionObject3D and not child is CollisionShape3D and not child is Item, "Print geometry has no physical or gameplay descendants")

func _count_products(world: Node, scene_path: String) -> int:
	var count := 0
	for actor in WorldEntities.get_container(world).get_children():
		if actor is Item and actor.scene_file_path == scene_path: count += 1
	return count

func _finish() -> void:
	if failures.is_empty(): print("PASS: crafting print progress, pause, restore, cancellation and output ownership")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _check_catalog_and_pre_ready_restore(world: Node3D, rv: Chassis, station: CraftingStation) -> void:
	# Every supported product must survive source-scene disposal with usable meshes.
	for recipe in RecipeCatalog.all():
		rv.inventory = {}
		check(rv.deposit_materials(recipe.costs), "Catalog fixture deposits exact recipe inputs: " + recipe.recipe_id)
		rv.current_power = 50.0
		check(station.request_craft(recipe.recipe_id), "Catalog product queues: " + recipe.recipe_id)
		_check_mesh_only(station.print_visual.preview)
		await process_frame
		_check_mesh_only(station.print_visual.preview)
		check(is_zero_approx(station.print_visual.progress), "Catalog product starts unprinted: " + recipe.recipe_id)
		station.cancel_jobs()
	# Loading inventory presentation happens before _ready; it must not start a job visual.
	var partial := {"jobs": [{"id": "pre-ready-print", "recipe": "gasoline", "remaining": 1.0, "costs": {}, "power": 0.3}]}
	var held: CraftingStation = load("res://equipment/crafting_station.tscn").instantiate()
	held.presentation_only = true
	held.restore_item_state({"service": partial})
	check(held.get_node("PrintVisual").get("preview") == null, "Pre-ready restore does not touch uninitialized print nodes")
	world.add_child(held)
	check(held.print_visual.preview == null and not held.can_operate() and not held.is_in_group(Groups.CRAFTING_STATIONS), "Held restored station suppresses print and crafting service")
	held.step_work(2.0)
	check(held.print_visual.preview == null and is_equal_approx(held.jobs[0].remaining, 1.0), "Presentation-only restored queue cannot produce or advance a print")
	held.queue_free()
	var restored: CraftingStation = load("res://equipment/crafting_station.tscn").instantiate()
	restored.restore_item_state({"service": partial})
	restored.freeze = true
	world.add_child(restored)
	check(is_equal_approx(restored.print_visual.progress, 0.5), "Real pre-ready restore builds the partial product when ready")
	_check_mesh_only(restored.print_visual.preview)
	restored.cancel_jobs()
	restored.queue_free()
	await process_frame

func _check_rotated_station(station: CraftingStation, visual: Node3D) -> void:
	var preview := visual.get("preview") as Node3D
	if not is_instance_valid(preview): return
	var old_pose := station.global_transform
	var mesh: MeshInstance3D = preview.get_child(0)
	var material := mesh.get_surface_override_material(0) as ShaderMaterial
	check(material != null, "Partial product has a print material")
	if material == null: return
	var original_cutoff: float = material.get_shader_parameter("cutoff")
	var marker_relative := station.spawn_marker.global_transform.affine_inverse() * mesh.global_position
	station.global_transform = Transform3D(Basis.from_euler(Vector3(0.31, 0.8, -0.22)), Vector3(31, 11, -8))
	station.step_work(0.0)
	check((station.spawn_marker.global_transform.affine_inverse() * mesh.global_position).is_equal_approx(marker_relative), "Partial product stays attached to output marker after station translation and tilt")
	for product_mesh: MeshInstance3D in preview.get_children():
		for surface in product_mesh.mesh.get_surface_count():
			var print_material := product_mesh.get_surface_override_material(surface) as ShaderMaterial
			if print_material == null:
				check(false, "Every printed surface retains its print material")
				continue
			check(is_equal_approx(float(print_material.get_shader_parameter("cutoff")), original_cutoff), "Station rotation preserves a common local print cutoff")
			var mapping: Transform3D = print_material.get_shader_parameter("mesh_to_print")
			var sample := product_mesh.mesh.get_aabb().get_center()
			var expected := station.to_local(product_mesh.to_global(sample))
			check((mapping * sample).is_equal_approx(expected), "Shader clips transformed product geometry in station coordinates")
	station.global_transform = old_pose
