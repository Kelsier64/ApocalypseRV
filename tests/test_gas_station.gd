extends SceneTree
var failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var world := load("res://tests/gas_station_playground.tscn").instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 30000
	while not world.ready_for_play and Time.get_ticks_msec() < deadline:
		await physics_frame
	if not world.ready_for_play:
		push_error("FAIL: gas station did not become ready")
		quit(1)
		return
	var station: Node3D = world.get_node("SiteNavigation/Station")
	var player: CharacterBody3D = world.player
	var pump: Node3D = station.get_node("Furnishings/Pump6_9")
	var model: Node3D = pump.get_node("Visuals/Model")
	_expect(model.scene_file_path.ends_with("fuel_pump.glb"), "Station uses the imported GLB")
	_expect(model.transform.is_equal_approx(Transform3D.IDENTITY), "Imported model needs no scale or axis correction")
	_expect(model.find_children("*", "CollisionObject3D", true, false).is_empty(), "GLB contains visuals only")
	var bounds := AABB()
	var has_bounds := false
	for visual in [model] + model.find_children("*", "MeshInstance3D", true, false):
		if not visual is MeshInstance3D: continue
		var local_bounds: AABB = (pump.global_transform.affine_inverse() * visual.global_transform) * visual.get_aabb()
		bounds = bounds.merge(local_bounds) if has_bounds else local_bounds
		has_bounds = true
	_expect(has_bounds and absf(bounds.position.y) < 0.001 and absf(bounds.end.y - 2.255) < 0.001, "Imported geometry is grounded and 2.255 m tall")
	_expect(bounds.position.x >= -0.68 and bounds.end.x <= 0.85 and bounds.size.z <= 1.11, "Imported pump stays inside its authored envelope")
	var reference: Node3D = load("res://world/poi_kit/furniture/fuel_pump_graybox.tscn").instantiate()
	for shape: CollisionShape3D in pump.get_node("Collision").get_children():
		var original: CollisionShape3D = reference.get_node("Collision/" + str(shape.name))
		_expect(shape.transform == original.transform and shape.shape.size == original.shape.size, "Model replacement preserves collision " + str(shape.name))
	reference.free()
	var collider_id: int = pump.get_node("Collision").get_instance_id()
	world.toggle_pump_visuals()
	world.toggle_pump_visuals()
	_expect(pump.get_node("Collision").get_instance_id() == collider_id, "A/B switching preserves the physical body")
	_expect(pump.get_node("Visuals").visible and not pump.get_node("GrayboxPreview").visible, "A/B restores the imported model")
	_expect(station.get_world_3d() == player.get_world_3d(), "Player and building share the outdoor world")
	_expect(station.find_children("*", "SubViewport", true, false).is_empty() and not station.has_node("Entrance"), "No instance/teleport entrance")
	for marker in station.find_children("*", "Marker3D", true, false):
		if marker is PoiLootPoint: _expect(marker.validate().is_empty(), "Valid loot marker " + str(marker.name))
	for i in range(90): await physics_frame
	var container := WorldEntities.get_container(world)
	_expect(container.get_child_count() >= 5, "Fixture spawns collectible supplies")
	for item in container.get_children():
		_expect(item.position.y > -0.3, "Loot has support: " + str(item.name))
	# A fresh asset has markers only: instancing it cannot duplicate supplies.
	var asset: Node3D = load("res://world/poi_kit/buildings/gas_station.tscn").instantiate()
	_expect(asset.find_children("*", "RigidBody3D", true, false).is_empty(), "Asset never mints loot")
	asset.free()
	var map: RID = world.navigation.get_navigation_map()
	for target in [Vector3(0, 0, -18), Vector3(6.5, 0, -10.5), Vector3(-4, 0, -12)]:
		var path := NavigationServer3D.map_get_path(map, Vector3(0, 0, 18), target, true)
		_expect(path.size() >= 2 and path[-1].distance_to(target) < 0.7, "Navigation reaches " + str(target))
	# Real continuous player input: both exterior doors and the internal opening.
	world.start_replay()
	for i in range(3605):
		await physics_frame
		if not world.replay: break
	_expect(world.route_index == world.route.size(), "Continuous shop / yard / service loop completed")
	_expect(absf(player.position.y) < 0.35, "Player remains on the ground")
	# Pick up a real counter item through the production interaction ray.
	player.position = Vector3(-5.5, 0.08, -4.7)
	player.rotation = Vector3.ZERO
	player.velocity = Vector3.ZERO
	var camera: Camera3D = player.get_node("Camera3D")
	camera.look_at(Vector3(-5.5, 1.35, -6.1))
	for i in range(10): await physics_frame
	var before: int = player.inventory.items.size()
	Input.action_press("interact")
	for i in range(8): await physics_frame
	Input.action_release("interact")
	for i in range(20): await physics_frame
	_expect(player.inventory.items.size() == before + 1, "E picks up counter fuel through the real ray")
	# Visual replacement cannot delete solid walls, floor or traversal markers.
	station.get_node("Visuals").free()
	var query := PhysicsRayQueryParameters3D.create(Vector3(-9, 2, -10), Vector3(-11, 2, -10))
	_expect(not station.get_world_3d().direct_space_state.intersect_ray(query).is_empty(), "Wall collision survives visual replacement")
	_expect(station.has_node("AccessPoints/Rear"), "Access points survive visual replacement")
	world.free()
	if failures.is_empty():
		print("PASS: gas station outdoor traversal, navigation, loot interaction and replaceable visuals")
		quit(0)
	else:
		for failure in failures: push_error("FAIL: " + failure)
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
