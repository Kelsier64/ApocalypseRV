extends CanvasLayer
## Transparent, right-aligned guide. The interaction ray supplies the bindings.

const HEADING_COLOR := Color("efcd90")
const KEY_COLOR := Color("fff1d7")
const TEXT_OUTLINE := Color(0.025, 0.02, 0.015, 0.95)

var _layout: VBoxContainer
var _heading: Label
var _rows: GridContainer
var _key_frame: StyleBoxFlat
var _bindings: Dictionary = {}

func _ready() -> void:
	layer = 6
	hide()
	HUDVisibility.attach(self)
	var screen := Control.new()
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(screen)
	var right_edge := HBoxContainer.new()
	right_edge.alignment = BoxContainer.ALIGNMENT_END
	right_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(right_edge)
	right_edge.anchor_right = 1.0
	right_edge.offset_right = -28.0

	_layout = VBoxContainer.new()
	_layout.theme = IndustrialTheme.make(16)
	_layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layout.custom_minimum_size.x = 286
	_layout.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_layout.add_theme_constant_override("separation", 10)
	right_edge.add_child(_layout)
	_key_frame = IndustrialTheme.box(Color.TRANSPARENT, Color(0.92, 0.86, 0.74, 0.68), 0)
	_key_frame.draw_center = false
	_key_frame.set_corner_radius_all(3)
	_key_frame.content_margin_left = 7
	_key_frame.content_margin_right = 7

	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_constant_override("separation", 8)
	_layout.add_child(header)
	var accent := ColorRect.new()
	accent.color = HEADING_COLOR
	accent.custom_minimum_size = Vector2(10, 2)
	accent.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(accent)
	_heading = _label("", HEADING_COLOR, 14)
	_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_heading)
	header.add_child(_keycap("J"))
	header.add_child(_label("Hide", IndustrialTheme.INK, 13))

	_rows = GridContainer.new()
	_rows.columns = 2
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows.add_theme_constant_override("h_separation", 12)
	_rows.add_theme_constant_override("v_separation", 4)
	_layout.add_child(_rows)
	var layout := UILayout.attach(self, screen)
	var position_guide := func(logical_size: Vector2) -> void:
		# On short windows, leave space below for the driving dashboard.
		var top := minf(logical_size.y * 0.25, logical_size.y - 465.0)
		right_edge.offset_top = top
		right_edge.offset_bottom = top
	layout.resized.connect(position_guide)
	position_guide.call(screen.size)

func present(heading: String, bindings: Dictionary) -> void:
	show()
	if _heading.text == heading and _bindings == bindings: return
	_heading.text = heading
	_bindings = bindings
	for row in _rows.get_children():
		_rows.remove_child(row)
		row.queue_free()
	for key: String in bindings:
		var key_column := HBoxContainer.new()
		key_column.alignment = BoxContainer.ALIGNMENT_END
		key_column.custom_minimum_size.x = 98
		key_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		key_column.add_child(_keycap(key))
		_rows.add_child(key_column)
		_rows.add_child(_label(bindings[key], IndustrialTheme.INK, 16))

func _keycap(text: String) -> PanelContainer:
	var cap := PanelContainer.new()
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.add_theme_stylebox_override("panel", _key_frame)
	cap.custom_minimum_size = Vector2(23, 22)
	var label := _label(text, KEY_COLOR, 13)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_child(label)
	return cap

func _label(text: String, ink: Color, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_font_size_override("outline_size", 5)
	label.add_theme_color_override("font_color", ink)
	label.add_theme_color_override("font_outline_color", TEXT_OUTLINE)
	return label
