extends RefCounted
## Placement, streaming ownership and existing actor persistence share one plan.
const CONTRACTS = preload("res://tests/support/terrain_contracts.gd")
const WAIT = preload("res://tests/support/test_wait.gd")
const NAV_SURFACE = preload("res://tests/support/nav_surface_probe.gd")

class SiteHost extends Node3D:
	var outdoor_sites: Dictionary = {}
	var field: WorldField
	var giant_navigation_map := RID()

static func run(tree: SceneTree, world: Node3D, check: Callable) -> void:
	var fixtures: Array[Dictionary] = []
	for seed_value: int in CONTRACTS.SEEDS:
		_check_plans(seed_value, check, fixtures)
	check.call(not fixtures.is_empty(), "Off-road fixtures contain accepted sites")
	if fixtures.is_empty(): return
	var field := WorldField.new(42, CONTRACTS.profile())
	_check_placement_membership(field, check)
	var selected: Dictionary = {}
	for fixture: Dictionary in fixtures:
		var site: Dictionary = fixture.site
		if site.kind == "walk_in" and str(site.definition_id).begins_with("roadside_camp_"):
			selected = fixture
			break
	check.call(not selected.is_empty(), "Off-road fixtures include a camp for outdoor persistence")
	if not selected.is_empty():
		await _check_build_and_persistence(tree, world, WorldField.new(int(selected.seed), CONTRACTS.profile()), selected.site, check)
	await _check_streaming_seam(tree, world, fixtures, check)

static func _check_plans(seed_value: int, check: Callable, fixtures: Array[Dictionary]) -> void:
	var field := WorldField.new(seed_value, CONTRACTS.profile())
	var reverse := WorldField.new(seed_value, CONTRACTS.profile())
	for row in range(11, -1, -1):
		for column in range(2, -1, -1): reverse.offroad_site(row, column)
	var accepted := 0
	var independent := true
	var legal := true
	var owned := true
	var indexed := true
	var no_driveway := true
	var probes := 0
	var definitions: Dictionary = {}
	for row in range(12):
		var count := 0
		for column in range(3):
			var site := field.offroad_site(row, column)
			independent = independent and site == reverse.offroad_site(row, column)
			if site.is_empty(): continue
			count += 1
			accepted += 1
			fixtures.append({"seed": seed_value, "site": site})
			var origin: Vector3 = site.building.origin
			var definition := POIConfig.definition_for_site(site)
			var problems := PackedStringArray()
			definitions[str(site.definition_id)] = true
			if site.placement != "off_road" or definition == null: problems.append("placement/definition")
			if site.kind not in ["entrance", "walk_in"] or site.has("route") or not site.get("walls", []).is_empty(): problems.append("kind/route/walls")
			if site.id != "v15:%d:offroad:%d:%d" % [seed_value, row, column]: problems.append("identity")
			if site.index != row * 3 + column or not is_equal_approx(float(site.s), -origin.z): problems.append("index/progress")
			var bounds: AABB = site.bounds
			if bounds.position.x <= -field.profile.terrain_half_width or bounds.end.x >= field.profile.terrain_half_width: problems.append("terrain bounds: %s" % bounds)
			var center_surface := field.surface(origin.x, origin.z)
			if not center_surface.reserved or absf(float(center_surface.height) - origin.y) >= 0.12:
				problems.append("root pad height %.4f vs building %.4f, reserved %s, water %s" % [float(center_surface.height), origin.y, center_surface.reserved, center_surface.water_height])
			for corner in [bounds.position, bounds.end, Vector3(bounds.position.x, 0, bounds.end.z), Vector3(bounds.end.x, 0, bounds.position.z)]:
				var road := field.road_query(corner.x, corner.z)
				if float(road.distance) <= float(road.width) * 0.5 + 4.0:
					problems.append("road at AABB corner %s: distance %.3f width %.3f" % [corner, float(road.distance), float(road.width)])
			legal = legal and problems.is_empty()
			if not problems.is_empty(): check.call(false, "%s (%s at %s): %s" % [site.id, site.definition_id, origin, "; ".join(problems)])
			var band := floori(float(site.s) / field.profile.chunk_length)
			var occurrences := 0
			for neighbour in range(band - 1, band + 2):
				for found: Dictionary in field.stops_in_band(neighbour):
					if found.id == site.id:
						occurrences += 1
						owned = owned and neighbour == band
			owned = owned and occurrences == 1
			indexed = indexed and _has_id(field.sites_near_z(origin.z, 1.0), site.id)
			# A point halfway to the road is beyond the local pad. This catches
			# accidentally retaining the roadside driveway in terrain flattening.
			var road_origin: Vector3 = field.road_query(origin.x, origin.z).frame.origin
			var halfway := origin.lerp(road_origin, 0.5)
			var clear := true
			for other: Dictionary in field.sites_near_z(halfway.z):
				clear = clear and field.court_distance(halfway.x, halfway.z, other) > 18.0
			var sample := field.surface(halfway.x, halfway.z)
			if clear and float(sample.road.distance) > float(sample.road.width) * 0.5 + 20.0 and not is_finite(float(sample.water_height)):
				probes += 1
				no_driveway = no_driveway and float(sample.gravel) == 0.0 and not sample.reserved
		check.call(count <= 3, "Off-road row has a bounded candidate count")
	var label := "v15 seed %d: " % seed_value
	check.call(accepted > 0 and independent, label + "off-road plans survive reverse cell query order")
	check.call(legal, label + "off-road buildings retain unique world-grid identity and clear road/terrain boundaries")
	check.call(owned and indexed, label + "mixed site queries include every off-road site with exactly one owning band")
	check.call(probes > 0 and no_driveway, label + "terrain between isolated sites and the road has no reserved gravel driveway")
	var first := field.sites_near_z(-1800.0, 900.0).duplicate(true)
	field._site_queries.clear()
	field._offroad_sites.clear()
	check.call(first == field.sites_near_z(-1800.0, 900.0), label + "mixed query cache invalidation preserves plans and ordering")
	var mixed := field.sites_near_z(-5400.0, 5400.0)
	var roadside := 0
	var offroad := 0
	for site: Dictionary in mixed:
		if site.placement == "off_road": offroad += 1
		if site.placement == "roadside": roadside += 1
	check.call(roadside > 0 and offroad > 0, label + "longitudinal queries preserve both roadside and off-road placement")
	for id: String in definitions:
		var definition := POIConfig.definition(StringName(id))
		var building := (load(definition.scene_path) as PackedScene).instantiate() as Node3D
		check.call(definition.validate_scene(building).is_empty(), "Selected off-road asset validates: " + id)
		building.free()

static func _check_placement_membership(field: WorldField, check: Callable) -> void:
	var roadside: Dictionary = {}
	var offroad: Dictionary = {}
	for site: Dictionary in field.sites_near_z(-9000.0, 9000.0):
		var definition := POIConfig.definition_for_site(site)
		var flag := PoiDefinition.Placement.OFF_ROAD if site.placement == "off_road" else PoiDefinition.Placement.ROADSIDE
		check.call(definition.supports_placement(flag), "Generated site belongs to its definition's allowed placement: " + str(site.id))
		if definition.kind == PoiDefinition.Kind.INSTANCE_ENTRANCE:
			if site.placement == "off_road": offroad[str(site.definition_id)] = true
			else: roadside[str(site.definition_id)] = true
			check.call(not site.has("route") and site.get("walls", []).is_empty(), "Bunker exterior remains independent of the removed guided forest route")
	check.call(not roadside.is_empty() and not offroad.is_empty(), "Bunkers generate in both roadside and off-road placement pools")
	for id: String in POIConfig.GENERATION_IDS:
		var definition := POIConfig.definition(StringName(id))
		check.call(definition.supports_placement(PoiDefinition.Placement.ROADSIDE) and definition.supports_placement(PoiDefinition.Placement.OFF_ROAD), "Bunker definition supports both placements: " + id)

static func _has_id(sites: Array[Dictionary], identity: String) -> bool:
	for site: Dictionary in sites:
		if site.id == identity: return true
	return false

static func _check_build_and_persistence(tree: SceneTree, world: Node3D, field: WorldField, site: Dictionary, check: Callable) -> void:
	var host := SiteHost.new()
	host.field = field
	host.set_meta("entity_domain", true)
	world.add_child(host)
	var chunk := ChunkGenerator.new()
	chunk.field = field
	chunk.band = floori(float(site.s) / field.profile.chunk_length)
	host.add_child(chunk)
	chunk._build_site(site, POISpawner.new())
	check.call(chunk.get_child_count() == 1 and chunk.get_child(0).get_meta("poi_id", "") == site.id, "Off-road chunk site builder creates its asset without generated sign, stripes or walls")
	WalkInSites.activate(host, site, chunk)
	var container := WorldEntities.get_container(host)
	var item := (load("res://props/battery.tscn") as PackedScene).instantiate() as Item
	container.add_child(item)
	item.global_position = site.building * Vector3(0, 1, 0)
	var identity := item.persistent_id
	var count := container.get_child_count()
	WalkInSites.activate(host, site, chunk)
	check.call(container.get_child_count() == count, "Repeated off-road activation cannot duplicate first-visit actors")
	WalkInSites.deactivate(host, site)
	var saved: Dictionary = host.outdoor_sites[site.id].duplicate(true)
	var captured := false
	for actor: Dictionary in saved.actors:
		if actor.kind == "item" and actor.state.id == identity: captured = true
	check.call(not saved.loaded and captured, "Off-road unload captures a player-dropped Item through existing spatial ownership")
	WalkInSites.activate(host, site, chunk)
	var restored := 0
	for actor in container.get_children():
		if actor is Item and actor.persistent_id == identity: restored += 1
	check.call(host.outdoor_sites[site.id].loaded and restored == 1, "Off-road revisit restores the same dropped Item exactly once")
	host.queue_free()
	await tree.process_frame

static func _check_streaming_seam(tree: SceneTree, world: Node3D, fixtures: Array[Dictionary], check: Callable) -> void:
	var selected: Dictionary = {}
	var field: WorldField
	var fields: Dictionary = {}
	var seam := 0
	var probe := Vector3.ZERO
	for fixture: Dictionary in fixtures:
		if not fields.has(fixture.seed): fields[fixture.seed] = WorldField.new(int(fixture.seed), CONTRACTS.profile())
		field = fields[fixture.seed]
		var site: Dictionary = fixture.site
		var bounds: AABB = site.bounds
		var candidate := roundi(float(site.s) / field.profile.chunk_length)
		var z := -candidate * field.profile.chunk_length
		if bounds.position.z >= z or bounds.end.z <= z: continue
		for side: float in [-1.0, 1.0]:
			var x := bounds.get_center().x + side * (bounds.size.x * 0.5 + 16.0)
			var before := field.surface(x, z + 4.0)
			var after := field.surface(x, z - 4.0)
			if before.reserved or after.reserved or is_finite(float(before.water_height)) or is_finite(float(after.water_height)): continue
			if absf(float(before.height) - float(after.height)) > 1.0: continue
			if field.normal_at(x, z + 4.0).y < 0.95 or field.normal_at(x, z - 4.0).y < 0.95: continue
			selected = site
			seam = candidate
			probe = Vector3(x, 0, z)
			break
		if not selected.is_empty(): break
	check.call(not selected.is_empty(), "Off-road fixture crosses a streaming seam beside walkable natural ground")
	if selected.is_empty(): return
	var host := SiteHost.new()
	host.giant_navigation_map = world.giant_navigation_map
	world.add_child(host)
	var chunks: Array[ChunkGenerator] = []
	var building_count := 0
	for band: int in [seam - 1, seam]:
		var chunk := ChunkGenerator.new()
		chunk.field = field
		chunk.band = band
		chunk.sites = field.stops_in_band(band)
		chunk.set_meta("skip_actors", true)
		host.add_child(chunk)
		chunks.append(chunk)
		await chunk._build_ground(false)
		chunk._build_road()
		await TerrainCrossings.build(chunk, false)
		for site: Dictionary in chunk.sites: chunk._build_site(site, POISpawner.new())
		for child in chunk.get_children():
			if child.get_meta("poi_id", "") == selected.id: building_count += 1
		await chunk._build_navigation(false)
	check.call(building_count == 1, "A real off-road building crossing a seam is instantiated only by its owning chunk")
	if not await WAIT.navigation_ready(tree, chunks):
		check.call(false, "Off-road neighbouring chunk navigation bake/publication timed out")
	else:
		var start := Vector3(probe.x, field.height_at(probe.x, probe.z + 4.0), probe.z + 4.0)
		var finish := Vector3(probe.x, field.height_at(probe.x, probe.z - 4.0), probe.z - 4.0)
		var map := chunks[0].navigation.get_navigation_map()
		var nav_start := NAV_SURFACE.point_at(chunks, start)
		var nav_finish := NAV_SURFACE.point_at(chunks, finish)
		check.call(nav_start.is_finite() and nav_finish.is_finite(), "Off-road seam natural-ground endpoints have baked XZ coverage (%s, seam %d, physical %s -> %s, baked %s -> %s)" % [selected.id, seam, start, finish, nav_start, nav_finish])
		if nav_start.is_finite() and nav_finish.is_finite():
			var path := NavigationServer3D.map_get_path(map, nav_start, nav_finish, true)
			check.call(path.size() >= 2 and Vector2(path[0].x - start.x, path[0].z - start.z).length() < 1.0 and Vector2(path[-1].x - finish.x, path[-1].z - finish.z).length() < 1.0, "Published navigation connects natural ground across a seam beside an actual off-road building (%s, seam %d, physical %s -> %s, baked %s -> %s, path %s)" % [selected.id, seam, start, finish, nav_start, nav_finish, path])
	host.queue_free()
	await tree.process_frame
