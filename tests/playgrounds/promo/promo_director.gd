extends Node

const SHOT_RAIL := "res://tests/playgrounds/promo/rails/%s.json"
const LOCAL_RAIL := "res://.godot/promo/%s-rail.json"
const GrabRules := preload("res://core/raker_grab_rules.gd")
const FREE_SPEED := 5.0
const SEGMENT_SECONDS := 2.0

var world: Node3D
var clean := false
var view: Camera3D
var rail: Array[Transform3D] = []
var rail_time := -1.0
var free_speed := FREE_SPEED
var _follow: Node3D
var _follow_offset: Vector3
var _label: Label
var _prior_hud: bool
var _prior_scale: float

func _ready() -> void:
	_prior_hud = HUDVisibility.hud_hidden
	_prior_scale = Engine.time_scale
	var overlay := CanvasLayer.new()
	overlay.layer = 48
	add_child(overlay)
	HUDVisibility.attach(overlay)
	_label = Label.new()
	_label.position = Vector2(18, 18)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	overlay.add_child(_label)
	clean = HUDVisibility.hud_hidden
	_load_rail()
	_status("Preparing " + world.shot_id)
	if "--preview" in OS.get_cmdline_user_args(): set_clean(true)

func _exit_tree() -> void:
	Engine.time_scale = _prior_scale
	if HUDVisibility.hud_hidden != _prior_hud: HUDVisibility.toggle(get_tree())
	if is_instance_valid(view) and not view.is_queued_for_deletion(): view.queue_free()

func _status(message: String) -> void:
	var action: String = world.shot.action
	_label.text = "%s   %s\nF7 Restart   Shift+F7 Next shot   F8 Free camera   F10 %s   F11 Rail   F12 HUD" % [world.shot_id, message, action]

func _input(event: InputEvent) -> void:
	if not world.take_ready or world.actor.settings_open: return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F7:
				var index: int = world.SHOTS.find(world.shot_id)
				var id: String = world.SHOTS[(index + 1) % world.SHOTS.size()] if event.shift_pressed else world.shot_id
				world.reload_take.call_deferred(id)
			KEY_F8:
				if event.ctrl_pressed: Engine.time_scale = 0.35 if Engine.time_scale == _prior_scale else _prior_scale
				elif event.shift_pressed: follow_subject()
				elif is_instance_valid(view): use_player_camera()
				else: use_free_camera()
			KEY_F10:
				if event.ctrl_pressed:
					world.actor.invulnerable = not world.actor.invulnerable
					_status("Invulnerability on" if world.actor.invulnerable else "Invulnerability off")
				else:
					if world.shot_id in ["R2", "R3"] and is_instance_valid(view): use_player_camera()
					world.trigger_take()
			KEY_F11:
				if event.ctrl_pressed and event.shift_pressed:
					rail_time = -1.0
					rail.clear()
					_status("Rail cleared")
				elif event.ctrl_pressed: _save_rail()
				elif event.shift_pressed: add_keyframe()
				else: play_rail()
			KEY_F12: set_clean(not clean)
			_:
				if not is_instance_valid(view): return
		get_viewport().set_input_as_handled()
		return
	if not is_instance_valid(view): return
	if event is InputEventMouseMotion and rail_time < 0.0 and not is_instance_valid(_follow):
		view.rotation.y -= event.relative.x * 0.0025
		view.rotation.x = clampf(view.rotation.x - event.relative.y * 0.0025, -1.54, 1.54)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: free_speed = minf(80.0, free_speed * 1.25)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: free_speed = maxf(0.25, free_speed / 1.25)
	get_viewport().set_input_as_handled()

func set_clean(value: bool) -> void:
	clean = value
	if clean != HUDVisibility.hud_hidden: HUDVisibility.toggle(get_tree())

func use_free_camera() -> bool:
	if world.actor.in_ui_mode: return false
	if is_instance_valid(view):
		rail_time = -1.0
		_follow = null
		return true
	var player_view := world.actor.get_viewport().get_camera_3d() as Camera3D
	if player_view == null: return false
	view = Camera3D.new()
	view.set_meta(&"promo_camera", true)
	view.fov = player_view.fov
	view.near = player_view.near
	view.far = player_view.far
	player_view.get_viewport().add_child(view)
	view.global_transform = player_view.global_transform
	world.actor.camera_locked = true
	view.make_current()
	_status("Free camera")
	return true

func use_player_camera() -> void:
	rail_time = -1.0
	_follow = null
	world.actor.camera_locked = false
	var seat: Node3D = world.actor.seated_in
	var player_view: Camera3D = seat.seat_camera if is_instance_valid(seat) else world.actor.camera
	player_view.make_current()
	if is_instance_valid(view): view.queue_free()
	view = null
	_status("Player camera")

func follow_subject() -> void:
	var target: Node3D = world.subject if is_instance_valid(world.subject) else world.rv
	follow(target)

func follow(target: Node3D) -> void:
	if not WorldEntities.same_world(target, world.actor) or not use_free_camera(): return
	_follow = target
	_follow_offset = target.to_local(view.global_position)
	_status("Following subject" if target == world.subject else "Following RV")

func add_keyframe() -> void:
	var camera := world.actor.get_viewport().get_camera_3d() as Camera3D
	if camera == null: return
	rail.append(camera.global_transform)
	_status("Rail keyframes: %d" % rail.size())

func play_rail() -> bool:
	if rail.size() < 2:
		_status("Add two or more rail keyframes")
		return false
	if not use_free_camera(): return false
	rail_time = 0.0
	view.global_transform = rail.front()
	_status("Playing rail")
	return true

func _process(delta: float) -> void:
	if not world.take_ready: return
	if not clean and _label.text.begins_with(world.shot_id + "   Preparing"):
		_status("Ready")
	if not is_instance_valid(view) or view.get_viewport() != world.actor.get_viewport():
		if world.actor.camera_locked: use_player_camera()
		return
	if rail_time >= 0.0:
		rail_time += delta / SEGMENT_SECONDS
		var segment := mini(floori(rail_time), rail.size() - 2)
		var weight := clampf(rail_time - segment, 0.0, 1.0)
		view.global_transform = rail[segment].interpolate_with(rail[segment + 1], smoothstep(0.0, 1.0, weight))
		if rail_time >= rail.size() - 1: rail_time = -1.0
		return
	if is_instance_valid(_follow):
		view.global_position = _follow.to_global(_follow_offset)
		var look := _follow.global_position + Vector3.UP
		if not view.global_position.is_equal_approx(look): view.look_at(look)
		return
	var movement := Vector3(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_SPACE)) - float(Input.is_physical_key_pressed(KEY_SHIFT)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	view.position += view.basis * movement.normalized() * free_speed * delta / maxf(0.01, Engine.time_scale)

func _rail_id() -> String:
	return world.shot_id if world.variant == 0 else "%s-%d" % [world.shot_id, world.variant]

func _load_rail() -> void:
	var path := LOCAL_RAIL % _rail_id()
	if not FileAccess.file_exists(path): path = SHOT_RAIL % _rail_id()
	if not FileAccess.file_exists(path): return
	var rows: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not rows is Array: return
	for row in rows:
		if not row is Array or row.size() != 7 or not row.all(func(value): return (value is float or value is int) and is_finite(value)): continue
		var rotation := Quaternion(row[3], row[4], row[5], row[6])
		if rotation.length_squared() <= 0.001: continue
		rail.append(Transform3D(Basis(rotation.normalized()), Vector3(row[0], row[1], row[2])))

func _save_rail() -> void:
	if rail.size() < 2:
		_status("Add two or more rail keyframes")
		return
	DirAccess.make_dir_recursive_absolute("res://.godot/promo")
	var path := LOCAL_RAIL % _rail_id()
	var output := FileAccess.open(path, FileAccess.WRITE)
	if output == null:
		_status("Could not save rail")
		return
	var rows: Array = []
	for frame in rail:
		var rotation := frame.basis.orthonormalized().get_rotation_quaternion()
		rows.append([frame.origin.x, frame.origin.y, frame.origin.z, rotation.x, rotation.y, rotation.z, rotation.w])
	output.store_string(JSON.stringify(rows, "  "))
	output.close()
	_status("Rail saved")

func preview() -> void:
	set_clean(true)
	var started := Time.get_ticks_usec()
	var first_frame := Engine.get_process_frames()
	var seconds := 4.0
	if world.shot_id == "R2":
		if not world.trigger_take():
			world._fail("Preview could not open the tablet")
			return
		await get_tree().create_timer(0.75).timeout
		var tablet: Node = world.rv.get_node("TabletScreen")
		tablet.ui_instance._craft()
		if world.station.jobs.is_empty():
			world._fail("Preview craft failed: " + world.station.last_error)
			return
		tablet._close_ui()
		seconds = RecipeCatalog.find(world.shot.recipes[0]).duration + 1.5
	elif world.shot_id == "B2":
		world.actor.invulnerable = true
		if not world.trigger_take():
			world._fail("Preview could not trigger the apparition")
			return
		world.actor._toggle_flashlight()
		use_free_camera()
		view.global_position += view.global_basis.x * 0.55
		var pursued := false
		for frame in 90:
			await get_tree().physics_frame
			if world.apparition.phase == BlackApparition.Phase.FRENZIED:
				pursued = true
				break
		if not pursued:
			world._fail("Flashlight did not trigger pursuit in the bunker preview")
			return
		seconds = 2.5
	elif world.shot_id in ["B5", "W1", "W2", "W3"]:
		var started_rail: bool = world.trigger_take() if world.shot_id == "W3" else play_rail()
		if not started_rail:
			world._fail("Preview could not start the rail")
			return
		seconds = maxf(12.0 if world.shot_id == "W3" else 0.0, float(rail.size() - 1) * SEGMENT_SECONDS + 0.5)
	elif world.shot_id == "O3":
		if not world.trigger_take():
			world._fail("White apparition had no valid emergence point")
			return
		await get_tree().create_timer(0.6).timeout
		world._aim_at(world.subject.global_position + WhiteApparition.CHEST)
		seconds = 4.5
	elif world.shot_id == "R3":
		if not world.trigger_take():
			world._fail("Preview could not open Structure")
			return
		var tablet: Node = world.rv.get_node("TabletScreen")
		var slots: RVStructureSlots = world.rv.get_node("StructureSlots")
		var construction: RVStructureConstruction = slots.construction
		await get_tree().create_timer(0.8).timeout
		if not await _preview_construction(tablet, construction, "roof_0", "repair"): return
		if not await _preview_construction(tablet, construction, "right_2", "rebuild"): return
		tablet._close_ui()
		world._aim_at(world.rv.to_global(Vector3(1.9, 1.7, 4.0)))
	elif world.shot_id == "R1":
		for index in world.staged.size():
			var input = world.staged[index]
			if not world.trigger_take():
				world._fail("Could not feed the scrapper")
				return
			for frame in 900:
				await get_tree().physics_frame
				if not is_instance_valid(input): break
			if is_instance_valid(input):
				world._fail("Scrapper did not finish " + input.item_name)
				return
			await get_tree().create_timer(0.45).timeout
	elif world.shot_id in ["B1", "B3", "B4"]:
		if world.shot_id != "B1": world.actor._toggle_flashlight()
		if not world.trigger_take():
			world._fail("Could not start the bunker action")
			return
		if world.shot_id == "B3":
			for frame in 240:
				await get_tree().physics_frame
				if world.actor.is_grabbed(): break
			if not world.actor.is_grabbed():
				world._fail("Raker did not grab the player")
				return
			var grab: Node = world.actor.grab_control
			var wounded := GrabRules.minimum_wounded_presses(grab.required)
			while world.actor.is_grabbed() and grab.presses < wounded:
				if not world.actor.submit_struggle(): break
				await get_tree().create_timer(0.055).timeout
		seconds = 8.0
	elif world.shot_id in ["O2", "D1", "D2", "D3", "O4"]:
		if not world.trigger_take():
			world._fail("Could not start the driving action")
			return
		world.stage.drive_replay = true
		if "--exterior" in OS.get_cmdline_user_args() and use_free_camera():
			world.actor.replay_driving = true
			view.global_position = world.rv.to_global(Vector3(-10, 5, 12))
			follow(world.rv)
			view.reset_physics_interpolation()
		if world.shot_id == "D3":
			await get_tree().create_timer(2.8).timeout
			world.rv.set_gear(2)
			await get_tree().create_timer(2.0).timeout
			world.rv.set_gear(3)
		seconds = {"D1": 13.0, "O4": 19.0}.get(world.shot_id, 11.0)
	elif world.shot_id == "D4":
		world.trigger_take()
		await get_tree().create_timer(7.0).timeout
		if world.rv.rollover_state() == Chassis.Rollover.UPRIGHT or not world.stage.mark_jack_operator(world) or not world.trigger_take():
			world._fail("RV did not settle at a usable recovery-jack mark")
			return
		seconds = 9.0
	else:
		if not world.trigger_take():
			world._fail("Could not start the take")
			return
		seconds = 45.0 if world.shot_id == "O5" else 7.0
	await get_tree().create_timer(seconds).timeout
	if world.shot_id == "R2" and not world.station.jobs.is_empty():
		world._fail("Preview did not finish: " + world.station.last_error)
		return
	if world.shot_id == "D4" and world.rv.rollover_state() != Chassis.Rollover.UPRIGHT:
		world._fail("Recovery jack did not right the RV")
		return
	if world.shot_id == "R1" and (not world.stage.recycler.props_being_crushed.is_empty() or world.staged.any(func(item): return is_instance_valid(item))):
		world._fail("Scrapper did not finish all three items")
		return
	print("PROMO PREVIEW: %s %.1f rendered frames/s" % [world.shot_id, (Engine.get_process_frames() - first_frame) * 1000000.0 / maxf(1.0, Time.get_ticks_usec() - started)])
	world.finish_preview.call_deferred()

func _preview_construction(tablet: Node, construction: RVStructureConstruction, slot: String, operation: String) -> bool:
	tablet.ui_instance.select_slot(slot)
	tablet.ui_instance._begin_structure(operation)
	if not construction.is_building():
		world._fail(construction.last_message)
		return false
	await get_tree().create_timer(float(construction.job.duration) + 0.2).timeout
	if construction.last_message != "Construction complete":
		world._fail(construction.last_message)
		return false
	return true
