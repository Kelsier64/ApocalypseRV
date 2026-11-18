extends "res://tests/playgrounds/rv_design_workshop.gd"
## Parked production RV with repeatable listener positions and the actual warning recording.

var warning: AudioStreamPlayer3D
var side_door: RVDoor
var outside := true
var cue_side := 1.0
var message := ""
var previous_hud_hidden := false


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


func _exit_tree() -> void:
	HUDVisibility.set_cinematic(get_viewport(), previous_hud_hidden)


func _process(_delta: float) -> void:
	var local_position := Vector3(4.3, 1.72, 1.65) if outside else Vector3(0.25, 1.72, 1.65)
	observer.global_position = rv.to_global(local_position)
	observer.look_at(rv.to_global(local_position + Vector3(0, 0, -4)))
	var audio := rv.get_node("Audio")
	instructions.text = (
		"RV AUDIO PILOT   |   %s   |   %s   |   %d RPM\n" +
		"F2 Outside   F3 Cabin   F4 Door   F5 Engine   Hold W to rev\n" +
		"F6 Grain / loop engine   F7 Warning on / off   F8 Move warning\n%s"
	) % ["Outside" if outside else "Cabin", "Loop recordings" if audio.loop_engine else "Grain engine", roundi(rv.engine_rpm()), message]


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
		KEY_F6:
			var audio := rv.get_node("Audio")
			audio.set_loop_engine(not audio.loop_engine)
		KEY_F7:
			if warning.playing: warning.stop()
			else: warning.play()
		KEY_F8:
			cue_side = -cue_side
			_position_warning()
