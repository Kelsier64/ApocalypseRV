extends SceneTree

func _init():
	print("--- Generating Interactive Items ---")
	
	# Small Item: Scrap
	var scrap_root = RigidBody3D.new()
	scrap_root.name = "Scrap"
	# attach the interactable item script
	var script = load("res://scripts/interactable_item.gd")
	if script:
		scrap_root.set_script(script)
		scrap_root.set("item_name", "Scrap Metal")
		scrap_root.set("is_large", false)
	else:
		printerr("Could not load interactable_item.gd")

	var scrap_mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.3, 0.3, 0.3)
	scrap_mesh.mesh = box
	scrap_root.add_child(scrap_mesh)
	scrap_mesh.owner = scrap_root
	
	var scrap_col = CollisionShape3D.new()
	var col_box = BoxShape3D.new()
	col_box.size = Vector3(0.3, 0.3, 0.3)
	scrap_col.shape = col_box
	scrap_root.add_child(scrap_col)
	scrap_col.owner = scrap_root
	
	var packed_scrap = PackedScene.new()
	if packed_scrap.pack(scrap_root) == OK:
		ResourceSaver.save(packed_scrap, "res://scenes/scrap.tscn")
		print("-> Created: res://scenes/scrap.tscn")
	
	# Large Item: Oil Barrel
	var barrel_root = RigidBody3D.new()
	barrel_root.name = "OilBarrel"
	if script:
		barrel_root.set_script(script)
		barrel_root.set("item_name", "Oil Barrel")
		barrel_root.set("is_large", true)
		
	# Make the barrel heavier
	barrel_root.mass = 20.0 

	var barrel_mesh = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.height = 1.0
	cyl.top_radius = 0.4
	cyl.bottom_radius = 0.4
	barrel_mesh.mesh = cyl
	barrel_root.add_child(barrel_mesh)
	barrel_mesh.owner = barrel_root
	
	var barrel_col = CollisionShape3D.new()
	var col_cyl = CylinderShape3D.new()
	col_cyl.height = 1.0
	col_cyl.radius = 0.4
	barrel_col.shape = col_cyl
	barrel_root.add_child(barrel_col)
	barrel_col.owner = barrel_root
	
	var packed_barrel = PackedScene.new()
	if packed_barrel.pack(barrel_root) == OK:
		ResourceSaver.save(packed_barrel, "res://scenes/oil_barrel.tscn")
		print("-> Created: res://scenes/oil_barrel.tscn")

	print("--- Generation Complete ---")
	quit()
