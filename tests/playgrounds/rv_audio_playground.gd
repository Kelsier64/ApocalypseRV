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


func _exit_tree() -> void:
	HUDVisibility.set_cinematic(get_viewport(), previous_hud_hidden)


func _process(_delta: float) -> void:
	var local_position := Vector3(4.3, 1.72, 1.65) if outside else Vector3(0.25, 1.72, 1.65)
	observer.global_position = rv.to_global(local_position)
	observer.look_at(rv.to_global(local_position + Vector3(0, 0, -4)))
	var audio := rv.get_node("Audio")
	held_slip.set_level(1.0 if Input.is_key_pressed(KEY_B) else 0.0)
	held_scrape.set_level(1.0 if Input.is_key_pressed(KEY_N) else 0.0)
	instructions.text = (
		"RV AUDIO PILOT   |   %s   |   %d drivetrain RPM   |   %d bus RPM\n" +
		"F2 Outside   F3 Cabin   F4 Door   F5 Engine   Hold W to rev\n" +
		"F7 Warning on / off   F8 Move warning\n" +
		"1 Handbrake  2 Switch  3 Hatch release  4 Hatch latch  5 Ramp  6 Jack  7 Install  8 Repair  9 Blocked  0 Puncture\n" +
		"Z / X / C Light / medium / heavy crash   V Tree hit   Hold B Tyre slip   Hold N Hull scrape\n%s"
	) % ["Outside" if outside else "Cabin",
		roundi(rv.engine_rpm()), roundi(audio.sound_rpm()) if audio.engine_player.playing else 0, message]


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
		_:
			var index: int = (event.keycode - KEY_1 + 10) % 10 if event.keycode >= KEY_0 and event.keycode <= KEY_9 else -1
			if index >= 0:
				var shot: Array = ONE_SHOTS[index]
				rv.feedback(load("res://assets/audio/events/rv/%s.tres" % shot[1]), shot[2])
				message = shot[0]
