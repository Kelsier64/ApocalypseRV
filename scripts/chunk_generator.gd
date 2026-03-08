extends Node3D
class_name ChunkGenerator

const CHUNK_SIZE = 150.0 # Length and width of chunk
const RESOLUTION = 80 # Highly detailed terrain mesh
const ROAD_WIDTH = 15.0 # Slightly narrower, more realistic highway lane
const ROAD_BLEND_DISTANCE = 12.0 
const MAX_HEIGHT = 60.0 # Taller mountains to ensure noticeable variation

var noise: FastNoiseLite
var detail_noise: FastNoiseLite
var start_pos: Vector3
var end_pos: Vector3
var control_p1: Vector3
var control_p2: Vector3

var has_house: bool = false
var house_local_pos: Vector3

# Helper to get the consistent height of the terrain at any global 2D coordinate
# micro_multiplier: 0.0 for smooth road, 1.0 for bumpy offroad terrain
func _get_terrain_height(gx: float, gz: float, micro_multiplier: float = 1.0) -> float:
	var raw_noise = noise.get_noise_2d(gx, gz)
	
	# Linear mapping ensures FBM hills stay massive and noticeable
	var base_h = raw_noise * MAX_HEIGHT
	
	# Add smaller high-frequency bumps
	var micro_noise = detail_noise.get_noise_2d(gx, gz)
	base_h += micro_noise * 1.5 * micro_multiplier
	
	return base_h

# Generate a single chunk of terrain and road
# start_transform: where this chunk begins (origin and rotation)
# next_turn_angle: roughly how much this chunk should turn by the end (-0.3 to 0.3 rad)
func generate_chunk(start_transform: Transform3D, next_turn_angle: float) -> Transform3D:
	global_transform = start_transform
	
	# 1. Setup Noise
	noise = FastNoiseLite.new()
	noise.seed = 1337 # Use a fixed or synced seed later if multiplayer
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.0005 # Large hills every ~600 meters
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 5
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.5
	
	detail_noise = FastNoiseLite.new()
	detail_noise.seed = 7331
	detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	detail_noise.frequency = 0.05 # Tiny bumps
	detail_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	detail_noise.fractal_octaves = 3
	detail_noise.fractal_gain = 0.6
	
	# 2. Define Bezier Curve for the Road
	# The road goes roughly from local (0,0,0) down to (offset_x, 0, -CHUNK_SIZE)
	start_pos = Vector3.ZERO
	# End position wanders left/right based on rotation
	var end_offset_x = sin(next_turn_angle) * CHUNK_SIZE * 0.5
	end_pos = Vector3(end_offset_x, 0, -CHUNK_SIZE)
	
	# Control points ensure the road starts straight and ends straight in the new direction
	control_p1 = Vector3(0, 0, -CHUNK_SIZE * 0.33)
	control_p2 = end_pos + Vector3(-sin(next_turn_angle) * CHUNK_SIZE * 0.33, 0, CHUNK_SIZE * 0.33)
	
	# Determine if this chunk has a house (30% chance)
	has_house = randf() < 0.3
	if has_house:
		# Random position within the chunk, avoiding the very edges
		var hx = randf_range(-CHUNK_SIZE/2.0 + 20.0, CHUNK_SIZE/2.0 - 20.0)
		var hz = randf_range(-CHUNK_SIZE + 20.0, -20.0)
		var global_hp = global_transform * Vector3(hx, 0, hz)
		
		# Foundation must be perfectly flat, so micro_multiplier = 0.0
		var h_height = _get_terrain_height(global_hp.x, global_hp.z, 0.0)
		
		# Calculate distance to road center to ensure it's not literally on the asphalt
		var curve_data = _get_closest_curve_point(hx, hz)
		var curve_pt: Vector3 = curve_data[0]
		var dist_to_road = Vector2(curve_pt.x - hx, curve_pt.z - hz).length()
		
		if dist_to_road < ROAD_WIDTH / 2.0 + 10.0:
			has_house = false # Too close to the road, cancel spawn
		else:
			house_local_pos = Vector3(hx, h_height - global_transform.origin.y, hz)
	
	# 3. Generate the Meshes
	_build_terrain_mesh()
	_build_road_mesh()
	
	# Calculate global end transform for the next chunk to hook into
	var end_basis = Basis(Vector3.UP, next_turn_angle)
	
	# Match the physical height of the road at the end of the chunk!
	# The end of the chunk is perfectly on the center of the road, so micro_multiplier = 0.0
	var global_end = global_transform * end_pos
	var true_end_height = _get_terrain_height(global_end.x, global_end.z, 0.0)
	
	# The local end transform must reflect the height difference from our start
	end_pos.y = true_end_height - global_transform.origin.y
	
	var local_end_transform = Transform3D(end_basis, end_pos)
	
	if has_house:
		_spawn_house()
		
	return global_transform * local_end_transform

func _cubic_bezier(t: float) -> Vector3:
	var q0 = start_pos.lerp(control_p1, t)
	var q1 = control_p1.lerp(control_p2, t)
	var q2 = control_p2.lerp(end_pos, t)
	
	var r0 = q0.lerp(q1, t)
	var r1 = q1.lerp(q2, t)
	
	return r0.lerp(r1, t)

# Find closest point on bezier curve to a given 2D (x,z) point.
# Returns [closest_point_on_curve, t_value]
func _get_closest_curve_point(px: float, pz: float) -> Array:
	var closest_dist = INF
	var closest_pt = Vector3.ZERO
	var closest_t = 0.0
	
	# Sample the curve to find roughly where we are
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

func _build_terrain_mesh():
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Overlap chunks by increasing the physical footprint to hide tears!
	var overlap = 4.0
	var step_z = (CHUNK_SIZE + overlap * 2.0) / RESOLUTION
	var step_x = (CHUNK_SIZE + overlap * 2.0) / RESOLUTION
	var half_size_x = (CHUNK_SIZE + overlap * 2.0) / 2.0
	
	# Center the terrain around the average curve
	var x_offset = end_pos.x / 2.0 
	
	# Generate Vertices and Colors
	var grid_data = [] # Stores [Vector3, Color]
	for zi in range(RESOLUTION + 1):
		grid_data.append([])
		for xi in range(RESOLUTION + 1):
			# Start at z = +overlap and go to z = -CHUNK_SIZE - overlap
			var lz = overlap - float(zi) * step_z
			var lx = float(xi) * step_x - half_size_x + x_offset
			
			var global_p = global_transform * Vector3(lx, 0, lz)
			
			# Calculate distance to road FIRST, so we know how bumpy the terrain should be
			var curve_data = _get_closest_curve_point(lx, lz)
			var curve_pt: Vector3 = curve_data[0]
			var dist_to_road = Vector2(curve_pt.x - lx, curve_pt.z - lz).length()
			
			# Smooth road (0.0 multiplier) gradually blending into bumpy terrain (1.0 multiplier)
			var micro_mult = clamp((dist_to_road - ROAD_WIDTH / 2.0) / (ROAD_BLEND_DISTANCE * 0.5), 0.0, 1.0)
			
			# Factor in house foundation distance
			var blend_factor = 1.0
			var dist_to_house = INF
			if has_house:
				dist_to_house = Vector2(house_local_pos.x - lx, house_local_pos.z - lz).length()
				var foundation_radius = 8.0 # Flat area size
				var house_blend = 10.0 # Transition slope size
				if dist_to_house < foundation_radius:
					micro_mult = 0.0
					blend_factor = 0.0
				elif dist_to_house < foundation_radius + house_blend:
					var t = (dist_to_house - foundation_radius) / house_blend
					micro_mult = min(micro_mult, t)
					blend_factor = t
			
			# Terrain now completely dictates the height, no flattening!
			var final_h = _get_terrain_height(global_p.x, global_p.z, micro_mult)
			var local_h = final_h - global_transform.origin.y
			
			# Flatten to house height
			if has_house and blend_factor < 1.0:
				local_h = lerp(house_local_pos.y, local_h, blend_factor)
				
			var col = Color.WHITE
			
			if dist_to_house < 8.0:
				var dirt_factor = clamp(abs(local_h) / MAX_HEIGHT, 0.0, 1.0)
				col = Color(0.3, 0.35, 0.2).lerp(Color(0.5, 0.45, 0.3), dirt_factor) # Dirt under house
			elif dist_to_road < ROAD_WIDTH / 2.0:
				col = Color(0.2, 0.25, 0.1) # Dirt directly under the road
			elif dist_to_road < ROAD_WIDTH / 2.0 + ROAD_BLEND_DISTANCE:
				col = Color(0.3, 0.35, 0.2) # Dirt transition
			else:
				var dirt_factor = clamp(abs(local_h) / MAX_HEIGHT, 0.0, 1.0)
				col = Color(0.4, 0.5, 0.2).lerp(Color(0.6, 0.5, 0.3), dirt_factor) # Grass to Rock
				
			grid_data[zi].append([Vector3(lx, local_h, lz), col])
			
	# Build Triangles
	for zi in range(RESOLUTION):
		for xi in range(RESOLUTION):
			var d0 = grid_data[zi][xi]
			var d1 = grid_data[zi][xi+1]
			var d2 = grid_data[zi+1][xi]
			var d3 = grid_data[zi+1][xi+1]
			
			# Triangle 1 (v0, v2, v1)
			st.set_color(d0[1])
			st.set_uv(Vector2(float(xi)/RESOLUTION, float(zi)/RESOLUTION))
			st.add_vertex(d0[0])
			
			st.set_color(d2[1])
			st.set_uv(Vector2(float(xi)/RESOLUTION, float(zi+1)/RESOLUTION))
			st.add_vertex(d2[0])
			
			st.set_color(d1[1])
			st.set_uv(Vector2(float(xi+1)/RESOLUTION, float(zi)/RESOLUTION))
			st.add_vertex(d1[0])
			
			# Triangle 2 (v1, v2, v3)
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
	
	# Optimize mesh by indexing vertices (merges duplicates)
	st.index()
	var mesh = st.commit()
	
	# Instantiate MeshInstance
	var mesh_node = MeshInstance3D.new()
	mesh_node.mesh = mesh
	add_child(mesh_node)
	
	# Add simple vertex color material
	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	mesh_node.material_override = mat
	
	# Add Collision
	var shape = ConcavePolygonShape3D.new()
	shape.set_faces(mesh.get_faces())
	
	var col_node = CollisionShape3D.new()
	col_node.shape = shape
	
	var static_body = StaticBody3D.new()
	static_body.add_child(col_node)
	mesh_node.add_child(static_body)

func _build_road_mesh():
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# High resolution for the road to make the curve completely smooth
	var road_segments = 60
	var half_width = ROAD_WIDTH / 2.0
	
	# Go slightly beyond 0 and 1 to create an overlap (hides tears in the road)
	var start_idx = -2
	var end_idx = road_segments + 2
	var total_verts = 0
	
	for i in range(start_idx, end_idx + 1):
		var t = float(i) / road_segments
		var center = _cubic_bezier(t)
		
		# Calculate tangent
		var t_next = t + 0.01
		var tangent = (_cubic_bezier(t_next) - center).normalized()
			
		var right = tangent.cross(Vector3.UP).normalized()
		
		var left_v = center - right * half_width
		var right_v = center + right * half_width
		
		# Sample true terrain height at the road edges
		# We're building the road, so micro_multiplier = 0.0 for completely smooth asphalt
		var global_left_p = global_transform * left_v
		var global_right_p = global_transform * right_v
		
		var left_h = _get_terrain_height(global_left_p.x, global_left_p.z, 0.0)
		var right_h = _get_terrain_height(global_right_p.x, global_right_p.z, 0.0)
		
		# Clamp the lateral tilt (max difference in height between left and right)
		# 10 degrees is a safe maximum for a heavy RV
		var max_tilt_angle_rad = deg_to_rad(10.0) 
		var max_height_diff = ROAD_WIDTH * tan(max_tilt_angle_rad)
		
		var current_diff = right_h - left_h
		if abs(current_diff) > max_height_diff:
			# If it's too tilted, we average the heights and re-apply the max allowed tilt
			var avg_h = (left_h + right_h) / 2.0
			var limited_diff = sign(current_diff) * max_height_diff
			left_h = avg_h - (limited_diff / 2.0)
			right_h = avg_h + (limited_diff / 2.0)
		
		# Bring the local heights relative to the chunk origin
		left_v.y = left_h - global_transform.origin.y + 0.15
		right_v.y = right_h - global_transform.origin.y + 0.15
		
		st.set_color(Color(0.2, 0.2, 0.2)) # Asphalt
		st.set_uv(Vector2(0, t))
		st.add_vertex(left_v)
		
		st.set_color(Color(0.2, 0.2, 0.2)) # Asphalt
		st.set_uv(Vector2(1, t))
		st.add_vertex(right_v)
		total_verts += 1
		
	# Build the strip
	for i in range(total_verts - 1):
		var vert_idx = i * 2
		# Triangle 1 (Clockwise)
		st.add_index(vert_idx)
		st.add_index(vert_idx + 2)
		st.add_index(vert_idx + 1)
		# Triangle 2 (Clockwise)
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
	
	# Add Collision for the road
	var shape = ConcavePolygonShape3D.new()
	shape.set_faces(mesh.get_faces())
	
	var col_node = CollisionShape3D.new()
	col_node.shape = shape
	
	var static_body = StaticBody3D.new()
	static_body.add_child(col_node)
	mesh_node.add_child(static_body)
	
	add_child(mesh_node)

func _spawn_house():
	var house_scene = load("res://scenes/house.tscn")
	if not house_scene: return
	
	var house = house_scene.instantiate()
	house.position = house_local_pos
	# Random Y rotation to make it feel organic
	house.rotation.y = randf_range(0, TAU)
	add_child(house)
	
	# Spawn loot
	var scrap_scene = load("res://scenes/scrap.tscn")
	var oil_scene = load("res://scenes/oil_barrel.tscn")
	var spawns = house.get_node_or_null("LootSpawns")
	
	if spawns and spawns.get_child_count() > 0:
		# Spawn 1 to 3 items
		var num_items = randi_range(1, 3)
		var spawn_points = spawns.get_children()
		spawn_points.shuffle()
		
		for i in range(min(num_items, spawn_points.size())):
			var is_scrap = randf() > 0.3
			var item
			if is_scrap and scrap_scene: 
				item = scrap_scene.instantiate()
			elif oil_scene: 
				item = oil_scene.instantiate()
				
			if item:
				var sp = spawn_points[i]
				item.position = sp.position 
				house.add_child(item)
