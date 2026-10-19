extends MeshInstance3D
class_name NightVisionEffect
## A world-owned mask: independent viewports use their own projection/depth.
## Ordinary transparent surfaces use background depth; weather samples its own.
const MASK_PRIORITY := 126
const WEATHER_PRIORITY := 127
const LUT_SIZE := 512
var curve_texture := ImageTexture.new()
var curve: Curve
var _materials: Array[ShaderMaterial] = []
var _strength := 0.0
var _fade_begin := 5.0
var _fade_end := 60.0

func _init() -> void:
	name = "NightVision"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ignore_occlusion_culling = true
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	mesh = quad
	var material := ShaderMaterial.new()
	material.shader = preload("res://world/night_vision.gdshader")
	material.render_priority = MASK_PRIORITY
	material_override = material
	_materials.append(material)
	visible = false

func _ready() -> void:
	# Clip-space geometry has no meaningful world-space bounding box.
	RenderingServer.instance_set_ignore_culling(get_instance(), true)

func configure(strength: float, fade_begin: float, fade_end: float, curve: Curve) -> void:
	_strength = clampf(strength, 0.0, 1.0)
	_fade_begin = maxf(0.0, fade_begin)
	_fade_end = maxf(_fade_begin + 0.001, fade_end)
	if self.curve != curve:
		if self.curve != null: self.curve.changed.disconnect(_bake_curve)
		self.curve = curve
		curve.changed.connect(_bake_curve)
		_bake_curve()
	visible = _strength > 0.0
	for material in _materials: _update_material(material)

func register_weather(material: ShaderMaterial) -> void:
	if _materials.has(material): return
	material.render_priority = WEATHER_PRIORITY
	_materials.append(material)
	_update_material(material)

func unregister_weather(material: ShaderMaterial) -> void:
	_materials.erase(material)

func _bake_curve() -> void:
	# Native CurveTexture omits X=1. Include both endpoints so zero stays black.
	var data := PackedByteArray()
	data.resize(LUT_SIZE * 4)
	for i in range(LUT_SIZE):
		data.encode_float(i * 4, curve.sample(float(i) / (LUT_SIZE - 1)))
	var image := Image.create_from_data(LUT_SIZE, 1, false, Image.FORMAT_RF, data)
	if curve_texture.get_width() == 0: curve_texture.set_image(image)
	else: curve_texture.update(image)

func _update_material(material: ShaderMaterial) -> void:
	material.set_shader_parameter("night_curve", curve_texture)
	material.set_shader_parameter("night_fade_begin", _fade_begin)
	material.set_shader_parameter("night_fade_end", _fade_end)
	material.set_shader_parameter("night_strength", _strength)
