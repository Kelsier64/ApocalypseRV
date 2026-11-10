extends Node3D

const FLASHLIGHT := "res://props/flashlight.tscn"

@onready var player = $Player
@onready var apparition: BlackApparition = $BlackApparition
@onready var status: Label = $PlaygroundHUD/Status
var _requested_spawn := false
var _spawn_feedback := ""

func _ready() -> void:
	get_window().title = "ApocalypseRV - Black Apparition Playground"
	player.camera.make_current()
	player.add_item("Flashlight", false, FLASHLIGHT)
	apparition.configure(player, true)
	apparition.emerge($ApparitionStart.global_position, player.camera)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.physical_keycode:
		KEY_R:
			get_viewport().set_input_as_handled()
			get_tree().reload_current_scene.call_deferred()
		KEY_F6:
			if player.is_player_dead: return
			get_viewport().set_input_as_handled()
			_requested_spawn = true

func _physics_process(_delta: float) -> void:
	if _requested_spawn:
		_requested_spawn = false
		_spawn_feedback = "Sighting moved. Check the dark around you." if apparition.try_emerge() \
			else "No dark spot from here. Move or turn, then try F6 again."
	if player.is_player_dead:
		status.text = "Contact was fatal. Press R to restart."
		return
	var phase: String = BlackApparition.Phase.keys()[apparition.phase].capitalize()
	var gaze := minf(apparition._gaze_time, BlackApparition.GAZE_SECONDS)
	var hint := "\n" + _spawn_feedback if not _spawn_feedback.is_empty() else ""
	status.text = "%s   Gaze %.1f / %.1f s   SAN %.1f%s" % [
		phase, gaze, BlackApparition.GAZE_SECONDS, player.survival.san, hint]
