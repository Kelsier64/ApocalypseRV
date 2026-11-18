extends Node
## The pool lives under the listening viewport, including POIs with their own World3D.
## Cabin and Exterior are muffled from the other side of the RV shell: a listener
## inside the cabin hears Exterior through the shell, one outside hears Cabin.

const MAX_VOICES := 12
const OPEN_CUTOFF_HZ := 20500.0
const CLOSED_CUTOFF_HZ := 1500.0
const CLOSED_GAIN_DB := -8.0
const TRANSITION_SECONDS := 0.3

var _rng := RandomNumberGenerator.new()
var _listener: Viewport
var _pool: Node3D
var _voices: Array[AudioStreamPlayer3D] = []
var _sources: Dictionary[AudioStreamPlayer3D, Node3D] = {}
var _offsets: Dictionary[AudioStreamPlayer3D, Vector3] = {}
## Current muffle per bus name, 0 open to 1 sealed shell.
var _cover: Dictionary[StringName, float] = {&"Exterior": 0.0, &"Cabin": 0.0}


func _ready() -> void:
	set_listener_viewport(get_tree().root)


func set_listener_viewport(viewport: Viewport) -> void:
	if _listener == viewport: return
	if is_instance_valid(_listener):
		_listener.audio_listener_enable_3d = false
	if is_instance_valid(_pool):
		for voice in _voices: voice.stop()
		_pool.queue_free()
	_pool = null
	_voices.clear()
	_sources.clear()
	_offsets.clear()
	_listener = viewport
	_listener.audio_listener_enable_3d = true
	for bus_name in _cover: _set_cover(bus_name, 0.0)


func play(event: SoundEvent, source: Node3D, local_position := Vector3.ZERO) -> bool:
	if event.samples.is_empty() or not is_instance_valid(_listener) or not source.is_inside_tree():
		return false
	if source.get_world_3d() != _listener.find_world_3d(): return false
	var voice := _available_voice()
	if voice == null: return false
	var at := source.to_global(local_position)
	voice.stream = event.samples[_rng.randi_range(0, event.samples.size() - 1)]
	voice.bus = bus_at(at, source.get_world_3d()) if event.occlusion_by_position else event.bus
	voice.volume_db = event.volume_db
	voice.pitch_scale = 1.0 + _rng.randf_range(-event.pitch_variation, event.pitch_variation)
	voice.unit_size = event.unit_size
	voice.max_distance = event.max_distance
	voice.global_position = at
	_sources[voice] = source
	_offsets[voice] = local_position
	voice.play()
	return true


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


func _available_voice() -> AudioStreamPlayer3D:
	for voice in _voices:
		if not voice.playing: return voice
	if _voices.size() >= MAX_VOICES: return null
	if not is_instance_valid(_pool):
		_pool = Node3D.new()
		_pool.name = "SpatialOneShots"
		_listener.add_child(_pool)
	var voice := AudioStreamPlayer3D.new()
	_pool.add_child(voice)
	_voices.append(voice)
	return voice


func _process(delta: float) -> void:
	if not is_instance_valid(_listener):
		set_listener_viewport(get_tree().root)
	for voice in _sources.keys():
		if not voice.playing:
			_sources.erase(voice)
			_offsets.erase(voice)
			continue
		var source := _sources[voice]
		if is_instance_valid(source) and source.is_inside_tree():
			voice.global_position = source.to_global(_offsets[voice])

	var targets: Dictionary[StringName, float] = {&"Exterior": 0.0, &"Cabin": 0.0}
	var camera := _listener.get_camera_3d()
	if camera != null:
		var inside := false
		var outside_cover := 0.0
		for audio in _vehicle_audio(camera.get_world_3d()):
			var cover: float = audio.shell_cover()
			if audio.contains_cabin_point(camera.global_position):
				inside = true
				targets[&"Exterior"] = maxf(targets[&"Exterior"], cover)
			else:
				outside_cover = maxf(outside_cover, cover)
		if not inside: targets[&"Cabin"] = outside_cover
	for bus_name in _cover:
		if not is_equal_approx(_cover[bus_name], targets[bus_name]):
			_set_cover(bus_name, move_toward(_cover[bus_name], targets[bus_name], delta / TRANSITION_SECONDS))


func _set_cover(bus_name: StringName, cover: float) -> void:
	_cover[bus_name] = cover
	var bus := AudioServer.get_bus_index(bus_name)
	var filter := AudioServer.get_bus_effect(bus, 0) as AudioEffectLowPassFilter
	AudioServer.set_bus_volume_db(bus, CLOSED_GAIN_DB * cover)
	filter.cutoff_hz = exp(lerpf(log(OPEN_CUTOFF_HZ), log(CLOSED_CUTOFF_HZ), cover))
	AudioServer.set_bus_effect_enabled(bus, 0, cover > 0.0)
