extends Node3D
## Runs the production controller and wheels on a flat, marked test course.

const SAN_STEP := 5.0
const VISION_NAMES := ["Bleached", "Cold Split", "Broken Signal"]

@onready var player: CharacterBody3D = $Player
@onready var rv: Chassis = $RV/Chassis
@onready var seat: Item = $RV/Chassis/DriverSeat
@onready var settings_menu: CanvasLayer = $Player/SettingsMenu

var _status: Label
var _editor: PanelContainer
var _value: LineEdit
var _error: Label
var _next_vision_profile := 0

func _ready() -> void:
	get_window().title = "ApocalypseRV - SAN Playground"
	RoadsideKit.part(self, Vector3(320, 0.3, 620), Vector3(0, -0.15, -235), Color("515957"), true)
	RoadsideKit.part(self, Vector3(10, 0.02, 594), Vector3(0, 0, -238), Color("353a3e"))
	for x in [-4.8, 4.8]:
		RoadsideKit.part(self, Vector3(0.12, 0.012, 594), Vector3(x, 0.015, -238), Color("b6bbb5"))
	for z in range(-525, 59, 8):
		RoadsideKit.part(self, Vector3(0.15, 0.012, 3.4), Vector3(0, 0.015, z), Color("b9ac70"))
	rv.unlimited_fuel = true
	rv.unlimited_power = true
	rv.set_handbrake(true)
	rv.set_engine_running(true)
	rv.set_gear(1)
	player.add_item("Energy Bar", false, "res://props/food/energy_bar.tscn")
	player.add_item("Beef Jerky", false, "res://props/food/beef_jerky.tscn")
	_build_ui()

func _process(_delta: float) -> void:
	var mode := "Driving" if seat.current_driver == player else "On foot"
	var effects: PlayerSanEffects = player.san_effects
	var active := PackedStringArray()
	if effects._blink_remaining > 0.0:
		active.append("Long blink %.1fs" % effects._blink_remaining if effects._long_blink else "Blink")
	if effects._vision_remaining > 0.0: active.append(VISION_NAMES[effects._vision_profile])
	if effects._delay_remaining > 0.0: active.append("Input delay %.0f ms" % (1000.0 * effects._input_delay()))
	if effects._misdirection_remaining > 0.0: active.append("Directional drift")
	_status.text = "SAN %.2f%%  |  %s\nActive: %s" % [player.survival.san, mode, ", ".join(active) if not active.is_empty() else "None"]

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_F6:
		if _editor.visible: _close_editor()
		else: _open_editor()
		get_viewport().set_input_as_handled()
	elif _editor.visible and event.is_action_pressed("ui_cancel"):
		_close_editor()
		get_viewport().set_input_as_handled()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or player.is_gameplay_input_blocked() or player.in_ui_mode: return
	if event.keycode in [KEY_UP, KEY_DOWN]:
		var change := SAN_STEP if event.keycode == KEY_UP else -SAN_STEP
		_set_san(player.survival.san + change)
		get_viewport().set_input_as_handled()
		return
	if event.echo: return
	match event.keycode:
		KEY_F5:
			if seat.current_driver == player: seat.exit_seat()
			else: seat.interact_hold(player)
		KEY_F4:
			_queue_effect(KEY_F4, event.shift_pressed)
		KEY_F7, KEY_F8, KEY_F9, KEY_F11:
			_queue_effect(event.keycode)
		KEY_F10:
			get_tree().reload_current_scene.call_deferred()

func _queue_effect(key: Key, cycle_vision := false) -> void:
	# Advance through the normal player gate before moving one timer forward.
	player._advance_san_effects(0.0)
	var effects: PlayerSanEffects = player.san_effects
	if effects._control == PlayerSanEffects.InputMode.NONE: return
	match key:
		KEY_F4:
			if player.survival.san > PlayerSanEffects.MEDIUM_THRESHOLD: return
			effects._vision_remaining = 0.0
			effects._vision_wait = 0.0
		KEY_F7: effects._blink_wait = 0.0
		KEY_F8: effects._delay_wait = 0.0
		KEY_F9: effects._misdirection_wait = 0.0
		KEY_F11: effects._long_blink_wait = 0.0
	player._advance_san_effects(0.0)
	if cycle_vision:
		effects._vision_profile = _next_vision_profile
		_next_vision_profile = (_next_vision_profile + 1) % VISION_NAMES.size()

func _open_editor() -> void:
	if player.is_gameplay_input_blocked() or player.in_ui_mode or player.is_placing_equipment(): return
	player.set_settings_open(true)
	settings_menu.set_process_input(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_error.text = ""
	_value.text = "%.2f" % player.survival.san
	_editor.show()
	_value.grab_focus()
	_value.select_all()

func _close_editor() -> void:
	_editor.hide()
	settings_menu.set_process_input(true)
	player.set_settings_open(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _apply_san() -> void:
	var entered := _value.text.strip_edges()
	if not entered.is_valid_float() or not is_finite(entered.to_float()):
		_error.text = "Enter a number, such as 10 or -5."
		return
	_set_san(entered.to_float())
	_close_editor()

func _set_san(value: float) -> void:
	player.survival.san = minf(value, PlayerSurvival.MAX_SAN)
	player._update_san_bar()
	player._advance_san_effects(0.0)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 59
	add_child(layer)
	var hud := PanelContainer.new()
	var labels := VBoxContainer.new()
	hud.add_child(labels)
	_status = Label.new()
	labels.add_child(_status)
	var controls := Label.new()
	controls.text = "Up / Down SAN +/- 5   F6 Enter SAN\nF5 Seat / Exit   F10 Reset\nF7 Blink   F8 Delay   F9 Misdirection (SAN < 20)\nF4 Random Vision   Shift+F4 Cycle Vision (SAN <= 0)\nF11 Long Blink (SAN <= 0)\nWASD Move / Drive   Space Parking Brake (seated)\n1 / 2 Select Snack   Hold Right Mouse to Eat"
	labels.add_child(controls)
	layer.add_child(hud)
	hud.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_editor = PanelContainer.new()
	_editor.custom_minimum_size.x = 300.0
	center.add_child(_editor)
	var fields := VBoxContainer.new()
	_editor.add_child(fields)
	var title := Label.new()
	title.text = "Set SAN (max 100, negatives allowed)"
	fields.add_child(title)
	_value = LineEdit.new()
	_value.text_submitted.connect(func(_text: String): _apply_san())
	fields.add_child(_value)
	_error = Label.new()
	fields.add_child(_error)
	var buttons := HBoxContainer.new()
	fields.add_child(buttons)
	var apply := Button.new()
	apply.text = "Apply"
	apply.pressed.connect(_apply_san)
	buttons.add_child(apply)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(_close_editor)
	buttons.add_child(cancel)
	_editor.hide()
