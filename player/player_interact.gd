extends RayCast3D
## The player owns a key gesture. Looking away cancels it; holding never repeats.
@onready var player = get_parent().get_parent()
var repair := RepairOperation.new()
var repair_label: Label
var action_progress: ProgressBar
var feedback_panel: PanelContainer
var feedback_label: Label
var feedback_time := 0.0
var aim_marker: CenterContainer
var _e_was_pressed := false
var _f_was_pressed := false
var _e_target: Node
var _f_target: Node
var _e_time := 0.0
var _f_time := 0.0
var _e_done := false
var _f_done := false
var _repair_release_required := false
var _input_edges: Array[Dictionary] = []

func _ready() -> void:
	# The camera can sit outside the controller capsule and look back through
	# its shoulder. RayCast excludes its Camera3D parent, not the player body.
	add_exception(player)
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	HUDVisibility.attach(layer)
	aim_marker = CenterContainer.new()
	aim_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	aim_marker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(aim_marker)
	var dot := Label.new()
	dot.text = "+"
	dot.add_theme_font_size_override("font_size", 20)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	aim_marker.add_child(dot)
	var panel := PanelContainer.new()
	feedback_panel = panel
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.position = Vector2(-380, -160)
	panel.size = Vector2(760, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	action_progress = ProgressBar.new()
	action_progress.custom_minimum_size = Vector2(180, 6)
	action_progress.show_percentage = false
	action_progress.hide()
	box.add_child(action_progress)
	repair_label = _label(box, 20)
	feedback_label = _label(box, 22)
	feedback_label.modulate = Color(1.0, 0.85, 0.4)
	panel.hide()

func _label(parent: Node, font_size: int) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 760
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _physics_process(delta: float) -> void:
	var e_pressed := Input.is_action_pressed("interact")
	var f_pressed := Input.is_action_pressed("place_equipment")
	var repair_pressed := Input.is_physical_key_pressed(KEY_H)
	if not repair_pressed: _repair_release_required = false
	feedback_time = maxf(0.0, feedback_time - delta)
	if feedback_time == 0.0: feedback_label.text = ""
	if player.is_gameplay_input_blocked() or player.get_player_mode() != player.PlayerMode.NORMAL:
		cancel_input_gestures()
		aim_marker.visible = not player.is_gameplay_input_blocked() and player.get_player_mode() == player.PlayerMode.PLACING
		action_progress.hide()
		repair_label.text = ""
		feedback_panel.visible = aim_marker.visible and not feedback_label.text.is_empty()
		return
	aim_marker.show()
	target_position = Vector3(0, 0, -3.0)
	var obj: Node = get_collider() if is_colliding() else null
	if is_instance_valid(obj) and obj.is_queued_for_deletion(): obj = null
	action_progress.hide()
	repair.step(player, null if obj is RVStructurePanel else obj, repair_pressed and not _repair_release_required, delta)
	repair_label.text = repair.message
	var edges := _input_edges.duplicate()
	_input_edges.clear()
	for edge in edges:
		if player.get_player_mode() != player.PlayerMode.NORMAL: break
		var target: Node = edge.target.get_ref() if edge.target else null
		_step_buttons(target, edge.pressed if edge.key == "e" else _e_was_pressed, edge.pressed if edge.key == "f" else _f_was_pressed, 0.0)
	if player.get_player_mode() == player.PlayerMode.NORMAL:
		_step_buttons(obj, e_pressed, f_pressed, delta)
	repair_label.visible = not repair_label.text.is_empty()
	feedback_label.visible = not feedback_label.text.is_empty()
	feedback_panel.visible = player.get_player_mode() == player.PlayerMode.NORMAL and (action_progress.visible or feedback_label.visible or repair_label.visible)

func _unhandled_input(event: InputEvent) -> void:
	if player.is_gameplay_input_blocked():
		cancel_input_gestures()
		return
	if event.is_echo() or player.get_player_mode() != player.PlayerMode.NORMAL: return
	var key := "e" if event.is_action("interact") else ("f" if event.is_action("place_equipment") else "")
	if key.is_empty(): return
	force_raycast_update()
	var target: Node = get_collider() if is_colliding() else null
	_input_edges.append({"key": key, "pressed": event.is_pressed(), "target": weakref(target) if is_instance_valid(target) else null})

func cancel_input_gestures() -> void:
	action_progress.hide()
	repair.step(player, null, false, 0.0)
	# A repair press made during any input block must be released too, including
	# one begun after closing settings while another held key keeps the latch.
	_repair_release_required = Input.is_physical_key_pressed(KEY_H)
	_input_edges.clear()
	_e_target = null
	_f_target = null
	_e_time = 0.0
	_f_time = 0.0
	_e_done = true
	_f_done = true
	_e_was_pressed = Input.is_action_pressed("interact")
	_f_was_pressed = Input.is_action_pressed("place_equipment")

func _step_buttons(obj: Node, e_pressed: bool, f_pressed: bool, delta: float) -> void:
	if is_instance_valid(obj) and not _can_interact(obj):
		if (e_pressed and not _e_was_pressed) or (f_pressed and not _f_was_pressed):
			show_feedback("Cannot use with your current body or carried load")
		obj = null
	if obj != _e_target: _e_target = null
	if is_instance_valid(_f_target) and obj != _f_target:
		_f_target = null
		_f_done = true
	if e_pressed and not _e_was_pressed:
		_e_target = obj
		_e_time = 0.0
		_e_done = false
		if is_instance_valid(obj) and not _uses_hold(obj):
			_e_done = true
			_invoke(obj, "interact")
	if e_pressed and is_instance_valid(_e_target) and not _e_done:
		_e_time += delta
		if _e_time >= 1.0:
			_e_done = true
			if _held_delivery(_e_target):
				_invoke(_e_target, "accept_held_item")
			elif _wheel_install(_e_target):
				var installed: bool = _e_target.install_wheel_from_player(player)
				show_feedback("Wheel installed" if installed else "Cannot install wheel: vehicle moving, engine running or no empty slot")
			else:
				_invoke(_e_target, "interact_hold")
		else:
			_show_progress(_e_time)
	if not e_pressed and _e_was_pressed:
		if is_instance_valid(_e_target) and not _e_done and _uses_hold(_e_target):
			_invoke(_e_target, "interact")
		_e_target = null
		_e_time = 0.0
	if f_pressed and not _f_was_pressed and not e_pressed:
		_f_target = obj if obj is Item and obj.is_fixed else null
		_f_time = 0.0
		_f_done = false
	if e_pressed:
		_f_target = null
		_f_done = true
	if f_pressed and not _f_done:
		_f_time += delta
		if _f_time >= 2.0 and is_instance_valid(_f_target):
			_f_done = true
			show_feedback(_f_target.pickup(player))
		elif is_instance_valid(_f_target):
			_show_progress(_f_time / 2.0)
	if not f_pressed:
		if _f_was_pressed and not _f_done and _f_time < 2.0 and not player.inventory.active_item().is_empty():
			player.enter_equipment_placement()
		_f_target = null
		_f_time = 0.0
	_e_was_pressed = e_pressed
	_f_was_pressed = f_pressed

func _wheel_install(obj: Node) -> bool:
	return obj.has_method("install_wheel") and player.get_active_item_name() == ItemNames.WHEEL

func _uses_hold(obj: Node) -> bool:
	if obj is Item and not obj.is_fixed: return false
	return obj.has_method("interact_hold") or _wheel_install(obj) or _held_delivery(obj)

func _held_delivery(obj: Node) -> bool:
	return obj.has_method("accept_held_item") and obj is Item and obj.is_fixed and player.inventory.is_holding_large_item()

func _invoke(obj: Node, method: String) -> void:
	if not is_instance_valid(obj) or obj.is_queued_for_deletion(): return
	if not _can_interact(obj): return
	if obj is PrintedPlayerBody:
		show_feedback(obj.interact(player))
		return
	if obj is Item and not obj.is_fixed:
		show_feedback(obj.pickup(player))
		return
	if not obj.has_method(method): return
	if obj is Item and method == "interact_hold" and not obj.can_operate():
		show_feedback("Device unavailable")
		return
	var result: Variant = obj.call(method, player)
	if result is String and not result.is_empty(): show_feedback(result)

func show_feedback(message: String) -> void:
	feedback_label.text = message
	feedback_label.visible = not message.is_empty()
	feedback_time = 3.0

func _show_progress(fraction: float) -> void:
	action_progress.value = clampf(fraction * 100.0, 0.0, 100.0)
	action_progress.show()

func _can_interact(obj: Node) -> bool:
	if obj is PrintedPlayerBody: return true
	# Existing inventory may still be stored with no arms; withdrawal is
	# gated separately by add_prop_item / the RV storage transaction.
	if obj is Item and not obj.is_fixed: return player.can_use_hands(2 if obj.is_large else 1)
	if obj.get_script() == preload("res://equipment/item_box.gd"): return true
	if obj.get_script() == preload("res://equipment/driver_seat.gd"): return player.can_drive()
	# A fixed control needs one hand; lifting its large body still preflights
	# both hands in Item.pickup, independently of whether E can use it.
	return player.can_use_hands()

func cancel_body_operations() -> void:
	if not player.can_use_hands(): repair.cancel()
	_input_edges = _input_edges.filter(func(edge: Dictionary):
		var target: Node = edge.target.get_ref() if edge.target else null
		return is_instance_valid(target) and _can_interact(target))
	if is_instance_valid(_e_target) and not _can_interact(_e_target):
		_e_target = null
		_e_time = 0.0
		_e_done = true
	var needed_hands := 2 if (is_instance_valid(_f_target) and _f_target is Item and _f_target.is_large) or player.inventory.active_item().get("is_large", false) else 1
	if not player.can_use_hands(needed_hands):
		_f_target = null
		_f_time = 0.0
		_f_done = true
