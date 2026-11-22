extends RefCounted
class_name BuildingKitMaterials
## Named finishes for BuildingKit. Each finish is a CC0 photo set (value detail)
## plus a tint from the GDD palette: cold grey, low saturation, industrial.
## Materials are cached per finish so every building shares the same surfaces.

const SHADER = preload("res://world/building_kit/building_kit.gdshader")
const TEXTURES := "res://assets/materials/building_kit/"

## set: texture set in TEXTURES; mean: the albedo's average colour (sRGB), used
## to normalise its value detail; meters: real-world size one texture tile covers.
const SETS := {
	"concrete_wall": {"mean": Color(0.284, 0.414, 0.311), "meters": 2.0},
	"concrete_floor": {"mean": Color(0.653, 0.524, 0.401), "meters": 2.08},
	"block_wall": {"mean": Color(0.272, 0.240, 0.199), "meters": 2.0},
	"plaster": {"mean": Color(0.588, 0.423, 0.364), "meters": 1.8},
	"corrugated": {"mean": Color(0.343, 0.160, 0.096), "meters": 2.0},
	"steel": {"mean": Color(0.673, 0.563, 0.354), "meters": 1.0},
	"tiles": {"mean": Color(0.266, 0.135, 0.062), "meters": 2.26},
	"planks": {"mean": Color(0.507, 0.478, 0.409), "meters": 1.6},
}

## The palette. Accents stay muted; keep_color > 0 lets rust and stains through.
static var finishes := {
	&"concrete": {"set": "concrete_wall", "tint": Color("7d8182"), "grime": 0.4, "detail": 0.7},
	&"slab": {"set": "concrete_floor", "tint": Color("7a7c79"), "grime": 0.2},
	&"block": {"set": "block_wall", "tint": Color("8e908c"), "grime": 0.45},
	&"plaster": {"set": "plaster", "tint": Color("9c9b94"), "grime": 0.4, "keep": 0.05},
	&"paint": {"set": "plaster", "tint": Color("6c7b7a"), "grime": 0.35, "keep": 0.08},
	&"corrugated": {"set": "corrugated", "tint": Color("686b69"), "keep": 0.12, "rough": 1.1},
	&"steel": {"set": "steel", "tint": Color("5d6462"), "keep": 0.35, "rough": 0.9, "grime": 0.2},
	&"trim": {"set": "steel", "tint": Color("3e4644"), "keep": 0.12, "grime": 0.15},
	&"tiles": {"set": "tiles", "tint": Color("8b8a82"), "grime": 0.15, "keep": 0.05},
	&"wood": {"set": "planks", "tint": Color("6f695f"), "keep": 0.15},
	&"accent": {"set": "plaster", "tint": Color("7f7660"), "keep": 0.05},
	&"glass": {"glass": true, "tint": Color("3a4746")},
}

static var _cache := {}


## Adds a named finish that reuses another's photo set with a new tint, for a
## building's own palette. Returns the name. Re-registering the same name is
## allowed only with identical settings, so shared materials stay consistent.
static func register(name: StringName, base: StringName, tint: Color) -> StringName:
	if not finishes.has(base):
		push_error("Unknown base finish %s" % base)
		return base
	var entry: Dictionary = finishes[base].duplicate()
	entry.tint = tint
	if finishes.has(name) and finishes[name] != entry:
		push_error("Finish %s is already registered with other settings" % name)
		return name
	finishes[name] = entry
	return name


static func has(finish: StringName) -> bool:
	return finishes.has(finish)


static func material(finish: StringName) -> Material:
	if _cache.has(finish):
		return _cache[finish]
	if not finishes.has(finish):
		push_error("Unknown building finish %s" % finish)
		finish = &"concrete"
	var entry: Dictionary = finishes[finish]
	var result: Material
	if entry.get("glass", false):
		var glass := StandardMaterial3D.new()
		glass.albedo_color = entry.tint
		glass.metallic = 0.55
		glass.roughness = 0.08
		glass.vertex_color_use_as_albedo = false
		result = glass
	else:
		var set_name: String = entry.set
		var info: Dictionary = SETS[set_name]
		var shader := ShaderMaterial.new()
		shader.shader = SHADER
		shader.set_shader_parameter("albedo_tex", load(TEXTURES + set_name + "_albedo.jpg"))
		shader.set_shader_parameter("normal_tex", load(TEXTURES + set_name + "_normal.jpg"))
		shader.set_shader_parameter("rough_tex", load(TEXTURES + set_name + "_roughness.jpg"))
		shader.set_shader_parameter("tint", entry.tint)
		shader.set_shader_parameter("mean_color", info.mean)
		shader.set_shader_parameter("texel_meters", info.meters)
		shader.set_shader_parameter("keep_color", entry.get("keep", 0.0))
		shader.set_shader_parameter("roughness_scale", entry.get("rough", 1.0))
		shader.set_shader_parameter("grime", entry.get("grime", 0.3))
		shader.set_shader_parameter("detail", entry.get("detail", 1.0))
		result = shader
	_cache[finish] = result
	return result
