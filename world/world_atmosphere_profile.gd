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
@export var night_mist_color := Color.BLACK
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
## Ground mist rides the wind: it drifts downwind at a floor speed plus a share
## of the local wind speed, and wind between the tear speeds thins it to wisps.
## Only the local FogVolumes move; the distance haze gameplay reads never does.
@export_range(0.0, 2.0, 0.01, "suffix:m/s") var mist_drift_floor := 0.3
@export_range(0.0, 0.5, 0.01) var mist_drift_share := 0.1
@export_range(0.0, 40.0, 0.5, "suffix:m/s") var mist_tear_start := 4.0
@export_range(0.0, 40.0, 0.5, "suffix:m/s") var mist_tear_full := 15.0
@export_range(0.0, 1.0, 0.01) var mist_tear := 0.85

@export_group("Dust")
## Haze at full dust (a gale over bare, dry ground): a faint brown backdrop.
## The sheets block the view up close; the haze only shortens the horizon and
## keeps the weather's own curve. Dust only pulls the haze in.
## Depth fog has no shelter, so the haze begins past the RV cabin's length.
@export_range(0.0, 500.0, 0.5, "suffix:m") var dust_begin := 10.0
## Apparitions cap their spawn distance at the haze end; keep it above
## WhiteApparition.SPAWN_MIN.
@export_range(1.0, 1000.0, 0.5, "suffix:m") var dust_end := 120.0
## Below 1, light dust already shortens the view noticeably.
@export_range(0.05, 4.0, 0.01) var dust_curve := 0.6
## At the peak of a storm surge (WorldWind.surge) the dust haze end comes this
## share closer; keep dust_end * (1 - this) above WhiteApparition.SPAWN_MIN.
@export_range(0.0, 0.9, 0.01) var dust_surge_reach := 0.35
## Dust colour where no landform is known (flat playgrounds, tests); on terrain
## the colour comes from TerrainLandforms.DUST_COLORS.
@export var dust_day_color := Color("a28b6b")
## Just enough scattering for headlight and lamp beams; the depth haze does the rest.
@export_range(0.0, 1.0, 0.0001) var dust_volume_density := 0.008
@export_range(0.0, 1.0, 0.01) var dust_sun_dimming := 0.35
## Scales the opacity of the rolling dust clouds.
@export_range(0.0, 8.0, 0.05) var dust_cloud_opacity := 2.0
## Clouds fade out closer than this to the camera, so none sits on the lens.
@export_range(0.0, 20.0, 0.1, "suffix:m") var dust_cloud_near := 2.0
## Dense sheets streaming past close up in strong dust.
@export_range(0.0, 8.0, 0.05) var dust_sheet_opacity := 1.0
@export_range(0.0, 20.0, 0.1, "suffix:m") var dust_sheet_near := 0.8
## 0 to 1: how far the sheets thin between passing walls of thick dust.
@export_range(0.0, 1.0, 0.01) var dust_sheet_clump := 0.7
## Extra sheet opacity at the peak of a strong gust; the gaps between sheets
## close too, so a wall of dust sweeps over and then opens again.
@export_range(0.0, 4.0, 0.05) var dust_gust_wall := 1.2
## Sunlight the sheets and clouds scatter: brighter and warmer in sun, dull
## under cloud, none at night.
@export_range(0.0, 2.0, 0.01) var dust_sun_glow := 0.3
## Volumetric billows (Forward+ with volumetric fog): peak extinction per
## metre, the share of the air they fill, their size and height falloff.
## The cabin's CabinAir volumes cancel up to 1.0 in total.
@export_range(0.0, 0.9, 0.01) var dust_billow_density := 0.35
@export_range(0.0, 1.0, 0.01) var dust_billow_coverage := 0.45
@export_range(2.0, 80.0, 0.5, "suffix:m") var dust_billow_scale := 18.0
@export_range(0.2, 20.0, 0.1, "suffix:m") var dust_billow_height := 3.0
## At full dust the volumetric range reaches this share of the haze end, so
## billows show from farther out than the default scattering range.
@export_range(0.01, 1.0, 0.01) var dust_volume_end_ratio := 0.45

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
## Dust (0 to 1, from WorldWind at the camera) works the same way: the nearer
## of the fog and dust ends wins, and `dust_mix` is dust's share of the color.
## A storm surge (0 to 1) pulls the dust end in further; without dust it does nothing.
## This sample is independent of camera, rendering quality and simulation state.
func mist(conditions: Vector3, dust := 0.0, surge := 0.0) -> Dictionary:
	var clear := clampf(conditions.x, 0.0, 1.0)
	var fog := clampf(conditions.z, WorldWeather.FOG_NONE, WorldWeather.FOG_HEAVY)
	var light := clampf(fog / WorldWeather.FOG_LIGHT, 0.0, 1.0)
	var medium := clampf((fog - WorldWeather.FOG_LIGHT) / (WorldWeather.FOG_MEDIUM - WorldWeather.FOG_LIGHT), 0.0, 1.0)
	var heavy := clampf((fog - WorldWeather.FOG_MEDIUM) / (WorldWeather.FOG_HEAVY - WorldWeather.FOG_MEDIUM), 0.0, 1.0)
	# Local drifting mist fades before the denser weather haze takes over, so
	# scattering cannot reveal geometry already concealed by distance fog.
	var volume_weight := (1.0 - clear) * (1.0 - light)
	var dust_level := clampf(dust, 0.0, 1.0)
	var dust_pull := pow(dust_level, dust_curve)
	var weather_begin_at := lerpf(lerpf(landscape_begin, clear_begin, clear), weather_begin, light)
	var weather_end_at := minf(landscape_end, lerpf(lerpf(lerpf(landscape_end, light_end, light), medium_end, medium), heavy_end, heavy))
	var fog_share := fog / WorldWeather.FOG_HEAVY
	return {
		"depth_begin": minf(weather_begin_at, lerpf(weather_begin_at, dust_begin, dust_pull)),
		"depth_end": minf(weather_end_at, lerpf(landscape_end, dust_end * (1.0 - dust_surge_reach * clampf(surge, 0.0, 1.0)), dust_pull)),
		"depth_curve": distance_curve,
		"white_strength": white_strength,
		# Dust scattering lets headlights and lamps draw beams in a dust storm.
		"global_density": (global_density + conditions.y * rain_density) * volume_weight + dust_volume_density * dust_level,
		"local_density": local_density * volume_weight,
		"dust_mix": 0.0 if dust_level <= 0.0 else dust_level * dust_level / (dust_level + fog_share),
	}

## All weather keeps an opaque terminal horizon, but its daylight color and
## foreground illumination still identify clear skies, cloud cover and fog.
func day_color(conditions: Vector3) -> Color:
	var clear := clampf(conditions.x, 0.0, 1.0)
	var light := clampf(conditions.z / WorldWeather.FOG_LIGHT, 0.0, 1.0)
	return overcast_day_color.lerp(clear_day_color, clear).lerp(day_mist_color, light)

## Volume depth is view-axis based; keep its integration inside radial haze,
## including wide-angle screen corners and a temporarily shortened horizon.
## Dust lengthens it toward dust_volume_end_ratio; it stays inside the haze end.
## Downwind speed of the ground mist in m/s for a local wind speed.
func mist_drift_speed(wind_speed: float) -> float:
	return mist_drift_floor + mist_drift_share * maxf(wind_speed, 0.0)

## How torn the ground mist is, 0 (still air) to 1, for a local wind speed.
func mist_torn(wind_speed: float) -> float:
	return smoothstep(mist_tear_start, maxf(mist_tear_full, mist_tear_start + 0.01), wind_speed)

func volume_length(depth_end: float, dust := 0.0) -> float:
	var ratio := lerpf(volume_end_ratio, maxf(volume_end_ratio, dust_volume_end_ratio), clampf(dust, 0.0, 1.0))
	return maxf(0.1, minf(volume_max_length, depth_end * ratio))
