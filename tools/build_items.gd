extends SceneTree

func _init():
	print("--- Generating Interactive Items ---")
	
	# Small Item: Scrap
	var scrap_root = RigidBody3D.new()
	scrap_root.name = "Scrap"
	# attach the interactable item script
	var script = load("res://props/interactable_item.gd")
	if script:
		scrap_root.set_script(script)
		scrap_root.set("item_name", "Scrap Metal")
		scrap_root.set("is_large", false)
		scrap_root.set("scrap_yields", {
			"Metal Parts": Vector2(2, 5)
		})
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
		ResourceSaver.save(packed_scrap, "res://props/scrap.tscn")
		print("-> Created: res://props/scrap.tscn")
	
	# Large Item: Oil Barrel
	var barrel_root = RigidBody3D.new()
	barrel_root.name = "OilBarrel"
	if script:
		barrel_root.set_script(script)
		barrel_root.set("item_name", "Oil Barrel")
		barrel_root.set("is_large", true)
		barrel_root.set("scrap_yields", {
			"Unrefined Fuel": Vector2(10, 20),
			"Metal Parts": Vector2(1, 4),
			"Electronic Scrap": Vector2(0, 1)
		})
		
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
		ResourceSaver.save(packed_barrel, "res://props/oil_barrel.tscn")
		print("-> Created: res://props/oil_barrel.tscn")
		
	# Medium Item: Gasoline Can
	var gas_can_root = RigidBody3D.new()
	gas_can_root.name = "GasolineCan"
	if script:
		gas_can_root.set_script(script)
		gas_can_root.set("item_name", "Gasoline Can")
		gas_can_root.set("is_large", false)
		gas_can_root.set("scrap_yields", {
			"Unrefined Fuel": Vector2(1, 3), # Just a little bit if you scrap it
			"Metal Parts": Vector2(0, 1)
		})
		
	gas_can_root.mass = 5.0

	var gas_mesh = MeshInstance3D.new()
	var gas_box = BoxMesh.new()
	gas_box.size = Vector3(0.2, 0.4, 0.3)
	gas_mesh.mesh = gas_box
	
	# Try to make it red
	var red_mat = StandardMaterial3D.new()
	red_mat.albedo_color = Color(0.8, 0.1, 0.1)
	gas_mesh.material_override = red_mat
	
	gas_can_root.add_child(gas_mesh)
	gas_mesh.owner = gas_can_root
	
	var gas_col = CollisionShape3D.new()
	var gas_col_box = BoxShape3D.new()
	gas_col_box.size = Vector3(0.2, 0.4, 0.3)
	gas_col.shape = gas_col_box
	gas_can_root.add_child(gas_col)
	gas_col.owner = gas_can_root
	
	var packed_gas = PackedScene.new()
	if packed_gas.pack(gas_can_root) == OK:
		ResourceSaver.save(packed_gas, "res://props/gas_can.tscn")
		print("-> Created: res://props/gas_can.tscn")

	print("--- Generation Complete ---")
	quit()
