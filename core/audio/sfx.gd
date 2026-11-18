extends Node
## The pool lives under the listening viewport, including POIs with their own World3D.

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
var _cover := 0.0
var _exterior_bus := -1
var _exterior_filter: AudioEffectLowPassFilter


func _ready() -> void:
	_exterior_bus = AudioServer.get_bus_index(&"Exterior")
	_exterior_filter = AudioServer.get_bus_effect(_exterior_bus, 0) as AudioEffectLowPassFilter
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
	_set_cover(0.0)


func play(event: SoundEvent, source: Node3D, local_position := Vector3.ZERO) -> bool:
	if event.samples.is_empty() or not is_instance_valid(_listener) or not source.is_inside_tree():
		return false
	if source.get_world_3d() != _listener.find_world_3d(): return false
	var voice := _available_voice()
	if voice == null: return false
	voice.stream = event.samples[_rng.randi_range(0, event.samples.size() - 1)]
	voice.bus = event.bus
	voice.volume_db = event.volume_db
	voice.pitch_scale = 1.0 + _rng.randf_range(-event.pitch_variation, event.pitch_variation)
	voice.unit_size = event.unit_size
	voice.max_distance = event.max_distance
	voice.global_position = source.to_global(local_position)
	_sources[voice] = source
	_offsets[voice] = local_position
	voice.play()
	return true


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

	var camera := _listener.get_camera_3d()
	var target := 0.0
	if camera != null:
		for vehicle in get_tree().get_nodes_in_group(Groups.CHASSIS):
			if vehicle.get_world_3d() != camera.get_world_3d(): continue
			var audio := vehicle.get_node_or_null("Audio")
			if audio != null and audio.has_method("exterior_audio_cover"):
				target = maxf(target, audio.exterior_audio_cover(camera.global_position))
	if not is_equal_approx(_cover, target):
		_set_cover(move_toward(_cover, target, delta / TRANSITION_SECONDS))


func _set_cover(cover: float) -> void:
	_cover = cover
	AudioServer.set_bus_volume_db(_exterior_bus, CLOSED_GAIN_DB * cover)
	_exterior_filter.cutoff_hz = exp(lerpf(log(OPEN_CUTOFF_HZ), log(CLOSED_CUTOFF_HZ), cover))
	AudioServer.set_bus_effect_enabled(_exterior_bus, 0, cover > 0.0)
