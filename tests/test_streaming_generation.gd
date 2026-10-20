extends SceneTree
## Slicing must preserve geometry and collision, including every forest trunk.
const WAIT = preload("res://tests/support/test_wait.gd")
const TERRAIN_CONTRACTS = preload("res://tests/support/terrain_contracts.gd")
var failures: Array[String] = []

class TerrainHost extends Node3D:
	var giant_navigation_map := RID()

	func _init() -> void:
		giant_navigation_map = NavigationServer3D.map_create()
		NavigationServer3D.map_set_cell_size(giant_navigation_map, 0.275)
		NavigationServer3D.map_set_cell_height(giant_navigation_map, 0.25)
		NavigationServer3D.map_set_merge_rasterizer_cell_scale(giant_navigation_map, 0.1)
		NavigationServer3D.map_set_edge_connection_margin(giant_navigation_map, 0.8)
		NavigationServer3D.map_set_active(giant_navigation_map, true)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE and giant_navigation_map.is_valid():
			NavigationServer3D.free_rid(giant_navigation_map)
			giant_navigation_map = RID()

func _init() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("FAIL: " + message)

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var reference: Dictionary = {}
	var legacy := WorldProfile.new()
	legacy.generation_version = 6
	for gradual: bool in [false, true]:
		var chunk := ChunkGenerator.new()
		chunk.set_meta("skip_actors", true)
		world.add_child(chunk)
		await chunk.generate(WorldField.new(42, legacy), 0, POISpawner.new(), gradual)
		var ground := chunk.get_node("Ground") as MeshInstance3D
		var body := chunk.get_node("ForestTrunks") as StaticBody3D
		var poses: Array[Transform3D] = []
		for shape: CollisionShape3D in body.get_children():
			poses.append(shape.transform)
			check(shape.shape is BoxShape3D and not shape.disabled, "Trunks retain active box collision")
		check(body.is_inside_tree() and body.collision_layer == 1, "Completed forest participates in physics")
		var snapshot := {"faces": ground.mesh.get_faces(), "trunks": poses, "decorations": chunk.decoration_positions.duplicate()}
		if gradual:
			check(snapshot == reference, "Sliced and immediate generation produce identical ground and forest")
		else:
			reference = snapshot
		if not await WAIT.navigation_ready(self, [chunk]):
			check(false, "Navigation bake/publication timed out (gradual=%s)" % gradual)
			quit(1)
			return
		chunk.queue_free()
		await process_frame
	TERRAIN_CONTRACTS.run(check)
	await _check_crossing_chunk(world)
	await _check_dry_viaduct(world)
	world.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: sliced generation preserves geometry/collision; v13 route and landforms satisfy sampled contracts")
	quit(0 if failures.is_empty() else 1)

func _check_crossing_chunk(world: Node3D) -> void:
	var field := WorldField.new(42, TERRAIN_CONTRACTS.profile())
	var rivers: Array[Dictionary] = field.landforms.rivers_near(-1200.0)
	check(not rivers.is_empty(), "v13 fixture contains a river crossing")
	if rivers.is_empty():
		return
	var crossing: Dictionary = rivers[0]
	var s := float(crossing.s)
	var host := TerrainHost.new()
	world.add_child(host)
	NavigationServer3D.map_set_merge_rasterizer_cell_scale(world.get_world_3d().navigation_map, 0.1)
	var chunk := ChunkGenerator.new()
	chunk.set_meta("skip_actors", true)
	host.add_child(chunk)
	await chunk.generate(field, floori(s / field.profile.chunk_length), POISpawner.new(), true)
	var water := chunk.find_children("*RiverWater*", "MeshInstance3D", true, false)
	check(not water.is_empty(), "v13 crossing chunk builds visible river water")
	for mesh: MeshInstance3D in water:
		check(mesh.mesh != null and mesh.mesh.get_faces().size() >= 6, "River water has real mesh geometry")
		check(mesh.find_children("*", "CollisionShape3D", true, false).is_empty(), "River surface does not become a solid floor")
	_check_terrain_side_seams(chunk)
	_check_rendered_shores(chunk, crossing)
	await _check_water_band_seam(host, chunk)
	check(chunk.has_node("BridgeStructure"), "v13 crossing chunk builds bridge structure")
	check(not chunk.find_children("*BridgeDeck*", "MeshInstance3D", true, false).is_empty(), "v13 crossing chunk builds bridge deck geometry")
	_check_bridge_supports(chunk)
	if not await WAIT.navigation_ready(self, [chunk]):
		check(false, "v13 river/bridge navigation bake/publication timed out")
	else:
		await physics_frame
		var frame := field.road_frame(s)
		var space := world.get_world_3d().direct_space_state
		for side: float in [-1.0, 1.0]:
			var x := side * (field.profile.terrain_half_width - 0.25)
			var z := -chunk.band * field.profile.chunk_length - 75.0
			var height := field.height_at(x, z)
			var ray := PhysicsRayQueryParameters3D.create(Vector3(x, height + 6.0, z), Vector3(x, height - 6.0, z), 1)
			var hit := space.intersect_ray(ray)
			check(not hit.is_empty(), "Physical ground supports actors immediately inside both terrain side boundaries")
			if not hit.is_empty():
				check(absf(float(hit.position.y) - height) < 0.3, "Side-boundary collision matches the continuous terrain surface")
		for lateral: float in [-1.6, 0.0, 1.6]:
			var point: Vector3 = frame.origin + frame.basis.x * lateral
			var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 6.0, point + Vector3.DOWN * 3.0, 1)
			var hit := space.intersect_ray(ray)
			check(not hit.is_empty(), "Bridge supplies physical support across the RV wheel span")
			if not hit.is_empty():
				check(absf(float(hit.position.y) - point.y) < 0.2, "Bridge wheel support matches the drivable road elevation")
			var closest := NavigationServer3D.map_get_closest_point(chunk.navigation.get_navigation_map(), point)
			check(Vector2(closest.x - point.x, closest.z - point.z).length() < 1.0 and absf(closest.y - point.y) < 0.8, "Published navigation crosses the bridge deck above the river")
	host.queue_free()
	await process_frame

func _check_dry_viaduct(world: Node3D) -> void:
	var field := WorldField.new(42, TERRAIN_CONTRACTS.profile())
	var band := -1
	for candidate in range(4, 80):
		var eligible := true
		for offset: float in [10.0, 75.0, 140.0]:
			var s := candidate * field.profile.chunk_length + offset
			eligible = eligible and not field.landforms.river_span_at(s) and field.landforms.bridge_gap(s) > 0.95 and field.landforms.natural_clearance(s) > 5.0
		if eligible:
			band = candidate
			break
	check(band >= 0, "v13 fixture contains a sustained elevated road over a dry valley")
	if band < 0: return
	var host := TerrainHost.new()
	world.add_child(host)
	var chunk := ChunkGenerator.new()
	chunk.field = field
	chunk.band = band
	chunk.set_meta("skip_actors", true)
	host.add_child(chunk)
	# Exercise the production ground, road, structure and navigation builders
	# without generating an unrelated second forest, scenery or actor population.
	await chunk._build_ground(false)
	chunk._build_road()
	await TerrainCrossings.build(chunk, false)
	_check_bridge_supports(chunk)
	await chunk._build_navigation(false)
	if not await WAIT.navigation_ready(self, [chunk]):
		check(false, "Dry viaduct navigation bake/publication timed out")
	else:
		await physics_frame
		var space := world.get_world_3d().direct_space_state
		var supported := true
		for offset in range(5, 150, 10):
			var frame := field.road_frame(band * field.profile.chunk_length + offset)
			for lateral: float in [-1.6, 1.6]:
				var point := frame.origin + frame.basis.x * lateral
				var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 2.0, point + Vector3.DOWN * 2.0, 1)
				var hit := space.intersect_ray(ray)
				supported = supported and not hit.is_empty()
				if not hit.is_empty(): supported = supported and absf(float(hit.position.y) - point.y) < 0.2
		check(supported, "Physical deck supports both RV wheel tracks continuously along the dry viaduct")
		var start := field.road_frame(band * field.profile.chunk_length + 10.0).origin
		var finish := field.road_frame(band * field.profile.chunk_length + 140.0).origin
		var path := NavigationServer3D.map_get_path(chunk.navigation.get_navigation_map(), start, finish, true)
		check(path.size() >= 2 and path[0].distance_to(start) < 1.0 and path[-1].distance_to(finish) < 1.0, "Published navigation connects both ends of the dry viaduct")
		var stays_on_deck := not path.is_empty()
		for point in path:
			var road := field.road_query(point.x, point.z)
			stays_on_deck = stays_on_deck and absf(point.y - float(road.height)) < 0.8
		check(stays_on_deck, "Dry viaduct navigation stays on the deck above the valley floor")
		var middle := field.road_frame(band * field.profile.chunk_length + 77.5)
		var underside_frame := field.road_frame(band * field.profile.chunk_length + 78.1)
		var underside := underside_frame * Vector3(field.road_width(band * field.profile.chunk_length + 78.1) * 0.5 * 0.58, -4.0, 0)
		var girder_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(underside, underside + Vector3.UP * 3.0, 1))
		check(not girder_hit.is_empty() and absf(float(girder_hit.position.y) - (underside_frame.origin.y - 2.11)) < 0.12, "Main girders have physical undersides matching the visible structure: %s" % girder_hit)
		for side: float in [-1.0, 1.0]:
			var inner := middle * Vector3(side * (field.road_width(band * field.profile.chunk_length + 77.5) * 0.5 - 1.0), 0.9, 0.0)
			var outer := inner + middle.basis.x * side * 4.0
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(inner, outer, 1))
			check(not hit.is_empty(), "Dry viaduct has physical vehicle barriers on both exposed edges")
	host.queue_free()
	await process_frame

func _check_bridge_supports(chunk: ChunkGenerator) -> void:
	var structure := chunk.get_node_or_null("BridgeStructure")
	check(structure != null, "Elevated roadway has modeled supporting structure")
	if structure == null: return
	var piers: Array[MeshInstance3D] = []
	var foundations: Array[MeshInstance3D] = []
	var caps: Array[MeshInstance3D] = []
	for member: MeshInstance3D in structure.find_children("*", "MeshInstance3D", true, false):
		if str(member.name).begins_with("Foundation"): foundations.append(member)
		elif str(member.name).begins_with("PierCap"): caps.append(member)
		elif str(member.name).begins_with("Pier"): piers.append(member)
	check(not piers.is_empty() and not foundations.is_empty() and not caps.is_empty(), "Bridge model includes piers, foundations and supporting caps")
	for pier in piers:
		var box := pier.global_transform * pier.mesh.get_aabb()
		var grounded := false
		var capped := false
		for foundation in foundations:
			var footing := foundation.global_transform * foundation.mesh.get_aabb()
			if not _horizontal_overlap(box, footing): continue
			var ground := chunk.field.height_at(footing.get_center().x, footing.get_center().z)
			grounded = grounded or (footing.position.y <= ground + 0.05 and footing.end.y >= box.position.y - 0.05)
		for cap in caps:
			var cap_box := cap.global_transform * cap.mesh.get_aabb()
			if _horizontal_overlap(box, cap_box): capped = capped or cap_box.position.y <= box.end.y + 0.05
		check(grounded, "Each pier contacts a foundation embedded in the actual valley or river bed")
		check(capped, "Each pier reaches its modeled cap beneath the bridge girders")
	var deck := chunk.get_node_or_null("BridgeDeck") as MeshInstance3D
	check(deck != null and deck.mesh != null and deck.mesh.get_aabb().size.y > 0.25, "Bridge deck is a substantial modeled slab")
	check(not structure.find_children("MainGirder*", "MeshInstance3D", true, false).is_empty(), "Bridge deck has longitudinal load bearing girders")

func _horizontal_overlap(a: AABB, b: AABB) -> bool:
	return a.position.x <= b.end.x and b.position.x <= a.end.x and a.position.z <= b.end.z and b.position.z <= a.end.z

func _check_terrain_side_seams(chunk: ChunkGenerator) -> void:
	var ground := chunk.get_node("Ground") as MeshInstance3D
	var distant := chunk.find_children("DistantTerrain*", "MeshInstance3D", false, false)
	check(distant.size() == 2, "River chunk retains both distant terrain sides")
	for side: float in [-1.0, 1.0]:
		var x := side * chunk.field.profile.terrain_half_width
		var near_edge := _vertices_at(ground.mesh.get_faces(), x, true)
		var far_edge: Dictionary = {}
		for mesh: MeshInstance3D in distant:
			far_edge.merge(_vertices_at(mesh.mesh.get_faces(), x, true))
		check(near_edge.size() >= 51 and near_edge == far_edge, "Physical and distant terrain share every vertex at x=%.0fm without a side gap" % x)

func _vertices_at(faces: PackedVector3Array, coordinate: float, use_x: bool) -> Dictionary:
	var vertices: Dictionary = {}
	for point in faces:
		if absf((point.x if use_x else point.z) - coordinate) < 0.001:
			vertices[Vector2i(roundi((point.z if use_x else point.x) * 1000.0), roundi(point.y * 1000.0))] = true
	return vertices

func _check_water_band_seam(host: Node3D, chunk: ChunkGenerator) -> void:
	var water := chunk.get_node("RiverWater") as MeshInstance3D
	var north := -chunk.band * chunk.field.profile.chunk_length
	var seam := north
	var neighbor_band := chunk.band - 1
	var edge := _vertices_at(water.mesh.get_faces(), seam, false)
	if edge.is_empty():
		seam = north - chunk.field.profile.chunk_length
		neighbor_band = chunk.band + 1
		edge = _vertices_at(water.mesh.get_faces(), seam, false)
	check(not edge.is_empty(), "River fixture exercises a water ribbon crossing a streaming boundary")
	if edge.is_empty(): return
	# Only build the crossing geometry: the existing fixture already covers
	# full generation/navigation, and a second forest adds no seam coverage.
	var neighbor := ChunkGenerator.new()
	neighbor.field = chunk.field
	neighbor.band = neighbor_band
	host.add_child(neighbor)
	await TerrainCrossings.build(neighbor, false)
	var adjacent := neighbor.get_node_or_null("RiverWater") as MeshInstance3D
	check(adjacent != null, "Adjacent band owns the continuing river water mesh")
	if adjacent != null:
		check(edge == _vertices_at(adjacent.mesh.get_faces(), seam, false), "Clipped water meshes have identical intersection vertices across the streaming seam")
	neighbor.queue_free()
	await process_frame

func _check_rendered_shores(chunk: ChunkGenerator, river: Dictionary) -> void:
	var north := -chunk.band * chunk.field.profile.chunk_length
	var south := north - chunk.field.profile.chunk_length
	var terrain: Array[PackedVector3Array] = []
	for mesh: MeshInstance3D in chunk.find_children("DistantTerrain*", "MeshInstance3D", false, false):
		terrain.append(mesh.mesh.get_faces())
	var checked := 0
	var exposed := 0
	var dry_bed := 0
	# Sample actual water-segment midpoints between far-terrain columns,
	# where a coarse mesh could bridge over the carved channel completely.
	for index in range(0, ceili(2.0 * TerrainCrossings.WATER_EXTENT / TerrainCrossings.WATER_STEP), 4):
		var x0 := -TerrainCrossings.WATER_EXTENT + index * TerrainCrossings.WATER_STEP
		var polygon := TerrainCrossings.water_polygon(chunk.field.landforms, river, x0, minf(x0 + TerrainCrossings.WATER_STEP, TerrainCrossings.WATER_EXTENT))
		for side: int in [0, 1]:
			var edge := polygon[0].lerp(polygon[1], 0.5) if side == 0 else polygon[3].lerp(polygon[2], 0.5)
			if absf(edge.x) < 520.0 or edge.z < south + 6.0 or edge.z > north - 6.0: continue
			var inside := edge + Vector3(0.0, 0.0, 5.0 if side == 0 else -5.0)
			var bank_height := INF
			var bed_height := INF
			for faces in terrain:
				bank_height = minf(bank_height, _mesh_height(faces, edge))
				bed_height = minf(bed_height, _mesh_height(faces, inside))
			checked += 1
			if not is_finite(bank_height) or bank_height < edge.y - 0.02: exposed += 1
			if not is_finite(bed_height) or bed_height >= edge.y - 0.02: dry_bed += 1
	check(checked > 0, "River fixture samples rendered shoreline in the distant terrain")
	check(exposed == 0, "Distant terrain covers the outer water ribbon edge (%d exposed samples)" % exposed)
	check(dry_bed == 0, "Distant terrain retains a submerged channel beneath visible water (%d dry samples)" % dry_bed)

func _mesh_height(faces: PackedVector3Array, point: Vector3) -> float:
	for index in range(0, faces.size(), 3):
		var a := faces[index]
		var b := faces[index + 1]
		var c := faces[index + 2]
		if point.x < minf(a.x, minf(b.x, c.x)) - 0.001 or point.x > maxf(a.x, maxf(b.x, c.x)) + 0.001: continue
		if point.z < minf(a.z, minf(b.z, c.z)) - 0.001 or point.z > maxf(a.z, maxf(b.z, c.z)) + 0.001: continue
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var ac := Vector2(c.x - a.x, c.z - a.z)
		var ap := Vector2(point.x - a.x, point.z - a.z)
		var determinant := ab.cross(ac)
		if absf(determinant) < 0.000001: continue
		var u := ap.cross(ac) / determinant
		var v := ab.cross(ap) / determinant
		if u >= -0.0001 and v >= -0.0001 and u + v <= 1.0001:
			return a.y + u * (b.y - a.y) + v * (c.y - a.y)
	return INF
