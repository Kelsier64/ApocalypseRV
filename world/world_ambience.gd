class_name WorldAmbience
extends Node
## The outdoor ambience beds: day or night underneath, then forest, highway and
## fog on top, crossfaded by the clock, the weather and where the listener
## stands. Night is nearly silent so monster cues stand out. The beds play on
## the Outdoors bus, which Sfx muffles in the RV cabin and under a roof; inside a
## POI they stop and the interior's room tone plays instead.

const BEDS := {
	&"day": preload("res://assets/audio/ambience/day.ogg"),
	&"night": preload("res://assets/audio/ambience/night.ogg"),
	&"forest": preload("res://assets/audio/ambience/forest.ogg"),
	&"highway": preload("res://assets/audio/ambience/highway.ogg"),
	&"fog": preload("res://assets/audio/ambience/fog.ogg"),
}
## Level of each bed at full weight against its loop, in dB.
const BED_DB := {&"day": -6.0, &"night": -12.0, &"forest": -6.0, &"highway": -8.0, &"fog": -8.0}
const ROOM_TONE_DB := -8.0
## Seconds a bed takes to fade fully in or out as time, weather or place change,
## and the quicker fade when the player enters or leaves an interior.
const FADE_SECONDS := 3.0
const ROOM_FADE_SECONDS := 1.0
## Seconds between samples of the listener's place and overhead cover.
const SAMPLE_SECONDS := 0.5
## Forest and highway level at night against daytime.
const NIGHT_PLACE := 0.5
## Share of the day and night beds that full fog and heavy rain take away.
const FOG_DUCK := 0.5
const RAIN_DUCK := 0.6
## Share of the highway bed a full forest takes away.
const FOREST_OVER_ROAD := 0.5
## Mean tree chance around the listener at or below which there is no forest,
## and from which it is full forest, sampled at the listener and four points
## FOREST_RADIUS away. Open ground is near 0.1; the densest tenth of the land
## is above 0.35.
const FOREST_SPARSE := 0.1
const FOREST_FULL := 0.35
const FOREST_RADIUS := 20.0
## Metres past the carriageway edge over which the highway bed fades out.
const ROAD_FADE := 45.0
## Outdoor shelter while something solid is overhead within ROOF_PROBE metres.
const ROOF_SHELTER := 0.7
const ROOF_PROBE := 30.0

var clock: WorldClock
## Playground overrides for the place weights, 0 to 1; negative reads the terrain.
var forest_override := -1.0
var road_override := -1.0
## Place weights at the last sample, and each bed's target and current weight.
var forest := 0.0
var road := 0.0
var targets: Dictionary[StringName, float] = {}
var levels: Dictionary[StringName, float] = {}
var room_level := 0.0
var _players: Dictionary[StringName, AudioStreamPlayer] = {}
var _room: AudioStreamPlayer
## Only picks loop start points; never touches gameplay or generation randomness.
var _rng := RandomNumberGenerator.new()
var _until_sample := 0.0


func _ready() -> void:
	_rng.randomize()
	for bed: StringName in BEDS:
		var voice := AudioStreamPlayer.new()
		voice.name = String(bed).capitalize()
		voice.stream = BEDS[bed]
		voice.bus = &"Outdoors"
		voice.volume_db = -80.0
		add_child(voice)
		voice.play(_rng.randf() * voice.stream.get_length())
		_players[bed] = voice
		levels[bed] = 0.0
		targets[bed] = 0.0
	_room = AudioStreamPlayer.new()
	_room.name = "RoomTone"
	_room.bus = &"Ambience"
	_room.volume_db = -80.0
	add_child(_room)


func _exit_tree() -> void:
	for voice in _players.values(): voice.stop()
	_room.stop()
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null: sfx.outdoor_shelter = 0.0


## Weight of each bed, 0 to 1: daylight 0 to 1, mist the weather fog level,
## rain 0 to 1, forest and road how much of each surrounds the listener.
static func mix(daylight: float, mist: float, rain: float, forest_weight: float, road_weight: float) -> Dictionary[StringName, float]:
	var fog := clampf(mist / WorldWeather.FOG_MEDIUM, 0.0, 1.0)
	var open := 1.0 - FOG_DUCK * fog
	var calm := 1.0 - RAIN_DUCK * clampf(rain, 0.0, 1.0)
	var place := lerpf(NIGHT_PLACE, 1.0, daylight) * open
	return {
		&"day": daylight * open * calm,
		&"night": (1.0 - daylight) * open * calm,
		&"forest": forest_weight * place,
		&"highway": road_weight * (1.0 - FOREST_OVER_ROAD * forest_weight) * place,
		&"fog": fog,
	}


func _process(delta: float) -> void:
	if not is_instance_valid(clock): return
	var sfx := get_node("/root/Sfx")
	var outdoors: bool = sfx.listening_outdoors()
	_until_sample -= delta
	if outdoors and _until_sample <= 0.0:
		_until_sample = SAMPLE_SECONDS
		_sample_place(sfx)
	var weather := clock.effective_visual_weather()
	targets = mix(clock.daylight(), weather.z, weather.y / 2.0, forest, road)
	var step := delta / (FADE_SECONDS if outdoors else ROOM_FADE_SECONDS)
	for bed: StringName in _players:
		levels[bed] = move_toward(levels[bed], targets[bed] if outdoors else 0.0, step)
		_players[bed].volume_db = linear_to_db(maxf(levels[bed], 0.0001)) + BED_DB[bed]
	_update_room(null if outdoors else sfx.room_tone(), delta / ROOM_FADE_SECONDS)


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
