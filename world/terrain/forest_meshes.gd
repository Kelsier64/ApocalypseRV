extends RefCounted
class_name ForestMeshes
## Four broken pine silhouettes, two snags and three irregular shrubs.
## Geometry is cached once, and only used by MultiMesh visual instances.
static var cache: Dictionary = {}

static func tree(kind: int) -> ArrayMesh:
	var key := "tree%d" % kind
	if cache.has(key): return cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + kind
	var bark := Color("625748")
	# The full lower trunk stays centred on the original collision column.
	_tube(st, Vector3.ZERO, Vector3(0.015 * (kind - 2), 1, 0.01), 0.10, 0.025, bark, 5)
	for tier in range(4):
		var y := 0.25 + tier * 0.16
		var angle := tier * 2.39 + kind * 0.9
		var reach := (0.96 - y) * (0.4 if kind < 4 else 0.28)
		var end := Vector3(cos(angle) * reach, y + 0.035, sin(angle) * reach)
		_tube(st, Vector3(0, y, 0), end, 0.014, 0.003, bark)
		if kind >= 4: continue
		var leaf: Color = [Color("536051"), Color("5b6050"), Color("414f47"), Color("686853")][kind]
		var radius := (1.0 - y) * 1.27
		var center := Vector3(cos(angle) * radius * 0.18, y, sin(angle) * radius * 0.18)
		_crown(st, rng, center, radius, 0.28, leaf, tier)
	if kind < 4: _crown(st, rng, Vector3(0.035, 0.88, 0), 0.16, 0.16, Color("536051"), 5)
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, _material())
	cache[key] = mesh
	return mesh

static func shrub(kind: int) -> ArrayMesh:
	var key := "shrub%d" % kind
	if cache.has(key): return cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 401 + kind
	for branch in range(2):
		var angle := branch * 2.4 + kind
		var end := Vector3(cos(angle) * 0.65, rng.randf_range(0.5, 1.0), sin(angle) * 0.65)
		_tube(st, Vector3.ZERO, end, 0.025, 0.007, Color("6b6151"))
		_crown(st, rng, end * 0.7, 0.58, 0.32, [Color("77745b"), Color("636854"), Color("555e4e")][kind], branch)
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, _material())
	cache[key] = mesh
	return mesh

static func _material() -> StandardMaterial3D:
	var mat := IndustrialArt.material("foliage", Color.WHITE).duplicate() as StandardMaterial3D
	mat.vertex_color_use_as_albedo = true
	mat.metallic_specular = 0.0
	# The baked meshes already carry UVs; avoid three texture samples per leaf.
	mat.uv1_triplanar = false
	mat.uv1_scale = Vector3(1, 2, 1)
	return mat

static func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	st.set_color(color)
	for point in [a, b, c]:
		st.set_uv(Vector2(point.x, point.y))
		st.add_vertex(point)

static func _tube(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, color: Color, sides: int = 3) -> void:
	var axis := (b - a).normalized()
	var tangent := axis.cross(Vector3.FORWARD).normalized()
	var side := axis.cross(tangent).normalized()
	for i in range(sides):
		var p := tangent * cos(i * TAU / sides) + side * sin(i * TAU / sides)
		var q := tangent * cos((i + 1) * TAU / sides) + side * sin((i + 1) * TAU / sides)
		_triangle(st, a + p * ra, b + p * rb, a + q * ra, color)
		_triangle(st, a + q * ra, b + p * rb, b + q * rb, color)

static func _crown(st: SurfaceTool, rng: RandomNumberGenerator, center: Vector3, radius: float, height: float, color: Color, tier: int) -> void:
	st.set_smooth_group(-1)
	var ring: Array[Vector3] = []
	for i in range(6):
		var angle := i * TAU / 6 + tier * 0.43
		var r := radius * rng.randf_range(0.55, 1.08)
		ring.append(center + Vector3(cos(angle) * r, rng.randf_range(-0.07, 0.035), sin(angle) * r))
	var peak := center + Vector3(radius * 0.15, height, -radius * 0.12)
	for i in range(6):
		var tint := color * rng.randf_range(0.8, 1.08)
		tint.a = 1
		_triangle(st, ring[(i + 1) % 6], peak, ring[i], tint)
		_triangle(st, ring[i], center - Vector3.UP * 0.1, ring[(i + 1) % 6], tint.darkened(0.2))
