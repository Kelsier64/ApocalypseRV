extends Node
class_name WorldClock
## One simulation clock per outdoor world, including time spent inside POIs.
signal minute_changed(day: int, hour: int, minute: int)
const DAY_SECONDS := 86400.0
const DEFAULT_TIME := 8.0 * 3600.0
@export_range(1.0, 1440.0) var day_length_minutes := 30.0
@export var atmosphere: WorldAtmosphereProfile = preload("res://world/world_atmosphere_profile.tres")
var elapsed_seconds := DEFAULT_TIME
var running := true
var weather := WorldWeather.new()
var deviation_fog := 0.0
var weather_running := true
var weather_label: Label
var fog_materials: Array[ShaderMaterial] = []
var environment: Environment
var sun: DirectionalLight3D
var sky_material: ShaderMaterial
var label: Label
var _last_minute := -1
var _stream_visibility := WorldStreamVisibility.new()
@onready var game_settings = get_node("/root/GameSettings")

func _ready() -> void:
	# Inherit the owning world's pause/staging state; an explicit PAUSABLE
	# mode would keep advancing even under a disabled checkpoint candidate.
	process_mode = Node.PROCESS_MODE_INHERIT
	var holder := get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	sun = get_parent().get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if holder != null:
		environment = holder.environment.duplicate(true) as Environment
		environment.background_mode = Environment.BG_SKY
		environment.fog_enabled = true
		environment.fog_mode = Environment.FOG_MODE_DEPTH
		environment.fog_density = 1.0
		environment.fog_height_density = 0.0
		environment.fog_sun_scatter = 0.0
		environment.fog_sky_affect = 1.0
		environment.volumetric_fog_sky_affect = 1.0
		environment.fog_light_energy = 1.0
		if game_settings.supports_volumetric_fog():
			# Concentrate froxels near the camera so fog behind a door does not bleed over it.
			environment.volumetric_fog_detail_spread = 2.0
			environment.volumetric_fog_anisotropy = 0.0
			environment.volumetric_fog_ambient_inject = 0.08
			# Moving flashlights/headlights need current-frame scattering. History
			# blending leaves their old beams in the fog after turning or switching off.
			environment.volumetric_fog_temporal_reprojection_enabled = false
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
		environment.sky = Sky.new()
		# Matte surfaces do not need a full-resolution reflection cubemap.
		environment.sky.radiance_size = Sky.RADIANCE_SIZE_32
		sky_material = ShaderMaterial.new()
		sky_material.shader = preload("res://world/terrain/overcast_v14.gdshader")
		environment.sky.sky_material = sky_material
		holder.environment = environment
	if sun != null:
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = 140.0
	var layer := CanvasLayer.new()
	layer.layer = 46
	add_child(layer)
	label = Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	label.position = Vector2(-224, 18)
	label.size = Vector2(200, 30)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(label)
	var generator := get_parent().get_node_or_null("WorldGenerator")
	weather.initialize(generator.world_seed if generator != null else 42)
	weather_label = Label.new()
	weather_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	weather_label.position = Vector2(-350, 46)
	weather_label.size = Vector2(326, 30)
	weather_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	weather_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(weather_label)
	var rain := WeatherRain.new()
	rain.name = "WeatherRain"
	rain.clock = self
	add_child(rain)
	apply_time()
	_last_minute = -1
	_notify_minute()
	game_settings.setting_changed.connect(_on_video_setting_changed)

func _on_video_setting_changed(key: StringName, _value: Variant) -> void:
	if key == &"fog_quality": apply_time()

func _process(delta: float) -> void:
	if running: advance(delta)

func advance(real_seconds: float) -> void:
	if not is_finite(real_seconds) or real_seconds < 0.0: return
	var seconds := real_seconds * DAY_SECONDS / (maxf(1.0, day_length_minutes) * 60.0)
	elapsed_seconds += seconds
	if weather_running: weather.advance(seconds)
	apply_time(real_seconds)
	_notify_minute()

func day_number() -> int:
	return floori(elapsed_seconds / DAY_SECONDS) + 1

func hour_of_day() -> float:
	return fposmod(elapsed_seconds, DAY_SECONDS) / 3600.0

func set_time(day: int, hour: float) -> void:
	if day < 1 or not is_finite(hour) or hour < 0.0 or hour >= 24.0: return
	elapsed_seconds = (day - 1) * DAY_SECONDS + hour * 3600.0
	apply_time()
	_notify_minute()

func _notify_minute() -> void:
	var minute := floori(elapsed_seconds / 60.0)
	if minute == _last_minute: return
	_last_minute = minute
	var hour := (minute % 1440) / 60
	if is_instance_valid(label): label.text = "DAY %d   %02d:%02d" % [day_number(), hour, minute % 60]
	minute_changed.emit(day_number(), hour, minute % 60)

func capture() -> Dictionary:
	return {"elapsed_seconds": elapsed_seconds, "day_length_minutes": day_length_minutes}

static func valid_state(data: Variant) -> bool:
	if not data is Dictionary or not data.has_all(["elapsed_seconds", "day_length_minutes"]): return false
	for key in ["elapsed_seconds", "day_length_minutes"]:
		if not (data[key] is float or data[key] is int) or not is_finite(float(data[key])): return false
	return data.elapsed_seconds >= 0.0 and data.elapsed_seconds < DAY_SECONDS * 1000000.0 and data.day_length_minutes >= 1.0 and data.day_length_minutes <= 1440.0

func restore(data: Dictionary) -> bool:
	if not valid_state(data): return false
	elapsed_seconds = float(data.elapsed_seconds)
	day_length_minutes = float(data.day_length_minutes)
	apply_time()
	_notify_minute()
	return true

func sun_direction() -> Vector3:
	# +X sunrise at 06:00, -X sunset at 18:00, peak elevation ~58 degrees.
	var angle := (hour_of_day() - 6.0) / 24.0 * TAU
	return Vector3(cos(angle), sin(angle) * 0.85, sin(angle) * 0.526783).normalized()

func apply_time(real_delta: float = 0.0) -> void:
	if environment == null or not is_instance_valid(sun): return
	var volumetric: bool = game_settings.volumetric_fog_enabled()
	var conditions := effective_visual_weather()
	var clear := conditions.x
	var rain := conditions.y / 2.0
	var mist := conditions.z / 2.0
	var direction := sun_direction()
	var daylight := smoothstep(-0.16, 0.22, direction.y)
	# Only physical lighting/weather depend on the clock. Display adaptation reads
	# the resulting brightness independently, including daytime shadows/interiors.
	var warmth := (1.0 - smoothstep(0.02, 0.42, absf(direction.y))) * daylight
	var horizon := Color("040609").lerp(Color("a4aca9"), daylight).lerp(Color("a08b78"), warmth * 0.55)
	var zenith := Color("010203").lerp(Color("7f9298"), daylight)
	horizon = horizon.lerp(Color("b3c8d4"), clear * daylight * 0.7) * (1.0 - rain * 0.2)
	zenith = zenith.lerp(Color("557f9f"), clear * daylight * 0.8) * (1.0 - rain * 0.3)
	var light_mist := minf(conditions.z / WorldWeather.FOG_LIGHT, 1.0)
	var profile := atmosphere.mist(conditions)
	# Quality controls scattering only; all qualities retain the same haze.
	environment.volumetric_fog_enabled = volumetric and (profile.global_density > 0.0 or profile.local_density > 0.0)
	environment.fog_depth_end = minf(profile.depth_end, _completed_scenery_mist_limit(real_delta))
	environment.fog_depth_begin = minf(profile.depth_begin, environment.fog_depth_end * 0.5)
	environment.fog_depth_curve = profile.depth_curve
	environment.volumetric_fog_length = atmosphere.volume_length(environment.fog_depth_end)
	# Weather haze and sky remain native lighting, independent of gray fill.
	horizon = horizon.lerp(Color("030405").lerp(Color("535c5b"), daylight), mist)
	zenith = zenith.lerp(horizon, mist * 0.7)
	var white_mist := atmosphere.night_mist_color.lerp(atmosphere.day_mist_color, daylight)
	# Lit white haze during the day; no emissive veil over dark nights.
	horizon = horizon.lerp(white_mist, profile.white_strength)
	zenith = zenith.lerp(white_mist, atmosphere.sky_white_blend * profile.white_strength)
	environment.volumetric_fog_albedo = atmosphere.base_volume_albedo.lerp(atmosphere.white_volume_albedo, profile.white_strength)
	environment.volumetric_fog_density = profile.global_density
	var local_density: float = profile.local_density
	for material in fog_materials:
		material.set_shader_parameter("density", local_density)
	if is_instance_valid(weather_label): weather_label.text = weather.description()
	# The fogged sky and fully hidden geometry must share one color, or distant
	# objects reappear as white silhouettes against the darker sky.
	environment.fog_light_color = horizon
	environment.ambient_light_color = Color("7a8da5").lerp(Color("9ba9b0"), daylight)
	environment.ambient_light_energy = lerpf(0.002, 0.24 + clear * 0.07 - rain * 0.04, daylight)
	sun.light_color = Color("e4ad7d").lerp(Color("dedbcc"), smoothstep(0.0, 0.48, direction.y))
	sun.light_energy = 1.05 * smoothstep(0.0, 0.32, direction.y) * (1.0 + clear * 0.25 - rain * 0.90) * (1.0 - mist * 0.85)
	sun.light_volumetric_fog_energy = lerpf(1.0, 0.15, mist)
	# The light emits along -Z; the visible disk sits in the opposite direction.
	sun.global_basis = Basis.looking_at(-direction, Vector3.UP)
	sky_material.set_shader_parameter("horizon_color", horizon)
	sky_material.set_shader_parameter("zenith_color", zenith)
	sky_material.set_shader_parameter("sun_direction", direction)
	sky_material.set_shader_parameter("sun_color", sun.light_color)
	sky_material.set_shader_parameter("cloud_cover", (1.0 - clear) * (0.7 + rain * 0.3))
	sky_material.set_shader_parameter("fog_cover", light_mist)
	sky_material.set_shader_parameter("sun_strength", smoothstep(-0.035, 0.10, direction.y) * (1.0 - rain * 0.95) * (1.0 - mist))

func _completed_scenery_mist_limit(real_delta: float) -> float:
	var generator := get_parent().get_node_or_null("WorldGenerator")
	var camera := get_viewport().get_camera_3d()
	var clearance := INF
	if generator != null and generator.has_method("completed_scenery_clearance") and camera != null and camera.get_world_3d() == get_viewport().world_3d:
		clearance = generator.completed_scenery_clearance(camera.global_position)
	return _stream_visibility.update(clearance, real_delta, atmosphere)

func register_fog(material: ShaderMaterial) -> void:
	fog_materials.append(material)
	var conditions := effective_visual_weather()
	var density: float = atmosphere.mist(conditions).local_density
	material.set_shader_parameter("density", density)

func unregister_fog(material: ShaderMaterial) -> void:
	fog_materials.erase(material)

func effective_visual_weather() -> Vector3:
	return WorldAtmosphereProfile.visual_conditions(weather.sample(), deviation_fog)

func set_deviation_fog(strength: float) -> void:
	if not is_finite(strength): return
	strength = clampf(strength, 0.0, WorldWeather.FOG_MEDIUM)
	if is_equal_approx(deviation_fog, strength): return
	deviation_fog = strength
	apply_time()
