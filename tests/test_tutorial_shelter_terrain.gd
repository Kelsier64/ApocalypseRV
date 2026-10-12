extends SceneTree
## v11 reserves the entire long tutorial building without changing old shelters.
var failures: Array[String] = []

func _init() -> void:
	run.call_deferred()

func check(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)

func run() -> void:
	check(WorldProfile.new().generation_version == 6 and WorldField.VERSION == 6, "Default generation remains v6")
	check(not "tutorial_shelter" in POIConfig.GENERATION_IDS, "Tutorial stays outside the random POI pool")
	var definition := POIConfig.definition(&"tutorial_shelter")
	check(definition != null, "Tutorial definition is registered")
	if definition == null: quit(1); return
	check(definition.scene_path == "res://world/tutorial_shelter/tutorial_shelter.tscn", "v11 selects its dedicated tutorial scene")
	check(definition.kind == PoiDefinition.Kind.WALK_IN and definition.validate().is_empty(), "Tutorial uses the valid walk-in contract")
	check(definition.building_bounds == AABB(Vector3(-30, -0.4, -232), Vector3( 60, 11.4, 246.5)), "Building bounds include the full 236 m interior and exterior shell")
	check(definition.site_bounds == AABB(Vector3(-33, -0.5, -235), Vector3( 66, 12, 281)), "Site bounds include the whole building and apron")
	var legacy_definition := POIConfig.definition(&"starting_shelter")
	check(legacy_definition.scene_path == "res://world/starting_shelter/starting_shelter.tscn" and legacy_definition.building_bounds == AABB(Vector3(-25, -0.4, -30.5), Vector3( 50, 14.4, 45)) and legacy_definition.site_bounds == AABB(Vector3(-27, -0.5, -33), Vector3( 54, 15, 79)), "Old shelter asset and bounds remain unchanged")
	for seed_value in [0, 1, 42, 99]:
		var profile := WorldProfile.new()
		profile.generation_version = 11
		var field := WorldField.new(seed_value, profile)
		var site := field.stop(0)
		check(site.definition_id == "tutorial_shelter" and site.id.begins_with("v11:"), "v11 opening keeps its own asset and site identity")
		check(site.s == 45.0 and site.building.origin.is_equal_approx(Vector3(49, 0, -45)) and site.building.basis.z.is_equal_approx(Vector3.LEFT), "Tutorial keeps the established opening placement and road frontage")
		# Sample every bay, both long side edges and the rear/apron corners.
		for x in [-33.0, -30.0, -20.4, -19.0, 0.0, 19.0, 20.4, 30.0, 33.0]:
			for z in [-235.0, -232.0, -222.4, -192.0, -152.0, -132.0, -108.0, -84.0, -64.0, -44.0, -24.0, 0.0, 14.0, 30.0, 44.0, 46.0]:
				var point: Vector3 = site.building * Vector3(x, 0, z)
				var sample := field.surface(point.x, point.z)
				check(sample.reserved and sample.height <= 0.001 and sample.height >= -0.081, "Full tutorial site is level and excludes vegetation: seed=%d local=(%s,%s)" % [seed_value, x, z])
		# Four vertices support each actual terrain triangle under the slab edge.
		for footprint in [Rect2(-20.4, -222.4, 40.8, 236.4), Rect2(-22, 14, 44, 30)]:
			for x in [footprint.position.x, footprint.get_center().x, footprint.end.x]:
				for fraction in [0.0, 0.125, 0.25, 0.5, 0.75, 0.875, 1.0]:
					var z: float = lerpf(footprint.position.y, footprint.end.y, fraction)
					var point: Vector3 = site.building * Vector3(x, 0, z)
					var grid_x := floorf(point.x / profile.terrain_step) * profile.terrain_step
					var grid_z := floorf(point.z / profile.terrain_step) * profile.terrain_step
					for dx in [0.0, profile.terrain_step]:
						for dz in [0.0, profile.terrain_step]:
							check(field.height_at(grid_x + dx, grid_z + dz) <= -0.079, "Tutorial slab supporting terrain vertices stay recessed: seed=%d local=(%s,%s)" % [seed_value, x, z])
		var generator: Node3D = load("res://world/world_generator.gd").new()
		generator.profile = profile
		generator.field = field
		for local_point in [Vector3(-32, 1, -234), Vector3(32, 1, -234), Vector3(-32, 1, 45), Vector3(32, 1, 45), Vector3(0, 1, -192)]:
			var point: Vector3 = site.building * local_point
			check(site.bounds.has_point(point), "Managed site bounds own every authored corner")
			var pinned: Array = generator.protected_bands(point)
			for band in range(floori(-site.bounds.end.z / 150.0) - 1, floori(-site.bounds.position.z / 150.0) + 2):
				check(band in pinned, "Stream protection retains all site and seam bands from anywhere inside the tutorial")
		generator.free()
		# Exercise the actual deterministic forest planner, not only its surface mask.
		var planner := ChunkGenerator.new()
		planner.field = field
		await ForestScenery.prepare(planner, 0, false)
		for tree in ForestScenery.trees(field, 0):
			var local: Vector3 = site.building.affine_inverse() * tree.point
			check(not (absf(local.x) <= 33 and local.z >= -235 and local.z <= 46), "Forest planner never places a trunk in the authored tutorial reservation")
		planner.free()
		for version in [7, 8, 9, 10]:
			var old_profile := WorldProfile.new()
			old_profile.generation_version = version
			var old_field := WorldField.new(seed_value, old_profile)
			var old_site := old_field.stop(0)
			check(old_site.definition_id == "starting_shelter" and POIConfig.definition_for_site(old_site) == legacy_definition, "v%d retains the original shelter selection" % version)
			var old_floor: Vector3 = old_site.building * Vector3(0, 0, -10)
			check(is_equal_approx(old_field.height_at(old_floor.x, old_floor.z), -0.08), "v%d retains the original recessed garage floor" % version)
			if version < 10: check(is_equal_approx(old_field.height_at(100, 20), 8), "v%d retains the legacy rear berm" % version)
	if failures.is_empty(): print("PASS: v11 tutorial terrain, full vegetation reservation, stream protection and v7-v10 asset preservation")
	quit(0 if failures.is_empty() else 1)
