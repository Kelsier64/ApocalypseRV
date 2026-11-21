extends RefCounted

static func run(tree: SceneTree, world: Node3D, check: Callable) -> void:
	var field := WorldField.new(42)
	var site := field.stop(1)
	check.call(site.get("definition_id") == "orbit_plaza" and POIConfig.definition(&"gas_station") == null,
		"Orbit occupies the primary fuel stop and Northline is archived")
	if site.is_empty(): return
	var variants := {}
	var stock := {}
	for seed_value: int in [42,43,44,45,46,47]:
		var sample := site.duplicate()
		sample.seed = seed_value
		sample.building = Transform3D.IDENTITY
		var visual := POISpawner.new().spawn_site(sample, world)
		if visual == null:
			check.call(false, "Orbit validates in the production spawner")
			return
		var nav := POIConfig.instantiate_site(sample, false)
		var shapes := _shape_plan(visual)
		check.call(shapes == _shape_plan(nav), "Orbit live and navigation geometry agree for seed %d" % seed_value)
		check.call(nav.find_children("*","VisualInstance3D",true,false).is_empty(), "Collision-only plaza omits artwork")
		variants[hash(shapes)] = true
		var shelf := visual.get_node("LootSpawns/FreightTable") as PoiLootPoint
		stock[shelf.candidates[0].resource_path] = true
		nav.free()
		await tree.physics_frame
		await tree.physics_frame
		# Headroom and shoulder clearance on the route from the RV through both
		# department doorways and out of receiving, with a detour to the diner.
		var trunk := [Vector2(0,18),Vector2(4,17),Vector2(4,1),Vector2(0,0),
			Vector2(0,-8.65),Vector2(9,-8.65),Vector2(9,-18)]
		var diner := [Vector2(0,-8.0),Vector2(-13,-8.0)]
		# The pump island on the centre line ends before z=17.
		for route: Array in [trunk,diner]:
			for i in range(1,route.size()):
				check.call(_walk_clear(world, route[i-1], route[i]), "Seed %d: walk clear %s to %s" % [seed_value,route[i-1],route[i]])
		visual.free()
	check.call(variants.size() > 1 and stock.size() == 2,"Plaza seeds vary the physical layout and freight stock")

static func _shape_plan(building: Node3D) -> Array:
	var plan := []
	for collider: CollisionShape3D in building.find_children("*","CollisionShape3D",true,false):
		plan.append([collider.transform,collider.shape.size])
	return plan

static func _walk_clear(world: Node3D, start: Vector2, end: Vector2) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.33
	capsule.height = 1.7
	query.shape = capsule
	query.collision_mask = 1
	query.transform.origin = Vector3(start.x,1.12,start.y)
	query.motion = Vector3(end.x-start.x,0,end.y-start.y)
	return world.get_world_3d().direct_space_state.cast_motion(query)[0] >= 0.999
