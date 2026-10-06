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
var structure_box: VBoxContainer
var structure_status: Label
var structure_rows: Dictionary = {}
var structure_buttons: Array[Dictionary] = []
var service_tabs: TabContainer

func _ready() -> void:
	layer = 30
	for child in get_children():
		child.queue_free()
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.045, 0.055, 0.06, 0.96)
	add_child(shade)
	var panel := MarginContainer.new()
	panel.theme = IndustrialTheme.make(24)
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
	title.add_theme_color_override("font_color", IndustrialTheme.AMBER)
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)
	var close := Button.new()
	close.text = "Close [Esc]"
	close.pressed.connect(func(): close_requested.emit())
	box.add_child(close)
	service_tabs = TabContainer.new()
	service_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(service_tabs)
	var service := VBoxContainer.new()
	service.name = "設備與資源"
	service.add_theme_constant_override("separation", 12)
	service_tabs.add_child(service)
	box = service
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 22)
	box.add_child(status_label)
	var engine := Button.new()
	engine.text = "Start / stop engine (stationary charging uses fuel)"
	engine.pressed.connect(func():
		if is_instance_valid(connected_rv):
			var okay: bool = connected_rv.set_engine_running(not connected_rv.energy.engine_running)
			message.text = ("引擎已發動" if connected_rv.energy.engine_running else "引擎已停止") if okay else connected_rv.engine_start_reason()
			_refresh())
	box.add_child(engine)
	var headlights := Button.new()
	headlights.text = "頭燈開關"
	headlights.pressed.connect(func():
		if is_instance_valid(connected_rv): connected_rv.headlights_requested = not connected_rv.headlights_requested)
	box.add_child(headlights)
	for kind in ["cabin", "work", "service"]:
		var light_button := Button.new()
		light_button.text = {"cabin": "車內照明開關", "work": "工作燈開關", "service": "維修燈開關（開蓋後照明）"}[kind]
		light_button.pressed.connect(func():
			if is_instance_valid(connected_rv): connected_rv.toggle_interior_light(kind))
		box.add_child(light_button)
	var brightness := Button.new()
	brightness.text = "調整儀表亮度：低 → 中 → 高"
	brightness.pressed.connect(func():
		if is_instance_valid(connected_rv): connected_rv.instrument_brightness = 0.2 if connected_rv.instrument_brightness > 0.9 else minf(1.0, connected_rv.instrument_brightness + 0.4))
	box.add_child(brightness)
	var vibration := Button.new()
	vibration.text = "引擎視覺震動：關 → 低 → 高"
	vibration.pressed.connect(func():
		if is_instance_valid(connected_rv): connected_rv.vibration_strength = fmod(connected_rv.vibration_strength + 0.5, 1.5))
	box.add_child(vibration)
	message = Label.new()
	box.add_child(message)
	structure_box = VBoxContainer.new()
	structure_box.name = "車體結構"
	structure_box.add_theme_constant_override("separation", 16)
	service_tabs.add_child(structure_box)
	var structure_title := Label.new()
	structure_title.text = "車體結構｜維修、重建與型態配置"
	structure_title.add_theme_color_override("font_color", IndustrialTheme.AMBER)
	structure_box.add_child(structure_title)
	structure_status = Label.new()
	structure_box.add_child(structure_status)
	_build_structure_rows()
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
	status_label.text += "\n" + VehicleStatus.messages(connected_rv)
	for kind in ["cabin", "work", "service"]: status_label.text += "\n" + connected_rv.interior_light_status(kind)
	status_label.text += "\n儀表亮度 %.0f%%｜視覺震動 %.0f%%" % [connected_rv.instrument_brightness * 100, connected_rv.vibration_strength * 100]
	var installed: EngineState = connected_rv.get_engine()
	status_label.text += "\n" + ("引擎槽為空" if installed == null else "%s｜耐久 %.0f / %.0f" % [installed.definition().display_name, installed.health, installed.definition().max_health])
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
	_refresh_structures()

func _construction() -> Node:
	if not is_instance_valid(connected_rv): return null
	var slots := connected_rv.get_node_or_null("StructureSlots")
	return slots.construction if slots and is_instance_valid(slots.get("construction")) else null

func _build_structure_rows() -> void:
	for slot in RVStructureSlots.layout():
		var row := VBoxContainer.new()
		structure_box.add_child(row)
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(label)
		var selector := OptionButton.new()
		for type in RVStructureSlots.types_for_slot(slot.id):
			var definition: Resource = RVStructureSlots.definition_for(type)
			selector.add_item(definition.display_name)
			selector.set_item_metadata(selector.item_count - 1, type)
		row.add_child(selector)
		selector.item_selected.connect(func(_index: int): _refresh_structures())
		structure_rows[slot.id] = {"label": label, "title": slot.label, "selector": selector}
		var actions := HFlowContainer.new()
		actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(actions)
		_add_structure_button(actions, row, slot.id, "repair", "維修")
		_add_structure_button(actions, row, slot.id, "rebuild", "重建選定型態")
		if RVStructureSlots.types_for_slot(slot.id).size() > 1:
			_add_structure_button(actions, row, slot.id, "convert", "變更選定型態")

func _selected_type(slot: String) -> String:
	var selector: OptionButton = structure_rows[slot].selector
	return str(selector.get_item_metadata(selector.selected))

func _add_structure_button(actions: Container, row: VBoxContainer, slot: String, operation: String, label: String) -> void:
	var button := Button.new()
	var explanation := Label.new()
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explanation.add_theme_font_size_override("font_size", 20)
	row.add_child(explanation)
	button.pressed.connect(func():
		var controller := _construction()
		if controller:
			var type := "" if operation == "repair" else _selected_type(slot)
			var reason: String = controller.begin(get_parent(), slot, operation, type)
			message.text = reason if not reason.is_empty() else "施工開始"
			_refresh_structures())
	actions.add_child(button)
	structure_buttons.append({"button": button, "reason": explanation, "slot": slot, "operation": operation, "label": label})

func _refresh_structures() -> void:
	var controller := _construction()
	if not controller: return
	structure_status.text = controller.status_message()
	var slots := connected_rv.get_node("StructureSlots")
	for slot in structure_rows:
		var target: Node = slots.panel(slot)
		if not is_instance_valid(target): continue
		var attached: PackedStringArray = target.dependent_names()
		structure_rows[slot].label.text = "%s｜%s｜HP %.0f / %.0f｜%s\n附掛設備：%s" % [structure_rows[slot].title, target.equipment_name,
			target.current_health, target.max_health, "已毀壞（空槽）" if target.is_destroyed else "完整" if target.current_health >= target.max_health else "受損",
			"無" if attached.is_empty() else ", ".join(attached)]
	for entry in structure_buttons:
		var target: Node = slots.panel(entry.slot)
		if not is_instance_valid(target):
			entry.button.disabled = true
			continue
		var type: String = str(target.definition.type_id) if entry.operation == "repair" else _selected_type(entry.slot)
		var definition: Resource = RVStructureSlots.definition_for(type)
		var reason: String = controller.rejection_reason(get_parent(), entry.slot, entry.operation, "" if entry.operation == "repair" else type)
		entry.button.text = "%s｜%d Metal Parts｜%.0f 秒" % [entry.label, controller.operation_cost(entry.operation, definition), controller.operation_seconds(entry.operation, definition)]
		entry.reason.text = entry.label + "：" + reason
		entry.reason.visible = not reason.is_empty()
		entry.button.tooltip_text = reason
		entry.button.disabled = not reason.is_empty()

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
		if device.has_method("step_work") or device.has_method("generate_power") or device is CabinLightStrip:
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
