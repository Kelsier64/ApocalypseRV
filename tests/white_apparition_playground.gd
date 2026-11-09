extends "res://world/main_world.gd"

const CAPTURE_DIRECTORY := "res://.godot/white_apparition"
const CAPTURE_PATH := CAPTURE_DIRECTORY + "/context.png"
const CAPTURE_AFTER_PATH := CAPTURE_DIRECTORY + "/context-after.png"
const WORLD_SEED := 42
const ROAD_START := 330.0

enum ReplayStep { WAITING, CAPTURING, REPOSITIONING, LOOK_AWAY }

@onready var player = $Player
@onready var encounter = $WhiteApparitionEncounter
@onready var status: Label = $PlaygroundHUD/Status

var apparition: WhiteApparition
var _replay := "--replay" in OS.get_cmdline_user_args()
var _elapsed := 0.0
var _replay_started := false
var _replay_step := ReplayStep.WAITING
var _san_at_capture := 0.0
var _reposition_origin := Vector3.ZERO
var _reposition_ticks := 0
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
				_begin_reposition()
		ReplayStep.REPOSITIONING:
			_verify_reposition(phase)
		ReplayStep.LOOK_AWAY:
			_verify_look_away(phase, delta)

func _begin_reposition() -> void:
	_replay_step = ReplayStep.CAPTURING
	if not await _save_capture(CAPTURE_PATH): return
	var camera: Camera3D = player.camera
	var rect := get_viewport().get_visible_rect()
	var ray := camera.project_local_ray_normal(rect.position + rect.size * Vector2(0.74, 0.5))
	_reposition_origin = apparition.global_position
	_san_at_capture = player.survival.san
	camera.rotate_y(atan2(ray.x, -ray.z))
	_replay_step = ReplayStep.REPOSITIONING

func _verify_reposition(phase: WhiteApparition.Phase) -> void:
	_reposition_ticks += 1
	var camera: Camera3D = player.camera
	if phase != WhiteApparition.Phase.CONFIRMED or not apparition.visible or player.survival.san != _san_at_capture:
		_replay_error("The apparition vanished or drained SAN while the replay looked away")
		return
	var destination := apparition.global_position
	if destination == _reposition_origin and _reposition_ticks < 3: return
	var displacement := (destination - _reposition_origin).slide(Vector3.UP).length()
	var observer := camera.get_camera_transform().origin
	var old_bearing := (_reposition_origin - observer).slide(Vector3.UP)
	var new_bearing := (destination - observer).slide(Vector3.UP)
	var bearing_change := rad_to_deg(old_bearing.angle_to(new_bearing))
	if displacement < 10.0 or bearing_change < 59.0:
		_replay_error("White apparition did not jump far enough (%.2f m, %.1f degrees)" % [displacement, bearing_change])
		return
	_replay_step = ReplayStep.CAPTURING
	if not await _save_capture(CAPTURE_AFTER_PATH): return
	print("WHITE_APPARITION_REPOSITION displacement=%.2f bearing_change=%.1f san_unchanged=true" % [displacement, bearing_change])
	_look_away_origin = apparition.global_position
	_look_away_elapsed = apparition._unseen_elapsed
	camera.look_at(apparition.to_global(WhiteApparition.CHEST))
	camera.rotate_y(PI)
	_replay_step = ReplayStep.LOOK_AWAY

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
