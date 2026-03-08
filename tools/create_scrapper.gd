extends SceneTree

func _init():
	print("Building Scaled Red Scrapper Equipment (0.7x)...")
	
	var root = RigidBody3D.new()
	root.name = "Scrapper"
	root.mass = 80.0
	
	var script = load("res://scripts/scrapper.gd")
	root.set_script(script)
	root.set("equipment_name", "Recycling Scrapper")
	root.set("placement_offset", 0.0)
	
	# Visuals using CSG
	var outer = CSGBox3D.new()
	outer.name = "BasinVisual"
	outer.size = Vector3(1.05, 0.7, 1.05)
	outer.position = Vector3(0, 0.35, 0)
	# DO NOT use CSG collision for RigidBody, we will make explicit shapes
	outer.use_collision = false
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.2, 0.2) # Red
	outer.material_override = mat
	root.add_child(outer)
	outer.owner = root
	
	var inner = CSGBox3D.new()
	inner.name = "Hole"
	inner.size = Vector3(0.91, 0.63, 0.91)
	inner.position = Vector3(0, 0.07, 0)
	inner.operation = CSGShape3D.OPERATION_SUBTRACTION
	outer.add_child(inner)
	inner.owner = root
	
	# Explicit Collision Shapes for the RigidBody3D to avoid "no shape" error
	# 1. Floor
	var col_floor = CollisionShape3D.new()
	col_floor.name = "ColFloor"
	col_floor.position = Vector3(0, 0.035, 0)
	var shape_floor = BoxShape3D.new()
	shape_floor.size = Vector3(1.05, 0.07, 1.05)
	col_floor.shape = shape_floor
	root.add_child(col_floor)
	col_floor.owner = root
	
	# 2. Wall Front/Back
	var col_f = CollisionShape3D.new()
	col_f.name = "ColFront"
	col_f.position = Vector3(0, 0.385, 0.49)
	var shape_f = BoxShape3D.new()
	shape_f.size = Vector3(1.05, 0.63, 0.07)
	col_f.shape = shape_f
	root.add_child(col_f)
	col_f.owner = root
	
	var col_b = CollisionShape3D.new()
	col_b.name = "ColBack"
	col_b.position = Vector3(0, 0.385, -0.49)
	var shape_b = BoxShape3D.new()
	shape_b.size = Vector3(1.05, 0.63, 0.07)
	col_b.shape = shape_b
	root.add_child(col_b)
	col_b.owner = root
	
	# 3. Wall Left/Right
	var col_l = CollisionShape3D.new()
	col_l.name = "ColLeft"
	col_l.position = Vector3(0.49, 0.385, 0)
	var shape_l = BoxShape3D.new()
	shape_l.size = Vector3(0.07, 0.63, 0.91)
	col_l.shape = shape_l
	root.add_child(col_l)
	col_l.owner = root
	
	var col_r = CollisionShape3D.new()
	col_r.name = "ColRight"
	col_r.position = Vector3(-0.49, 0.385, 0)
	var shape_r = BoxShape3D.new()
	shape_r.size = Vector3(0.07, 0.63, 0.91)
	col_r.shape = shape_r
	root.add_child(col_r)
	col_r.owner = root
	
	# Hopper Area
	var hopper = Area3D.new()
	hopper.name = "HopperArea"
	hopper.position = Vector3(0, 0.14, 0)
	
	var h_shape = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	box_shape.size = Vector3(0.7, 0.14, 0.7)
	h_shape.shape = box_shape
	
	hopper.add_child(h_shape)
	root.add_child(hopper)
	
	hopper.owner = root
	h_shape.owner = root
	
	var pack = PackedScene.new()
	pack.pack(root)
	ResourceSaver.save(pack, "res://scenes/scrapper.tscn")
	root.queue_free()
	
	print("Scrapper saved successfully.")
	quit()
