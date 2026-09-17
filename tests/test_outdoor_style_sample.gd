extends SceneTree
var failures: Array[String] = []

func _init() -> void: _run.call_deferred()

func check(ok: bool, note: String) -> void:
	if not ok:
		failures.append(note)
		push_error("FAIL: " + note)

func _run() -> void:
	var study: Node3D = load("res://tests/industrial_style_playground.tscn").instantiate()
	root.add_child(study)
	current_scene = study
	for i in range(20): await physics_frame
	check(study.dressing_ready and study.forest.size() >= 27, "Sample decorates the production world")
	var buildings: Array = study.buildings
	check(buildings.size() == 1, "Only the reference maintenance entrance receives facade study")
	var shape_count := study.find_children("*", "CollisionShape3D", true, false).size()
	var site_pose: Transform3D = study.site.building
	var forest_entry: Dictionary = study.forest[0]
	check(forest_entry.base.mesh == ForestMeshes.tree(0), "Production cached tree resource stays unchanged")
	var sample_count := 0
	for cell in forest_entry.sample.get_children(): sample_count += cell.multimesh.instance_count
	check(sample_count == forest_entry.base.instance_count, "Spatial partition retains the complete vegetation count")
	study.styled = false
	study.apply_style()
	await process_frame
	check(forest_entry.node.multimesh == forest_entry.base and forest_entry.node.visible and not forest_entry.sample.visible, "A/B restores original vegetation resource")
	check(study.main.get_node("WorldEnvironment").environment == study.baseline_environment, "A/B restores original environment")
	study.styled = true
	study.apply_style()
	await process_frame
	check(study.find_children("*", "CollisionShape3D", true, false).size() == shape_count, "A/B never changes physical geometry")
	check(study.site.building == site_pose, "Entrance transform remains stable")
	var panel: Equipment = study.main.get_node("NewRv/Chassis/RightFront")
	panel.current_health = panel.max_health * 0.2
	await process_frame
	await process_frame
	check(panel.get_node("Lower").get_active_material(0).detail_enabled, "Sample retains real damage layer")
	panel.current_health = panel.max_health
	await process_frame
	await process_frame
	check(not panel.get_node("Lower").get_active_material(0).detail_enabled, "Repair restores structured sample paint")
	var event := InputEventKey.new()
	event.keycode = KEY_F3
	event.pressed = true
	study._unhandled_input(event)
	var engine_id: String = study.player.inventory.active_item().state.engine.id
	for i in range(7800):
		await physics_frame
		if not study.walking: break
	check(not study.walking, "Actual engine carrier completes sample route")
	check(study.player.inventory.active_item().state.engine.id == engine_id, "Carried engine identity survives route")
	check(study.walk_time > 95 and study.walk_time < 120, "Sample preserves production travel duration")
	var building: Node3D = buildings[0].sample.get_parent()
	var manager: PoiInstanceManager = study.main.get_node("PoiInstances")
	study.player.global_basis = building.global_basis
	study.player.camera.rotation = Vector3.ZERO
	for i in range(5): await physics_frame
	Input.action_press("interact")
	for i in range(10): await physics_frame
	Input.action_release("interact")
	var deadline := Time.get_ticks_msec() + 20000
	while (manager.busy or manager.interior == null) and Time.get_ticks_msec() < deadline: await process_frame
	check(manager.interior != null and not manager.busy, "Real E ray enters through the dressed doorway")
	if manager.interior != null and not manager.busy:
		check(not study.main.get_node("OutdoorPresentation").effect.visible, "Interior still disables outdoor filter")
		await manager.leave()
		check(study.player.inventory.active_item().state.engine.id == engine_id, "Return preserves carried engine")
		check(study.player.global_position.distance_to(building.get_node("ReturnPoint").global_position) < 1, "Dressed entrance leaves return landing clear")
	study.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: style A/B isolation, unchanged physics, real engine carry, damage, entry and return")
	quit(0 if failures.is_empty() else 1)
