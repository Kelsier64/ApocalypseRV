class_name PlaygroundControls
extends Node
## Playground-only controls shown as a "Playground" tab in the player's Esc menu.
## Add one instance to the playground scene, declare rows in _ready, and leave all
## gameplay on the normal input map. The menu builds the tab when it first opens.

const GROUP := &"playground_controls"
const SCENARIO_META := &"playground_scenario"

var _rows: Array[Callable] = []
var _readouts: Array[Array] = []
var _page: VBoxContainer


func _enter_tree() -> void:
	add_to_group(GROUP)


## Scenario chosen by the last restart() in this run, else --scenario=<name>, else fallback.
static func scenario(fallback: String) -> String:
	if Engine.has_meta(SCENARIO_META): return Engine.get_meta(SCENARIO_META)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--scenario="): return argument.trim_prefix("--scenario=")
	return fallback


## Reloads the playground, optionally into another scenario.
func restart(next_scenario := "") -> void:
	if not next_scenario.is_empty(): Engine.set_meta(SCENARIO_META, next_scenario)
	get_tree().reload_current_scene.call_deferred()


## Scenario buttons plus "Restart"; the current scenario is marked.
func scenarios(names: PackedStringArray, current: String) -> void:
	section("Scenario")
	var entries: Array = []
	for scenario_name in names:
		entries.append([("> %s" % scenario_name) if scenario_name == current else scenario_name, restart.bind(scenario_name)])
	entries.append(["Restart", restart])
	buttons(entries)


func section(title: String) -> void:
	_rows.append(func(page: VBoxContainer):
		var heading := _label(title, 18)
		heading.add_theme_color_override("font_color", IndustrialTheme.AMBER)
		page.add_child(heading))


## One short line of guidance, such as which normal controls to use.
func note(text: String) -> void:
	_rows.append(func(page: VBoxContainer):
		var line := _label(text, 16)
		line.add_theme_color_override("font_color", Color("b6b8a9"))
		page.add_child(line))


func button(text: String, action: Callable) -> void:
	buttons([[text, action]])


## A wrapping row of buttons from [[text, callable], ...].
func buttons(entries: Array) -> void:
	_rows.append(func(page: VBoxContainer):
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 8)
		row.add_theme_constant_override("v_separation", 8)
		page.add_child(row)
		for entry in entries:
			var pressed := Button.new()
			pressed.text = entry[0]
			pressed.pressed.connect(entry[1])
			row.add_child(pressed))


func toggle(text: String, on: bool, changed: Callable) -> void:
	_rows.append(func(page: VBoxContainer):
		var check := CheckButton.new()
		check.text = text
		check.button_pressed = on
		check.toggled.connect(changed)
		page.add_child(check))


func choice(text: String, options: PackedStringArray, selected: int, changed: Callable) -> void:
	_rows.append(func(page: VBoxContainer):
		var row := _labelled_row(page, text)
		var option := OptionButton.new()
		for item in options: option.add_item(item)
		option.selected = selected
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option.item_selected.connect(changed)
		row.add_child(option))


func slider(text: String, minimum: float, maximum: float, step: float, value: float, changed: Callable) -> void:
	_rows.append(func(page: VBoxContainer):
		var row := _labelled_row(page, text)
		var bar := HSlider.new()
		bar.min_value = minimum
		bar.max_value = maximum
		bar.step = step
		bar.value = value
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		var shown := _label(str(value), 16)
		shown.custom_minimum_size.x = 64
		row.add_child(shown)
		bar.value_changed.connect(func(next: float):
			shown.text = str(next)
			changed.call(next)))


## A live value; value returns the text and is polled while the tab is visible.
func readout(text: String, value: Callable) -> void:
	_rows.append(func(page: VBoxContainer):
		var row := _labelled_row(page, text)
		var shown := _label("", 16)
		row.add_child(shown)
		_readouts.append([shown, value]))


## Called by the Esc menu once, with the tab's empty page.
func build(page: VBoxContainer) -> void:
	_page = page
	for row in _rows: row.call(page)
	_refresh()


func _process(_delta: float) -> void:
	if is_instance_valid(_page) and _page.is_visible_in_tree(): _refresh()


func _refresh() -> void:
	for readout_row in _readouts: readout_row[0].text = str(readout_row[1].call())


func _labelled_row(page: VBoxContainer, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	page.add_child(row)
	var title := _label(text, 16)
	title.custom_minimum_size.x = 220
	row.add_child(title)
	return row


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	return label
