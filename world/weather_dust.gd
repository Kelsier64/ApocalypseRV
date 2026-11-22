extends Node3D
class_name WeatherDust
## Blowing grit and low rolling dust clouds around the camera, scaled by
## WorldClock.dust. Built like WeatherRain: fixed-seed MultiMesh fields animated
## in the shader, a fixed particle budget, and only uniforms updated per frame.
## Roof shelter (cover caches and roof shapes) is WeatherRain's; dust adds no rays.
const GRIT_COUNT := 6144
const GRIT_RADIUS := 18.0
const GRIT_HEIGHT := 4.0
const PUFF_COUNT := 96
const PUFF_RADIUS := 40.0
const PUFF_HEIGHT := 3.0
## Seconds for the dust's travel to follow a change in wind.
const WIND_RESPONSE := 1.0
## Drift wraps at a common multiple of both field widths, keeping floats small.
const DRIFT_PERIOD := 720.0
## Below this the fields hide entirely.
const MIN_DUST := 0.001

var clock: WorldClock
var rain: WeatherRain
var fields: Array[MultiMeshInstance3D] = []
var materials: Array[ShaderMaterial] = []
var drift := Vector3.ZERO
var flow := Vector3.ZERO
var simulation_time := 0.0
var visible_particles := 0

func _ready() -> void:
	var noise := NoiseTexture2D.new()
	noise.seamless = true
	noise.width = 128
	noise.height = 128
	noise.noise = FastNoiseLite.new()
	noise.noise.seed = 5821
	noise.noise.frequency = 0.03
	_build_field("DustGrit", GRIT_COUNT, GRIT_RADIUS, GRIT_HEIGHT, false, noise, 2207)
	_build_field("DustClouds", PUFF_COUNT, PUFF_RADIUS, PUFF_HEIGHT, true, noise, 6113)

func _build_field(field_name: String, count: int, radius: float, height: float, puff: bool, noise: Texture2D, seed_value: int) -> void:
	var field := MultiMeshInstance3D.new()
	field.name = field_name
	field.layers = NightVisionEffect.LIGHT_LAYER
	field.multimesh = MultiMesh.new()
	field.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	field.multimesh.use_custom_data = true
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	var material := ShaderMaterial.new()
	material.shader = preload("res://world/dust_field.gdshader")
	material.set_shader_parameter("radius", radius)
	material.set_shader_parameter("band_height", height)
	material.set_shader_parameter("puff", puff)
	material.set_shader_parameter("noise", noise)
	material.set_shader_parameter("dust_color", clock.atmosphere.dust_day_color)
	# Grit stays inside the fine cache; clouds reach past it into the coarse one.
	material.set_shader_parameter("cover", rain.far_cover.texture if puff else rain.near_cover.texture)
	material.set_shader_parameter("cover_cell", 3.0 if puff else 0.75)
	mesh.material = material
	field.multimesh.mesh = mesh
	field.multimesh.instance_count = count
	var seeds := RandomNumberGenerator.new()
	seeds.seed = seed_value
	for i in range(count):
		field.multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(seeds.randf_range(-radius, radius), 0.0, seeds.randf_range(-radius, radius))))
		field.multimesh.set_instance_custom_data(i, Color(seeds.randf(), seeds.randf(), seeds.randf(), seeds.randf()))
	field.multimesh.visible_instance_count = 0
	field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(field)
	fields.append(field)
	materials.append(material)
	rain.shelter_materials.append(material)

func _exit_tree() -> void:
	if is_instance_valid(rain):
		for material in materials: rain.shelter_materials.erase(material)

func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or not rain.sheltering or clock.dust <= MIN_DUST:
		visible_particles = 0
		for field in fields: field.multimesh.visible_instance_count = 0
		return
	simulation_time += delta
	flow = flow.lerp(clock.wind_velocity, 1.0 - exp(-delta / WIND_RESPONSE))
	drift += flow * delta
	drift.x = fposmod(drift.x, DRIFT_PERIOD)
	drift.z = fposmod(drift.z, DRIFT_PERIOD)
	var amount := clock.dust
	visible_particles = 0
	for i in range(fields.size()):
		var field := fields[i]
		var radius := GRIT_RADIUS if i == 0 else PUFF_RADIUS
		var count := ceili(field.multimesh.instance_count * (pow(amount, 1.2) if i == 0 else amount))
		field.multimesh.visible_instance_count = count
		visible_particles += count
		# Shader positions wrap around the real camera; keep CPU culling in agreement.
		field.custom_aabb = AABB(to_local(camera.global_position) - Vector3(radius + 8, 64, radius + 8), Vector3((radius + 8) * 2, 128, (radius + 8) * 2))
		materials[i].set_shader_parameter("camera_center", camera.global_position)
		materials[i].set_shader_parameter("drift", drift)
		materials[i].set_shader_parameter("flow", flow)
		materials[i].set_shader_parameter("simulation_time", simulation_time)
		materials[i].set_shader_parameter("density", smoothstep(0.0, 0.25, amount))
