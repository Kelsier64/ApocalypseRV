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
		check(AudioServer.get_bus_index(event.bus) >= 0, "The door routes to a configured bus")

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
	var closed_cover: float = audio.exterior_audio_cover(cabin)
	check(closed_cover > audio.exterior_audio_cover(chassis.to_global(Vector3(0, 3.4, 0.75))), "The RV roof does not count as its cabin")
	check(door.toggle_leaf(0) == "Door opening", "Production door opens in the audio fixture")
	var pool := root.get_node_or_null("SpatialOneShots")
	check(pool != null and _playing(pool, door_open.samples[0]), "Opening the door selects its latch release recording")
	for i in range(100):
		if is_equal_approx(door.angles[0], door.targets[0]): break
		await physics_frame
	check(closed_cover > audio.exterior_audio_cover(cabin), "An open door noticeably reduces cabin cover")
	check(door.toggle_leaf(0) == "Door closing", "Production door closes in the audio fixture")
	for i in range(100):
		if is_equal_approx(door.angles[0], door.targets[0]): break
		await physics_frame
	check(pool != null and _playing(pool, door_close.samples[0]), "The closing recording plays when the latch reaches the frame")
	var layers: Array[AudioStreamPlayer3D] = audio.engine_layers
	for layer in layers:
		var recording := layer.stream as AudioStreamWAV
		check(recording.loop_mode == AudioStreamWAV.LOOP_FORWARD, "Imported engine samples loop forward")
		check(layer.bus == &"Cabin", "Engine layers share the cabin mix")
	check(chassis.set_engine_running(true), "The fixture starts through the production engine control")
	check(audio.engine_cue.playing and audio.engine_cue.stream == audio.engine_start_sound, "Starting the engine plays the starter recording")
	audio._update_engine(0.4, Chassis.ENGINE_IDLE_RPM)
	check(not layers[0].playing, "Cranking starts before the engine loops")
	audio.engine_cue.stop()
	audio._update_engine(0.4, Chassis.ENGINE_IDLE_RPM)
	check(layers[0].playing and not layers[1].playing and not layers[2].playing, "Only the idle layer runs when parked")
	var above_idle := lerpf(Chassis.ENGINE_IDLE_RPM, Chassis.ENGINE_MAX_RPM, 0.28)
	audio._update_engine(0.4, above_idle)
	check(layers[0].playing and layers[1].playing, "Low RPM fades between idle and cruise")
	check(is_equal_approx(layers[0].pitch_scale * audio.ENGINE_PULSE_HZ[0], layers[1].pitch_scale * audio.ENGINE_PULSE_HZ[1]),
		"Adjacent engine layers share a pulse rate through the crossfade")
	var cruising := lerpf(Chassis.ENGINE_IDLE_RPM, Chassis.ENGINE_MAX_RPM, 0.53)
	audio._update_engine(0.4, cruising)
	check(not layers[0].playing and layers[1].playing and not layers[2].playing, "Cruising uses its own recording")
	audio._update_engine(0.4, Chassis.ENGINE_MAX_RPM)
	check(not layers[0].playing and not layers[1].playing and layers[2].playing, "High RPM fades into the higher engine recording")
	var running_volume := layers[2].volume_db
	audio.was_running = true
	check(chassis.set_engine_running(false), "The fixture shuts down through the production engine control")
	audio._process(0.025)
	check(audio.engine_cue.playing and audio.engine_cue.stream == audio.engine_stop_sound, "Shutting down plays the tail recording")
	check(layers[2].playing and layers[2].volume_db < running_volume, "The running loop fades under the shutdown")
	audio._update_engine(0.4, 0.0)
	for layer in layers:
		check(not layer.playing, "Engine loops stop after shutdown")

	vehicle.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: RV audio routing, playback isolation and engine transitions")
	quit(0 if failures.is_empty() else 1)


func _playing(pool: Node, stream: AudioStream) -> bool:
	for cue in pool.get_children():
		if cue.stream == stream and cue.playing:
			return true
	return false
