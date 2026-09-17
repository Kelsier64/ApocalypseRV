extends RefCounted
class_name ForestMeshes
## Opaque low-poly boughs, aligned with the existing lower trunk collision.
static var cache: Dictionary = {}
static var materials: Dictionary = {}

static func tree(kind: int) -> ArrayMesh:
	var key := "tree%d" % kind
	if cache.has(key): return cache[key]
	var wood := SurfaceTool.new()
	var leaf := SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	leaf.begin(Mesh.PRIMITIVE_TRIANGLES)
	wood.set_smooth_group(-1)
	leaf.set_smooth_group(-1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + kind
	var bend := Vector3(sin(kind * 1.7) * 0.05, 0, cos(kind * 2.1) * 0.04)
	var bark := Color("a69984")
	_tube(wood, Vector3.ZERO, Vector3.UP * 0.55, 0.1, 0.057, bark, 6)
	var tip := Vector3.UP + bend
	_tube(wood, Vector3.UP * 0.55, tip, 0.057, 0.012, bark, 5)
	for i in range(5):
		var a := Vector3(cos(i * TAU / 5), 0, sin(i * TAU / 5)) * 0.012
		var b := Vector3(cos((i+1) * TAU / 5), 0, sin((i+1) * TAU / 5)) * 0.012
		_triangle(wood, tip, tip + b, tip + a, bark)
	for i in range(19):
		var y := 0.25 + i * 0.037
		var angle := i * 2.399 + kind * 0.87
		var direction := Vector3(cos(angle), 0, sin(angle))
		var root := Vector3.UP * y + bend * y
		var reach := (1.0 - y) * rng.randf_range(1.35, 1.95)
		var end := root + direction * reach + Vector3.UP * rng.randf_range(-0.065, 0.04)
		_tube(wood, root, end, 0.012, 0.002, bark, 3)
		if kind >= 4 or i % 7 == 0: continue
		var tint: Color = [Color("515345"), Color("5b5949"), Color("454e46"), Color("66604b")][kind]
		var side := direction.cross(Vector3.UP)
		for fork in [-1.0, 0.0, 1.0]:
			var start := root.lerp(end, 0.20)
			var edge: Vector3 = end + side * fork * reach * 0.52 + Vector3.UP * (0.045 if fork != 0 else -0.025)
			_bough(leaf, start, edge, reach * 0.44, tint.lightened(rng.randf_range(0, 0.10)))
	wood.generate_normals()
	var result := wood.commit()
	result.surface_set_material(0, _material(true))
	if kind < 4:
		leaf.generate_normals()
		leaf.commit(result)
		result.surface_set_material(1, _material(false))
	cache[key] = result
	return result

static func shrub(kind: int) -> ArrayMesh:
	var key := "shrub%d" % kind
	if cache.has(key): return cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for i in range(5):
		var angle := i * 2.399 + kind
		var end := Vector3(cos(angle) * 0.6, 0.55 + i * 0.09, sin(angle) * 0.6)
		_bough(st, Vector3(0, 0.08, 0), end, 0.2, Color("64634e").darkened(i * 0.035))
	st.generate_normals()
	var result := st.commit()
	result.surface_set_material(0, _material(false))
	cache[key] = result
	return result

static func _material(wood: bool) -> StandardMaterial3D:
	if materials.has(wood): return materials[wood]
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.metallic_specular = 0.0
	if wood:
		mat.albedo_texture = preload("res://assets/materials/style_sample/bark.svg")
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	else:
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.albedo_texture = preload("res://assets/materials/outdoor/bough.svg")
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	materials[wood] = mat
	return mat

static func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, tint: Color) -> void:
	st.set_color(tint)
	for p in [a, b, c]:
		st.set_uv(Vector2((p.x + p.z) * 4.0, p.y * 2.0))
		st.add_vertex(p)

static func _tube(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, tint: Color, sides: int) -> void:
	var axis := (b-a).normalized()
	var tangent := axis.cross(Vector3.FORWARD).normalized()
	var side := axis.cross(tangent).normalized()
	for i in range(sides):
		var p := tangent * cos(i * TAU / sides) + side * sin(i * TAU / sides)
		var q := tangent * cos((i+1) * TAU / sides) + side * sin((i+1) * TAU / sides)
		_triangle(st, a+p*ra, b+p*rb, a+q*ra, tint)
		_triangle(st, a+q*ra, b+p*rb, b+q*rb, tint)

static func _bough(st: SurfaceTool, a: Vector3, b: Vector3, width: float, tint: Color) -> void:
	var axis := b-a
	var side := axis.normalized().cross(Vector3.UP) * width
	# Serrated perimeter and a raised spine give real shaded facets.
	var outline: Array[Vector3] = []
	for i in range(8):
		var t := float(i) / 8.0
		outline.append(a + axis * t + side * (0.48 if i % 2 == 0 else 1.0) * (1.0-t*0.6))
	outline.append(b)
	for i in range(7, -1, -1):
		var t := float(i) / 8.0
		outline.append(a + axis * t - side * (0.55 if i % 2 == 0 else 0.9) * (1.0-t*0.6))
	var spine := a.lerp(b, 0.45) + Vector3.UP * width * 0.09
	for i in range(outline.size()):
		_triangle(st, outline[i], spine, outline[(i+1) % outline.size()], tint)
