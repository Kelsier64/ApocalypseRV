extends SceneTree
var failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var manager := PoiInstanceManager.new()
	manager.name = "PoiInstances"
	world.add_child(manager)
	var spawner := POISpawner.new()
	for id in ["maintenance_legacy", "maintenance", "warehouse", "pump", "research", "gas_station"]:
		var definition := POIConfig.definition(id)
		var site := {"definition_id": id, "id": "test:" + id, "seed": 42, "building": Transform3D(Basis.IDENTITY, Vector3(60 * world.get_child_count(), 0, 0))}
		var building := spawner.spawn_site(site, world)
		check(building != null, "Registry spawns " + id)
		if building == null: continue
		check(building.get_meta("poi_id") == site.id and building.get_meta("poi_seed") == 42, "Spawn preserves site identity")
		check(building.get_meta("poi_definition_id") == definition.definition_id, "Spawn attaches definition identity")
		check(definition.validate_scene(building).is_empty(), "Scene contract after ready: " + id)
		check(building.is_in_group("poi_entrances") == (definition.kind == PoiDefinition.Kind.INSTANCE_ENTRANCE), "Only instance entrances are registered")
		if definition.kind == PoiDefinition.Kind.INSTANCE_ENTRANCE:
			check(building.get_node("Entrance").entry_requested.get_connections().size() == 1, "Exactly one transition connection")
		else:
			check(building.find_children("*", "RigidBody3D", true, false).is_empty(), "Walk-in asset does not mint loot")
			building.get_node("Visuals").free()
			check(building.has_node("Collision") and building.has_node("AccessPoints/Front"), "Visual replacement preserves walk-in contract")
	check(POIConfig.definition_for_site({}) == POIConfig.definition("maintenance_legacy"), "Missing exterior resolves the existing v2 scene")
	check(POIConfig.definition_for_site({"exterior": "unknown"}) == null, "Unknown definition never silently becomes maintenance")
	check(not "gas_station" in POIConfig.GENERATION_IDS, "Catalog does not change the production spawn pool")
	var invalid := POIConfig.definition("gas_station").duplicate() as PoiDefinition
	invalid.access_paths = [^"missing"]
	var station: Node3D = load(invalid.scene_path).instantiate()
	check(not invalid.validate_scene(station).is_empty(), "Missing access marker rejected")
	invalid.access_paths = [^"AccessPoints/Front"]
	invalid.site_bounds.size = Vector3.ZERO
	check(not invalid.validate().is_empty(), "Invalid site envelope rejected")
	invalid = POIConfig.definition("gas_station").duplicate() as PoiDefinition
	invalid.access_paths = [^"../Outside"]
	check(not invalid.validate_scene(station).is_empty(), "Escaping paths are rejected before scene traversal")
	station.free()
	var custom: Node3D = load(POIConfig.definition("maintenance_legacy").scene_path).instantiate()
	custom.get_node("Entrance").name = "Portal"
	custom.get_node("ReturnPoint").name = "ExitMarker"
	custom.set_meta("poi_entrance_path", ^"Portal")
	custom.set_meta("poi_return_path", ^"ExitMarker")
	world.add_child(custom)
	manager.register_entrance(custom, 123, "test:custom")
	check(custom.get_node("Portal").entry_requested.get_connections().size() == 1, "Instance manager honors the configured entrance path")
	var strict := POIConfig.definition("gas_station")
	var invalid_asset: Node3D = load(strict.scene_path).instantiate()
	var hidden_collision := StaticBody3D.new()
	invalid_asset.get_node("Furnishings/Pump6_9/Visuals").add_child(hidden_collision)
	check(not strict.validate_scene(invalid_asset).is_empty(), "Strict contract catches collision inside nested replaceable visuals")
	invalid_asset.free()
	# Snapshot captured before registry changes, across v2/v3/v4 and four seeds.
	var records: Array = []
	for version in [2, 3, 4]:
		var profile := WorldProfile.new()
		profile.generation_version = version
		for seed_value in [0, 1, 42, 99]:
			var field := WorldField.new(seed_value, profile)
			for index in range(12):
				var site := field.stop(index)
				records.append(site)
				records.append(field.loot_plan(index))
				records.append(field.height_at(site.building.origin.x, site.building.origin.z))
	check(var_to_bytes(records).hex_encode().sha256_text() == "9a0b9c7b180bdf16c6e6a7062403154ae5ab0b056d96ad57b332abc529b4900b", "Existing site transforms, IDs, seeds, routes, terrain and loot remain byte-identical")
	world.free()
	if failures.is_empty():
		print("PASS: unified POI definitions, type routing, validation and legacy site compatibility")
		quit(0)
	else:
		for failure in failures: push_error("FAIL: " + failure)
		quit(1)

func check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
