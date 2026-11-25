extends Node
## Filming controls for the promo world: director panel, cameras, rail, clean view,
## slow motion and the unattended autoplay used with Movie Maker.

const CAMERA := preload("res://tests/playgrounds/promo/promo_camera.gd")
const RAIL := preload("res://tests/playgrounds/promo/promo_rail.gd")
const PANEL := preload("res://tests/playgrounds/promo/promo_panel.gd")
const SHOT_RAIL := "res://tests/playgrounds/promo/rails/%s.json"
const SLOW_SCALES := [1.0, 0.5, 0.25]
const FOLLOW_PRESETS := {
	"chase": Vector3(0.0, 3.4, 12.0),
	"side": Vector3(-10.0, 2.4, 1.0),
	"front": Vector3(2.5, 1.3, -10.0),
	"high": Vector3(0.0, 14.0, 16.0),
}
const NOTICE_SECONDS := 3.0
const FOV_STEP := 2.0

var world: Node3D
var rail: RefCounted = RAIL.new()
var view: Camera3D
var clean := false
var error := ""
var slow_index := 0
var _panel: PanelContainer
var _panel_layer: CanvasLayer
var _indicator: Label
var _notice := ""
var _notice_time := 0.0
var _prior_hud: bool
var _take_path := ""
var _take := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_prior_hud = HUDVisibility.hud_hidden
	var overlay := CanvasLayer.new()
	overlay.layer = 48
	add_child(overlay)
	HUDVisibility.attach(overlay)
	_indicator = Label.new()
	_indicator.position = Vector2(18, 14)
	_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_indicator.add_theme_font_size_override("font_size", 15)
	_indicator.add_theme_color_override("font_shadow_color", Color.BLACK)
	_indicator.add_theme_constant_override("shadow_offset_y", 1)
	overlay.add_child(_indicator)
	_panel_layer = CanvasLayer.new()
	_panel_layer.layer = 100
	_panel_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_panel_layer)
	_panel = PANEL.new()
	_panel.director = self
	_panel.build(_shot_rows())
	_panel.load_requested.connect(load_shot)
	_panel.hide()
	_panel_layer.add_child(_panel)
	clean = HUDVisibility.hud_hidden
	if rail.load_file(SHOT_RAIL % _rail_id()): rail.source = RAIL.Source.SAVED
	if _unattended(): set_clean(true)

func _exit_tree() -> void:
	Engine.time_scale = 1.0
	world.get_tree().paused = false
	if HUDVisibility.hud_hidden != _prior_hud: HUDVisibility.toggle(world.get_tree())
	if is_instance_valid(view) and not view.is_queued_for_deletion(): view.queue_free()

# --- Shots ---

func trigger() -> bool:
	if not world.take_ready:
		notify("The shot is not ready yet")
		return false
	# Tablet shots need the player view: the tablet opens from the player's own camera.
	if world.shot.get("player_camera", false) and is_instance_valid(view): use_player_camera()
	var started: bool = world.trigger_take()
	if not started: notify("Nothing to trigger right now")
	return started

func restart() -> void:
	load_shot(world.shot_id, world.variant)

func load_shot(id: String, variant: int) -> void:
	_close_panel()
	world.reload_take(id, variant)

func show_error(message: String) -> void:
	error = message
	if _panel.visible: _panel.refresh()

func notify(message: String) -> void:
	_notice = message
	_notice_time = NOTICE_SECONDS

# --- Take settings ---

func set_clean(value: bool) -> void:
	clean = value
	if clean != HUDVisibility.hud_hidden: HUDVisibility.toggle(world.get_tree())

func set_invulnerable(value: bool) -> void:
	if not is_instance_valid(world.actor): return
	world.actor.invulnerable = value
	notify("Invulnerable" if value else "Damage on")

func set_slow_index(index: int) -> void:
	slow_index = posmod(index, SLOW_SCALES.size())
	Engine.time_scale = SLOW_SCALES[slow_index]

# --- Cameras ---

func use_player_camera() -> void:
	if not is_instance_valid(world.actor): return
	world.actor.camera_locked = false
	var seat: Node3D = world.actor.seated_in
	var player_view: Camera3D = seat.seat_camera if is_instance_valid(seat) else world.actor.camera
	player_view.make_current()
	if is_instance_valid(view): view.queue_free()
	view = null

func use_free_camera() -> bool:
	if not _detached_view(): return false
	view.free_flight()
	world.actor.camera_locked = true
	return true

func follow_subject() -> bool:
	var target := _subject()
	if target == null or not _detached_view(): return false
	view.follow_from_here(target)
	world.actor.camera_locked = false
	return true

func follow_preset(preset: String, target: Node3D = null) -> bool:
	if target == null: target = _subject()
	if target == null or not _detached_view(): return false
	view.follow_with_offset(target, FOLLOW_PRESETS[preset])
	world.actor.camera_locked = false
	return true

func set_fov(value: float) -> void:
	if is_instance_valid(view): view.target_fov = value

func current_fov() -> float:
	if is_instance_valid(view): return view.target_fov
	var camera := _player_view()
	return camera.fov if camera != null else 70.0

func cycle_camera() -> void:
	if not is_instance_valid(view): use_free_camera()
	elif view.mode == CAMERA.Mode.FREE and follow_subject(): pass
	else: use_player_camera()

# --- Rail ---

func add_keyframe() -> void:
	var camera := world.actor.get_viewport().get_camera_3d() as Camera3D
	if camera == null: return
	if not rail.authored(): rail.clear()
	rail.add(camera.global_transform, camera.fov)
	notify("Rail key %d added" % rail.size())

func remove_keyframe() -> void:
	rail.remove_last()
	notify("Rail keys: %d" % rail.size())

func clear_rail() -> void:
	rail.clear()
	notify("Rail cleared")

func set_rail_duration(seconds: float) -> void:
	rail.set_duration(seconds)

func set_rail_ease(value: bool) -> void:
	rail.ease_ends = value
	if rail.source != RAIL.Source.NONE: rail.source = RAIL.Source.EDITED

func play_rail() -> bool:
	if not rail.playable():
		notify("Add two or more rail keys first")
		return false
	if not _detached_view(): return false
	world.actor.camera_locked = false
	return view.play(rail)

func save_rail() -> void:
	if not rail.playable():
		notify("Add two or more rail keys first")
		return
	var path := SHOT_RAIL % _rail_id()
	var result: Error = rail.save_file(path)
	notify("Rail saved to " + path if result == OK else "Could not save rail: " + error_string(result))

## Stages build a default rail only when nobody saved or edited one for the shot.
func use_generated_rail() -> bool:
	return not rail.authored()

func generated_rail_key(frame: Transform3D) -> void:
	rail.add(frame, _player_view().fov if _player_view() != null else 70.0, RAIL.Source.GENERATED)

func clear_generated_rail() -> void:
	rail.clear(RAIL.Source.GENERATED)

# --- Panel and input ---

func open_panel() -> void:
	_panel.refresh()
	_panel.show()
	world.get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func close_panel_and(action: Callable) -> void:
	_close_panel()
	action.call()

func _close_panel() -> void:
	if not _panel.visible: return
	_panel.hide()
	world.get_tree().paused = false
	var ui: bool = is_instance_valid(world.actor) and world.actor.in_ui_mode
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if ui else Input.MOUSE_MODE_CAPTURED)

func _input(event: InputEvent) -> void:
	if _unattended(): return
	if _panel.visible:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_F2, KEY_ESCAPE]:
			_close_panel()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var handled := true
		match event.keycode:
			KEY_F2: open_panel()
			KEY_F3: trigger()
			KEY_F4: cycle_camera()
			KEY_F8: set_slow_index(slow_index + 1)
			KEY_F12: set_clean(not clean)
			_: handled = false
		if handled:
			get_viewport().set_input_as_handled()
			return
	if not _free_flying(): return
	if event is InputEventMouseMotion:
		view.look(event.relative)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: view.adjust_speed(1.25)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: view.adjust_speed(0.8)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ENTER, KEY_KP_ENTER: add_keyframe()
			KEY_BACKSPACE: remove_keyframe()
	# The free camera owns the keyboard and mouse; the player stays put.
	get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	_notice_time = maxf(0.0, _notice_time - delta / maxf(Engine.time_scale, 0.01))
	if is_instance_valid(view) and is_instance_valid(world.actor) and view.get_viewport() != world.actor.get_viewport():
		# Entering or leaving an interior moves the player into another World3D.
		use_player_camera()
	if _free_flying() and not _panel.visible:
		view.move_input = Vector3(
			float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
			float(Input.is_physical_key_pressed(KEY_SPACE)) - float(Input.is_physical_key_pressed(KEY_SHIFT)),
			float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
		if Input.is_physical_key_pressed(KEY_Z): view.adjust_fov(-FOV_STEP * delta * 20.0)
		if Input.is_physical_key_pressed(KEY_X): view.adjust_fov(FOV_STEP * delta * 20.0)
	elif is_instance_valid(view):
		view.move_input = Vector3.ZERO
	_indicator.text = _indicator_text()
	_indicator.add_theme_color_override("font_color", Color(1.0, 0.5, 0.45) if not error.is_empty() else Color.WHITE)

func _indicator_text() -> String:
	if not error.is_empty(): return "%s  FAILED: %s\nF2 panel to pick another shot" % [world.shot_id, error]
	var state := "Ready" if world.take_ready else "Preparing..."
	var camera := "Player"
	if is_instance_valid(view): camera = ["Free", "Follow", "Rail"][view.mode]
	var line := "%s  %s   Camera: %s" % [world.shot_id, state, camera]
	if slow_index > 0: line += "   Speed %sx" % str(SLOW_SCALES[slow_index])
	if is_instance_valid(world.actor) and world.actor.invulnerable: line += "   Invulnerable"
	line += "   F2 panel   F3 trigger"
	if _notice_time > 0.0: line += "\n" + _notice
	return line

func _free_flying() -> bool:
	return is_instance_valid(view) and view.mode == CAMERA.Mode.FREE

func _detached_view() -> bool:
	if not is_instance_valid(world.actor): return false
	# Staging moves and locks the player until the take is ready.
	if not world.take_ready:
		notify("Wait for Ready")
		return false
	if world.actor.in_ui_mode:
		notify("Close the tablet before using a detached camera")
		return false
	if is_instance_valid(view): return true
	var source := _player_view()
	if source == null: return false
	view = CAMERA.new()
	source.get_viewport().add_child(view)
	view.start_from(source)
	return true

func _player_view() -> Camera3D:
	if not is_instance_valid(world.actor): return null
	var seat: Node3D = world.actor.seated_in
	return seat.seat_camera if is_instance_valid(seat) else world.actor.camera

func _subject() -> Node3D:
	var target: Node3D = world.subject if is_instance_valid(world.subject) else world.rv
	if not is_instance_valid(target) or not WorldEntities.same_world(target, world.actor):
		notify("Nothing to follow in this view")
		return null
	return target

func _rail_id() -> String:
	return world.shot_id if world.variant == 0 else "%s-%d" % [world.shot_id, world.variant]

func _shot_rows() -> Array:
	var rows: Array = []
	for id: String in world.SHOTS:
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(world.SHOT_PATH % id))
		if not data is Dictionary: continue
		rows.append({"id": id, "title": data.get("title", id), "action": data.get("action", ""),
			"steps": data.get("steps", ""), "variants": data.get("variants", []).size()})
	return rows

static func _unattended() -> bool:
	return "--preview" in OS.get_cmdline_user_args()

# --- Unattended takes ---

func preview() -> void:
	set_clean(true)
	_write_take_marker()
	var started := Time.get_ticks_usec()
	var first_frame := Engine.get_process_frames()
	var seconds: float = await world.stage.autoplay(world)
	if seconds < 0.0: return
	await world.get_tree().create_timer(seconds).timeout
	var problem: String = world.stage.autoplay_error(world)
	if not problem.is_empty():
		world._fail(problem)
		return
	print("PROMO PREVIEW: %s %.1f rendered frames/s" % [world.shot_id, (Engine.get_process_frames() - first_frame) * 1000000.0 / maxf(1.0, Time.get_ticks_usec() - started)])
	world.finish_preview.call_deferred()

## Movie Maker records from launch; this marker tells the editor where the take starts.
func _write_take_marker() -> void:
	var directory := ""
	var fps := 0
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--take-dir="): directory = argument.trim_prefix("--take-dir=")
		if argument.begins_with("--capture-fps="): fps = argument.trim_prefix("--capture-fps=").to_int()
	# Movie Maker writes one frame per process frame at its fixed rate.
	var frame := Engine.get_process_frames()
	print("PROMO TAKE START: frame %d" % frame)
	_take = {"shot": world.shot_id, "variant": world.variant, "start_frame": frame,
		"start_seconds": float(frame) / fps if fps > 0 else 0.0, "fps": fps, "markers": []}
	if not directory.is_empty(): _take_path = directory.path_join("take.json")
	_save_take()

## Records a named moment of the take (a narration line, an impact) by Movie Maker frame,
## so the edit can place subtitles and hard cuts without scrubbing.
func mark(label: String) -> void:
	var frame := Engine.get_process_frames()
	print("PROMO MARK: %s frame %d" % [label, frame])
	if _take.is_empty(): return
	var fps: int = _take.fps
	_take.markers.append({"name": label, "frame": frame, "seconds": float(frame) / fps if fps > 0 else 0.0})
	_save_take()

func _save_take() -> void:
	if _take_path.is_empty(): return
	var output := FileAccess.open(_take_path, FileAccess.WRITE)
	if output == null: return
	output.store_string(JSON.stringify(_take, "  ") + "\n")
	output.close()

func exterior_requested() -> bool:
	return "--exterior" in OS.get_cmdline_user_args()
