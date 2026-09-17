extends RefCounted
class_name SampleMaterials
## Opt-in art study only. All resources are owned by the sample, never by saves.
static var cache: Dictionary = {}

static func surface(kind: String, tint: Color) -> StandardMaterial3D:
	var key := kind + tint.to_html()
	if cache.has(key): return cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.roughness = 0.92
	mat.metallic_specular = 0.18
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	if kind == "panel": mat.albedo_texture = preload("res://assets/materials/style_sample/panel.svg")
	if kind == "concrete":
		mat.albedo_texture = preload("res://assets/materials/style_sample/concrete.svg")
		mat.uv1_triplanar = true
		mat.uv1_scale = Vector3.ONE * 0.22
	if kind == "bark":
		mat.albedo_texture = preload("res://assets/materials/style_sample/bark.svg")
		mat.vertex_color_use_as_albedo = true
	if kind == "needles":
		mat.albedo_texture = preload("res://assets/materials/style_sample/needles.svg")
		mat.vertex_color_use_as_albedo = true
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.42
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.metallic_specular = 0.0
	cache[key] = mat
	return mat

static func box(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = at
	node.material_override = mat
	parent.add_child(node)
	return node

static func beam(parent: Node3D, a: Vector3, b: Vector3, width: float, mat: Material) -> MeshInstance3D:
	var node := box(parent, Vector3(width, width, a.distance_to(b)), (a + b) * 0.5, mat)
	node.basis = Basis.looking_at(b - a, Vector3.FORWARD if absf((b-a).normalized().y) > 0.99 else Vector3.UP)
	return node

static func caption(parent: Node3D, words: String, at: Vector3, size: int, color: Color = Color("d5c9a4")) -> void:
	var label := Label3D.new()
	label.text = words
	label.position = at
	label.font_size = size
	label.pixel_size = 0.012
	label.outline_size = 0
	label.modulate = color
	label.no_depth_test = false
	label.shaded = true
	parent.add_child(label)
