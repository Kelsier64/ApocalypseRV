extends RayCast3D
## The player owns a key gesture. Looking away cancels it; holding never repeats.
@onready var player = get_parent().get_parent()
var repair := RepairOperation.new()
var repair_label: Label
var prompt_label: Label
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
var _input_edges: Array[Dictionary] = []

func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
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
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.position = Vector2(-380, -160)
	panel.size = Vector2(760, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	prompt_label = _label(box, 22)
	repair_label = _label(box, 20)
	feedback_label = _label(box, 22)
	feedback_label.modulate = Color(1.0, 0.85, 0.4)

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
	var panel: Control = prompt_label.get_parent().get_parent()
	if player.get_player_mode() != player.PlayerMode.NORMAL:
		repair.step(player, null, false, delta)
		_input_edges.clear()
		_e_target = null
		_f_target = null
		_e_time = 0.0
		_f_time = 0.0
		_e_was_pressed = e_pressed
		_f_was_pressed = f_pressed
		aim_marker.visible = player.get_player_mode() == player.PlayerMode.PLACING
		panel.visible = aim_marker.visible
		prompt_label.text = player.placement.message if panel.visible else ""
		repair_label.text = ""
		feedback_label.text = ""
		return
	aim_marker.show()
	target_position = Vector3(0, 0, -3.0)
	var obj: Node = get_collider() if is_colliding() else null
	if is_instance_valid(obj) and obj.is_queued_for_deletion(): obj = null
	feedback_time = maxf(0.0, feedback_time - delta)
	if feedback_time == 0.0: feedback_label.text = ""
	prompt_label.text = get_prompt(obj)
	repair.step(player, obj, Input.is_physical_key_pressed(KEY_H), delta)
	repair_label.text = repair.message
	var edges := _input_edges.duplicate()
	_input_edges.clear()
	for edge in edges:
		if player.get_player_mode() != player.PlayerMode.NORMAL: break
		var target: Node = edge.target.get_ref() if edge.target else null
		_step_buttons(target, edge.pressed if edge.key == "e" else _e_was_pressed, edge.pressed if edge.key == "f" else _f_was_pressed, 0.0)
	if player.get_player_mode() == player.PlayerMode.NORMAL:
		_step_buttons(obj, e_pressed, f_pressed, delta)
	panel.visible = player.get_player_mode() == player.PlayerMode.NORMAL and (not prompt_label.text.is_empty() or not feedback_label.text.is_empty() or not repair_label.text.is_empty())

func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or player.get_player_mode() != player.PlayerMode.NORMAL: return
	var key := "e" if event.is_action("interact") else ("f" if event.is_action("place_equipment") else "")
	if key.is_empty(): return
	force_raycast_update()
	var target: Node = get_collider() if is_colliding() else null
	_input_edges.append({"key": key, "pressed": event.is_pressed(), "target": weakref(target) if is_instance_valid(target) else null})

func _step_buttons(obj: Node, e_pressed: bool, f_pressed: bool, delta: float) -> void:
	if obj != _e_target: _e_target = null
	if obj != _f_target: _f_target = null
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
			if _wheel_install(_e_target):
				var installed: bool = _e_target.install_wheel_from_player(player)
				show_feedback("輪胎已安裝" if installed else "無法安裝：請熄火停穩，並確認有空輪槽")
			else:
				_invoke(_e_target, "interact_hold")
		else:
			prompt_label.text += "\n長按 E：%d%%" % mini(100, int(_e_time * 100.0))
	if not e_pressed and _e_was_pressed:
		if is_instance_valid(_e_target) and not _e_done and _uses_hold(_e_target):
			_invoke(_e_target, "interact")
		_e_target = null
		_e_time = 0.0
	if f_pressed and not _f_was_pressed and not e_pressed:
		_f_target = obj if obj is Equipment else null
		_f_time = 0.0
		_f_done = false
	if e_pressed: _f_target = null
	if f_pressed and is_instance_valid(_f_target) and not _f_done:
		_f_time += delta
		if _f_time >= 2.0:
			_f_done = true
			_f_target.start_placement(player)
		else:
			prompt_label.text += "\n長按 F 搬移：%d%%" % mini(100, int(_f_time * 50.0))
	if not f_pressed:
		_f_target = null
		_f_time = 0.0
	_e_was_pressed = e_pressed
	_f_was_pressed = f_pressed

func _wheel_install(obj: Node) -> bool:
	return obj.has_method("install_wheel") and player.get_active_item_name() == ItemNames.WHEEL

func _uses_hold(obj: Node) -> bool:
	return obj.has_method("interact_hold") or _wheel_install(obj)

func _invoke(obj: Node, method: String) -> void:
	if not is_instance_valid(obj) or obj.is_queued_for_deletion() or not obj.has_method(method): return
	var result: Variant = obj.call(method, player)
	if result is String and not result.is_empty(): show_feedback(result)

func show_feedback(message: String) -> void:
	feedback_label.text = message
	feedback_time = 3.0

func get_prompt(obj: Node) -> String:
	if not is_instance_valid(obj): return ""
	var text := ""
	if obj.has_method("get_interaction_prompt"):
		text = obj.get_interaction_prompt(player)
	elif obj is Equipment:
		text = obj.equipment_name
		if obj.has_method("interact_hold"): text += "\n長按 E 1 秒使用"
		elif obj.has_method("interact"): text += "\nE 使用"
		if obj.get_connected_rv() == null: text += "\n未安裝至 RV，功能尚未接通"
	elif obj.has_method("interact_hold"):
		text = "長按 E 1 秒使用"
	elif obj.has_method("interact"):
		text = "E 使用"
	if _wheel_install(obj): text += "\n長按 E 1 秒安裝手持輪胎"
	if obj is Equipment: text += "\n長按 F 2 秒搬移"
	if obj.has_method("needs_repair") and obj.needs_repair() and not obj.has_method("repair_requirement"):
		text += "\n長按 H 維修：2 秒／2 Metal Parts（需熄火停穩）"
	return text
