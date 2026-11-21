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
	var shot := load("res://assets/audio/events/pistol/shot.tres") as SoundEvent
	check(shot.priority > door_open.priority and sfx.play(shot, outside_source),
		"A full pool hands a lower-priority voice to a gunshot")
	check(sfx.play(shot, outside_source) and not sfx.play(door_close, outside_source),
		"Taken voices still count against the limit for low-priority events")
	check(sfx._echoes.size() == 2 and sfx._echoes.all(func(echo): return echo.playing and echo.bus == &"OutdoorEcho"),
		"Each outdoor gunshot adds an echo tail")
	for i in range(sfx.MAX_ECHOES + 2): sfx.play(shot, outside_source)
	check(sfx._echoes.size() == sfx.MAX_ECHOES and sfx._voices.size() == sfx.MAX_VOICES,
		"Echo tails use their own capped voices instead of the one-shot pool")
	var shooter := Node3D.new()
	root.add_child(shooter)
	for voice in sfx._voices + sfx._echoes: voice.stop()
	check(sfx.play(door_open, outside_source) and not sfx._echoes.any(func(echo): return echo.playing),
		"Events without an echo level play dry")
	for voice in sfx._voices: voice.stop()
	var reload := load("res://assets/audio/events/pistol/reload.tres") as SoundEvent
	check(sfx.play(reload, shooter) and sfx.play(door_open, outside_source), "Two sources play side by side")
	sfx.stop_from(shooter)
	var still_playing := 0
	for voice in sfx._voices: if voice.playing: still_playing += 1
	check(still_playing == 1, "Stopping one source's sounds leaves other sources playing")
	shooter.queue_free()

	sfx.set_listener_viewport(inside)
	check(inside.audio_listener_enable_3d and not root.audio_listener_enable_3d, "Only the selected viewport listens")
	check(not sfx.play(door_open, outside_source), "The POI pool rejects coordinates from the highway world")
	check(sfx.play(door_open, inside_source), "The POI pool accepts sources from its own World3D")
	check(sfx.play(shot, inside_source) and sfx._echoes.is_empty(), "A gunshot inside a POI interior has no outdoor echo")
	check(inside.get_node("SpatialOneShots").get_child(0).get_world_3d() == inside.find_world_3d(),
		"The POI player resolves its position in the interior world")
	sfx.set_listener_viewport(root)
	var burst := door_close.duplicate() as SoundEvent
	burst.cooldown_seconds = 1.0
	check(sfx.play(burst, outside_source) and not sfx.play(burst, outside_source) and sfx.play(door_close, outside_source),
		"A repeat inside the cooldown is skipped without blocking other events")
	inside.queue_free()
	outside_source.queue_free()

	check(AudioServer.get_bus_send(AudioServer.get_bus_index(&"Exterior")) == &"Effects", "Threat cue follows the effects slider")
	check(AudioServer.get_bus_send(AudioServer.get_bus_index(&"Rain")) == &"Ambience", "Rain follows the ambience slider")
	check(AudioServer.get_bus_send(AudioServer.get_bus_index(&"Self")) == &"Master",
		"The player's own ringing bypasses the World muffle")
	var original: float = settings.get_setting(&"effects_volume")
	settings.set_setting(&"effects_volume", 0.0, false)
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Effects")), "The effects slider can mute gameplay sounds")
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Self")), "The effects slider also mutes the player's own sounds")
	settings.set_setting(&"effects_volume", original, false)
	var loops: Array[AudioStream] = WeatherRain.RAIN_LOOPS.duplicate()
	loops.append_array([load("res://player/player_injury_effects.gd").RINGING, load("res://equipment/scrapper_crush_effect.gd").GRINDING])
	for loop: AudioStreamWAV in loops:
		check(loop.loop_mode == AudioStreamWAV.LOOP_FORWARD and loop.mix_rate == 44100, "%s loops forward at 44.1 kHz" % loop.resource_path.get_file())
	for loop: AudioStreamWAV in WeatherRain.RAIN_LOOPS:
		check(loop.stereo, "%s keeps its stereo width" % loop.resource_path.get_file())

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
	for echo in sfx._echoes: echo.stop()
	check(sfx.play(shot, chassis, chassis.to_local(cabin)) and not sfx._echoes.any(func(echo): return echo.playing),
		"A gunshot inside the cabin has no outdoor echo")
	check(audio.engine_player.bus == &"Engine" and audio.engine_cue.bus == &"Engine"
		and AudioServer.get_bus_send(AudioServer.get_bus_index(&"Engine")) == &"Effects",
		"The engine plays on its own bus under the effects slider")
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
	check(_bus_mix(&"Engine").is_equal_approx(cabin_exterior), "The engine bay is muffled like the rest of the exterior from the cabin")
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
	var engine_player: AudioStreamPlayer3D = audio.engine_player
	check(chassis.set_engine_running(true), "The fixture starts through the production engine control")
	check(audio.engine_cue.playing and audio.engine_cue.stream == audio.engine_start_sound, "Starting the engine plays the starter recording")
	audio._update_engine(0.4, Chassis.ENGINE_IDLE_RPM)
	check(not engine_player.playing, "Cranking starts before the engine runs")
	audio.engine_cue.stop()
	audio._update_engine(0.4, Chassis.ENGINE_IDLE_RPM)
	check(engine_player.playing and engine_player.stream is BusEngineStream, "The bus engine plays at idle")
	var idle_rpm: float = audio.sound_rpm()
	var step := 1.0 / Engine.physics_ticks_per_second
	for i in range(Engine.physics_ticks_per_second):
		audio._update_engine(step, Chassis.ENGINE_MAX_RPM)
	var revved_rpm: float = audio.sound_rpm()
	check(revved_rpm > idle_rpm * 2.0, "Revving raises the simulated RPM well above idle")
	var revved_speed: float = audio.engine_speed
	var half_shift := ceili(audio.SHIFT_SECONDS * 0.5 / step)
	for i in range(half_shift):
		audio._update_engine(step, Chassis.ENGINE_IDLE_RPM)
	var plain_fall_rpm: float = audio.sound_rpm()
	audio.engine_speed = revved_speed
	audio.play_cue("gear", Vector3(-0.1, 1, -4))
	check(pool != null and _playing_any(pool, load(audio.GEAR_SHIFT).samples), "Changing gear plays a lever recording")
	chassis.set_handbrake(not chassis.handbrake)
	check(_playing_any(pool, Chassis.HANDBRAKE_SOUND.samples), "The parking brake plays its lever recording")
	chassis.set_handbrake(not chassis.handbrake)
	audio.play_cue("crash", Vector3.INF, 1.0)
	audio.play_cue("crash", Vector3.INF, 0.0)
	check(_playing_any(pool, audio.CRASH_SOUNDS[-1].samples) and _playing_any(pool, audio.CRASH_SOUNDS[0].samples),
		"Collision strength picks between the heavy and light recordings")
	for i in range(half_shift):
		audio._update_engine(step, Chassis.ENGINE_IDLE_RPM)
	check(audio._shift_load_scale() < 0.25, "Load drops out halfway through a shift")
	check(audio.sound_rpm() > plain_fall_rpm, "Revs glide down more slowly across a gear change than when lifting off")
	for i in range(ceili(audio.SHIFT_SECONDS / step)):
		audio._update_engine(step, Chassis.ENGINE_IDLE_RPM)
	check(is_equal_approx(audio._shift_load_scale(), 1.0), "Load returns after the shift")
	# Free revving in neutral goes through the real pedal path and pulls the engine.
	chassis.set_gear(0)
	chassis.allow_test_controls = true
	chassis.control_override = {"throttle": 1.0}
	var driver := Camera3D.new()
	root.add_child(driver)
	driver.make_current()
	driver.global_position = cabin
	for i in range(Engine.physics_ticks_per_second):
		await physics_frame
	var unmasked: float = sfx.CLOSED_GAIN_DB * sfx._cover[&"Exterior"]
	var exterior_duck := _bus_mix(&"Exterior").x - unmasked
	var speaker_duck := exterior_duck + AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Loudspeaker"))
	check(exterior_duck < -1.0, "A revving engine masks other outside sound for the driver")
	check(speaker_duck < 0.0 and speaker_duck > exterior_duck, "The Slender Speaker is masked less than other outside sound")
	check(is_equal_approx(_bus_mix(&"Engine").x, sfx.CLOSED_GAIN_DB * sfx._cover[&"Engine"]), "The engine does not mask itself")
	check(audio.engine_masking(cabin) > audio.engine_masking(outside) and audio.engine_masking(chassis.to_global(Vector3(40, 1.6, 0))) == 0.0,
		"Engine masking fades with distance from the RV")
	driver.queue_free()
	check(chassis.engine_pedal() > 0.9 and audio.engine_load > 0.9
		and engine_player.pitch_scale > BusEngineStream.pitch_for(idle_rpm),
		"Revving in neutral raises the bus playback speed and selects loaded exhaust")
	chassis.control_override = {}
	audio.was_running = true
	check(chassis.set_engine_running(false), "The fixture shuts down through the production engine control")
	audio._process(0.025)
	check(audio.engine_cue.playing and audio.engine_cue.stream == audio.engine_stop_sound, "Shutting down plays the tail recording")
	check(engine_player.playing, "The running engine fades under the shutdown instead of cutting")
	audio._update_engine(0.4, 0.0)
	check(not engine_player.playing, "The bus engine stops after shutdown")
	_check_bus_loops(audio.engine_stream)
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
	# Silence pooled voices before quitting; see the exit-crash row in docs/plans/README.md.
	for voice in sfx._voices + sfx._echoes: voice.stop()
	await process_frame
	await process_frame
	if failures.is_empty(): print("PASS: RV audio routing, playback isolation and engine transitions")
	quit(0 if failures.is_empty() else 1)


func _check_bus_loops(bank: BusEngineStream) -> void:
	var width := bank.RPMS.size()
	check(bank.BANK.format == AudioStreamWAV.FORMAT_16_BITS and not bank.BANK.stereo,
		"The bus sample bank imports as uncompressed mono PCM16")
	check(bank.stream_count == width * bank.PEDALS.size(), "Every dyno operating point has a loop")
	var first := bank.get_sync_stream(0) as AudioStreamWAV
	for i in range(bank.stream_count):
		var loop := bank.get_sync_stream(i) as AudioStreamWAV
		check(loop.loop_mode == AudioStreamWAV.LOOP_FORWARD and loop.loop_end == first.loop_end
			and loop.loop_end > 0 and loop.data.size() == loop.loop_end * 2,
			"Bus layers loop across matching four-stroke cycles")
	var middle := lerpf(bank.RPMS[1], bank.RPMS[2], 0.5)
	bank.set_operating_point(middle, bank.PEDALS[1] * 0.5)
	for i in range(bank.stream_count):
		var expected := 0.25 if i in [1, 2, width + 1, width + 2] else 0.0
		check(is_equal_approx(db_to_linear(bank.get_sync_stream_volume(i)), expected),
			"RPM and pedal interpolate only the four adjacent dyno recordings")
	bank.set_operating_point(bank.RPMS.back(), bank.PEDALS.back())
	check(is_zero_approx(bank.get_sync_stream_volume(bank.stream_count - 1)),
		"Full throttle at redline plays the highest loaded recording at unity gain")


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
		check(event.attenuation != null and event.attenuation.max_distance > event.attenuation.unit_size,
			"%s fades out beyond its reference distance" % file)
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
