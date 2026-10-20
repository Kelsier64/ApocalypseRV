extends RefCounted
class_name ForestMeshes
## Opaque low-poly boughs, aligned with the existing lower trunk collision.
static var cache: Dictionary = {}
static var materials: Dictionary = {}

static func tree(kind: int) -> ArrayMesh:
	var key := "tree%d" % kind
	if cache.has(key): return cache[key]
	if kind >= 6: return _broadleaf(kind)
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

static func _broadleaf(kind: int) -> ArrayMesh:
	var wood := SurfaceTool.new()
	var leaf := SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	leaf.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1400 + kind
	var bend := Vector3(0.06 if kind == 6 else -0.08, 0, 0.035)
	var bark := Color("8c8877")
	_tube(wood, Vector3.ZERO, Vector3.UP * 0.45, 0.10, 0.065, bark, 7)
	_tube(wood, Vector3.UP * 0.45, Vector3.UP * 0.84 + bend, 0.065, 0.015, bark, 6)
	for i in range(6):
		var angle := i * 2.399 + kind
		var start := Vector3.UP * (0.40 + i * 0.046) + bend * 0.4
		var reach := rng.randf_range(0.50, 0.92) * (0.85 if kind == 7 else 1.0)
		var end := Vector3(cos(angle) * reach, rng.randf_range(0.62, 0.82), sin(angle) * reach) + bend
		_tube(wood, start, end, 0.035, 0.007, bark, 5)
		_crown(leaf, end + Vector3.UP * 0.05, Vector3(0.62, 0.19, 0.57), Color("505c3d") if kind == 6 else Color("5c6349"), rng)
	_crown(leaf, Vector3.UP * 0.87 + bend, Vector3(0.63, 0.15, 0.61), Color("626e4b"), rng)
	wood.generate_normals()
	leaf.generate_normals()
	var mesh := wood.commit()
	mesh.surface_set_material(0, _material(true))
	leaf.commit(mesh)
	# Solid crowns use their own facets and tint rather than the needle pattern.
	if not materials.has("broadleaf"):
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.roughness = 1.0
		material.metallic_specular = 0.0
		material.set_meta("forest_foliage", true)
		materials["broadleaf"] = material
	mesh.surface_set_material(1, materials["broadleaf"])
	cache["tree%d" % kind] = mesh
	return mesh

static func _crown(st: SurfaceTool, center: Vector3, size: Vector3, tint: Color, rng: RandomNumberGenerator) -> void:
	var rings: Array[PackedVector3Array] = []
	for level: float in [-0.60, 0.0, 0.65]:
		var ring := PackedVector3Array()
		for i in range(7):
			var angle := i * TAU / 7.0
			var radius := (1.0 if level == 0 else 0.72) * rng.randf_range(0.87, 1.08)
			ring.append(center + Vector3(cos(angle) * radius * size.x, level * size.y, sin(angle) * radius * size.z))
		rings.append(ring)
	for i in range(7):
		var next := (i + 1) % 7
		_triangle(st, center - Vector3.UP * size.y, rings[0][next], rings[0][i], tint.darkened(0.12))
		for row in range(2):
			var color := tint.lightened(row * 0.06)
			_triangle(st, rings[row][i], rings[row][next], rings[row + 1][i], color)
			_triangle(st, rings[row][next], rings[row + 1][next], rings[row + 1][i], color)
		_triangle(st, rings[2][i], rings[2][next], center + Vector3.UP * size.y, tint.lightened(0.10))

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
