extends CanvasLayer
var user: Node3D
var rv: Node3D
var title: Label
var rows: VBoxContainer
var feedback: Label
var _signature := ""
var _elapsed := 0.0

func _ready() -> void:
	layer = 30
	var screen := Control.new()
	add_child(screen)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.02, 0.03, 0.04, 0.92)
	screen.add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 60)
	screen.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	box.theme = IndustrialTheme.make(24)
	margin.add_child(box)
	title = Label.new()
	box.add_child(title)
	var help := Label.new()
	help.text = "Boxes on this RV share storage and need no power.\nStored batteries supply no power. Materials are tracked separately."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(help)
	var close_button := Button.new()
	close_button.text = "Close [Esc]"
	close_button.pressed.connect(close)
	box.add_child(close_button)
	feedback = Label.new()
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(feedback)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	UILayout.attach(self, screen)
	hide()

func open(player: Node3D, vehicle: Node3D) -> void:
	user = player
	player.grab_started.connect(close)
	rv = vehicle
	_signature = ""
	feedback.text = ""
	show()
	_refresh()

func close() -> void:
	hide()
	if is_instance_valid(user) and user.is_inside_tree(): user.exit_ui_mode()
	if is_instance_valid(user) and user.grab_started.is_connected(close): user.grab_started.disconnect(close)
	user = null
	rv = null

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not visible: return
	if not is_instance_valid(user) or user.is_player_dead or not is_instance_valid(rv) or get_parent().get_connected_rv() != rv or not get_parent().can_operate():
		close()
		return
	_elapsed += delta
	if _elapsed >= 0.2:
		_elapsed = 0.0
		_refresh()

func _refresh() -> void:
	title.text = "RV storage %d / %d  |  Inventory %d / %d" % [rv.stored_items.size(), rv.item_capacity, user.inventory.items.size(), PlayerInventory.MAX_SLOTS]
	var signature := str(rv.stored_items) + str(user.inventory.items) + str(user.usable_arms())
	if signature == _signature: return
	_signature = signature
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	var header := Label.new()
	header.text = "Inventory to RV"
	rows.add_child(header)
	for index in range(user.inventory.items.size()):
		_add_item_button(user.inventory.items[index], index, true)
	header = Label.new()
	header.text = "RV to inventory"
	rows.add_child(header)
	if rv.stored_items.is_empty():
		var empty := Label.new()
		empty.text = "RV storage is empty"
		rows.add_child(empty)
	for index in range(rv.stored_items.size()):
		_add_item_button(rv.stored_items[index], index, false)

func _add_item_button(item: Dictionary, index: int, deposit: bool) -> void:
	var button := Button.new()
	var detail := ""
	if item.state.has("battery"):
		detail = " | Charge %.1f / %.0f" % [item.state.battery.charge, item.state.battery.capacity]
	elif item.state.has("condition"):
		detail = " | Durability %.0f" % item.state.condition
	button.text = "%s %s%s" % ["Store" if deposit else "Take", item.name, detail]
	button.disabled = rv.stored_items.size() >= rv.item_capacity if deposit else user.inventory.items.size() >= PlayerInventory.MAX_SLOTS
	if not deposit and not user.can_use_hands(2 if item.is_large else 1):
		button.disabled = true
		button.text += " | Arms unavailable"
	# Bind a snapshot too: a stale button must never transfer a different item.
	var expected := item.duplicate(true)
	button.pressed.connect(func():
		if not is_instance_valid(user) or not is_instance_valid(rv) or not get_parent().can_operate(): return
		var source: Array = user.inventory.items if deposit else rv.stored_items
		if index >= source.size() or source[index] != expected:
			feedback.text = "Items changed. Select again."
		else:
			var okay: bool = rv.store_player_item(user, index) if deposit else rv.take_stored_item(user, index)
			feedback.text = ("Stored in RV" if deposit else "Moved to inventory") if okay else "Cannot transfer. Inventory or storage full, or already carrying a large item."
		_signature = ""
		_refresh())
	rows.add_child(button)
