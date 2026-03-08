@tool
extends EditorScript

func _run():
	var player_scene = load("res://player/player.tscn")
	if not player_scene:
		printerr("Could not load res://player/player.tscn")
		return
		
	var root = player_scene.instantiate()
	
	# Check if UI already exists
	if root.has_node("InventoryUI"):
		print("InventoryUI already exists in player.tscn")
		root.free() # Free the instance if we aren't saving it
		return
		
	print("Adding InventoryUI to player...")
	
	# Create CanvasLayer
	var ui_layer = CanvasLayer.new()
	ui_layer.name = "InventoryUI"
	
	# Attach script
	var script = load("res://player/inventory_ui.gd")
	if script:
		ui_layer.set_script(script)
	
	root.add_child(ui_layer)
	ui_layer.owner = root
	
	var packed = PackedScene.new()
	if packed.pack(root) == OK:
		ResourceSaver.save(packed, "res://player/player.tscn")
		print("Successfully added InventoryUI to player.tscn!")
	else:
		printerr("Failed to pack scene")
		
	root.free()
