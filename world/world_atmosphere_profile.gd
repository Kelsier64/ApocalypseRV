extends Resource
class_name WorldAtmosphereProfile
## Presentation only: landscape mist, weather haze and streaming safety tuning.
## Natural weather probabilities, clocks and saved RNG belong to WorldWeather.

@export_group("Landscape Mist")
@export_range(0.0, 500.0, 0.5, "suffix:m") var landscape_begin := 24.0
@export_range(0.0, 500.0, 0.5, "suffix:m") var clear_begin := 64.0
@export_range(1.0, 1000.0, 0.5, "suffix:m") var landscape_end := 230.0
@export_range(0.01, 4.0, 0.01) var distance_curve := 1.0
@export_range(0.0, 1.0, 0.01) var white_strength := 1.0
@export var night_mist_color := Color("030405")
@export var day_mist_color := Color("c3cbc8")
@export var overcast_day_color := Color("a4afb0")
@export var clear_day_color := Color("d0cbb8")
@export_range(0.0, 1.0, 0.01) var sky_white_blend := 0.16

@export_group("Daylight")
@export_range(0.0, 4.0, 0.01) var overcast_sun_energy := 0.45
@export_range(0.0, 4.0, 0.01) var clear_sun_energy := 1.3

@export_group("Weather Haze")
@export_range(0.0, 500.0, 0.5, "suffix:m") var weather_begin := 8.0
@export_range(1.0, 1000.0, 0.5, "suffix:m") var light_end := 150.0
@export_range(1.0, 1000.0, 0.5, "suffix:m") var medium_end := 110.0
@export_range(1.0, 1000.0, 0.5, "suffix:m") var heavy_end := 38.0

@export_group("Volumetric Mist")
@export_range(0.0, 1.0, 0.0001) var global_density := 0.0025
@export_range(0.0, 1.0, 0.0001) var rain_density := 0.0005
@export_range(0.0, 1.0, 0.01) var local_density := 0.14
@export var base_volume_albedo := Color(0.28, 0.31, 0.30)
@export var white_volume_albedo := Color("c3cdc8")
@export_range(0.1, 500.0, 0.5, "suffix:m") var volume_max_length := 160.0
@export_range(0.01, 1.0, 0.01) var volume_end_ratio := 0.3

@export_group("Streaming Visibility")
@export_range(0.0, 100.0, 0.5, "suffix:m") var stream_margin := 8.0
@export_range(0.0, 100.0, 0.5, "suffix:m/s") var stream_reveal_speed := 20.0
@export_range(0.0, 100.0, 0.5, "suffix:m") var cull_buffer := 8.0

## Deviation changes presentation without creating natural fog or consuming RNG.
static func visual_conditions(natural: Vector3, deviation: float) -> Vector3:
	var conditions := natural
	conditions.x *= 1.0 - clampf(deviation / WorldWeather.FOG_LIGHT, 0.0, 1.0)
	conditions.z = maxf(conditions.z, deviation)
	return conditions

## Weather can thicken the permanent haze, never extend its visibility horizon.
## This sample is independent of camera, rendering quality and simulation state.
func mist(conditions: Vector3) -> Dictionary:
	var clear := clampf(conditions.x, 0.0, 1.0)
	var fog := clampf(conditions.z, WorldWeather.FOG_NONE, WorldWeather.FOG_HEAVY)
	var light := clampf(fog / WorldWeather.FOG_LIGHT, 0.0, 1.0)
	var medium := clampf((fog - WorldWeather.FOG_LIGHT) / (WorldWeather.FOG_MEDIUM - WorldWeather.FOG_LIGHT), 0.0, 1.0)
	var heavy := clampf((fog - WorldWeather.FOG_MEDIUM) / (WorldWeather.FOG_HEAVY - WorldWeather.FOG_MEDIUM), 0.0, 1.0)
	# Local drifting mist fades before the denser weather haze takes over, so
	# scattering cannot reveal geometry already concealed by distance fog.
	var volume_weight := (1.0 - clear) * (1.0 - light)
	return {
		"depth_begin": lerpf(lerpf(landscape_begin, clear_begin, clear), weather_begin, light),
		"depth_end": minf(landscape_end, lerpf(lerpf(lerpf(landscape_end, light_end, light), medium_end, medium), heavy_end, heavy)),
		"depth_curve": distance_curve,
		"white_strength": white_strength,
		"global_density": (global_density + conditions.y * rain_density) * volume_weight,
		"local_density": local_density * volume_weight,
	}

## All weather keeps an opaque terminal horizon, but its daylight color and
## foreground illumination still identify clear skies, cloud cover and fog.
func day_color(conditions: Vector3) -> Color:
	var clear := clampf(conditions.x, 0.0, 1.0)
	var light := clampf(conditions.z / WorldWeather.FOG_LIGHT, 0.0, 1.0)
	return overcast_day_color.lerp(clear_day_color, clear).lerp(day_mist_color, light)

## Volume depth is view-axis based; keep its integration inside radial haze,
## including wide-angle screen corners and a temporarily shortened horizon.
func volume_length(depth_end: float) -> float:
	return maxf(0.1, minf(volume_max_length, depth_end * volume_end_ratio))
