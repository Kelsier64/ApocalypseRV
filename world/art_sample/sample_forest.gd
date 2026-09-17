extends RefCounted
class_name SampleForest
## Bent branch skeletons and cutout needles replace closed cone canopies.
## The lower trunk remains on the production collision column.
static var cache: Dictionary = {}

static func tree(kind: int, shrub: bool = false) -> ArrayMesh:
	var key := str(kind) + str(shrub)
	if cache.has(key): return cache[key]
	var wood := SurfaceTool.new()
	var leaf := SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	leaf.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7361 + kind * 179 + (401 if shrub else 0)
	var bend := Vector3(0.14 * sin(kind + 1.0), 0, 0.10 * cos(kind * 3.0))
	var bark := Color("70695b")
	var trunk: Array[Vector3] = [Vector3.ZERO, Vector3(0, 0.3, 0), Vector3.UP * 0.64 + bend * 0.35, Vector3.UP * 0.98 + bend]
	if shrub: trunk = [Vector3.ZERO, Vector3(0, 0.18, 0), Vector3(0.11, 0.56, 0), Vector3(-0.06, 0.92, 0.03)]
	for i in range(3):
		_tube(wood, trunk[i], trunk[i+1], (0.08 if not shrub else 0.027) * (1.0 - i * 0.27), 0.018 if i == 2 else 0.048 - i * 0.017, bark, 5)
	var branches := 18 if not shrub else 9
	for i in range(branches):
		var y := 0.31 + float(i) / branches * 0.58 if not shrub else 0.10 + float(i) / branches * 0.6
		var angle := i * 2.399 + kind * 0.83 + rng.randf_range(-0.4, 0.4)
		var reach := (1.0 - y) * rng.randf_range(1.25, 2.0) if not shrub else rng.randf_range(0.6, 1.1)
		var root := Vector3(0, y, 0) + bend * maxf(0, y - 0.3)
		var direction := Vector3(cos(angle), 0, sin(angle))
		var tip := root + direction * reach + Vector3.UP * rng.randf_range(-0.1, 0.07)
		_tube(wood, root, tip, 0.015 if not shrub else 0.01, 0.003, bark, 3)
		# Bare broken branches puncture the canopy instead of a solid silhouette.
		if kind >= 4 or i % 6 == 0: continue
		var side := direction.cross(Vector3.UP)
		for twig in range(3):
			var start := root.lerp(tip, 0.30 + twig * 0.20)
			for sign_value in [-1.0, 1.0]:
				var end: Vector3 = start + direction * reach * 0.32 + side * sign_value * reach * (0.39 - twig * 0.065)
				end.y += rng.randf_range(-0.06, 0.04)
				var tint := Color("738075").darkened(rng.randf_range(0.0, 0.22))
				_frond(leaf, start, end, 0.16 + reach * 0.19, tint)
				# Tilted second plane keeps needles readable at player eye height.
				_frond(leaf, start, end + Vector3.UP * 0.035, 0.12 + reach * 0.11, tint.darkened(0.08), true)
	wood.generate_normals()
	var mesh := wood.commit()
	mesh.surface_set_material(0, SampleMaterials.surface("bark", Color.WHITE))
	if kind < 4:
		leaf.generate_normals()
		leaf.commit(mesh)
		mesh.surface_set_material(1, SampleMaterials.surface("needles", Color.WHITE))
	cache[key] = mesh
	return mesh

static func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, tint: Color) -> void:
	st.set_color(tint)
	for p in [a, b, c]:
		st.set_uv(Vector2(p.x * 7, p.y * 2))
		st.add_vertex(p)

static func _tube(st: SurfaceTool, a: Vector3, b: Vector3, radius: float, end_radius: float, tint: Color, sides: int) -> void:
	var axis := (b - a).normalized()
	var tangent := axis.cross(Vector3.FORWARD).normalized()
	var side := axis.cross(tangent).normalized()
	for i in range(sides):
		var p := tangent * cos(i * TAU / sides) + side * sin(i * TAU / sides)
		var q := tangent * cos((i + 1) * TAU / sides) + side * sin((i + 1) * TAU / sides)
		_triangle(st, a + p * radius, b + p * end_radius, a + q * radius, tint)
		_triangle(st, a + q * radius, b + p * end_radius, b + q * end_radius, tint)

static func _frond(st: SurfaceTool, a: Vector3, b: Vector3, width: float, tint: Color, upright: bool = false) -> void:
	var side := Vector3.UP * width * 0.55 if upright else (b-a).normalized().cross(Vector3.UP) * width
	var points := [a - side * 0.4, a + side * 0.4, b + side, b - side]
	var uv := [Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)]
	st.set_color(tint)
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_uv(uv[i])
		st.add_vertex(points[i])
