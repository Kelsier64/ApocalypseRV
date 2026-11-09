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
var _look_away_elapsed := 0.0

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
	if _capture_saved:
		_verify_look_away(phase, delta)
	elif phase == WhiteApparition.Phase.VISIBLE:
		player.camera.look_at(apparition.to_global(WhiteApparition.CHEST))
	elif phase == WhiteApparition.Phase.CONFIRMED and player.survival.san <= -10.0 and not _capture_started:
		_capture_started = true
		_capture_context()

func _verify_look_away(phase: WhiteApparition.Phase, delta: float) -> void:
	_look_away_elapsed += delta
	var grace := WhiteApparition.UNSEEN_DESPAWN_SECONDS
	var timely_despawn := phase == WhiteApparition.Phase.HIDDEN and not apparition.visible and _look_away_elapsed >= grace - delta
	if player.survival.san != _san_at_capture:
		push_error("White apparition kept draining SAN after the replay looked away")
		get_tree().quit(1)
	elif _look_away_elapsed > grace + 2.0 * delta or (not apparition.visible and not timely_despawn):
		push_error("White apparition disappeared outside the expected grace period")
		get_tree().quit(1)
	elif timely_despawn:
		print("WHITE_APPARITION_REPLAY confirmed=true despawn_after_looking_away=%.2f san_unchanged=true san=%.1f" % [_look_away_elapsed, _san_at_capture])
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
