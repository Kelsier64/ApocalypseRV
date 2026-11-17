extends PanelContainer
## Director panel: pick a shot, run it, choose cameras and edit the camera rail.
## Shown on a top layer while the game is paused; never part of the footage.

signal load_requested(id: String, variant: int)

var director: Node
var _shots: ItemList
var _variant: SpinBox
var _title: Label
var _steps: Label
var _error: Label
var _invulnerable: CheckButton
var _clean: CheckButton
var _slow: OptionButton
var _fov: HSlider
var _rail_info: Label
var _duration: SpinBox
var _ease: CheckBox
var _syncing := false

func build(shot_rows: Array) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 40
	offset_top = 40
	offset_right = -40
	offset_bottom = -40
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.08, 0.94)
	style.set_content_margin_all(16)
	add_theme_stylebox_override("panel", style)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	add_child(columns)

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 380
	columns.add_child(left)
	left.add_child(_heading("Shots"))
	_shots = ItemList.new()
	_shots.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for row: Dictionary in shot_rows:
		_shots.add_item("%s   %s" % [row.id, row.title])
		_shots.set_item_metadata(_shots.item_count - 1, row)
	_shots.item_selected.connect(_on_shot_selected)
	_shots.item_activated.connect(func(_index): _load_selected())
	left.add_child(_shots)
	var load_row := HBoxContainer.new()
	left.add_child(load_row)
	load_row.add_child(_text("Variant"))
	_variant = SpinBox.new()
	_variant.min_value = 0
	load_row.add_child(_variant)
	load_row.add_child(_button("Load shot", _load_selected))

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	columns.add_child(right)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	right.add_child(_title)
	_steps = Label.new()
	_steps.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_steps)
	_error = Label.new()
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
	right.add_child(_error)

	right.add_child(_heading("Take"))
	var take := HFlowContainer.new()
	right.add_child(take)
	take.add_child(_button("Trigger  [F3]", func(): director.close_panel_and(director.trigger)))
	take.add_child(_button("Restart shot", func(): director.restart()))
	_clean = CheckButton.new()
	_clean.text = "Clean view  [F12]"
	_clean.toggled.connect(_relay.bind("set_clean"))
	take.add_child(_clean)
	_invulnerable = CheckButton.new()
	_invulnerable.text = "Invulnerable"
	_invulnerable.toggled.connect(_relay.bind("set_invulnerable"))
	take.add_child(_invulnerable)
	take.add_child(_text("Speed  [F8]"))
	_slow = OptionButton.new()
	for scale in director.SLOW_SCALES: _slow.add_item("%sx" % str(scale))
	_slow.item_selected.connect(_relay.bind("set_slow_index"))
	take.add_child(_slow)

	right.add_child(_heading("Camera  [F4 cycles Player / Free / Follow]"))
	var camera := HFlowContainer.new()
	right.add_child(camera)
	camera.add_child(_button("Player view", func(): director.close_panel_and(director.use_player_camera)))
	camera.add_child(_button("Free camera", func(): director.close_panel_and(director.use_free_camera)))
	camera.add_child(_button("Follow: keep framing", func(): director.close_panel_and(director.follow_subject)))
	for preset in director.FOLLOW_PRESETS:
		camera.add_child(_button("Follow: " + preset, func(): director.close_panel_and(director.follow_preset.bind(preset))))
	var lens := HBoxContainer.new()
	right.add_child(lens)
	lens.add_child(_text("Field of view"))
	_fov = HSlider.new()
	_fov.min_value = 20
	_fov.max_value = 100
	_fov.step = 1
	_fov.custom_minimum_size.x = 260
	_fov.value_changed.connect(_relay.bind("set_fov"))
	lens.add_child(_fov)

	right.add_child(_heading("Rail  [free camera: Enter adds a key, Backspace removes the last]"))
	var rail := HFlowContainer.new()
	right.add_child(rail)
	rail.add_child(_button("Add key here", func(): director.add_keyframe()))
	rail.add_child(_button("Remove last", func(): director.remove_keyframe()))
	rail.add_child(_button("Clear", func(): director.clear_rail()))
	rail.add_child(_button("Play rail", func(): director.close_panel_and(director.play_rail)))
	rail.add_child(_button("Save rail", func(): director.save_rail()))
	var timing := HBoxContainer.new()
	right.add_child(timing)
	timing.add_child(_text("Duration (s)"))
	_duration = SpinBox.new()
	_duration.min_value = 1
	_duration.max_value = 120
	_duration.step = 0.5
	_duration.value_changed.connect(_relay.bind("set_rail_duration"))
	timing.add_child(_duration)
	_ease = CheckBox.new()
	_ease.text = "Ease in and out"
	_ease.toggled.connect(_relay.bind("set_rail_ease"))
	timing.add_child(_ease)
	_rail_info = Label.new()
	right.add_child(_rail_info)

	var keys := Label.new()
	keys.text = "F2 panel   F3 trigger   F4 camera   F8 speed   F12 clean view\nFree camera: mouse look, WASD move, Space/Shift up/down, wheel speed, Z/X zoom"
	keys.add_theme_color_override("font_color", Color(0.7, 0.74, 0.78))
	keys.size_flags_vertical = Control.SIZE_SHRINK_END
	right.add_child(keys)

func refresh() -> void:
	_syncing = true
	var world: Node = director.world
	var current := -1
	for index in _shots.item_count:
		if _shots.get_item_metadata(index).id == world.shot_id: current = index
	if current >= 0 and not _shots.is_selected(current):
		_shots.select(current)
		_shots.ensure_current_is_visible()
	_show_shot(world.shot_id, world.variant)
	_error.text = director.error
	_clean.button_pressed = director.clean
	_invulnerable.button_pressed = is_instance_valid(world.actor) and world.actor.invulnerable
	_slow.selected = director.slow_index
	_fov.value = director.current_fov()
	var rail: RefCounted = director.rail
	_duration.value = rail.duration
	_ease.button_pressed = rail.ease_ends
	_rail_info.text = "%d keys   %s" % [rail.size(), ["no rail", "generated for this shot", "saved", "edited, not saved"][rail.source]]
	_syncing = false

## Forwards a control change to the director unless refresh() is writing it.
func _relay(value: Variant, method: String) -> void:
	if not _syncing: director.call(method, value)

func _on_shot_selected(index: int) -> void:
	var row: Dictionary = _shots.get_item_metadata(index)
	_show_shot(row.id, 0 if row.id != director.world.shot_id else director.world.variant)

func _show_shot(id: String, variant: int) -> void:
	var row := _row(id)
	if row.is_empty(): return
	_variant.max_value = row.variants
	_variant.value = variant
	_variant.editable = row.variants > 0
	var loaded: bool = id == director.world.shot_id
	_title.text = "%s  %s%s" % [id, row.title, "" if loaded else "   (not loaded)"]
	_steps.text = "F3: %s\n\n%s" % [row.action, row.steps]

func _load_selected() -> void:
	var selected := _shots.get_selected_items()
	if selected.is_empty(): return
	var row: Dictionary = _shots.get_item_metadata(selected[0])
	load_requested.emit(row.id, int(_variant.value))

func _row(id: String) -> Dictionary:
	for index in _shots.item_count:
		var row: Dictionary = _shots.get_item_metadata(index)
		if row.id == id: return row
	return {}

func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.95, 0.78, 0.35))
	return label

func _text(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label

func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	return button
