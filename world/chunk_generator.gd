extends Node3D
class_name ChunkGenerator
## Fixed world-grid band. Roads curve inside it; the band never rotates.
const CHUNK_SIZE := 150.0
const ZOMBIE_SCENE = preload("res://enemies/zombie.tscn")
const TERRAIN_SHADER = preload("res://world/terrain/terrain_material.gdshader")
var field: WorldField
var band: int
var sites: Array[Dictionary] = []
var decoration_positions: Array[Vector3] = []
var build_ms: float = 0.0
var max_slice_ms: float = 0.0
var _slice_start: int
var navigation: NavigationRegion3D
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
	await _decorate(gradual)
	if gradual:
		await _pause()
	_build_navigation()
	_spawn_actors()
	_measure_slice()

func _measure_slice() -> void:
	var elapsed := (Time.get_ticks_usec() - _slice_start) / 1000.0
	build_ms += elapsed
	max_slice_ms = maxf(max_slice_ms, elapsed)

func _pause() -> void:
	_measure_slice()
	await get_tree().process_frame
	_slice_start = Time.get_ticks_usec()

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
		rows.append(row)
		if gradual and posmod(j, 3) == 0:
			await _pause()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(nz + 1):
		for i in range(nx + 1):
			var sample: Dictionary = rows[j + 1][i + 1]
			var normal := Vector3(float(rows[j + 1][i].height) - float(rows[j + 1][i + 2].height), 2.0 * step, float(rows[j + 2][i + 1].height) - float(rows[j][i + 1].height)).normalized()
			var w: Vector3 = sample.weights
			var color := Color(0.38, 0.43, 0.23) * w.x + Color(0.24, 0.32, 0.18) * w.y + Color(0.48, 0.43, 0.33) * w.z
			color = color.lerp(Color(0.38, 0.38, 0.34), smoothstep(0.18, 0.6, 1.0 - normal.y))
			color = color.lerp(Color(0.43, 0.39, 0.30), float(sample.gravel) * 0.85)
			st.set_normal(normal)
			st.set_color(color)
			st.set_uv(Vector2(i, j) * step / 4.0)
			st.add_vertex(Vector3(-field.profile.terrain_half_width + i * step, sample.height, z0 - j * step))
		if gradual and j % 12 == 0:
			await _pause()
	for j in range(nz):
		for i in range(nx):
			var a := j * (nx + 1) + i
			for v in [a, a + nx + 1, a + 1, a + 1, a + nx + 1, a + nx + 2]:
				st.add_index(v)
	_terrain = _mesh(st.commit(), "Ground", true)
	var mat := ShaderMaterial.new()
	mat.shader = TERRAIN_SHADER
	_terrain.material_override = mat
	if gradual:
		await _pause()
	await _build_distant_sides(gradual)

func _build_distant_sides(gradual: bool) -> void:
	for side in [-1.0, 1.0]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var columns := [225.0, 255.0, 315.0, 435.0, 675.0, 1035.0]
		for j in range(51):
			var z := -band * 150.0 - j * 3.0
			for x in columns:
				st.set_color(Color(0.36, 0.39, 0.27))
				st.add_vertex(Vector3(x * side, field.height_at(x * side, z), z))
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
	if site.kind == "entrance":
		spawner.spawn_site(site, self)
	else:
		_place_module(site.kind, site.building.origin, site.building.basis)
	var sign_pos: Vector3 = site.road * Vector3(float(site.side) * 12.0, 0, 21.0)
	var sign_node := _place_module("sign", sign_pos, site.road.basis)
	RoadsideKit.label(sign_node, "SERVICE" if site.kind == "entrance" else "LAY-BY", Vector3(0, 3.4, 0.08))
	for side in [-1.0, 1.0]:
		var point: Vector3 = site.frame * Vector3(side * 6.2, 0.05, 0)
		var stripe := RoadsideKit.part(self, Vector3(0.15, 0.03, 24), point, Color(0.72, 0.64, 0.43))
		stripe.basis = site.frame.basis
	for i in range(3):
		var point: Vector3 = site.building * Vector3(0, 0.06, 7.5 + i)
		var stripe := RoadsideKit.part(self, Vector3(2, 0.03, 0.25), point, Color(0.70, 0.65, 0.49))
		stripe.basis = site.building.basis

func _decorate(gradual: bool) -> void:
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
			bushes.append(Transform3D(orientation.scaled(Vector3.ONE * scale_value), point + Vector3.UP * 0.25))
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
		mesh.material = RoadsideKit.material(Color(0.32, 0.37, 0.19))
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

func _build_navigation() -> void:
	var nav := NavigationMesh.new()
	nav.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav.agent_height = 2.0
	nav.agent_radius = 0.5
	nav.agent_max_climb = 0.25
	nav.agent_max_slope = 40.0
	nav.cell_size = 0.5
	nav.cell_height = 0.25
	# Sub-metre ground noise should not introduce near-collinear detail
	# triangles into the already walkable voxel contour.
	nav.detail_sample_max_error = 2.0
	nav.border_size = 1.0
	nav.filter_baking_aabb = AABB(Vector3(-120, -100, -band * 150.0 - 151), Vector3(240, 250, 152))
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
	# Neighbour ground halo prevents agent-radius erosion from leaving a gap
	# at every streaming boundary. Only the interior band is kept by the bake.
	var halo := PackedVector3Array()
	for edge in [0, 1]:
		var z0 := -band * 150.0 + (3.0 if edge == 0 else -150.0)
		for i in range(80):
			var x := -120.0 + i * 3.0
			for offset in [Vector2(0, 0), Vector2(0, -3), Vector2(3, 0), Vector2(3, 0), Vector2(0, -3), Vector2(3, -3)]:
				var px: float = x + offset.x
				var pz: float = z0 + offset.y
				halo.append(Vector3(px, field.height_at(px, pz), pz))
	source.add_faces(halo, Transform3D.IDENTITY)
	NavigationServer3D.bake_from_source_geometry_data_async(nav, source, func():
		if is_instance_valid(navigation):
			navigation.navigation_mesh = nav)

func _spawn_actors() -> void:
	if get_meta("skip_actors", false):
		return
	var container := WorldEntities.get_container(self)
	if container == null:
		container = self
	for site in sites:
		if site.kind == "entrance":
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
