extends CanvasLayer

signal close_requested
var connected_rv: Node3D
var status_label: Label
var device_box: VBoxContainer
var material_box: VBoxContainer
var recipe_box: VBoxContainer
var message: Label
var _refresh_time := 0.0
var _signature := ""
var recipe_buttons: Dictionary = {}
var device_labels: Dictionary = {}

func _ready() -> void:
	layer = 30
	for child in get_children():
		child.queue_free()
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.02, 0.03, 0.04, 0.9)
	add_child(shade)
	var panel := MarginContainer.new()
	var theme := Theme.new()
	theme.default_font_size = 24
	panel.theme = theme
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		panel.add_theme_constant_override("margin_" + side, 40)
	add_child(panel)
	var scroll := ScrollContainer.new()
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 12)
	scroll.add_child(box)
	var title := Label.new()
	title.text = "RV SERVICE TERMINAL"
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)
	var close := Button.new()
	close.text = "Close [Esc]"
	close.pressed.connect(func(): close_requested.emit())
	box.add_child(close)
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 22)
	box.add_child(status_label)
	var engine := Button.new()
	engine.text = "Start / stop engine (stationary charging uses fuel)"
	engine.pressed.connect(func():
		if is_instance_valid(connected_rv):
			var okay: bool = connected_rv.set_engine_running(not connected_rv.energy.engine_running)
			message.text = ("引擎已發動" if connected_rv.energy.engine_running else "引擎已停止") if okay else "無法發動：底盤損壞或燃油不足"
			_refresh())
	box.add_child(engine)
	message = Label.new()
	box.add_child(message)
	device_box = VBoxContainer.new()
	material_box = VBoxContainer.new()
	recipe_box = VBoxContainer.new()
	box.add_child(device_box)
	box.add_child(material_box)
	box.add_child(recipe_box)

func on_open() -> void:
	connected_rv = get_parent().get_connected_rv()
	_signature = ""
	_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_requested.emit()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_time -= delta
	if _refresh_time <= 0.0:
		_refresh_time = 0.2
		_refresh()

func _station() -> Node:
	if not is_instance_valid(connected_rv):
		return null
	for device in connected_rv.get_equipment():
		if device is CraftingStation and device.can_operate():
			return device
	return null

func _refresh() -> void:
	if not is_instance_valid(connected_rv) or not is_instance_valid(status_label):
		return
	connected_rv.update_storage_capacity()
	status_label.text = "ENGINE %s | FUEL %.1f / %.1f\nBATTERY %.1f / %.1f | CHARGE +%.2f / LOAD -%.2f per s\nMATERIALS %d / %d%s\nTIRES FL %.0f / FR %.0f / RL %.0f / RR %.0f\nStandby: -0.15 power/s | Hold H facing damaged hardware to repair (engine off)." % [
		"RUNNING" if connected_rv.energy.engine_running else "OFF", connected_rv.current_fuel, connected_rv.max_fuel,
		connected_rv.current_power, connected_rv.max_power, connected_rv.energy.generated_rate, connected_rv.energy.load_rate,
		connected_rv.storage.used(), connected_rv.storage.capacity, " — OVER CAPACITY: spend materials before recycling" if connected_rv.storage.used() > connected_rv.storage.capacity else "", connected_rv.wheel_health[0], connected_rv.wheel_health[1], connected_rv.wheel_health[2], connected_rv.wheel_health[3]]
	if connected_rv.energy.battery == null:
		status_label.text += "\nNO BATTERY: install a battery into an operational socket."
	elif connected_rv.current_power <= 0.0:
		status_label.text += "\nBATTERY EMPTY: swap it or start the engine with a generator installed."
	var devices: Array[Node] = connected_rv.get_equipment()
	var signature := ""
	for device in devices:
		signature += device.persistent_id
	signature += str(connected_rv.get_all_items())
	if signature != _signature:
		_signature = signature
		_rebuild(devices)
	for device in devices:
		if device_labels.has(device.persistent_id):
			var state := "ON" if device.can_operate() else "OFFLINE"
			if device.has_method("get_status"):
				state = device.get_status()
			if device is CraftingStation:
				state += " | %d jobs | %s" % [device.jobs.size(), device.last_error]
				if not device.jobs.is_empty():
					state += " | %.1fs remaining" % device.jobs[0].remaining
			if "props_being_crushed" in device:
				state += " | %d inputs | work %.1f power/s" % [device.props_being_crushed.size(), device.power_draw_per_second]
				if not device.props_being_crushed.is_empty():
					state += " | %.1fs%s" % [maxf(0.0, device.props_being_crushed[0].timer), " (battery empty)" if connected_rv.current_power <= 0.0 else ""]
			device_labels[device.persistent_id].text = "%s | HP %.0f / %.0f | %s" % [device.equipment_name, device.current_health, device.max_health, state]
	var station := _station()
	for recipe in RecipeCatalog.all():
		if recipe_buttons.has(recipe.recipe_id):
			recipe_buttons[recipe.recipe_id].disabled = station == null or not connected_rv.has_materials(recipe.costs) or not connected_rv.has_usable_power(recipe.power_cost) or station.jobs.size() >= station.queue_capacity

func _rebuild(devices: Array[Node]) -> void:
	for box in [device_box, material_box, recipe_box]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
	device_labels.clear()
	recipe_buttons.clear()
	for device in devices:
		var row := HBoxContainer.new()
		device_box.add_child(row)
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(label)
		device_labels[device.persistent_id] = label
		if device.has_method("step_work") or device.has_method("generate_power"):
			var toggle := Button.new()
			toggle.text = "On / off"
			toggle.pressed.connect(func():
				if is_instance_valid(device): device.set_enabled(not device.enabled))
			row.add_child(toggle)
		if device.has_method("generate_power"):
			var settings := HBoxContainer.new()
			device_box.add_child(settings)
			var note := Label.new()
			note.text = "Recharge below % / fuel reserve:"
			settings.add_child(note)
			var threshold := SpinBox.new()
			threshold.max_value = 100.0
			threshold.step = 5.0
			threshold.value = device.recharge_below * 100.0
			threshold.value_changed.connect(func(value: float):
				if is_instance_valid(device): device.recharge_below = value / 100.0)
			settings.add_child(threshold)
			var reserve := SpinBox.new()
			reserve.max_value = connected_rv.max_fuel
			reserve.value = device.fuel_reserve
			reserve.value_changed.connect(func(value: float):
				if is_instance_valid(device): device.fuel_reserve = value)
			settings.add_child(reserve)
		if device is CraftingStation:
			var cancel := Button.new()
			cancel.text = "Cancel queued jobs"
			cancel.pressed.connect(func():
				if is_instance_valid(device): device.cancel_jobs())
			row.add_child(cancel)
	for material: String in connected_rv.get_all_items():
		var label := Label.new()
		label.text = "%s: %d" % [material, connected_rv.get_item_count(material)]
		material_box.add_child(label)
	for recipe in RecipeCatalog.all():
		var button := Button.new()
		button.text = "Queue %s | %s | %.1f power | %.1fs" % [recipe.display_name, str(recipe.costs), recipe.power_cost, recipe.duration]
		button.pressed.connect(func():
			var station := _station()
			if station:
				station.request_craft(recipe.recipe_id)
				message.text = station.last_error)
		recipe_box.add_child(button)
		recipe_buttons[recipe.recipe_id] = button
