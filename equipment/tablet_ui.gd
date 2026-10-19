extends CanvasLayer

signal close_requested
signal section_presented(section: String)
enum Mode { TUI, SHELL }
const PAGES := ["overview", "energy", "equipment", "crafting", "structure"]
const PAGE_NAMES := ["Overview", "Energy", "Equipment", "Crafting", "Structure"]
const FRAME = preload("res://equipment/terminal_panel.gd")
const HISTORY_LIMIT := 100
const OUTPUT_LIMIT := 500

var mode := Mode.TUI
var current_page := "overview"
var connected_rv: Node3D
var controls: Dictionary = {}
var slot_controls: Dictionary = {}
var device_selectors: Dictionary = {}
var selected_recipe := "gasoline"
var selected_slot := "front"
var selected_device := ""
var terminal_lines := PackedStringArray()
var command_history := PackedStringArray()
var commands := RVTerminalCommands.new()
var _pages: Dictionary = {}
var _texts: Dictionary = {}
var _grids: Array[GridContainer] = []
var _nav: Dictionary = {}
var _devices: Array = []
var _device_ids := PackedStringArray()
var _station_ids := PackedStringArray()
var _station_id := ""
var _type_slot := ""
var _refresh_time := 0.0
var _refreshing := false
var _history_index := 0
var _history_draft := ""
var _message := ""
var _last_construction_message := ""
var _presentation_revision := 0
var _device_list: VBoxContainer
var _construction_row: HBoxContainer
@onready var _screen: Control = $Screen
@onready var _tui: VBoxContainer = $Screen/Margin/TUI
@onready var _shell: VBoxContainer = $Screen/Margin/Shell
@onready var shell_input: LineEdit = $Screen/Margin/Shell/Prompt/Input
@onready var shell_output: RichTextLabel = $Screen/Margin/Shell/Output

func _ready() -> void:
	_screen.theme = RVTerminalTheme.make()
	shell_input.text_submitted.connect(submit_command)
	shell_input.text_changed.connect(_sanitize_input)
	_build_tui()
	_screen.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	var layout := UILayout.attach(self, _screen)
	layout.resized.connect(_resize_console.unbind(1))
	_resize_console()
	select_page("overview", false)

func _label(parent: Node, id: String, text: String = "", color: Color = RVTerminalTheme.INK) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	if not id.is_empty(): _texts[id] = label
	return label

func _button(parent: Node, id: String, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = "[ " + text + " ]"
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 40
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	button.focus_entered.connect(_button_focus.bind(button, true))
	button.focus_exited.connect(_button_focus.bind(button, false))
	parent.add_child(button)
	controls[id] = button
	_button_focus(button, false)
	return button

func _toggle(parent: Node, id: String, text: String, action: Callable) -> CheckButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	_label(row, "", text)
	var button := CheckButton.new()
	button.custom_minimum_size = Vector2(115, 40)
	button.toggled.connect(action)
	button.focus_entered.connect(_button_focus.bind(button, true))
	button.focus_exited.connect(_button_focus.bind(button, false))
	row.add_child(button)
	controls[id] = button
	_button_focus(button, false)
	return button

func _button_focus(button: BaseButton, focused: bool) -> void:
	# Hover/pressed draw states can override native focus colors. Keep focus
	# contrast consistent during mouse/keyboard activation, including ON/OFF.
	for color in ["font_color", "font_focus_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(color, RVTerminalTheme.BACKGROUND if focused else RVTerminalTheme.INK)
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var fill := RVTerminalTheme.AMBER if focused else (Color("26333c") if state in ["hover", "hover_pressed"] else Color.TRANSPARENT)
		button.add_theme_stylebox_override(state, RVTerminalTheme.style(fill))

func _number(parent: Node, id: String, text: String, maximum: float, step: float, action: Callable) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	_label(row, "", text)
	var field := SpinBox.new()
	field.custom_minimum_size = Vector2(145, 40)
	field.max_value = maximum
	field.step = step
	field.value_changed.connect(action)
	field.get_line_edit().context_menu_enabled = false
	row.add_child(field)
	controls[id] = field

func _panel(parent: Node, heading: String) -> VBoxContainer:
	var frame := PanelContainer.new()
	frame.set_script(FRAME)
	frame.heading = heading
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(frame)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	frame.add_child(content)
	return content

func _grid(parent: Node) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 12)
	parent.add_child(grid)
	_grids.append(grid)
	return grid

func _page(id: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_tui.add_child(scroll)
	_pages[id] = scroll
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	scroll.add_child(body)
	return body

func _build_tui() -> void:
	var header := HBoxContainer.new()
	_tui.add_child(header)
	_label(header, "", "rvctl / VEHICLE CONTROL", RVTerminalTheme.CYAN)
	_label(header, "telemetry", "", RVTerminalTheme.DIM)
	var navigation := HFlowContainer.new()
	_tui.add_child(navigation)
	for index in PAGES.size():
		var id: String = PAGES[index]
		var button := _button(navigation, "page:" + id, "F%d %s" % [index + 1, PAGE_NAMES[index]], func(): select_page(id))
		_nav[id] = button
	_build_overview(_page("overview"))
	_build_energy(_page("energy"))
	_build_equipment(_page("equipment"))
	_build_crafting(_page("crafting"))
	_build_structure(_page("structure"))
	_construction_row = HBoxContainer.new()
	_tui.add_child(_construction_row)
	_label(_construction_row, "construction")
	_button(_construction_row, "structure:cancel", "Cancel construction", _cancel_construction)
	_label(_tui, "message", "", RVTerminalTheme.AMBER)
	var footer := _label(_tui, "", "F1-F5 Pages   Tab / Shift+Tab Focus   Arrows Select / Adjust   Enter Activate   Esc Close tablet", RVTerminalTheme.DIM)
	footer.add_theme_font_size_override("font_size", 16)

func _build_overview(body: Node) -> void:
	_label(_panel(body, "Vehicle status"), "overview:status")
	var grid := _grid(body)
	var actions := _panel(grid, "Quick controls")
	_button(actions, "engine", "Start engine", _toggle_engine)
	_label(actions, "engine:reason", "", RVTerminalTheme.DIM)
	_toggle(actions, "headlights", "Headlights", func(value: bool): _set_light("headlights", value))
	_label(actions, "headlights:state", "", RVTerminalTheme.DIM)
	var attention := _panel(grid, "Attention")
	_label(attention, "warnings")
	_button(attention, "inspect:equipment", "Inspect equipment", func(): select_page("equipment"))
	_button(attention, "inspect:structure", "Inspect damaged parts", _inspect_structure)
	_label(_panel(body, "Body condition"), "overview:structure")

func _build_energy(body: Node) -> void:
	var grid := _grid(body)
	_label(_panel(grid, "Power & fuel"), "energy:flow")
	var settings := _panel(grid, "Automatic charging")
	_toggle(settings, "charging_enabled", "RV charging", func(value: bool):
		if _can_write():
			connected_rv.energy.charging_enabled = value
			if not value: connected_rv.energy.charging = false
			_refresh())
	_number(settings, "charging_threshold", "Start below (%)", 100, 5, func(value: float):
		if _can_write(): connected_rv.energy.recharge_below = value / 100.0)
	_number(settings, "charging_reserve", "Fuel reserve", 100, 1, func(value: float):
		if _can_write(): connected_rv.energy.fuel_reserve = value)
	_label(settings, "", "Charging needs a running engine and an installed battery. The reserve stops charging; an idling engine still burns fuel.", RVTerminalTheme.DIM)
	_label(settings, "charging:state")

func _build_equipment(body: Node) -> void:
	var lights := _panel(body, "Interior lighting")
	_toggle(lights, "cabin", "Cabin light master", func(value: bool): _set_light("cabin", value))
	_toggle(lights, "service", "Engine bay service lamp", func(value: bool): _set_light("service", value))
	_label(lights, "interior:state", "", RVTerminalTheme.DIM)
	var grid := _grid(body)
	_device_list = _panel(grid, "Installed equipment")
	var detail := _panel(grid, "Selected equipment")
	_label(detail, "device:detail")
	_label(detail, "", "Hold H while facing damaged hardware to repair it. Stop the engine first. Engine repairs require an Engine Repair Kit.", RVTerminalTheme.DIM)
	_label(_panel(body, "Tires"), "tires")

func _build_crafting(body: Node) -> void:
	_label(_panel(body, "Materials"), "materials")
	var grid := _grid(body)
	var recipes := _panel(grid, "Recipes")
	for recipe in RecipeCatalog.all():
		var id: String = recipe.recipe_id
		var button := _button(recipes, "recipe:" + id, RVTerminalPresenter.recipe_name(recipe), func(): select_recipe(id))
		button.focus_entered.connect(func(): select_recipe(id))
	var detail := _panel(grid, "Recipe & workstation")
	var selector := OptionButton.new()
	selector.custom_minimum_size.y = 40
	detail.add_child(selector)
	controls["craft:station"] = selector
	selector.item_selected.connect(func(index: int):
		_station_id = str(selector.get_item_metadata(index))
		_refresh())
	_wire_popup(selector)
	_label(detail, "recipe:detail")
	_label(detail, "craft:reason", "", RVTerminalTheme.DIM)
	_button(detail, "craft:add", "Add to queue", _craft)
	_label(detail, "queue")
	_button(detail, "craft:cancel", "Cancel queue / refund materials", _cancel_crafting)

func _build_structure(body: Node) -> void:
	_label(body, "structure:conditions", "", RVTerminalTheme.DIM)
	var grid := _grid(body)
	var diagram := _panel(grid, "Body slots / front at top")
	_centered_slot_button(diagram, "front")
	var cells := GridContainer.new()
	cells.columns = 3
	cells.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	diagram.add_child(cells)
	for index in 3:
		for side in ["left", "roof", "right"]:
			_slot_button(cells, "%s_%d" % [side, index])
	_centered_slot_button(diagram, "rear")
	_label(diagram, "", "LEFT          ROOF          RIGHT\nHP = durability   X = destroyed", RVTerminalTheme.DIM)
	var detail := _panel(grid, "Selected part")
	_label(detail, "structure:detail")
	var selector := OptionButton.new()
	selector.custom_minimum_size.y = 40
	detail.add_child(selector)
	controls["structure:type"] = selector
	selector.item_selected.connect(func(_index: int): _refresh())
	_wire_popup(selector)
	for operation in ["repair", "rebuild", "convert"]:
		_button(detail, "structure:" + operation, operation.capitalize(), func(): _begin_structure(operation))
		_label(detail, "structure:reason:" + operation, "", RVTerminalTheme.DIM)

func _slot_button(parent: Node, id: String) -> void:
	var button := _button(parent, "slot:" + id, id, func(): select_slot(id))
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.focus_entered.connect(func(): select_slot(id, false))
	slot_controls[id] = button

func _centered_slot_button(parent: Node, id: String) -> void:
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(center)
	_slot_button(center, id)
	slot_controls[id].custom_minimum_size.x = 180

func _wire_popup(selector: OptionButton) -> void:
	selector.focus_entered.connect(_button_focus.bind(selector, true))
	selector.focus_exited.connect(_button_focus.bind(selector, false))
	_button_focus(selector, false)
	# PopupMenu is a separate Window/Viewport, so it forwards the global chords.
	selector.get_popup().window_input.connect(_input)

func _resize_console() -> void:
	for grid in _grids: grid.columns = 1 if _screen.size.x < 1050 else 2

func on_open() -> void:
	connected_rv = get_parent().get_connected_rv()
	_message = ""
	_type_slot = ""
	enter_tui()
	select_page("overview")

func is_management_active() -> bool:
	return visible and mode == Mode.TUI

func enter_shell() -> void:
	_presentation_revision += 1
	dismiss_popups()
	if mode == Mode.TUI and is_instance_valid(connected_rv):
		var construction := _construction()
		if construction: construction.cancel_for(get_parent())
	mode = Mode.SHELL
	_tui.hide()
	_shell.show()
	_history_index = command_history.size()
	_history_draft = ""
	shell_input.grab_focus()

func enter_tui() -> void:
	mode = Mode.TUI
	_shell.hide()
	_tui.show()
	_refresh()
	select_page(current_page)

func select_page(id: String, focus: bool = true) -> void:
	if not _pages.has(id): return
	_presentation_revision += 1
	dismiss_popups()
	current_page = id
	for page in _pages:
		_pages[page].visible = page == id
		var index: int = PAGES.find(page)
		_nav[page].text = "[ F%d %s%s ]" % [index + 1, PAGE_NAMES[index], " *" if page == id else ""]
	_refresh()
	if focus and mode == Mode.TUI:
		var target: String = {"overview": "engine", "energy": "charging_enabled",
			"equipment": "cabin", "crafting": "recipe:" + selected_recipe, "structure": "slot:" + selected_slot}[id]
		if not _focus_id(target): _focus_first(_focus_order())
	if id in ["overview", "energy", "equipment"] and _owns_session():
		_report_section.call_deferred(id, _presentation_revision, get_parent().current_user)

func _report_section(id: String, revision: int, user: Node3D) -> void:
	# Page selection must survive a layout/render frame with the same owner.
	await get_tree().process_frame
	if revision != _presentation_revision or current_page != id or not is_management_active(): return
	if not is_instance_valid(user) or get_parent().current_user != user or not _owns_session(): return
	var page: Control = _pages[id]
	if not page.is_visible_in_tree() or page.size.x <= 0.0 or page.size.y <= 0.0: return
	section_presented.emit(id)

func select_slot(id: String, focus: bool = true) -> void:
	if not slot_controls.has(id): return
	selected_slot = id
	_refresh()
	if focus: slot_controls[id].grab_focus()

func select_device(id: String) -> void:
	if not device_selectors.has(id): return
	selected_device = id
	_refresh()

func select_recipe(id: String) -> void:
	if not controls.has("recipe:" + id): return
	selected_recipe = id
	_refresh()

func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed: return
	if event.keycode == KEY_ESCAPE:
		_handle_event()
		_close()
		return
	if event.ctrl_pressed and event.keycode in [KEY_C, KEY_D]:
		_handle_event()
		if mode == Mode.TUI:
			enter_shell()
		elif event.keycode == KEY_C:
			shell_input.clear()
		return
	if mode == Mode.SHELL:
		if event.keycode in [KEY_UP, KEY_DOWN]:
			_history(-1 if event.keycode == KEY_UP else 1)
			_handle_event()
		elif event.keycode == KEY_TAB:
			_complete()
			_handle_event()
		return
	if event.keycode >= KEY_F1 and event.keycode <= KEY_F5:
		_handle_event()
		select_page(PAGES[event.keycode - KEY_F1])
		return
	# OptionButton menus own their arrows, Tab and activation keys. Their
	# separate viewport forwards only the global shortcuts handled above.
	if _popup_open(): return
	if event.keycode == KEY_TAB:
		_move_focus_order(-1 if event.shift_pressed else 1)
		_handle_event()
	elif event.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
		_move_focus(event.keycode)
		_handle_event()

func _unhandled_input(_event: InputEvent) -> void:
	if visible: _handle_event()

func _handle_event() -> void:
	get_viewport().set_input_as_handled()
	for id in ["craft:station", "structure:type"]:
		var popup: PopupMenu = controls[id].get_popup()
		if popup.visible: popup.get_viewport().set_input_as_handled()

func _close() -> void:
	dismiss_popups()
	close_requested.emit()

func dismiss_popups() -> void:
	for id in ["craft:station", "structure:type"]: controls[id].get_popup().hide()

func _popup_open() -> bool:
	return controls["craft:station"].get_popup().visible or controls["structure:type"].get_popup().visible

func _focus_control(id: String) -> Control:
	var control: Control = controls.get(id)
	if not is_instance_valid(control) or not control.is_visible_in_tree(): return null
	if control is BaseButton and control.disabled: return null
	return control.get_line_edit() if control is SpinBox else control

func _focused_id() -> String:
	var focused := get_viewport().gui_get_focus_owner()
	for id in controls:
		var control: Control = controls[id]
		if focused == control or (control is SpinBox and focused == control.get_line_edit()): return id
	return ""

func _focus_id(id: String) -> bool:
	var control := _focus_control(id)
	if not control: return false
	control.grab_focus()
	# Scroll on the next layout pass, including when a newly selected recipe
	# changes the height of its details or the viewport is narrow.
	var scroll: ScrollContainer = _pages[current_page]
	if scroll.is_ancestor_of(control): scroll.ensure_control_visible.call_deferred(control)
	return true

func _focus_first(ids: Array) -> bool:
	for id in ids:
		if _focus_id(id): return true
	return false

func _recipe_ids() -> Array:
	var ids: Array = []
	for recipe in RecipeCatalog.all(): ids.append("recipe:" + recipe.recipe_id)
	return ids

func _device_column(toggles: bool) -> Array:
	var ids: Array = ["cabin", "service"]
	for id in _device_ids:
		var key := ("device:" if toggles else "select:") + id
		if controls.has(key): ids.append(key)
	return ids

func _structure_actions() -> Array:
	return ["structure:type", "structure:repair", "structure:rebuild", "structure:convert", "structure:cancel"]

func _focus_order() -> Array:
	# Tab uses reading order, independent of panel sizes, wrapped text, or
	# disabled/hidden actions. Arrows additionally preserve logical columns.
	var ids: Array = []
	match current_page:
		"overview": ids = ["engine", "headlights", "inspect:equipment", "inspect:structure"]
		"energy": ids = ["charging_enabled", "charging_threshold", "charging_reserve"]
		"equipment":
			ids = ["cabin", "service"]
			for id in _device_ids:
				ids.append("select:" + id)
				if controls.has("device:" + id): ids.append("device:" + id)
		"crafting": ids = _recipe_ids() + ["craft:station", "craft:add", "craft:cancel"]
		"structure":
			for id in slot_controls: ids.append("slot:" + id)
			ids.append_array(_structure_actions())
	if current_page != "structure": ids.append("structure:cancel")
	return ids

func _move_in_list(ids: Array, id: String, direction: int, wrap: bool = false) -> void:
	var available: Array = []
	for candidate in ids:
		if _focus_control(candidate): available.append(candidate)
	if available.is_empty(): return
	var index: int = available.find(id)
	if index < 0:
		_focus_id(available[0 if direction > 0 else -1])
		return
	var next := index + direction
	if wrap: next = posmod(next, available.size())
	if next >= 0 and next < available.size(): _focus_id(available[next])

func _move_focus_order(direction: int) -> void:
	var id := _focused_id()
	if id.begins_with("page:"):
		# Tab from the page bar always enters the visible page's controls.
		_focus_first(_focus_order() if direction > 0 else _reversed(_focus_order()))
	else: _move_in_list(_focus_order(), id, direction, true)

func _reversed(ids: Array) -> Array:
	var result := ids.duplicate()
	result.reverse()
	return result

func _move_focus(key: Key) -> void:
	var id := _focused_id()
	var vertical := key in [KEY_UP, KEY_DOWN]
	var direction := -1 if key in [KEY_UP, KEY_LEFT] else 1
	if id.begins_with("page:"):
		if vertical: _focus_first(_focus_order())
		else:
			var pages: Array = []
			for page in PAGES: pages.append("page:" + page)
			_move_in_list(pages, id, direction, true)
		return
	if id.is_empty():
		_focus_first(_focus_order())
		return
	if id == "structure:cancel" and current_page != "structure":
		if vertical: _focus_first(_reversed(_focus_order().slice(0, -1)))
		return
	match current_page:
		"overview":
			if vertical: _move_in_list(_focus_order(), id, direction)
			else:
				var pairs := {"engine": "inspect:equipment", "headlights": "inspect:structure", "inspect:equipment": "engine", "inspect:structure": "headlights"}
				if (direction > 0 and id in ["engine", "headlights"]) or (direction < 0 and id.begins_with("inspect:")):
					_focus_id(pairs[id])
		"energy":
			if vertical: _move_in_list(_focus_order(), id, direction)
			elif controls.get(id) is SpinBox:
				var field: SpinBox = controls[id]
				field.apply()
				field.value += direction * field.step
		"equipment":
			if vertical:
				var column := _device_column(id.begins_with("device:"))
				column.append("structure:cancel")
				_move_in_list(column, id, direction)
			elif direction > 0 and id.begins_with("select:"): _focus_id(id.replace("select:", "device:"))
			elif direction < 0 and id.begins_with("device:"): _focus_id(id.replace("device:", "select:"))
		"crafting":
			var actions: Array = ["craft:station", "craft:add", "craft:cancel", "structure:cancel"]
			if id.begins_with("recipe:"):
				if vertical: _move_in_list(_recipe_ids(), id, direction)
				elif direction > 0: _focus_first(["craft:add", "craft:station", "craft:cancel", "structure:cancel"])
			elif vertical: _move_in_list(actions, id, direction)
			elif direction < 0: _focus_id("recipe:" + selected_recipe)
		"structure":
			if id.begins_with("slot:"): _move_structure_slot(id.trim_prefix("slot:"), key)
			elif vertical: _move_in_list(_structure_actions(), id, direction)
			elif direction < 0: _focus_id("slot:" + selected_slot)

func _move_structure_slot(id: String, key: Key) -> void:
	if id in ["front", "rear"]:
		if key == KEY_RIGHT: _focus_first(_structure_actions())
		elif key == KEY_DOWN and id == "front": _focus_id("slot:roof_0")
		elif key == KEY_UP and id == "rear": _focus_id("slot:roof_2")
		return
	var side := id.get_slice("_", 0)
	var row := int(id.get_slice("_", 1))
	var sides := ["left", "roof", "right"]
	var column: int = sides.find(side)
	match key:
		KEY_UP: _focus_id("slot:front" if row == 0 else "slot:%s_%d" % [side, row - 1])
		KEY_DOWN: _focus_id("slot:rear" if row == 2 else "slot:%s_%d" % [side, row + 1])
		KEY_LEFT:
			if column > 0: _focus_id("slot:%s_%d" % [sides[column - 1], row])
		KEY_RIGHT:
			if column < 2: _focus_id("slot:%s_%d" % [sides[column + 1], row])
			else: _focus_first(_structure_actions())

func _sanitize_input(text: String) -> void:
	var clean := text.replace("\r", " ").replace("\n", " ")
	if clean != text:
		shell_input.text = clean
		shell_input.caret_column = clean.length()

func _command_context() -> Dictionary:
	return {"rv": connected_rv, "terminal": get_parent(), "player": get_parent().current_user, "status_lines": _status_lines}

func submit_command(line: String) -> void:
	if not visible or mode != Mode.SHELL or not _owns_session(): return
	var clean := line.strip_edges()
	shell_input.clear()
	if clean.is_empty(): return
	command_history.append(clean)
	while command_history.size() > HISTORY_LIMIT: command_history.remove_at(0)
	_history_index = command_history.size()
	_history_draft = ""
	_append_output(PackedStringArray(["operator@rv:~$ " + clean]))
	var result := commands.execute(clean, _command_context())
	_append_output(result.lines)
	match result.action:
		"open_tui": enter_tui()
		"close_tablet": _close()
		"clear":
			terminal_lines.clear()
			shell_output.text = ""

func _append_output(lines: PackedStringArray) -> void:
	terminal_lines.append_array(lines)
	while terminal_lines.size() > OUTPUT_LIMIT: terminal_lines.remove_at(0)
	shell_output.text = "\n".join(terminal_lines)

func _history(direction: int) -> void:
	if _history_index == command_history.size(): _history_draft = shell_input.text
	_history_index = clampi(_history_index + direction, 0, command_history.size())
	shell_input.text = command_history[_history_index] if _history_index < command_history.size() else _history_draft
	shell_input.caret_column = shell_input.text.length()

func _complete() -> void:
	var candidates := commands.completion_candidates(shell_input.text, _command_context())
	if candidates.size() == 1:
		shell_input.text = candidates[0]
		shell_input.caret_column = shell_input.text.length()
	elif not candidates.is_empty(): _append_output(PackedStringArray(["  ".join(candidates)]))

func _process(delta: float) -> void:
	if not visible or mode != Mode.TUI: return
	_refresh_time -= delta
	if _refresh_time <= 0:
		_refresh_time = 0.2
		_refresh()

func _text(id: String, value: String) -> void:
	_texts[id].text = value

func _bar(value: float, maximum: float, width: int = 16) -> String:
	var filled := clampi(int(round(value / maxf(maximum, 0.001) * width)), 0, width)
	return "[" + "#".repeat(filled) + "-".repeat(width - filled) + "]"

func _pressed(id: String, value: bool) -> void:
	var button: CheckButton = controls[id]
	button.set_pressed_no_signal(value)
	button.text = "[ ON  ]" if value else "[ OFF ]"

func _number_value(id: String, value: float, maximum: float) -> void:
	var field: SpinBox = controls[id]
	if field.get_line_edit().has_focus(): return
	field.set_block_signals(true)
	field.max_value = maxf(maximum, value)
	field.set_value_no_signal(value)
	field.set_block_signals(false)

func _unlimited(enabled: bool) -> String:
	return " UNLIMITED" if enabled else ""

func _refresh() -> void:
	if not is_instance_valid(connected_rv) or _refreshing: return
	var focused_id := _focused_id()
	_refreshing = true
	var rv := connected_rv
	var energy: VehicleEnergy = rv.energy
	var engine: EngineState = rv.get_engine()
	var engine_info := "No engine installed"
	if engine:
		engine_info = "%s / HP %.0f / %.0f" % [RVTerminalPresenter.message(engine.definition().display_name), engine.health, engine.definition().max_health]
	_text("telemetry", "FUEL %.1f   BATTERY %.1f" % [rv.current_fuel, rv.current_power])
	_text("overview:status", "ENGINE  %s   %s\nFUEL    %s %5.1f / %.1f%s\nPOWER   %s %5.1f / %.1f%s\nSPEED   %.1f m/s   |   MATERIALS %d / %d%s" % [
		"RUNNING" if energy.engine_running else "STOPPED", engine_info, _bar(rv.current_fuel, rv.max_fuel), rv.current_fuel, rv.max_fuel, _unlimited(rv.unlimited_fuel),
		_bar(rv.current_power, rv.max_power), rv.current_power, rv.max_power, _unlimited(rv.unlimited_power), rv.linear_velocity.length(), rv.storage.used(), rv.storage.capacity, _unlimited(rv.unlimited_materials)])
	controls.engine.text = "[ Stop engine ]" if energy.engine_running else "[ Start engine ]"
	var engine_reason: String = "" if energy.engine_running else RVTerminalPresenter.message(rv.engine_start_reason())
	controls.engine.disabled = not engine_reason.is_empty()
	_text("engine:reason", engine_reason)
	_pressed("headlights", rv.headlights_requested)
	_text("headlights:state", "Off" if not rv.headlights_requested else ("Powered" if rv.lamps_powered else "Waiting for power"))
	var warnings := PackedStringArray()
	for row in RVTerminalPresenter.warnings(rv):
		if row.level > 0 and row.id != "headlight": warnings.append("%s: %s" % [row.label, row.message])
	if rv.storage.used() > rv.storage.capacity: warnings.append("Storage full: spend materials before recycling")
	_text("warnings", "\n".join(warnings) if not warnings.is_empty() else "All systems ready")
	_refresh_structure()
	_text("energy:flow", "BATTERY %s\n%.1f / %.1f charge%s\n\nGENERATION +%.2f /s\nLOAD       -%.2f /s\nNET        %+.2f /s\n\nFUEL %.1f / %.1f%s\nStandby load: 0.15 /s" % [
		_bar(rv.current_power, rv.max_power), rv.current_power, rv.max_power, _unlimited(rv.unlimited_power), energy.generated_rate, energy.load_rate,
		energy.generated_rate - energy.load_rate, rv.current_fuel, rv.max_fuel, _unlimited(rv.unlimited_fuel)])
	_pressed("charging_enabled", energy.charging_enabled)
	_number_value("charging_threshold", energy.recharge_below * 100.0, 100)
	_number_value("charging_reserve", energy.fuel_reserve, rv.max_fuel)
	_text("charging:state", RVTerminalPresenter.message(energy.charging_status()))
	for kind in ["cabin", "service"]: _pressed(kind, rv.interior_requested[kind])
	_text("interior:state", "Cabin: %s   |   Service: %s\nService lamp lights an open engine bay." % [_light_state("cabin"), _light_state("service")])
	_refresh_devices()
	_refresh_crafting()
	_text("message", _message)
	_refreshing = false
	# A completed job or equipment removal can hide/disable the focused
	# action. Keep focus in this page instead of falling back to geometry.
	if not focused_id.is_empty() and not focused_id.begins_with("page:") and not _focus_control(focused_id):
		var order := _focus_order()
		var index := order.find(focused_id)
		if index >= 0: _focus_first(order.slice(index + 1) + _reversed(order.slice(0, index)))

func _light_state(kind: String) -> String:
	return "Powered" if connected_rv.interior_powered[kind] else ("Waiting for power / equipment" if connected_rv.interior_requested[kind] else "Off")

func _refresh_devices() -> void:
	_devices = connected_rv.get_equipment().duplicate()
	_devices.sort_custom(func(a: Node, b: Node): return RVTerminalPresenter.display_name(a) < RVTerminalPresenter.display_name(b))
	var ids := PackedStringArray()
	for device in _devices: ids.append(device.persistent_id)
	if ids != _device_ids:
		var focus_id := _focused_id()
		var old_index := _device_ids.find(focus_id.get_slice(":", 1))
		for child in _device_list.get_children():
			child.hide()
			child.queue_free()
		for id in _device_ids:
			controls.erase("device:" + id)
			controls.erase("select:" + id)
		device_selectors.clear()
		_device_ids = ids
		for device in _devices:
			var id: String = device.persistent_id
			var row := HBoxContainer.new()
			_device_list.add_child(row)
			var button := _button(row, "select:" + id, _device_title(device), func(): select_device(id))
			button.clip_text = true
			button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			button.tooltip_text = _device_title(device)
			device_selectors[id] = button
			button.focus_entered.connect(func(): select_device(id))
			if device.has_method("step_work") or device is CabinLightStrip:
				var toggle := _toggle(row, "device:" + id, "", func(value: bool):
					if _can_write() and is_instance_valid(device):
						device.set_enabled(value)
						_refresh())
				toggle.custom_minimum_size.x = 100
				toggle.focus_entered.connect(func(): select_device(id))
		if not ids.has(selected_device): selected_device = ids[0] if not ids.is_empty() else ""
		if focus_id.begins_with("select:") or focus_id.begins_with("device:"):
			if not _focus_id(focus_id):
				if ids.is_empty(): _focus_id("service")
				else:
					var nearest: String = ids[clampi(old_index, 0, ids.size() - 1)]
					_focus_first(["device:" + nearest, "select:" + nearest] if focus_id.begins_with("device:") else ["select:" + nearest])
	var selected: Node = null
	for device in _devices:
		var id: String = device.persistent_id
		if controls.has("device:" + id): _pressed("device:" + id, device.enabled)
		if id == selected_device: selected = device
	if selected:
		var state: String = "Ready" if selected.can_operate() else ("Disabled" if not selected.enabled else "Disconnected / damaged")
		var activity := ""
		if selected is CabinLightStrip: activity = "\nLighting: " + ("Powered" if selected.enabled and selected.can_operate() and connected_rv.interior_powered.cabin else "Off")
		elif selected is BatterySocket: activity = "\nBattery %.1f / %.1f%s" % [connected_rv.current_power, connected_rv.max_power, _unlimited(connected_rv.unlimited_power)]
		elif selected is CraftingStation: activity = "\nCraft queue %d / %d" % [selected.jobs.size(), selected.queue_capacity]
		elif "props_being_crushed" in selected:
			activity = "\nRecycling queue %d / %d" % [selected.props_being_crushed.size(), selected.queue_capacity]
			if not selected.props_being_crushed.is_empty(): activity += "\n" + _bar(selected.crush_time - selected.props_being_crushed[0].timer, selected.crush_time)
		_text("device:detail", "%s\n%s\nHP %s %.0f / %.0f\nMounted to: %s%s" % [_device_title(selected), state,
			_bar(selected.current_health, selected.max_health), selected.current_health, selected.max_health, _mount_location(selected), activity])
	else: _text("device:detail", "No installed equipment")
	var tires := PackedStringArray()
	var names := ["Front left", "Front right", "Rear left", "Rear right"]
	for index in 4:
		var state := "MISSING" if connected_rv.installed_wheels[index] == null else ("FLAT" if connected_rv.wheel_health[index] <= 0 else "%.0f HP" % connected_rv.wheel_health[index])
		tires.append("%-12s %s %s" % [names[index], _bar(connected_rv.wheel_health[index], 100, 10), state])
	_text("tires", "\n".join(tires) + "\nStop and face a damaged tire; hold H to repair or install a replacement wheel.")

func _mount_location(device: Item) -> String:
	var support: Node = device.mount_support
	if support is RVStructurePanel: return RVTerminalPresenter.slot_name(support.mount_slot)
	if support == connected_rv: return "Chassis"
	return RVTerminalPresenter.display_name(support)

func _device_title(device: Item) -> String:
	var title := RVTerminalPresenter.display_name(device)
	if device is CabinLightStrip and device.mount_support is RVStructurePanel:
		var slot: String = device.mount_support.mount_slot
		if slot.begins_with("roof_"): title += " / " + ["front", "middle", "rear"][int(slot.right(1))]
	return title

func _station() -> CraftingStation:
	for device in _devices:
		if is_instance_valid(device) and device is CraftingStation and device.persistent_id == _station_id: return device
	return null

func _refresh_crafting() -> void:
	var items: Dictionary = connected_rv.get_all_items()
	var lines := PackedStringArray()
	var keys := items.keys()
	keys.sort()
	for key in keys: lines.append("%s: %d" % [RVTerminalPresenter.message(str(key)), items[key]])
	var material_text := "  |  ".join(lines) if not lines.is_empty() else "Storage empty"
	_text("materials", ("UNLIMITED materials | " if connected_rv.unlimited_materials else "") + material_text)
	var ids := PackedStringArray()
	for device in _devices:
		if device is CraftingStation: ids.append(device.persistent_id)
	var selector: OptionButton = controls["craft:station"]
	if ids != _station_ids or selector.item_count == 0:
		_station_ids = ids
		selector.clear()
		for device in _devices:
			if device is CraftingStation:
				selector.add_item("%s %d / %s" % [RVTerminalPresenter.display_name(device), selector.item_count + 1, _mount_location(device)])
				selector.set_item_metadata(selector.item_count - 1, device.persistent_id)
		if not ids.has(_station_id): _station_id = ids[0] if not ids.is_empty() else ""
		if ids.is_empty(): selector.add_item("No workstation installed")
		else: selector.select(ids.find(_station_id))
	selector.disabled = ids.is_empty()
	var recipe := RecipeCatalog.find(selected_recipe)
	var costs := PackedStringArray()
	for key in recipe.costs: costs.append("%s: %d needed / %d owned" % [key, recipe.costs[key], connected_rv.get_item_count(key)])
	_text("recipe:detail", "%s\n%s\nTime %.1fs   Power %.1f" % [RVTerminalPresenter.recipe_name(recipe), "\n".join(costs), recipe.duration, recipe.power_cost])
	var station := _station()
	var reason: String = station.craft_rejection_reason(selected_recipe) if station else "Workstation unavailable"
	_text("craft:reason", reason if not reason.is_empty() else "Ready to queue")
	controls["craft:add"].disabled = not reason.is_empty()
	controls["craft:cancel"].disabled = station == null or station.jobs.is_empty()
	var queue := PackedStringArray()
	if station:
		queue.append("QUEUE %d / %d" % [station.jobs.size(), station.queue_capacity])
		for job in station.jobs:
			var queued := RecipeCatalog.find(job.recipe)
			queue.append("%s  %s %.1fs" % [RVTerminalPresenter.recipe_name(queued), _bar(queued.duration - job.remaining, queued.duration, 10), job.remaining])
		if not station.last_error.is_empty(): queue.append(RVTerminalPresenter.message(station.last_error))
	_text("queue", "\n".join(queue) if not queue.is_empty() else "Queue unavailable")

func _construction() -> RVStructureConstruction:
	if not is_instance_valid(connected_rv): return null
	var slots := connected_rv.get_node_or_null("StructureSlots")
	return slots.construction if slots else null

func _refresh_structure() -> void:
	var slots := connected_rv.get_node_or_null("StructureSlots")
	if not slots: return
	var damaged := 0
	var destroyed := 0
	for id in slot_controls:
		var part: Node = slots.panel(id)
		if part.is_destroyed: destroyed += 1
		elif part.current_health < part.max_health: damaged += 1
		var short_name: String = {"front": "Front", "rear": "Rear"}.get(id, id.replace("left_", "L").replace("right_", "R").replace("roof_", "Roof "))
		slot_controls[id].text = "[ %s %s ]" % [short_name, "X" if part.is_destroyed else "%.0f" % part.current_health]
	_text("overview:structure", "%d ready   |   %d damaged   |   %d destroyed\nUse F5 to inspect, repair, rebuild or convert a part." % [11 - damaged - destroyed, damaged, destroyed])
	_text("structure:conditions", "ENGINE %s   SPEED %.1f / 0.5 m/s   METAL PARTS %d%s\nConstruction needs a stopped engine and an active tablet." % ["RUNNING" if connected_rv.energy.engine_running else "OFF", connected_rv.linear_velocity.length(), connected_rv.get_item_count(ItemNames.METAL_PARTS), _unlimited(connected_rv.unlimited_materials)])
	var target: Node = slots.panel(selected_slot)
	var selector: OptionButton = controls["structure:type"]
	if _type_slot != selected_slot:
		_type_slot = selected_slot
		selector.clear()
		for type in RVStructureSlots.types_for_slot(selected_slot):
			selector.add_item(RVTerminalPresenter.type_name(type))
			selector.set_item_metadata(selector.item_count - 1, type)
			if type == target.definition.type_id: selector.select(selector.item_count - 1)
	var type: String = str(selector.get_selected_metadata())
	var dependents: PackedStringArray = target.dependent_names()
	_text("structure:detail", "%s\n%s\nHP %s %.0f / %.0f\n%s" % [RVTerminalPresenter.slot_name(selected_slot), RVTerminalPresenter.type_name(target.definition.type_id),
		_bar(target.current_health, target.max_health), target.current_health, target.max_health,
		RVTerminalPresenter.message("Attached equipment: " + ", ".join(dependents)) if not dependents.is_empty() else "No attached equipment"])
	var construction: RVStructureConstruction = slots.construction
	for operation in ["repair", "rebuild", "convert"]:
		var chosen: String = "" if operation == "repair" else type
		var definition: Resource = target.definition if operation == "repair" else RVStructureSlots.definition_for(type)
		var reason: String = construction.rejection_reason(get_parent(), selected_slot, operation, chosen)
		var show_action: bool = (operation == "rebuild" and target.is_destroyed) or (operation == "repair" and not target.is_destroyed) or (operation == "convert" and not target.is_destroyed and selector.item_count > 1)
		controls["structure:" + operation].visible = show_action
		_texts["structure:reason:" + operation].visible = show_action
		controls["structure:" + operation].text = "[ %s / %d Metal Parts / %.1fs ]" % [operation.capitalize(), construction.operation_cost(operation, definition), construction.operation_seconds(operation, definition)]
		controls["structure:" + operation].disabled = not reason.is_empty()
		_text("structure:reason:" + operation, RVTerminalPresenter.message(reason) if not reason.is_empty() else "Ready")
	_construction_row.visible = construction.is_building()
	if construction.is_building():
		_text("construction", _bar(construction.progress(), 1, 12) + " " + RVTerminalPresenter.message(construction.status_message()))
		controls["structure:cancel"].disabled = construction.job.terminal != get_parent()
	elif construction.last_message != _last_construction_message:
		_last_construction_message = construction.last_message
		_message = RVTerminalPresenter.message(construction.last_message)

func _can_write() -> bool:
	return not _refreshing and is_management_active() and _owns_session()

func _owns_session() -> bool:
	var terminal := get_parent()
	if not is_instance_valid(connected_rv) or not is_instance_valid(terminal.current_user): return false
	var user: Node = terminal.current_user
	if user.get("is_player_dead") == true: return false
	if user.has_method("can_use_hands") and not user.can_use_hands(): return false
	if user.has_method("get_player_mode") and user.get_player_mode() != user.PlayerMode.UI: return false
	return terminal.can_operate() and terminal.get_connected_rv() == connected_rv and connected_rv.has_usable_power()

func _toggle_engine() -> void:
	if not _can_write(): return
	var okay: bool = connected_rv.set_engine_running(not connected_rv.energy.engine_running)
	_message = ("Engine started" if connected_rv.energy.engine_running else "Engine stopped") if okay else RVTerminalPresenter.message(connected_rv.engine_start_reason())
	_refresh()

func _set_light(kind: String, value: bool) -> void:
	if not _can_write(): return
	if kind == "headlights": connected_rv.headlights_requested = value
	elif bool(connected_rv.interior_requested[kind]) != value:
		connected_rv.toggle_interior_light(kind)
		if kind == "cabin" and bool(connected_rv.interior_requested.cabin) == value:
			connected_rv.cabin_lights_changed.emit(value, get_parent())
	_refresh()

func _craft() -> void:
	var station := _station()
	if not _can_write() or not station: return
	_message = "Queued " + RVTerminalPresenter.recipe_name(RecipeCatalog.find(selected_recipe)) if station.request_craft(selected_recipe) else RVTerminalPresenter.message(station.last_error)
	_refresh()

func _cancel_crafting() -> void:
	var station := _station()
	if not _can_write() or not station: return
	station.cancel_jobs()
	_message = "Queue cancelled; reserved materials refunded"
	_refresh()

func _begin_structure(operation: String) -> void:
	if not _can_write(): return
	var type: String = "" if operation == "repair" else str(controls["structure:type"].get_selected_metadata())
	var reason := _construction().begin(get_parent(), selected_slot, operation, type)
	_message = RVTerminalPresenter.message(reason) if not reason.is_empty() else "Construction started"
	_refresh()

func _cancel_construction() -> void:
	var construction := _construction()
	if not _can_write() or not construction or not construction.is_building() or construction.job.terminal != get_parent(): return
	construction.cancel()
	_refresh()

func _inspect_structure() -> void:
	var slots := connected_rv.get_node("StructureSlots")
	for id in slot_controls:
		var panel: Node = slots.panel(id)
		if panel.is_destroyed or panel.current_health < panel.max_health:
			selected_slot = id
			break
	select_page("structure")

func _status_lines() -> PackedStringArray:
	if not is_instance_valid(connected_rv): return PackedStringArray(["RV unavailable"])
	var rv := connected_rv
	return PackedStringArray(["ENGINE %s" % ("RUNNING" if rv.energy.engine_running else "STOPPED"),
		"FUEL %.1f / %.1f%s" % [rv.current_fuel, rv.max_fuel, _unlimited(rv.unlimited_fuel)], "BATTERY %.1f / %.1f%s" % [rv.current_power, rv.max_power, _unlimited(rv.unlimited_power)],
		"SPEED %.1f m/s" % rv.linear_velocity.length(), "MATERIALS %d / %d%s" % [rv.storage.used(), rv.storage.capacity, _unlimited(rv.unlimited_materials)],
		RVTerminalPresenter.message(rv.energy.charging_status())])
