extends RefCounted
class_name PlayerSleep

const SAN_PER_HOUR := 10.0
const SKIP_DURATION := 4.0
const HOURS := [1, 3, 6]
const POSE_COLLISION := Transform3D(Basis.IDENTITY, Vector3(0, 1.0, -0.25))
const VIEW_PITCH := -PI / 7.0

var bed: Bed
var clock: WorldClock
var capsule := CapsuleShape3D.new()
var _entry_local := Vector3.ZERO
var _exit_position := Vector3.ZERO
var _exit_yaw := 0.0
var _wake_requested := false
var _skip_end := 0.0
var _skip_span := 0.0
var _skip_rate := 0.0
var _layer: CanvasLayer
var _shade: ColorRect
var _status: Label
var _options: HBoxContainer
var _progress: ProgressBar
var _wake_button: Button

func _init() -> void:
	capsule.radius = 0.25
	capsule.height = 1.78

func active() -> bool:
	return is_instance_valid(_layer)

func begin(player: Node3D, target: Bed) -> String:
	if player.is_gameplay_input_blocked() or player.get_player_mode() != player.PlayerMode.NORMAL or player.locomotion_state != player.LocomotionState.NORMAL:
		return "Bed unavailable"
	if player.is_crawling() or player.is_crouching() or player.inventory.is_holding_large_item() or not player.is_on_floor():
		return "Stand beside the bed to rest"
	var pose: Transform3D = target.get_node("RestPose").global_transform.orthonormalized()
	if not _volume_clear(player, capsule, pose * POSE_COLLISION):
		return "Clear the space above the bed"
	var entry_local := target.to_local(player.global_position)
	if absf(entry_local.x) < 0.64 and absf(entry_local.z) < 1.35:
		return "Stand beside the bed"
	if not player.enter_ui_mode(): return "Bed unavailable"
	bed = target
	bed.occupant = player
	clock = _owning_clock(player)
	_entry_local = entry_local
	_exit_position = player.global_position
	_exit_yaw = player.global_rotation.y
	player.crouching = false
	player.rv_support.clear()
	player.released_carrier_velocity = Vector3.ZERO
	player.velocity = Vector3.ZERO
	player.camera.rotation = Vector3(VIEW_PITCH, 0.0, 0.0)
	player.global_transform = pose
	player.reset_physics_interpolation()
	_build_controls(player)
	player._apply_body_collision()
	return ""

func request_skip(hours: int) -> void:
	if not active() or _skip_end > 0.0 or not _clock_running() or hours not in HOURS: return
	_skip_span = hours * 3600.0
	_skip_end = clock.elapsed_seconds + _skip_span
	_skip_rate = maxf(0.0, _skip_span / SKIP_DURATION - clock.game_seconds_per_real_second())
	_status.text = "Sleeping…"
	_progress.value = 0.0
	_progress.show()
	_options.hide()
	_wake_button.grab_focus()

func request_wake() -> void:
	_wake_requested = true
	_skip_end = 0.0

func handle_input(player: Node3D, event: InputEvent) -> void:
	if not event.is_echo() and (event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel")):
		request_wake()
		player.get_viewport().set_input_as_handled()

func advance(player: Node3D, delta: float) -> float:
	if not active(): return delta
	if not is_instance_valid(bed) or not bed.can_operate():
		if is_instance_valid(bed): _update_exit(player)
		player.exit_ui_mode()
		return delta
	if _wake_requested:
		_wake_requested = false
		if _update_exit(player):
			player.exit_ui_mode()
			return delta
		_status.text = "Clear the aisle to get up"
	player.global_transform = bed.get_node("RestPose").global_transform.orthonormalized()
	var skipping := _skip_end > 0.0 and _clock_running() and PlayerSurvival.simulation_active(player)
	_shade.color.a = move_toward(_shade.color.a, 0.96 if skipping else 0.0, 3.5 * delta)
	if not skipping:
		_skip_end = 0.0
		if _status.text == "Sleeping…": _status.text = "Resting"
		_progress.hide()
		_options.visible = _clock_running()
		return delta
	var remaining := _skip_end - clock.elapsed_seconds
	var seconds := clampf(remaining, 0.0, _skip_rate * delta)
	if seconds > 0.0: clock.advance_game_seconds(seconds, 0.0)
	_progress.value = 1.0 - (remaining - seconds) / _skip_span
	if remaining <= seconds + 0.001:
		_skip_end = 0.0
		_status.text = "Resting"
		_options.show()
		_progress.hide()
	return delta + seconds / clock.game_seconds_per_real_second()

func recover_amount(delta: float) -> float:
	# Fall back to the standard day length when resting in a clockless scene.
	var rate := clock.game_seconds_per_real_second() if _clock_running() else WorldClock.DAY_SECONDS / 1800.0
	return delta * rate * SAN_PER_HOUR / 3600.0

func end(player: Node3D) -> void:
	if not active(): return
	if is_instance_valid(bed) and bed.occupant == player: bed.occupant = null
	bed = null
	clock = null
	_skip_end = 0.0
	_wake_requested = false
	_layer.hide()
	_layer.queue_free()
	_layer = null
	player.global_transform = Transform3D(Basis(Vector3.UP, _exit_yaw), _exit_position)
	player.camera.rotation = Vector3.ZERO
	player._apply_body_collision()
	player.reset_physics_interpolation()

func _update_exit(player: Node3D) -> bool:
	var side := signf(_entry_local.x)
	if side == 0.0: side = 1.0
	var candidates := [_entry_local, Vector3(side * 0.93, 0.0, 0.0), Vector3(side * 0.93, 0.0, -0.65), Vector3(side * 0.93, 0.0, 0.65)]
	for offset: Vector3 in candidates:
		var point := bed.to_global(offset)
		var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.35, point - Vector3.UP * 0.65, player.collision_mask, [player.get_rid(), bed.get_rid()])
		var ground: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(ray)
		if ground.is_empty() or ground.normal.dot(Vector3.UP) < 0.7: continue
		var sole: float = (player.standing_collision_shape as CapsuleShape3D).height * 0.5 - player.standing_collision_transform.origin.y
		var standing: Vector3 = ground.position + Vector3.UP * (sole + 0.025)
		var pose := Transform3D(Basis(Vector3.UP, _exit_yaw), standing)
		if _volume_clear(player, player.standing_collision_shape, pose * player.standing_collision_transform):
			_exit_position = standing
			return true
	return false

func _volume_clear(player: Node3D, shape: Shape3D, pose: Transform3D) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = pose
	query.collision_mask = player.collision_mask
	query.exclude = [player.get_rid()]
	return player.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _clock_running() -> bool:
	return is_instance_valid(clock) and clock.running

func _owning_clock(player: Node3D) -> WorldClock:
	var ancestor := player.get_parent()
	while ancestor != null and not ancestor is Viewport:
		var candidate := ancestor.get_node_or_null("WorldClock") as WorldClock
		if candidate != null: return candidate
		ancestor = ancestor.get_parent()
	return null

func _build_controls(player: Node3D) -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 48
	player.add_child(_layer)
	var screen := Control.new()
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.theme = IndustrialTheme.make(18)
	_layer.add_child(screen)
	UILayout.attach(_layer, screen)
	_shade = ColorRect.new()
	_shade.color = Color(0.016, 0.020, 0.019, 0.0)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(_shade)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bottom := VBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.alignment = BoxContainer.ALIGNMENT_END
	screen.add_child(bottom)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bottom.offset_bottom = -158
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.add_theme_stylebox_override("panel", IndustrialTheme.box(Color(0.06, 0.08, 0.085, 0.96), IndustrialTheme.BORDER, 12))
	bottom.add_child(card)
	var content := VBoxContainer.new()
	content.custom_minimum_size.x = 350.0
	content.add_theme_constant_override("separation", 8)
	card.add_child(content)
	_status = Label.new()
	_status.text = "Resting"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 22)
	content.add_child(_status)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	content.add_child(row)
	_options = HBoxContainer.new()
	_options.add_theme_constant_override("separation", 8)
	row.add_child(_options)
	for hours: int in HOURS:
		var option := Button.new()
		option.text = "Sleep %dh" % hours
		option.custom_minimum_size = Vector2(104, 40)
		option.pressed.connect(request_skip.bind(hours))
		_options.add_child(option)
	_options.visible = _clock_running()
	_progress = ProgressBar.new()
	_progress.max_value = 1.0
	_progress.show_percentage = false
	_progress.custom_minimum_size.y = 6.0
	_progress.hide()
	content.add_child(_progress)
	_wake_button = Button.new()
	_wake_button.text = "Get up"
	_wake_button.custom_minimum_size = Vector2(104, 40)
	_wake_button.pressed.connect(request_wake)
	row.add_child(_wake_button)
	_wake_button.grab_focus()
