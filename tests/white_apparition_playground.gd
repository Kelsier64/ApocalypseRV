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
var _san_at_capture := 0.0

func _ready() -> void:
	player.camera.make_current()
	if _replay: apparition._rng.seed = 2026
	apparition.configure(player)

func _physics_process(delta: float) -> void:
	var phase := apparition._phase
	status.text = WhiteApparition.Phase.keys()[phase].capitalize()
	if not _replay: return
	_elapsed += delta
	if _elapsed > 45.0:
		push_error("White apparition replay timed out")
		get_tree().quit(1)
		return
	if phase == WhiteApparition.Phase.VISIBLE:
		player.camera.look_at(apparition.to_global(WhiteApparition.CHEST))
	elif phase == WhiteApparition.Phase.CONFIRMED:
		if player.survival.san <= -10.0 and not _capture_started:
			_capture_started = true
			_capture_context()
		if _capture_saved and apparition.visible and player.survival.san <= _san_at_capture - 100.0:
			print("WHITE_APPARITION_REPLAY confirmed=true visible_after_looking_away=true san=%.1f" % player.survival.san)
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
	_san_at_capture = player.survival.san
	print("WHITE_APPARITION_CAPTURE distance=%.2f san=%.1f path=%s" % [player.camera.global_position.distance_to(apparition.global_position), _san_at_capture, CAPTURE_PATH])
	player.camera.rotate_y(PI)
