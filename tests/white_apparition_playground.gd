extends "res://world/main_world.gd"

const CAPTURE_DIRECTORY := "res://.godot/white_apparition"
const CAPTURE_PATH := CAPTURE_DIRECTORY + "/context.png"
const CAPTURE_AFTER_PATH := CAPTURE_DIRECTORY + "/context-after.png"
const WORLD_SEED := 42
const ROAD_START := 330.0

enum ReplayStep { WAITING, PERIPHERAL, CAPTURING_AFTER, LOOK_AWAY }

@onready var player = $Player
@onready var encounter = $WhiteApparitionEncounter
@onready var status: Label = $PlaygroundHUD/Status

var apparition: WhiteApparition
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

func _enter_tree() -> void:
	set_meta("checkpoint_staging", true)
	var generator := get_node("WorldGenerator")
	generator.world_seed = WORLD_SEED
	super._enter_tree()
	# Start past the tutorial without moving either actor when its band streams in.
	fresh_start = false
	get_node("StartRun").phase = "sealed"
	var field := WorldField.new(WORLD_SEED, generator.profile)
	var band := floori(ROAD_START / generator.profile.chunk_length)
	generator.restore_bands.assign(range(band - generator.profile.chunks_behind, band + generator.profile.chunks_ahead + 1))
	get_node("Player").transform = field.road_frame(ROAD_START).translated(Vector3.UP * 0.25)

func _ready() -> void:
	super._ready()
	remove_meta("checkpoint_staging")
	get_window().title = "ApocalypseRV - White Apparition Playground"
	var clock: WorldClock = $WorldClock
	clock.running = false
	clock.weather_running = false
	clock.weather.set_weather(Vector3.ZERO, true)
	clock.set_time(1, 14.0)
	player.camera.make_current()
	if _replay:
		player.camera.fov = 75.0
		# The normal background drain stops at zero. Starting there isolates encounter drain.
		player.survival.san = 0.0

func _unhandled_key_input(event: InputEvent) -> void:
	if _replay or not event is InputEventKey or not event.pressed or event.echo or event.physical_keycode != KEY_F6:
		return
	if is_instance_valid(apparition) and apparition._active_player_camera() != null:
		_request_sighting()
		get_viewport().set_input_as_handled()

func _request_sighting() -> void:
	apparition._reset()
	apparition._time_left = 0.0

func _physics_process(delta: float) -> void:
	if _replay:
		_elapsed += delta
		if _elapsed > 60.0:
			_replay_error("White apparition replay timed out")
			return
	apparition = encounter._apparition
	if not is_instance_valid(apparition) or apparition._world_id == 0: return
	var phase := apparition._phase
	status.text = "WASD move   Mouse look   F6 request sighting\n%s   SAN %.1f" % [WhiteApparition.Phase.keys()[phase].capitalize(), player.survival.san]
	if not _replay: return
	# Wait until the live player settles onto the streamed road.
	if not _replay_started and _elapsed >= 0.2 and player.is_on_floor():
		_replay_started = true
		_request_sighting()
		apparition._rng.seed = 2
	match _replay_step:
		ReplayStep.WAITING:
			if phase == WhiteApparition.Phase.HIDDEN: return
			player.camera.look_at(apparition.to_global(WhiteApparition.CHEST))
			if phase == WhiteApparition.Phase.CONFIRMED and player.survival.san < 0.0:
				_begin_peripheral()
		ReplayStep.PERIPHERAL:
			_verify_peripheral(phase, delta)
		ReplayStep.LOOK_AWAY:
			_verify_look_away(phase, delta)

func _begin_peripheral() -> void:
	var camera: Camera3D = player.camera
	var chest := apparition.to_global(WhiteApparition.CHEST)
	var distance := camera.global_position.distance_to(chest)
	var rect := get_viewport().get_visible_rect()
	var peripheral_ray := camera.project_local_ray_normal(rect.position + rect.size * Vector2(0.73, 0.5))
	camera.rotate_y(atan2(peripheral_ray.x, -peripheral_ray.z))
	_replay_step = ReplayStep.PERIPHERAL
	_peripheral_view = camera.global_transform
	_peripheral_origin = apparition.global_position
	_peripheral_screen_x = camera.unproject_position(chest).x
	_san_at_capture = player.survival.san
	if await _save_capture(CAPTURE_PATH):
		print("WHITE_APPARITION_CAPTURE distance=%.2f san=%.2f" % [distance, _san_at_capture])

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
	var lateral := displacement.slide(inward).length()
	if viewport_shift < 0.10 or approach < 3.8 or lateral < 3.8:
		_replay_error("White apparition relocation was too small (viewport shift %.3f, approach %.2f m, lateral %.2f m)" % [viewport_shift, approach, lateral])
		return
	_replay_step = ReplayStep.CAPTURING_AFTER
	if not await _save_capture(CAPTURE_AFTER_PATH): return
	print("WHITE_APPARITION_PERIPHERAL viewport_shift=%.3f relocation_inward=%.2f relocation_lateral=%.2f san_unchanged=true" % [viewport_shift, approach, lateral])
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
	if DisplayServer.get_name() == "headless": return true
	await RenderingServer.frame_post_draw
	var error := DirAccess.make_dir_recursive_absolute(CAPTURE_DIRECTORY)
	if error == OK:
		error = get_viewport().get_texture().get_image().save_png(path)
	if error != OK:
		_replay_error("White apparition screenshot failed: %s" % error_string(error))
	else:
		print("WHITE_APPARITION_SCREENSHOT path=", path)
	return error == OK

func _replay_error(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
