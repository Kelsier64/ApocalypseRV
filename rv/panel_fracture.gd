extends RefCounted
## Fracture the authored panel pieces, retaining their paint and actual openings.
const MAX_PIECES := 48

static func build(surface: MeshInstance3D, rng: RandomNumberGenerator, budget: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	# Production shell geometry is authored from boxes; do not fabricate imported-model volumes.
	if not surface.mesh is BoxMesh: return result
	var bounds := surface.mesh.get_aabb()
	var size := bounds.size
	var thin := size.min_axis_index()
	var u := (thin + 1) % 3
	var v := (thin + 2) % 3
	var source := surface.get_active_material(0) as StandardMaterial3D
	if source == null or budget <= 0: return result
	var glass := source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
	var cell_size := 0.48 if glass else 1.35
	var columns := clampi(ceili(size[u] / cell_size), 1, 5)
	var rows := clampi(ceili(size[v] / cell_size), 1, 5)
	while columns * rows * (2 if glass and budget >= 2 else 1) > budget:
		if columns >= rows: columns -= 1
		else: rows -= 1
	var grid: Array[Vector3] = []
	for y in range(rows + 1):
		for x in range(columns + 1):
			var point := bounds.get_center()
			point[u] = bounds.position[u] + size[u] * float(x) / columns
			point[v] = bounds.position[v] + size[v] * float(y) / rows
			if x > 0 and x < columns: point[u] += rng.randf_range(-0.22, 0.22) * size[u] / columns
			if y > 0 and y < rows: point[v] += rng.randf_range(-0.22, 0.22) * size[v] / rows
			grid.append(point)
	for y in range(rows):
		for x in range(columns):
			var corners: Array[Vector3] = [grid[y * (columns + 1) + x], grid[y * (columns + 1) + x + 1],
				grid[(y + 1) * (columns + 1) + x + 1], grid[(y + 1) * (columns + 1) + x]]
			# Glass breaks into irregular triangular panes; sheet metal stays in larger bent plates.
			if glass and result.size() + 2 <= budget:
				result.append(_piece([corners[0], corners[1], corners[2]], thin, u, v, bounds, source, glass, rng, surface.global_transform))
				result.append(_piece([corners[0], corners[2], corners[3]], thin, u, v, bounds, source, glass, rng, surface.global_transform))
			else:
				result.append(_piece(corners, thin, u, v, bounds, source, glass, rng, surface.global_transform))
			if result.size() >= budget: return result
	return result

static func _piece(corners: Array[Vector3], thin: int, u: int, v: int, bounds: AABB,
		source: StandardMaterial3D, glass: bool, rng: RandomNumberGenerator, source_pose: Transform3D) -> Dictionary:
	var center := Vector3.ZERO
	for point in corners: center += point
	center /= corners.size()
	var normal := Vector3.ZERO
	normal[thin] = 1.0
	var thickness := minf(bounds.size[thin], 0.012) if glass else bounds.size[thin]
	var bend := 0.0 if glass else rng.randf_range(-0.055, 0.055) * minf(bounds.size[u], bounds.size[v])
	var skin := SurfaceTool.new()
	skin.begin(Mesh.PRIMITIVE_TRIANGLES)
	skin.set_smooth_group(-1)
	var edge := SurfaceTool.new()
	edge.begin(Mesh.PRIMITIVE_TRIANGLES)
	edge.set_smooth_group(-1)
	for i in range(corners.size()):
		var a := corners[i]
		var b := corners[(i + 1) % corners.size()]
		var front_a := a + normal * thickness * 0.5
		var front_b := b + normal * thickness * 0.5
		var back_a := a - normal * thickness * 0.5
		var back_b := b - normal * thickness * 0.5
		_triangle(skin, [center + normal * (thickness * 0.5 + bend), front_a, front_b], center, u, v, bounds)
		_triangle(skin, [center + normal * (-thickness * 0.5 + bend), back_b, back_a], center, u, v, bounds)
		_triangle(edge, [front_a, back_a, back_b], center, u, v, bounds)
		_triangle(edge, [front_a, back_b, front_b], center, u, v, bounds)
	skin.generate_normals()
	edge.generate_normals()
	var mesh := skin.commit()
	edge.commit(mesh)
	var paint := source.duplicate() as StandardMaterial3D
	# Wear has already darkened the paint. Detached pieces retain its texture, with exposed cut edges.
	paint.next_pass = null
	paint.cull_mode = BaseMaterial3D.CULL_DISABLED
	paint.uv1_offset += center * paint.uv1_scale
	if glass:
		paint.albedo_color = Color(0.25, 0.43, 0.46, 0.62)
		paint.metallic = 0.18
		paint.roughness = 0.18
	var cut := StandardMaterial3D.new()
	cut.albedo_color = Color("789697") if glass else Color("555953")
	cut.metallic = 0.15 if glass else 0.7
	cut.roughness = 0.3 if glass else 0.8
	cut.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, paint)
	mesh.surface_set_material(1, cut)
	return {"mesh": mesh, "center": center, "normal": normal, "glass": glass,
		"source_bounds": bounds, "source_transform": source_pose}

static func _triangle(tool: SurfaceTool, vertices: Array[Vector3], center: Vector3, u: int, v: int, bounds: AABB) -> void:
	for point in vertices:
		tool.set_uv(Vector2((point[u] - bounds.position[u]) / bounds.size[u], (point[v] - bounds.position[v]) / bounds.size[v]))
		tool.add_vertex(point - center)
