extends CanvasLayer
var seat: Node3D
var label: Label
var status: Label
var indicators: Dictionary = {}

func _ready() -> void:
	seat = get_parent()
	layer = 15
	var panel := PanelContainer.new()
	panel.theme = IndustrialTheme.make(22)
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 24
	panel.offset_right = -24
	panel.offset_top = -230
	panel.offset_bottom = -24
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.055, 0.06, 0.94)
	style.border_color = IndustrialTheme.BORDER
	style.set_border_width_all(1)
	style.set_content_margin_all(12)
	style.set_corner_radius_all(0)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(rows)
	label = Label.new()
	label.add_theme_font_size_override("font_size", 28)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(label)
	var lamps := HBoxContainer.new()
	lamps.add_theme_constant_override("separation", 18)
	rows.add_child(lamps)
	for id in VehicleStatus.IDS:
		var cell := HBoxContainer.new()
		lamps.add_child(cell)
		var icon := TextureRect.new()
		icon.texture = load("res://assets/rv_status/" + id + ".svg")
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.custom_minimum_size = Vector2(36, 36)
		cell.add_child(icon)
		var caption := Label.new()
		caption.add_theme_font_size_override("font_size", 22)
		cell.add_child(caption)
		indicators[id] = {"icon": icon, "caption": caption}
	status = Label.new()
	status.add_theme_font_size_override("font_size", 22)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_color_override("font_color", Color(0.94, 0.72, 0.38))
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(status)
	var controls := Label.new()
	controls.text = "B 引擎 · L 頭燈 · Space 手煞車 · Z/X/C 排檔 · R/T 升降檔 · W/S 油門煞車 · E 離座"
	controls.add_theme_font_size_override("font_size", 20)
	controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(controls)
	visible = false

func _process(_delta: float) -> void:
	visible = is_instance_valid(seat.current_driver)
	if not visible: return
	var rv: Chassis = seat.get_connected_rv() as Chassis
	if rv == null: return
	var gear := "R" if rv.gear < 0 else ("N" if rv.gear == 0 else str(rv.gear))
	label.text = "%03.0f km/h   %s 檔   |   引擎 %s   |   燃油 %.0f / %.0f   |   電池 %.0f / %.0f" % [rv.road_speed() * 3.6, gear, "運轉" if rv.energy.engine_running else "停止", rv.current_fuel, rv.max_fuel, rv.current_power, rv.max_power]
	for row in VehicleStatus.read(rv):
		indicators[row.id].icon.modulate = VehicleStatus.color(row.level)
		indicators[row.id].caption.text = row.label
	status.text = seat.exit_message if not seat.exit_message.is_empty() else VehicleStatus.messages(rv)
	if not rv.service_message.is_empty(): status.text += "  " + rv.service_message
