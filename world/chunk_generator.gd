extends Node3D
class_name ChunkGenerator
## Fixed world-grid band. Roads curve inside it; the band never rotates.
const CHUNK_SIZE := 150.0
const ZOMBIE_SCENE = preload("res://enemies/zombie.tscn")
const TERRAIN_SHADER = preload("res://world/terrain/terrain_material.gdshader")
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
var _terrain: MeshInstance3D

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
	for site in sites:
		_build_site(site, spawner)
	if field.profile.generation_version >= 3:
		await _build_exploration_scenery(gradual)
	await _decorate(gradual)
	if field.profile.generation_version >= 4:
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
	var nz := roundi(field.profile.chunk_length / step)
	var z0 := -band * field.profile.chunk_length
	var rows: Array = []
	for j in range(-1, nz + 2):
		var row: Array = []
		for i in range(-1, nx + 2):
			row.append(field.surface(-field.profile.terrain_half_width + i * step, z0 - j * step))
			if gradual and i % 32 == 0 and slice_exhausted(): await _pause()
		rows.append(row)
		if gradual and slice_exhausted():
			await _pause()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(nz + 1):
		for i in range(nx + 1):
			var sample: Dictionary = rows[j + 1][i + 1]
			var normal := Vector3(float(rows[j + 1][i].height) - float(rows[j + 1][i + 2].height), 2.0 * step, float(rows[j + 2][i + 1].height) - float(rows[j][i + 1].height)).normalized()
			var w: Vector3 = sample.weights
			var color := Color(0.38, 0.43, 0.23) * w.x + Color(0.24, 0.32, 0.18) * w.y + Color(0.48, 0.43, 0.33) * w.z
			if field.profile.generation_version >= 3:
				color = Color("656153") * w.x + Color("515849") * w.y + Color("797369") * w.z
			color = color.lerp(Color(0.38, 0.38, 0.34), smoothstep(0.18, 0.6, 1.0 - normal.y))
			color = color.lerp(Color(0.43, 0.39, 0.30), float(sample.gravel) * 0.85)
			st.set_normal(normal)
			st.set_color(color)
			st.set_uv(Vector2(i, j) * step / 4.0)
			st.add_vertex(Vector3(-field.profile.terrain_half_width + i * step, sample.height, z0 - j * step))
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
	mat.shader = TERRAIN_SHADER
	mat.set_shader_parameter("ground_texture", preload("res://assets/materials/industrial/forest_floor.png"))
	_terrain.material_override = mat
	if gradual:
		await _pause()
	await _build_distant_sides(gradual)

func _build_distant_sides(gradual: bool) -> void:
	for side in [-1.0, 1.0]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var edge := field.profile.terrain_half_width
		var columns := [edge, edge + 30, edge + 90, edge + 210, edge + 450, edge + 810]
		for j in range(51):
			var z := -band * 150.0 - j * 3.0
			for x in columns:
				st.set_color(Color(0.36, 0.39, 0.27))
				st.add_vertex(Vector3(x * side, field.height_at(x * side, z), z))
			if gradual and slice_exhausted(): await _pause()
		for j in range(50):
			for i in range(5):
				var a := j * 6 + i
				var indices := [a, a + 6, a + 1, a + 1, a + 6, a + 7] if side > 0 else [a, a + 1, a + 6, a + 1, a + 7, a + 6]
				for v in indices:
					st.add_index(v)
		st.generate_normals()
		_mesh(st.commit(), "DistantTerrain", false)
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
		paint.rotation.x = atan2(field.road_height(s + 2) - field.road_height(s - 2), 4.0)
	for i in range(3):
		var s := band * 150.0 + i * 50.0 + 20.0
		var point := field.road_frame(s) * Vector3(14, 0, 0)
		if not _near_site(point):
			_place_module("pole", point, field.road_frame(s).basis)
	if posmod(band, 6) == 3:
		var frame := field.road_frame(band * 150.0 - 35.0)
		var sign_node := _place_module("sign", frame * Vector3(11, 0, 0), frame.basis)
		RoadsideKit.label(sign_node, "NARROW ROAD\nSLOW", Vector3(0, 3.4, 0.08), 34)
		for i in range(12):
			var s := band * 150.0 + 40.0 + i * 5.0
			var rail := field.road_frame(s)
			var point := rail * Vector3(-field.road_width(s) * 0.5 - 1.2, 0, 0)
			if not _near_site(point):
				_place_module("rail", point, rail.basis)

func _near_site(point: Vector3) -> bool:
	var nearest := maxi(0, roundi(-point.z / field.profile.stop_spacing))
	for i in range(maxi(0, nearest - 1), nearest + 2):
		if field.court_distance(point.x, point.z, field.stop(i)) < 20:
			return true
	return false

func _place_module(kind: String, point: Vector3, orientation: Basis = Basis.IDENTITY) -> Node3D:
	var node := RoadsideKit.instantiate_module(kind)
	node.transform = Transform3D(orientation, Vector3(point.x, field.height_at(point.x, point.z), point.z))
	add_child(node)
	return node

func _build_site(site: Dictionary, spawner: POISpawner) -> void:
	if site.kind in ["entrance", "walk_in"]:
		spawner.spawn_site(site, self)
	else:
		_place_module(site.kind, site.building.origin, site.building.basis)
	var sign_pos: Vector3 = site.road * Vector3(float(site.side) * 12.0, 0, 21.0)
	var sign_node := _place_module("sign", sign_pos, site.road.basis)
	RoadsideKit.label(sign_node, str(site.get("title", "SERVICE")) + "\nFOOT ACCESS" if site.kind == "entrance" else ("NORTHLINE\nGAS / SERVICE" if site.kind == "walk_in" else "LAY-BY"), Vector3(0, 3.4, 0.08), 24)
	for side in [-1.0, 1.0]:
		var point: Vector3 = site.frame * Vector3(side * 6.2, 0.05, 0)
		var stripe := RoadsideKit.part(self, Vector3(0.15, 0.03, 24), point, Color(0.72, 0.64, 0.43))
		stripe.basis = site.frame.basis
	for i in range(3):
		var point: Vector3 = site.building * Vector3(0, 0.06, 7.5 + i)
		var stripe := RoadsideKit.part(self, Vector3(2, 0.03, 0.25), point, Color(0.70, 0.65, 0.49))
		stripe.basis = site.building.basis

func _build_exploration_scenery(gradual: bool = false) -> void:
	var first := maxi(0, floori(band * 150.0 / field.profile.stop_spacing) - 1)
	for index in range(first, first + 4):
		var site := field.stop(index)
		if not site.has("route"): continue
		# A rotated deep site can touch a band far from its road anchor.
		if site.bounds.position.z > -band * 150.0 + 4 or site.bounds.end.z < -(band + 1) * 150.0 - 4: continue
		var parts := ExplorationSite.wall_parts(site)
		for part_index in range(parts.size()):
			if gradual and part_index % 20 == 0: await _pause()
			var data: Dictionary = parts[part_index]
			if floori(-data.base.z / 150.0) != band: continue
			var color := Color("50564f") if part_index % 4 != 0 else Color("424b44")
			var part := RoadsideKit.part(self, data.size, data.transform.origin, color, true)
			part.basis = site.road.basis
			var cap := RoadsideKit.part(self, Vector3(data.size.x + 0.12, 0.14, data.size.z + 0.12), data.base + Vector3.UP * (data.size.y + 0.05), Color("383f38"))
			cap.basis = site.road.basis
		for i in range(1, site.route.size() - 1):
			var point: Vector3 = site.route[i] + site.road.basis * Vector3(3.5, 0, 3.5 if i % 2 == 0 else -3.5)
			if floori(-point.z / 150.0) != band: continue
			var post := _place_module("pole", point, site.road.basis)
			post.scale = Vector3.ONE * 0.35
			var marker := RoadsideKit.part(self, Vector3(0.3, 0.4, 0.3), point + Vector3.UP * 1.6, Color("b6a071"))
			marker.basis = site.road.basis
		# Authored groves supplement sparse biome scenery, away from travel lanes.
		if field.profile.generation_version >= 4: continue
		var grove_rng := field.rng_for(index, "groves")
		for i in range(70):
			if gradual and i % 20 == 0: await _pause()
			var u := grove_rng.randf_range(47, 148)
			var v := grove_rng.randf_range(-34, 34)
			var point := ExplorationSite.local_point(site, u, v)
			if floori(-point.z / 150.0) != band or field.surface(point.x, point.z).reserved: continue
			# Keep the elevated landmark view from the complete parking bay clear.
			if absf(v) < 8: continue
			var tree := _place_module("dead_tree" if i % 3 == 0 else "tree", point, Basis(Vector3.UP, grove_rng.randf_range(-PI, PI)))
			tree.scale = Vector3.ONE * grove_rng.randf_range(0.65, 1.1)
			for mesh in tree.find_children("*", "GeometryInstance3D", true, false):
				mesh.visibility_range_end = 290.0
			decoration_positions.append(point)

func _decorate(gradual: bool) -> void:
	if field.profile.generation_version >= 4: return
	var rng := field.rng_for(band, "decoration")
	var bushes: Array[Transform3D] = []
	for i in range(roundi(450 * field.profile.decoration_density)):
		if gradual and i % 75 == 0:
			await _pause()
		var x := rng.randf_range(-210.0, 210.0)
		var z := -band * 150.0 - rng.randf_range(4.0, 146.0)
		var sample := field.surface(x, z)
		if sample.reserved:
			continue
		var w: Vector3 = sample.weights
		var cluster := field.clusters.get_noise_2d(x, z)
		if rng.randf() > clampf(0.25 + cluster * 1.5 + w.y * 0.35, 0.08, 0.9):
			continue
		var point := Vector3(x, sample.height, z)
		var orientation := Basis(Vector3.UP, rng.randf_range(-PI, PI))
		var scale_value := rng.randf_range(0.7, 1.35)
		if i % 3 != 0:
			var bush_scale := Vector3.ONE * scale_value
			var bush_height := 0.25
			if field.profile.generation_version >= 3:
				if i % 5 == 0: bush_scale *= Vector3(1.6, 2.4, 1.6)
				bush_height = 0.4 * bush_scale.y
			bushes.append(Transform3D(orientation.scaled(bush_scale), point + Vector3.UP * bush_height))
			continue
		if field.normal_at(x, z).y < 0.83:
			continue
		var kind := "rock" if rng.randf() < 0.18 + w.z * 0.6 else ("tree" if rng.randf() < 0.15 + w.y * 0.85 else "dead_tree")
		var module := _place_module(kind, point, orientation)
		module.scale = Vector3.ONE * scale_value
		for child in module.get_children():
			if child is GeometryInstance3D:
				child.visibility_range_end = 290.0
		decoration_positions.append(point)
	if not bushes.is_empty():
		var mesh := SphereMesh.new()
		mesh.radius = 0.65
		mesh.height = 0.8
		mesh.radial_segments = 5
		mesh.rings = 2
		mesh.material = RoadsideKit.material(Color("424c38") if field.profile.generation_version >= 3 else Color(0.32, 0.37, 0.19))
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = mesh
		multi.instance_count = bushes.size()
		for i in range(bushes.size()):
			multi.set_instance_transform(i, bushes[i])
		var node := MultiMeshInstance3D.new()
		node.multimesh = multi
		node.visibility_range_end = 190.0
		add_child(node)

func _build_navigation(gradual: bool = false) -> void:
	var nav := NavigationMesh.new()
	nav.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav.agent_height = 2.0
	nav.agent_radius = 0.5
	nav.agent_max_climb = 0.25
	nav.agent_max_slope = 40.0
	nav.cell_size = 0.25 if field.profile.generation_version >= 3 else 0.5
	nav.cell_height = 0.25
	# Sub-metre ground noise should not introduce near-collinear detail
	# triangles into the already walkable voxel contour.
	nav.detail_sample_max_error = 64.0 if field.profile.generation_version >= 3 else 2.0
	nav.border_size = 1.0
	var nav_half := field.profile.terrain_half_width if field.profile.generation_version >= 3 else 120.0
	nav.filter_baking_aabb = AABB(Vector3(-nav_half, -100, -band * 150.0 - 151), Vector3(nav_half * 2, 250, 152))
	navigation = NavigationRegion3D.new()
	navigation.name = "ChunkNavigationRegion"
	navigation.navigation_mesh = nav
	add_child(navigation)
	var source := NavigationMeshSourceGeometryData3D.new()
	# The asphalt is only 7cm above the sculpted ground. Voxelizing both
	# creates duplicate raster edges; use the ground once for navigation.
	var road_body := get_node("Road").get_child(0) as StaticBody3D
	road_body.collision_layer = 0
	NavigationServer3D.parse_source_geometry_data(nav, source, self)
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
				var px := -nav_half + i * 3.0
				var pz := z0 - row * 3.0
				points.append(Vector3(px, field.height_at(px, pz), pz))
				if gradual and i % 32 == 0 and slice_exhausted(): await _pause()
			rows.append(points)
		for i in range(columns):
			for point in [rows[0][i], rows[1][i], rows[0][i + 1], rows[0][i + 1], rows[1][i], rows[1][i + 1]]:
				halo.append(point)
	source.add_faces(halo, Transform3D.IDENTITY)
	if field.profile.generation_version >= 3:
		_append_neighbour_obstacles(source)
	if field.profile.generation_version >= 4:
		for neighbour in [band - 1, band + 1]:
			for tree: Dictionary in ForestScenery.trees(field, neighbour):
				if tree.point.z > -band * 150.0 + 5 or tree.point.z < -(band + 1) * 150.0 - 5: continue
				_append_box_faces(source, Vector3(0.7, tree.height, 0.7), Transform3D(Basis.IDENTITY, tree.point + Vector3.UP * tree.height * 0.5))
	NavigationServer3D.bake_from_source_geometry_data_async(nav, source, _navigation_baked.bind(nav))

func _append_neighbour_obstacles(source: NavigationMeshSourceGeometryData3D) -> void:
	# Query the shared plan, not loaded neighbours: bake order must not change
	# walls at a seam. Physical segments still have exactly one owning chunk.
	var first := maxi(0, floori(band * 150.0 / field.profile.stop_spacing) - 1)
	for index in range(first, first + 4):
		var site := field.stop(index)
		if not site.has("walls"): continue
		for part: Dictionary in ExplorationSite.wall_parts(site):
			if floori(-part.base.z / 150.0) == band: continue
			if part.base.z > -band * 150.0 + 5 or part.base.z < -(band + 1) * 150.0 - 5: continue
			_append_box_faces(source, part.size, part.transform)
		if floori(float(site.s) / 150.0) == band or absf(site.building.origin.z + band * 150.0 + 75) > 95: continue
		# Exterior collision boxes are read without registering a second POI.
		var model: Node3D = POIConfig.scene_for_site(site).instantiate()
		if model.has_method("_ready"): model._ready()
		_append_collision_boxes(source, model, site.building)
		model.free()

func _append_collision_boxes(source: NavigationMeshSourceGeometryData3D, node: Node, pose: Transform3D) -> void:
	if node is CollisionShape3D and node.shape is BoxShape3D and not node.disabled:
		_append_box_faces(source, node.shape.size, pose)
	for child in node.get_children():
		_append_collision_boxes(source, child, pose * child.transform if child is Node3D else pose)

func _append_box_faces(source: NavigationMeshSourceGeometryData3D, size: Vector3, pose: Transform3D) -> void:
	var corners := [Vector3(-1,-1,-1), Vector3(1,-1,-1), Vector3(1,1,-1), Vector3(-1,1,-1), Vector3(-1,-1,1), Vector3(1,-1,1), Vector3(1,1,1), Vector3(-1,1,1)]
	var faces := PackedVector3Array()
	for i in [0,1,2,0,2,3,4,6,5,4,7,6,3,2,6,3,6,7,0,5,1,0,4,5,0,3,7,0,7,4,1,5,6,1,6,2]:
		faces.append(corners[i] * size * 0.5)
	source.add_faces(faces, pose)

func _navigation_baked(nav: NavigationMesh) -> void:
	if not is_instance_valid(navigation): return
	await get_tree().process_frame
	var rid := navigation.get_region_rid()
	var before := NavigationServer3D.region_get_iteration_id(rid)
	# Publish an immutable result after entering the tree. Mutating a resource
	# already attached during async bake can leave the server with empty data.
	navigation.navigation_mesh = nav.duplicate()
	# Baking and server synchronization finish separately. In fast headless
	# runs, a fixed number of physics frames can still query an empty region.
	while is_inside_tree() and (NavigationServer3D.region_get_iteration_id(rid) <= before or NavigationServer3D.region_get_bounds(rid).size == Vector3.ZERO):
		await get_tree().physics_frame
	if not is_inside_tree(): return
	# Region data can publish before the complete map's async synchronization.
	# Shared seam points can belong to either neighbour; require proximity,
	# not exclusive ownership of that point by this region.
	if nav.get_polygon_count() > 0:
		var probe := Vector3.ZERO
		var polygon := nav.get_polygon(0)
		var vertices := nav.get_vertices()
		for index in polygon: probe += vertices[index]
		probe /= polygon.size()
		while is_inside_tree():
			# Checkpoint staging can transfer this node to another World3D.
			# Never retain that old map RID across an await.
			var map := navigation.get_navigation_map()
			if map.is_valid() and NavigationServer3D.map_get_closest_point_owner(map, probe).is_valid() and NavigationServer3D.map_get_closest_point(map, probe).distance_to(probe) <= 2.0: break
			await get_tree().physics_frame
		if not is_inside_tree(): return
	navigation_ready = true

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
			var prop: Prop = load(loot[i]).instantiate()
			var point: Vector3 = site.building * Vector3(-2.0 + i * 2.0, 0, 4.5)
			point.y = field.height_at(point.x, point.z) + 0.8
			prop.position = point
			container.add_child(prop)
		for i in range(field.enemy_count(int(site.index))):
			var monster: Node3D = ZOMBIE_SCENE.instantiate()
			var point: Vector3 = site.frame * Vector3(float(site.side) * 9, 0, -10 + i * 5)
			point.y = field.height_at(point.x, point.z) + 0.5
			monster.position = point
			container.add_child(monster)
