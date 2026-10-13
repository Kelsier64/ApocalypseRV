extends CanvasLayer
## English tutorial pages, kept separate from rvctl and its command authority.
signal close_requested
signal current_conditions_visible(stage: int)
const FRAME = preload("res://equipment/terminal_panel.gd")
const PAGE_IDS := ["conditions", "steps", "reference", "manual"]
const PAGE_NAMES := ["Conditions", "Steps", "Controls", "Manual"]
var current_page := "conditions"
var controls: Dictionary = {}
var page_data: Dictionary = {}
var _screen: Control
var _body: VBoxContainer
var _pages: Dictionary = {}
var _title: Label
var _conditions: Label
var _steps: Label
var _reference: Label
var _manual: Label
var _search: LineEdit
var _refresh_time := 0.0
var _last_presented_stage := -1
var _session := 0

func _ready() -> void:
	layer = 20
	# A container root can retain its content's minimum height beyond the
	# viewport. Keep the viewport frame independent of scroll-page contents.
	_screen = Control.new()
	_screen.name = "Screen"
	_screen.theme = RVTerminalTheme.make()
	add_child(_screen)
	var background := ColorRect.new()
	background.color = RVTerminalTheme.BACKGROUND
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	_screen.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.offset_bottom = -60
	margin.clip_contents = true
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 12)
	margin.add_child(_body)
	label(_body, "training / CIVIL DEFENSE", RVTerminalTheme.CYAN)
	_title = label(_body, "Training terminal")
	var navigation := HFlowContainer.new()
	_body.add_child(navigation)
	for index in PAGE_IDS.size():
		var id: String = PAGE_IDS[index]
		var button := Button.new()
		button.text = "[ F%d %s ]" % [index + 1, PAGE_NAMES[index]]
		button.custom_minimum_size.y = 40
		button.pressed.connect(select_page.bind(id))
		navigation.add_child(button)
		controls[id] = button
		button.focus_entered.connect(_focus_button.bind(button, true))
		button.focus_exited.connect(_focus_button.bind(button, false))
		_focus_button(button, false)
	_conditions = label(_page("conditions", "Current conditions"), "")
	_steps = label(_page("steps", "Procedure"), "")
	_reference = label(_page("reference", "Controls"), "")
	var manual_body := _page("manual", "Survival manual")
	_search = LineEdit.new()
	_search.placeholder_text = "Search manual"
	_search.context_menu_enabled = false
	_search.text_changed.connect(_refresh_manual.unbind(1))
	manual_body.add_child(_search)
	_manual = label(manual_body, "")
	# Keep keyboard guidance outside page/container minimum-size negotiation.
	# Pages may scroll, but their content cannot displace the viewport footer.
	var footer := label(_screen, "F1-F4 Pages   Tab Focus   Enter Select   Esc Close", RVTerminalTheme.DIM)
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_left = 20
	footer.offset_right = -20
	footer.offset_top = -56
	footer.offset_bottom = -16
	footer.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	get_viewport().size_changed.connect(_resize)
	select_page("conditions", false)
	_resize()

func label(parent: Node, text: String, color: Color = RVTerminalTheme.INK) -> Label:
	var result := Label.new()
	result.text = text
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.add_theme_color_override("font_color", color)
	parent.add_child(result)
	return result

func _page(id: String, heading: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_body.add_child(scroll)
	_pages[id] = scroll
	var frame := PanelContainer.new()
	frame.set_script(FRAME)
	frame.heading = heading
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(frame)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.add_child(content)
	return content

func _focus_button(button: Button, focused: bool) -> void:
	for color in ["font_color", "font_focus_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(color, RVTerminalTheme.BACKGROUND if focused else RVTerminalTheme.INK)
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		button.add_theme_stylebox_override(state, RVTerminalTheme.style(RVTerminalTheme.AMBER if focused else Color.TRANSPARENT))

func _resize() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var factor := maxf(1.0, viewport_size.x / 1280.0)
	scale = Vector2.ONE * factor
	_screen.size = viewport_size / factor

func on_open() -> void:
	_session += 1
	_last_presented_stage = -1
	_search.text = ""
	select_page("conditions")

func select_page(id: String, focus: bool = true) -> void:
	if not _pages.has(id): return
	current_page = id
	for page in _pages: _pages[page].visible = page == id
	refresh()
	if focus: controls[id].grab_focus()

func refresh() -> void:
	var terminal := get_parent()
	var controller: Node = terminal.tutorial_controller()
	page_data = controller.terminal_page() if controller != null else {}
	if page_data.is_empty():
		_title.text = "Training terminal"
		_conditions.text = "No active training course in this location."
		_steps.text = "No active procedure."
		_reference.text = "E Pick up / interact\nHold E Use mounted devices\nHold F Remove a mounted item\nEsc Close terminal"
	else:
		_title.text = "Stage %d / %s" % [page_data.get("stage", 0), page_data.get("title", "Training")]
		var lines := PackedStringArray()
		if not page_data.get("available", false): lines.append("This station is offline. Consult the available briefing pages.")
		for condition: Dictionary in page_data.get("conditions", []):
			lines.append("[%s] %s" % ["x" if condition.get("complete", false) else " ", condition.get("label", "")])
		_conditions.text = "\n".join(lines)
		_steps.text = _list_text(page_data.get("steps", []))
		_reference.text = _list_text(page_data.get("reference", []))
	_refresh_manual()
	if visible and current_page == "conditions" and page_data.get("available", false):
		var stage: int = page_data.get("stage", 0)
		if stage != _last_presented_stage: _report_visible.call_deferred(stage, _session)

func _list_text(lines: Array) -> String:
	var result := PackedStringArray()
	for index in lines.size(): result.append("%d. %s" % [index + 1, lines[index]])
	return "\n".join(result)

func _refresh_manual() -> void:
	var terminal := get_parent()
	_search.editable = terminal.manual_unlocked
	if not terminal.manual_unlocked:
		_manual.text = "Complete training to unlock the field manual."
		return
	# Search infrastructure is ready; the full manual is delivered with stage 5.
	var entries := ["Civil Defense field manual", "Training record: " + terminal.completion.capitalize()]
	var matches := PackedStringArray()
	for entry: String in entries:
		if _search.text.is_empty() or entry.to_lower().contains(_search.text.to_lower()): matches.append(entry)
	_manual.text = "\n\n".join(matches) if not matches.is_empty() else "No matching entries."

func _report_visible(stage: int, session: int) -> void:
	# Deferred presentation alone is insufficient: allow one layout/render frame
	# and check the actual current page, session and player ownership afterward.
	await get_tree().process_frame
	if session != _session or not visible or current_page != "conditions": return
	if not _conditions.is_visible_in_tree() or not page_data.get("available", false) or page_data.get("stage", 0) != stage: return
	if not get_parent()._user_valid() or stage == _last_presented_stage: return
	_last_presented_stage = stage
	current_conditions_visible.emit(stage)

func _process(delta: float) -> void:
	if not visible: return
	_refresh_time += delta
	if _refresh_time >= 0.2:
		_refresh_time = 0.0
		refresh()

func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close_requested.emit()
	elif event.keycode >= KEY_F1 and event.keycode <= KEY_F4:
		get_viewport().set_input_as_handled()
		select_page(PAGE_IDS[event.keycode - KEY_F1])
