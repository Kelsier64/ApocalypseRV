extends Node3D
class_name ChunkGenerator

const CHUNK_SIZE = 150.0
const RESOLUTION = 80
const ROAD_WIDTH = 15.0
const ROAD_BLEND_DISTANCE = 12.0
const MAX_HEIGHT = 60.0

var noise: FastNoiseLite
var detail_noise: FastNoiseLite
var start_pos: Vector3
var end_pos: Vector3
var control_p1: Vector3
var control_p2: Vector3

var has_poi: bool = false
var poi_local_pos: Vector3
var poi_footprint_radius: float = 8.0
var poi_footprint_blend: float = 10.0
var _current_poi: Dictionary = {}
var _poi_spawner: POISpawner


func _get_terrain_height(gx: float, gz: float, micro_multiplier: float = 1.0) -> float:
	var raw_noise = noise.get_noise_2d(gx, gz)
	var base_h = raw_noise * MAX_HEIGHT
	var micro_noise = detail_noise.get_noise_2d(gx, gz)
	base_h += micro_noise * 1.5 * micro_multiplier
	return base_h


func generate_chunk(start_transform: Transform3D, next_turn_angle: float,
		shared_noise: FastNoiseLite, shared_detail_noise: FastNoiseLite) -> Transform3D:
	global_transform = start_transform

	noise = shared_noise
	detail_noise = shared_detail_noise

	# Bezier road curve
	start_pos = Vector3.ZERO
	var end_offset_x = sin(next_turn_angle) * CHUNK_SIZE * 0.5
	end_pos = Vector3(end_offset_x, 0, -CHUNK_SIZE)
	control_p1 = Vector3(0, 0, -CHUNK_SIZE * 0.33)
	control_p2 = end_pos + Vector3(-sin(next_turn_angle) * CHUNK_SIZE * 0.33, 0, CHUNK_SIZE * 0.33)

	# POI placement
	_poi_spawner = POISpawner.new()
	has_poi = false
	if randf() < 0.5:
		_try_place_poi()

	# Build meshes
	_build_terrain_mesh()
	_build_road_mesh()

	# End transform for next chunk
	var end_basis = Basis(Vector3.UP, next_turn_angle)
	var global_end = global_transform * end_pos
	var true_end_height = _get_terrain_height(global_end.x, global_end.z, 0.0)
	end_pos.y = true_end_height - global_transform.origin.y
	var local_end_transform = Transform3D(end_basis, end_pos)

	# Spawn POI contents
	if has_poi:
		_poi_spawner.spawn_building(_current_poi, self, poi_local_pos)
		_poi_spawner.spawn_loot(_current_poi, self, poi_local_pos)
		_poi_spawner.spawn_enemies(_current_poi, self, poi_local_pos, _get_local_height)

	_spawn_road_zombies()

	return global_transform * local_end_transform


func _try_place_poi() -> void:
	var poi := _poi_spawner.pick_poi()

	var hx := randf_range(-CHUNK_SIZE / 2.0 + 20.0, CHUNK_SIZE / 2.0 - 20.0)
	var hz := randf_range(-CHUNK_SIZE + 20.0, -20.0)
	var global_hp := global_transform * Vector3(hx, 0, hz)
	var h_height := _get_terrain_height(global_hp.x, global_hp.z, 0.0)

	var curve_data := _get_closest_curve_point(hx, hz)
	var curve_pt: Vector3 = curve_data[0]
	var dist_to_road := Vector2(curve_pt.x - hx, curve_pt.z - hz).length()
	var min_road_dist: float = poi.get("min_road_distance", ROAD_WIDTH / 2.0 + 10.0)

	if dist_to_road < min_road_dist:
		return

	has_poi = true
	poi_local_pos = Vector3(hx, h_height - global_transform.origin.y, hz)
	poi_footprint_radius = poi.get("footprint_radius", 8.0)
	poi_footprint_blend = poi.get("footprint_blend", 10.0)
	_current_poi = poi


func _get_local_height(lx: float, lz: float) -> float:
	var global_spawn := global_transform * Vector3(lx, 0, lz)
	var terrain_h := _get_terrain_height(global_spawn.x, global_spawn.z, 0.0)
	return terrain_h - global_transform.origin.y


# --- Road math ---

func _cubic_bezier(t: float) -> Vector3:
	var q0 = start_pos.lerp(control_p1, t)
	var q1 = control_p1.lerp(control_p2, t)
	var q2 = control_p2.lerp(end_pos, t)
	var r0 = q0.lerp(q1, t)
	var r1 = q1.lerp(q2, t)
	return r0.lerp(r1, t)


func _get_closest_curve_point(px: float, pz: float) -> Array:
	var closest_dist = INF
	var closest_pt = Vector3.ZERO
	var closest_t = 0.0
	var samples = 20
	for i in range(samples + 1):
		var t = float(i) / samples
		var pt = _cubic_bezier(t)
		var d = Vector2(pt.x - px, pt.z - pz).length_squared()
		if d < closest_dist:
			closest_dist = d
			closest_pt = pt
			closest_t = t
	return [closest_pt, closest_t]


# --- Terrain mesh ---

func _build_terrain_mesh():
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var overlap = 4.0
	var step_z = (CHUNK_SIZE + overlap * 2.0) / RESOLUTION
	var step_x = (CHUNK_SIZE + overlap * 2.0) / RESOLUTION
	var half_size_x = (CHUNK_SIZE + overlap * 2.0) / 2.0
	var x_offset = end_pos.x / 2.0

	var grid_data = []
	for zi in range(RESOLUTION + 1):
		grid_data.append([])
		for xi in range(RESOLUTION + 1):
			var lz = overlap - float(zi) * step_z
			var lx = float(xi) * step_x - half_size_x + x_offset

			var global_p = global_transform * Vector3(lx, 0, lz)

			var curve_data = _get_closest_curve_point(lx, lz)
			var curve_pt: Vector3 = curve_data[0]
			var dist_to_road = Vector2(curve_pt.x - lx, curve_pt.z - lz).length()

			var micro_mult = clamp((dist_to_road - ROAD_WIDTH / 2.0) / (ROAD_BLEND_DISTANCE * 0.5), 0.0, 1.0)

			var blend_factor = 1.0
			var dist_to_poi = INF
			if has_poi:
				dist_to_poi = Vector2(poi_local_pos.x - lx, poi_local_pos.z - lz).length()
				if dist_to_poi < poi_footprint_radius:
					micro_mult = 0.0
					blend_factor = 0.0
				elif dist_to_poi < poi_footprint_radius + poi_footprint_blend:
					var t = (dist_to_poi - poi_footprint_radius) / poi_footprint_blend
					micro_mult = min(micro_mult, t)
					blend_factor = t

			var final_h = _get_terrain_height(global_p.x, global_p.z, micro_mult)
			var local_h = final_h - global_transform.origin.y

			if has_poi and blend_factor < 1.0:
				local_h = lerp(poi_local_pos.y, local_h, blend_factor)

			var col = Color.WHITE

			if dist_to_poi < poi_footprint_radius:
				var dirt_factor = clamp(abs(local_h) / MAX_HEIGHT, 0.0, 1.0)
				col = Color(0.3, 0.35, 0.2).lerp(Color(0.5, 0.45, 0.3), dirt_factor)
			elif dist_to_road < ROAD_WIDTH / 2.0:
				col = Color(0.2, 0.25, 0.1)
			elif dist_to_road < ROAD_WIDTH / 2.0 + ROAD_BLEND_DISTANCE:
				col = Color(0.3, 0.35, 0.2)
			else:
				var dirt_factor = clamp(abs(local_h) / MAX_HEIGHT, 0.0, 1.0)
				col = Color(0.4, 0.5, 0.2).lerp(Color(0.6, 0.5, 0.3), dirt_factor)

			grid_data[zi].append([Vector3(lx, local_h, lz), col])

	for zi in range(RESOLUTION):
		for xi in range(RESOLUTION):
			var d0 = grid_data[zi][xi]
			var d1 = grid_data[zi][xi+1]
			var d2 = grid_data[zi+1][xi]
			var d3 = grid_data[zi+1][xi+1]

			st.set_color(d0[1])
			st.set_uv(Vector2(float(xi)/RESOLUTION, float(zi)/RESOLUTION))
			st.add_vertex(d0[0])

			st.set_color(d2[1])
			st.set_uv(Vector2(float(xi)/RESOLUTION, float(zi+1)/RESOLUTION))
			st.add_vertex(d2[0])

			st.set_color(d1[1])
			st.set_uv(Vector2(float(xi+1)/RESOLUTION, float(zi)/RESOLUTION))
			st.add_vertex(d1[0])

			st.set_color(d1[1])
			st.set_uv(Vector2(float(xi+1)/RESOLUTION, float(zi)/RESOLUTION))
			st.add_vertex(d1[0])

			st.set_color(d2[1])
			st.set_uv(Vector2(float(xi)/RESOLUTION, float(zi+1)/RESOLUTION))
			st.add_vertex(d2[0])

			st.set_color(d3[1])
			st.set_uv(Vector2(float(xi+1)/RESOLUTION, float(zi+1)/RESOLUTION))
			st.add_vertex(d3[0])

	st.generate_normals()
	st.index()
	var mesh = st.commit()

	var mesh_node = MeshInstance3D.new()
	mesh_node.mesh = mesh
	add_child(mesh_node)

	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	mesh_node.material_override = mat

	var shape = ConcavePolygonShape3D.new()
	shape.set_faces(mesh.get_faces())

	var col_node = CollisionShape3D.new()
	col_node.shape = shape

	var static_body = StaticBody3D.new()
	static_body.add_child(col_node)
	mesh_node.add_child(static_body)


# --- Road mesh ---

func _build_road_mesh():
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var road_segments = 60
	var half_width = ROAD_WIDTH / 2.0

	var start_idx = -2
	var end_idx = road_segments + 2
	var total_verts = 0

	for i in range(start_idx, end_idx + 1):
		var t = float(i) / road_segments
		var center = _cubic_bezier(t)

		var t_next = t + 0.01
		var tangent = (_cubic_bezier(t_next) - center).normalized()
		var right = tangent.cross(Vector3.UP).normalized()

		var left_v = center - right * half_width
		var right_v = center + right * half_width

		var global_left_p = global_transform * left_v
		var global_right_p = global_transform * right_v

		var left_h = _get_terrain_height(global_left_p.x, global_left_p.z, 0.0)
		var right_h = _get_terrain_height(global_right_p.x, global_right_p.z, 0.0)

		var max_tilt_angle_rad = deg_to_rad(10.0)
		var max_height_diff = ROAD_WIDTH * tan(max_tilt_angle_rad)

		var current_diff = right_h - left_h
		if abs(current_diff) > max_height_diff:
			var avg_h = (left_h + right_h) / 2.0
			var limited_diff = sign(current_diff) * max_height_diff
			left_h = avg_h - (limited_diff / 2.0)
			right_h = avg_h + (limited_diff / 2.0)

		left_v.y = left_h - global_transform.origin.y + 0.15
		right_v.y = right_h - global_transform.origin.y + 0.15

		st.set_color(Color(0.2, 0.2, 0.2))
		st.set_uv(Vector2(0, t))
		st.add_vertex(left_v)

		st.set_color(Color(0.2, 0.2, 0.2))
		st.set_uv(Vector2(1, t))
		st.add_vertex(right_v)
		total_verts += 1

	for i in range(total_verts - 1):
		var vert_idx = i * 2
		st.add_index(vert_idx)
		st.add_index(vert_idx + 2)
		st.add_index(vert_idx + 1)
		st.add_index(vert_idx + 1)
		st.add_index(vert_idx + 2)
		st.add_index(vert_idx + 3)

	st.generate_normals()
	var mesh = st.commit()

	var mesh_node = MeshInstance3D.new()
	mesh_node.mesh = mesh

	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mesh_node.material_override = mat

	var shape = ConcavePolygonShape3D.new()
	shape.set_faces(mesh.get_faces())

	var col_node = CollisionShape3D.new()
	col_node.shape = shape

	var static_body = StaticBody3D.new()
	static_body.add_child(col_node)
	mesh_node.add_child(static_body)

	add_child(mesh_node)


# --- Road zombies (ambient, not POI-related) ---

func _spawn_road_zombies():
	var zombie_scene = load("res://enemies/zombie.tscn")
	if not zombie_scene: return

	if randf() > 0.6: return

	var num_zombies = randi_range(1, 2)
	for i in range(num_zombies):
		var t = randf_range(0.1, 0.9)
		var road_pt = _cubic_bezier(t)

		var t_next = t + 0.01
		var tangent = (_cubic_bezier(t_next) - road_pt).normalized()
		var right = tangent.cross(Vector3.UP).normalized()

		var side = 1.0 if randf() > 0.5 else -1.0
		var offset_dist = randf_range(10.0, 20.0)
		var spawn_local = road_pt + right * side * offset_dist

		var global_spawn = global_transform * spawn_local
		var terrain_h = _get_terrain_height(global_spawn.x, global_spawn.z, 0.0)
		spawn_local.y = terrain_h - global_transform.origin.y + 2.0

		var zombie = zombie_scene.instantiate()
		zombie.position = spawn_local
		add_child(zombie)
