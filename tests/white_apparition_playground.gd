extends Node3D

const CAPTURE_DIRECTORY := "res://.godot/white_apparition"
const CAPTURE_PATH := CAPTURE_DIRECTORY + "/context.png"

@onready var player = $Player
@onready var apparition: WhiteApparition = $WhiteApparition
@onready var status: Label = $HUD/Status

var _replay := "--replay" in OS.get_cmdline_user_args()
var _elapsed := 0.0
var _capture_started := false
var _capture_saved := false
var _thresholds := 0

func _ready() -> void:
	player.camera.make_current()
	if _replay: apparition._rng.seed = 2026
	apparition.configure(player)
	apparition.threshold_reached.connect(_on_threshold_reached)

func _physics_process(delta: float) -> void:
	var phase := apparition._phase
	status.text = "Sightings %d/3   %s" % [apparition._gaze.count, WhiteApparition.Phase.keys()[phase].capitalize()]
	if not _replay: return
	_elapsed += delta
	if _elapsed > 45.0:
		push_error("White apparition replay timed out")
		get_tree().quit(1)
		return
	if phase == WhiteApparition.Phase.VISIBLE:
		player.camera.look_at(apparition.to_global(WhiteApparition.CHEST))
		if apparition._presence >= 0.95 and not _capture_started:
			_capture_started = true
			_capture_context()
	if phase == WhiteApparition.Phase.COOLDOWN and _thresholds == 1 and _capture_saved:
		print("WHITE_APPARITION_REPLAY sightings=", apparition._gaze.count, " threshold=", _thresholds)
		get_tree().quit()

func _capture_context() -> void:
	await RenderingServer.frame_post_draw
	var error := DirAccess.make_dir_recursive_absolute(CAPTURE_DIRECTORY)
	if error == OK:
		error = get_viewport().get_texture().get_image().save_png(CAPTURE_PATH)
	if error != OK:
		push_error("White apparition screenshot failed: %s" % error_string(error))
		get_tree().quit(1)
		return
	_capture_saved = true
	print("WHITE_APPARITION_CAPTURE distance=%.2f path=%s" % [player.camera.global_position.distance_to(apparition.global_position), CAPTURE_PATH])

func _on_threshold_reached(observer: Node3D) -> void:
	if observer == player: _thresholds += 1
