extends Node3D
## Parked production RV for auditioning its sounds. Walk, open doors, sit and drive with
## the normal controls; the Esc menu's Playground tab plays the recordings that normal
## play cannot trigger on demand.

const SCENARIOS := ["Outside", "Cabin", "Driver seat"]
# Recorded one-shots and the chassis point each plays from in the game.
const ONE_SHOTS := [
	["Handbrake", "handbrake", Vector3(-0.1, 1, -4)],
	["Light switch", "light_switch", Vector3(0, 2.2, -4)],
	["Hatch release", "hatch_release", Vector3(0, -0.08, -5.88)],
	["Hatch latch", "hatch_latch", Vector3(0, -0.08, -5.88)],
	["Ramp clank", "ramp_clank", Vector3(0, 0.6, 5.9)],
	["Jack ratchet", "jack_ratchet", Vector3(1.9, 0.3, 0)],
	["Install", "install", Vector3(0, -0.03, -5.3)],
	["Repair done", "repair_done", Vector3(0, -0.03, -5.3)],
	["Blocked", "blocked", Vector3(1.8, 1.2, 0.75)],
	["Puncture", "puncture", Vector3(1.6, 0.4, -3.8)],
]
const BESIDE_RV := Vector3(3.0, 1.2, 1.5)
const IN_CABIN := Vector3(0.0, 1.2, 1.5)

var rv: Chassis
var player: CharacterBody3D
var controls := PlaygroundControls.new()
var warning := AudioStreamPlayer3D.new()
var tinnitus := AudioStreamPlayer.new()
var rain: Array[AudioStreamPlayer] = []
# Playground-owned copies, so a held loop is not undone by the RV's own contact speeds.
var held_slip: SoundLoop
var held_scrape: SoundLoop
var events: Array[String] = []
var event_index := 0
var message := "-"


func _ready() -> void:
	get_window().title = "ApocalypseRV - RV Audio"
	var scenario := PlaygroundControls.scenario(SCENARIOS[0])
	print("PLAYGROUND scenario=%s" % scenario)
	PlaygroundStage.flat_lot(self)
	rv = PlaygroundStage.parked_rv(self)
	add_child(controls)
	_build_sources()
	_build_controls(scenario)
	# Let the chassis settle on its wheels before placing the player on or in it.
	for i in range(Engine.physics_ticks_per_second): await get_tree().physics_frame
	var aisle := rv.to_global(Vector3(0.25, rv.get_node("Audio").CABIN.position.y + 0.1, 1.65))
	match scenario:
		"Cabin":
			player = PlaygroundStage.player(self, aisle, rv.global_rotation.y)
		"Driver seat":
			player = PlaygroundStage.player(self, aisle, rv.global_rotation.y)
			await get_tree().physics_frame
			rv.set_engine_running(true)
			rv.get_node("DriverSeat").interact_hold(player)
		_:
			var beside := rv.to_global(Vector3(3.6, 0.0, 1.65))
			player = PlaygroundStage.player(self, Vector3(beside.x, 0.05, beside.z), rv.global_rotation.y + PI / 2.0)


func _build_sources() -> void:
	var audio := rv.get_node("Audio")
	held_slip = audio._loop(audio.tire_player.stream, Vector3.ZERO, audio.CONTACT_DB)
	held_scrape = audio._loop(audio.scrape_player.stream, Vector3.ZERO, audio.CONTACT_DB)
	warning.stream = preload("res://assets/audio/slender_speaker/patrol.wav")
	warning.bus = &"Exterior"
	warning.unit_size = 30.0
	warning.max_distance = 75.0
	warning.volume_db = -16.0
	warning.position = Vector3(10.0, 2.0, -9.0)
	rv.add_child(warning)
	for loop in WeatherRain.RAIN_LOOPS:
		var voice := AudioStreamPlayer.new()
		voice.stream = loop
		voice.bus = &"Rain"
		add_child(voice)
		rain.append(voice)
	# Same bus, stream and level as the injury effects.
	tinnitus.stream = preload("res://player/player_injury_effects.gd").RINGING
	tinnitus.bus = &"Self"
	tinnitus.volume_db = linear_to_db(0.22)
	add_child(tinnitus)
	_collect_events("res://assets/audio/events")


func _build_controls(scenario: String) -> void:
	controls.scenarios(SCENARIOS, scenario)
	controls.note("Play normally: E opens doors, hold E on the driver seat to sit, B starts the engine, hold W in neutral to rev, Space toggles the handbrake, L the lights.")
	var audio := rv.get_node("Audio")
	controls.readout("Listener", func():
		var camera := get_viewport().get_camera_3d()
		if camera == null: return "-"
		return "Cabin" if rv.get_node("Audio").CABIN.has_point(rv.to_local(camera.global_position)) else "Outside")
	controls.readout("Drivetrain RPM", func(): return roundi(rv.engine_rpm()))
	controls.readout("Engine sound RPM", func(): return roundi(audio.sound_rpm()) if audio.engine_player.playing else 0)
	controls.readout("Last played", func(): return message)
	controls.section("RV one-shots")
	var shots: Array = []
	for shot in ONE_SHOTS:
		shots.append([shot[0], _play_one_shot.bind(shot)])
	controls.buttons(shots)
	controls.section("Impacts")
	controls.buttons([
		["Light crash", _crash.bind(0.15)],
		["Medium crash", _crash.bind(0.5)],
		["Heavy crash", _crash.bind(0.95)],
		["Tree hit", _tree_hit],
	])
	controls.toggle("Tyre slip loop", false, func(on: bool): held_slip.set_level(1.0 if on else 0.0))
	controls.toggle("Hull scrape loop", false, func(on: bool): held_scrape.set_level(1.0 if on else 0.0))
	controls.section("Sound events")
	var names := PackedStringArray()
	for path in events: names.append(path.trim_prefix("res://assets/audio/events/"))
	controls.choice("Event", names, event_index, func(index: int): event_index = index)
	controls.buttons([["Play beside RV", _play_event.bind(BESIDE_RV)], ["Play in cabin", _play_event.bind(IN_CABIN)]])
	controls.section("Surroundings")
	controls.toggle("Slender Speaker warning", false, func(on: bool):
		if on: warning.play()
		else: warning.stop())
	controls.choice("Warning side", PackedStringArray(["Right", "Left"]), 0, func(index: int): warning.position.x = 10.0 if index == 0 else -10.0)
	controls.choice("Rain", PackedStringArray(["Off", "Light", "Heavy"]), 0, _set_rain)
	controls.toggle("Tinnitus", false, func(on: bool):
		if on: tinnitus.play()
		else: tinnitus.stop())


func _collect_events(path: String) -> void:
	for folder in DirAccess.get_directories_at(path): _collect_events(path.path_join(folder))
	for file in DirAccess.get_files_at(path):
		if file.get_extension() == "tres": events.append(path.path_join(file))


func _play_one_shot(shot: Array) -> void:
	rv.feedback(load("res://assets/audio/events/rv/%s.tres" % shot[1]), shot[2])
	message = shot[0]


func _crash(strength: float) -> void:
	rv.get_node("Audio").play_cue("crash", Vector3(0, 0.8, -6.2), strength)
	message = "Crash %.2f" % strength


func _tree_hit() -> void:
	rv.feedback(TreeImpact.HIT_SOUND, TreeImpact.BUMPER_POSITION)
	message = "Tree hit"


func _play_event(point: Vector3) -> void:
	if events.is_empty(): return
	var played: bool = get_node("/root/Sfx").play(load(events[event_index]), rv, point)
	message = events[event_index].get_file().get_basename() if played else "Voice pool full"


func _set_rain(level: int) -> void:
	for i in range(rain.size()):
		if level == i + 1:
			# WeatherRain's level at full strength of either bed.
			rain[i].volume_db = linear_to_db(0.7)
			if not rain[i].playing: rain[i].play()
		else:
			rain[i].stop()
