extends SceneTree
## Protect spatial playback across POI worlds and isolate sound variation from gameplay RNG.

var failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("FAIL: " + message)


func _run() -> void:
	var sfx := root.get_node("Sfx")
	var settings := root.get_node("GameSettings")
	var outside_source := Node3D.new()
	root.add_child(outside_source)
	var inside := SubViewport.new()
	inside.own_world_3d = true
	root.add_child(inside)
	var inside_source := Node3D.new()
	inside.add_child(inside_source)
	var door_open := load("res://assets/audio/events/rv/door_open.tres") as SoundEvent
	var door_close := load("res://assets/audio/events/rv/door_close.tres") as SoundEvent
	for event in [door_open, door_close]:
		check(event.samples.size() == 1 and event.samples[0] is AudioStreamWAV, "The RV door uses a recorded sample")
	_check_event_folder("res://assets/audio/events")

	seed(7710)
	var expected := randi()
	seed(7710)
	check(sfx.play(door_open, outside_source), "The pool plays a root-world event")
	check(randi() == expected, "A one-shot leaves the gameplay RNG sequence intact")
	for i in range(sfx.MAX_VOICES - 1):
		check(sfx.play(door_open, outside_source), "The pool allocates until its limit")
	check(not sfx.play(door_close, outside_source), "The voice limit also applies across different events")

	sfx.set_listener_viewport(inside)
	check(inside.audio_listener_enable_3d and not root.audio_listener_enable_3d, "Only the selected viewport listens")
	check(not sfx.play(door_open, outside_source), "The POI pool rejects coordinates from the highway world")
	check(sfx.play(door_open, inside_source), "The POI pool accepts sources from its own World3D")
	check(inside.get_node("SpatialOneShots").get_child(0).get_world_3d() == inside.find_world_3d(),
		"The POI player resolves its position in the interior world")
	sfx.set_listener_viewport(root)
	inside.queue_free()
	outside_source.queue_free()

	check(AudioServer.get_bus_send(AudioServer.get_bus_index(&"Exterior")) == &"Effects", "Threat cue follows the effects slider")
	check(AudioServer.get_bus_send(AudioServer.get_bus_index(&"Rain")) == &"Ambience", "Rain follows the ambience slider")
	var original: float = settings.get_setting(&"effects_volume")
	settings.set_setting(&"effects_volume", 0.0, false)
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Effects")), "The effects slider can mute gameplay sounds")
	settings.set_setting(&"effects_volume", original, false)

	var vehicle: Node3D = load("res://rv/new_rv.tscn").instantiate()
	root.add_child(vehicle)
	var chassis: Chassis = vehicle.get_node("Chassis")
	chassis.freeze = true
	await physics_frame
	var audio := chassis.get_node("Audio")
	var door: RVDoor = chassis.get_node("RightMiddle")
	var cabin := chassis.to_global(Vector3(0, 1.65, 0.75))
	var outside := chassis.to_global(Vector3(6.0, 1.65, 0.75))
	var closed_cover: float = audio.shell_cover()
	check(closed_cover > 0.0, "A sealed shell separates cabin and exterior sound")
	check(audio.contains_cabin_point(cabin) and not audio.contains_cabin_point(chassis.to_global(Vector3(0, 3.4, 0.75))),
		"The RV roof does not count as its cabin")
	check(sfx.bus_at(cabin, chassis.get_world_3d()) == &"Cabin" and sfx.bus_at(outside, chassis.get_world_3d()) == &"Exterior",
		"Positioned events route by whether they play inside the cabin")
	check(audio.engine_grains.bus == &"Exterior", "The engine bay sits outside the cabin mix")
	var listener := Camera3D.new()
	root.add_child(listener)
	listener.make_current()
	listener.global_position = outside
	await _settle_mix(sfx)
	var outside_exterior := _bus_mix(&"Exterior")
	var outside_cabin := _bus_mix(&"Cabin")
	listener.global_position = cabin
	await _settle_mix(sfx)
	var cabin_exterior := _bus_mix(&"Exterior")
	var cabin_cabin := _bus_mix(&"Cabin")
	check(cabin_exterior.x < outside_exterior.x and cabin_exterior.y < outside_exterior.y, "The cabin lowers the exterior bus level and cutoff")
	check(outside_cabin.x < cabin_cabin.x and outside_cabin.y < cabin_cabin.y, "Standing outside lowers the cabin bus level and cutoff")
	listener.queue_free()
	await _settle_mix(sfx)
	check(door.toggle_leaf(0) == "Door opening", "Production door opens in the audio fixture")
	var pool := sfx.get_node_or_null("SpatialOneShots")
	check(pool != null and _playing(pool, door_open.samples[0]), "Opening the door selects its latch release recording")
	for i in range(100):
		if is_equal_approx(door.angles[0], door.targets[0]): break
		await physics_frame
	check(closed_cover > audio.shell_cover(), "An open door noticeably reduces cabin cover")
	check(door.toggle_leaf(0) == "Door closing", "Production door closes in the audio fixture")
	for i in range(100):
		if is_equal_approx(door.angles[0], door.targets[0]): break
		await physics_frame
	check(pool != null and _playing(pool, door_close.samples[0]), "The closing recording plays when the latch reaches the frame")
	var grains: AudioStreamPlayer3D = audio.engine_grains
	check(chassis.set_engine_running(true), "The fixture starts through the production engine control")
	check(audio.engine_cue.playing and audio.engine_cue.stream == audio.engine_start_sound, "Starting the engine plays the starter recording")
	audio._update_engine(0.4, Chassis.ENGINE_IDLE_RPM)
	check(not grains.playing, "Cranking starts before the engine runs")
	audio.engine_cue.stop()
	audio._update_engine(0.4, Chassis.ENGINE_IDLE_RPM)
	check(grains.playing and grains.get_stream_playback() is AudioStreamGeneratorPlayback, "The grain engine streams at idle")
	var idle_hz: float = audio.engine_firing_hz()
	var step := 1.0 / Engine.physics_ticks_per_second
	for i in range(Engine.physics_ticks_per_second):
		audio._update_engine(step, Chassis.ENGINE_MAX_RPM)
	var revved_hz: float = audio.engine_firing_hz()
	check(revved_hz > idle_hz * 2.0, "Revving raises the firing rate well above idle")
	var revved_speed: float = audio.engine_speed
	var half_shift := ceili(audio.SHIFT_SECONDS * 0.5 / step)
	for i in range(half_shift):
		audio._update_engine(step, Chassis.ENGINE_IDLE_RPM)
	var plain_fall_hz: float = audio.engine_firing_hz()
	audio.engine_speed = revved_speed
	audio.play_cue("gear", Vector3(-0.1, 1, -4))
	check(pool != null and _playing_any(pool, load(audio.GEAR_SHIFT).samples), "Changing gear plays a lever recording")
	for i in range(half_shift):
		audio._update_engine(step, Chassis.ENGINE_IDLE_RPM)
	check(audio._shift_load_scale() < 0.25, "Load drops out halfway through a shift")
	check(audio.engine_firing_hz() > plain_fall_hz, "Revs glide down more slowly across a gear change than when lifting off")
	for i in range(ceili(audio.SHIFT_SECONDS / step)):
		audio._update_engine(step, Chassis.ENGINE_IDLE_RPM)
	check(is_equal_approx(audio._shift_load_scale(), 1.0), "Load returns after the shift")
	# Free revving in neutral goes through the real pedal path and pulls the engine.
	chassis.set_gear(0)
	chassis.allow_test_controls = true
	chassis.control_override = {"throttle": 1.0}
	for i in range(Engine.physics_ticks_per_second):
		await physics_frame
	check(chassis.engine_pedal() > audio.engine_synth.PULL_ON and audio.engine_synth.pulling,
		"Revving in neutral plays the pulling grains")
	chassis.control_override = {}
	audio.was_running = true
	check(chassis.set_engine_running(false), "The fixture shuts down through the production engine control")
	audio._process(0.025)
	check(audio.engine_cue.playing and audio.engine_cue.stream == audio.engine_stop_sound, "Shutting down plays the tail recording")
	check(grains.playing, "The running engine fades under the shutdown instead of cutting")
	audio._update_engine(0.4, 0.0)
	check(not grains.playing, "The grain engine stops after shutdown")
	_check_grain_synth(audio.engine_synth.bank)
	check(audio.road_layers.size() == RVTireModel.Surface.size(), "Every road surface has a rolling loop")
	for layer: AudioStreamPlayer3D in audio.road_layers + [audio.wind_player]:
		check((layer.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD, "Rolling and wind recordings loop forward")
	check(RVTireModel.surface(null, Vector3.ZERO) == RVTireModel.Surface.ASPHALT, "Without a world field the road counts as asphalt")
	var cruise: float = audio.ROAD_REFERENCE_SPEED
	check(audio.road_level(0.0) == 0.0 and audio.wind_level(0.0) == 0.0, "A parked RV makes no rolling or wind noise")
	check(audio.road_level(cruise) > audio.road_level(cruise * 0.5), "Rolling noise grows with speed")
	check(audio.wind_level(cruise) / audio.wind_level(cruise * 0.5) > audio.road_level(cruise) / audio.road_level(cruise * 0.5),
		"Wind grows faster with speed than rolling noise")
	audio._update_road(0.1)
	for layer: AudioStreamPlayer3D in audio.road_layers:
		check(not layer.playing, "Road loops stay silent while the wheels are off the ground or parked")

	vehicle.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: RV audio routing, playback isolation and engine transitions")
	quit(0 if failures.is_empty() else 1)


func _check_grain_synth(bank: EngineGrainBank) -> void:
	var count := bank.size()
	check(count > 0 and bank.periods.size() == count and bank.fades.size() == count and bank.lengths.size() == count
		and bank.firing_hz.size() == count and bank.kinds.size() == count and bank.follows.size() == count
		and bank.levels.size() == count and bank.brightness.size() == count and bank.cylinders.size() == count,
		"Every grain has a complete record")
	check(bank.idle_hz >= bank.min_hz() and bank.top_hz > bank.idle_hz * 2.0 and bank.top_hz <= bank.max_hz(),
		"The bank spans from its idle to a raised top rate")
	var pcm := bank.pcm()
	var valid := true
	for i in range(count):
		valid = valid and bank.starts[i] + bank.lengths[i] <= pcm.size() and bank.follows[i] < count
		valid = valid and bank.lengths[i] == bank.periods[i] + 2 * bank.fades[i]
	check(valid, "Grain spans stay inside the sample data and runs point at real grains")
	var synth := EngineGrainSynth.new(bank)
	var frames := int(bank.samples.mix_rate)
	seed(7710)
	var expected := randi()
	seed(7710)
	var idle := synth.render(frames, synth.idle_hz(), synth.idle_hz(), 0.0)
	check(randi() == expected, "Rendering grains leaves the gameplay RNG sequence intact")
	var idle_grains := synth.grains_started
	synth.reset()
	var fast_hz := synth.idle_hz() * 3.0
	var fast := synth.render(frames, fast_hz, fast_hz, 1.0)
	var fast_grains := synth.grains_started - idle_grains
	var expected_ratio := fast_hz / synth.idle_hz()
	check(absf(float(fast_grains) / idle_grains / expected_ratio - 1.0) < 0.15, "Firings per second follow the requested rate")
	check(synth.jumps * 2 < fast_grains, "A held raised rate follows the recording between splices")
	var peak := 0.0
	for sample in idle + fast: peak = maxf(peak, absf(sample))
	check(peak > 0.0 and peak < 1.0, "Overlapping grains stay within full scale")


func _playing_any(pool: Node, streams: Array) -> bool:
	for stream in streams:
		if _playing(pool, stream): return true
	return false


func _check_event_folder(path: String) -> void:
	for folder in DirAccess.get_directories_at(path):
		_check_event_folder(path.path_join(folder))
	for file in DirAccess.get_files_at(path):
		if file.get_extension() != "tres": continue
		var event := load(path.path_join(file)) as SoundEvent
		check(event != null, "%s is a SoundEvent" % file)
		if event == null: continue
		check(not event.samples.is_empty(), "%s has at least one sample" % file)
		for sample in event.samples:
			check(sample != null and sample.get_length() > 0.0, "%s samples load with audio" % file)
		check(AudioServer.get_bus_index(event.bus) >= 0, "%s routes to a configured bus" % file)
		check(event.max_distance > event.unit_size, "%s fades out beyond its reference distance" % file)
		check(event.volume_db <= 0.0, "%s leaves headroom" % file)


func _bus_mix(bus_name: StringName) -> Vector2:
	var bus := AudioServer.get_bus_index(bus_name)
	var filter := AudioServer.get_bus_effect(bus, 0) as AudioEffectLowPassFilter
	var cutoff := filter.cutoff_hz if AudioServer.is_bus_effect_enabled(bus, 0) else INF
	return Vector2(AudioServer.get_bus_volume_db(bus), cutoff)


func _settle_mix(sfx: Node) -> void:
	for i in range(ceili(sfx.TRANSITION_SECONDS * Engine.physics_ticks_per_second) + 10):
		await process_frame


func _playing(pool: Node, stream: AudioStream) -> bool:
	for cue in pool.get_children():
		if cue.stream == stream and cue.playing:
			return true
	return false
