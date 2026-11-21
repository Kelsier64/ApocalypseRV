class_name WorldAmbience
extends Node
## Ambience that leaves the world mostly silent. Outdoors there is no bed: every
## INTERVAL seconds one distant, positioned sound plays somewhere around the
## listener, picked by time of day and place: a crow by day, a creaking trunk or
## a snapping branch among trees, creaking metal by the road, a cricket at night.
## Fog and rain make them rarer, and fog also puts them farther away and quieter.
## They play on the Outdoors bus, which Sfx muffles in the RV cabin and under a
## roof and masks under a revving engine. Inside a POI a very faint low hum loops
## and now and then a drip or a metal creak sounds in the room.

const OUTDOOR := {
	&"crow": preload("res://assets/audio/events/ambience/crow.tres"),
	&"tree_creak": preload("res://assets/audio/events/ambience/tree_creak.tres"),
	&"branch_snap": preload("res://assets/audio/events/ambience/branch_snap.tres"),
	&"metal_creak": preload("res://assets/audio/events/ambience/metal_creak.tres"),
	&"cricket": preload("res://assets/audio/events/ambience/cricket.tres"),
}
const INDOOR := {
	&"drip": preload("res://assets/audio/events/ambience/drip.tres"),
	&"room_creak": preload("res://assets/audio/events/ambience/room_creak.tres"),
}
## Seconds between ambience sounds, drawn evenly from this range.
const INTERVAL := Vector2(30.0, 90.0)
## How much full fog and heavy rain each stretch the wait, as extra multiples.
const FOG_SPARSER := 1.0
const RAIN_SPARSER := 1.0
## Distance of an outdoor sound and its height above the listener, in metres.
const OUTDOOR_DISTANCE := Vector2(25.0, 60.0)
const OUTDOOR_HEIGHT := Vector2(0.0, 6.0)
## Full fog puts outdoor sounds this much farther away and this much quieter.
const FOG_DISTANCE := 0.5
const FOG_GAIN_DB := -6.0
## Distance of an interior sound from the listener, in metres.
const INDOOR_DISTANCE := Vector2(3.0, 10.0)
## Level of the interior hum against its loop, and how fast it fades on entry.
const ROOM_TONE_DB := -20.0
const ROOM_FADE_SECONDS := 1.0
## Seconds between samples of the listener's place and overhead cover.
const SAMPLE_SECONDS := 0.5
## Mean tree chance around the listener at or below which there is no forest,
## and from which it is full forest, sampled at the listener and four points
## FOREST_RADIUS away. Open ground is near 0.1; the densest tenth of the land
## is above 0.35.
const FOREST_SPARSE := 0.1
const FOREST_FULL := 0.35
const FOREST_RADIUS := 20.0
## Metres past the carriageway edge over which the road counts less and less.
const ROAD_FADE := 45.0
## Outdoor shelter while something solid is overhead within ROOF_PROBE metres.
const ROOF_SHELTER := 0.7
const ROOF_PROBE := 30.0

var clock: WorldClock
## Playground overrides for the place weights, 0 to 1; negative reads the terrain.
var forest_override := -1.0
var road_override := -1.0
## Place weights at the last sample.
var forest := 0.0
var road := 0.0
## The last sound played and how far from the listener, and the wait to the next.
var last_sound: StringName = &""
var last_distance := 0.0
var until_next := 0.0
var room_level := 0.0
var _room: AudioStreamPlayer
## Only picks sounds, places and waits; never touches gameplay or generation randomness.
var _rng := RandomNumberGenerator.new()
var _until_sample := 0.0


func _ready() -> void:
	_rng.randomize()
	until_next = _rng.randf_range(INTERVAL.x, INTERVAL.y)
	_room = AudioStreamPlayer.new()
	_room.name = "RoomTone"
	_room.bus = &"Ambience"
	_room.volume_db = -80.0
	add_child(_room)


func _exit_tree() -> void:
	_room.stop()
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null: sfx.outdoor_shelter = 0.0


## How likely each outdoor sound is, from daylight 0 to 1 and how much forest
## and road surround the listener, 0 to 1.
static func weights(daylight: float, forest_weight: float, road_weight: float) -> Dictionary[StringName, float]:
	var open := 1.0 - 0.5 * forest_weight
	return {
		&"crow": daylight * open,
		&"tree_creak": forest_weight,
		&"branch_snap": forest_weight * 0.5,
		&"metal_creak": road_weight * 0.8,
		&"cricket": (1.0 - daylight) * open,
	}


## Seconds to wait before the next sound: mist is the weather fog level, rain 0 to 1.
func next_wait(mist: float, rain: float) -> float:
	var sparser := 1.0 + FOG_SPARSER * _fog(mist) + RAIN_SPARSER * clampf(rain, 0.0, 1.0)
	return _rng.randf_range(INTERVAL.x, INTERVAL.y) * sparser


func _process(delta: float) -> void:
	if not is_instance_valid(clock): return
	var sfx := get_node("/root/Sfx")
	var outdoors: bool = sfx.listening_outdoors()
	_until_sample -= delta
	if outdoors and _until_sample <= 0.0:
		_until_sample = SAMPLE_SECONDS
		_sample_place(sfx)
	_update_room(null if outdoors else sfx.room_tone(), delta / ROOM_FADE_SECONDS)
	until_next -= delta
	if until_next <= 0.0:
		play_next()
		var weather := clock.effective_visual_weather()
		until_next = next_wait(weather.z, weather.y / 2.0) if outdoors else _rng.randf_range(INTERVAL.x, INTERVAL.y)


## Plays one ambience sound now, outdoors or in the interior being listened to.
func play_next() -> bool:
	var sfx := get_node("/root/Sfx")
	var camera: Camera3D = sfx.listener_camera()
	if camera == null: return false
	var bearing := _rng.randf() * TAU
	var flat := Vector3(cos(bearing), 0.0, sin(bearing))
	var at: Vector3
	var gain := 0.0
	var event: SoundEvent
	if sfx.listening_outdoors():
		last_sound = _pick(weights(clock.daylight(), forest, road))
		if last_sound.is_empty(): return false
		var fog := _fog(clock.effective_visual_weather().z)
		last_distance = _rng.randf_range(OUTDOOR_DISTANCE.x, OUTDOOR_DISTANCE.y) * (1.0 + FOG_DISTANCE * fog)
		at = camera.global_position + flat * last_distance + Vector3.UP * _rng.randf_range(OUTDOOR_HEIGHT.x, OUTDOOR_HEIGHT.y)
		gain = FOG_GAIN_DB * fog
		event = OUTDOOR[last_sound]
	else:
		last_sound = INDOOR.keys()[_rng.randi_range(0, INDOOR.size() - 1)]
		last_distance = _rng.randf_range(INDOOR_DISTANCE.x, INDOOR_DISTANCE.y)
		at = camera.global_position + flat * last_distance + Vector3.UP * _rng.randf_range(-1.0, 1.0)
		event = INDOOR[last_sound]
	return sfx.play_at(event, at, gain)


func _pick(chances: Dictionary[StringName, float]) -> StringName:
	var total := 0.0
	for chance in chances.values(): total += chance
	if total <= 0.0: return &""
	var roll := _rng.randf() * total
	for sound in chances:
		roll -= chances[sound]
		if roll <= 0.0: return sound
	return chances.keys().back()


static func _fog(mist: float) -> float:
	return clampf(mist / WorldWeather.FOG_MEDIUM, 0.0, 1.0)


## Fades the current room tone out before a different one, or none, takes over.
func _update_room(tone: AudioStream, step: float) -> void:
	if _room.stream != tone:
		room_level = move_toward(room_level, 0.0, step)
		if room_level <= 0.0:
			_room.stream = tone
			if tone == null: _room.stop()
			else: _room.play(_rng.randf() * tone.get_length())
	else:
		room_level = move_toward(room_level, 1.0 if tone != null else 0.0, step)
	_room.volume_db = linear_to_db(maxf(room_level, 0.0001)) + ROOM_TONE_DB


func _sample_place(sfx: Node) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null: return
	var at := camera.global_position
	var field := _field()
	forest = forest_override if forest_override >= 0.0 else _forest_at(field, at)
	road = road_override if road_override >= 0.0 else _road_at(field, at)
	var query := PhysicsRayQueryParameters3D.create(at, at + Vector3.UP * ROOF_PROBE, 1)
	sfx.outdoor_shelter = ROOF_SHELTER if not camera.get_world_3d().direct_space_state.intersect_ray(query).is_empty() else 0.0


func _field() -> WorldField:
	var world := clock.get_parent()
	var generator := world.get_node_or_null("WorldGenerator") if world != null else null
	return generator.get(&"field") if generator != null else null


static func _forest_at(field: WorldField, at: Vector3) -> float:
	if field == null: return 0.0
	var chance := 0.0
	for offset in [Vector2.ZERO, Vector2(FOREST_RADIUS, 0), Vector2(-FOREST_RADIUS, 0), Vector2(0, FOREST_RADIUS), Vector2(0, -FOREST_RADIUS)]:
		chance += field.landforms.flora_weights(at.x + offset.x, at.z + offset.y).x
	return smoothstep(FOREST_SPARSE, FOREST_FULL, chance / 5.0 * field.profile.decoration_density)


static func _road_at(field: WorldField, at: Vector3) -> float:
	if field == null: return 0.0
	var query := field.road_query(at.x, at.z)
	var edge := float(query.width) * 0.5
	return 1.0 - smoothstep(edge, edge + ROAD_FADE, float(query.distance))
