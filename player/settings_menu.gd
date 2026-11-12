extends CanvasLayer
## Settings overlay scaled independently of 3D. The simulation keeps running.

const CATEGORIES: Array[StringName] = [&"display", &"input", &"audio", &"help"]
var player
var settings
var controls: Dictionary = {}
var _root: Control
var _shade: ColorRect
var _panel: PanelContainer
var _tabs: TabContainer
var _status: Label
var _save_message: Label
var _retry: Button
var _reset: Button
var _return: Button
var _restart_stage: Button
var _skip_tutorial: Button
var _preset: OptionButton
var _preset_current: Label
var _resolution_label: Label
var _calibrate: Button
var _calibration: VBoxContainer
var _calibration_slider: HSlider
var _calibration_compare: CheckButton
var _calibration_reset: Button
var _calibration_patches: Array[ShaderMaterial] = []
var _modal: Control
var _modal_shade: ColorRect
var _modal_center: CenterContainer
var _modal_text: Label
var _modal_accept: Button
var _modal_cancel: Button
var _modal_kind := ""
var _refreshing := false
var _modal_focus_modes: Dictionary = {}

func _ready() -> void:
	layer = 60
	visible = false
	player = get_parent()
	settings = get_node("/root/GameSettings")
	# The interior viewport matches native window size; only its 3D is scaled.
	# CanvasLayer remains visible independently when the seated Player hides.
	_build()
	settings.setting_changed.connect(_on_setting_changed)
	settings.save_completed.connect(_on_save_completed)
	settings.window_preview_changed.connect(_on_window_preview_changed)
	player.grab_started.connect(close_menu)
	var layout := UILayout.attach(self, _root)
	layout.resized.connect(_resize)
	_resize(_root.size)
	_refresh()

func _exit_tree() -> void:
	if is_instance_valid(settings):
		if _modal_kind == "calibration": settings.clear_shadow_trim_preview()
		settings.cancel_window_preview()
		settings.flush()

func open_menu() -> bool:
	if visible or not player.can_open_settings():
		return false
	player.set_settings_open(true)
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_refresh()
	_update_status()
	_return.grab_focus()
	return true

func close_menu() -> void:
	if not visible:
		return
	settings.cancel_window_preview()
	_hide_modal()
	settings.flush()
	visible = false
	player.set_settings_open(false)
	if player.is_player_dead or player.is_grabbed() or player.in_ui_mode:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel") or event.is_echo():
		return
	if visible:
		if not _modal_kind.is_empty():
			_cancel_modal()
		else:
			close_menu()
		_handle_event()
		return
	# Tablet and storage retain ownership of their own first Escape.
	if player.in_ui_mode:
		return
	if player.is_placing_equipment():
		player.cancel_equipment_placement(true)
		_handle_event()
	elif open_menu():
		_handle_event()

func _unhandled_input(_event: InputEvent) -> void:
	# GUI gets its normal turn before leftovers can reach gameplay handlers.
	if visible:
		_handle_event()

func _handle_event() -> void:
	get_viewport().set_input_as_handled()
	get_tree().root.set_input_as_handled()

func _process(_delta: float) -> void:
	if not visible:
		return
	if player.is_player_dead or player.is_grabbed() or player.in_ui_mode or not player.can_open_settings():
		close_menu()
		return
	_update_status()
	_update_resolution_summary()
	if _modal_kind == "window":
		_modal_text.text = "Keep this display mode?\nReverting in %.0f s. The game keeps running." % ceilf(settings.preview_remaining())

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = IndustrialTheme.make(18)
	add_child(_root)
	_shade = ColorRect.new()
	_shade.color = Color(0.0, 0.0, 0.0, 0.4)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	_root.add_child(margin)
	var center := CenterContainer.new()
	margin.add_child(center)
	_panel = PanelContainer.new()
	center.add_child(_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	_panel.add_child(content)
	var title := _label("Settings", 28)
	title.add_theme_color_override("font_color", IndustrialTheme.AMBER)
	content.add_child(title)
	_status = _label("")
	content.add_child(_status)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.get_tab_bar().focus_mode = Control.FOCUS_ALL
	_tabs.tab_changed.connect(func(_index: int):
		if is_instance_valid(_reset):
			_reset.disabled = _tabs.current_tab == 3)
	content.add_child(_tabs)
	var pages: Array[VBoxContainer] = []
	for tab_name in ["Video", "Controls", "Audio", "Key Bindings"]:
		var scroll := ScrollContainer.new()
		scroll.name = tab_name
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.follow_focus = true
		_tabs.add_child(scroll)
		var page := VBoxContainer.new()
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.add_theme_constant_override("separation", 12)
		scroll.add_child(page)
		pages.append(page)
	_build_display(pages[0])
	_build_input(pages[1])
	_add_slider(pages[2], &"master_volume", "Master Volume", "Controls all game audio. Set to 0% to mute.", 0.0, 1.0, 0.01, "percent")
	_build_help(pages[3])
	var save_row := HBoxContainer.new()
	content.add_child(save_row)
	_save_message = _label("")
	_save_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_row.add_child(_save_message)
	_retry = _button("Retry Save", func(): _on_save_completed(settings.flush()))
	_retry.visible = false
	save_row.add_child(_retry)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	content.add_child(footer)
	_reset = _button("Reset Tab", func(): settings.reset_category(CATEGORIES[_tabs.current_tab]))
	footer.add_child(_reset)
	_restart_stage = _button("Restart Stage", _show_restart_stage)
	_restart_stage.visible = false
	footer.add_child(_restart_stage)
	_skip_tutorial = _button("Skip Tutorial", _show_skip_tutorial)
	_skip_tutorial.visible = false
	footer.add_child(_skip_tutorial)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	_return = _button("Resume [Esc]", close_menu)
	footer.add_child(_return)
	footer.add_child(_button("Quit Game", _show_quit))
	_build_modal()

func _build_display(page: VBoxContainer) -> void:
	_calibrate = _button("Calibrate Display", _show_calibration)
	_calibrate.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	page.add_child(_calibrate)
	_section(page, "Graphics")
	_preset = _option(["Game Default", "Low (Faster)", "Medium (Balanced)", "High (Sharper)", "Custom"])
	_preset.set_item_disabled(4, true)
	_preset.item_selected.connect(func(index: int):
		if not _refreshing and index < 4:
			settings.apply_preset(index))
	var preset_row := _row(page, "Quality Preset", "Adjust resolution, anti-aliasing, shadows and fog together. Game Default scales resolution by location.", _preset)
	_preset_current = preset_row.current
	_preset_current.hide()
	_add_option(page, &"render_mode", "3D Resolution", "Changes scene resolution. Menus, text and the HUD stay sharp.", ["Automatic", "Custom Scale"], [0, 1])
	_resolution_label = controls[&"render_mode"].current
	_resolution_label.show()
	_add_slider(page, &"render_scale", "Resolution Scale", "100% matches window resolution. Lower scales improve performance but reduce sharpness.", 0.5, 1.0, 0.05, "percent")
	_add_option(page, &"aa", "Anti-Aliasing", "Smooths jagged edges. Higher MSAA settings use more GPU power.", ["Off", "FXAA (Faster)", "MSAA 2×", "MSAA 4×"], [0, 1, 2, 3])
	_add_option(page, &"shadow_quality", "Shadow Quality", "Higher quality smooths shadow edges.", ["Game Default", "Low", "Medium", "High"], [0, 1, 2, 3])
	_add_option(page, &"fog_quality", "Fog Quality", "Volumetric fog shows local mist and lighting. Heavy weather fog persists at all settings.", ["Distance Fog (Faster)", "Volumetric Fog (Low)", "Volumetric Fog (Medium)", "Volumetric Fog (High)"], [0, 1, 2, 3])
	_section(page, "Display and Performance")
	_add_option(page, &"window_mode", "Display Mode", "Confirm within 15 seconds to keep the new mode.", ["Windowed", "Fullscreen"], [0, 1])
	_add_toggle(page, &"vsync", "VSync", "Reduces screen tearing and may increase input latency.")
	_add_option(page, &"max_fps", "Frame Rate Limit", "Caps the frame rate to reduce GPU load.", ["Unlimited", "30 FPS", "60 FPS", "120 FPS", "144 FPS"], [0, 30, 60, 120, 144])
	_section(page, "Color")
	_add_toggle(page, &"retro", "Retro Colors", "Gives outdoor areas cooler, muted colors at the same resolution.")
	_add_slider(page, &"saturation", "Saturation", "0% is grayscale. 100% is the default saturation.", 0.0, 1.5, 0.05, "percent")

func _section(page: VBoxContainer, title: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	page.add_child(row)
	var heading := _label(title, 18)
	heading.autowrap_mode = TextServer.AUTOWRAP_OFF
	heading.add_theme_color_override("font_color", IndustrialTheme.AMBER)
	row.add_child(heading)
	var line := HSeparator.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(line)

func _build_input(page: VBoxContainer) -> void:
	_add_slider(page, &"sensitivity", "Mouse Sensitivity", "Applies on foot and while driving. 1× is the default.", 0.25, 2.0, 0.05, "multiple")
	_add_toggle(page, &"invert_y", "Invert Vertical Look", "Reverses vertical mouse look.")
	_add_slider(page, &"walk_fov", "On-Foot FOV", "A wider field of view shows more of your surroundings. Default is 75°.", 60.0, 100.0, 1.0, "degrees")
	_add_slider(page, &"drive_fov", "Driving FOV", "Sets the field of view from the driver seat. Default is 80°.", 60.0, 100.0, 1.0, "degrees")

func _build_help(page: VBoxContainer) -> void:
	page.add_child(_label("These controls use fixed bindings."))
	var rows := [
		["Control Hints", "Press J during gameplay to show or hide control hints. Hints start hidden."],
		["Movement and View", "WASD to move, Left Shift to sprint, mouse to look, Space to jump. Sprinting and jumping cost stamina."],
		["Climbing Ladders", "Face the rungs and press W to climb, S to descend or Space to let go. Put down large items first. Use the side ladder to board and the cabin ladder to reach the roof hatch."],
		["Pickup and Interaction", "Tap E to pick up items, refuel or enter and exit interiors. Hold E for 1 second to sit, open the tablet, or install or remove a wheel."],
		["Equipment Placement", "Hold F for 2 seconds to move equipment. Left-click to place, right-click or Esc to cancel, and R to toggle surface alignment. Use the tablet to modify the RV structure."],
		["Placement Adjustments", "Q/E to rotate 15°. Hold Shift for 5° steps. Arrow keys move 5 cm."],
		["Held Items", "Use 1–6 or the mouse wheel to select and G to drop. Large items lock selection. Right-click to toggle a flashlight or open a portable terminal. Hold right-click to eat or aim a pistol."],
		["Driving", "W for throttle, A/D to steer, S for the foot brake, Space for the parking brake and E to exit. Driving controls are disabled while Settings is open."],
		["Engine, Gears and Lights", "B toggles the engine and L toggles headlights. Z selects reverse, X neutral, C first gear, R shifts up and T shifts down."],
		["Lights and Dashboard", "Use the tablet to control cabin, work and service lights, dashboard brightness and engine camera shake."],
		["Battery and Engine", "Tap E while holding a part to swap it, or hold E to remove it. Stop, shut off the engine and set the parking brake before an engine swap."],
		["Repairs", "Hold H for 3 seconds with an Engine Repair Kit. For equipment and wheel slots, stop, shut off the engine and hold H for 2 seconds. Costs 2 Metal Parts."],
		["Rear Ramp", "Press E at the handle. Stop on suitable ground, set the parking brake and fully open the rear doors. Clear the ramp before stowing it."],
		["Interior Map", "M opens the explored map. Page Up and Page Down switch floors."],
		["Save and Load", "In the main world, F6 saves and F9 loads. To save, go outside on foot, finish interactions and wait for terrain to load. Close Settings first."],
		["Settings and Back", "Esc opens or closes Settings. It first closes the tablet or storage screen, or cancels equipment placement."],
		["Menu Navigation", "Tab and Shift+Tab move focus. Arrow keys adjust values. Enter or Space activates buttons. Esc dismisses confirmation dialogs."]
	]
	for item in rows:
		var box := VBoxContainer.new()
		page.add_child(box)
		var title := _label(item[0])
		title.add_theme_color_override("font_color", IndustrialTheme.AMBER)
		box.add_child(title)
		box.add_child(_label(item[1]))

func _add_option(page: VBoxContainer, key: StringName, title: String, description: String, labels: Array, values: Array) -> void:
	var option := _option(labels)
	var row := _row(page, title, description, option)
	row.current.hide()
	controls[key] = {"control": option, "current": row.current, "reason": row.reason, "values": values, "description": row.description}
	option.item_selected.connect(func(index: int):
		if _refreshing:
			return
		if key == &"window_mode":
			if not settings.begin_window_preview(int(values[index])):
				_refresh()
		else:
			settings.set_setting(key, values[index]))

func _add_toggle(page: VBoxContainer, key: StringName, title: String, description: String) -> void:
	var pair := HBoxContainer.new()
	pair.add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	group.allow_unpress = false
	var buttons: Array[Button] = []
	for value: bool in [false, true]:
		var button := Button.new()
		button.text = "On" if value else "Off"
		button.toggle_mode = true
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 38
		button.toggled.connect(func(pressed: bool):
			if pressed and not _refreshing: settings.set_setting(key, value))
		pair.add_child(button)
		buttons.append(button)
	var row := _row(page, title, description, pair)
	pair.focus_mode = Control.FOCUS_NONE
	row.current.hide()
	controls[key] = {"control": pair, "current": row.current, "reason": row.reason, "buttons": buttons}

func _add_slider(page: VBoxContainer, key: StringName, title: String, description: String, minimum: float, maximum: float, step_value: float, format_kind: String = "decimal") -> void:
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step_value
	slider.custom_minimum_size = Vector2(220, 32)
	var row := _row(page, title, description, slider)
	row.current.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.current.add_theme_font_size_override("font_size", 20)
	row.current.add_theme_color_override("font_color", IndustrialTheme.AMBER)
	controls[key] = {"control": slider, "current": row.current, "reason": row.reason, "format": format_kind, "panel": row.panel}
	slider.value_changed.connect(func(value: float):
		if not _refreshing:
			settings.set_setting(key, value))

func _row(page: VBoxContainer, title: String, description: String, control: Control) -> Dictionary:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", IndustrialTheme.box(Color("20272a")))
	page.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	panel.add_child(row)
	var explanation := VBoxContainer.new()
	explanation.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(explanation)
	explanation.add_child(_label(title, 20))
	var detail := _label(description, 16)
	detail.add_theme_color_override("font_color", Color("b6b8a9"))
	explanation.add_child(detail)
	var value_box := VBoxContainer.new()
	value_box.custom_minimum_size.x = 280
	row.add_child(value_box)
	value_box.add_child(control)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.focus_mode = Control.FOCUS_ALL
	var current := _label("", 16)
	value_box.add_child(current)
	var reason := _label("", 15)
	reason.add_theme_color_override("font_color", IndustrialTheme.AMBER)
	reason.visible = false
	value_box.add_child(reason)
	return {"current": current, "reason": reason, "description": detail, "panel": panel}

func _refresh() -> void:
	_refreshing = true
	_preset.select(settings.preset_index())
	_preset_current.text = "Current: " + _preset.get_item_text(_preset.selected)
	for key in controls:
		var entry: Dictionary = controls[key]
		var control: Control = entry.control
		var value = settings.get_setting(key)
		entry.reason.visible = false
		if entry.has("buttons"):
			for index in range(2):
				var button: Button = entry.buttons[index]
				var selected: bool = bool(value) == bool(index)
				button.set_pressed_no_signal(selected)
				button.text = ("✓ " if selected else "") + ("On" if index == 1 else "Off")
		elif control is OptionButton:
			var index: int = entry.values.find(value)
			control.select(maxi(0, index))
			entry.current.text = "Current: " + control.get_item_text(control.selected)
		elif control is HSlider:
			control.set_value_no_signal(float(value))
			entry.current.text = _format_value(float(value), entry.format)
	var scale: HSlider = controls[&"render_scale"].control
	scale.editable = int(settings.get_setting(&"render_mode")) == 1
	controls[&"render_scale"].panel.visible = scale.editable
	for button: Button in controls[&"vsync"].buttons:
		button.disabled = not settings.supports_vsync_toggle()
	_set_reason(&"vsync", "The current display driver cannot toggle VSync." if not settings.supports_vsync_toggle() else "")
	var fog: OptionButton = controls[&"fog_quality"].control
	var volume_supported: bool = settings.supports_volumetric_fog()
	for index in range(1, 4):
		fog.set_item_disabled(index, not volume_supported)
	if not volume_supported:
		fog.select(0)
		controls[&"fog_quality"].current.show()
		controls[&"fog_quality"].current.text = "Active: Distance Fog (Compatibility)"
	else:
		controls[&"fog_quality"].current.hide()
	_set_reason(&"fog_quality", "The current renderer does not support volumetric fog." if not volume_supported else "")
	_update_resolution_summary()
	_refreshing = false
	_on_save_completed(settings.last_save_error)

func _set_reason(key: StringName, message: String) -> void:
	controls[key].reason.text = message
	controls[key].reason.visible = not message.is_empty()

func _format_value(value: float, kind: String) -> String:
	match kind:
		"percent": return "%.0f%%" % (value * 100.0)
		"degrees": return "%.0f°" % value
		"multiple": return "%.2f×" % value
	return "%.2f" % value

func _update_resolution_summary() -> void:
	if not is_instance_valid(_resolution_label): return
	# The actor's viewport follows it indoors. Read the applied scale, rather
	# than the saved manual percentage, which is unused in automatic mode.
	var viewport: Viewport = player.get_viewport()
	var dimensions := Vector2i(viewport.get_visible_rect().size)
	var ratio := viewport.scaling_3d_scale
	var rendered := Vector2i(Vector2(dimensions) * ratio)
	_resolution_label.text = "3D: %d × %d (%.0f%%)" % [rendered.x, rendered.y, ratio * 100.0]
	var automatic: bool = int(settings.get_setting(&"render_mode")) == 0
	var explanation := "Automatic uses a lower resolution outdoors and full resolution indoors." if automatic else "At 100%, the scene matches window resolution. Lower scales reduce sharpness."
	controls[&"render_mode"].description.text = "%s\nWindow: %d × %d. Menus and text stay sharp." % [explanation, dimensions.x, dimensions.y]

func _on_setting_changed(_key: StringName, _value: Variant) -> void:
	_refresh()

func _on_save_completed(error: Error) -> void:
	_retry.visible = error != OK
	_save_message.text = "Could not save settings (%s). Changes are active. Try saving again." % error_string(error) if error != OK else "Settings save automatically. Use F6 to save game progress."

func _update_status() -> void:
	var tutorial := _tutorial()
	_restart_stage.visible = tutorial != null and tutorial.can_restart()
	_restart_stage.disabled = not _restart_stage.visible
	_skip_tutorial.visible = tutorial != null and tutorial.has_method("can_skip") and tutorial.can_skip()
	_skip_tutorial.disabled = not _skip_tutorial.visible
	_status.text = "Game running  ·  HP %.0f / %.0f" % [player.current_player_health, player.max_player_health]
	if is_instance_valid(player.seated_in):
		var chassis = player.seated_in.get_connected_rv()
		if is_instance_valid(chassis):
			_status.text += "  ·  Speed %.0f km/h" % (chassis.linear_velocity.length() * 3.6)

func _resize(dimensions: Vector2) -> void:
	_panel.custom_minimum_size = Vector2(minf(1040, maxf(0, dimensions.x - 40)), minf(650, maxf(0, dimensions.y - 40)))

func _build_modal() -> void:
	_modal = Control.new()
	_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.visible = false
	_root.add_child(_modal)
	_modal_shade = ColorRect.new()
	_modal_shade.color = Color(0, 0, 0, 0.45)
	_modal_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.add_child(_modal_shade)
	_modal_center = CenterContainer.new()
	_modal_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.add_child(_modal_center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	_modal_center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)
	_modal_text = _label("")
	box.add_child(_modal_text)
	_build_calibration(box)
	var buttons := HBoxContainer.new()
	box.add_child(buttons)
	_modal_accept = _button("Confirm", _accept_modal)
	buttons.add_child(_modal_accept)
	_modal_cancel = _button("Cancel", _cancel_modal)
	buttons.add_child(_modal_cancel)

func _build_calibration(box: VBoxContainer) -> void:
	_calibration = VBoxContainer.new()
	_calibration.add_theme_constant_override("separation", 8)
	box.add_child(_calibration)
	var chart := HBoxContainer.new()
	chart.add_theme_constant_override("separation", 0)
	_calibration.add_child(chart)
	for code: int in [0, 2, 8, 16, 32, 64]:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chart.add_child(column)
		var patch := ColorRect.new()
		patch.custom_minimum_size.y = 54
		patch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(patch)
		var material := ShaderMaterial.new()
		material.shader = preload("res://player/display_calibration_patch.gdshader")
		material.set_shader_parameter("patch_level", float(code) / 255.0)
		patch.material = material
		_calibration_patches.append(material)
		var marker := _label("Black" if code == 0 else ("▲" if code in [8, 16] else ""), 15)
		marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(marker)
	var trim_row := HBoxContainer.new()
	_calibration.add_child(trim_row)
	trim_row.add_child(_label("Shadow Detail"))
	_calibration_slider = HSlider.new()
	var bounds: Vector2 = settings.RANGES["shadow_trim"]
	_calibration_slider.min_value = bounds.x
	_calibration_slider.max_value = bounds.y
	_calibration_slider.step = 0.05
	_calibration_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trim_row.add_child(_calibration_slider)
	_calibration_slider.value_changed.connect(_refresh_calibration_preview.unbind(1))
	var actions := HBoxContainer.new()
	_calibration.add_child(actions)
	_calibration_compare = CheckButton.new()
	_calibration_compare.text = "Preview Default"
	_calibration_compare.toggled.connect(_refresh_calibration_preview.unbind(1))
	actions.add_child(_calibration_compare)
	_calibration_reset = _button("Reset", _reset_calibration)
	actions.add_child(_calibration_reset)

func _show_calibration() -> void:
	_modal_kind = "calibration"
	_modal_text.text = "Adjust Shadow Detail until both marked patches are distinct from black. The darkest patch may blend in."
	_modal_accept.text = "Apply"
	_modal_cancel.text = "Cancel"
	_calibration_compare.set_pressed_no_signal(false)
	_calibration_slider.set_value_no_signal(settings.get_setting(&"shadow_trim"))
	_refresh_calibration_preview()
	_show_modal()

func _refresh_calibration_preview() -> void:
	var trim := 0.0 if _calibration_compare.button_pressed else _calibration_slider.value
	settings.preview_shadow_trim(trim)
	for patch in _calibration_patches: patch.set_shader_parameter("shadow_trim", trim)

func _reset_calibration() -> void:
	_calibration_compare.set_pressed_no_signal(false)
	_calibration_slider.set_value_no_signal(0.0)
	_refresh_calibration_preview()

func _show_quit() -> void:
	_modal_kind = "quit"
	_modal_text.text = "Quit the game?\nProgress since your last F6 save will be lost.\nSettings are saved automatically."
	_modal_accept.text = "Quit Game"
	_modal_cancel.text = "Cancel"
	_show_modal()

func _tutorial() -> Node:
	var anchor: Node = player
	while anchor != null:
		if anchor.has_meta("entity_domain"): return anchor.get_node_or_null("StartRun/Tutorial")
		anchor = anchor.get_parent()
	return null

func _show_restart_stage() -> void:
	var tutorial := _tutorial()
	if tutorial == null or not tutorial.can_restart(): return
	_modal_kind = "restart_stage"
	_modal_text.text = "Restart this stage?\nThe world returns to the stage entrance.\nYour manual checkpoint remains unchanged."
	_modal_accept.text = "Restart Stage"
	_modal_cancel.text = "Cancel"
	_show_modal()

func _show_skip_tutorial() -> void:
	var tutorial := _tutorial()
	if tutorial == null or not tutorial.has_method("can_skip") or not tutorial.can_skip(): return
	_modal_kind = "skip_tutorial"
	_modal_text.text = "Skip the remaining training?\nThe shelter route will open and the field manual will unlock.\nYour training record will be marked Skipped."
	_modal_accept.text = "Skip Tutorial"
	_modal_cancel.text = "Cancel"
	_show_modal()

func _on_window_preview_changed(active: bool) -> void:
	_refresh()
	if active and visible:
		if _modal_kind == "calibration": _hide_modal()
		_modal_kind = "window"
		_modal_accept.text = "Keep Display Mode"
		_modal_cancel.text = "Revert"
		_show_modal()
	elif _modal_kind == "window":
		_hide_modal()

func _accept_modal() -> void:
	if _modal_kind == "window":
		settings.confirm_window_preview()
	elif _modal_kind == "calibration":
		settings.set_setting(&"shadow_trim", _calibration_slider.value)
		settings.flush()
	elif _modal_kind == "quit":
		settings.cancel_window_preview()
		settings.flush()
		get_tree().quit()
	elif _modal_kind == "restart_stage":
		var tutorial := _tutorial()
		if tutorial != null and tutorial.can_restart():
			var world: Node = tutorial.get_parent().get_parent()
			var snapshot: Dictionary = tutorial.entry_snapshot.duplicate(true)
			close_menu()
			get_node("/root/Checkpoint").call_deferred("load_snapshot", world, snapshot)
			return
	elif _modal_kind == "skip_tutorial":
		var tutorial := _tutorial()
		if tutorial != null and tutorial.has_method("can_skip") and tutorial.can_skip():
			close_menu()
			tutorial.skip_tutorial.call_deferred()
			return
	_hide_modal()

func _cancel_modal() -> void:
	if _modal_kind == "window":
		settings.cancel_window_preview()
	_hide_modal()

func _hide_modal() -> void:
	var was_calibration := _modal_kind == "calibration"
	if was_calibration: settings.clear_shadow_trim_preview()
	_modal_kind = ""
	_modal.hide()
	_panel.show()
	_shade.show()
	for control in _modal_focus_modes:
		if is_instance_valid(control):
			control.focus_mode = _modal_focus_modes[control]
	_modal_focus_modes.clear()
	if visible:
		if was_calibration: _calibrate.grab_focus()
		else: _return.grab_focus()

func _show_modal() -> void:
	# Confine keyboard navigation to the active modal.
	if _modal_focus_modes.is_empty():
		_suspend_background_focus(_panel)
	var is_calibration := _modal_kind == "calibration"
	_calibration.visible = is_calibration
	_panel.visible = not is_calibration
	_shade.visible = not is_calibration
	_modal_shade.visible = not is_calibration
	_modal_center.anchor_top = 0.4 if is_calibration else 0.0
	var focus_order: Array[Control] = [_modal_accept, _modal_cancel]
	if is_calibration:
		focus_order = [_calibration_slider, _calibration_compare, _calibration_reset, _modal_accept, _modal_cancel]
	for index in focus_order.size():
		var control := focus_order[index]
		var previous := control.get_path_to(focus_order[posmod(index - 1, focus_order.size())])
		var next := control.get_path_to(focus_order[(index + 1) % focus_order.size()])
		control.focus_previous = previous
		control.focus_neighbor_top = previous
		control.focus_next = next
		control.focus_neighbor_bottom = next
		if control != _calibration_slider:
			control.focus_neighbor_left = previous
			control.focus_neighbor_right = next
	_modal.show()
	if is_calibration: _calibration_slider.grab_focus()
	else: _modal_cancel.grab_focus()

func _suspend_background_focus(node: Node) -> void:
	if node is Control and node.focus_mode != Control.FOCUS_NONE:
		_modal_focus_modes[node] = node.focus_mode
		node.focus_mode = Control.FOCUS_NONE
	for child in node.get_children():
		_suspend_background_focus(child)

func _option(labels: Array) -> OptionButton:
	var option := OptionButton.new()
	for label in labels:
		option.add_item(str(label))
	return option

func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	return button

func _label(text: String, font_size: int = 18) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	return label
