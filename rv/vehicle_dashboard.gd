extends CanvasLayer
var seat: Node3D
var label: Label
var status: Label

func _ready() -> void:
	seat = get_parent()
	layer = 15
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 24
	panel.offset_right = -24
	panel.offset_top = -180
	panel.offset_bottom = -24
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.055, 0.055, 0.92)
	style.border_color = Color(0.32, 0.48, 0.41)
	style.set_border_width_all(1)
	style.set_content_margin_all(12)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(rows)
	label = Label.new()
	label.add_theme_font_size_override("font_size", 30)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(label)
	status = Label.new()
	status.add_theme_font_size_override("font_size", 24)
	status.add_theme_color_override("font_color", Color(0.94, 0.72, 0.38))
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(status)
	var controls := Label.new()
	controls.text = "B 引擎  ·  Space 手煞車  ·  Z 倒檔 / X 空檔 / C 前進  ·  R / T 升降檔  ·  W 油門 / S 煞車  ·  E 離座"
	controls.add_theme_font_size_override("font_size", 22)
	controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(controls)
	visible = false

func _process(_delta: float) -> void:
	visible = is_instance_valid(seat.current_driver)
	if not visible: return
	var rv: Chassis = seat.get_connected_rv() as Chassis
	if rv == null: return
	var gear := "R" if rv.gear < 0 else ("N" if rv.gear == 0 else str(rv.gear))
	label.text = "%03.0f km/h   %s 檔   |   引擎 %s   |   燃油 %.0f / %.0f   |   電池 %.0f / %.0f" % [rv.linear_velocity.length() * 3.6, gear, "運轉" if rv.energy.engine_running else "停止", rv.current_fuel, rv.max_fuel, rv.current_power, rv.max_power]
	var messages: Array[String] = []
	if rv.handbrake: messages.append("手煞車已拉起")
	if rv.current_fuel <= 0.0: messages.append("燃油耗盡：使用加油孔補充")
	if rv.energy.battery == null: messages.append("未裝電池：將電池裝入插槽")
	elif rv.current_power <= 0.0: messages.append("電池耗盡：更換電池或發動引擎配合發電機充電")
	if rv.get_installed_wheel_count() < 4: messages.append("輪胎缺失：停車安裝")
	if rv.current_chassis_health < rv.max_chassis_health * 0.3: messages.append("車體嚴重損壞：熄火停穩後 H 維修")
	status.text = "  ·  ".join(messages) if not messages.is_empty() else "車體 %.0f%%   ·   供電 +%.2f / 耗電 −%.2f 每秒" % [100.0 * rv.current_chassis_health / rv.max_chassis_health, rv.energy.generated_rate, rv.energy.load_rate]
