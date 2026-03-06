extends CanvasLayer

var slots_container: HBoxContainer

func _ready():
	var control = Control.new()
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(control)
	
	slots_container = HBoxContainer.new()
	control.add_child(slots_container)
	
	# Anchor to the bottom center
	slots_container.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	
	# Box is 6 * 80px + some spacing (around 500px total). Let's make it 520px wide.
	# Left/Right offsets are relative to the center anchor (0).
	slots_container.offset_left = -260
	slots_container.offset_right = 260
	
	# Top/Bottom offsets are relative to the bottom anchor (0).
	slots_container.offset_top = -100
	slots_container.offset_bottom = -20
	
	slots_container.alignment = BoxContainer.ALIGNMENT_CENTER
	
	for i in range(6):
		var panel = ColorRect.new()
		panel.custom_minimum_size = Vector2(80, 80)
		panel.color = Color(0.1, 0.1, 0.1, 0.5)
		
		var label = Label.new()
		label.text = "Empty"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		panel.add_child(label)
		
		slots_container.add_child(panel)

func update_slots(inventory: Array, active_slot: int = 0):
	if not slots_container:
		return
		
	var children = slots_container.get_children()
	for i in range(children.size()):
		var slot_label = children[i].get_child(0) as Label
		
		# Base color
		var bg_color = Color(0.1, 0.1, 0.1, 0.5)
		
		# If item exists
		if i < inventory.size():
			var item = inventory[i]
			var prefix = "[L] " if item.get("is_large", false) else ""
			slot_label.text = prefix + item.get("name", "Item")
			bg_color = Color(0.8, 0.4, 0.4, 0.9) if item.get("is_large", false) else Color(0.2, 0.2, 0.2, 0.9)
		else:
			slot_label.text = "Empty"

		# Highlight active slot
		if i == active_slot:
			# Make it brighter and more opaque if it's the active slot
			bg_color = bg_color.lightened(0.5)
			bg_color.a = 1.0
			
		children[i].color = bg_color
