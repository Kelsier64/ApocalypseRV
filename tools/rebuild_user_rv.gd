extends SceneTree

func _init():
	print("--- Rebuilding RV with User Dimensions ---")
	_generate_rv_scene()
	print("--- Done ---")
	quit()

func _generate_rv_scene():
	var root = VehicleBody3D.new()
	root.name = "RV"
	root.mass = 2000.0
	
	var script = load("res://scripts/rv.gd")
	if script:
		root.set_script(script)
		
	# Dimensions
	var width = 3.0
	var length = 8.0
	var thick = 0.1
	var interior_height = 2.0
	
	var floor_y = 1.5
	var ceiling_y = floor_y + interior_height
	
	# Floor and Ceiling (Width x Thick x Length)
	_add_wall(root, "Floor", Vector3(width, thick, length), Vector3(0, floor_y, 0))
	_add_wall(root, "Ceiling", Vector3(width, thick, length), Vector3(0, ceiling_y, 0))
	
	# Side Walls (Thick x Height x Length)
	var side_x = (width / 2.0) - (thick / 2.0)  # 1.45
	var wall_y = floor_y + (interior_height / 2.0) # 2.5
	_add_wall(root, "WallLeft", Vector3(thick, interior_height, length), Vector3(side_x, wall_y, 0))
	_add_wall(root, "WallRight", Vector3(thick, interior_height, length), Vector3(-side_x, wall_y, 0))
	
	# Front and Back Walls (Width-2*Thick x Height x Thick)
	# To overlap corners nicely, we can just make front/back width = full width
	var front_z = (length / 2.0) - (thick / 2.0) # 3.95
	_add_wall(root, "WallFront", Vector3(width, interior_height, thick), Vector3(0, wall_y, front_z))
	_add_wall(root, "WallBack", Vector3(width, 1.0, thick), Vector3(0, floor_y + 0.5, -front_z)) # Low back wall for jumping in/out
	
	# Wheels
	# Wider wheel base (x), longer wheel base (z)
	var wheel_x = 1.6 # Protrude slightly from 1.5 half-width
	var wheel_z = 3.2 # 3.2 from center for 8m length
	_add_wheel(root, "Wheel_FL", Vector3(wheel_x, 0.0, wheel_z), true, false)
	_add_wheel(root, "Wheel_FR", Vector3(-wheel_x, 0.0, wheel_z), true, false)
	
	_add_wheel(root, "Wheel_RL", Vector3(wheel_x, 0.0, -wheel_z), false, true)
	_add_wheel(root, "Wheel_RR", Vector3(-wheel_x, 0.0, -wheel_z), false, true)
	
	# Add Driver Seat
	var seat_scene = load("res://scenes/driver_seat.tscn")
	if seat_scene:
		var seat = seat_scene.instantiate()
		seat.name = "DriverSeat"
		# Place front-left inside cabin
		seat.position = Vector3(side_x - 0.6, floor_y + thick/2.0, front_z - 1.0) 
		root.add_child(seat)
		seat.owner = root
	
	var packed_scene = PackedScene.new()
	if packed_scene.pack(root) == OK:
		ResourceSaver.save(packed_scene, "res://scenes/rv.tscn")
		print("-> Created: res://scenes/rv.tscn")
	else:
		printerr("Failed to pack RV scene")

func _add_wall(root: Node, node_name: String, size: Vector3, pos: Vector3):
	var col = CollisionShape3D.new()
	col.name = node_name + "Col"
	var shape = BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = pos
	root.add_child(col)
	col.owner = root
	
	var mesh_inst = MeshInstance3D.new()
	mesh_inst.name = node_name + "Mesh"
	var mesh = BoxMesh.new()
	mesh.size = size
	mesh_inst.mesh = mesh
	mesh_inst.position = pos
	root.add_child(mesh_inst)
	mesh_inst.owner = root

func _add_wheel(root: Node, node_name: String, pos: Vector3, is_steering: bool, is_traction: bool):
	var wheel = VehicleWheel3D.new()
	wheel.name = node_name
	wheel.position = pos
	wheel.use_as_steering = is_steering
	wheel.use_as_traction = is_traction
	wheel.wheel_radius = 0.5 
	wheel.suspension_travel = 0.5
	wheel.suspension_stiffness = 30.0
	wheel.suspension_max_force = 10000.0
	wheel.wheel_friction_slip = 10.5
	root.add_child(wheel)
	wheel.owner = root
	
	var mesh_inst = MeshInstance3D.new()
	mesh_inst.name = "WheelMesh"
	var mesh = CylinderMesh.new()
	mesh.top_radius = 0.5
	mesh.bottom_radius = 0.5
	mesh.height = 0.4 
	mesh_inst.mesh = mesh
	mesh_inst.rotation_degrees.x = 90
	mesh_inst.rotation_degrees.z = 90
	wheel.add_child(mesh_inst)
	mesh_inst.owner = root
