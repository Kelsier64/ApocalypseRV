extends SceneTree
## Protect spatial playback across POI worlds and isolate sound variation from gameplay RNG.

const MonsterSounds := preload("res://tests/support/monster_sound_probe.gd")

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
	var hall := load("res://assets/audio/rooms/hall.tres") as AudioEffectReverb
	sfx.set_listener_viewport(inside, hall)
	var effects := AudioServer.get_bus_index(&"Effects")
	check(AudioServer.get_bus_effect_count(effects) == 1 and AudioServer.get_bus_effect(effects, 0) == hall,
		"An interior listener hears world sound through its room reverb")
	sfx.set_listener_viewport(root)
	check(AudioServer.get_bus_effect_count(effects) == 0, "The outdoor listener hears no room reverb")
	for file in DirAccess.get_files_at("res://world/instances/catalog"):
		if file.get_extension() != "tres": continue
		var profile := load("res://world/instances/catalog".path_join(file)) as InteriorProfile
		check(profile != null and profile.reverb != null, "%s names a room reverb preset" % file)
		check(profile != null and profile.room_tone is AudioStreamOggVorbis and profile.room_tone.loop, "%s names a looping room tone" % file)
	var tone := load("res://assets/audio/ambience/room_hall.ogg") as AudioStream
	sfx.set_listener_viewport(inside, hall, tone)
	check(sfx.room_tone() == tone and not sfx.listening_outdoors(), "An interior listener carries its room tone")
	sfx.set_listener_viewport(root)
	check(sfx.room_tone() == null and sfx.listening_outdoors(), "The outdoor listener has no room tone")
	await _check_ambience(sfx, inside, tone)
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
	var monster_loop := SoundLoop.new()
	monster_loop.stream = load("res://assets/audio/barrel_man/fuse.wav")
	monster_loop.occlusion_by_position = true
	root.add_child(monster_loop)
	monster_loop.global_position = cabin
	monster_loop.set_level(1.0)
	var cabin_bus := monster_loop.bus
	monster_loop.global_position = outside
	monster_loop.set_level(1.0)
	check(cabin_bus == &"Cabin" and monster_loop.bus == &"Exterior",
		"A positioned loop follows its source in and out of the cabin")
	monster_loop.queue_free()
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
	check(_bus_mix(&"Outdoors").is_equal_approx(outside_exterior), "Outdoor ambience is open beside the RV")
	listener.global_position = cabin
	await _settle_mix(sfx)
	var cabin_exterior := _bus_mix(&"Exterior")
	var cabin_cabin := _bus_mix(&"Cabin")
	check(_bus_mix(&"Engine").is_equal_approx(cabin_exterior), "The engine bay is muffled like the rest of the exterior from the cabin")
	check(_bus_mix(&"Outdoors").is_equal_approx(cabin_exterior), "Outdoor ambience is muffled like the exterior from the cabin")
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

	_check_footstep_surfaces(chassis)
	await _check_rv_footsteps(chassis)
	await _check_wind_audio(sfx, chassis)
	vehicle.queue_free()
	await _check_monster_footfalls()
	await _check_player_footsteps()
	# Silence pooled voices before quitting; see the exit-crash row in docs/plans/README.md.
	for voice in sfx._voices + sfx._echoes: voice.stop()
	await process_frame
	await process_frame
	if failures.is_empty(): print("PASS: RV audio routing, playback isolation and engine transitions")
	quit(0 if failures.is_empty() else 1)


func _check_ambience(sfx: Node, inside: SubViewport, tone: AudioStream) -> void:
	var day := WorldAmbience.weights(1.0, 0.0, 0.0)
	var night := WorldAmbience.weights(0.0, 0.0, 0.0)
	check(day[&"crow"] > 0.0 and day[&"cricket"] == 0.0 and night[&"cricket"] > 0.0 and night[&"crow"] == 0.0,
		"Open ground hears crows by day and crickets by night")
	check(day[&"tree_creak"] == 0.0 and day[&"branch_snap"] == 0.0 and day[&"metal_creak"] == 0.0,
		"Open ground away from trees and road hears neither")
	var woods := WorldAmbience.weights(1.0, 1.0, 0.0)
	check(woods[&"tree_creak"] > 0.0 and woods[&"branch_snap"] > 0.0, "Trees creak and branches snap in the forest")
	check(WorldAmbience.weights(1.0, 0.0, 1.0)[&"metal_creak"] > 0.0, "Metal creaks beside the road")
	for sound in WorldAmbience.OUTDOOR:
		var event: SoundEvent = WorldAmbience.OUTDOOR[sound]
		check(event.bus == &"Outdoors" and not event.occlusion_by_position and not event.samples.is_empty(),
			"The %s sound plays on the outdoor ambience bus" % sound)
	for sound in WorldAmbience.INDOOR:
		var event: SoundEvent = WorldAmbience.INDOOR[sound]
		check(event.occlusion_by_position and not event.samples.is_empty(), "The %s sound plays through the room's reverb" % sound)

	var clock := WorldClock.new()
	var ambience := WorldAmbience.new()
	ambience.clock = clock
	ambience.forest_override = 0.0
	ambience.road_override = 0.0
	root.add_child(ambience)
	var waits := func(mist: float, rain: float) -> float:
		var total := 0.0
		for i in range(200): total += ambience.next_wait(mist, rain)
		return total / 200.0
	var clear: float = waits.call(0.0, 0.0)
	check(clear >= WorldAmbience.INTERVAL.x and clear <= WorldAmbience.INTERVAL.y, "Clear weather spaces sounds within the interval")
	check(waits.call(WorldWeather.FOG_HEAVY, 0.0) > clear and waits.call(0.0, 1.0) > clear, "Fog and rain make sounds rarer")
	var listener := Camera3D.new()
	root.add_child(listener)
	listener.make_current()
	for voice in sfx._voices: voice.stop()
	clock.set_time(1, 12.0)
	check(ambience.play_next() and ambience.last_sound == &"crow", "A clear noon on open ground plays a crow")
	var played: Array = sfx._voices.filter(func(voice): return voice.playing)
	check(played.size() == 1 and played[0].bus == &"Outdoors" and played[0].stream in WorldAmbience.OUTDOOR[&"crow"].samples,
		"The crow plays on the outdoor ambience bus")
	check(ambience.last_distance >= WorldAmbience.OUTDOOR_DISTANCE.x and ambience.last_distance <= WorldAmbience.OUTDOOR_DISTANCE.y,
		"An outdoor sound plays at a distance")
	clock.weather.set_weather(Vector3(0.0, 0.0, WorldWeather.FOG_HEAVY), true)
	var far := 0.0
	for i in range(20):
		ambience.play_next()
		far = maxf(far, ambience.last_distance)
	check(far > WorldAmbience.OUTDOOR_DISTANCE.y, "Fog puts outdoor sounds farther away")
	for voice in sfx._voices: voice.stop()
	var room_camera := Camera3D.new()
	inside.add_child(room_camera)
	room_camera.make_current()
	sfx.set_listener_viewport(inside, null, tone)
	check(ambience.play_next() and ambience.last_sound in WorldAmbience.INDOOR, "An interior plays a drip or a creak")
	var pool := inside.get_node_or_null("SpatialOneShots")
	check(pool != null and pool.get_children().any(func(voice): return voice.playing and voice.bus == &"Exterior"),
		"The interior sound plays in the interior world through its room sound")
	for i in range(ceili(WorldAmbience.ROOM_FADE_SECONDS * Engine.physics_ticks_per_second) + 10): await process_frame
	check(ambience._room.playing and ambience._room.stream == tone and ambience.room_level > 0.0, "Inside an interior its faint hum plays")
	sfx.set_listener_viewport(root)
	for i in range(ceili(WorldAmbience.ROOM_FADE_SECONDS * Engine.physics_ticks_per_second) + 10): await process_frame
	check(not ambience._room.playing, "Back outdoors the hum stops")
	room_camera.queue_free()
	listener.queue_free()
	ambience.free()
	clock.free()


func _check_wind_audio(sfx: Node, chassis: Chassis) -> void:
	var calm := WorldWindAudio.tier_levels(0.0)
	check(calm[0] == 0.0 and calm[1] == 0.0 and calm[2] == 0.0, "Calm plays no wind bed")
	for tier in [WorldWind.BREEZE, WorldWind.STRONG, WorldWind.GALE]:
		check(is_equal_approx(WorldWindAudio.tier_levels(float(tier))[tier - 1], 1.0), "%s plays its own wind bed" % WorldWind.DESCRIPTIONS[tier])
	var between := WorldWindAudio.tier_levels(2.5)
	check(between[1] > 0.0 and between[2] > 0.0 and is_equal_approx(between[1] * between[1] + between[2] * between[2], 1.0),
		"Neighbouring wind beds crossfade at equal power")
	check(WorldWindAudio.masking_for(0.0) == 0.0 and WorldWindAudio.masking_for(WorldWind.SPEEDS[WorldWind.BREEZE]) == 0.0
		and WorldWindAudio.masking_for(WorldWind.SPEEDS[WorldWind.GALE]) > WorldWindAudio.masking_for(WorldWind.SPEEDS[WorldWind.STRONG]),
		"Only a strong wind masks outside sound, a gale most")
	check(WorldWindAudio.rush_rate(float(WorldWind.BREEZE), 1.0, 1.0) == 0.0 and WorldWindAudio.rush_rate(float(WorldWind.GALE), 0.0, 1.0) == 0.0
		and WorldWindAudio.rush_rate(float(WorldWind.GALE), 1.0, 1.0) > WorldWindAudio.rush_rate(float(WorldWind.STRONG), 1.0, 1.0),
		"Treetop rushes need trees and a strong wind, most in a gale")
	for bed: AudioStream in WorldWindAudio.BEDS:
		check(bed is AudioStreamOggVorbis and bed.loop, "%s is a looping Ogg Vorbis bed" % bed.resource_path.get_file())
	check(WorldWindAudio.TREE_RUSH.bus == &"Outdoors" and not WorldWindAudio.TREE_RUSH.occlusion_by_position,
		"Treetop rushes play on the outdoor ambience bus")

	# Masking takes the larger of engine and wind, never their sum.
	var exterior := AudioServer.get_bus_index(&"Exterior")
	var outdoors := AudioServer.get_bus_index(&"Outdoors")
	var speaker := AudioServer.get_bus_index(&"Loudspeaker")
	sfx._set_mask(1.0, 1.0)
	check(is_equal_approx(AudioServer.get_bus_volume_db(exterior), sfx.CLOSED_GAIN_DB * sfx._cover[&"Exterior"] + sfx.ENGINE_MASK_DB),
		"Engine and wind masking together duck outside sound no more than either alone")
	sfx._set_mask(0.0, 1.0)
	check(is_equal_approx(AudioServer.get_bus_volume_db(exterior), sfx.CLOSED_GAIN_DB * sfx._cover[&"Exterior"] + sfx.ENGINE_MASK_DB),
		"A full wind masks outside sound as much as a revving engine")
	check(is_equal_approx(AudioServer.get_bus_volume_db(speaker), -sfx.ENGINE_MASK_DB * (1.0 - sfx.LOUDSPEAKER_MASK_SHARE)),
		"The Slender Speaker gets most of the wind masking back")
	check(is_equal_approx(AudioServer.get_bus_volume_db(outdoors), sfx.CLOSED_GAIN_DB * sfx._cover[&"Outdoors"]),
		"The wind does not mask the outdoor bus it plays on")
	sfx._set_mask(0.0, 0.0)

	var clock := WorldClock.new()
	clock.weather.initialize(7710)
	clock.wind.initialize(clock.weather, 7710)
	var ambience := WorldAmbience.new()
	ambience.clock = clock
	ambience.forest_override = 0.0
	ambience.road_override = 0.0
	var wind := WorldWindAudio.new()
	wind.clock = clock
	wind.ambience = ambience
	root.add_child(ambience)
	root.add_child(wind)
	var listener := Camera3D.new()
	root.add_child(listener)
	listener.make_current()
	listener.global_position = chassis.to_global(Vector3(30, 1.6, 0))
	var settle := func() -> void:
		clock.wind_velocity = clock.wind.velocity(clock.elapsed_seconds)
		for i in range(ceili(sfx.TRANSITION_SECONDS * Engine.physics_ticks_per_second) + 10): await process_frame
	clock.wind.set_override(WorldWind.CALM)
	await settle.call()
	check(not wind._beds.any(func(bed): return bed.playing) and sfx.exterior_masking() == 0.0, "A calm is silent and masks nothing")
	seed(7711)
	var expected := randi()
	seed(7711)
	clock.wind.set_override(WorldWind.GALE)
	await settle.call()
	var gale: AudioStreamPlayer = wind._beds[WorldWind.GALE - 1]
	check(gale.playing and gale.bus == &"Outdoors", "A gale plays its bed on the outdoor ambience bus")
	check(sfx.wind_masking > 0.0 and sfx.exterior_masking() > 0.0, "A gale masks outside sound")
	for voice in sfx._voices: voice.stop()
	check(sfx.play_at(load("res://assets/audio/events/raker/click.tres"), listener.global_position + Vector3(0, 0, -35)), "A distant click plays in the wind")
	var heard: Array = sfx._voices.filter(func(voice): return voice.playing)
	check(heard.size() == 1 and heard[0].bus == &"Exterior" and heard[0].panning_strength < 1.0, "A gale blurs where outside sounds come from")
	var open_db := gale.volume_db
	wind.exposure_override = 1.0 - WorldWind.TREE_SHELTER
	await process_frame
	check(gale.volume_db < open_db, "Ground sheltered by trees hears the wind bed quieter")
	wind.exposure_override = -1.0
	ambience.forest = 1.0
	check(wind.play_rush(float(WorldWind.GALE)), "A gale rushes through the treetops")
	check(sfx._voices.any(func(voice): return voice.playing and voice.bus == &"Outdoors" and voice.stream in WorldWindAudio.TREE_RUSH.samples),
		"Treetop rushes play on the outdoor ambience bus")
	check(randi() == expected, "The wind audio leaves the gameplay RNG sequence intact")

	var hull: RVWindAudio = chassis.get_node("Audio").weather_wind
	check(RVWindAudio.whistle_level(0.0, 0) == 0.0 and RVWindAudio.whistle_level(WorldWind.SPEEDS[WorldWind.BREEZE], 0) == 0.0,
		"The RV does not whistle in a calm or a breeze")
	var gale_speed: float = WorldWind.SPEEDS[WorldWind.GALE]
	check(RVWindAudio.whistle_level(gale_speed, 3) > RVWindAudio.whistle_level(gale_speed, 0)
		and RVWindAudio.whistle_level(gale_speed, 0) > RVWindAudio.whistle_level(WorldWind.SPEEDS[WorldWind.STRONG], 0),
		"The RV whistles louder in a gale and with panels missing")
	check(RVWindAudio.rattle_rate(WorldWind.SPEEDS[WorldWind.BREEZE], 1.0) == 0.0 and RVWindAudio.rattle_rate(gale_speed, 0.0) == 0.0
		and RVWindAudio.rattle_rate(gale_speed, 1.0) > 0.0, "Panels rattle only when a strong gust hits")
	check(hull.whistle.bus == &"Exterior" and (hull.whistle.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD,
		"The hull whistle loops outside the cabin shell")
	hull.speed_override = gale_speed
	await process_frame
	check(hull.whistle.playing, "A gale whistles over the RV")
	hull.speed_override = 0.0
	await process_frame
	check(not hull.whistle.playing, "The whistle stops when the wind drops")
	hull.speed_override = -1.0
	for voice in sfx._voices: voice.stop()
	check(hull.play_rattle(), "A gust rattles a hull panel")
	check(sfx._voices.any(func(voice): return voice.playing and voice.bus == &"Exterior" and voice.stream in RVWindAudio.RATTLE.samples),
		"A panel rattle plays outside the cabin")

	var inside := SubViewport.new()
	inside.own_world_3d = true
	root.add_child(inside)
	var room_camera := Camera3D.new()
	inside.add_child(room_camera)
	room_camera.make_current()
	sfx.set_listener_viewport(inside)
	for i in range(ceili(WorldWindAudio.FADE_SECONDS * Engine.physics_ticks_per_second) + 10): await process_frame
	check(not wind._beds.any(func(bed): return bed.playing) and sfx.exterior_masking() == 0.0, "Inside a POI the wind stops and masks nothing")
	sfx.set_listener_viewport(root)
	for voice in sfx._voices: voice.stop()
	inside.queue_free()
	listener.queue_free()
	wind.free()
	ambience.free()
	clock.free()
	check(sfx.wind_masking == 0.0, "Removing the wind audio clears its masking")


func _check_monster_footfalls() -> void:
	var walker := MonsterFootfalls.new({&"walk": [[0.2, 0], [0.7, 1]]})
	check(walker.advance(&"walk", 0.1).is_empty(), "A gait starts without a footfall")
	check(walker.advance(&"walk", 0.25) == [0] and walker.advance(&"walk", 0.25).is_empty(),
		"Crossing a plant lands that foot once")
	check(walker.advance(&"walk", 0.75) == [1] and walker.advance(&"walk", 0.21) == [0],
		"Footfalls continue across the end of the cycle")
	check(walker.advance(&"walk", 0.15) == [0], "Walking backwards lands the foot it passes")
	check(walker.advance(&"run", 0.25).is_empty(), "A changed clip lands nothing")
	# Each table must match where its clip actually puts the feet down.
	var specs := [
		["res://enemies/raker.tscn", preload("res://enemies/raker_audio.gd").PLANTS, ["foot_L", "foot_R"]],
		["res://enemies/barrel_man.tscn", preload("res://enemies/barrel_man_audio.gd").PLANTS, ["foot_L", "foot_R"]]]
	for spec in specs:
		var actor: Node3D = load(spec[0]).instantiate()
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		root.add_child(actor)
		await process_frame
		for clip: StringName in spec[1]:
			for entry: Array in spec[1][clip]:
				var found := MonsterSounds.plant_phases(actor, clip, spec[2][entry[1]])
				check(found.size() == 1 and _cycle_gap(found[0], entry[0]) < 0.03,
					"%s %s lands on its clip's plant" % [spec[0].get_file(), clip])
		actor.queue_free()
	var giant: Node3D = load("res://enemies/slender_speaker/slender_speaker.tscn").instantiate()
	giant.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(giant)
	await process_frame
	var gait: Array = preload("res://enemies/slender_speaker/slender_speaker_footsteps.gd").PLANTS[&"gait"]
	for clip in ["review/walk", "review/run"]:
		for entry: Array in gait:
			var found := MonsterSounds.plant_phases(giant, clip, ["foot.L", "foot.R"][entry[1]])
			check(found.size() == 1 and _cycle_gap(found[0], entry[0]) < 0.03,
				"The Slender Speaker's shared gait lands on the %s plants" % clip)
	giant.queue_free()
	await process_frame
	# Each monster's decided range must sit well inside its fade to silence.
	var ranges := [
		[load("res://assets/audio/attenuation/presence.tres"), WhiteApparition.SPAWN_MAX, "The white apparition is heard across its spawn ring"],
		[load("res://assets/audio/attenuation/breath.tres"), preload("res://enemies/black_apparition/black_apparition_audio.gd").BREATH_HEARD_WITHIN, "Black apparition breathing is heard within its range"],
		[load("res://assets/audio/attenuation/vocal.tres"), preload("res://enemies/raker_audio.gd").VOCAL_HEARD_WITHIN, "Raker vocals and tells are heard within their range"],
		[load("res://assets/audio/attenuation/giant.tres"), preload("res://enemies/slender_speaker/slender_speaker_footsteps.gd").HEARD_WITHIN, "Slender Speaker footfalls are heard within their range"]]
	for entry in ranges:
		check(_distance_db(entry[0], entry[1]) > -24.0, entry[2])


func _check_footstep_surfaces(chassis: Chassis) -> void:
	var Kind := FootstepSurface.Kind
	var plain := StaticBody3D.new()
	check(FootstepSurface.classify(plain, Vector3.ZERO) == Kind.CONCRETE, "An untagged floor sounds like concrete")
	var building := Node3D.new()
	building.set_meta(FootstepSurface.META, "wood")
	building.add_child(plain)
	check(FootstepSurface.classify(plain, Vector3.ZERO) == Kind.WOOD, "A building's surface tag reaches the floors inside it")
	building.free()
	check(FootstepSurface.classify(chassis, chassis.to_global(Vector3(0, 0.45, 0))) == Kind.WOOD, "The RV cabin floor sounds like wood")
	check(FootstepSurface.classify(chassis, chassis.to_global(Vector3(0, 2.75, 0))) == Kind.METAL, "The RV roof sounds like sheet metal")
	# A loose chunk shaped like a streamed one: road and ground meshes over static bodies.
	var field := WorldField.new(4242)
	var chunk := ChunkGenerator.new()
	chunk.field = field
	var floors := {}
	for surface_name in ["Road", "Ground"]:
		var surface := MeshInstance3D.new()
		surface.name = surface_name
		chunk.add_child(surface)
		floors[surface_name] = StaticBody3D.new()
		surface.add_child(floors[surface_name])
	var frame := field.road_frame(400.0)
	var edge := field.road_width(400.0) * 0.5
	check(FootstepSurface.classify(floors.Road, frame.origin) == Kind.ASPHALT, "Streamed road sounds like asphalt")
	var shoulder := frame.origin + frame.basis.x * (edge + FootstepSurface.SHOULDER * 0.5)
	check(FootstepSurface.classify(floors.Ground, shoulder) == Kind.GRAVEL, "Ground just past the carriageway is the gravel shoulder")
	for offset in range(40, 120, 10):
		var kind := FootstepSurface.classify(floors.Ground, frame.origin + frame.basis.x * offset)
		check(kind in [Kind.GRASS, Kind.DIRT, Kind.GRAVEL], "Open ground is grass, dirt or a gravel pad")
	var steep := Vector3(1, 1, 0).normalized()
	check(FootstepSurface.ground(field, frame.origin + frame.basis.x * 80.0, steep) != Kind.GRASS, "Steep ground is bare earth, not grass")
	chunk.free()


## A player's own step inside the cabin plays wood on the Cabin bus; on the roof,
## sheet metal outside the shell.
func _check_rv_footsteps(chassis: Chassis) -> void:
	var sfx := root.get_node("Sfx")
	var player: CharacterBody3D = load("res://player/player.tscn").instantiate()
	root.add_child(player)
	var footsteps = player.get_node("Footsteps")
	for spot in [[Vector3(0, 0.6, 2.0), FootstepSurface.Kind.WOOD, &"Cabin", "inside the cabin"],
			[Vector3(0, 3.0, 0.0), FootstepSurface.Kind.METAL, &"Exterior", "on the roof"]]:
		player.global_position = chassis.to_global(spot[0])
		player.velocity = Vector3.ZERO
		for i in 30: await physics_frame
		MonsterSounds.stop_all(sfx)
		check(footsteps.step(), "A step plays %s" % spot[3])
		check(footsteps.last_surface == spot[1], "A step %s plays its surface" % spot[3])
		var event: SoundEvent = footsteps.EVENTS[spot[1]]
		var routed: Array = sfx._voices.filter(func(voice): return voice.playing and voice.stream in event.samples)
		check(routed.size() == 1 and routed[0].bus == spot[2], "A step %s routes to %s" % [spot[3], spot[2]])
	player.queue_free()
	await physics_frame


## A real player on a flat floor: steps follow the distance walked, sprinting and
## crouching change stride and level, landing adds a step, standing makes none.
func _check_player_footsteps() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(200, 0.2, 200)
	floor_body.add_child(shape)
	floor_body.position = Vector3(400, -0.1, 0)
	root.add_child(floor_body)
	var player: CharacterBody3D = load("res://player/player.tscn").instantiate()
	player.position = Vector3(400, 0.05, 60)
	root.add_child(player)
	var footsteps = player.get_node("Footsteps")
	var ticks := Engine.physics_ticks_per_second
	for i in ticks: await physics_frame
	check(footsteps.steps_taken == 0, "Standing still makes no footsteps")
	var walks := {}
	for gait in [&"walk", &"sprint", &"crouch"]:
		if gait == &"sprint": Input.action_press("sprint")
		if gait == &"crouch": Input.action_press("crouch")
		for i in 10: await physics_frame
		Input.action_press("move_forward")
		var start := player.global_position
		var before: int = footsteps.steps_taken
		for i in ticks * 2: await physics_frame
		check(footsteps.gait() == gait, "The %s gait is recognised" % gait)
		Input.action_release("move_forward")
		var walked := player.global_position.distance_to(start)
		var taken: int = footsteps.steps_taken - before
		var stride: float = footsteps.STRIDE[gait]
		check(absi(taken - roundi(walked / stride)) <= 1, "%s steps follow the distance walked (%d over %.1f m)" % [gait, taken, walked])
		check(is_equal_approx(footsteps.last_gain_db, footsteps.GAIN[gait]), "%s steps play at their gait level" % gait)
		check(footsteps.last_surface == FootstepSurface.Kind.CONCRETE, "A plain floor plays concrete steps")

		walks[gait] = taken / maxf(walked, 0.01)
		Input.action_release("sprint")
		Input.action_release("crouch")
		for i in 20: await physics_frame
	# Headless playback never ends, so the walks above filled the pool.
	MonsterSounds.stop_all(root.get_node("Sfx"))
	check(footsteps.step() and MonsterSounds.playing(root.get_node("Sfx"), footsteps.EVENTS[FootstepSurface.Kind.CONCRETE]) == 1,
		"A step on a plain floor is heard")
	check(walks[&"sprint"] < walks[&"walk"] and walks[&"walk"] < walks[&"crouch"], "Longer strides space steps out at speed")
	var before_fall: int = footsteps.steps_taken
	player.global_position += Vector3.UP * 2.0
	player.velocity = Vector3.ZERO
	for i in ticks * 2: await physics_frame
	check(footsteps.steps_taken == before_fall + 1 and footsteps.last_gain_db > footsteps.GAIN[&"walk"],
		"Landing from a fall plays one heavier step")
	player.queue_free()
	floor_body.queue_free()
	await physics_frame


## Godot 4.7 inverse-distance falloff, capped at +3 dB, times the linear fade
## to silence at max_distance.
static func _distance_db(attenuation: SoundAttenuation, distance: float) -> float:
	var falloff := minf(attenuation.unit_size / distance, db_to_linear(3.0))
	return linear_to_db(falloff * maxf(0.0, 1.0 - distance / attenuation.max_distance))


static func _cycle_gap(a: float, b: float) -> float:
	return absf(fposmod(a - b + 0.5, 1.0) - 0.5)


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
