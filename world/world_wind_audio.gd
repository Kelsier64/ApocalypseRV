class_name WorldWindAudio
extends Node
## The weather wind as heard outdoors. Calm is silent. A breeze, a strong-wind
## and a gale bed, low and dark on purpose, crossfade by WorldWind.strength()
## and swell with the same gusts the dust and rain follow; ground the trees
## shelter hears less of them. Among trees a strong wind adds treetop rushes
## that rise and fall at random bearings above the listener. All of it plays on
## the Outdoors bus, so the RV cabin and a roof muffle it and a revving engine
## masks it, and it fades out inside a POI. The wind in turn masks other outside
## sound through Sfx.wind_masking, like a revving engine does.

## Breeze, strong wind and gale: stereo loops matched in loudness.
const BEDS: Array[AudioStream] = [
	preload("res://assets/audio/weather/wind_breeze.ogg"),
	preload("res://assets/audio/weather/wind_strong.ogg"),
	preload("res://assets/audio/weather/wind_gale.ogg"),
]
## Level of each bed at its own tier and the top of a gust.
const BED_DB := [-22.0, -17.0, -13.0]
## A lull between gusts is this much quieter than a gust's peak, and plays at
## the first pitch against the second at the peak.
const GUST_RANGE_DB := 8.0
const GUST_PITCH := Vector2(0.94, 1.05)
## Ground fully sheltered by trees (WorldWind.TREE_SHELTER) hears the bed this much quieter.
const SHELTER_DB := -8.0
## Seconds the bed takes to fade out on entering a POI and back in on leaving.
const FADE_SECONDS := 1.0
const TREE_RUSH: SoundEvent = preload("res://assets/audio/events/weather/tree_rush.tres")
## Treetop rushes start at this wind strength and are most frequent at a gale,
## RUSH_RATE per second in full forest at the top of a gust.
const RUSH_START := 1.5
const RUSH_RATE := 0.45
## Distance of a rush from the listener and its height above, in metres.
const RUSH_DISTANCE := Vector2(10.0, 30.0)
const RUSH_HEIGHT := Vector2(6.0, 14.0)
## A rush in a strong wind is this much quieter than in a gale.
const RUSH_STRONG_DB := -6.0
## Mean local wind speed in m/s at which the wind starts to mask other outside
## sound, and at which it masks it fully (Sfx.ENGINE_MASK_DB).
const MASK_SPEED := Vector2(8.0, 20.0)

var clock: WorldClock
## Where the forest weight comes from; WorldClock sets it.
var ambience: WorldAmbience
## Playground override for the share of open-ground wind reaching the listener,
## 0 to 1; negative reads the clock's sample at the camera.
var exposure_override := -1.0
## Playground override for the three beds; empty uses BEDS.
var bed_override: Array[AudioStream] = []
## Linear level of each bed at the last update, and how many rushes played.
var bed_levels := PackedFloat32Array([0.0, 0.0, 0.0])
var rushes := 0
var presence := 1.0
var _beds: Array[AudioStreamPlayer] = []
## Only picks rush bearings, timing and loop starts; never touches gameplay randomness.
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	for index in range(BEDS.size()):
		var bed := AudioStreamPlayer.new()
		bed.name = "WindBed%d" % index
		bed.bus = &"Outdoors"
		bed.stream = BEDS[index]
		add_child(bed)
		_beds.append(bed)


func _exit_tree() -> void:
	for bed in _beds: bed.stop()
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null: sfx.wind_masking = 0.0


## Linear level of the breeze, strong and gale beds for a strength of 0 (calm)
## to 3 (gale). Calm is silent; neighbouring tiers crossfade at equal power.
static func tier_levels(strength: float) -> PackedFloat32Array:
	var levels := PackedFloat32Array([0.0, 0.0, 0.0])
	var value := clampf(strength, 0.0, 3.0)
	if value <= 1.0:
		levels[0] = smoothstep(0.0, 1.0, value)
		return levels
	var low := mini(floori(value - 1.0), 1)
	var blend := (value - 1.0 - low) * PI * 0.5
	levels[low] = cos(blend)
	levels[low + 1] = sin(blend)
	return levels


## How often treetop rushes start, per second.
static func rush_rate(strength: float, forest: float, gust: float) -> float:
	return RUSH_RATE * clampf(forest, 0.0, 1.0) * smoothstep(RUSH_START, 3.0, strength) * lerpf(0.3, 1.0, clampf(gust, 0.0, 1.0))


## Masking of other outside sound for a mean local wind speed in m/s, 0 to 1.
static func masking_for(local_mean_speed: float) -> float:
	return smoothstep(MASK_SPEED.x, MASK_SPEED.y, local_mean_speed)


func _process(delta: float) -> void:
	if not is_instance_valid(clock): return
	var sfx := get_node("/root/Sfx")
	var outdoors: bool = sfx.listening_outdoors()
	presence = move_toward(presence, 1.0 if outdoors else 0.0, delta / FADE_SECONDS)
	var wind := clock.wind
	var seconds := clock.elapsed_seconds
	var strength := wind.strength()
	var gust := wind.gust(seconds)
	var exposure := _exposure(seconds)
	sfx.wind_masking = masking_for(wind.mean_speed() * exposure) if outdoors else 0.0
	_update_beds(strength, gust, exposure)
	var forest := ambience.forest if is_instance_valid(ambience) else 0.0
	if outdoors and _rng.randf() < rush_rate(strength, forest, gust) * delta:
		play_rush(strength)


## Plays one treetop rush now somewhere above the listener.
func play_rush(strength: float) -> bool:
	var sfx := get_node("/root/Sfx")
	var camera: Camera3D = sfx.listener_camera()
	if camera == null: return false
	var bearing := _rng.randf() * TAU
	var at := camera.global_position + Vector3(cos(bearing), 0.0, sin(bearing)) * _rng.randf_range(RUSH_DISTANCE.x, RUSH_DISTANCE.y) \
		+ Vector3.UP * _rng.randf_range(RUSH_HEIGHT.x, RUSH_HEIGHT.y)
	var gain := RUSH_STRONG_DB * (1.0 - smoothstep(float(WorldWind.STRONG), float(WorldWind.GALE), strength))
	if not sfx.play_at(TREE_RUSH, at, gain): return false
	rushes += 1
	return true


## Share of the open-ground wind at the camera, from the clock's sample there.
func _exposure(seconds: float) -> float:
	if exposure_override >= 0.0: return clampf(exposure_override, 0.0, 1.0)
	var open := clock.wind.speed(seconds)
	return clampf(clock.wind_velocity.length() / open, 0.0, 1.0) if open > 0.001 else 1.0


func _update_beds(strength: float, gust: float, exposure: float) -> void:
	var tiers := tier_levels(strength)
	var swell := GUST_RANGE_DB * (gust - 1.0) + SHELTER_DB * (1.0 - exposure) / WorldWind.TREE_SHELTER
	var pitch := lerpf(GUST_PITCH.x, GUST_PITCH.y, gust)
	for index in range(_beds.size()):
		var bed := _beds[index]
		var stream: AudioStream = bed_override[index] if bed_override.size() == _beds.size() else BEDS[index]
		if bed.stream != stream:
			bed.stop()
			bed.stream = stream
		bed_levels[index] = tiers[index] * presence
		if bed_levels[index] < SoundLoop.SILENT_LEVEL:
			if bed.playing: bed.stop()
			continue
		bed.volume_db = BED_DB[index] + swell + linear_to_db(bed_levels[index])
		bed.pitch_scale = pitch
		if not bed.playing: bed.play(_rng.randf() * stream.get_length())
