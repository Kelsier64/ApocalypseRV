extends SceneTree
var failures: Array[String] = []

class SiteOwner extends Node3D:
	var outdoor_sites: Dictionary = {}
	var field: WorldField

func _init() -> void:
	run.call_deferred()

func check(ok: bool, note: String) -> void:
	if not ok: failures.append(note)

func actor_ids(container: Node) -> Array[String]:
	var ids: Array[String] = []
	for actor in container.get_children():
		if actor is Item: ids.append(actor.persistent_id)
	ids.sort()
	return ids

func run() -> void:
	check(WorldProfile.new().generation_version == 6 and WorldField.VERSION == 6, "Default/test generation stays v6")
	check(not "starting_shelter" in POIConfig.GENERATION_IDS, "Shelter stays out of the random entrance pool")
	var profile := WorldProfile.new()
	profile.generation_version = 7
	var definition := POIConfig.definition(&"starting_shelter")
	check(definition != null and definition.kind == PoiDefinition.Kind.WALK_IN, "Shelter is a walk-in asset")
	if definition == null:
		quit(1)
		return
	for seed_value in [0, 1, 42, 99]:
		var field := WorldField.new(seed_value, profile)
		var site := field.stop(0)
		check(site.s == 45.0 and site.side == 1.0 and site.definition_id == "starting_shelter", "Fixed v7 opening site")
		check(site.building.origin.is_equal_approx(Vector3(49, 0, -45)), "Fixed shelter origin")
		check((site.building.basis.z).is_equal_approx(Vector3.LEFT), "Open frontage faces west")
		for x in [-27.0, -25.0, -17.0, -10.0, 0.0, 10.0, 17.0, 25.0, 27.0]:
			for z in [-33.0, -30.5, -16.0, 0.0, 14.0, 30.0, 46.0]:
				var point: Vector3 = site.building * Vector3(x, 0, z)
				var sample := field.surface(point.x, point.z)
				check(sample.height >= -0.081 and sample.height <= 0.001 and sample.reserved, "Full authored site is level and clear below concrete tops")
		for x in [-37.0, 37.0]:
			var point: Vector3 = site.building * Vector3(x, 0, -8)
			check(is_equal_approx(field.height_at(point.x, point.z), 5.0), "Side earth banks follow the expanded building footprint")
		for x in [0.0, 12.0, 24.0, 32.0]:
			var point: Vector3 = site.road * Vector3(x, 0, 0)
			check(absf(field.height_at(point.x, point.z)) <= 0.081, "Road-to-forecourt drive remains level")
		# Actual terrain triangles interpolate outside samples at the slab edge.
		# Check their four supporting vertices, not only height queries on concrete.
		for footprint in [Rect2(-10.4, -14.4, 20.8, 28.4), Rect2(-16, 14, 32, 30)]:
			for x in [footprint.position.x, footprint.get_center().x, footprint.end.x]:
				for z in [footprint.position.y, footprint.get_center().y, footprint.end.y]:
					var point: Vector3 = site.building * Vector3(x, 0, z)
					var grid_x := floorf(point.x / profile.terrain_step) * profile.terrain_step
					var grid_z := floorf(point.z / profile.terrain_step) * profile.terrain_step
					for dx in [0.0, profile.terrain_step]:
						for dz in [0.0, profile.terrain_step]:
							check(field.height_at(grid_x + dx, grid_z + dz) <= -0.079, "Slab edge triangle vertices remain recessed")
		for x in [-400.0, -100.0, 100.0, 400.0]:
			check(is_equal_approx(field.height_at(x, 20), 8.0) and field.surface(x, 20).reserved, "Rear roadblock wings backed by clear berm")
		for x in [-25.0, 0.0, 25.0]:
			for z in [14.0, 20.0, 29.0]:
				check(is_zero_approx(field.height_at(x, z)), "Central roadblock collision has level support")
		var legacy := WorldField.new(seed_value)
		check(legacy.stop(0).kind == "entrance" and not legacy.stop(0).has("definition_id"), "v6 retains its original starting entrance")
		for cell in range(4):
			var minor := field.minor_site(cell)
			if not minor.is_empty(): check(minor.id.begins_with("v7:"), "Minor IDs reflect their generation version")
	# Exercise actual loose actors and snapshots without loading the costly world.
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var owner := SiteOwner.new()
	owner.field = WorldField.new(42, profile)
	world.add_child(owner)
	var chunk := Node3D.new()
	owner.add_child(chunk)
	var site := owner.field.stop(0)
	var spawner := POISpawner.new()
	var building := spawner.spawn_site(site, chunk)
	check(building != null, "Starting asset validates and spawns")
	if building != null:
		check(building.find_children("*", "RigidBody3D", true, false).is_empty(), "Static asset owns no loot actors")
		WalkInSites.activate(owner, site, chunk)
		var container := WorldEntities.get_container(owner)
		check(container.get_child_count() == 15, "First visit has three devices and twelve props")
		check(container.get_children().filter(func(actor): return actor is Item).size() == 15, "All starter devices and loot share the Item lifecycle")
		var device_scenes: Array[String] = ["res://equipment/generator.tscn", "res://equipment/crafting_station.tscn", "res://equipment/scrapper.tscn"]
		var found_devices: Array[String] = []
		for actor in container.get_children():
			if actor is Item and actor.scene_file_path in device_scenes:
				found_devices.append(actor.scene_file_path)
				check(not actor.is_fixed and actor.is_large and actor.get_connected_rv() == null, "Starter device remains movable large ground cargo: " + actor.scene_file_path)
		found_devices.sort()
		device_scenes.sort()
		check(found_devices == device_scenes, "Three movable ground devices, exactly one of each service type")
		var picked_id := ""
		for actor in container.get_children():
			check(site.bounds.has_point(actor.global_position), "Starter marker within managed bounds")
			if actor is Item and actor.scene_file_path == "res://props/flashlight.tscn":
				picked_id = actor.persistent_id
				actor.free()
		WalkInSites.activate(owner, site, chunk)
		check(container.get_child_count() == 14, "Repeated activation does not replace picked loot")
		var remaining_ids := actor_ids(container)
		check(not picked_id.is_empty() and picked_id not in remaining_ids, "Picked flashlight excluded")
		WalkInSites.deactivate(owner, site)
		check(container.get_child_count() == 0 and owner.outdoor_sites[site.id].actors.size() == 14, "Props and ground devices snapshot together")
		check(WalkInSites.validation_error({"generation_version": 7, "outdoor_sites": owner.outdoor_sites, "generated_bands": [0]}).is_empty(), "Dormant starter actor snapshots are valid")
		chunk.free()
		chunk = Node3D.new()
		owner.add_child(chunk)
		spawner.spawn_site(site, chunk)
		WalkInSites.activate(owner, site, chunk)
		check(actor_ids(container) == remaining_ids, "Rebuilt shelter restores exactly the remaining actor IDs")
		WalkInSites.deactivate(owner, site)
		owner.outdoor_sites[site.id].actors = []
		WalkInSites.activate(owner, site, chunk)
		check(container.get_child_count() == 0, "Cleared dormant shelter never seeds starter inventory again")
	world.free()
	if failures.is_empty(): print("PASS: v7 starting terrain, fixed inventory and existing outdoor snapshot lifecycle")
	for note in failures: push_error("FAIL: " + note)
	quit(0 if failures.is_empty() else 1)
