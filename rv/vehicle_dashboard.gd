extends CanvasLayer

var seat: Node3D
var label: Label

func _ready() -> void:
	seat = get_parent()
	layer = 15
	var panel := PanelContainer.new()
	panel.position = Vector2(24, 24)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	label = Label.new()
	label.add_theme_font_size_override("font_size", 22)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)

func _process(_delta: float) -> void:
	visible = is_instance_valid(seat.current_driver)
	if not visible:
		return
	var rv: Node = seat.get_connected_rv()
	if rv == null:
		return
	label.text = "%3.0f km/h   %s   %s\nENGINE %s | FUEL %.1f / %.1f\nBATTERY %.1f / %.1f | +%.2f / -%.2f per s\nCHASSIS %.0f%% | WHEELS %d/4 | MASS %.0f kg\nB engine | Space parking brake | Z reverse / X neutral / C forward | R up / T down (1-4)\nW throttle / S brake | E leave seat" % [
		rv.linear_velocity.length() * 3.6, "R" if rv.gear < 0 else ("N" if rv.gear == 0 else str(rv.gear)),
		"PARK BRAKE" if rv.handbrake else "RELEASED", "ON" if rv.energy.engine_running else "OFF",
		rv.current_fuel, rv.max_fuel, rv.current_power, rv.max_power, rv.energy.generated_rate, rv.energy.load_rate,
		100.0 * rv.current_chassis_health / rv.max_chassis_health, rv.get_installed_wheel_count(), rv.mass]
