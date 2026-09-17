@tool
extends RefCounted
class_name IndustrialArt
## Shared exterior material library. Does not mutate indoor source resources.
static var materials: Dictionary = {}
static var textures: Dictionary = {}

static func texture(kind: String) -> Texture2D:
	if textures.has(kind): return textures[kind]
	if kind == "paint" or kind == "steel":
		var path := "res://assets/materials/industrial/worn_paint.png"
		if ResourceLoader.exists(path):
			textures[kind] = load(path)
			return textures[kind]
	var noise := FastNoiseLite.new()
	noise.seed = 714 if kind == "bark" else 185
	noise.frequency = 0.035 if kind == "bark" else 0.06
	noise.fractal_octaves = 3
	if kind == "bark": noise.domain_warp_enabled = true
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color("73736b"), Color("bcb9a8"), Color("e5e0ce")])
	gradient.offsets = PackedFloat32Array([0.1, 0.55, 0.9])
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = gradient
	textures[kind] = tex
	return tex

static func material(kind: String, tint: Color) -> StandardMaterial3D:
	var key := kind + tint.to_html()
	if materials.has(key): return materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.albedo_texture = texture(kind)
	mat.roughness = 0.96
	mat.metallic = 0.12 if kind == "steel" else 0.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(0.7, 0.7, 0.7) if kind != "bark" else Vector3(3, 0.3, 3)
	materials[key] = mat
	return mat

static func dress_exterior(root: Node3D) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		if node.mesh == null: continue
		var source: Material = node.get_active_material(0)
		if not source is StandardMaterial3D: continue
		if source.emission_enabled or source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: continue
		var tint: Color = source.albedo_color
		var kind := "steel" if source.metallic > 0.3 or tint.v < 0.32 else "paint"
		if "concrete" in source.resource_path or "floor" in source.resource_path: kind = "concrete"
		node.material_override = material(kind, tint.lerp(Color("77746a"), 0.15))
