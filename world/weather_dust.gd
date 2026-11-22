extends Node3D
class_name WeatherDust
## Blowing dust around the camera, scaled by WorldClock.dust. Built like
## WeatherRain: fixed-seed MultiMesh fields animated in the shader, a fixed
## particle budget, and only uniforms updated per frame. Three fields:
## grit streaks skimming the ground, large clouds rolling past in the distance,
## and dense sheets streaming past close up that open and close the view.
## Billows add a volumetric FogVolume of rolling dust (Forward+ with
## volumetric fog only). Roof shelter (cover caches and roof shapes) is
## WeatherRain's; dust adds no rays.
const GRIT := 0
const CLOUDS := 1
const SHEETS := 2
const FIELDS := [
	{"name": "DustGrit", "count": 6144, "radius": 18.0, "height": 4.0, "puff": false, "far": false, "seed": 2207},
	{"name": "DustClouds", "count": 96, "radius": 40.0, "height": 3.0, "puff": true, "far": true, "seed": 6113,
		"size": Vector2(2.5, 6.5), "opacity": Vector2(0.05, 0.14), "lift": 0.8, "stretch": 1.0, "fade_span": 4.5, "glow": 0.25},
	{"name": "DustSheets", "count": 160, "radius": 16.0, "height": 3.2, "puff": true, "far": false, "seed": 8807,
		"size": Vector2(2.0, 4.5), "opacity": Vector2(0.12, 0.32), "lift": 0.9, "stretch": 2.4, "fade_span": 2.5, "glow": 0.35},
]
## Half the width of the billow box that follows the camera, and its height.
const BILLOW_RADIUS := 30.0
const BILLOW_HEIGHT := 14.0
## Seconds for the dust's travel to follow a change in wind.
const WIND_RESPONSE := 1.0
## Drift wraps at a common multiple of the field widths, keeping floats small.
const DRIFT_PERIOD := 1440.0
## Below this the fields hide entirely.
const MIN_DUST := 0.001

var clock: WorldClock
var rain: WeatherRain
var fields: Array[MultiMeshInstance3D] = []
var materials: Array[ShaderMaterial] = []
var billows: FogVolume
var billow_material: ShaderMaterial
## Session-only switches for playgrounds comparing the looks.
var show_sheets := true
var show_clouds := true
var show_billows := true
var drift := Vector3.ZERO
var billow_drift := Vector3.ZERO
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
	for spec: Dictionary in FIELDS: _build_field(spec, noise)
	# Fog shaders exist only with Forward+ volumetric fog.
	if clock.game_settings.supports_volumetric_fog(): _build_billows()

func _build_field(spec: Dictionary, noise: Texture2D) -> void:
	var field := MultiMeshInstance3D.new()
	field.name = spec.name
	field.layers = NightVisionEffect.LIGHT_LAYER
	field.multimesh = MultiMesh.new()
	field.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	field.multimesh.use_custom_data = true
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	var material := ShaderMaterial.new()
	material.shader = preload("res://world/dust_field.gdshader")
	var radius: float = spec.radius
	material.set_shader_parameter("radius", radius)
	material.set_shader_parameter("band_height", spec.height)
	material.set_shader_parameter("puff", spec.puff)
	material.set_shader_parameter("noise", noise)
	material.set_shader_parameter("dust_color", clock.atmosphere.dust_day_color)
	if spec.puff:
		material.set_shader_parameter("size_min", spec.size.x)
		material.set_shader_parameter("size_max", spec.size.y)
		material.set_shader_parameter("opacity_min", spec.opacity.x)
		material.set_shader_parameter("opacity_max", spec.opacity.y)
		material.set_shader_parameter("lift_min", spec.lift)
		material.set_shader_parameter("stretch", spec.stretch)
		material.set_shader_parameter("fade_span", spec.fade_span)
		material.set_shader_parameter("glow", spec.glow)
	# Near fields stay inside the fine cache; far ones reach into the coarse one.
	material.set_shader_parameter("cover", rain.far_cover.texture if spec.far else rain.near_cover.texture)
	material.set_shader_parameter("cover_cell", 3.0 if spec.far else 0.75)
	mesh.material = material
	field.multimesh.mesh = mesh
	field.multimesh.instance_count = spec.count
	var seeds := RandomNumberGenerator.new()
	seeds.seed = spec.seed
	for i in range(spec.count):
		field.multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(seeds.randf_range(-radius, radius), 0.0, seeds.randf_range(-radius, radius))))
		field.multimesh.set_instance_custom_data(i, Color(seeds.randf(), seeds.randf(), seeds.randf(), seeds.randf()))
	field.multimesh.visible_instance_count = 0
	field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(field)
	fields.append(field)
	materials.append(material)
	rain.shelter_materials.append(material)

func _build_billows() -> void:
	var noise := NoiseTexture3D.new()
	noise.seamless = true
	noise.width = 64
	noise.height = 64
	noise.depth = 64
	noise.noise = FastNoiseLite.new()
	noise.noise.seed = 3361
	noise.noise.frequency = 0.045
	noise.noise.fractal_octaves = 3
	billow_material = ShaderMaterial.new()
	billow_material.shader = load("res://world/dust_billows.gdshader")
	billow_material.set_shader_parameter("noise3d", noise)
	billow_material.set_shader_parameter("cover", rain.far_cover.texture)
	billow_material.set_shader_parameter("cover_cell", 3.0)
	billow_material.set_shader_parameter("radius", BILLOW_RADIUS)
	billows = FogVolume.new()
	billows.name = "DustBillows"
	billows.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	billows.size = Vector3(BILLOW_RADIUS * 2.0, BILLOW_HEIGHT, BILLOW_RADIUS * 2.0)
	billows.material = billow_material
	billows.visible = false
	add_child(billows)

func _exit_tree() -> void:
	if is_instance_valid(rain):
		for material in materials: rain.shelter_materials.erase(material)

## Share of the field budget shown at this dust amount.
static func field_share(field: int, amount: float) -> float:
	match field:
		GRIT: return pow(amount, 1.2)
		SHEETS: return smoothstep(0.3, 1.0, amount)
	return amount

func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or not rain.sheltering or clock.dust <= MIN_DUST:
		visible_particles = 0
		for field in fields: field.multimesh.visible_instance_count = 0
		if billows != null: billows.visible = false
		return
	simulation_time += delta
	flow = flow.lerp(clock.wind_velocity, 1.0 - exp(-delta / WIND_RESPONSE))
	drift += flow * delta
	drift.x = fposmod(drift.x, DRIFT_PERIOD)
	drift.z = fposmod(drift.z, DRIFT_PERIOD)
	# Billow noise tiles every dust_billow_scale metres; wrap on a whole number of tiles.
	var billow_period := clock.atmosphere.dust_billow_scale * 64.0
	billow_drift += flow * delta
	billow_drift.x = fposmod(billow_drift.x, billow_period)
	billow_drift.z = fposmod(billow_drift.z, billow_period)
	var amount := clock.dust
	var profile := clock.atmosphere
	var glow_color := clock.environment.fog_light_color
	visible_particles = 0
	for i in range(fields.size()):
		var field := fields[i]
		var radius: float = FIELDS[i].radius
		var shown: bool = [true, show_clouds, show_sheets][i]
		var count := ceili(field.multimesh.instance_count * field_share(i, amount)) if shown else 0
		field.multimesh.visible_instance_count = count
		visible_particles += count
		# Shader positions wrap around the real camera; keep CPU culling in agreement.
		field.custom_aabb = AABB(to_local(camera.global_position) - Vector3(radius + 8, 64, radius + 8), Vector3((radius + 8) * 2, 128, (radius + 8) * 2))
		var material := materials[i]
		material.set_shader_parameter("camera_center", camera.global_position)
		material.set_shader_parameter("drift", drift)
		material.set_shader_parameter("flow", flow)
		material.set_shader_parameter("simulation_time", simulation_time)
		material.set_shader_parameter("density", smoothstep(0.0, 0.25, amount))
		material.set_shader_parameter("glow_color", glow_color)
		match i:
			CLOUDS:
				material.set_shader_parameter("opacity_scale", profile.dust_cloud_opacity)
				material.set_shader_parameter("near_fade", profile.dust_cloud_near)
			SHEETS:
				material.set_shader_parameter("opacity_scale", profile.dust_sheet_opacity)
				material.set_shader_parameter("near_fade", profile.dust_sheet_near)
				material.set_shader_parameter("clump", profile.dust_sheet_clump)
	# Billows follow the haze dust so they do not pump with every gust.
	if billows == null: return
	billows.visible = show_billows and clock.haze_dust > MIN_DUST
	if billows.visible:
		billows.global_position = camera.global_position
		billow_material.set_shader_parameter("camera_center", camera.global_position)
		billow_material.set_shader_parameter("drift", billow_drift)
		billow_material.set_shader_parameter("simulation_time", simulation_time)
		billow_material.set_shader_parameter("density", profile.dust_billow_density * smoothstep(0.2, 1.0, clock.haze_dust))
		billow_material.set_shader_parameter("coverage", profile.dust_billow_coverage)
		billow_material.set_shader_parameter("scale", profile.dust_billow_scale)
		billow_material.set_shader_parameter("height", profile.dust_billow_height)
		billow_material.set_shader_parameter("albedo", clock.environment.volumetric_fog_albedo)
