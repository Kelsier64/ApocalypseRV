extends SceneTree

func _init():
	print("Building Tablet Screen & UI...")
	
	# --- 1. Create the UI Scene ---
	var ui_root = CanvasLayer.new()
	ui_root.name = "TabletUI"
	ui_root.set_script(load("res://scripts/tablet_ui.gd"))
	
	# Transparent background
	var bg = ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0, 0, 0, 0.4)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.add_child(bg)
	bg.owner = ui_root
	
	# Main Panel (centered and massive)
	var panel = PanelContainer.new()
	panel.name = "PanelContainer"
	# Lock to all 4 edges of the screen
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Add padding from the edges so it's ~90% of the screen
	panel.offset_left = 60
	panel.offset_top = 60
	panel.offset_right = -60
	panel.offset_bottom = -60 
	
	ui_root.add_child(panel)
	panel.owner = ui_root
	
	var margin = MarginContainer.new()
	margin.name = "MarginContainer"
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	panel.add_child(margin)
	margin.owner = ui_root
	
	var vbox = VBoxContainer.new()
	vbox.name = "VBoxContainer"
	margin.add_child(vbox)
	vbox.owner = ui_root
	
	var header = HBoxContainer.new()
	header.name = "Header"
	header.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(header)
	header.owner = ui_root
	
	var title = Label.new()
	title.name = "Title"
	title.text = "SMART TERMINAL OS v1.0"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(title)
	title.owner = ui_root
	
	var close_btn = Button.new()
	close_btn.name = "CloseButton"
	close_btn.text = " [ X ] "
	header.add_child(close_btn)
	close_btn.owner = ui_root
	
	var content = Label.new()
	content.name = "ContentLabel"
	content.text = "\n\nWelcome to the Smart Terminal.\n\nHere you will be able to control power, lighting, and cameras.\n\n(Systems Offline)"
	content.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(content)
	content.owner = ui_root
	
	var ui_pack = PackedScene.new()
	ui_pack.pack(ui_root)
	ResourceSaver.save(ui_pack, "res://scenes/tablet_ui.tscn")
	ui_root.queue_free()
	
	# --- 2. Create the Equipment Scene ---
	var equip_root = RigidBody3D.new()
	equip_root.name = "TabletScreen"
	equip_root.mass = 5.0
	equip_root.set_script(load("res://scripts/tablet_screen.gd"))
	equip_root.set("equipment_name", "Tablet Screen")
	equip_root.set("placement_offset", 0.025) # Pop out from wall slightly (half of Y thickness)
	
	var mesh = MeshInstance3D.new()
	mesh.name = "Mesh"
	
	var box = BoxMesh.new()
	box.size = Vector3(0.6, 0.05, 0.4) # Flat tablet shape, Y is the thickness axis
	mesh.mesh = box
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.1, 0.1) # Dark grey tablet
	mesh.material_override = mat
	
	equip_root.add_child(mesh)
	mesh.owner = equip_root
	
	var col = CollisionShape3D.new()
	col.name = "Collision"
	var col_shape = BoxShape3D.new()
	col_shape.size = box.size
	col.shape = col_shape
	equip_root.add_child(col)
	col.owner = equip_root
	
	var equip_pack = PackedScene.new()
	equip_pack.pack(equip_root)
	ResourceSaver.save(equip_pack, "res://scenes/tablet_screen.tscn")
	equip_root.queue_free()
	
	print("Tablet scenes saved successfully.")
	quit()
