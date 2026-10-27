extends Node3D
class_name ChunkGenerator
## Fixed world-grid band. Roads curve inside it; the band never rotates.
const CHUNK_SIZE := 150.0
const RAKER_SCENE = preload("res://enemies/raker.tscn")
const TERRAIN_V14 = preload("res://world/terrain/terrain_v14.gdshader")
const SLICE_BUDGET_USEC := 4000
var field: WorldField
var band: int
var sites: Array[Dictionary] = []
var decoration_positions: Array[Vector3] = []
var build_ms: float = 0.0
var max_slice_ms: float = 0.0
var _slice_start: int
var navigation: NavigationRegion3D
var navigation_ready := false
var giant_navigation: NavigationRegion3D
var giant_navigation_ready := true
var _regular_navigation_ready := false
var _terrain: MeshInstance3D
var road_spawns: Dictionary = {}
var _road_monsters_spawned := false
var _navigation_dirty := false
var _navigation_rebuild_timer: Timer
var _navigation_publications: Array[Dictionary] = []

func _enter_tree() -> void:
	if not _navigation_publications.is_empty() and not get_tree().process_frame.is_connected(_poll_navigation_publications):
		get_tree().process_frame.connect(_poll_navigation_publications)

func _exit_tree() -> void:
	if get_tree().process_frame.is_connected(_poll_navigation_publications):
		get_tree().process_frame.disconnect(_poll_navigation_publications)

func generate(data: WorldField, index: int, spawner: POISpawner, gradual: bool = false) -> void:
	_slice_start = Time.get_ticks_usec()
	field = data
	band = index
	name = "TerrainBand_%d" % band
	sites = field.stops_in_band(band)
	await _build_ground(gradual)
	if gradual:
		await _pause()
	_build_road()
	await TerrainCrossings.build(self, gradual)
	road_spawns = RoadSpawns.plan(field, band)
	RoadSpawns.build_static(self, road_spawns)
	for site in sites:
		var sliced_exterior: bool = gradual and site.get("definition_id", "") == "modular_megashelter"
		var exterior := _build_site(site, spawner, not sliced_exterior)
		if sliced_exterior and exterior != null:
			await exterior.build_visuals_gradual(self)
	await ForestScenery.build(self, gradual)
	if gradual:
		await _pause()
	await _build_navigation(gradual)
	_spawn_actors()
	ForestFog.build(self)
	_measure_slice()

func _measure_slice() -> void:
	var elapsed := (Time.get_ticks_usec() - _slice_start) / 1000.0
	build_ms += elapsed
	max_slice_ms = maxf(max_slice_ms, elapsed)
	if elapsed > 12.0 and "--profile-streaming" in OS.get_cmdline_user_args():
		print("STREAM_SLICE ms=%.2f stack=%s" % [elapsed, get_stack()])

func _pause() -> void:
	_measure_slice()
	await get_tree().process_frame
	_slice_start = Time.get_ticks_usec()

func slice_exhausted() -> bool:
	return Time.get_ticks_usec() - _slice_start >= SLICE_BUDGET_USEC

func _build_ground(gradual: bool) -> void:
	var step := field.profile.terrain_step
	var nx := roundi(field.profile.terrain_half_width * 2.0 / step)
	var step_x := field.profile.terrain_half_width * 2.0 / nx
	var nz := roundi(field.profile.chunk_length / step)
	var z0 := -band * field.profile.chunk_length
	var rows: Array = []
	for j in range(-1, nz + 2):
		var row: Array = []
		for i in range(-1, nx + 2):
			row.append(field.surface(-field.profile.terrain_half_width + i * step_x, z0 - j * step))
			if gradual and i % 32 == 0 and slice_exhausted(): await _pause()
		rows.append(row)
		if gradual and slice_exhausted():
			await _pause()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(nz + 1):
		for i in range(nx + 1):
			var sample: Dictionary = rows[j + 1][i + 1]
			var normal := Vector3((float(rows[j + 1][i].height) - float(rows[j + 1][i + 2].height)) * step / step_x, 2.0 * step, float(rows[j + 2][i + 1].height) - float(rows[j][i + 1].height)).normalized()
			var w: Vector3 = sample.weights
			var color := Color(0.38, 0.43, 0.23) * w.x + Color(0.24, 0.32, 0.18) * w.y + Color(0.48, 0.43, 0.33) * w.z
			color = Color("656153") * w.x + Color("515849") * w.y + Color("797369") * w.z
			color = field.landforms.color_at(-z0 + j * step)
			if is_finite(float(sample.water_height)): color = Color("454e43")
			color = color.lerp(Color("716b54"), float(sample.river_bank) * 0.72)
			st.set_normal(normal)
			st.set_color(color)
			st.set_uv(Vector2(sample.gravel, sample.river_bank))
			st.set_uv2(field.landforms.material_weights(sample.appearance))
			st.add_vertex(Vector3(-field.profile.terrain_half_width + i * step_x, sample.height, z0 - j * step))
		if gradual and slice_exhausted():
			await _pause()
	for j in range(nz):
		for i in range(nx):
			var a := j * (nx + 1) + i
			for v in [a, a + nx + 1, a + 1, a + 1, a + nx + 1, a + nx + 2]:
				st.add_index(v)
		if gradual and slice_exhausted(): await _pause()
	_terrain = _mesh(st.commit(), "Ground", true)
	var mat := ShaderMaterial.new()
	mat.shader = TERRAIN_V14
	mat.set_shader_parameter("ground_texture", preload("res://assets/materials/industrial/forest_floor.png"))
	_terrain.material_override = mat
	if gradual:
		await _pause()
	await _build_distant_sides(gradual)

func _build_distant_sides(gradual: bool) -> void:
	var river_detail := not field.landforms.rivers_near(-(band + 0.5) * 150.0, 190.0).is_empty()
	for side in [-1.0, 1.0]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var edge := field.profile.terrain_half_width
		var columns := [edge, edge + 30, edge + 90, edge + 210, edge + 450, edge + 810]
		if river_detail:
			# A 360m-wide far triangle cannot represent a 40m river. Keep the
			# same banks beyond the collision boundary, on a shared 12m grid.
			columns = []
			for i in range(ceili(810.0 / 12.0)):
				columns.append(edge + i * 12.0)
			columns.append(edge + 810.0)
		var stride := columns.size()
		for j in range(51):
			var z := -band * 150.0 - j * 3.0
			for x in columns:
				var sample := field.surface(x * side, z)
				var color := field.landforms.color_at(-z)
				if is_finite(float(sample.water_height)): color = Color("454e43")
				st.set_color(color.lerp(Color("716b54"), float(sample.river_bank) * 0.72))
				st.set_uv(Vector2(sample.gravel, sample.river_bank))
				st.set_uv2(field.landforms.material_weights(sample.appearance))
				st.add_vertex(Vector3(x * side, sample.height, z))
				if gradual and slice_exhausted(): await _pause()
			if gradual and slice_exhausted(): await _pause()
		for j in range(50):
			for i in range(stride - 1):
				var a := j * stride + i
				var indices := [a, a + stride, a + 1, a + 1, a + stride, a + stride + 1] if side > 0 else [a, a + 1, a + stride, a + 1, a + stride + 1, a + stride]
				for v in indices:
					st.add_index(v)
		st.generate_normals()
		var title := "DistantTerrainLeft" if side < 0.0 else "DistantTerrainRight"
		var node := _mesh(st.commit(), title, false)
		node.material_override = _terrain.material_override
		if gradual:
			await _pause()

func _mesh(mesh: ArrayMesh, title: String, collision: bool) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = title
	node.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.98
	node.material_override = mat
	add_child(node)
	if collision:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		shape.shape = mesh.create_trimesh_shape()
		body.add_child(shape)
		node.add_child(body)
	return node

func _build_road() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(61):
		var s := band * 150.0 + i * 2.5
		var frame := field.road_frame(s)
		for side in [-1.0, 1.0]:
			var point: Vector3 = frame.origin + frame.basis.x * side * field.road_width(s) * 0.5
			point.y += 0.07
			st.set_color(Color(0.135, 0.145, 0.14))
			st.add_vertex(point)
	for i in range(60):
		var a := i * 2
		for v in [a, a + 2, a + 1, a + 1, a + 2, a + 3]:
			st.add_index(v)
	st.generate_normals()
	_mesh(st.commit(), "Road", true)
	for i in range(15):
		var s := band * 150.0 + i * 10.0 + 3.0
		var frame := field.road_frame(s)
		var paint := RoadsideKit.part(self, Vector3(0.16, 0.015, 4), frame.origin + Vector3.UP * 0.09, Color(0.76, 0.69, 0.42))
		paint.basis = frame.basis
		var behind := field.road_frame(s - 2).origin
		var ahead := field.road_frame(s + 2).origin
		paint.basis = Basis.looking_at(ahead - behind)
	for i in range(3):
		var s := band * 150.0 + i * 50.0 + 20.0
		var point := field.road_frame(s) * Vector3(14, 0, 0)
		if (field.landforms.bridge_at(s) or field.road_width(s) > 18.0): continue
		if not _near_site(point):
			_place_module("pole", point, field.road_frame(s).basis)
func _near_site(point: Vector3) -> bool:
	for site in field.sites_near_z(point.z):
		if field.court_distance(point.x, point.z, site) < 20:
			return true
	return false

func _place_module(kind: String, point: Vector3, orientation: Basis = Basis.IDENTITY) -> Node3D:
	var node := RoadsideKit.instantiate_module(kind)
	node.transform = Transform3D(orientation, Vector3(point.x, field.height_at(point.x, point.z), point.z))
	add_child(node)
	return node

func _build_site(site: Dictionary, spawner: POISpawner, include_visuals: bool = true) -> Node3D:
	var exterior: Node3D
	if site.kind in ["entrance", "walk_in"]:
		exterior = spawner.spawn_site(site, self, include_visuals)
	else:
		_place_module(site.kind, site.building.origin, site.building.basis)
	# Standalone entrances and wild sites have no road advertising or approach.
	if site.get("placement", "roadside") == "off_road" or site.kind == "entrance": return exterior
	var sign_pos: Vector3 = site.road * Vector3(float(site.side) * 12.0, 0, 21.0)
	var sign_node := _place_module("sign", sign_pos, site.road.basis)
	var title := str(site.get("title", "LAY-BY"))
	if site.get("definition_id", "") == "gas_station": title = "NORTHLINE\nGAS / SERVICE"
	RoadsideKit.label(sign_node, title, Vector3(0, 3.4, 0.08), 24)
	for side in [-1.0, 1.0]:
		var point: Vector3 = site.frame * Vector3(side * 6.2, 0.05, 0)
		var stripe := RoadsideKit.part(self, Vector3(0.15, 0.03, 24), point, Color(0.72, 0.64, 0.43))
		stripe.basis = site.frame.basis
	for i in range(3):
		var point: Vector3 = site.building * Vector3(0, 0.06, 7.5 + i)
		var stripe := RoadsideKit.part(self, Vector3(2, 0.03, 0.25), point, Color(0.70, 0.65, 0.49))
		stripe.basis = site.building.basis
	return exterior

func request_navigation_rebuild() -> void:
	_navigation_dirty = true
	if _navigation_rebuild_timer == null:
		_navigation_rebuild_timer = Timer.new()
		_navigation_rebuild_timer.one_shot = true
		_navigation_rebuild_timer.timeout.connect(_rebuild_navigation)
		add_child(_navigation_rebuild_timer)
	_navigation_rebuild_timer.start(0.35)

func _rebuild_navigation() -> void:
	if not navigation_ready: return # The current bake will schedule pending edits.
	_navigation_dirty = false
	navigation_ready = false
	_build_navigation()

func _build_navigation(gradual: bool = false) -> void:
	navigation_ready = false
	_regular_navigation_ready = false
	giant_navigation_ready = false
	# A runtime rebake can outlive the 16-band placement cache. Recreate the
	# same neighbour plans before capturing seam obstacles, just as at startup.
	for neighbour in [band - 1, band + 1]:
		await ForestScenery.prepare(self, neighbour, gradual)
	var nav := NavigationMesh.new()
	nav.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav.agent_height = 2.0
	nav.agent_radius = 0.5
	nav.agent_max_climb = 0.25
	nav.agent_max_slope = 40.0
	nav.cell_size = 0.25
	nav.cell_height = 0.25
	# Sub-metre ground noise should not introduce near-collinear detail
	# triangles into the already walkable voxel contour.
	nav.detail_sample_max_error = 64.0
	nav.border_size = 1.0
	var nav_half := field.profile.terrain_half_width
	if navigation == null:
		navigation = NavigationRegion3D.new()
		navigation.name = "ChunkNavigationRegion"
		# Exact grid-aligned seam edges merge through the map's edge hash.
		# Margin matching otherwise compares every forest-hole edge pair.
		navigation.use_edge_connections = false
		# Keep the mutable background bake detached from the live region. Its
		# changed signal must not race the immutable publication in the callback.
		navigation.navigation_mesh = nav.duplicate()
		add_child(navigation)
	var source := NavigationMeshSourceGeometryData3D.new()
	# The asphalt is only 7cm above the sculpted ground. Voxelizing both
	# creates duplicate raster edges; use the ground once for navigation.
	var road_body := get_node("Road").get_child(0) as StaticBody3D
	road_body.collision_layer = 0
	# Moving leaves block physics, but their doorways remain in the static bake.
	var gate_layers: Dictionary = {}
	# Closed bridge undersides remain physical, but navigation uses the exact
	# asphalt top once instead of rasterizing two surfaces 15cm apart.
	for body: CollisionObject3D in find_children("*", "CollisionObject3D", true, false):
		if body.get_meta("bridge_deck", false):
			gate_layers[body] = body.collision_layer
			body.collision_layer = 0
	for building in get_children():
		if building.get_meta("poi_definition_id", "") == &"starting_shelter":
			for leaf_name in ["GarageGate/LeftLeaf", "GarageGate/RightLeaf"]:
				var leaf := building.get_node_or_null(NodePath(leaf_name)) as CollisionObject3D
				if leaf != null:
					gate_layers[leaf] = leaf.collision_layer
					leaf.collision_layer = 0
		elif building.get_meta("poi_definition_id", "") == &"orientation_shelter":
			for leaf: CollisionObject3D in building.find_children("*", "CollisionObject3D", true, false):
				if not leaf.get_meta("navigation_movable", false): continue
				gate_layers[leaf] = leaf.collision_layer
				leaf.collision_layer = 0
	NavigationServer3D.parse_source_geometry_data(nav, source, self)
	TerrainCrossings.navigation_obstacles(field, band, source)
	# Closed mesh shells alone can leave terrain navigation underneath them.
	# Authored solid decorative volumes explicitly remove that interior space.
	for building in get_children():
		if not building.get_meta("navigation_solid_geometry", false) and building.get_meta("poi_definition_id", "") not in [&"starting_shelter", &"tutorial_shelter", &"orientation_shelter"]: continue
		for shape in building.find_children("*", "CollisionShape3D", true, false):
			if shape.get_meta("navigation_solid", false) and shape.shape is BoxShape3D and not shape.disabled:
				_append_solid_box_obstruction(source, shape.shape.size, global_transform.affine_inverse() * shape.global_transform)
	for leaf in gate_layers: leaf.collision_layer = gate_layers[leaf]
	road_body.collision_layer = 1
	if gradual: await _pause()
	# Neighbour ground halo prevents agent-radius erosion from leaving a gap
	# at every streaming boundary. Only the interior band is kept by the bake.
	var halo := PackedVector3Array()
	for edge in [0, 1]:
		var z0 := -band * 150.0 + (3.0 if edge == 0 else -150.0)
		var columns := roundi(nav_half * 2 / 3)
		var rows: Array[PackedVector3Array] = []
		# Adjacent triangles share vertices: sample each halo point once.
		for row in range(2):
			var points := PackedVector3Array()
			for i in range(columns + 1):
				var px := -nav_half + i * (nav_half * 2.0 / columns)
				var pz := z0 - row * 3.0
				points.append(Vector3(px, field.height_at(px, pz), pz))
				if gradual and i % 32 == 0 and slice_exhausted(): await _pause()
			rows.append(points)
		for i in range(columns):
			for point in [rows[0][i], rows[1][i], rows[0][i + 1], rows[0][i + 1], rows[1][i], rows[1][i + 1]]:
				halo.append(point)
	source.add_faces(halo, Transform3D.IDENTITY)
	_append_neighbour_obstacles(source)
	for neighbour in [band - 1, band + 1]:
		var planned := ForestScenery.trees(field, neighbour)
		for i in range(planned.size()):
			if field.destroyed_trees.has(TreeImpact.forest_id(neighbour, i)): continue
			var tree: Dictionary = planned[i]
			if tree.point.z > -band * 150.0 + 5 or tree.point.z < -(band + 1) * 150.0 - 5: continue
			_append_box_faces(source, Vector3(0.7, tree.height, 0.7), Transform3D(Basis.IDENTITY, tree.point + Vector3.UP * tree.height * 0.5))
	# Mountain roads can rise above the old fixed 150m ceiling. Derive only
	# the vertical bake extent from the complete collision/halo/obstacle source.
	# Shared voxel-aligned heights keep neighbouring bands on the same lattice.
	var source_bounds := source.get_bounds()
	var vertical_padding := maxf(nav.agent_height, SlenderSpeakerSpawns.HEIGHT) + nav.agent_max_climb + nav.cell_height * 2.0
	var bottom := floorf((source_bounds.position.y - vertical_padding) / nav.cell_height) * nav.cell_height
	var top := ceilf((source_bounds.end.y + vertical_padding) / nav.cell_height) * nav.cell_height
	nav.filter_baking_aabb = AABB(Vector3(-nav_half, bottom, -band * 150.0 - 151), Vector3(nav_half * 2, top - bottom, 152))
	var giant_nav: NavigationMesh = nav.duplicate()
	giant_nav.agent_height = SlenderSpeakerSpawns.HEIGHT
	giant_nav.agent_radius = SlenderSpeakerSpawns.RADIUS
	# Four voxels represent the requested 1.1m radius exactly; 0.5m cells
	# silently round it up to 1.5m and reject otherwise legal forest gaps.
	giant_nav.cell_size = 0.275
	giant_nav.border_size = 2.2
	# Match the extra border on both seam sides. Keeping the humanoid's
	# +/-1m AABB with this larger border cuts a gap between giant regions.
	var north := snappedf(-band * 150.0, giant_nav.cell_size)
	var south := snappedf(-(band + 1) * 150.0, giant_nav.cell_size)
	# 150m does not divide by 0.275m. Anchor both clipped seam boundaries
	# to one global voxel lattice so neighbours retain identical edges.
	giant_nav.filter_baking_aabb = AABB(Vector3(-nav_half, bottom, south - giant_nav.border_size), Vector3(nav_half * 2, top - bottom, north - south + 2.0 * giant_nav.border_size))
	if giant_navigation == null:
		giant_navigation = NavigationRegion3D.new()
		giant_navigation.name = "GiantNavigationRegion"
		giant_navigation.use_edge_connections = false
		giant_navigation.navigation_mesh = giant_nav.duplicate()
		add_child(giant_navigation)
	giant_navigation.set_navigation_map(get_parent().giant_navigation_map)
	giant_navigation.set_meta("pending_navigation_bake", giant_nav)
	NavigationServer3D.bake_from_source_geometry_data_async(giant_nav, source, _giant_navigation_baked.bind(giant_nav))
	navigation.set_meta("pending_navigation_bake", nav)
	NavigationServer3D.bake_from_source_geometry_data_async(nav, source, _navigation_baked.bind(nav))

func _append_neighbour_obstacles(source: NavigationMeshSourceGeometryData3D) -> void:
	# Query the shared plan, not loaded neighbours: bake order must not change
	# walls at a seam. Physical segments still have exactly one owning chunk.
	for site in field.sites_near_z(-(band + 0.5) * 150, 400):
		if floori(float(site.s) / 150.0) == band: continue
		if site.has("bounds") and (site.bounds.position.z > -band * 150.0 + 5 or site.bounds.end.z < -(band + 1) * 150.0 - 5): continue
		# Exterior collision boxes are read without registering a second POI.
		var model := POIConfig.instantiate_site(site, false)
		if model == null: continue
		if model.has_method("_ready"): model._ready()
		_append_collision_boxes(source, model, site.building)
		model.free()

func _append_collision_boxes(source: NavigationMeshSourceGeometryData3D, node: Node, pose: Transform3D) -> void:
	if node.get_meta("navigation_movable", false): return
	if node is CollisionShape3D and node.shape is BoxShape3D and not node.disabled:
		_append_box_faces(source, node.shape.size, pose)
		if node.get_meta("navigation_solid", false):
			_append_solid_box_obstruction(source, node.shape.size, pose)
	for child in node.get_children():
		_append_collision_boxes(source, child, pose * child.transform if child is Node3D else pose)

func _append_solid_box_obstruction(source: NavigationMeshSourceGeometryData3D, size: Vector3, pose: Transform3D) -> void:
	# These authored volumes are upright boxes; rotation around Y is supported.
	var outline := PackedVector3Array()
	for corner in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1)]:
		outline.append(pose * (corner * size * 0.5))
	var bounds := pose * AABB(-size * 0.5, size)
	source.add_projected_obstruction(outline, bounds.position.y - 0.5, bounds.size.y + 1.0, false)

func _append_box_faces(source: NavigationMeshSourceGeometryData3D, size: Vector3, pose: Transform3D) -> void:
	var corners := [Vector3(-1,-1,-1), Vector3(1,-1,-1), Vector3(1,1,-1), Vector3(-1,1,-1), Vector3(-1,-1,1), Vector3(1,-1,1), Vector3(1,1,1), Vector3(-1,1,1)]
	var faces := PackedVector3Array()
	for i in [0,1,2,0,2,3,4,6,5,4,7,6,3,2,6,3,6,7,0,5,1,0,4,5,0,3,7,0,7,4,1,5,6,1,6,2]:
		faces.append(corners[i] * size * 0.5)
	source.add_faces(faces, pose)

func _navigation_baked(nav: NavigationMesh) -> void:
	_queue_navigation_publication(navigation, nav, false)

func _giant_navigation_baked(nav: NavigationMesh) -> void:
	_queue_navigation_publication(giant_navigation, nav, true)

func _queue_navigation_publication(region: NavigationRegion3D, nav: NavigationMesh, giant: bool) -> void:
	if not is_instance_valid(region): return
	region.remove_meta("pending_navigation_bake")
	var probe := Vector3.ZERO
	if nav.get_polygon_count() > 0:
		var polygon := nav.get_polygon(0)
		var vertices := nav.get_vertices()
		for index in polygon: probe += vertices[index]
		probe /= polygon.size()
	_navigation_publications.append({"region": region, "mesh": nav, "giant": giant, "before": -1, "probe": probe, "map": RID(), "iteration": -1})
	if is_inside_tree() and not get_tree().process_frame.is_connected(_poll_navigation_publications):
		get_tree().process_frame.connect(_poll_navigation_publications)

func _poll_navigation_publications() -> void:
	for pending: Dictionary in _navigation_publications.duplicate():
		var region: NavigationRegion3D = pending.region
		var rid := region.get_region_rid()
		var region_iteration := NavigationServer3D.region_get_iteration_id(rid)
		if pending.before < 0:
			# Godot can lose a mesh edit made while the initial empty region's
			# async upload is still building. Finish that upload before editing it.
			if region_iteration == 0: continue
			pending.before = region_iteration
			region.navigation_mesh = pending.mesh.duplicate()
			continue
		if region_iteration <= pending.before: continue
		if pending.mesh.get_polygon_count() > 0:
			if NavigationServer3D.region_get_bounds(rid).size == Vector3.ZERO: continue
			# Checkpoint transfer can replace the normal World3D map. Check the
			# current RID, and scan each published map iteration only once.
			var map := region.get_navigation_map()
			var iteration := NavigationServer3D.map_get_iteration_id(map) if map.is_valid() else 0
			if iteration == 0 or (map == pending.map and iteration == pending.iteration): continue
			pending.map = map
			pending.iteration = iteration
			if not NavigationServer3D.map_get_closest_point_owner(map, pending.probe).is_valid(): continue
			if NavigationServer3D.map_get_closest_point(map, pending.probe).distance_to(pending.probe) > 2.0: continue
		if pending.giant: giant_navigation_ready = true
		else: _regular_navigation_ready = true
		_navigation_publications.erase(pending)
		_finish_navigation()
	if _navigation_publications.is_empty():
		get_tree().process_frame.disconnect(_poll_navigation_publications)

func _finish_navigation() -> void:
	if not _regular_navigation_ready or not giant_navigation_ready: return
	navigation_ready = true
	_spawn_road_monsters()
	if _navigation_dirty: request_navigation_rebuild()

func _spawn_actors() -> void:
	var container := WorldEntities.get_container(self)
	if container == null:
		container = self
	for site in sites:
		if site.kind == "walk_in":
			if not get_meta("skip_walk_in", false) and get_parent().has_method("activate_walk_in"):
				get_parent().activate_walk_in(site, self)
			continue
		if site.kind == "entrance" or get_meta("skip_actors", false):
			continue
		var loot := field.loot_plan(int(site.index))
		for i in range(loot.size()):
			var prop: Item = load(loot[i]).instantiate()
			var point: Vector3 = site.building * Vector3(-2.0 + i * 2.0, 0, 4.5)
			point.y = field.height_at(point.x, point.z) + 0.8
			prop.position = point
			container.add_child(prop)
		for i in range(field.enemy_count(int(site.index))):
			var monster: Node3D = RAKER_SCENE.instantiate()
			var point: Vector3 = site.frame * Vector3(float(site.side) * 9, 0, -10 + i * 5)
			point.y = field.height_at(point.x, point.z) + 0.5
			monster.position = point
			container.add_child(monster)

func _spawn_road_monsters() -> void:
	# The shared once-only latch also owns loose barrels. They must not be
	# rebuilt with static chunk geometry after pickup, explosion or a rebake.
	if not navigation_ready or _road_monsters_spawned or road_spawns.is_empty(): return
	_road_monsters_spawned = true
	if get_meta("skip_actors", false): return
	var container := WorldEntities.get_container(self)
	if container == null: return
	for index in range(road_spawns.monsters.size()):
		var point: Vector3 = road_spawns.monsters[index]
		var scenes: Array = road_spawns.get("monster_scenes", [])
		var path: String = scenes[index] if index < scenes.size() else RoadSpawns.RAKER_SCENE
		var monster: Node3D = load(path).instantiate()
		container.add_child(monster)
		monster.global_position = point - Vector3.UP * 0.5 if monster is BarrelMan else point
		var yaws: Array = road_spawns.get("monster_yaws", [])
		if index < yaws.size(): monster.global_rotation.y = float(yaws[index])
	var barrels: Array = road_spawns.get("barrels", [])
	for index in range(barrels.size()):
		var placement: Dictionary = barrels[index]
		var barrel: Item = load(placement.scene).instantiate()
		barrel.restore_item_state({"id": "road:%d:%d:%d:barrel:%d" % [field.profile.generation_version, field.world_seed, band, index]})
		container.add_child(barrel)
		barrel.global_transform = placement.transform
