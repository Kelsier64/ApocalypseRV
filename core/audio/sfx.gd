extends Node
## The pool lives under the listening viewport, including POIs with their own World3D.
## Cabin and Exterior are muffled from the other side of the RV shell: a listener
## inside the cabin hears Exterior through the shell, one outside hears Cabin.
## The engine bus is outside the shell too, and a revving engine masks the rest
## of Exterior; the Slender Speaker keeps most of its level so it stays locatable.
## The outdoor ambience bus is muffled like Exterior, and also under a roof.

const MAX_VOICES := 12
const OPEN_CUTOFF_HZ := 20500.0
const CLOSED_CUTOFF_HZ := 1500.0
const CLOSED_GAIN_DB := -8.0
const TRANSITION_SECONDS := 0.3
## Exterior level at full engine masking, and the share of it the loudspeaker takes.
const ENGINE_MASK_DB := -6.0
const LOUDSPEAKER_MASK_SHARE := 1.0 / 3.0
## Outdoor echo tails play on their own voices, so they never take the pool.
const MAX_ECHOES := 4
## Echo level gained against the direct sound at the event's max distance.
const ECHO_DISTANCE_GAIN_DB := 9.0

var _rng := RandomNumberGenerator.new()
var _listener: Viewport
var _pool: Node3D
var _voices: Array[AudioStreamPlayer3D] = []
var _echoes: Array[AudioStreamPlayer3D] = []
var _sources: Dictionary[AudioStreamPlayer3D, Node3D] = {}
var _offsets: Dictionary[AudioStreamPlayer3D, Vector3] = {}
## Priority and start time of what each voice plays, for taking over voices.
var _priorities: Dictionary[AudioStreamPlayer3D, int] = {}
var _started: Dictionary[AudioStreamPlayer3D, int] = {}
## Current muffle per bus name, 0 open to 1 sealed shell.
var _cover: Dictionary[StringName, float] = {&"Exterior": 0.0, &"Cabin": 0.0, &"Engine": 0.0, &"Outdoors": 0.0}
## How sheltered the outdoor ambience sounds from overhead cover such as a roof,
## 0 to 1; WorldAmbience sets it, the RV shell adds to it here.
var outdoor_shelter := 0.0
## The looping room sound of the interior being listened to; null outdoors.
var _room_tone: AudioStream
## Current engine masking, 0 to 1.
var _mask := 0.0
## Room reverb inserted on Effects while the listener is inside a POI interior.
var _room: AudioEffectReverb
## Engine time in msec each event with a cooldown last played, by instance id
## so the autoload holds no references to the events themselves.
var _last_played: Dictionary[int, int] = {}


func _ready() -> void:
	set_listener_viewport(get_tree().root)


## room is the interior's reverb preset and tone its room sound; null outdoors.
func set_listener_viewport(viewport: Viewport, room: AudioEffectReverb = null, tone: AudioStream = null) -> void:
	_set_room(room)
	_room_tone = tone
	if _listener == viewport: return
	if is_instance_valid(_listener):
		_listener.audio_listener_enable_3d = false
	if is_instance_valid(_pool):
		for voice in _voices + _echoes: voice.stop()
		# Rename it now, so a pool created this frame keeps the name.
		_pool.name = "RetiredOneShots"
		_pool.queue_free()
	_pool = null
	_voices.clear()
	_echoes.clear()
	_sources.clear()
	_offsets.clear()
	_priorities.clear()
	_started.clear()
	_listener = viewport
	_listener.audio_listener_enable_3d = true
	_mask = 0.0
	for bus_name in _cover: _set_cover(bus_name, 0.0)
	_set_mask(0.0)


## gain_db scales this one playback, for example by impact strength.
func play(event: SoundEvent, source: Node3D, local_position := Vector3.ZERO, gain_db := 0.0) -> bool:
	if event.samples.is_empty() or not is_instance_valid(_listener) or not source.is_inside_tree():
		return false
	if source.get_world_3d() != _listener.find_world_3d(): return false
	var now := Time.get_ticks_msec()
	if event.cooldown_seconds > 0.0:
		if now - _last_played.get(event.get_instance_id(), -1000000) < event.cooldown_seconds * 1000.0: return false
		_last_played[event.get_instance_id()] = now
	var voice := _available_voice(event.priority)
	if voice == null: return false
	var at := source.to_global(local_position)
	voice.stream = event.samples[_rng.randi_range(0, event.samples.size() - 1)]
	voice.bus = bus_at(at, source.get_world_3d()) if event.occlusion_by_position else event.bus
	voice.volume_db = event.volume_db + gain_db
	voice.pitch_scale = 1.0 + _rng.randf_range(-event.pitch_variation, event.pitch_variation)
	event.attenuation.apply(voice)
	voice.global_position = at
	_sources[voice] = source
	_offsets[voice] = local_position
	_priorities[voice] = event.priority
	_started[voice] = now
	voice.play()
	if event.outdoor_echo_db > -80.0 and voice.bus == &"Exterior" and _listener == get_tree().root:
		_play_echo(voice, event)
	return true


## A wet copy on OutdoorEcho, wetter the farther the listener stands.
func _play_echo(direct: AudioStreamPlayer3D, event: SoundEvent) -> void:
	var echo: AudioStreamPlayer3D = null
	for candidate in _echoes:
		if not candidate.playing:
			echo = candidate
			break
	if echo == null and _echoes.size() < MAX_ECHOES:
		echo = AudioStreamPlayer3D.new()
		echo.bus = &"OutdoorEcho"
		_ensure_pool().add_child(echo)
		_echoes.append(echo)
	if echo == null:
		echo = _echoes[0]
		for candidate in _echoes:
			if candidate.get_playback_position() > echo.get_playback_position(): echo = candidate
	var camera := _listener.get_camera_3d()
	var distance := camera.global_position.distance_to(direct.global_position) if camera != null else 0.0
	var far := smoothstep(0.0, event.attenuation.max_distance, distance)
	echo.stream = direct.stream
	echo.pitch_scale = direct.pitch_scale
	echo.volume_db = direct.volume_db + event.outdoor_echo_db + ECHO_DISTANCE_GAIN_DB * far
	event.attenuation.apply(echo)
	echo.global_position = direct.global_position
	echo.play()


## True while the root world is heard, false while the player listens inside a POI.
func listening_outdoors() -> bool:
	return not is_instance_valid(_listener) or _listener == get_tree().root


func room_tone() -> AudioStream:
	return _room_tone


## Current muffle of a bus Sfx manages, 0 open to 1 sealed.
func cover(bus_name: StringName) -> float:
	return _cover.get(bus_name, 0.0)


## Stops every one-shot still following source, such as an interrupted reload.
func stop_from(source: Node3D) -> void:
	for voice in _sources.keys():
		if _sources[voice] == source: voice.stop()


## Cabin for a point inside any RV cabin of that world, otherwise Exterior.
func bus_at(world_position: Vector3, world: World3D) -> StringName:
	for audio in _vehicle_audio(world):
		if audio.contains_cabin_point(world_position): return &"Cabin"
	return &"Exterior"


func _vehicle_audio(world: World3D) -> Array[Node]:
	var found: Array[Node] = []
	for vehicle in get_tree().get_nodes_in_group(Groups.CHASSIS):
		if vehicle.get_world_3d() != world: continue
		var audio := vehicle.get_node_or_null("Audio")
		if audio != null and audio.has_method("shell_cover"): found.append(audio)
	return found


func _available_voice(priority: int) -> AudioStreamPlayer3D:
	for voice in _voices:
		if not voice.playing: return voice
	if _voices.size() >= MAX_VOICES:
		# Take over the oldest of the lowest-priority voices below this event.
		var taken: AudioStreamPlayer3D = null
		for voice in _voices:
			var rank: int = _priorities.get(voice, 0)
			if rank >= priority: continue
			if taken == null or rank < _priorities.get(taken, 0) or (rank == _priorities.get(taken, 0) and _started.get(voice, 0) < _started.get(taken, 0)):
				taken = voice
		if taken != null: taken.stop()
		return taken
	var voice := AudioStreamPlayer3D.new()
	_ensure_pool().add_child(voice)
	_voices.append(voice)
	return voice


func _ensure_pool() -> Node3D:
	if not is_instance_valid(_pool):
		_pool = Node3D.new()
		_pool.name = "SpatialOneShots"
		# Under the root viewport the pool hangs from this autoload, because a scene
		# can play sounds from _ready while the root is still adding children.
		(self if _listener == get_tree().root else _listener).add_child(_pool)
	return _pool


func _process(delta: float) -> void:
	if not is_instance_valid(_listener):
		set_listener_viewport(get_tree().root)
	for voice in _sources.keys():
		if not voice.playing:
			_sources.erase(voice)
			_offsets.erase(voice)
			_priorities.erase(voice)
			_started.erase(voice)
			continue
		var source := _sources[voice]
		if is_instance_valid(source) and source.is_inside_tree():
			voice.global_position = source.to_global(_offsets[voice])

	var targets: Dictionary[StringName, float] = {&"Exterior": 0.0, &"Cabin": 0.0}
	var mask := 0.0
	var camera := _listener.get_camera_3d()
	if camera != null:
		var inside := false
		var outside_cover := 0.0
		for audio in _vehicle_audio(camera.get_world_3d()):
			mask = maxf(mask, audio.engine_masking(camera.global_position))
			var cover: float = audio.shell_cover()
			if audio.contains_cabin_point(camera.global_position):
				inside = true
				targets[&"Exterior"] = maxf(targets[&"Exterior"], cover)
			else:
				outside_cover = maxf(outside_cover, cover)
		if not inside: targets[&"Cabin"] = outside_cover
	targets[&"Engine"] = targets[&"Exterior"]
	targets[&"Outdoors"] = maxf(targets[&"Exterior"], outdoor_shelter)
	for bus_name in _cover:
		if not is_equal_approx(_cover[bus_name], targets[bus_name]):
			_set_cover(bus_name, move_toward(_cover[bus_name], targets[bus_name], delta / TRANSITION_SECONDS))
	if not is_equal_approx(_mask, mask):
		_set_mask(move_toward(_mask, mask, delta / TRANSITION_SECONDS))


func _set_cover(bus_name: StringName, cover: float) -> void:
	_cover[bus_name] = cover
	var bus := AudioServer.get_bus_index(bus_name)
	var filter := AudioServer.get_bus_effect(bus, 0) as AudioEffectLowPassFilter
	AudioServer.set_bus_volume_db(bus, CLOSED_GAIN_DB * cover + (ENGINE_MASK_DB * _mask if bus_name == &"Exterior" else 0.0))
	filter.cutoff_hz = exp(lerpf(log(OPEN_CUTOFF_HZ), log(CLOSED_CUTOFF_HZ), cover))
	AudioServer.set_bus_effect_enabled(bus, 0, cover > 0.0)


func _set_room(room: AudioEffectReverb) -> void:
	if room == _room: return
	var bus := AudioServer.get_bus_index(&"Effects")
	for index in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, index) == _room:
			AudioServer.remove_bus_effect(bus, index)
			break
	_room = room
	if room != null: AudioServer.add_bus_effect(bus, room, 0)


## Ducks Exterior by the engine masking and gives the loudspeaker most of it back.
func _set_mask(mask: float) -> void:
	_mask = mask
	_set_cover(&"Exterior", _cover[&"Exterior"])
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(&"Loudspeaker"), -ENGINE_MASK_DB * mask * (1.0 - LOUDSPEAKER_MASK_SHARE))


func _exit_tree() -> void:
	_set_room(null)
	# Stop pooled voices before shutdown rather than leaving them mixing.
	for voice in _voices + _echoes:
		if is_instance_valid(voice): voice.stop()
