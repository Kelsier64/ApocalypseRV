extends SceneTree

func _init():
	var player_scene = load("res://scenes/player.tscn")
	var player = player_scene.instantiate()
	
	# Only add if it doesn't already exist
	if not player.has_node("InventoryUI"):
		var ui = CanvasLayer.new()
		ui.name = "InventoryUI"
		var script = load("res://scripts/inventory_ui.gd")
		ui.set_script(script)
		
		var control = Control.new()
		control.name = "Control"
		control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ui.add_child(control)
		control.owner = player
		
		# Move the container down
		var hbox = HBoxContainer.new()
		hbox.name = "HBoxContainer"
		hbox.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		# Needs to be anchored to bottom center
		hbox.position = Vector2(576 - (6*84)/2.0, 540) # Approximate center bottom positioning for default window (1152x648)
		control.add_child(hbox)
		hbox.owner = player
		
		for i in range(6):
			var panel = ColorRect.new()
			panel.name = "Slot_" + str(i)
			panel.custom_minimum_size = Vector2(80, 80)
			panel.color = Color(0.1, 0.1, 0.1, 0.5)
			
			var label = Label.new()
			label.name = "Label"
			label.text = "Empty"
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			panel.add_child(label)
			label.owner = player
			
			hbox.add_child(panel)
			panel.owner = player
			
		player.add_child(ui)
		ui.owner = player
		
		var packed = PackedScene.new()
		packed.pack(player)
		ResourceSaver.save(packed, "res://scenes/player.tscn")
		print("Added InventoryUI to player.tscn")
	else:
		print("InventoryUI already exists in player.tscn")

	quit()
