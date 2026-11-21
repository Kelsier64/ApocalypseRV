extends RefCounted

class SiteHost extends Node3D:
	var field: WorldField
	var outdoor_sites := {}

static func run(tree: SceneTree, world: Node3D, check: Callable) -> void:
	var uses := {}
	var encounters := {}
	var fuel_rolls := {}
	for seed_value: int in [0, 1, 3]:
		var host := SiteHost.new()
		host.set_meta("entity_domain", true)
		host.field = WorldField.new(seed_value)
		world.add_child(host)
		var site := _first_station(host.field)
		check.call(not site.is_empty(), "Seed %d schedules a roadside fuel stop" % seed_value)
		if site.is_empty():
			host.free()
			continue
		var chunk := Node3D.new()
		host.add_child(chunk)
		var building := POISpawner.new().spawn_site(site, chunk)
		check.call(building != null, "Fuel station passes production definition and scene validation")
		if building == null:
			host.free()
			continue
		uses[building.get_node("Furnishings").get_child(0).name] = true
		var nav := POIConfig.instantiate_site(site, false)
		check.call(_collision_signature(nav) == _collision_signature(building), "Seeded live and neighbour-bake collision agree")
		nav.free()
		await tree.physics_frame
		await tree.physics_frame
		for marker: Marker3D in building.get_node("AccessPoints").get_children():
			var outside := marker.global_position + Vector3.UP
			var query := PhysicsRayQueryParameters3D.create(outside, outside + marker.global_basis.z * 1.8, 1)
			check.call(building.get_world_3d().direct_space_state.intersect_ray(query).is_empty(), "Door opens through the shell at " + str(marker.name))
		WalkInSites.activate(host, site, chunk)
		var container := WorldEntities.get_container(host)
		var remaining: Array[String] = []
		var enemy_count := 0
		var has_fuel := false
		for actor in container.get_children():
			if actor is BarrelMan:
				enemy_count += 1
				actor.free()
			elif actor.scene_file_path == "res://props/gas_can.tscn":
				has_fuel = true
				actor.free()
			else:
				remaining.append(actor.scene_file_path)
		encounters[enemy_count] = true
		fuel_rolls[has_fuel] = true
		check.call(enemy_count <= 1 and "res://props/oil_barrel.tscn" in remaining, "Yard has an ordinary barrel and at most one disguised enemy")
		WalkInSites.deactivate(host, site)
		check.call(container.get_child_count() == 0, "Retired fuel stop releases live actors")
		WalkInSites.activate(host, site, chunk)
		var restored: Array[String] = []
		for actor in container.get_children(): restored.append(actor.scene_file_path)
		remaining.sort()
		restored.sort()
		check.call(restored == remaining, "Revisiting retains remaining stock and keeps cleared fuel and enemies absent")
		host.free()
	check.call(uses.size() == 3 and encounters.size() == 2 and fuel_rolls.size() == 2,
		"Sampled roadside fuel stops cover three uses and both encounter/fuel outcomes")

static func _first_station(field: WorldField) -> Dictionary:
	for index in range(2, 80, 3):
		for site in field.sites_near_z(-index * field.profile.stop_spacing, 200):
			if site.definition_id == "mile_end": return site
	return {}

static func _collision_signature(building: Node3D) -> Dictionary:
	var shapes := {}
	for shape: CollisionShape3D in building.find_children("*", "CollisionShape3D", true, false):
		shapes[building.get_path_to(shape)] = [shape.transform, shape.shape.size]
	return shapes
