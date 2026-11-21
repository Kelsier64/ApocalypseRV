extends "res://tests/playgrounds/rv_design_workshop.gd"
## Parked production RV with repeatable listener positions and the actual warning recording.

# Number keys 1-0 play these recorded one-shots from their usual chassis point.
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

var warning: AudioStreamPlayer3D
var side_door: RVDoor
var outside := true
var cue_side := 1.0
var message := ""
var previous_hud_hidden := false
# Playground-owned copies, so holding a key is not undone by the RV's own contact speeds.
var held_slip: SoundLoop
var held_scrape: SoundLoop
# Every SoundEvent under assets/audio/events, played from beside or inside the RV.
var events: Array[String] = []
var event_index := 0
var event_inside := false
var rain: Array[AudioStreamPlayer] = []
var rain_level := 0
var tinnitus := AudioStreamPlayer.new()
var inhale := AudioStreamPlayer.new()


func _ready() -> void:
	super._ready()
	get_window().title = "ApocalypseRV - RV Audio Pilot"
	get_window().mode = Window.MODE_WINDOWED
	var viewport := get_viewport()
	previous_hud_hidden = viewport.get_meta("cinematic_hud_hidden", false)
	HUDVisibility.set_cinematic(viewport, true)
	rv.freeze = true
	rv.set_gear(0)
	player.set_process_unhandled_input(false)
	side_door = rv.get_node("RightMiddle") as RVDoor
	warning = AudioStreamPlayer3D.new()
	warning.stream = preload("res://assets/audio/slender_speaker/patrol.wav")
	warning.bus = &"Exterior"
	warning.unit_size = 30.0
	warning.max_distance = 75.0
	warning.volume_db = -16.0
	rv.add_child(warning)
	_position_warning()
	instructions.position = Vector2(24, 24)
	var audio := rv.get_node("Audio")
	held_slip = audio._loop(audio.tire_player.stream, Vector3.ZERO, audio.CONTACT_DB)
	held_scrape = audio._loop(audio.scrape_player.stream, Vector3.ZERO, audio.CONTACT_DB)
	_collect_events("res://assets/audio/events")
	for loop in WeatherRain.RAIN_LOOPS:
		var voice := AudioStreamPlayer.new()
		voice.stream = loop
		voice.bus = &"Rain"
		add_child(voice)
		rain.append(voice)
	# Same bus, stream and level as the injury and recovery code.
	tinnitus.stream = preload("res://player/player_injury_effects.gd").RINGING
	tinnitus.bus = &"Self"
	tinnitus.volume_db = linear_to_db(0.22)
	inhale.stream = preload("res://player/body_recovery.gd").INHALE
	inhale.bus = &"Self"
	inhale.volume_db = -12.0
	add_child(tinnitus)
	add_child(inhale)


func _collect_events(path: String) -> void:
	for folder in DirAccess.get_directories_at(path): _collect_events(path.path_join(folder))
	for file in DirAccess.get_files_at(path):
		if file.get_extension() == "tres": events.append(path.path_join(file))


func _exit_tree() -> void:
	HUDVisibility.set_cinematic(get_viewport(), previous_hud_hidden)


func _process(_delta: float) -> void:
	var local_position := Vector3(4.3, 1.72, 1.65) if outside else Vector3(0.25, 1.72, 1.65)
	observer.global_position = rv.to_global(local_position)
	observer.look_at(rv.to_global(local_position + Vector3(0, 0, -4)))
	var audio := rv.get_node("Audio")
	held_slip.set_level(1.0 if Input.is_key_pressed(KEY_B) else 0.0)
	held_scrape.set_level(1.0 if Input.is_key_pressed(KEY_N) else 0.0)
	var ringing := Input.is_key_pressed(KEY_T)
	if ringing != tinnitus.playing:
		if ringing: tinnitus.play()
		else: tinnitus.stop()
	instructions.text = (
		"RV AUDIO PILOT   |   %s   |   %d drivetrain RPM   |   %d bus RPM\n" +
		"F2 Outside   F3 Cabin   F4 Door   F5 Engine   Hold W to rev\n" +
		"F7 Warning on / off   F8 Move warning\n" +
		"1 Handbrake  2 Switch  3 Hatch release  4 Hatch latch  5 Ramp  6 Jack  7 Install  8 Repair  9 Blocked  0 Puncture\n" +
		"Z / X / C Light / medium / heavy crash   V Tree hit   Hold B Tyre slip   Hold N Hull scrape\n" +
		", / . Pick event   Space Play %s %s   F9 Source in cabin / outside\n" +
		"R Rain: %s   Hold T Tinnitus   Y Revival gasp\n%s"
	) % ["Outside" if outside else "Cabin",
		roundi(rv.engine_rpm()), roundi(audio.sound_rpm()) if audio.engine_player.playing else 0,
		events[event_index].trim_prefix("res://assets/audio/events/") if not events.is_empty() else "-",
		"in cabin" if event_inside else "beside the RV", ["off", "light", "heavy"][rain_level], message]


func _physics_process(_delta: float) -> void:
	rv.control_override["throttle"] = Input.get_action_strength("move_forward")


func _position_warning() -> void:
	warning.position = Vector3(10.0 * cue_side, 2.0, -9.0)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_F2: outside = true
		KEY_F3: outside = false
		KEY_F4: message = side_door.toggle_leaf(0)
		KEY_F5:
			var start := rv.engine_rpm() == 0.0
			if rv.set_engine_running(start): message = "Engine running" if start else "Engine off"
			else: message = rv.engine_start_reason()
		KEY_F7:
			if warning.playing: warning.stop()
			else: warning.play()
		KEY_F8:
			cue_side = -cue_side
			_position_warning()
		KEY_Z, KEY_X, KEY_C:
			rv.get_node("Audio").play_cue("crash", Vector3(0, 0.8, -6.2), {KEY_Z: 0.15, KEY_X: 0.5, KEY_C: 0.95}[event.keycode])
		KEY_V:
			rv.feedback(TreeImpact.HIT_SOUND, TreeImpact.BUMPER_POSITION)
		KEY_COMMA, KEY_PERIOD:
			if not events.is_empty(): event_index = posmod(event_index + (1 if event.keycode == KEY_PERIOD else -1), events.size())
		KEY_SPACE:
			if not events.is_empty():
				var point := Vector3(0.0, 1.2, 1.5) if event_inside else Vector3(3.0, 1.2, 1.5)
				message = "Played" if get_node("/root/Sfx").play(load(events[event_index]), rv, point) else "Voice pool full"
		KEY_F9: event_inside = not event_inside
		KEY_R:
			rain_level = (rain_level + 1) % 3
			for i in range(rain.size()):
				# WeatherRain's level at full strength of either bed.
				rain[i].volume_db = linear_to_db(0.7) if rain_level == i + 1 else -80.0
				if rain_level == i + 1 and not rain[i].playing: rain[i].play()
				elif rain_level != i + 1: rain[i].stop()
		KEY_Y: inhale.play()
		_:
			var index: int = (event.keycode - KEY_1 + 10) % 10 if event.keycode >= KEY_0 and event.keycode <= KEY_9 else -1
			if index >= 0:
				var shot: Array = ONE_SHOTS[index]
				rv.feedback(load("res://assets/audio/events/rv/%s.tres" % shot[1]), shot[2])
				message = shot[0]
