extends Node3D

const CAPTURE_DIRECTORY := "res://.godot/white_apparition"
const CAPTURE_PATH := CAPTURE_DIRECTORY + "/context.png"

@onready var player = $Player
@onready var apparition: WhiteApparition = $WhiteApparition
@onready var status: Label = $HUD/Status

var _replay := "--replay" in OS.get_cmdline_user_args()
var _elapsed := 0.0
var _replay_started := false
var _capture_started := false
var _capture_saved := false
var _san_at_capture := 0.0
var _look_away_origin := Vector3.ZERO
var _look_away_elapsed := 0.0

func _ready() -> void:
	player.camera.make_current()
	# Start the replay in the distant emergence band.
	if _replay: apparition._rng.seed = 2
	apparition.configure(player)

func _physics_process(delta: float) -> void:
	var phase := apparition._phase
	status.text = WhiteApparition.Phase.keys()[phase].capitalize()
	if not _replay: return
	_elapsed += delta
	# Give the encounter and its streamed-ground fixture a few physics ticks to initialize.
	if not _replay_started and _elapsed >= 0.1:
		_replay_started = true
		apparition._time_left = 0.0
	if _elapsed > 60.0:
		push_error("White apparition replay timed out")
		get_tree().quit(1)
		return
	if _capture_saved:
		_verify_look_away(phase, delta)
	elif phase != WhiteApparition.Phase.HIDDEN:
		player.camera.look_at(apparition.to_global(WhiteApparition.CHEST))
		if phase == WhiteApparition.Phase.CONFIRMED and player.survival.san <= -10.0 and not _capture_started:
			_capture_started = true
			_capture_context()

func _verify_look_away(phase: WhiteApparition.Phase, delta: float) -> void:
	_look_away_elapsed += delta
	var grace := WhiteApparition.UNSEEN_DESPAWN_SECONDS
	var timely_despawn := phase == WhiteApparition.Phase.HIDDEN and not apparition.visible and _look_away_elapsed >= grace - delta
	var displacement := (apparition.global_position - _look_away_origin).slide(Vector3.UP)
	if player.survival.san != _san_at_capture:
		push_error("White apparition kept draining SAN after the replay looked away")
		get_tree().quit(1)
	elif _look_away_elapsed < WhiteApparition.REPOSITION_DELAY - delta and not displacement.is_zero_approx():
		push_error("White apparition moved before the look-away delay")
		get_tree().quit(1)
	elif _look_away_elapsed > grace + 2.0 * delta or (not apparition.visible and not timely_despawn):
		push_error("White apparition disappeared outside the expected grace period")
		get_tree().quit(1)
	elif timely_despawn:
		var inward: Vector3 = (player.camera.global_position - _look_away_origin).slide(Vector3.UP).normalized()
		var approach := displacement.dot(inward)
		var lateral := displacement.slide(inward).length()
		if approach < 1.99 or approach > 4.01 or lateral < 1.99 or lateral > 4.01:
			push_error("White apparition did not complete its diagonal relocation while offscreen")
			get_tree().quit(1)
			return
		print("WHITE_APPARITION_REPLAY confirmed=true despawn_after_looking_away=%.2f relocation_inward=%.2f relocation_lateral=%.2f san_unchanged=true san=%.1f" % [_look_away_elapsed, approach, lateral, _san_at_capture])
		get_tree().quit()

func _capture_context() -> void:
	var distance: float = player.camera.global_position.distance_to(apparition.to_global(WhiteApparition.CHEST))
	if distance < WhiteApparition.DISTANT_SPAWN_MIN:
		push_error("White apparition replay did not start in the distant emergence band")
		get_tree().quit(1)
		return
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
	_look_away_origin = apparition.global_position
	print("WHITE_APPARITION_CAPTURE distance=%.2f san=%.1f path=%s" % [distance, _san_at_capture, CAPTURE_PATH])
	player.camera.rotate_y(PI)
