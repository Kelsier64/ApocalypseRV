extends RefCounted
class_name FloraMeshes
## Small native ground cover. Batched visuals never add snagging colliders.
static var cache: Dictionary = {}

static func ground(kind: int) -> ArrayMesh:
	if cache.has(kind): return cache[kind]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7014 + kind
	if kind == 4:
		# A low opaque crown fills the sight gap below tall tree canopies.
		for i in range(5):
			var center := Vector3(sin(i * 2.4) * 0.28, 0.42 + i * 0.10, cos(i * 2.4) * 0.25)
			ForestMeshes._tube(st, Vector3(0, 0.02, 0), center, 0.023, 0.008, Color("77715b"), 4)
			ForestMeshes._crown(st, center, Vector3(0.45, 0.32, 0.42), Color("48563b").lightened(i * 0.025), rng)
			ForestMeshes._bough(st, center, center + Vector3(sin(i * 2.4), 0.15, cos(i * 2.4)) * 0.60, 0.18, Color("506240"))
	elif kind == 2:
		for i in range(4):
			var center := Vector3(rng.randf_range(-0.4, 0.4), 0.02, rng.randf_range(-0.4, 0.4))
			var height := rng.randf_range(0.09, 0.24)
			var radius := rng.randf_range(0.10, 0.25)
			for j in range(5):
				var a := center + Vector3(cos(j * TAU / 5), 0, sin(j * TAU / 5)) * radius
				var b := center + Vector3(cos((j + 1) * TAU / 5), 0, sin((j + 1) * TAU / 5)) * radius
				ForestMeshes._triangle(st, a, center + Vector3.UP * height, b, Color("77786c").darkened(i * 0.04))
	else:
		var count := 8 if kind == 1 else (10 if kind == 0 else 6)
		for i in range(count):
			var angle := i * 2.399
			var axis := Vector3(cos(angle), 0, sin(angle))
			var root := axis * rng.randf_range(0.03, 0.28)
			var height := rng.randf_range(0.95, 1.75) if kind == 1 else rng.randf_range(0.22, 0.65)
			var tip := root + Vector3.UP * height + axis * (0.07 if kind == 1 else 0.23)
			var width := 0.022 if kind == 1 else 0.065
			var side := axis.cross(Vector3.UP) * width
			var color := Color("666b43") if kind == 1 else (Color("63714b") if kind == 0 else Color("495a3e"))
			ForestMeshes._triangle(st, root - side, tip, root + side, color.darkened(rng.randf_range(0, 0.15)))
			if kind == 1:
				ForestMeshes._tube(st, tip - Vector3.UP * 0.23, tip + Vector3.UP * 0.08, 0.025, 0.018, Color("5c4930"), 4)
			elif kind == 3:
				ForestMeshes._bough(st, root + Vector3.UP * 0.14, tip, 0.15, color)
	st.generate_normals()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	if kind == 4: mat.vertex_color_is_srgb = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	mat.metallic_specular = 0.0
	mesh.surface_set_material(0, mat)
	cache[kind] = mesh
	return mesh
