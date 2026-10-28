extends RefCounted
## Closed exterior plans, shared build ownership and streamed navigation.
const PLAN = preload("res://world/megashelter/megashelter_plan.gd")
const KIT = preload("res://world/megashelter/megashelter_kit.gd")
const WAIT = preload("res://tests/support/test_wait.gd")
const NAV_SURFACE = preload("res://tests/support/nav_surface_probe.gd")

class NavigationHost extends Node3D:
	var giant_navigation_map := RID()
	var field: WorldField
	var outdoor_sites: Dictionary = {}

class SeamField extends WorldField:
	var fixture: Dictionary = {}

	func sites_near_z(_z: float, _radius: float = 240.0) -> Array[Dictionary]:
		return [fixture] if not fixture.is_empty() else []

	func height_at(_x: float, _z: float) -> float:
		return 0.0

static func run(tree: SceneTree, world: Node3D, check: Callable) -> void:
	_check_generation(check)
	for seed_value in range(64):
		var plan: Dictionary = PLAN.generate(seed_value)
		_check_plan(plan,seed_value,check)
		check.call(plan == PLAN.generate(seed_value),"Growth seed %d reproduces every module and collider" % seed_value)
	_check_seed_diversity(check)
	_check_custom_heights(check)
	for seed_value in range(8): _check_build(PLAN.generate(seed_value),check)
	await _check_streaming_navigation(tree,world,PLAN.generate(0),check)

static func _check_generation(check: Callable) -> void:
	var accepted := 0
	var ids := {}
	for seed_value in [6, 42, 913, 2026]:
		var field := WorldField.new(seed_value)
		var reverse := WorldField.new(seed_value)
		for row in range(37, 1, -1): reverse.megashelter_site(row)
		check.call(field.megashelter_site(0).is_empty(), "Megashelters stay outside the opening area")
		for row in range(2, 38):
			var site := field.megashelter_site(row)
			check.call(site == reverse.megashelter_site(row), "Megashelter placement survives reversed query order: %d/%d" % [seed_value, row])
			if site.is_empty(): continue
			accepted += 1
			check.call(not ids.has(site.id), "Megashelters retain unique stable identities")
			ids[site.id] = true
			var envelope: AABB = site.building * (site.local_site_bounds as AABB).grow(20.0)
			check.call(envelope.position.x >= -440.0 and envelope.end.x <= 440.0 and envelope.position.z >= -(row + 1) * 300.0 and envelope.end.z <= -row * 300.0, "Large-building terrain blend fits its row and terrain strip")
			var band := floori(float(site.s) / field.profile.chunk_length)
			var occurrences := 0
			for neighbour in range(band - 1, band + 2):
				for found: Dictionary in field.stops_in_band(neighbour):
					if found.id == site.id:
						occurrences += 1
						check.call(neighbour == band, "Megashelter belongs to the chunk containing its root")
			check.call(occurrences == 1, "Megashelter has exactly one streamed owner")
			for other: Dictionary in field.sites_near_z(-float(site.s)):
				if other.id == site.id: continue
				var local_bounds: AABB = other.get("local_site_bounds", POIConfig.definition_for_site(other).site_bounds)
				var bounds: AABB = other.building * local_bounds.grow(20.0)
				check.call(not OffroadSites._intersects_xz(envelope, bounds), "Megashelter terrain blend avoids existing sites")
			var surface := field.surface(site.building.origin.x, site.building.origin.z)
			check.call(surface.reserved and absf(float(surface.height) - site.building.origin.y) < 0.12, "Generated megashelter remains grounded on its reserved pad")
	# Four fixed seeds over 72 chunks each: measure accepted sites, including
	# terrain rejection, rather than asserting the candidate probability.
	var spacing := 288.0 / maxi(1, accepted)
	check.call(spacing >= 3.0 and spacing <= 5.0, "Sampled megashelter density stays near one per 3-5 chunks: %.2f" % spacing)
	print("MEGASHELTER_DENSITY chunks=288 accepted=", accepted, " mean_chunks=", spacing)

static func _check_plan(plan: Dictionary, seed_value: int, check: Callable) -> void:
	var label := "Megashelter seed %d: " % seed_value
	check.call(plan.version == 5 and plan.seed == seed_value and not plan.has("template") and plan.growth_steps.size() >= 2, label + "versioned plan retains its seed and a grown assembly without a template ID")
	check.call(plan.structure in range(5) and plan.style in range(3), label + "structural treatment and facade style use separate valid choices")
	check.call(plan.width in [48.0, 56.0, 64.0] and plan.depth in [32.0, 40.0, 48.0] and plan.height in [54.0, 67.5, 81.0], label + "default dimensions retain the configured envelope choices")
	var building: AABB = plan.building_bounds
	var site: AABB = plan.site_bounds
	var maximum := POIConfig.definition(&"modular_megashelter").building_bounds
	check.call(building.position.is_finite() and building.size.is_finite() and building.size.x > 0.0 and building.size.y > 0.0 and building.size.z > 0.0 and maximum.encloses(building) and plan.width <= 64.0 and plan.depth <= 48.0 and plan.height <= 81.0, label + "structural dimensions and facade extents fit the declared maximum")
	check.call(site.encloses(building) and site.has_point(plan.access_point), label + "site bounds contain the structure and front approach")
	check.call(not plan.volumes.is_empty() and not plan.modules.is_empty() and not plan.collision_boxes.is_empty(), label + "plan contains structural, visual and physical members")
	var enclosed := true
	var supported := true
	var non_overlapping := true
	var footprint_area := 0.0
	for volume: AABB in plan.volumes:
		footprint_area += volume.size.x * volume.size.z
		enclosed = enclosed and volume.size.x > 0.0 and volume.size.y > 0.0 and volume.size.z > 0.0 and building.grow(0.001).encloses(volume) and volume in plan.collision_boxes
		# Structural masses are closed solid boxes. Upper blocks must touch an
		# underlying mass; decorative ribs and service fittings are separate.
		var contact := volume.position.y <= 0.01
		for lower: AABB in plan.volumes:
			if lower == volume: continue
			non_overlapping = non_overlapping and not lower.grow(-0.001).intersects(volume.grow(-0.001))
			if absf(lower.end.y - volume.position.y) < 0.01 and _contains_xz(lower, volume): contact = true
		supported = supported and contact
	check.call(enclosed and supported and non_overlapping, label + "closed structural masses meet without overlap, fully support upper footprints and retain complete collision")
	check.call(_connected_ground_footprint(plan.volumes), label + "structural wings form one connected footprint through shared faces")
	check.call(footprint_area < float(plan.width * plan.depth) - 0.01, label + "the footprint leaves genuine exterior space instead of filling one rectangular slab")
	var unique: Dictionary = {}
	var modules_valid := true
	var solid_modules_valid := true
	var solid_kinds: Dictionary = {}
	for module: Dictionary in plan.modules:
		var pose: Transform3D = module.transform
		var size: Vector3 = module.size
		var id := str(module.id)
		modules_valid = modules_valid and not id.is_empty() and not unique.has(id) and not str(module.kind).is_empty() and module.variant is int and pose.is_finite() and size.is_finite() and size.x > 0.0 and size.y > 0.0 and size.z > 0.0
		var pieces: Array[Dictionary] = KIT.pieces(module.kind, size, module.variant)
		modules_valid = modules_valid and module.kind in PLAN.KINDS and not pieces.is_empty()
		for piece: Dictionary in pieces:
			modules_valid = modules_valid and piece.center.is_finite() and piece.size.is_finite() and piece.size.x > 0.0 and piece.size.y > 0.0 and piece.size.z > 0.0 and building.grow(0.01).encloses(pose * AABB(piece.center - piece.size * 0.5, piece.size))
		if module.kind in ["pier", "roof_plant", "drain"]:
			solid_kinds[module.kind] = true
			solid_modules_valid = solid_modules_valid and module.get("solid", false)
		if module.get("solid", false):
			solid_modules_valid = solid_modules_valid and PLAN.module_bounds(module) in plan.collision_boxes
		unique[id] = true
	check.call(modules_valid, label + "module identities, transforms and bounds are finite, unique and enclosed")
	check.call(solid_modules_valid and solid_kinds.has("roof_plant") and solid_kinds.has("drain"), label + "structural fittings and service equipment retain their complete solid module collision envelopes")
	var collision_enclosed := true
	for box: AABB in plan.collision_boxes:
		collision_enclosed = collision_enclosed and box.size.x > 0.0 and box.size.y > 0.0 and box.size.z > 0.0 and building.grow(0.01).encloses(box)
	check.call(collision_enclosed, label + "closed-door collision remains inside declared bounds")
	_check_facade_and_equipment_clearance(plan, label, check)

static func _check_custom_heights(check: Callable) -> void:
	# Valid floor-aligned profiles need not be multiples of a facade band.
	var profile := MegashelterProfile.new()
	profile.widths = PackedInt32Array([56])
	profile.depths = PackedInt32Array([40])
	for height: float in [58.5, 63.0, 72.0]:
		profile.heights = PackedFloat32Array([height])
		check.call(profile.validate().is_empty(), "Megashelter custom height %.1f is a valid authoring profile" % height)
		for sample in range(8):
			var plan: Dictionary = PLAN.generate(42+sample,profile)
			_check_facade_and_equipment_clearance(plan, "Megashelter height %.1f sample %d: " % [height, sample], check)

static func _check_facade_and_equipment_clearance(plan: Dictionary, label: String, check: Callable) -> void:
	var walls_backed := true
	var equipment_clear := true
	for module: Dictionary in plan.modules:
		if module.kind in ["wall", "rib_wall"]:
			# Facades sit just outside the solid boundary. Probe through their
			# thickness to identify the actual wing supporting this wall band.
			var probe: Vector3 = module.transform * Vector3(0, 0, -2.25)
			var backed := false
			for volume: AABB in plan.volumes:
				if _contains_xz(volume, AABB(probe, Vector3.ZERO)):
					backed = backed or volume.end.y + 0.01 >= module.transform.origin.y + module.size.y
			walls_backed = walls_backed and backed
		elif module.kind == "roof_plant":
			var plant: AABB = PLAN.module_bounds(module)
			for volume: AABB in plan.volumes:
				if volume.end.y <= plant.position.y: continue
				# Taller wings carry outward facade fittings. Their horizontal
				# clearance must remain free all the way down to the plant roof.
				var facade := AABB(volume.position - Vector3(3.15, 0, 3.15), volume.size + Vector3(6.3, 0, 6.3))
				equipment_clear = equipment_clear and not facade.intersects(plant.grow(-0.001))
	check.call(walls_backed, label + "every facade wall band ends at or below its backing wing roof")
	check.call(equipment_clear, label + "roof equipment clears taller wings and their projecting facade fittings")

static func _check_seed_diversity(check: Callable) -> void:
	var profile := MegashelterProfile.new()
	profile.widths = PackedInt32Array([56])
	profile.depths = PackedInt32Array([40])
	profile.heights = PackedFloat32Array([67.5])
	var silhouettes: Dictionary = {}
	var counts: Dictionary = {}
	var combinations: Dictionary = {}
	for seed_value in range(128):
		var plan: Dictionary = PLAN.generate(seed_value,profile)
		silhouettes[_footprint_signature(plan.volumes)] = true
		counts[plan.growth_steps.size()] = true
		combinations[Vector2i(plan.structure,plan.style)] = true
		_check_growth_trace(plan,check)
	print("MEGASHELTER_GROWTH_DIVERSITY samples=128 canonical_footprints=",silhouettes.size()," module_counts=",counts.keys()," structure_palette_pairs=",combinations.size())
	check.call(silhouettes.size() >= 48,"Growth creates at least48 distinct footprints after discarding heights, translation, rotation and reflection")
	check.call(counts.size() >= 3 and combinations.size() == 15,"Growth has variable assembly length and independently combines all structure/palette pairs")

static func _check_growth_trace(plan: Dictionary,check: Callable) -> void:
	var steps: Array = plan.growth_steps
	var valid := true
	var expected_area := 0.0
	for index in range(steps.size()):
		var step: Dictionary = steps[index]
		var rect: Rect2i = step.rect
		expected_area += rect.get_area()*16.0
		valid = valid and Rect2i(0,0,int(plan.width/4),int(plan.depth/4)).encloses(rect)
		if index == 0:
			valid = valid and step.parent == -1 and rect.end.y == int(plan.depth/4) and rect.size.x >= 4
		else:
			valid = valid and step.parent >= 0 and step.parent < index
			var parent: Rect2i = steps[step.parent].rect
			var contact_x := mini(rect.end.x,parent.end.x)-maxi(rect.position.x,parent.position.x)
			var contact_z := mini(rect.end.y,parent.end.y)-maxi(rect.position.y,parent.position.y)
			valid = valid and ((contact_x >= 2 and (rect.end.y == parent.position.y or rect.position.y == parent.end.y)) or (contact_z >= 2 and (rect.end.x == parent.position.x or rect.position.x == parent.end.x)))
		for earlier in range(index): valid = valid and not rect.intersects(steps[earlier].rect)
	var actual_area := 0.0
	for volume: AABB in plan.volumes: actual_area += volume.size.x*volume.size.z
	check.call(valid and is_equal_approx(expected_area,actual_area),"Each growth module attaches by a full face to an earlier parent and contributes real occupied area")
	var approach := AABB(plan.access_point+Vector3(-1,0,-1),Vector3(2,3,2))
	for box: AABB in plan.collision_boxes: valid = valid and not approach.intersects(box)
	check.call(valid,"Growth keeps the front approach free of solid geometry")

static func _footprint_signature(volumes: Array) -> String:
	var cells: Array[Vector2i] = []
	for volume: AABB in volumes:
		for z in range(roundi(volume.position.z/4),roundi(volume.end.z/4)):
			for x in range(roundi(volume.position.x/4),roundi(volume.end.x/4)): cells.append(Vector2i(x,z))
	var signatures: Array[String] = []
	for turn in range(4):
		for mirror in range(2):
			var points: Array[Vector2i] = []
			var minimum := Vector2i(10000,10000)
			for cell in cells:
				var point := Vector2i(-cell.x if mirror else cell.x,cell.y)
				for rotation_index in range(turn): point = Vector2i(-point.y,point.x)
				points.append(point)
				minimum = minimum.min(point)
			var encoded: Array[String] = []
			for point in points: encoded.append("%d,%d" % [point.x-minimum.x,point.y-minimum.y])
			encoded.sort()
			signatures.append(";".join(encoded))
	signatures.sort()
	return signatures[0]

static func _check_build(plan: Dictionary, check: Callable) -> void:
	var site := _site(plan)
	var visual := POIConfig.instantiate_site(site, true)
	var collision := POIConfig.instantiate_site(site, false)
	var definition := POIConfig.definition_for_site(site)
	check.call(visual != null and collision != null and definition != null, "Megashelter shared factory builds visual and neighbour-only instances")
	if visual == null or collision == null or definition == null:
		if visual != null: visual.free()
		if collision != null: collision.free()
		return
	check.call(definition.validate_scene(visual).is_empty() and definition.validate_scene(collision).is_empty(), "Both megashelter build modes satisfy the POI scene contract")
	check.call(definition.kind == PoiDefinition.Kind.WALK_IN and definition.placement_modes == PoiDefinition.Placement.OFF_ROAD and definition.enemy_count_range == Vector2i.ZERO and definition.content_version == 5 and definition.content_version == plan.version, "Megashelter is a versioned peaceful wilderness walk-in definition")
	check.call(_collision_snapshot(visual) == _collision_snapshot(collision) and _collision_snapshot(visual).size() == plan.collision_boxes.size(), "Owner and neighbour consume identical complete collision plans")
	var expected: Array = []
	for box: AABB in plan.collision_boxes:
		expected.append([Transform3D(Basis.IDENTITY, box.get_center()), box.size, false, true])
	check.call(_collision_snapshot(visual) == expected, "Megashelter physical boxes exactly match their declared plan")
	check.call(visual.get_meta("navigation_solid_geometry", false) and collision.get_meta("navigation_solid_geometry", false), "Both megashelter factory modes declare closed solid navigation geometry")
	check.call(not visual.find_children("*", "MeshInstance3D", true, false).is_empty() and collision.find_children("*", "MeshInstance3D", true, false).is_empty(), "Neighbour factory omits only visual mesh construction")
	var bounds_ok := true
	var shapes_solid := true
	for mesh: MeshInstance3D in visual.get_node("Visuals").find_children("*", "MeshInstance3D", true, false):
		bounds_ok = bounds_ok and (plan.building_bounds as AABB).grow(0.02).encloses(_local_pose(visual, mesh) * mesh.get_aabb())
	for mesh: MeshInstance3D in visual.get_node("Furnishings").find_children("*", "MeshInstance3D", true, false):
		bounds_ok = bounds_ok and (plan.site_bounds as AABB).grow(0.02).encloses(_local_pose(visual, mesh) * mesh.get_aabb())
	for shape: CollisionShape3D in visual.find_children("*", "CollisionShape3D", true, false):
		shapes_solid = shapes_solid and shape.shape is BoxShape3D and not shape.disabled and shape.get_meta("navigation_solid", false)
	check.call(bounds_ok and shapes_solid, "Megashelter rendered extents are enclosed and every static box excludes interior navigation")
	check.call(visual.get_node("LootSpawns").get_child_count() == 0 and visual.find_children("*", "PoiEntrance", true, false).is_empty() and visual.find_children("*", "PoiLootPoint", true, false).is_empty() and visual.find_children("*", "CharacterBody3D", true, false).is_empty(), "Exterior-only megashelter creates no loot, actors or transition entrance")
	var before := _collision_snapshot(visual)
	visual.configure_exterior(plan, true)
	check.call(before == _collision_snapshot(visual), "Reconfiguring a megashelter is idempotent")
	visual.free()
	collision.free()
	var reloaded := POIConfig.instantiate_site(site, true)
	check.call(before == _collision_snapshot(reloaded), "Unloading and reloading a megashelter retains exact physical geometry")
	reloaded.free()

static func _site(plan: Dictionary) -> Dictionary:
	var pose := Transform3D(Basis.IDENTITY, Vector3(0, 0, -150))
	return {"index": 1, "id": "v18:42:offroad:fixture", "s": 150.0, "building": pose, "frame": pose,
		"bounds": pose * (plan.site_bounds as AABB), "placement": "off_road", "definition_id": "modular_megashelter",
		"kind": "walk_in", "title": "Abandoned Megashelter", "seed": plan.seed, "walls": [], "exterior_plan": plan}

static func _collision_snapshot(building: Node3D) -> Array:
	var result: Array = []
	for shape: CollisionShape3D in building.find_children("*", "CollisionShape3D", true, false):
		if shape.shape is BoxShape3D:
			result.append([_local_pose(building, shape), shape.shape.size, shape.disabled, shape.get_meta("navigation_solid", false)])
	return result

static func _visual_snapshot(building: Node3D) -> Array:
	var result: Array = []
	for layer: String in ["Visuals", "Furnishings"]:
		for visual: MeshInstance3D in building.get_node(layer).find_children("*", "MeshInstance3D", true, false):
			var surfaces: Array = []
			for index in range(visual.mesh.get_surface_count()):
				var material := visual.mesh.surface_get_material(index)
				var appearance: Array = [material.get_class() if material != null else ""]
				if material is ShaderMaterial:
					appearance.append_array([material.shader.resource_path, material.get_shader_parameter("base_color"), material.get_shader_parameter("surface_kind"), material.get_shader_parameter("wear_seed")])
					for parameter in ["concrete_texture", "coating_texture", "aggregate_texture"]:
						var texture = material.get_shader_parameter(parameter)
						appearance.append(texture.resource_path if texture is Texture2D else "missing:" + parameter)
				surfaces.append([visual.mesh.surface_get_arrays(index), appearance])
			result.append([str(building.get_path_to(visual)), _local_pose(building, visual), visual.mesh.get_aabb(), surfaces])
	return result

static func _local_pose(building: Node3D, child: Node3D) -> Transform3D:
	var pose := child.transform
	var parent := child.get_parent()
	while parent != building:
		if parent is Node3D: pose = parent.transform * pose
		parent = parent.get_parent()
	return pose

static func _contains_xz(a: AABB, b: AABB) -> bool:
	return a.position.x <= b.position.x + 0.01 and a.end.x >= b.end.x - 0.01 and a.position.z <= b.position.z + 0.01 and a.end.z >= b.end.z - 0.01

static func _connected_ground_footprint(volumes: Array) -> bool:
	if volumes.is_empty(): return false
	var reached: Array[int] = [0]
	var cursor := 0
	while cursor < reached.size():
		var current: AABB = volumes[reached[cursor]]
		cursor += 1
		for index in range(volumes.size()):
			if index in reached: continue
			var other: AABB = volumes[index]
			var overlap_x := minf(current.end.x, other.end.x) - maxf(current.position.x, other.position.x)
			var overlap_z := minf(current.end.z, other.end.z) - maxf(current.position.z, other.position.z)
			var touch_x := absf(current.end.x - other.position.x) < 0.01 or absf(other.end.x - current.position.x) < 0.01
			var touch_z := absf(current.end.z - other.position.z) < 0.01 or absf(other.end.z - current.position.z) < 0.01
			if (touch_x and overlap_z > 0.01) or (touch_z and overlap_x > 0.01): reached.append(index)
	return reached.size() == volumes.size()

static func _check_streaming_navigation(tree: SceneTree, world: Node3D, plan: Dictionary, check: Callable) -> void:
	# A controlled level fixture isolates both production navigation branches:
	# band 1 owns the actual POI; band 0 imports its collision from the plan.
	# Ground, forest RNG and bridge geometry have their own existing fixtures.
	var settings := WorldProfile.new()
	settings.terrain_half_width = 60.0
	var field := SeamField.new(42, settings)
	field.fixture = _site(plan)
	for band in range(-1, 3): field.forest_cache[band] = [] as Array[Dictionary]
	var host := NavigationHost.new()
	host.giant_navigation_map = world.giant_navigation_map
	host.field = field
	host.set_meta("entity_domain", true)
	world.add_child(host)
	var chunks: Array[ChunkGenerator] = []
	var owners := 0
	for band: int in [0, 1]:
		var chunk := ChunkGenerator.new()
		chunk.field = field
		chunk.band = band
		chunk.sites = field.stops_in_band(band)
		chunk.set_meta("skip_actors", true)
		host.add_child(chunk)
		chunks.append(chunk)
		_add_floor(chunk, band)
		var road := Node3D.new()
		road.name = "Road"
		road.add_child(StaticBody3D.new())
		chunk.add_child(road)
		for site: Dictionary in chunk.sites:
			var exterior := chunk._build_site(site, POISpawner.new(), false)
			check.call(exterior.get_node("Visuals").get_child_count() == 0 and _collision_snapshot(exterior).size() == plan.collision_boxes.size(), "Sliced megashelter starts with complete collision before building any visual mesh")
			var collision_before := _collision_snapshot(exterior)
			var first_frame := Engine.get_process_frames()
			chunk._slice_start = Time.get_ticks_usec() - ChunkGenerator.SLICE_BUDGET_USEC
			await exterior.build_visuals_gradual(chunk)
			var immediate := POIConfig.instantiate_site(site, true)
			check.call(Engine.get_process_frames() > first_frame and _visual_snapshot(exterior) == _visual_snapshot(immediate), "Sliced megashelter yields a frame and preserves every immediate mesh array, transform and material kind")
			check.call(collision_before == _collision_snapshot(exterior) and collision_before == _collision_snapshot(immediate), "Sliced visual construction preserves the complete immediate collision plan")
			immediate.free()
			owners += 1
		await chunk._build_navigation(false)
	check.call(owners == 1, "Megashelter crossing the seam has exactly one owning chunk")
	WalkInSites.activate(host, field.fixture, chunks[1])
	var actors := WorldEntities.get_container(host)
	check.call(actors.get_child_count() == 0 and host.outdoor_sites[field.fixture.id].content_version == plan.version, "First exterior visit records versioned ownership without spawning loot or enemies")
	WalkInSites.deactivate(host, field.fixture)
	WalkInSites.activate(host, field.fixture, chunks[1])
	check.call(actors.get_child_count() == 0 and host.outdoor_sites[field.fixture.id].loaded, "Exterior revisit restores an empty actor state without generating content")
	if not await WAIT.navigation_ready(tree, chunks):
		check.call(false, "Megashelter seam publishes ordinary and giant navigation")
	else:
		for giant: bool in [false, true]:
			var label := "Giant" if giant else "Ordinary"
			var map: RID = host.giant_navigation_map if giant else chunks[0].navigation.get_navigation_map()
			var start := Vector3(-45, 0, -150)
			var finish := Vector3(45, 0, -150)
			var path := NavigationServer3D.map_get_path(map, start, finish, true)
			var connected := path.size() >= 2 and path[0].distance_to(start) < 1.0 and path[-1].distance_to(finish) < 1.0
			check.call(connected, label + " navigation detours around the closed megashelter across both streamed bands")
			if connected:
				var clear := true
				for index in range(1, path.size()):
					for step in range(21):
						var point: Vector3 = path[index - 1].lerp(path[index], step / 20.0) - field.fixture.building.origin
						for box: AABB in plan.volumes:
							clear = clear and not box.grow(-0.05).has_point(point)
				check.call(clear, label + " path contains no segment through a closed structural mass")
			var interior_clear := true
			for volume: AABB in plan.volumes:
				# Probe actual occupied wings; the footprint's center may be a
				# courtyard whose ground must remain available to navigation.
				var interior_point: Vector3 = field.fixture.building * Vector3(volume.get_center().x, 0, volume.get_center().z)
				var interior := NAV_SURFACE.point_at(chunks, interior_point, giant)
				interior_clear = interior_clear and (not interior.is_finite() or absf(interior.y) > 2.0)
			check.call(interior_clear, label + " neither owner nor neighbouring bake leaves navigable ground inside the megashelter")
	host.queue_free()
	await tree.process_frame

static func _add_floor(chunk: ChunkGenerator, band: int) -> void:
	var body := StaticBody3D.new()
	body.name = "FixtureGround"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120, 1, 150)
	shape.shape = box
	shape.position = Vector3(0, -0.5, -band * 150 - 75)
	body.add_child(shape)
	chunk.add_child(body)
