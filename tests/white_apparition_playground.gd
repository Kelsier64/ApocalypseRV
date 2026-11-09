extends Node3D

const CAPTURE_DIRECTORY := "res://.godot/white_apparition"
const CAPTURE_PATH := CAPTURE_DIRECTORY + "/context.png"
const CAPTURE_AFTER_PATH := CAPTURE_DIRECTORY + "/context-after.png"

enum ReplayStep { WAITING, PERIPHERAL, CAPTURING_AFTER, LOOK_AWAY }

@onready var player = $Player
@onready var apparition: WhiteApparition = $WhiteApparition
@onready var status: Label = $HUD/Status

var _replay := "--replay" in OS.get_cmdline_user_args()
var _elapsed := 0.0
var _replay_started := false
var _replay_step := ReplayStep.WAITING
var _san_at_capture := 0.0
var _peripheral_view := Transform3D.IDENTITY
var _peripheral_origin := Vector3.ZERO
var _peripheral_screen_x := 0.0
var _peripheral_elapsed := 0.0
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
	match _replay_step:
		ReplayStep.WAITING:
			if phase == WhiteApparition.Phase.HIDDEN: return
			player.camera.look_at(apparition.to_global(WhiteApparition.CHEST))
			if phase == WhiteApparition.Phase.CONFIRMED and player.survival.san <= -10.0:
				_begin_peripheral()
		ReplayStep.PERIPHERAL:
			_verify_peripheral(phase, delta)
		ReplayStep.LOOK_AWAY:
			_verify_look_away(phase, delta)

func _begin_peripheral() -> void:
	var camera: Camera3D = player.camera
	var chest := apparition.to_global(WhiteApparition.CHEST)
	var distance := camera.global_position.distance_to(chest)
	if distance < WhiteApparition.DISTANT_SPAWN_MIN:
		_replay_error("White apparition replay did not start in the distant emergence band")
		return
	camera.rotate_y(deg_to_rad(32.0))
	_replay_step = ReplayStep.PERIPHERAL
	_peripheral_view = camera.global_transform
	_peripheral_origin = apparition.global_position
	_peripheral_screen_x = camera.unproject_position(chest).x
	_san_at_capture = player.survival.san
	if await _save_capture(CAPTURE_PATH):
		print("WHITE_APPARITION_CAPTURE distance=%.2f san=%.1f path=%s" % [distance, _san_at_capture, CAPTURE_PATH])

func _verify_peripheral(phase: WhiteApparition.Phase, delta: float) -> void:
	_peripheral_elapsed += delta
	var camera: Camera3D = player.camera
	var chest := apparition.to_global(WhiteApparition.CHEST)
	if phase != WhiteApparition.Phase.CONFIRMED or not apparition.visible or not camera.is_position_in_frustum(chest) \
		or apparition._point_in_frame(camera, chest, WhiteApparition.CENTER):
		_replay_error("White apparition left the visible periphery during replay relocation")
		return
	if player.survival.san != _san_at_capture or not camera.global_transform.is_equal_approx(_peripheral_view):
		_replay_error("SAN or the fixed camera changed during peripheral relocation")
		return
	var displacement := (apparition.global_position - _peripheral_origin).slide(Vector3.UP)
	if _peripheral_elapsed < WhiteApparition.REPOSITION_DELAY - delta and not displacement.is_zero_approx():
		_replay_error("White apparition moved before the peripheral delay")
		return
	if not apparition._reposition_spent or apparition._reposition_target.is_finite(): return
	var rect := get_viewport().get_visible_rect()
	var screen_x := camera.unproject_position(chest).x
	var viewport_shift := (absf(screen_x - rect.get_center().x) - absf(_peripheral_screen_x - rect.get_center().x)) / rect.size.x
	var inward := (camera.global_position - _peripheral_origin).slide(Vector3.UP).normalized()
	var approach := displacement.dot(inward)
	if viewport_shift < 0.06 or approach < 6.0:
		_replay_error("White apparition did not visibly shift toward the edge and approach during replay")
		return
	_replay_step = ReplayStep.CAPTURING_AFTER
	if not await _save_capture(CAPTURE_AFTER_PATH): return
	print("WHITE_APPARITION_PERIPHERAL viewport_shift=%.3f relocation_inward=%.2f relocation_lateral=%.2f san_unchanged=true path=%s" % [viewport_shift, approach, displacement.slide(inward).length(), CAPTURE_AFTER_PATH])
	_look_away_origin = apparition.global_position
	_replay_step = ReplayStep.LOOK_AWAY
	camera.rotate_y(PI)

func _verify_look_away(phase: WhiteApparition.Phase, delta: float) -> void:
	_look_away_elapsed += delta
	var grace := WhiteApparition.UNSEEN_DESPAWN_SECONDS
	var timely_despawn := phase == WhiteApparition.Phase.HIDDEN and not apparition.visible and _look_away_elapsed >= grace - delta
	if player.survival.san != _san_at_capture:
		_replay_error("White apparition kept draining SAN after the replay looked away")
	elif apparition.global_position != _look_away_origin:
		_replay_error("White apparition relocated again after the replay looked away")
	elif _look_away_elapsed > grace + 2.0 * delta or (not apparition.visible and not timely_despawn):
		_replay_error("White apparition disappeared outside the expected grace period")
	elif timely_despawn:
		print("WHITE_APPARITION_REPLAY confirmed=true despawn_after_looking_away=%.2f san_unchanged=true san=%.1f" % [_look_away_elapsed, _san_at_capture])
		get_tree().quit()

func _save_capture(path: String) -> bool:
	await RenderingServer.frame_post_draw
	var error := DirAccess.make_dir_recursive_absolute(CAPTURE_DIRECTORY)
	if error == OK:
		error = get_viewport().get_texture().get_image().save_png(path)
	if error != OK:
		_replay_error("White apparition screenshot failed: %s" % error_string(error))
	return error == OK

func _replay_error(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
